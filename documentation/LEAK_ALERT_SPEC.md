# Water-leak alert — end-to-end spec

Status: **firmware done; app banner + FCM copy remain.** The leak sensor is on
GPIO22. On a leak it alerts the phone (live BLE + FCM push), cuts power, and
**latches** OFF against the schedule/auto-reheat — but the **user can override**
(button/app) to resume normal running while it's still wet, and it **re-arms
only after a confirmed dry**. **No LED effect**, by decision.

## Principle

A leak is the one genuinely hazardous state this product can detect: water
where it shouldn't be, plus the risk of the element dry-firing if the tank
drains. Unlike a *sensor* fault — where cutting power just costs hot water, see
`MVP_STABILIZATION_PLAN.md` §0 — a leak is a case where **de-energising is the
safe action**. So a leak both **alerts** and (recommended) **cuts and latches
mains OFF** until the user clears it. Cutting mains does **not** stop the water,
so the copy must tell the user to close the supply / call a plumber.

## The path (reuses existing plumbing)

Detected on-device → fired as a firmware event → travels the **same** route as
every other event (BLE notify + RTDB `events` + FCM push) → surfaced in the app
as a **critical** notification (a live BLE alert when connected, an FCM push
otherwise). Two new event codes; everything else is existing pipeline. **No
LED** — a leak is app-only by decision.

## 1. Firmware (`gs_firmware`) — DONE

State machine (per device), debounced GPIO22 (wet 2 s / dry 10 s; active-low
pull-up — **verify polarity at bench**, flip `LEAK_WET_LEVEL` if inverted):

- **DRY → LEAKING** (probes wet): fire `EVT_LEAK 0x09` **once** (buffer + BLE
  notify + RTDB/FCM), cut the relay, set the latch. No repeats while wet.
- **LEAKING → OVERRIDDEN** (user turns ON via button / BLE / remote): the latch
  clears, full normal control resumes; still wet, no re-alert.
- **→ DRY** (probes dry 10 s, from either state): fire `EVT_LEAK_CLEAR 0x0A`,
  clear the latch, re-arm. Only then can a fresh wetting trigger again.

The **latch** is a single choke point: a `leak_lockout` flag in `device_state`;
`device_state_set_relay(true)` is refused while set (OFF always allowed), so the
scheduler and auto-reheat can't re-energise a wet geyser. The **override** is
`device_state_user_set_relay()` — the button / BLE / remote paths call it and it
clears the latch on a user ON; the automatic paths stay on the guarded
`set_relay()`. Codes added to `event_buffer.h` (`EVT_TYPE_COUNT` → 10); the task
is wired in `main.c` (`leak_task`, GPIO22). Fires once per episode via
`leak.c`'s debounce flag; `leak.c` itself needed no change for the override.

## 2. App (`gs_rework`) — DONE

- `NotificationType.leak (0x09)` / `leakClear (0x0A)` added
  (`device_notification.dart`) and rendered through all six `NotificationType`
  switches (`device_notification.dart` body, `settings_tab.dart` +
  `notifications_page.dart` colour/icon): leak → red + `Icons.water_damage`,
  body "Water leak detected near the geyser — check it now".
- **Not silenceable:** `leak` is excluded from `NotificationType.settable`, so
  it has no mute toggle and always alerts. `leakClear` stays mutable.

Still to do: a persistent **critical dashboard banner** — "leak detected —
sensor still wet" — while a leak is unresolved, with the wet state **derived
app-side from the event pair** (an `EVT_LEAK` not yet followed by
`EVT_LEAK_CLEAR`), following the `_ClockLostBanner` pattern; and a
**high-importance FCM channel** so the push lands with the app closed.

## 3. Cloud function (`functions/index.js`)

- `onDeviceEvent` maps event codes → push copy. Add `0x09` → title "Water leak
  detected", body "GeyserSwitch cut the power. Check your geyser and water
  supply." at high priority; `0x0A` → an optional, quieter "Leak cleared".

## Nothing else changes

RTDB rules already accept any numeric `events/$did/type` (no rule change). The
BLE event characteristic, the 6-byte event struct, buffering, ack, and the
7-day local retention all carry the new codes unchanged.

## Open decisions

1. **Lockout semantics** — resolved: latch + user-override + re-arm on
   confirmed-dry (§1). Open only: a per-device opt-out for false-positive-prone
   installs?
2. **Debounce window** (suggested ≈ 2–3 s bridged) and clear hysteresis.
3. **Probe hardware** — GPIO22 is assigned on the board; the wet/dry threshold
   and probe placement remain the hardware choice.
4. **Push channel** — dedicated critical / high-importance channel + DND bypass?
