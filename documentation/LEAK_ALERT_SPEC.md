# Water-leak alert — end-to-end spec

Status: **spec (not yet implemented).** The leak sensor is roadmap hardware
(`HARDWARE_ROADMAP.md` Phase 1 — "Leak sensor triggers when water bridges
probes"); there is no firmware or app code for it yet. A leak must be **loud on
the device (LED) and on the phone (app)** — this spec defines the whole path so
the two stay in lockstep, reusing the existing event/notification pipeline (no
new transport).

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
as a **critical** notification + dashboard banner → and shown on the LED. Two
new event codes; everything else is existing pipeline.

## 1. Firmware (`gs_firmware`)

- **New event codes** (`event_buffer.h`, next free after `0x08`):
  `EVT_LEAK 0x09`, `EVT_LEAK_CLEAR 0x0A`; bump `EVT_TYPE_COUNT` to 10.
- **Sensor read:** a GPIO input (probes bridged by water = active). Poll and
  **debounce hard** — require sustained bridging (≈ 2–3 s) before firing, with
  hysteresis before clear, so condensation/splash don't false-trigger. Mirror
  the `button_task` poll + task-WDT pattern on **GPIO22** (`Leak_1` on the
  board schematic).
- **On leak (rising edge):** `device_state_set_relay(false)` and **latch** — do
  not let the scheduler or auto-reheat switch it back on while a leak is active
  — then `event_buffer_push_event(EVT_LEAK, temp)` and push over BLE + RTDB/FCM
  (the same calls the temperature events use).
- **On clear:** fire `EVT_LEAK_CLEAR`; the relay stays off until the **user**
  turns it back on — do not auto-resume, a re-wetting probe shouldn't cycle the
  element.
- **Control decision to sign off:** auto-cut-and-latch is customer-impacting
  (no hot water until cleared). Recommended for a leak, but consider a
  per-device opt-out (like the interval-fallback opt-out) for installs where
  probe placement is false-positive-prone. **The alert always fires regardless
  of the opt-out.**

## 2. App (`gs_rework`)

- **New `NotificationType`s** (`device_notification.dart`, mirroring the codes):
  `leak(0x09, 'Water Leak')`, `leakClear(0x0A, 'Leak Cleared')`.
- **Styling** (`settings_tab.dart` `_iconForType` / `_colorForType` /
  `_descriptionForType`): leak → `Icons.water_damage`, the **critical** colour
  (`AppColors.critical`), description "Water detected near the geyser — power
  cut. Check for a leak."
- **Not silenceable.** Exclude `leak` from the mutable set (`NotificationType.
  settable`) — a safety alert must not be toggle-off-able. `leakClear` can sit
  with the normal, mutable set.
- **Critical surfacing beyond the list:** don't let a leak be just one row on
  the notifications page. Add a **persistent red dashboard banner** (follow the
  `_ClockLostBanner` pattern in `dashboard_page.dart`) while a leak is
  unacknowledged — "Water leak detected — power off. Check your geyser." — that
  clears on `leakClear` or user acknowledgement.
- **Push priority:** the leak FCM should use a **high-importance / critical**
  channel so it alerts with the app closed, and should bypass the per-type mute
  (it's non-silenceable).

## 3. Cloud function (`functions/index.js`)

- `onDeviceEvent` maps event codes → push copy. Add `0x09` → title "Water leak
  detected", body "GeyserSwitch cut the power. Check your geyser and water
  supply." at high priority; `0x0A` → an optional, quieter "Leak cleared".

## 4. LED (firmware)

- Specced in `gs_firmware/LED_STATUS_SPEC.md`: leak is the **highest-priority
  overlay** — a fast, unmistakable red/off strobe that overrides every other
  state until `EVT_LEAK_CLEAR`.

## Nothing else changes

RTDB rules already accept any numeric `events/$did/type` (no rule change). The
BLE event characteristic, the 6-byte event struct, buffering, ack, and the
7-day local retention all carry the new codes unchanged.

## Open decisions

1. **Auto-cut + latch on leak** (recommended) vs alert-only — and whether to
   offer a per-device opt-out for false-positive-prone installs.
2. **Debounce window** (suggested ≈ 2–3 s bridged) and clear hysteresis.
3. **Probe hardware** — GPIO22 is assigned on the board; the wet/dry threshold
   and probe placement remain the hardware choice.
4. **Push channel** — dedicated critical / high-importance channel + DND bypass?
