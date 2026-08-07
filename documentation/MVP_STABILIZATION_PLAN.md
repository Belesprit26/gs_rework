# MVP Stabilization & Release Plan

**Scope:** `gs_rework` (Flutter app) + `gs_firmware` (ESP32-C6, ESP-IDF)
**Goal:** a stable field MVP that can be updated remotely on both sides — firmware via the existing RTDB-manifest OTA, app via Play/App Store staged rollout — with no breaking changes to the app↔firmware BLE contract or the cloud data model.
**Source:** full-code audit (2026-07-30) of both repos: firmware safety logic, firmware connectivity, app↔firmware protocol contract, app data/Firebase layer, and release tooling.

---

## 0. Hardware topology — read this before reasoning about safety

**The relay switches the geyser at the POWER SOURCE (upstream mains). It is not wired to the heating element, and the geyser's own mechanical thermostat is untouched and still fully regulates water temperature.**

Consequences that govern every design decision below:

- **Relay ON = an ordinary geyser**, self-regulating at its factory setpoint. This controller cannot cause runaway heating or a scald.
- **Relay OFF = the geyser has no power** — i.e. no hot water for the customer. Switching off is a *customer-impacting* action, not a "safe" default.
- The DS18B20 provides **monitoring, smart scheduling, and one genuine added protective layer**: when it reads above the user's setpoint (capped at `TEMP_MAX_CEIL` 65 °C, below a typical factory setpoint), cutting mains catches a geyser whose own thermostat has stuck closed.
- **A failed sensor is a loss of visibility, not a hazard.** Degrading toward relay-OFF on sensor failure trades a monitoring fault for a no-hot-water callout — strictly worse. Notify the user; leave the power alone.
- "Max continuous run" is an **energy / left-on-too-long feature**, not a safety cutoff. `0 = Off` is a legitimate user choice firmware must never override.

The original audit (2026-07-30) assumed element-level switching and recommended failing toward relay-OFF; S3/S4 below were implemented on that assumption and **reverted on 2026-07-30** once the topology was confirmed. Anything that reasons "cut the power to be safe" should be re-checked against this section.

---

## 0b. Scheduling model (firmware 0.7.0 / app 1.0.13+)

**Timers switch ON; the run limit switches OFF.** Together they form a complete time-based control loop that needs no sensor — so when the sensor fails the system degrades into time-only control by itself, with no special mode required. The temperature setpoint stays active throughout as a ceiling that can end a block early (it is the layer that catches a stuck geyser thermostat, per §0); it simply stops being the thing that usually ends the block.

**Overlapping slots: the running block wins.** A timer whose time falls inside an active block is ignored — the original allocated duration runs out. The app shows the remaining time so this is visible rather than surprising.

**Block boundaries.** A duration exactly equal to the gap between two slots would end one block at the very moment the next timer fires. Two independent guards: the app's duration presets stop two minutes short of the hour (58 m, 1 h 58 m, 3 h 58 m …), and firmware suppresses any timer firing within 60 s of a run-limit cutoff — so a hand-picked duration is safe too.

**The run window survives a reboot.** The ON-stretch start is stamped as a wall-clock epoch and persisted next to the relay state, so a unit that restarts mid-block resumes the same window instead of restarting it. Falls back to a RAM counter when the clock is unusable.

**Clock-less interval fallback.** The schedule is wall-clock based, so a BLE-only unit that has never been told the time — or one rebooted after an outage with the router still down — would otherwise do nothing. Interval mode then heats on a free-running counter at the *same daily duty the user's own schedule asks for*, preserving their energy budget even though the phase is unknowable. It only stands in when at least one timer is enabled, honours a per-device opt-out, waits 15 minutes after boot, and self-cancels the instant the clock returns — which happens automatically on the next BLE connect, since the app pushes phone time. Surfaced via `EVT_CLOCK_LOST` / `EVT_SCHEDULE_OK` and a dashboard banner.

**Deployment note:** all of this is additive — a new read-only characteristic (`0x0F`) and two new event codes. Old app ↔ new firmware and new app ↔ old firmware both behave as before, and `0x0F` was deliberately kept **off** the RTDB `live` node so this firmware does **not** depend on a security-rules deploy.

---

## 1. Verdict & principles

The codebase is structurally sound: the BLE protocol contract is byte-verified on both sides (UUIDs, endianness, clamps, HMAC owner-auth with a shared RFC 4231 test vector), sync is crash-safe by construction, Firebase rules are deny-by-default and uid-scoped, TLS is enforced everywhere, and OTA uses true A/B partitions. What blocks release is a short list of high-impact defects, most with small fixes.

Every fix in this plan obeys three rules:

1. **Non-breaking protocol.** No change alters a GATT UUID, payload byte layout, status enum, RTDB schema, or NDJSON chunk format. Old app ↔ new firmware and new app ↔ old firmware must keep working during the rollout window.
2. **Remote-updatable from day one.** Firmware ships only after OTA rollback is proven working (flash a deliberately-crashing image; watch it revert). The app ships with Crashlytics symbol upload and staged rollout so a bad release is caught at 10%, not 100%.
3. **Fail visible, not fail-dark.** Where the device must degrade, it degrades toward an event/log a human can see — *not* toward cutting power. Per §0, relay-OFF means no hot water, so it is never the automatic "safe" choice; the geyser regulates itself when powered.

---

## 2–6. Blockers, majors, minors — COMPLETE

Every release-blocker, safety/control-correctness major, app-visible
major, and cloud/ops item from the 2026-07-30 audit is **implemented,
verified and shipped** (firmware v0.7.0, app on `main`, CI green on both
repos). Two items were later **reverted as wrong** once the mains-level
topology in §0 was confirmed — forcing the relay OFF on sensor failure,
and refusing to restore relay-ON after a crash reboot; both would have
traded a non-hazard for a no-hot-water callout. The full per-item record
(B1–B6, S1–S6, U1–U9, C1–C10, the minors, and the adversarial re-review
that caught a tick-overflow blocker, the broken iOS build and an
owner-key leak) lives in the git history.

**What remains** is tracked in `OUTSTANDING.md` (hard gates, deploys,
post-MVP engineering) and `DEFERRED.md` (deferred enhancements,
low-impact known issues). The CI gates that now guard against
regression: app — analyze/test/release-build/version-bump; firmware —
clean build plus a grep gate asserting `BOOTLOADER_APP_ROLLBACK_ENABLE`,
`ESP_TASK_WDT_PANIC` and a 60 s watchdog are on and legacy BLE pairing
is off. That firmware grep gate alone would have caught the original
stale-`sdkconfig` blocker.

**Product risk register (not a code fix):** current sensing is staged
but not built, so the MVP can't detect a welded relay contact or failed
element. Per §0 this is a *functional* gap, not a safety one — a welded
contact leaves an ordinary self-regulating geyser. State plainly in
certification/insurance docs that this controller is not a safety device
and does not replace the geyser's thermostat or TP valve.

## 7. Remote update strategy (steady state)

**Firmware:** publish via existing `tools/publish_firmware.sh` (binary → sha256 → manifest). Staged rollout by pointing a `firmware/beta` manifest at internal units first (additive path; app/firmware ignore unknown paths), then promote to `firmware/latest`. Rollback protection: bootloader auto-revert (B3) + semver anti-downgrade already implemented. Known accepted trade-off (document): the 3-min health confirm runs without requiring cloud connectivity, so a build with a broken cloud stack can self-confirm — mitigated by the staged-manifest soak on internal units.

**App:** Play staged rollout + App Store phased release; Crashlytics with uploaded symbols (C6) as the abort signal; `firebase_remote_config` (already a dependency) for kill switches — minimum: `min_supported_app_version` (paired with the existing `version_check.dart` gate) and a `remote_control_enabled` flag to disable cloud relay control fleet-wide if a defect is found.

**Compatibility rule for every future change:** GATT — additive characteristics only, never re-type or renumber; payloads — length-checked on firmware, so new optional trailing fields are safe; RTDB — additive paths with uid-scoped rules; app must tolerate missing paths (old firmware) and firmware must tolerate absent writes (old app). The existing version characteristic (0x0B) + `version_check.dart` gate is the mechanism for gating new app features on firmware version — keep using it.

---

## 8. Field validation matrix (exit gate for Phase 1, re-run before each release)

Real hardware, both an Android and an iOS phone:

1. Fresh provision, WiFi mode — iOS and Android (proves B4).
2. Fresh provision, BLE-only mode; then add WiFi later.
3. Wrong WiFi password → explicit failure UI → retry with correct password.
4. Kill BLE mid-provisioning (walk away / reboot ESP) → sheet fails within 30 s, retry works (U1).
5. Power-cut the router 5 min, restore → device reconnects, SNTP recovers, timers fire (S5).
6. Power-cut the ESP → relay restores safely; schedule resumes after time sync.
7. Single enabled timer fires on two consecutive days (B2).
8. Thermostat cutoff at max temp; deadband honored (no chatter).
9. Disconnect the DS18B20 while the geyser is powered → **relay stays ON** (geyser keeps running on its own thermostat), `SENSOR_FAIL` event reaches app and RTDB, user is notified, and the app shows "limits paused — sensor offline". Temperature-limits dialog still opens, with the paused banner.
10. **Scheduling (0.7.0):** two timers 2 h apart with a 2-hour duration → two clean blocks, no flap at the boundary (firmware's 60 s guard prevents the immediate re-fire).
11. **Run window across reboot:** start a block, power-cycle mid-block → the app shows the *remaining* time continuing, not a fresh full window.
12. **Interval fallback:** BLE-only unit with timers enabled and no clock (factory-reset or WiFi withheld) → after 15 min it begins cycling at the schedule's duty, `EVT_CLOCK_LOST` fires, and the dashboard shows the clock banner. Connect the app → clock is pushed, `EVT_SCHEDULE_OK` fires, banner clears, normal schedule resumes.
13. **Fallback restraint:** same unit with *no* timers enabled → no cycling at all (manual-only users must not be surprised).
14. OTA: publish test build → fleet updates; publish deliberately-crashing build to one bench unit → auto-rollback (B3).
15. Second phone, same account: connects, unlocks, controls (U2/U9).
16. Sign out → sign in as a different account: no data bleed, no stale FCM alerts (U3).
17. Phone offline (airplane mode) → remote toggle fails cleanly within 10 s, UI recovers (U6).
18. iOS background sync fires (Xcode BGTask debug trigger) and foreground fallback syncs after >24 h (B5).
19. Week-long offline ESP → reconnect → event/telemetry backlog lands in app, ack only after success (U5).
