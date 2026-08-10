# Bench + app test checklist — this development cycle

Everything built or changed this cycle that needs validating on a real
device / real hardware before it's trusted in the field. Run a section at a
time. The **core system** scenarios (provisioning, scheduling, sensor-fail,
sign-out, OTA rollback…) live in `MVP_STABILIZATION_PLAN.md` §8 — this doc is
the *new* work on top of that.

Legend: `(HW)` needs the new PCB / LED / leak hardware · `(deploy)` needs a
Firebase deploy or a test-publish first.

---

## 1. App — Settings tab (H1)

- [ ] Settings tab renders on `paper`; all sections present (Alerts at top,
      This geyser, Devices, Account, About).
- [ ] Device switcher in the "This geyser" label appears only with 2+
      devices; picking a device fans out (stats + control + dashboard swipe
      all follow).
- [ ] Geyser setup dialog saves per-device (tank / element / rate /
      household).
- [ ] Max continuous run: card is collapsed to title + description; tap
      expands the chips; picking one writes it and folds shut; 2 h shows the
      recommended star.
- [ ] About shows app version (always) and firmware version over BLE
      ("Bluetooth required" on WiFi/remote).
- [ ] Sign out (Account) confirms, tears down, and on next sign-in there's no
      data / notification bleed (pairs with §8 sign-out test).

## 2. App — Heat-for-a-time + 70 °C ceiling

- [ ] Temperature tile → dialog opens with the "Heat to a temperature | Heat
      for a time" toggle.
- [ ] Max slider now reaches **70 °C**; set 66–70 and Save → it **sticks**
      (doesn't snap back to 65) — proves firmware + RTDB rule accept 70.
- [ ] "Heat for a time": chips set the run limit; Save parks max at 70 +
      auto-reheat off; glance tile reads "Timed · Xh".
- [ ] Flip back to "Heat to a temperature" → the previous max + auto-reheat
      are restored.
- [ ] Time-mode persists per device, survives an app restart, and a
      different device shows its own mode.
- [ ] Device behaviour in time mode: the geyser runs across the timer window /
      run-limit and does **not** cut early at the old setpoint. `(HW)`

## 3. App — notifications & multi-device (earlier this cycle)

- [ ] Pooled notifications from multiple devices show, differentiated by
      device; the device filter works.
- [ ] Unread badge counts are correct; muted types don't badge.
- [ ] Add a 2nd device; switching/swiping updates stats + control +
      notifications consistently.

## 4. Device — 70 °C ceiling end-to-end `(HW)`

- [ ] Set max = 70 in app → device honours it; thermostat cutoff at ~70,
      deadband respected (no chatter).
- [ ] Legacy Orange untouched: a legacy unit's settings still read/write fine
      (spot-check one). The `max ≤ 70` rule is already deployed.

## 5. OTA — sha256 integrity gate `(deploy)`

- [ ] Publish a real update → device downloads, log shows **"OTA sha256
      verified"**, update applies and boots.
- [ ] Tamper test: publish a manifest whose `sha256` doesn't match the binary
      → device logs "sha256 mismatch — reverting" and **keeps the old
      firmware running** (not bricked).
- [ ] Old-manifest test: a manifest with no `sha256` still updates
      (backward-compatible skip).

## 6. OTA — token-gated firmware path `(deploy)`

- [ ] `firebase deploy --only storage` (adds `/firmware_gs/` read:false).
- [ ] Test-publish → device downloads the binary via the tokenised URL.
- [ ] Plain URL denied: `GET …/firmware_gs/…bin?alt=media` **without** the
      token → **403** (binary not publicly downloadable).
- [ ] Legacy still public: `GET …/firmware/…` (legacy path) still returns 200
      (Orange OTA unaffected).

## 7. OTA — B1 signed images `(deploy, once B1 is on)`

- [ ] Device **accepts** a firmware signed with the project key and applies
      it.
- [ ] Device **rejects** an unsigned or wrong-key-signed image and keeps
      running.
- [ ] Rollback still works under signing (a crashing signed build reverts).

## 8. Hardware — RGB status LED `(HW)`

- [ ] **First build:** `led.c` compiles — confirm the `led_strip` version
      (2.x `.led_pixel_format` / `.led_model` vs 3.x `.color_component_format`)
      and that its RMT channel allocates alongside the DS18B20 OneWire.
- [ ] 3.3 V colour check: all states legible (white / blue / green / amber /
      red); if green/blue skew, calibrate the firmware white-balance.
- [ ] Resting: unprovisioned = white; BLE connected = blue; cloud online =
      green; provisioned-offline = amber. Relay ON = breathe, OFF = steady.
- [ ] Provisioning: white breathe → green blink (connecting) → settles; wrong
      WiFi password → red blink.
- [ ] Button: LED blacks out on press; short-press toggle → white-green-white
      (on) / white-red-white (off); hold 5–10 s → red strobe; 8–10 s → solid
      red; 10 s → wipe flashes then boots to white (setup).
- [ ] OTA overlay (if built): cyan pulse during an update.

## 9. Water-leak alert

- [ ] **Cut + latch `(HW)`:** bridge the probes (>2 s) → `EVT_LEAK` fires
      **once**, relay cuts; the **schedule and auto-reheat can't re-power it**
      (leave a timer due / temp below min → stays off). Confirm probe polarity
      (flip `LEAK_WET_LEVEL` if inverted).
- [ ] **User override `(HW)`:** while still wet, turn it on from the **button**
      and from the **app** — both succeed and resume normal running; **no
      repeat alert/cut** while it stays wet.
- [ ] **Re-arm `(HW)`:** dry the probes (>10 s) → `EVT_LEAK_CLEAR`; re-wetting
      now triggers a fresh alert/cut (it didn't while continuously wet).
- [ ] **Debounce `(HW)`:** a brief splash / condensation does **not** trigger.
- [ ] **App:** critical, non-silenceable notification (live BLE / FCM push);
      once built, a "still wet" banner that clears on `EVT_LEAK_CLEAR`.

## 10. Core system scenarios

- [ ] Run the 19-scenario field-validation matrix in
      `MVP_STABILIZATION_PLAN.md` §8 (provisioning, scheduling, sensor-fail,
      interval fallback, sign-out, OTA rollback, second phone, etc.).

---

## Deploys / publishes for the testing round

- [ ] `firebase deploy --only storage` — the `/firmware_gs/` rule.
- [ ] Test-publish firmware via `tools/publish_firmware.sh` (token flow).
- [x] `firebase deploy --only database` — the `max ≤ 70` rule (already done).
