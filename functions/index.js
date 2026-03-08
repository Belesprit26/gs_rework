const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onValueWritten } = require("firebase-functions/v2/database");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

admin.initializeApp();

const FIREBASE_API_KEY = "AIzaSyD2m4T7ylElcXPbPS9YupoRFX2ebfjB7bI";

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

  try {
    const customToken = await admin.auth().createCustomToken(uid);

    const url =
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${FIREBASE_API_KEY}`;

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

/**
 * Sends a push notification to all of a user's registered devices.
 * Triggered by writes to the RTDB live node — called by the backend
 * when the ESP reports events that warrant user notification.
 *
 * Input: { uid: string, title: string, body: string, data?: object }
 */
exports.sendPushToUser = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const { uid, title, body, data } = request.data;
  const targetUid = uid || request.auth.uid;

  if (targetUid !== request.auth.uid) {
    throw new HttpsError("permission-denied", "Can only notify yourself");
  }

  const sent = await sendPushToAllTokens(targetUid, { title, body, data });
  return { sent };
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
  });

  console.log(`onDeviceEvent: uid=${uid} did=${did} type=${type} sent=${sent}`);
});

// ── FCM push: device offline scheduler ───────────────────────────
//
// Runs every 5 minutes.  For each user with registered FCM tokens,
// checks if the latest live/{did}/at timestamp is older than 5 min.
// Sends a single "device offline" push per staleness window and
// sets an offlineNotified flag to prevent repeat alerts.

exports.checkDeviceOffline = onSchedule("every 5 minutes", async (event) => {
  const db = admin.database();
  const firestore = admin.firestore();

  const usersSnap = await firestore.collection("fcm_tokens").get();
  if (usersSnap.empty) return;

  const now = Date.now();
  const THRESHOLD = 5 * 60 * 1000;

  for (const userDoc of usersSnap.docs) {
    const uid = userDoc.id;

    const liveSnap = await db.ref(`gs/${uid}/live`).once("value");
    const live = liveSnap.val();
    if (!live) continue;

    const metaSnap = await db.ref(`gs/${uid}/meta/offlineNotified`).once("value");
    const alreadyNotified = metaSnap.val() === true;

    for (const did of Object.keys(live)) {
      const lastSeen = live[did]?.at;
      if (!lastSeen) continue;

      const isOffline = (now - lastSeen) > THRESHOLD;

      if (isOffline && !alreadyNotified) {
        const ago = Math.round((now - lastSeen) / 60000);
        await sendPushToAllTokens(uid, {
          title: "Device offline",
          body: `Your geyser hasn't reported in ${ago} minutes`,
          data: { type: "device_offline", deviceId: did },
        });
        await db.ref(`gs/${uid}/meta/offlineNotified`).set(true);
        console.log(`checkDeviceOffline: uid=${uid} did=${did} offline ${ago}m`);
      } else if (!isOffline && alreadyNotified) {
        await sendPushToAllTokens(uid, {
          title: "Device back online",
          body: "Your geyser is reporting again",
          data: { type: "device_online", deviceId: did },
        });
        await db.ref(`gs/${uid}/meta/offlineNotified`).remove();
        console.log(`checkDeviceOffline: uid=${uid} did=${did} back online`);
      }
    }
  }
});

// ── Shared FCM send helper ───────────────────────────────────────

async function sendPushToAllTokens(uid, { title, body, data }) {
  const firestore = admin.firestore();
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
        channelId: "geyser_alerts",
        priority: "high",
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
// The legacy GeyserSwitch_Orange app calls httpsCallable('sendNotification')
// with { tokens, title, body, data }.  This function must remain deployed
// as long as that app version is in the field.

exports.sendNotification = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const { tokens, title, body, data } = request.data;
  if (!tokens || !Array.isArray(tokens) || !title || !body) {
    throw new HttpsError("invalid-argument", "tokens, title, and body required");
  }

  console.log(`sendNotification: uid=${request.auth.uid}, tokens=${tokens.length}, title="${title}"`);

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
      invalidTokens.push(tokens[i]);
    }
  });

  console.log(`sendNotification: sent=${response.successCount}, failed=${response.failureCount}, invalid=${invalidTokens.length}`);

  return { success: true, invalidTokens };
});

/**
 * HTTP endpoint for the ESP32 to send push notifications directly.
 * Authenticates via a shared authKey (not Firebase Auth).
 */
exports.sendNotificationFromESP32 = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).send("Method Not Allowed");
  }

  const { title, body, data, userId, authKey } = req.body;

  if (authKey !== "geyserswitch-bloc-orange") {
    console.warn("sendNotificationFromESP32: invalid authKey");
    return res.status(400).send("Invalid authKey");
  }

  if (!title || !body || !userId) {
    console.warn("sendNotificationFromESP32: missing fields", req.body);
    return res.status(400).send("Missing required fields");
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
        if (data.hasOwnProperty(key)) {
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
});
