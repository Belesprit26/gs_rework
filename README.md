# GeyserSwitch

Companion app for the GeyserSwitch smart geyser (water-heater) controller.
The app talks to an ESP32-C6 device over **BLE** for local control and
provisioning, and over **WiFi → Firebase** for remote control, telemetry
and alerts.

- **App** (this repo): Flutter, clean-architecture layers under `lib/`
  (`core` / `data` / `domain` / `presentation`).
- **Firmware**: separate repo `gs_firmware` (ESP-IDF).

The device switches the geyser at the **mains**, upstream of the geyser's
own mechanical thermostat — it is an energy/scheduling controller, not a
safety device. See `documentation/MVP_STABILIZATION_PLAN.md` §0.

## ⚠️ Licence — this is not open source

The source is published so people can read it and try it out. That is the
whole of the permission granted.

**You may** read the code, and build and run it privately to evaluate it.

**You may not** use it commercially, redistribute it in source or compiled
form, publish a build to any app store, offer it as a service, distribute
modified versions, or use it as machine-learning training data.

[LICENSE](LICENSE) governs; the summary above is not a substitute for
reading it. Section 5 covers safety and liability — this app controls
mains electricity, and nothing here is certified against any electrical
safety standard. Not accepting contributions: see
[CONTRIBUTING.md](CONTRIBUTING.md).

## Running

```bash
flutter pub get
flutter run          # a real device is best — BLE needs hardware
```

Requires a JDK 17 toolchain for the Android build (`flutter config
--jdk-dir <android-studio>/jbr/Contents/Home` if your system default is
newer). iOS needs `pod install` in `ios/` after dependency changes.

## Documentation

Project docs live in [`documentation/`](documentation/):

| Doc | What it is |
|-----|------------|
| `MVP_STABILIZATION_PLAN.md` | The canonical reference: hardware topology (§0), the scheduling model (§0b), remote-update strategy, and the field-validation matrix. |
| `OUTSTANDING.md` | Live tracker of what's left before/around release. |
| `DEFERRED.md` | Deliberately-deferred enhancements and low-impact known issues. |
| `DESIGN_LANGUAGE.md` | The app's visual grammar (soft-UI depth budget, tokens, states). |
| `MULTI_DEVICE_SYNC_PLAN.md` | How device selection stays in sync across screens. |
| `HARDWARE_ROADMAP.md` | PCB revisions, current-sense evaluation, certification path. |
| `CERTIFICATION_GUIDE.md` | NRCS / SANS 60335 compliance reference. |

Firmware build/secure-boot docs live in the `gs_firmware` repo.
