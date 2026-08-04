# Outstanding work — MVP rollout

Working checklist of everything not yet done, as of 2026-08-05.
Background and rationale live in `MVP_STABILIZATION_PLAN.md`; this file
is the tracker.

All audit-identified blockers, safety majors, app majors and cloud/ops
items are **implemented, verified and pushed**. What remains is grouped
by what actually blocks it.

---

## 1. Hard gates — cannot ship without these

These need physical hardware or a real device build. Nothing in the
development toolchain can substitute.

- [ ] **OTA rollback proof.** Flash v0.7.0 to a bench unit, publish a
      deliberately broken build to it, confirm the bootloader reverts
      on its own. This converts "the anti-brick setting is enabled"
      into "we have watched it save a unit". **No firmware may go out
      over the air before this passes.**
- [ ] **iOS Xcode build + device install.** Highest-uncertainty area in
      the project: an `import workmanager` vs `workmanager_apple`
      mismatch survived an entire session of checks because nothing in
      CI or the local toolchain compiles Swift. Assume more may be
      hiding behind it.
- [ ] **Field validation matrix** — 19 scenarios in
      `MVP_STABILIZATION_PLAN.md` §8. Highest value:
  - [ ] Fresh provisioning on a **real iPhone** (proves the MTU /
        long-write fix; this failed for essentially every iPhone before)
  - [ ] A single enabled timer firing on **two consecutive days**
  - [ ] Disconnect the temperature sensor while the geyser is powered →
        relay must **stay on**, user notified, limits show as paused
  - [ ] Sign out → sign in as a **different account** → no data bleed,
        no stale notifications
  - [ ] **Interval fallback** (re-test after the tick-overflow fix): one
        timer + default limit should give a ~20 h off period, not ~8 h
  - [ ] Manual-only user (no timers enabled) with no clock → **no**
        surprise cycling

---

## 2. Deploys and console settings

- [ ] **Orphaned `sendPushToUser`** exists in production with no source
      and no references in the current or legacy codebases. A full
      `firebase deploy --only functions` will want to delete it and
      aborts until this is decided. Needs an explicit call.
- [ ] **Full functions sync.** Only `createDeviceToken` and
      `onDeviceEvent` are currently redeployed. Because deploys were
      silently broken (see §5), the remaining functions in production
      may be stale relative to the repo. Resolve the orphan, then
      deploy everything and diff behaviour.
- [ ] **Node.js 20 runtime is deprecated** — decommissioned
      **2026-10-30**, after which functions cannot be deployed at all
      without upgrading. Also `firebase-functions` is flagged outdated
      with known breaking changes on upgrade. Do this well before the
      deadline, not during an incident.
- [ ] **Remote Config standing-loss values** (optional): defaults ship
      as 1.6 / 2.2 / 2.8 kWh per 24 h for 100/150/200 L tanks. Override
      in the console once metered data exists — no app release needed.

**Already done:** RTDB rules deployed and verified (legacy fleet of 35
households intact on `/GeyserSwitch/<uid>`); `createDeviceToken` and
`onDeviceEvent` deployed.

---

## 3. Product decisions needed before building

- [ ] **Boost control** ("run for 1 h / 2 h / 3 h now"). Needs its own
      one-shot duration — it cannot safely reuse the global run limit,
      because temporarily rewriting that value is racy. Small firmware
      field plus app UI; the open question is precedence against an
      active schedule block.
- [ ] **Time-mode framing** (Temperature / Time / Both). Not a real
      firmware mode any more: the setpoint always applies as a ceiling,
      so this is an app-level preset that parks max-temp at 65 °C and
      leans on timers. Decide whether it is worth the extra concept.
- [ ] **Per-slot timer durations.** The only remaining piece that needs
      a **protocol change** (timer payload 4 → 5 bytes per slot, via a
      new characteristic with fallback). Deliberately deferred: with a
      healthy sensor the setpoint usually ends a block long before the
      duration does, so per-slot precision only matters in time-only
      mode. Ship the global duration, wait for evidence customers want
      more.

---

## 4. Post-MVP engineering

- [ ] **Tier 2 energy model.** Firmware accumulates the sum of positive
      temperature deltas per day → true calorimetry
      (`kWh ≈ ΣΔT⁺ × litres × 4.186 / 3600`), ±10% instead of a
      standing-loss estimate. ~25 lines firmware, one additive RTDB
      field, rules line, app maths.
- [ ] **Secure boot + flash encryption.** Runbook already written
      (`SECURE_BOOT.md`). Until then: OTA images are unsigned (RTDB
      manifest + sha256 is the trust root) and the WiFi PSK, Firebase
      refresh token and owner key sit in plaintext NVS.
- [ ] **Signed OTA images** — pairs with the above.
- [ ] **BLE / provisioning integration tests.** Still the largest
      coverage gap: the riskiest paths have no automated coverage and
      are only ever exercised by a human with a device. Needs a fake
      transport.
- [ ] **Current sensing** (`current_sense.c` is staged but not built).
      Would give welded-relay and failed-element detection, and ground
      truth for energy. Functional gap, not a safety one — a welded
      contact leaves an ordinary self-regulating geyser.
- [ ] **`cy` stat is mislabelled** — it increments once per hourly
      stats push, not per relay cycle. Either relabel in the UI or
      count real transitions in firmware.
- [ ] **Dependency freshening**: flutter_bloc 8→9, get_it 7→8,
      sqlite3_flutter_libs 0.5→0.6.

---

## 5. Known-and-accepted risks (documented, not scheduled)

- **This controller is not a safety device.** It switches mains
  upstream of the geyser's own mechanical thermostat, which remains the
  temperature regulator. See `MVP_STABILIZATION_PLAN.md` §0 before
  reasoning about any failure mode.
- **BLE pairing is Just Works**, so an active MITM during the one-time
  provisioning window could capture the WiFi password, refresh token
  and owner key. Legacy pairing is disabled (SC-only), which closes the
  passive-sniffing case.
- **Setup-mode first-claim**: an unprovisioned or factory-reset device
  is open to whoever claims it first. Keep the setup window short.
- **Owner key is stored in SharedPreferences**, not secure storage.
- **Legacy fleet constraints — do not violate:** Storage `firmware/**`
  must stay publicly readable (legacy ESP units download OTA
  unauthenticated), and the `sendNotification` /
  `sendNotificationFromESP32` compat functions must stay deployed until
  every fielded legacy unit is replaced.
- **Functions deploys were silently failing** until 2026-08-05 (a
  reserved `FIREBASE_` prefix in `functions/.env`). Treat any
  "fixed in functions/index.js" claim predating that as unverified in
  production until re-checked.
