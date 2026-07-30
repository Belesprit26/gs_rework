# MVP Stabilization & Release Plan

**Scope:** `gs_rework` (Flutter app) + `gs_firmware` (ESP32-C6, ESP-IDF)
**Goal:** a stable field MVP that can be updated remotely on both sides — firmware via the existing RTDB-manifest OTA, app via Play/App Store staged rollout — with no breaking changes to the app↔firmware BLE contract or the cloud data model.
**Source:** full-code audit (2026-07-30) of both repos: firmware safety logic, firmware connectivity, app↔firmware protocol contract, app data/Firebase layer, and release tooling.

---

## 1. Verdict & principles

The codebase is structurally sound: the BLE protocol contract is byte-verified on both sides (UUIDs, endianness, clamps, HMAC owner-auth with a shared RFC 4231 test vector), sync is crash-safe by construction, Firebase rules are deny-by-default and uid-scoped, TLS is enforced everywhere, and OTA uses true A/B partitions. What blocks release is a short list of high-impact defects, most with small fixes.

Every fix in this plan obeys three rules:

1. **Non-breaking protocol.** No change alters a GATT UUID, payload byte layout, status enum, RTDB schema, or NDJSON chunk format. Old app ↔ new firmware and new app ↔ old firmware must keep working during the rollout window.
2. **Remote-updatable from day one.** Firmware ships only after OTA rollback is proven working (flash a deliberately-crashing image; watch it revert). The app ships with Crashlytics symbol upload and staged rollout so a bad release is caught at 10%, not 100%.
3. **Fail safe, fail visible.** Where the device must degrade, it degrades toward relay-OFF and toward an event/log a human can see.

---

## 2. Blockers (release gates — none are optional)

### B1 — Task watchdog does not protect the control loop
- **Where:** firmware — no `esp_task_wdt_add()` anywhere in `main/`; `CONFIG_ESP_TASK_WDT_PANIC` unset (`sdkconfig:1264`).
- **Failure:** `temperature_task` is the only task that ever turns the relay OFF (thermostat cutoff `temperature.c:231`, max-on backstop `temperature.c:306-335`). If it hangs in the OneWire/RMT driver, the relay stays ON indefinitely and every software cutoff is dead.
- **Fix:**
  1. `sdkconfig.defaults`: add `CONFIG_ESP_TASK_WDT_PANIC=y` (keep 30 s timeout).
  2. Subscribe `temperature_task`, `scheduler_task`, and `button_task` with `esp_task_wdt_add(NULL)` at task start; call `esp_task_wdt_reset()` once per loop iteration.
  3. Panic → reboot → relay GPIO is low (OFF) through boot until NVS state restore — the safe direction.
- **Non-breaking:** firmware-internal. **Verify:** add a debug-only test hook that blocks the temp task; confirm reboot within 30 s.

### B2 — Scheduler timer fires once, then never again (single-timer config)
- **Where:** `scheduler.c:20-21, 38, 53-54` — `last_fired_hh/mm` guard has no day component and is never cleared.
- **Failure:** with exactly one enabled timer (the most common setup), it fires on day 1 and never again until reboot. Silent feature death → support calls.
- **Fix:** clear `last_fired` when the current minute moves past it, or add `last_fired_day` (yday) to the guard. ~2 lines.
- **Non-breaking:** firmware-internal. **Verify:** unit-style host test or accelerated clock test: one timer, two simulated days, two firings.

### B3 — Shipped builds silently lack OTA rollback (stale `sdkconfig`)
- **Where:** `gs_firmware/sdkconfig:427` — `BOOTLOADER_APP_ROLLBACK_ENABLE` not set; `sdkconfig.defaults:34` says `=y` but the checked-in `sdkconfig` predates it and wins. `ota.c:233-246` (`confirm_running_image`) is currently a no-op.
- **Failure:** a runtime-broken OTA boot-loops every fleet device; recovery is a physical reflash. This defeats the entire "update remotely" goal.
- **Fix:** `idf.py fullclean` + delete `sdkconfig`, regenerate from defaults; confirm `CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE=y` in `build/config/sdkconfig.h`. Add the CI gate from §6 so this cannot regress.
- **Verify (mandatory before first field OTA):** flash a test image that crashes after boot; confirm the bootloader reverts to the previous slot. Also verify the happy path: image runs 3 min → `confirm_running_image` marks it valid.

### B4 — WiFi provisioning fails on refresh-token length (BLE write > MTU)
- **Where:** app — `ble_provisioning_repository.dart:82-91` writes `refreshToken\0deviceId` (~280–340 B) in one write; `flutter_blue_plus_ble_repository.dart:171-174` has no `allowLongWrite`. Cap is MTU−3: ~253 B Android, ~182 B iOS.
- **Failure:** provisioning throws at the auth-data step → "Setup Failed", device never gets cloud credentials, remote mode dead. Fails for essentially all iOS users and any Android user with a token > ~244 chars.
- **Fix:** pass `allowLongWrite: true` for this characteristic write (add an optional flag to the repository `write` method). Firmware already reassembles prepared writes (`wifi_prov.c` reads full `OS_MBUF_PKTLEN`, `AUTH_REFRESH_MAX` 512).
- **Non-breaking:** long-write is standard ATT; old firmware already accepts it. **Verify:** provision on a real iPhone with a real Firebase token.

### B5 — iOS background sync never runs (workmanager never registered + name mismatch)
- **Where:** app — `ios/Runner/AppDelegate.swift` never calls `WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "com.geyserswitch.dailySync", ...)`; `workmanager_config.dart:71` compares the iOS-delivered identifier against the Android task name and bails.
- **Failure:** zero telemetry ever reaches the cloud from iOS; records never marked synced; the 60-day prune (which lives only in the workmanager callback) never runs → unbounded local DB growth (~1,440 rows/day).
- **Fix:**
  1. Add the `registerPeriodicTask` call in `AppDelegate.swift` (`didFinishLaunchingWithOptions`).
  2. In the dispatcher, accept both `kDailySyncTaskName` and the iOS identifier.
  3. Add a foreground fallback: on app resume, if `lastSync > 24 h`, trigger sync + prune inline (BGAppRefreshTask is best-effort on iOS regardless).
- **Non-breaking:** app-internal. **Verify:** trigger via Xcode `BGTaskScheduler` debug command; confirm chunks land in Storage and prune runs.

### B6 — ~~Release keystore + passwords committed to git~~ **FALSE POSITIVE (verified)**
- Re-verification against git: `git ls-files` does not list the keystore or `key.properties`, and `git log --all` shows neither was committed in **any** revision. Both are properly gitignored and exist only on the local disk. **No key rotation or history purge is needed.**
- Retained hardening (done): release builds now **fail** when `key.properties` is absent instead of silently falling back to debug signing, and versionCode/Name now come from pubspec (bumped to 1.0.13+13, above the already-published versionCode 12).

---

## 3. Major fixes (before launch, or first patch immediately after)

### 3.1 Safety-adjacent (firmware)

| ID | Issue | Fix |
|----|-------|-----|
| S1 | Relay state/GPIO set non-atomically from 5 tasks (`temperature.c`, `scheduler.c`, `button.c`, `gatt_server.c`, `firebase_rtdb.c`); a race can leave GPIO=ON with state=OFF → thermostat cutoff blind | Drive the GPIO inside `device_state_set_relay()` under the existing mutex; plus one reconciliation line in the temp task each 10 s cycle: `relay_set(device_state_get_relay())` — self-healing |
| S2 | `max_on_minutes` unclamped everywhere (0 = backstop disabled; contrast temp limits, clamped at every path) | Clamp at the same choke point as temp limits (`device_state.c`): range 30–360, reject 0. RTDB `.validate` already range-checks — mirror the same range |
| S3 | On confirmed sensor failure the relay stays ON up to 4 h (max-on default) | Policy decision: force relay OFF on `EVT_SENSOR_FAIL` (recommended for MVP — cold water is a complaint, scalding is a liability), or a short sensor-fail ceiling (e.g. 30 min) |
| S4 | Max-on accumulator resets every reboot (RAM-only) — a crash-looping device with relay persisted ON gets a fresh 4 h per boot | If reboot was not clean (`esp_reset_reason() != POWERON/SW`) and relay restores ON, start with a reduced first window |
| S5 | SNTP starts only if router is up within 15 s of boot (`wifi_prov.c:294`); after an outage the clock stays 1970 → all timers silently dead, stats keyed to 1970 | Call `time_sync_start_sntp()` from the `IP_EVENT_STA_GOT_IP` handler. One line |
| S6 | App phone-time push races owner unlock; rejection silently swallowed → BLE-only device can run preset timers on a bogus clock | Sequence: push time immediately after unlock succeeds (`BleConnectionCubit` exposes unlock completion; `GeyserControlCubit` retries the push on it) |

### 3.2 User-visible breakage (app)

| ID | Issue | Fix |
|----|-------|-----|
| U1 | Provisioning infinite spinner: 30 s timeout cancelled by first *non-terminal* status (`provisioning_cubit.dart:173-180`); BLE drop mid-WiFi-join hangs the sheet | Re-arm the timeout on non-terminal statuses; listen to `connectionStatus` and fail fast to a retry screen on disconnect |
| U2 | Re-provision rotates the owner key every time → all other household phones locked out permanently; `BleOwnerAuth.unlock()` never invalidates its cached key | (a) Only generate a new key when none exists in Firestore; reuse otherwise. (b) On `locked`: drop cache, re-fetch from Firestore, retry once |
| U3 | Sign-out doesn't wipe local data: Drift rows sync into the next user's cloud; FCM token keeps delivering previous owner's alerts | On sign-out: `TelemetryRepository.deleteAll()`, `NotificationRepository.deleteAll()`, `FirebaseMessaging.deleteToken()` + remove from `fcm_tokens/{uid}` via the existing callable |
| U4 | Sign-out is stop-forever: re-login in-session leaves telemetry/notifications/remote-sync dead until app restart (`NotificationService.stop()` closes its controller) | Make `stop()` reversible (don't close the broadcast controller); restart recorder/services on auth-state → signed-in |
| U5 | ESP offline event backlog acked (wiped) even when reads/inserts failed (`notification_service.dart:120-142`) | Track per-buffer success; only write the ack characteristic when both read **and** insert succeeded |
| U6 | Remote relay toggle hangs forever offline — the RTDB `update` itself has no timeout (`firebase_rtdb_repository.dart:87`) | Wrap the `update` in the same 10 s timeout; on timeout revert optimistic UI and clear `isBusy` |
| U7 | Scan failures hang UI: un-awaited `startScan` throw is unhandled; broadcast stream never fires `onDone` | `await startScan` in try/catch → `scanError` state; drive scan-end from `FlutterBluePlus.isScanning` |
| U8 | Owner-gated reads run before unlock → SSID never displays; retry wrapper burns 1.2 s on deterministic auth failures | Run `_runOwnerUnlock` right after device-ID resolution, before gated reads; exclude owner-auth writes from the generic `_withRetry` (nonce is consumed per attempt) |
| U9 | iOS + BLE-only device: second iPhone derives a different device ID (CoreBluetooth UUID is per-phone) → `noKey` lockout + split identity | Firmware: persist the app-supplied RTDB device ID for BLE-only provisioning too (add to bind payload — additive, old apps unaffected); app: prefer the 0x0C read over MAC derivation whenever non-empty |

### 3.3 Security / cloud / ops

| ID | Issue | Fix |
|----|-------|-----|
| C1 | Legacy `Orange` RTDB node readable/writable by ANY signed-in user (`database.rules.json:8-11`) — cross-tenant hole redeployed from this repo | Scope to uid or freeze (`.write: false`) after confirming legacy-app requirements; add `.validate` |
| C2 | BLE legacy pairing enabled (`CONFIG_BT_NIMBLE_SM_LEGACY=y`) — provisioning-window secrets sniffable | Set SC-only (disable SM_LEGACY). Just Works MITM residual risk documented in threat model |
| C3 | Firebase loop: 3 s flat retry forever (~29 k TLS handshakes/day in an outage); 401/`auth_revoked` never triggers re-auth; revoked refresh token → blocking retry every 3–5 s forever | Exponential backoff 3 s → 5 min on both SSE loop and auth refresh; on SSE 401 or `auth_revoked`, force token refresh; after N refresh failures enter dormant "auth dead" state, retry hourly |
| C4 | `/firmware` RTDB manifest is the sole OTA trust root; unsigned images until secure boot | Verify + test rules: `/firmware` admin-write-only. Keep `publish_firmware.sh` sha256 flow. Secure boot = post-MVP (§7) |
| C5 | No firmware remote crash visibility — a crash-looping unit is invisible | On boot, publish `esp_reset_reason()`, `version.txt`, uptime-at-last-reset to `gs/{uid}/devices/{dev}/health`. Additive RTDB path; add matching uid-scoped rule |
| C6 | Missing Crashlytics Gradle plugin → Android field stack traces unreadable | Add `com.google.firebase.crashlytics` to `settings.gradle.kts` + app `build.gradle.kts` (mapping upload) |
| C7 | No CI in either repo | Minimal CI (§6) |
| C8 | Version split: Android hardcodes 1.0.12, pubspec says 1.0.0+1 | Single source of truth: pubspec `version:`; remove hardcoded versionCode/Name from `build.gradle.kts` |
| C9 | No proguard keep rules; R8 release build unverified (`flutter_local_notifications` gson issue known) | Add `proguard-rules.pro` (gson TypeToken keep); install & smoke-test a `flutter build appbundle --release` |
| C10 | Firebase stream listens without `onError` (`geyser_control_cubit.dart:253,279`, `device_stats_cubit.dart:64`) — one backend error kills live data silently AND logs a fatal | Add `onError` + bounded resubscribe with backoff |

---

## 4. Minor items (tracked, not gating)

Firmware: `try_fire_event` bounds check; custom-timer hour validation (BLE accepts 0–255, RTDB minutes > 1439 truncate); event ring overwrite horizon (20); SSE 1024 B line truncation; stack high-water check on 2048 B tasks (scheduler/button do NVS+printf); wrong-password backoff keeps retrying noisily; nickname counted in UTF-16 chars vs 16 firmware bytes; open-WiFi (passwordless) unprovisionable — surface why in UI; provisioning-unchanged-WiFi reports `bleOnlyOk` until reboot; cloud `events/{dev}` PATCH clobbers history (use POST if history matters); WiFi-creds `strncpy` over-read (`wifi_prov.c:335-349` — bound by `len`); event-group free race in `wifi_prov.c`; ID-token pointer race across tasks.

App: owner key in SharedPreferences → move to `flutter_secure_storage`; unlock-retry consumes nonce (covered by U8); emit-after-close edge in provisioning timeout; sync retry-on-WiFi without backoff + signed-out `StateError` spin; dual-isolate SQLite without `busy_timeout`; notifications page resolves device via BLE pairing only; permission-denied bail skips in-app message bridging; email verification decision; stale `_deviceId` across account switch; raw exception text in snackbars; app display name still "Gs Rework"; `ACCESS_FINE_LOCATION` missing `maxSdkVersion="30"`; stale majors (flutter_bloc 8, get_it 7) — upgrade post-MVP.

Product risk register (explicit, not a code fix): **current sensing is staged but not built** (`current_sense.c` absent from CMakeLists) — no element-failure or welded-relay detection in MVP; the geyser's mechanical thermostat/TP valve is the last line of defense. State this in certification/insurance docs.

---

## 5. Execution phases

Each phase is independently shippable; no phase breaks compatibility with units or apps still on the previous phase.

**Phase 0 — Repo & signing hygiene (½ day)**
B6 keystore rotation/purge; commit the dirty working tree in gs_rework; C8 version unification.

**Phase 1 — Blockers (2–3 days)**
Firmware: B1 (watchdog), B2 (scheduler day guard), B3 (sdkconfig regen + rollback proof).
App: B4 (`allowLongWrite`), B5 (iOS workmanager + fallback).
Exit gate: the field-test matrix in §8 passes on real hardware, both platforms.

**Phase 2 — Safety majors (firmware release v0.6.0) (2–3 days)**
S1–S6, plus C2 (SC-only pairing), C5 (boot health reporting), minors m: `try_fire_event` bounds, max-on/custom-timer validation.
Ships as the **first field OTA** — which simultaneously proves the remote-update path end-to-end (B3 gate must already be green).

**Phase 3 — App majors (app release, staged rollout) (3–4 days)**
U1–U9, C6 (Crashlytics plugin), C9 (proguard + release smoke test), C10 (stream onError).
Ship at 10% → 50% → 100% on Play; phased release on App Store.

**Phase 4 — Cloud & resilience (1–2 days, deploy independently)**
C1 (Orange rules), C3 (backoff/re-auth — firmware v0.6.x OTA), C4 (rules test for `/firmware`), U3/U4 if not landed in Phase 3.
Rules deploys are instant and reversible; test with the Firebase emulator first.

**Phase 5 — CI + observability hardening (1 day, parallel with any phase)**
§6 pipelines; Crashlytics dashboards; a simple RTDB health view (units by version / reset reason).

**Post-MVP (before scale, not before launch):** secure boot + flash encryption per `SECURE_BOOT.md` (Part A → B → C staged), signed OTA images, NVS encryption, `flutter_secure_storage`, BLE/provisioning integration tests with a fake transport, dependency major upgrades.

---

## 6. CI gates (minimum viable, GitHub Actions)

**gs_rework:** `flutter analyze` (fail on error/warning) → `flutter test` → `flutter build appbundle --release` (with real signing config presence check — fail if falling back to debug) → assert pubspec version bumped on release branches.

**gs_firmware:** `idf.py build` from a clean tree (defaults-generated sdkconfig) → grep gates on `build/config/sdkconfig.h`: `CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE 1`, `CONFIG_ESP_TASK_WDT_PANIC 1`, `CONFIG_BT_NIMBLE_SM_LEGACY` **absent** → artifact the .bin with `version.txt` stamp.

The sdkconfig grep gate alone would have caught B3.

---

## 7. Remote update strategy (steady state)

**Firmware:** publish via existing `tools/publish_firmware.sh` (binary → sha256 → manifest). Staged rollout by pointing a `firmware/beta` manifest at internal units first (additive path; app/firmware ignore unknown paths), then promote to `firmware/latest`. Rollback protection: bootloader auto-revert (B3) + semver anti-downgrade already implemented. Known accepted trade-off (document): the 3-min health confirm runs without requiring cloud connectivity, so a build with a broken cloud stack can self-confirm — mitigated by the staged-manifest soak on internal units.

**App:** Play staged rollout + App Store phased release; Crashlytics with uploaded symbols (C6) as the abort signal; `firebase_remote_config` (already a dependency) for kill switches — minimum: `min_supported_app_version` (paired with the existing `version_check.dart` gate) and a `remote_control_enabled` flag to disable cloud relay control fleet-wide if a defect is found.

**Compatibility rule for every future change:** GATT — additive characteristics only, never re-type or renumber; payloads — length-checked on firmware, so new optional trailing fields are safe; RTDB — additive paths with uid-scoped rules; app must tolerate missing paths (old firmware) and firmware must tolerate absent writes (old app). The existing version characteristic (0x0B) + `version_check.dart` gate is the mechanism for gating new app features on firmware version — keep using it.

---

## 8. Field validation matrix (exit gate for Phase 1, re-run before each release)

Real hardware, both an Android and an iOS phone:

1. Fresh provision, WiFi mode — iOS and Android (proves B4).
2. Fresh provision, BLE-only mode; then add WiFi later.
3. Wrong WiFi password → explicit failure UI → retry with correct password.
4. Kill BLE mid-provisioning (walk away / reboot ESP) → sheet fails within 30 s, retry works (U1).
5. Power-cut the router 5 min, restore → device reconnects, SNTP recovers, timers fire (S5).
6. Power-cut the ESP → relay restores safely; schedule resumes after time sync.
7. Single enabled timer fires on two consecutive days (B2).
8. Thermostat cutoff at max temp; deadband honored (no chatter).
9. Disconnect the DS18B20 while relay ON → chosen S3 policy observed; SENSOR_FAIL event reaches app and RTDB.
10. OTA: publish test build → fleet updates; publish deliberately-crashing build to one bench unit → auto-rollback (B3).
11. Second phone, same account: connects, unlocks, controls (U2/U9).
12. Sign out → sign in as a different account: no data bleed, no stale FCM alerts (U3).
13. Phone offline (airplane mode) → remote toggle fails cleanly within 10 s, UI recovers (U6).
14. iOS background sync fires (Xcode BGTask debug trigger) and foreground fallback syncs after >24 h (B5).
15. Week-long offline ESP → reconnect → event/telemetry backlog lands in app, ack only after success (U5).
