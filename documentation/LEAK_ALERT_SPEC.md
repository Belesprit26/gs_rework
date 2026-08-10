# Water-leak alert — end-to-end spec

Status: **app + firmware implemented; app banner + FCM copy remain.** The leak
sensor is on GPIO22. A leak alerts the phone (live BLE + FCM push), cuts power,
and blocks re-power while wet. **No LED effect**, by decision. One firmware
deviation from the plan needs a call — see the note in §1
(block-while-wet vs latch-until-user).

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

- Event codes `EVT_LEAK 0x09` / `EVT_LEAK_CLEAR 0x0A` (`event_buffer.h`,
  `EVT_TYPE_COUNT` → 10).
- `leak.c` / `leak.h`: a debounced GPIO22 poll task (wet 2 s, dry 10 s;
  active-low pull-up — **verify the probe polarity at bench**, flip
  `LEAK_WET_LEVEL` if inverted). On a confirmed leak it fires `EVT_LEAK` via
  the standard path (`event_buffer_push_event` + `gatt_server_notify_event` +
  `firebase_rtdb_request_event_push`), and on confirmed-dry `EVT_LEAK_CLEAR`.
  Wired in `main.c` (`leak_task`, GPIO22).
- **Power lockout — single choke point:** a `leak_lockout` flag in
  `device_state`; `device_state_set_relay(true)` is **refused** while it's set
  (switching OFF is always allowed). One guard covers every path — a leak cuts
  the relay and the scheduler, auto-reheat, button and remote all fail to
  re-energise a wet geyser.

> **Deviation to confirm.** The plan said "latch OFF until the *user* turns it
> back on." What's built is **block-while-wet + auto-release on confirmed-dry**
> (10 s): the lockout blocks all power-on while water is present, then clears
> itself once the probes are dry, so normal control resumes (the relay still
> stays OFF until the schedule / user / auto-reheat turns it on). This is
> simpler and hard-blocks power while wet, but it does **not** wait for an
> explicit user acknowledgement. The strict "latch until user" version needs
> the user-on paths (button / BLE / remote) to clear the lockout — a
> cross-cutting change better done once it can be compiled. Which do you want?

## 2. App (`gs_rework`) — DONE

- `NotificationType.leak (0x09)` / `leakClear (0x0A)` added
  (`device_notification.dart`) and rendered through all six `NotificationType`
  switches (`device_notification.dart` body, `settings_tab.dart` +
  `notifications_page.dart` colour/icon): leak → red + `Icons.water_damage`,
  body "Water leak detected near the geyser — check it now".
- **Not silenceable:** `leak` is excluded from `NotificationType.settable`, so
  it has no mute toggle and always alerts. `leakClear` stays mutable.

Still to do (alongside the firmware step): a persistent **critical dashboard
banner** while a leak is unacknowledged (follow the `_ClockLostBanner`
pattern), and a **high-importance FCM channel** so the push lands with the app
closed.

## 3. Cloud function (`functions/index.js`)

- `onDeviceEvent` maps event codes → push copy. Add `0x09` → title "Water leak
  detected", body "GeyserSwitch cut the power. Check your geyser and water
  supply." at high priority; `0x0A` → an optional, quieter "Leak cleared".

## Nothing else changes

RTDB rules already accept any numeric `events/$did/type` (no rule change). The
BLE event characteristic, the 6-byte event struct, buffering, ack, and the
7-day local retention all carry the new codes unchanged.

## Open decisions

1. **Lockout semantics** — built as *block-while-wet + auto-release on
   confirmed-dry* (§1). Confirm, or upgrade to *latch until the user turns it
   back on* (needs the user-on paths to clear the lockout). Plus: a per-device
   opt-out for false-positive-prone installs?
2. **Debounce window** (suggested ≈ 2–3 s bridged) and clear hysteresis.
3. **Probe hardware** — GPIO22 is assigned on the board; the wet/dry threshold
   and probe placement remain the hardware choice.
4. **Push channel** — dedicated critical / high-importance channel + DND bypass?
