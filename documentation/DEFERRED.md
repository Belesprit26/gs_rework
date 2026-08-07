# Deferred items & backlog

Things consciously **not** done now — low-impact known issues, and
future enhancements to build on. Distinct from `OUTSTANDING.md` (the
MVP-rollout hard gates) and the design/plan docs. When one of these is
picked up, move it out of here into a real plan.

---

## Future enhancements (build-on)

### Per-device theme colour
Each geyser carries a slightly different accent colour, applied
app-wide, so switching device is obvious everywhere at a glance. Its
own design + plumbing job: a per-device accent token threaded through
the theme, the gauge, chips, the CTA, and the notification device
labels. The seams are already in place — device identity flows through
`DeviceRegistryCubit` — so it drops in without restructuring. Depends
on the multi-device sync foundation (done).

### "Remember last device" on launch
The app opens on the registry's index-0 device (arbitrary order of
`getAllDeviceMappings`), not the one you used last. Persist and restore
the last-selected device. Small; pairs naturally with the per-device
theme work.

### Snackbar design pass
Consistent snackbar treatment in the design language. First real use:
explaining that a run-limit block ends ~2 minutes before the hour so
the next scheduled block starts cleanly (the whole-hour presets hide
the `:58` detail; the snackbar is where it gets said if needed).

---

## Low-impact known issues (correct-but-imperfect)

### Sign-in re-pointing bypasses the coordinator
On sign-in the registry isn't rebuilt (sign-out wiped prefs +
`clear()`), so `reactivateAfterSignIn(deviceId)` re-points geyser only,
not stats. No double-application, no cross-account leak (a stale id
reads an empty/denied path under the new uid); it self-corrects the
moment a device is added. Fix if we ever rebuild the registry on
sign-in. (Audit 2026-08-08, finding 5.)

### `cy` stat mislabel
The daily `cy` value increments once per hourly stats push, not per
relay cycle. Either relabel in the UI or count real transitions in
firmware. (Also noted in `OUTSTANDING.md`.)
