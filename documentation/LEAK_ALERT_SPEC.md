# Water-leak alert — end-to-end spec

Status: **firmware + app + cloud done** (pending bench + deploy). The leak
sensor is on GPIO22. On a leak it alerts the phone (live BLE + FCM push on a
dedicated max-importance channel), cuts power, and **latches** OFF against the
schedule/auto-reheat — but the **user can override** (button/app) to resume
normal running while it's still wet, and it **re-arms only after a confirmed
dry**. In the app it surfaces as a **hanging drop badge** in the focal-card
gutter (not a banner), and the power toggle is **gated** while latched. **No LED
effect**, by decision.

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
  (`device_notification.dart`) and rendered through all `NotificationType`
  switches. **Not silenceable:** `leak` is excluded from
  `NotificationType.settable`, so it always alerts. `leakClear` stays mutable.
- **Wet-state derivation:** `NotificationRepository.hasActiveLeak(deviceId)` —
  the most recent `leak` not yet followed by a `leakClear`. Independent of
  dismissal (clearing the list doesn't clear the hazard) and survives restarts.
  Re-derived on every `NotificationService.changes` tick (a "something changed"
  pulse now fired on every insert — BLE live, buffer sync, and FCM foreground).
- **Hanging drop badge (not a banner):** `_FocalWithAlertRail` in
  `dashboard_page.dart` puts a blue-drop neu badge in the focal card's existing
  46 px left gutter while a leak is unresolved. Purely additive — a device with
  nothing wrong renders exactly as before. Tapping the badge opens
  `showLeakDetailSheet` (context + numbered steps + the deliberate override).
- **Gated toggle:** tapping the power toggle while latched (`_leakActive &&
  !isOn`) does **not** send the command — it shows an inline nudge and the badge
  draws the eye. Turning ON happens only through the sheet's "Turn back on
  anyway", which calls `toggleGeyser()` (the firmware then clears the latch via
  the user-override path). Turning OFF, or acting once already on, passes
  through untouched.

Deferred (fast-follow): a **no-temperature-sensor thermometer badge** on the
same rail (amber, informational) — the rail is built generically to host it.

## 3. Cloud function (`functions/index.js`) — DONE

- `EVENT_LABELS` maps `9` → title "Water leak detected", body "GeyserSwitch cut
  the power. Check your geyser and water supply." on a dedicated
  **`geyser_leak_alerts`** channel at **`max`** priority; `10` → a quieter
  "Leak cleared". `sendPushToAllTokens` takes optional `channelId`/`priority`
  overrides (defaulting to the standard channel, so every other caller is
  unchanged). The app creates the matching max-importance channel in
  `push_notification_manager.dart` and routes a foreground leak through it.

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
