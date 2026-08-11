# UX polish plan — feedback, haptics, connectivity rail, provisioning

Status: **planned, not started.** Four workstreams that share one goal: every
piece of feedback the app gives — visual, textual, tactile — speaks the same
neu design language with the same severity grammar. Ordered so each phase
lands independently (one commit each, analyze + tests green, no cross-phase
coupling). Logic layers (cubits, repositories) are untouched throughout;
this is presentation-layer work.

---

## Audit findings (2026-08-11 sweep)

### Snackbars — 4 call sites, no system

| Site | Today | Problem |
|---|---|---|
| `dashboard_page.dart` `_SingleDeviceHome` listener | `Command failed: ${state.error}` on `colorScheme.error` red | The red offline-toggle message. Leaks raw exception text ("Exception: Command timed out…"). Red implies *fault*; being offline is a *condition*. |
| `login_form.dart` | "Password reset email sent." default dark snackbar | Unstyled, off-language. |
| `device_management_page.dart` key reset | One identical snackbar for success AND failure | No severity signal at all. |
| `app_theme.dart` | No `snackBarTheme` registered | Every snackbar falls back to Material defaults. |

### Haptics — none

Zero `HapticFeedback` / `enableFeedback` usage anywhere. Greenfield: we get
to define the vocabulary once, centrally.

### Provisioning access + surfaces

- The app-bar `AuthLogoBadge` is a raised neu disc that **looks tappable but
  has no tap handler**.
- `DeviceScanPage` is reachable only from (a) the mode banner in its three
  offline-ish states, (b) Settings → Devices → `DeviceManagementPage` FAB.
- `DeviceScanPage`, `provisioning_sheet.dart`, and `DeviceManagementPage`
  are the last stock-Material surfaces in the app: `FilledButton`,
  `ListTile`, `Colors.blue.shade50` status banners, a FAB. Everything else
  is neu.
- Provisioning logic (`ProvisioningCubit`, `BleConnectionCubit`,
  `ble_provisioning_repository`) is solid and recently field-hardened — the
  overhaul is **widget-layer only**.

### Mode banner (to be replaced by the rail badge)

`_ModeBanner` renders six states: BLE-connected · WiFi-fresh · WiFi-stale
("Device offline" + last-seen) · connecting · Bluetooth-off · not-connected.
It always occupies a full-width row under the focal card, and its offline
states are tap-to-scan. Both the *last-seen* detail and the *tap action*
must survive the move into a badge (they go into the tap sheet).

---

## Phase A — `AppSnack`: one feedback system

New file `lib/presentation/shared/feedback/app_snack.dart`.

### API

```dart
enum AppSnackType { success, info, warning, error }
void showAppSnack(BuildContext context, {
  required AppSnackType type,
  required String message,
  String? actionLabel, VoidCallback? onAction,
});
```

### Styling (the neu snack)

Reuses the exact grammar of the leak nudge card — white surface, neu raised
shadow, 3 px left accent bar, leading icon in the type colour, **ink text on
white** (never white-on-colour):

- Container: `AppColors.surface`, radius 14, `neuRaisedShadows(distance: 4,
  blur: 12)`, floating with 16 px margin, above the bottom nav.
- Left accent bar 3 px + leading icon, both in the type colour.
- Text: `AppColors.ink`, 13.5 px; optional action as a teal text button.

| Type | Colour | Icon | Duration | Used for |
|---|---|---|---|---|
| success | `AppColors.primary` (teal) | `check_circle_outline` | 2 s | saves, key reset OK, reset email sent |
| info | `AppColors.rampBlue` | `info_outline` | 3 s | neutral FYIs |
| warning | `AppColors.warning` (amber) | `cloud_off_rounded` etc. | 3.5 s | **offline / unreachable / degraded** |
| error | `AppColors.critical` (red) | `error_outline` | 4 s | real failures (auth rejected, write refused) |

Also register a matching `snackBarTheme` in `app_theme.dart` so any stray
`SnackBar` inherits sane styling.

### Copy map (current → new)

| Trigger | Today | New |
|---|---|---|
| Toggle timeout (remote, device offline) | red "Command failed: Command timed out — device may be offline" | **warning**: "Couldn't reach the geyser — it looks offline. Nothing was changed." |
| Toggle/BLE write failure (other) | red raw exception | **error**: "That didn't go through. Try again in a moment." (raw error → debug log only) |
| Settings/timers/temp save OK | *(silent)* | **success**: "Saved" (with what, e.g. "Timers saved") |
| Key reset OK / fail | identical default snack | **success** "Access key reset." / **error** "Couldn't reset the key — connect to the device and try again." |
| Password reset email | default snack | **success**: "Reset email sent — check your inbox." |

Rule going forward: **raw exception strings never reach the UI.** The cubit
keeps `state.error` for logic; the listener maps it to human copy.

---

## Phase B — Haptics

### Research summary (why the built-in API is enough)

Flutter's `HapticFeedback` (`flutter/services`) — no plugin, no permission:

| Call | iOS (UIKit generator) | Android (`performHapticFeedback`) |
|---|---|---|
| `selectionClick()` | `UISelectionFeedbackGenerator` | `CLOCK_TICK` |
| `lightImpact()` | Impact `.light` | `VIRTUAL_KEY` |
| `mediumImpact()` | Impact `.medium` | `KEYBOARD_TAP` |
| `heavyImpact()` | Impact `.heavy` | `CONTEXT_CLICK` |
| `vibrate()` | ~400 ms buzz | `LONG_PRESS` |

- **No `VIBRATE` permission needed** — these route through the platform
  haptic-feedback channel, not the vibrator service.
- Both platforms **respect the user's system haptic setting**; iPads and
  haptic-less devices silently no-op. Safe to call unconditionally.
- Avoid `vibrate()` entirely — it's the long buzzer and reads as an error
  klaxon.
- OEM Android intensity varies; that's acceptable — we encode *semantics*,
  not waveforms. (Core-Haptics-style custom patterns would need a plugin —
  explicitly out of scope, over-engineering for now.)

### Semantic wrapper

New file `lib/presentation/shared/feedback/haptics.dart`:

```dart
abstract final class Haptics {
  static void select()  => HapticFeedback.selectionClick(); // picked an option
  static void tap()     => HapticFeedback.lightImpact();    // minor acknowledgment
  static void commit()  => HapticFeedback.mediumImpact();   // state-changing action
  static void success() async { … medium, 90ms, light … }   // double-tick, op confirmed
  static void blocked() => HapticFeedback.heavyImpact();    // action refused / critical
}
```

One place to tune, and the future home of a user "haptics off" preference
(single kill-switch, not scattered calls).

**Ground rule:** haptics fire only on *user-initiated* actions or on
milestones of a flow the user is actively watching (provisioning). Ambient
background events (auto-reconnect in the pocket, FCM arrivals) never buzz.

### Touchpoint map

| Touchpoint | Haptic |
|---|---|
| Geyser power toggle (accepted) | `commit` |
| Geyser toggle while leak-gated | `blocked` |
| Save buttons — temp dialog, timers, geyser setup, rename | `commit` on tap → `success` when the write confirms |
| Option-selected: `RunLimitChips`, heat-mode segmented, `NeuSwitch`es (timers, auto-reheat), savings period segmented, notification filter chips, `AuthModeWell`, settings device switcher | `select` |
| Bottom nav tab change | `select` |
| App-bar logo button | `tap` (+ opens the hub, Phase D) |
| Scan: connect tapped | `tap` |
| BLE connected / provisioning step passes | `tap` per step |
| Provisioning complete | `success` |
| Provisioning / connection failed | `blocked` |
| Leak badge tap | `tap` |

Implementation note: add the calls inside the shared widgets where possible
(`NeuSwitch.onTap`, `RunLimitChip`, `NeuBottomNav`, `AuthModeWell`) so every
existing and future usage inherits them for free; per-site calls only where
a widget is single-use.

---

## Phase C — Connectivity rail badge (replaces `_ModeBanner`)

The `_FocalWithAlertRail` gutter becomes the home of a **permanent**
connectivity badge. `_ModeBanner` row is deleted from the dashboard column
(freeing vertical space); `_ClockLostBanner` and `_OwnerLockedBanner` are
untouched.

### Visual spec (user-confirmed direction)

Same 40 px neu disc as the leak badge (`AppColors.neuBase`,
`neuRaisedShadows(distance: 3, blur: 7)`), with a **thin, very light halo**
— alpha ≈ 0.25, blur 6, spread 0.5 — and the icon in **blackish grey**
(`AppColors.ink` at 0.72) except offline, which goes full orange:

| State (from `GeyserMode` + substates) | Icon | Icon colour | Halo |
|---|---|---|---|
| BLE ready | `bluetooth_connected` | ink-grey | light thin **blue** (`rampBlue` @ .25) |
| WiFi / remote, fresh | `wifi_rounded` | ink-grey | light thin **green** (`save` @ .25) |
| Device offline (remote-stale) · not connected · Bluetooth off | `link_off` (crossed connection) | **orange** (`rampOrange`) | orange @ .25 |
| Connecting / reconnecting (transient) | `bluetooth_searching` | ink-grey | amber @ .25, gentle breathe |

Distinct from the leak badge by construction: leak = *coloured* pulsing
icon; connectivity = *grey* icon with a whisper of halo. Calm by default.

### Rail stacking

Connectivity badge is **pinned first** (top, aligned with the focal card's
top edge — a stable anchor that never moves); hazard badges (leak now, the
no-sensor thermometer later) stack beneath it. Gap 12 px.

### Tap → connection sheet

The badge is tappable (haptic `tap`) and opens a neu bottom sheet carrying
everything the banner used to say, plus the actions the banner's tap hid:

- Status line + icon (mirrors the badge), device nickname.
- "Last seen 4m ago" when remote/stale (the banner's trailing text).
- Actions by state: **Reconnect** (BLE attempt), **Pair a device** (scan
  page), **Configure WiFi** (prov sheet, only when BLE-connected), and
  "Bluetooth is off" guidance when applicable.

### Implementation shape

Extract a pure mapper `ConnectivityBadgeState.from(GeyserControlState,
BleConnectionState)` → enum + colours, unit-tested against all six legacy
banner states (that's the don't-break-things audit for this phase). The
widget renders the mapper's output; `_timeAgo` moves alongside.

---

## Phase D — Logo button + connection hub

The app-bar `AuthLogoBadge` becomes a real button (it already reads as
one):

- Wrap in `GestureDetector` + `Semantics(button:)`, haptic `tap`, pressed
  state = momentary inset (the "active is inset" rule) via a 120 ms scale/
  shadow swap.
- Tap opens the **same connection sheet as Phase C's badge** — one sheet,
  two entrances. The logo is the always-available, discoverable entry into
  connection + provisioning; the rail badge is the contextual one.
- With 2+ devices the sheet lists devices (current selection highlighted,
  per-device connection state) with **Pair another device** beneath —
  subsumes the quick paths into `DeviceManagementPage` without replacing
  that page.

This answers "how do we access the prov screen": **logo → hub → Pair /
Configure**, from anywhere in the app, plus the contextual rail badge and
the existing Settings → Devices path.

---

## Phase E — Provisioning & scan surfaces in the neu language

Widget-layer restyle only; `ProvisioningCubit`, `BleConnectionCubit`, and
repositories are not touched. Every interactive element picks up Phase A/B
feedback automatically.

1. **`DeviceScanPage`** — `paper` scaffold + neu app bar; status banner →
   `NeuPanel` status card; scan CTA → neu primary button whose icon
   breathes while scanning; device rows → `SoftCard` tiles with signal-dot
   strength (not text), chevron, `tap` haptic; Bluetooth-off and empty
   states restyled with the muted neu iconography.
2. **Provisioning sheet** — sheet ground → `AppColors.paper` with standard
   drag handle (match the leak sheet); connection chips → `NeuInset` chips
   (active = inset + tinted, the app-wide grammar); text fields keep
   `AppTextField`; summary card → `SoftCard`; progress steps get neu
   step-dots with `tap` haptic per completed step, `success` on complete,
   `blocked` on failure; result view restyled (teal success, calm error
   with Try Again as neu button). **Copy addition:** mirror the device LED
   during steps — "the light on your GeyserSwitch turns blue when
   connected, green while joining WiFi" — ties the physical LED spec into
   the flow and halves "is it working?" doubt.
3. **`DeviceManagementPage`** — `SoftCard` device rows, FAB → neu button
   pinned bottom, dialogs onto `neuBase` like the dashboard's.

Phase-E acceptance: no `Colors.*.shade*` literals left in
`lib/presentation/ble/`, `lib/presentation/provisioning/`,
`lib/presentation/device/`; all colours from `AppColors`.

---

## Execution order, risk & verification

| Phase | Size | Risk | Verification |
|---|---|---|---|
| A AppSnack | S | none — additive + 4 call-site swaps | analyze; manual: offline toggle shows amber warning |
| B Haptics | S | none — fire-and-forget calls | analyze; feel-check on device (sim has no haptics) |
| C Rail badge | M | replaces a visible widget | unit test the state mapper vs all 6 banner states; visual check per state |
| D Logo hub | M | new nav surface | hub reachable from every tab; existing routes untouched |
| E Prov restyle | L | biggest diff, logic frozen | full provisioning bench run (checklist §item below); screenshot diff per state |

- One commit per phase, direct to main, full `flutter analyze` + test suite
  each time.
- TEST_CHECKLIST additions: §11 *Feedback & haptics* (snack types render
  correctly incl. offline-toggle amber; haptic map spot-checks on a real
  phone) and §12 *Connectivity badge & hub* (six states, last-seen text,
  hub actions, logo press-state), plus a re-run of §core provisioning after
  Phase E.

## Decisions (confirmed 2026-08-11)

1. **Rail stacking** — connectivity pinned **top**, hazards stack beneath.
   Stable anchor; hazard pulse still draws the eye.
2. **Logo tap** — opens the **connection hub sheet** (same sheet as the
   rail badge — one surface, two entrances).
3. **Save feedback** — dialog saves get a "Saved" snack + `success` haptic;
   inline chip/switch changes get the haptic tick only.
