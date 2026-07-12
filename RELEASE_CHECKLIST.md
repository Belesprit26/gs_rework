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

- [x] **[audit] BLE owner-lock — implemented 2026-07-13.** A random 32-byte
  device key is generated at provisioning, written to the ESP (0x16, NVS) and
  stored in the account's Firestore scope (`users/{uid}/geyser_config/{did}`).
  Control + provisioning writes are gated behind an HMAC-SHA256
  challenge-response (0x0E): any phone signed into the household account fetches
  the key and unlocks (then works offline via a local cache); a stranger's phone
  is refused (`INSUFFICIENT_AUTHOR`). **Hijack fixed:** `on_user_bind` and the
  WiFi/nickname/auth/SSID characteristics now require an owner-unlocked session
  once provisioned. Multi-phone by construction (one login = full BLE + cloud
  control), key rotation via Device Management → "Reset access key", ownership
  transfer via the physical factory-reset. Reads (temp/state/events) stay open.
  App + firmware HMAC pinned to a shared RFC 4231 test vector.
  - Residual (documented, accepted): the one-time provisioning window is still
    Just Works (NO_IO hardware) — an active MITM present at first setup could
    capture the key. Cross-*account* sharing with roles is a future phase.
- [x] **[audit] Telemetry cloud sync durability — fixed 2026-07-04.** Replaced
  the read-modify-write merged file with immutable NDJSON chunk objects
  (`telemetry/{uid}/{deviceId}/{utcTs}_{nonce}.ndjson.gz`): no download step
  (10 MB ceiling and quadratic re-upload gone), concurrent writers (isolates or
  two phones on one account) can no longer clobber each other, and a crash
  between upload and `markSynced` now yields a dedup-able duplicate chunk
  instead of data loss. Added a cross-isolate `SyncLock` (atomic exclusive
  file create + stale takeover) so main-isolate and workmanager syncs
  serialize; per-device failure isolation + drain loop; `prefs.reload()`
  before retry checks. **Also fixed:** retention pruning deleted records
  older than 7 days *before* sync and regardless of sync state — prunes are
  now synced-only (7 d) with a 60-day absolute backstop, and run *after* the
  sync. Legacy merged files are left as frozen archives; nothing reads them.
  Covered by the repo's first unit tests (lock, prune, chunk paths, codec).
- [x] **[audit] `current_sense.c` — resolved as documented staging (2026-07-04).**
  Deliberately excluded from the build: the CT hardware is still under
  evaluation (HARDWARE_ROADMAP.md → "Current sensor evaluation", open BOM
  decision). The file now carries a "STAGED, NOT IN THE BUILD" header; add it
  to SRCS + init from `app_main` if/when the CT clamp lands on the BOM.

## Should fix (Medium)

- [x] **[audit] `main()` init error guard — fixed 2026-07-04.** Non-critical
  startup steps (telemetry recorder, notification service, FCM, sync
  orchestrator, workmanager) each run through `_guardedStart`: a failure is
  logged + reported to Crashlytics (non-fatal) and launch continues. Firebase
  init + DI stay fail-loud (nothing works without them).
- [ ] **[audit] No battery-backed RTC** — after a power cut the clock is invalid
  until NTP (needs WiFi) or a BLE time write, so scheduled heating silently
  won't fire. Significant in a load-shedding market. (Hardware — see roadmap.)
- [x] **[audit] `'g1'` device-ID fallback collision — fixed 2026-07-04.**
  Provisioning now aborts with a clear error if the BLE identifier is missing
  (instead of provisioning under a shared ID), and the legacy no-`0x0C`
  fallback derives the ID from the BLE identifier (unique per device) instead
  of mapping everything to `g1`. The provisioning Firestore registry write is
  now awaited + error-contained.
- [ ] **[audit] Test coverage** — improved (sync lock, prune semantics, chunk
  paths, codec, temp-limit clamp), still missing: cubit tests, security-rules
  emulator tests.
- [x] Fix `checkDeviceOffline` to track `offlineNotified` per-device —
  **already done** in `index.js` (`meta/offlineNotified/{did}`); the line was
  stale.
- [x] Remove dead code — done 2026-07-04. App: `HomePage` wrapper removed
  (auth gate returns `DashboardPage` directly); `agent_log` and the Devices-tab
  placeholder no longer exist (stale entries). Firmware: see table below.
- [x] Fix deprecated `isInDebugMode` in WorkManager config — parameter removed
  (deprecated and a no-op in the current workmanager).
- [x] Scope `profile_pics` storage rule — `storage.rules` no longer exposes it
  (now only `firmware/` + per-user `telemetry/`)
- [x] Add `firestore.rules` to the repo — present and well-scoped

## Nice to have for v1

- [ ] **[audit] Hardcoded `TZ=SAST-2`** (`time_sync.c`) — schedules are wrong
  outside South Africa. Make timezone configurable if expanding.
- [x] **[audit] 5 °C deadband mirrored in the app — done 2026-07-04.** Shared
  `clampTempLimits()` in `domain/geyser/temp_limits.dart` (same constants +
  order of operations as the firmware clamp) applied in `GeyserControlCubit`
  (covers both RTDB and BLE paths) and `BleGeyserControlRepository`. Unit
  tests keep it in lockstep with `device_state.c`.
- [x] **[audit] `watchTodayStats` midnight rollover — fixed 2026-07-04.** The
  RTDB subscription now swaps to the new date node just after local midnight
  and emits an empty-day reset immediately.
- [ ] Split `dashboard_page.dart` into smaller widgets
- [ ] Clean up legacy RTDB paths in `firebase_auth_repository.dart`
- [x] Fix firmware stack-size comment inconsistency — comment now says 12 KB.
- [ ] Set up l10n if targeting multiple languages

## Corrections to prior claims

- ~~"Wire device ID … already done — derived from BLE MAC"~~ — on **iOS**,
  `remoteId` is a per-phone Core Bluetooth UUID, **not** the ESP MAC. It works
  in practice because the app re-reads the ESP's stored ID via characteristic
  `0x0C` when no local mapping exists — but the `'g1'` fallback collision remains
  (see Medium).
- ~~"Perfect as-is: `temperature.c`"~~ — the thermostat was correct but the
  max-on backstop had the two safety gaps fixed above.

## Firmware dead code — status after 2026-07-04 cleanup

| Item | Status |
|------|--------|
| `current_sense.c` (whole file) | **Kept, documented** — staged for the CT-hardware BOM decision (header note added) |
| `time_sync_stop_sntp()` | Already gone — stale entry |
| `firebase_rtdb_sync_relay()` | Already gone — stale entry |
| `wifi_prov_is_connected()`, `wifi_prov_event_group()` | **Removed**, along with the write-only `s_wifi_event_group` plumbing + `WIFI_EVT_CONNECTED` |
| `wifi_prov_reset()` | **Kept deliberately** — header documents it as reserved for the re-provisioning / owner-unbind flow (needed by the upcoming BLE owner-lock) |
| GATT 0x07 telemetry characteristic | **Removed** (uuid, stub callback, table entry) — no app consumer existed; buffered telemetry is 0x0A |
| Stale comment "8 KB stack" | **Fixed** — now 12 KB |

## App dead/redundant code — status after 2026-07-04 cleanup

| Item | Status |
|------|--------|
| `HomePage` | **Removed** — auth gate returns `DashboardPage` directly |
| `agent_log` / `agent_log_scope` | Never existed in this repo — stale entry |
| Devices tab placeholder | Already replaced by the Device Management page — stale entry |

## Security rules gaps

| Rule file | Issue | Severity |
|-----------|-------|----------|
| `database.rules.json` | `Orange` node — any authed user can read/write entire tree | Medium |
| `storage.rules` | **[audit]** `firmware/` — client write closed (`write: if false`) 2026-07-01 | Resolved |
| `database.rules.json` | `GeyserSwitch/{uid}/ServiceInfo` — fixed, enforces `auth.uid === $uid` | Resolved |
| `storage.rules` | `profile_pics/` — no longer present | Resolved |
| Firestore | `firestore.rules` now in repo, per-user scoped | Resolved |
