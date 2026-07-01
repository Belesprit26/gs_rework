# GeyserSwitch Release Checklist

Last updated: 2026-07-01

> 2026-07-01: Full production-readiness audit of the app + firmware + Cloud
> Functions + security rules. New findings added below and several prior
> "done"/"perfect" claims corrected. Items marked **[audit]** were surfaced
> in that pass.

## Fixed in the 2026-07-01 pass

- [x] **Max-on safety timer is now an absolute ceiling** — previously it only
  counted while the sensor was dead, so a stuck/mis-placed sensor or an
  unreachable setpoint could leave the relay energised indefinitely.
  (`temperature.c`)
- [x] **Max-on timer is now flap-resistant** — the accumulator resets only when
  the relay is actually OFF, so an intermittently-recovering sensor can no
  longer keep zeroing the backstop. (`temperature.c`)
- [x] **Minimum temperature deadband (5 °C) enforced** — prevents relay/contactor
  chatter when auto-reheat is on and min/max are set almost equal (e.g.
  50/51). Clamp is centralised in `device_state_clamp_limits()` and applied on
  every entry path (BLE, RTDB, NVS load/save) so live state and persisted
  values cannot diverge. (`device_state.c/h`, `nvs_store.c`)
- [x] Corrected FCM copy for the max-on event (no longer claims "sensor
  offline"). (`functions/index.js`)

## Must fix before release (Critical)

- [~] **[audit] OTA update path — Part A implemented 2026-07-01, needs bench
  validation.** Added `main/ota.c` (manifest poll at RTDB `/firmware/latest` →
  `esp_https_ota` download → validate → relay-safe reboot), app rollback
  (`CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE`, health-gated
  `esp_ota_mark_app_valid_cancel_rollback`), version from `version.txt` /
  `esp_app_desc`, and `tools/publish_firmware.sh`. **Still required before this
  channel is production-trustworthy: Part B (image signing via Secure Boot v2).**
  Validate the full flow (update, power-loss mid-download, rollback on bad boot,
  downgrade rejection) on dev boards first.
  - Build note: `sdkconfig.defaults` gained a key — regenerate `sdkconfig`
    (delete it or `idf.py reconfigure`) so `CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE`
    actually takes effect; a committed `sdkconfig` will not auto-absorb it.
- [~] **[audit] Flash encryption / Secure Boot v2 / NVS encryption — Part B
  scaffolding staged 2026-07-01; eFuse burn still pending.** Protects the
  plaintext refresh token + WiFi PSK at rest and (via image signing) makes the
  OTA channel forgery-proof. Staged in the firmware repo:
  `sdkconfig.secure` (opt-in fragment, **not** in the default build; dev-mode
  flash-enc so bench boards stay reflashable), `nvs_key` partition already in
  `partitions.csv` (inert until secure, so no future repartition/NVS wipe),
  `tools/gen_secure_boot_key.sh`, `.gitignore` for the key, and a phased
  runbook in `SECURE_BOOT.md`. **Remaining = the irreversible hardware step:**
  generate/secure the signing key, then dev-mode bring-up on sacrificial boards
  → re-validate OTA under secure boot → release-mode on production units. Do
  **not** start until OTA (Part A) is validated on a bench board.
- [x] **[audit] `storage.rules` firmware bucket writable by any authed user** —
  fixed 2026-07-01: client writes to `firmware/` now denied (`write: if false`);
  firmware is published via Admin SDK / `firebase deploy` / CI only. Read stays
  public for now (legacy Orange downloads unauthenticated); tighten to
  authenticated read + signed images when gs_rework gains OTA.
- [x] Add proper Android release signing config (keystore)
- [x] Move `FIREBASE_API_KEY` to environment/Secret Manager in Cloud Functions
  (verify `functions/.env` is actually deployed — `createDeviceToken` fails
  silently if it's unset; the key is public, so a hardcoded fallback is safe)
- [x] Fix `GeyserSwitch/{uid}/ServiceInfo` RTDB rules to enforce `auth.uid === $uid`
- [x] Remove or secure `sendNotificationFromESP32` shared secret (uses
  `defineSecret` + Secret Manager; the docstring still mentions a removed
  hardcoded fallback — cosmetic)

## High

- [ ] **[audit] BLE has no owner lock** — Just Works pairing (`sm_mitm = 0`,
  `NO_IO`) + advertises forever + `on_user_bind` never checks "already
  provisioned". Any phone in range can pair and toggle the relay, and a paired
  peer can **re-bind a deployed unit to their own account** (hijack). WiFi creds +
  refresh token cross this un-authenticated link at provisioning time. Options:
  reject re-provisioning once owned, gate advertising post-provision, or
  app-layer-encrypt the provisioning payload with a per-device secret (QR).
- [ ] **[audit] Telemetry cloud sync is fragile** (`cloud_storage_sync_repository.dart`):
  read-modify-write of one per-device `.ndjson.gz` with (a) no concurrency guard
  in `SyncOrchestrator` → concurrent syncs lose data, (b) a hard 10 MB
  `getData` cap → sync breaks permanently once the file grows past it, no
  rotation, (c) crash between upload and `markSynced` → duplicate records.
- [ ] **[audit] `current_sense.c` is dead code** — not in `main/CMakeLists.txt`
  SRCS, referenced by nothing. Element/relay current-failure detection ships
  dark. Wire it in or remove it.

## Should fix (Medium)

- [ ] **[audit] `main()` has no init error guard** (`main.dart`) — a throw from
  `Firebase.initializeApp` or `PushNotificationManager.initialize()` kills app
  launch. Wrap in try/catch / `runZonedGuarded`.
- [ ] **[audit] No battery-backed RTC** — after a power cut the clock is invalid
  until NTP (needs WiFi) or a BLE time write, so scheduled heating silently
  won't fire. Significant in a load-shedding market.
- [ ] **[audit] `'g1'` device-ID fallback collides** — multiple unprovisioned/
  legacy devices per user all map to `g1` (same RTDB path). (Cross-platform iOS
  is otherwise handled well via the `0x0C` stored-ID recovery.)
- [ ] **[audit] Effectively no test coverage** — one default `widget_test.dart`.
  Add unit tests for the thermostat/deadband bounds, BLE byte codecs, and
  security rules (emulator).
- [ ] Fix `checkDeviceOffline` to track `offlineNotified` per-device —
  **already done** in `index.js` (`meta/offlineNotified/{did}`); this line was
  stale.
- [ ] Remove dead code (firmware: unused functions; app: `HomePage` wrapper, `agent_log`)
- [ ] Fix deprecated `isInDebugMode` in WorkManager config
- [x] Scope `profile_pics` storage rule — `storage.rules` no longer exposes it
  (now only `firmware/` + per-user `telemetry/`)
- [x] Add `firestore.rules` to the repo — present and well-scoped

## Nice to have for v1

- [ ] **[audit] Hardcoded `TZ=SAST-2`** (`time_sync.c`) — schedules are wrong
  outside South Africa. Make timezone configurable if expanding.
- [ ] **[audit] Mirror the 5 °C deadband in the app's `setTempLimits`** so the UI
  can't briefly show a value the firmware will override.
- [ ] **[audit] `watchTodayStats` captures "today" at subscribe time** — no
  midnight rollover while the app stays open.
- [ ] Split `dashboard_page.dart` into smaller widgets
- [ ] Clean up legacy RTDB paths in `firebase_auth_repository.dart`
- [ ] Fix firmware stack-size comment inconsistency
- [ ] Set up l10n if targeting multiple languages

## Corrections to prior claims

- ~~"Wire device ID … already done — derived from BLE MAC"~~ — on **iOS**,
  `remoteId` is a per-phone Core Bluetooth UUID, **not** the ESP MAC. It works
  in practice because the app re-reads the ESP's stored ID via characteristic
  `0x0C` when no local mapping exists — but the `'g1'` fallback collision remains
  (see Medium).
- ~~"Perfect as-is: `temperature.c`"~~ — the thermostat was correct but the
  max-on backstop had the two safety gaps fixed above.

## Firmware dead code to clean up

| Item | File |
|------|------|
| `current_sense.c` (whole file) | **[audit]** not compiled — absent from `CMakeLists.txt` SRCS |
| `time_sync_stop_sntp()` | `time_sync.c` — declared, implemented, never called |
| `firebase_rtdb_sync_relay()` | `firebase_rtdb.c` — declared, implemented, never called |
| `wifi_prov_reset()`, `wifi_prov_event_group()`, `wifi_prov_is_connected()` | `wifi_prov.c` — never called (factory reset uses `nvs_flash_erase()` in `button.c` instead) |
| GATT 0x07 telemetry characteristic | `gatt_server.c` — stub, always returns empty |
| Stale comment "8 KB stack" | `firebase_rtdb.c` — task actually uses 12 KB |

## App dead/redundant code

| Item | Location |
|------|----------|
| `HomePage` | Only wraps `DashboardPage` — redundant layer |
| `agent_log` / `agent_log_scope` | `lib/core/` — not referenced anywhere |
| Devices tab | `Center(child: Text('Devices – coming soon'))` — placeholder |

## Security rules gaps

| Rule file | Issue | Severity |
|-----------|-------|----------|
| `database.rules.json` | `Orange` node — any authed user can read/write entire tree | Medium |
| `storage.rules` | **[audit]** `firmware/` — client write closed (`write: if false`) 2026-07-01 | Resolved |
| `database.rules.json` | `GeyserSwitch/{uid}/ServiceInfo` — fixed, enforces `auth.uid === $uid` | Resolved |
| `storage.rules` | `profile_pics/` — no longer present | Resolved |
| Firestore | `firestore.rules` now in repo, per-user scoped | Resolved |
