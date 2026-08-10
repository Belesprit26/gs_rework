const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onValueWritten } = require("firebase-functions/v2/database");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");

admin.initializeApp();

// NOTE: the name must NOT start with FIREBASE_ / X_GOOGLE_ / EXT_ —
// those prefixes are reserved, and a .env containing one makes the
// whole `firebase deploy --only functions` fail to load the file.
// This is the Identity Toolkit (Firebase Web) API key: a public client
// identifier, the same value shipped in the app, not a secret.
const IDENTITY_TOOLKIT_API_KEY = process.env.IDENTITY_TOOLKIT_API_KEY;

const ESP_AUTH_KEY = defineSecret("ESP_AUTH_KEY");

/**
 * Creates a Firebase custom token for the calling user, exchanges it
 * for an ID token + refresh token via the Identity Toolkit REST API,
 * and returns the refresh token.
 *
 * The mobile app calls this during provisioning, then passes the
 * refresh token to the ESP32 via BLE.  The ESP uses the refresh
 * token for ongoing RTDB authentication.
 */
exports.createDeviceToken = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const uid = request.auth.uid;

  if (!IDENTITY_TOOLKIT_API_KEY) {
    // Fail loudly and specifically: without this, the exchange below
    // returns a confusing 400 and provisioning appears to fail for
    // reasons unrelated to the actual misconfiguration.
    console.error("IDENTITY_TOOLKIT_API_KEY is not set — check functions/.env");
    throw new HttpsError("failed-precondition", "Server not configured");
  }

  try {
    const customToken = await admin.auth().createCustomToken(uid);

    const url =
      "https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken" +
      `?key=${IDENTITY_TOOLKIT_API_KEY}`;

    const resp = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        token: customToken,
        returnSecureToken: true,
      }),
    });

    if (!resp.ok) {
      const errBody = await resp.text();
      console.error("Token exchange failed:", resp.status, errBody);
      throw new HttpsError("internal", "Token exchange failed");
    }

    const data = await resp.json();

    return { refreshToken: data.refreshToken };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    console.error("createDeviceToken error:", err);
    throw new HttpsError("internal", `Failed: ${err.message}`);
  }
});

/**
 * Registers an FCM token for the calling user.
 * Stored in Firestore (not RTDB) for security — the ESP never sees these.
 *
 * Input: { token: string, platform: string }
 */
exports.registerFcmToken = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const { token, platform } = request.data;
  if (!token || !platform) {
    throw new HttpsError("invalid-argument", "token and platform required");
  }

  const uid = request.auth.uid;
  const db = admin.firestore();

  await db
    .collection("fcm_tokens")
    .doc(uid)
    .collection("tokens")
    .doc(tokenHash(token))
    .set(
      {
        token,
        platform,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        valid: true,
      },
      { merge: true }
    );

  return { ok: true };
});

function tokenHash(token) {
  const crypto = require("crypto");
  return crypto.createHash("sha256").update(token).digest("hex").slice(0, 16);
}

// ── FCM push: device event trigger ───────────────────────────────
//
// When the ESP writes to gs/{uid}/events/{did}, this function fires
// and sends a push notification to all registered FCM tokens.

const EVENT_LABELS = {
  1: {
    title: "Geyser turned off",
    body: (t) => `Reached ${t}°C (max limit)`,
  },
  2: {
    title: "Auto-reheat activated",
    body: (t) => `Temp dropped to ${t}°C — geyser turned on`,
  },
  3: {
    title: "Low temperature alert",
    body: (t) => `Temp dropped to ${t}°C — auto-reheat is off`,
  },
  4: {
    title: "Sensor offline",
    body: () => "Temperature sensor is not responding — geyser runs normally",
  },
  5: {
    title: "Sensor recovered",
    body: (t) => `Temperature sensor is back online (${t}°C)`,
  },
  6: {
    title: "Max run time reached",
    body: () => "Geyser turned off — maximum run time reached",
  },
  // Must stay in step with the Dart copy in device_notification.dart —
  // the same event arrives by either path (BLE or FCM).
  7: {
    title: "Schedule paused",
    body: () =>
      "Device clock not set — heating on a backup timer until it reconnects",
  },
  8: {
    title: "Schedule resumed",
    body: () =>
      "Device clock is set again — your schedule is running normally",
  },
  // Water leak — safety-critical. Routed to a dedicated max-importance
  // channel so it lands loud with the app closed. Non-silenceable in-app.
  9: {
    title: "Water leak detected",
    body: () =>
      "GeyserSwitch cut the power. Check your geyser and water supply.",
    channelId: "geyser_leak_alerts",
    priority: "max",
  },
  10: {
    title: "Leak cleared",
    body: () => "The water-leak sensor is dry again",
  },
};

exports.onDeviceEvent = onValueWritten("gs/{uid}/events/{did}", async (event) => {
  const after = event.data.after.val();
  if (!after) return;

  const before = event.data.before.val();
  if (before && before.at === after.at) return;

  const uid = event.params.uid;
  const did = event.params.did;
  const { type, temp } = after;

  const label = EVENT_LABELS[type];
  if (!label) {
    console.warn(`onDeviceEvent: unknown type ${type} for ${uid}/${did}`);
    return;
  }

  const sent = await sendPushToAllTokens(uid, {
    title: label.title,
    body: label.body(temp),
    data: { type: String(type), temp: String(temp), deviceId: did },
    channelId: label.channelId,
    priority: label.priority,
  });

  console.log(`onDeviceEvent: uid=${uid} did=${did} type=${type} sent=${sent}`);
});

// ── FCM push: device offline scheduler ───────────────────────────
//
// Runs every 2 minutes.
//
// Cost strategy:
//   • Firestore listDocuments() to get user IDs — zero doc reads.
//   • Per user: 2 targeted RTDB reads (live + offlineNotified only).
//     Does NOT download stats/settings/events.
//   • sendPushToAllTokens (the expensive Firestore subcollection
//     read) fires ONLY on state transitions.
//   • All users processed in parallel.

exports.checkDeviceOffline = onSchedule("every 2 minutes", async (event) => {
  const db = admin.database();
  const firestore = admin.firestore();
  const now = Date.now();
  const THRESHOLD = 2.5 * 60 * 1000;

  const userRefs = await firestore.collection("fcm_tokens").listDocuments();
  if (userRefs.length === 0) return;

  await Promise.all(userRefs.map(async (ref) => {
    const uid = ref.id;

    const [liveSnap, flagsSnap] = await Promise.all([
      db.ref(`gs/${uid}/live`).once("value"),
      db.ref(`gs/${uid}/meta/offlineNotified`).once("value"),
    ]);

    const live = liveSnap.val();
    if (!live) return;

    const flags = flagsSnap.val() || {};
    const transitions = [];

    for (const did of Object.keys(live)) {
      const lastSeen = live[did]?.at;
      if (!lastSeen) continue;

      const isOffline = (now - lastSeen) > THRESHOLD;
      const alreadyNotified = flags[did] === true;

      if (isOffline && !alreadyNotified) {
        const ago = Math.round((now - lastSeen) / 60000);
        transitions.push(
          sendPushToAllTokens(uid, {
            title: "Device offline",
            body: `Your geyser hasn't reported in ${ago} minutes`,
            data: { type: "device_offline", deviceId: did },
          }).then(() => {
            db.ref(`gs/${uid}/meta/offlineNotified/${did}`).set(true);
            console.log(`checkDeviceOffline: uid=${uid} did=${did} offline ${ago}m`);
          })
        );
      } else if (!isOffline && alreadyNotified) {
        transitions.push(
          sendPushToAllTokens(uid, {
            title: "Device back online",
            body: "Your geyser is reporting again",
            data: { type: "device_online", deviceId: did },
          }).then(() => {
            db.ref(`gs/${uid}/meta/offlineNotified/${did}`).remove();
            console.log(`checkDeviceOffline: uid=${uid} did=${did} back online`);
          })
        );
      }
    }

    if (transitions.length > 0) {
      await Promise.all(transitions);
    }
  }));
});

// ── Shared FCM send helper ───────────────────────────────────────

async function sendPushToAllTokens(uid, { title, body, data, channelId, priority }) {
  const firestore = admin.firestore();
  // Per-event overrides fall back to the standard alert channel, so every
  // existing caller (offline scheduler, temp events) is unchanged.
  const androidChannelId = channelId || "geyser_alerts";
  const androidPriority = priority || "high";
  const tokensSnap = await firestore
    .collection("fcm_tokens").doc(uid)
    .collection("tokens").where("valid", "==", true)
    .get();

  if (tokensSnap.empty) return 0;

  const tokens = tokensSnap.docs.map((d) => d.data().token);

  const dataPayload = {};
  if (data) {
    for (const k of Object.keys(data)) {
      dataPayload[k] = String(data[k]);
    }
  }

  const messages = tokens.map((tk) => ({
    token: tk,
    notification: { title, body },
    data: dataPayload,
    android: {
      notification: {
        channelId: androidChannelId,
        priority: androidPriority,
      },
    },
    apns: {
      headers: { "apns-priority": "10" },
      payload: {
        aps: { alert: { title, body }, sound: "default" },
      },
    },
  }));

  const response = await admin.messaging().sendEach(messages);

  // Prune invalid tokens.
  const invalid = [];
  response.responses.forEach((r, i) => {
    if (
      r.error &&
      (r.error.code === "messaging/invalid-registration-token" ||
        r.error.code === "messaging/registration-token-not-registered")
    ) {
      invalid.push(tokens[i]);
    }
  });

  if (invalid.length > 0) {
    const batch = firestore.batch();
    for (const tk of invalid) {
      const docs = await firestore
        .collection("fcm_tokens").doc(uid)
        .collection("tokens").where("token", "==", tk)
        .get();
      docs.forEach((d) => batch.delete(d.ref));
    }
    await batch.commit();
  }

  return response.successCount;
}

// ── GeyserSwitch_Orange compatibility ────────────────────────────
//
// @deprecated — Legacy GeyserSwitch_Orange calls this.
// Keep deployed until all legacy app installs are replaced.
// Usage is tracked in Cloud Functions logs for monitoring.

exports.sendNotification = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const uid = request.auth.uid;
  const { tokens, title, body, data } = request.data;
  if (!tokens || !Array.isArray(tokens) || !title || !body) {
    throw new HttpsError("invalid-argument", "tokens, title, and body required");
  }

  console.warn(`[DEPRECATED] sendNotification called by uid=${uid}, tokens=${tokens.length}`);

  // Server-side token ownership: only send to tokens that belong
  // to this user (Firestore fcm_tokens/{uid}/tokens).
  const firestore = admin.firestore();
  const ownedSnap = await firestore
    .collection("fcm_tokens").doc(uid)
    .collection("tokens").where("valid", "==", true)
    .get();

  const ownedTokens = new Set(ownedSnap.docs.map((d) => d.data().token));
  const filtered = tokens.filter((t) => ownedTokens.has(t));

  if (filtered.length === 0) {
    console.warn(`sendNotification: uid=${uid} has no owned tokens among ${tokens.length} submitted`);
    return { success: true, invalidTokens: [] };
  }

  const dataPayload = {};
  if (data) {
    for (const k of Object.keys(data)) {
      dataPayload[k] = String(data[k]);
    }
  }

  const messages = filtered.map((tk) => ({
    token: tk,
    notification: { title, body },
    data: dataPayload,
    android: {
      notification: {
        channelId: "high_importance_channel",
        priority: "high",
      },
    },
    apns: {
      headers: { "apns-priority": "10" },
      payload: { aps: { alert: { title, body }, sound: "default", badge: 1 } },
    },
  }));

  const response = await admin.messaging().sendEach(messages);

  const invalidTokens = [];
  response.responses.forEach((r, i) => {
    if (
      r.error &&
      (r.error.code === "messaging/invalid-registration-token" ||
        r.error.code === "messaging/registration-token-not-registered")
    ) {
      invalidTokens.push(filtered[i]);
    }
  });

  console.log(`sendNotification: sent=${response.successCount}, failed=${response.failureCount}, invalid=${invalidTokens.length}`);

  return { success: true, invalidTokens };
});

/**
 * HTTP endpoint for the ESP32 to send push notifications directly.
 *
 * Security layers:
 *   1. Shared secret read from Firebase Secret Manager (ESP_AUTH_KEY).
 *      No fallback — requests without the exact secret are rejected.
 *   2. userId must correspond to a real Firebase Auth account.
 *   3. Per-userId rate limit (max 10 requests / minute, in-memory).
 */

const _espRateMap = new Map();
const ESP_RATE_WINDOW_MS = 60_000;
const ESP_RATE_MAX = 10;

function espRateOk(uid) {
  const now = Date.now();
  let bucket = _espRateMap.get(uid);
  if (!bucket || now - bucket.windowStart > ESP_RATE_WINDOW_MS) {
    bucket = { windowStart: now, count: 0 };
    _espRateMap.set(uid, bucket);
  }
  bucket.count++;
  return bucket.count <= ESP_RATE_MAX;
}

exports.sendNotificationFromESP32 = onRequest(
  { secrets: [ESP_AUTH_KEY] },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).send("Method Not Allowed");
    }

    const { title, body, data, userId, authKey } = req.body;

    // --- Layer 1: shared-secret check ---
    const expectedKey = ESP_AUTH_KEY.value();
    if (!expectedKey || authKey !== expectedKey) {
      console.warn("sendNotificationFromESP32: invalid authKey");
      return res.status(403).send("Forbidden");
    }

    if (!title || !body || !userId) {
      console.warn("sendNotificationFromESP32: missing fields", req.body);
      return res.status(400).send("Missing required fields");
    }

    // --- Layer 2: userId must be a real Firebase Auth user ---
    try {
      await admin.auth().getUser(userId);
    } catch (e) {
      console.warn(`sendNotificationFromESP32: unknown userId ${userId}`);
      return res.status(403).send("Forbidden");
    }

    // --- Layer 3: per-user rate limit ---
    if (!espRateOk(userId)) {
      console.warn(`sendNotificationFromESP32: rate limit hit for ${userId}`);
      return res.status(429).send("Too Many Requests");
    }

    console.log(`sendNotificationFromESP32: userId=${userId}, title="${title}"`);

    try {
      const tokensSnapshot = await admin
        .database()
        .ref(`/GeyserSwitch/${userId}/ServiceInfo/notificationTokens`)
        .once("value");
      const tokens = tokensSnapshot.val();

      if (!tokens) {
        console.log("sendNotificationFromESP32: no tokens for user", userId);
        return res.status(400).send("No tokens found for userId");
      }

      const deviceTokens = Object.keys(tokens);
      console.log(`sendNotificationFromESP32: ${deviceTokens.length} tokens`);

      const dataPayload = {};
      if (data) {
        for (const key in data) {
          if (Object.prototype.hasOwnProperty.call(data, key)) {
            dataPayload[key] = String(data[key]);
          }
        }
      }

      const messages = deviceTokens.map((token) => ({
        token,
        notification: { title, body },
        data: dataPayload,
        android: {
          notification: {
            channel_id: "high_importance_channel",
            priority: "high",
          },
        },
        apns: {
          headers: { "apns-priority": "10" },
          payload: {
            aps: { alert: { title, body }, sound: "default", badge: 1 },
          },
        },
      }));

      const response = await admin.messaging().sendEach(messages);
      console.log(`sendNotificationFromESP32: sent=${response.successCount}, failed=${response.failureCount}`);

      const tokensToRemove = [];
      response.responses.forEach((result, index) => {
        if (result.error) {
          const code = result.error.code;
          if (
            code === "messaging/invalid-registration-token" ||
            code === "messaging/registration-token-not-registered"
          ) {
            tokensToRemove.push(deviceTokens[index]);
          }
        }
      });

      if (tokensToRemove.length > 0) {
        const removePromises = tokensToRemove.map((token) =>
          admin
            .database()
            .ref(
              `/GeyserSwitch/${userId}/ServiceInfo/notificationTokens/${token}`
            )
            .remove()
        );
        await Promise.all(removePromises);
        console.log(`sendNotificationFromESP32: removed ${tokensToRemove.length} invalid tokens`);
      }

      res.status(200).send("Notification sent successfully");
    } catch (error) {
      console.error("sendNotificationFromESP32 error:", error);
      res.status(500).send(`Internal Server Error: ${error.message}`);
    }
  }
);
