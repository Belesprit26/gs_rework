# Multi-device sync plan (Settings rework prerequisite)

The Settings rework (option A / H1) puts a device switcher on the
Settings tab. Before that can be safe, device selection has to become
a single source of truth that every screen obeys — today it isn't.
This doc plans that, then the Settings build sits on top.

## The problem, precisely

`DeviceRegistryCubit` holds the selected device, but nothing reacts to
a selection change automatically. The fan-out is **hand-wired in one
place** — `dashboard_page.dart _onPageChanged` (:215-222):

```dart
registry.selectDevice(index);
context.read<GeyserControlCubit>().switchDevice(device.rtdbDeviceId);
context.read<DeviceStatsCubit>().switchDevice(device.rtdbDeviceId);
```

So a second caller (the Settings switcher) that only does
`selectDevice()` would update the registry but leave stats and geyser
control pointing at the old device — the screens would silently
disagree. And some per-device reads bypass the registry entirely
(notifications resolves the device by BLE pairing; the cubits capture
a `'g1'` fallback id at construction).

## Target: registry drives everything

1. **One writer, everyone subscribes.** Selecting a device (dashboard
   swipe *or* Settings switcher) calls `registry.selectDevice(...)` and
   nothing else. The fan-out to stats + geyser-control moves *inside*
   the registry flow so it fires no matter who triggered it — either by
   having the registry expose a `selectedDevice` stream the cubits
   listen to, or a thin `DeviceSelectionCoordinator` that owns the
   three-way update. (Prefer the coordinator: keeps the cubits free of
   each other, one place to read when debugging.)

2. **Dashboard swipe delegates.** `_onPageChanged` calls only
   `selectDevice(index)`; the manual `switchDevice` pair is deleted.
   The PageView also has to *follow* external selection changes (jump
   to the page when Settings switches) — a `BlocListener` on the
   registry animating the controller.

3. **Settings scopes to the selection.** The per-geyser section reads
   `regState.selectedDevice`; its switcher label opens a picker that
   calls `selectDevice`. Global sections (Alerts, Account, About) are
   unscoped.

## Audit — every per-device read must go through the registry

| Reader | Today | Fix |
|---|---|---|
| GeyserControlCubit | `deviceId` captured at DI, `switchDevice` manual | Driven by coordinator/registry stream |
| DeviceStatsCubit | same | same |
| Geyser setup dialog | `registry.state.selectedRtdbId` ✓ | keep; move onto Settings tab |
| Max-run / backup timer | on device-management page | move onto Settings, read selected id |
| Notifications page | resolves by BLE `pairedDeviceId`, shows one device | **Pool, don't filter:** show ALL devices' notifications in one list, each row labelled by its device. Drops the pairing-centric resolution (fixes that audit flag) — the list stops depending on the selected device at all |
| `'g1'` fallback in cubits | silent default | only when genuinely no device; never masks a real selection |

## Notifications: pooled + differentiated

Notifications are the one screen that is NOT scoped to the selected
device. They pool across every registered geyser into a single list,
newest-first, with each row showing which device it came from (a small
device chip/label). Rationale: alerts are things you want to see
regardless of which geyser you're currently looking at — a sensor
failing on the cottage geyser shouldn't be hidden because you're
viewing the main house. The rows are already stored per `deviceId` in
Drift, so this is a query + label change, not a schema change. The
unread badge counts across all devices.

Future work that builds on this device-identity seam — per-device
theme colour, "remember last device" — is tracked in `DEFERRED.md`.

## Single-device presentation

`isMultiDevice == false` → the switcher hides, the section label drops
the `▾` picker affordance and reads just "This geyser". No behaviour
change for the common case.

## Build order (Settings UI last)

1. Coordinator/stream: registry selection fans out to stats +
   geyser-control. Dashboard swipe delegates to it. Verify swipe still
   works with the manual calls removed.
2. PageView follows external selection (listener → animateToPage).
3. Repoint captured ids at the registry; rework the notifications page
   to pool across all devices with per-device labels + all-device
   unread badge.
4. Build the Settings tab (H1): global sections, then the scoped card
   with the section-label switcher + picker sheet.
5. Fold in the run-limit rounding (whole-hour presets; firmware 60 s
   guard already covers boundary collisions — the :58 values retire).
6. Move sign-out into Settings › Account; drop the app-bar logout icon.

## Audit findings — deferred (low impact, tracked not fixed)

An adversarial review (2026-08-08) cleared the design and confirmed the
two blockers were fixed (pre-auth cold-start fatal in stats
`switchDevice`; single→multi PageView desync). Two items were judged
not worth changing now:

- **Sign-in re-pointing bypasses the coordinator.** On sign-in the
  registry isn't rebuilt (sign-out wiped prefs + `clear()`), so
  `reactivateAfterSignIn(deviceId)` re-points *geyser only*, not stats.
  No double-application and no cross-account leak (the stale id reads an
  empty/denied path under the new uid); it self-corrects the moment a
  device is added (→ coordinator fans out). Revisit if we ever rebuild
  the registry on sign-in.
- **Launch shows the index-0 device, not the last-used one.**
  Pre-existing registry behaviour; the coordinator now applies it to
  the cubits too. Cosmetic; a "remember last device" feature is
  separate.

## Verify (each step, not just at the end)

- Switch on the dashboard → Settings' scoped section follows.
- Switch in Settings → dashboard PageView jumps, stats + control follow.
- Single-device: no switcher, everything still works.
- Sign out → in as another account: selection resets, no stale device.
- Notifications list pools all devices, each row labelled by device;
  unread badge counts across all devices; switching device does NOT
  change the list.
