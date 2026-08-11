# App ↔ firmware contract — parity table

Audited 2026-08-11 (UX polish E1), **code-to-code**: every value below was
read from both repos on the same day, not from memory. Columns cite the
authoritative files. When either side changes one of these, update the
other **and this table** in the same cycle.

Legend: ✓ = verified match · **FIXED** = mismatch found in this audit and
corrected app-side.

## GATT — service & characteristic UUIDs

Base `475300xx-7652-4543-b201-c4b801a6c700` ("GS"). App:
`gatt_uuids.dart` · firmware: `gatt_server.c` / `wifi_prov.c`
(`GS_UUID128_INIT`).

| id | Purpose | Status |
|---|---|---|
| 0x01 | Main service | ✓ |
| 0x02 | Temperature (int16 LE, °C×100) R/N | ✓ |
| 0x03 | Relay state (1 byte; fw rejects len≠1) R/W/N | ✓ |
| 0x04 | Temp limits ([min,max,ar]; fw accepts 2–3 bytes, app sends 3) R/W | ✓ |
| 0x05 | Timers (N×4 bytes; fw requires len%4==0, clamps to MAX_TIMERS; app sends 20) R/W | ✓ |
| 0x06 | Device info (fw version, UTF-8) R | ✓ |
| 0x08 | Time sync (uint32 LE epoch; fw rejects len≠4) W | ✓ |
| 0x09 | Events (buffered N×6 [type,temp,ts u32 LE]; notify 2 [type,temp]) R/N | ✓ |
| 0x0A | Telemetry buffer (N×10 [temp i16,relay,min,max,ar,ts u32]) R | ✓ |
| 0x0B | Buffer ack (1 byte; fw rejects len≠1) W | ✓ |
| 0x0C | Stored device id (RTDB id string) R | ✓ |
| 0x0D | Max-on timer (uint16 LE minutes; fw rejects len≠2) R/W | ✓ |
| 0x0E | Owner auth (R: 16-byte nonce · W: 32-byte HMAC-SHA256; RFC-4231-vector-tested both sides) | ✓ |
| 0x0F | Run status (7 bytes: u32 elapsed, u16 maxon echo, u8 flags; app degrades gracefully if <7) R | ✓ |
| 0x10 | Provisioning service | ✓ |
| 0x11 | WiFi creds (W "ssid\0password"; R returns SSID only, never the password) | ✓ |
| 0x12 | User bind (uid, optional "\0deviceId" suffix; fw len-guards vs `s_user_id`, re-entrancy-protected) | ✓ |
| 0x13 | Prov status (uint8 0–6) R/N | ✓ |
| 0x14 | Nickname (≤16 **bytes**; fw rejects over-length) R/W | **FIXED** |
| 0x15 | Auth data ("refreshToken\0deviceId"; app uses `allowLongWrite: true` — required, token ≈200+ bytes) W | ✓ |
| 0x16 | Owner key (exactly 32 bytes) W | ✓ |

## Provisioning status codes

`provisioning_status.dart` ↔ `wifi_prov.h prov_status_t` — all seven:
0 idle · 1 connecting · 2 wifi_ok · 3 wifi_fail · 4 complete · 5 error ·
6 **ble_only_ok**. App maps unknown bytes → `error`. ✓

## String/byte limits

| Field | Firmware | App (after E1) | Status |
|---|---|---|---|
| Nickname | rejects >16 **bytes** (`PROV_NICKNAME_MAX`); becomes adv name `GeyserSwitch-<nick>` — `ADV_NAME_MAX 30` = 13+16+NUL exact fit | `maxLength 16` + ASCII-only input filter `[A-Za-z0-9_-]` (chars==bytes) + `isNicknameValid` checks **UTF-8 bytes** ≤16, so legacy non-ASCII names ≤16 bytes still validate | **FIXED** (was chars-only: 16 emoji = up to 64 bytes → opaque on-device rejection) |
| SSID | `s_ssid[33]` — silently **truncates** at 32 bytes | `maxLength 32` + `canSubmit` refuses >32 UTF-8 bytes | **FIXED** (was unbounded → truncated creds → doomed connect) |
| WiFi password | `s_pass[65]` — truncates at 64 | `maxLength 63` + `canSubmit` requires 8–63 bytes when creds will be sent (WPA2 bounds) | **FIXED** (was any non-empty; <8 was a guaranteed round-trip failure) |
| Creds write total | fw rejects len<3 or >98; requires NUL separator, non-empty SSID | bounded by the two limits above (32+1+63 = 96 ≤ 98) | ✓ |
| Firebase UID | len-guarded vs `s_user_id` | 28-char ASCII from Firebase Auth | ✓ |

## Numeric ranges

| Value | Firmware (`device_state.h`) | App (`temp_limits.dart` etc.) | Status |
|---|---|---|---|
| temp min | floor 5 · ceil 50 | 5 · 50 | ✓ |
| temp max | floor 51 · ceil 70 | 51 · 70 | ✓ |
| deadband | 5 (raise-max-first resolution) | 5, same algorithm — unit-tested | ✓ |
| max-on minutes | 0–1440 (`MAX_ON_CEIL`) | 0–1440, 0 = disabled | ✓ |

## RTDB `set/$did` keys

App writes ↔ `firebase_rtdb.c apply_partial` (also full-object `is_put`):
`on` bool · `min` num · `max` num · `ar` bool · `tmask` num · `tcust` num
· `maxon` num. ✓ — and **unknown keys are ignored** (verified), which is
what makes E2's `cs`/`ls` sensor flags a zero-migration addition. Rules
(`database.rules.json`) mirror the same ranges (max ≤ 70 deployed).

## Event codes

0x01 maxTempOff · 0x02 minTempOn · 0x03 minTempAlert · 0x04 sensorFail ·
0x05 sensorRecover · 0x06 maxOnTimeout · 0x07 clockLost ·
0x08 scheduleRestored · 0x09 leak · 0x0A leakClear — `event_buffer.h` ↔
`device_notification.dart`, and `functions/index.js` push copy 1–10. ✓

## Discovery & flow invariants

- Scan filter: app matches `advName.startsWith('GeyserSwitch')`; firmware
  advertises `GeyserSwitch-Setup` / `GeyserSwitch-<nick>` /
  `GeyserSwitch`. ✓
- Provisioning safety timeout: cubit arms a timeout and **re-arms on
  every non-terminal status** notification, so a BLE drop mid-flow can't
  spin the sheet forever. ✓
- Owner-auth gating: creds/bind/nickname writes require the unlock
  (`owner_auth_gate_ok`) once provisioned; app performs unlock on
  connect. ✓
- `hasChanges` guard prevents idempotent re-submits on an
  already-provisioned device. ✓
