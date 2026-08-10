# GeyserSwitch — Hardware Roadmap

Last updated: 2026-03-08

---

## Phase 1: Current Prototype (NOW)

**Goal:** Validate core functionality on the existing PCB.

### Hardware fixes on current board

- [x] Bypass F1 fuse holder with jumper wire (temporary, for testing)
- [x] Leave D1 (SMBJ5.0A) unpopulated (safe for bench testing)
- [x] Leave R6 + C4 snubber unpopulated (no mains load yet)
- [x] Fix R4: desolder and bridge pads to give Q2 emitter a direct GND path
- [x] Relay switching confirmed working

### Functional testing

- [ ] Relay toggles via button press (short press)
- [ ] Relay toggles via BLE GATT write from app
- [ ] D3 (green LED) lights when relay is ON, off when OFF
- [ ] DS18B20 temperature sensor reads correctly
- [ ] Thermostat auto-off at max temperature works
- [ ] Leak sensor triggers when water bridges probes (alert path: `documentation/LEAK_ALERT_SPEC.md`)
- [ ] RGB LED shows correct status colours (behaviour spec: `gs_firmware/LED_STATUS_SPEC.md`)
- [ ] BLE advertising and connection stable
- [ ] NVS stores and restores relay state across reboot
- [ ] Factory reset (10s button hold) works
- [ ] UART debug output functional

### Current sensor evaluation

- [ ] Splice ACS712-20A module inline on AC/L output wire
- [ ] Wire module signal (VCC, GND, VOUT) back to main board
- [ ] Add voltage divider (10kΩ + 18kΩ) to scale VOUT for 3.3V ADC
- [ ] Connect to GPIO0 (A0/D0) — currently unused
- [ ] Write firmware driver to read ADC, calculate RMS current
- [ ] Validate readings against multimeter clamp meter
- [ ] Decide: is current sensing worth adding to production BOM?

---

## Phase 2: Pre-Certification PCB Revision

**Goal:** Address all known issues and design for compliance before submitting
to test lab.

### Schematic changes

| Change | Reason |
|--------|--------|
| Move R4 (100kΩ) from Q2 emitter (pin 2) to Q2 base (pin 1) | Base pulldown keeps relay OFF during boot |
| Add direct GND connection to Q2 emitter (pin 2) | Allows full current flow for relay coil |
| Add ACS712-20A-T inline on AC/L (relay NO → AC/L_OUT) | Current sensing for element monitoring |
| Add voltage divider on ACS712 VOUT (10kΩ + 18kΩ) | Scale 0–5V output to 0–3.2V for ESP32 ADC |
| Add 100nF bypass cap on ACS712 VCC | Required by datasheet |
| Add 1nF filter cap on ACS712 FILTER pin | Sets output bandwidth |
| Update R4 BOM description | Was copy-pasted from leak sensor section |
| Populate D1 (SMBJ5.0A) | Required for production surge protection |
| Verify all protection components in BOM | F1, R2, D1, D2, D7, D8 |
| Power D9 (WS2812B RGB) from 5V via a series diode on VDD (→ ~4.3V), or a level shifter on LED_1 | At 3.3V the WS2812B is dim/marginal; at 5V its data V_IH (~3.5V) exceeds the C6's 3.3V GPIO — the diode drop fixes both at once. Confirm R17's role on LED_1 (series damping is fine; a lone resistor can't level-shift). **3.3V for now** — colours calibrated in firmware (`gs_firmware/LED_STATUS_SPEC.md`) |

### PCB layout changes

| Change | Reason |
|--------|--------|
| Rotate XIAO ESP32-C6 so antenna faces board edge | BLE/WiFi range — antenna pointing inward loses 30–60% range |
| Add ground-plane keepout (15mm) under antenna area | Prevents antenna detuning |
| Add routed PCB slot between HV and LV zones | Increases creepage for certification |
| Route ACS712 with wide traces (≥6mm) on IP+/IP- | Carries full mains current |
| Add PCB slot between ACS712 mains pins and signal pins | Creepage for 2.4kV isolation boundary |
| Verify creepage ≥ 8mm at all HV/LV boundaries | SANS 60335 requirement |
| Verify clearance ≥ 6mm at all HV/LV boundaries | SANS 60335 requirement |
| Remove copper pour from all isolation boundaries | Prevents creepage reduction |
| Verify mains trace widths for 20A thermal budget | Temperature rise test will measure this |

### Mechanical / enclosure design

- [ ] Design enclosure (injection moulded for production)
- [ ] Material: ABS or PC, UL94 V-0 rated
- [ ] IP rating: minimum IP20 (ceiling mount), IP44 if near water
- [ ] Strain relief for all wire entry points (cable glands or moulded clamps)
- [ ] Ventilation slots if thermal analysis requires it
- [ ] Mounting features (screw holes, DIN rail clip, or ceiling bracket)
- [ ] Space for rating label
- [ ] Class II double-insulation maintained throughout

### Wire and connector decisions

- [ ] Decide: pre-soldered flying leads vs PCB-mount screw terminals
- [ ] If flying leads: 2.5mm² minimum, heat-shrink on solder joints, strain relief
- [ ] If screw terminals: 16A+ rated, accept up to 4mm² wire
- [ ] Label all wires: L IN, N IN, L OUT, N OUT, Temp, Leak

---

## Phase 3: Certification

**Goal:** Obtain NRCS LOA to legally sell in South Africa.

### Pre-submission

- [ ] Get 2–3 boards professionally assembled (not hand-soldered)
- [ ] Assemble in final production enclosure
- [ ] Prepare documentation package:
  - [ ] Circuit schematic (PDF)
  - [ ] PCB layout with dimensions
  - [ ] Bill of materials with supplier datasheets
  - [ ] Assembly drawing
  - [ ] Wiring diagram for installer
  - [ ] User manual / installation instructions
- [ ] Design rating label with all required markings
- [ ] Book pre-assessment consultation with test lab

### Testing

- [ ] Submit samples to accredited test lab (TÜV SÜD, SABS, or Intertek)
- [ ] Tests performed: hi-pot, creepage/clearance, temperature rise, mechanical, marking
- [ ] Address any findings / non-conformances
- [ ] Retest if required
- [ ] Obtain final test report in IEC format

### LOA application

- [ ] Register company with NRCS (if not already done)
- [ ] Submit LOA application with test report and product documentation
- [ ] Pay application fee (R2,045.55)
- [ ] Wait for LOA issue (30–120 days)
- [ ] Add LOA number to rating label for production units

**Budget:** R15,000–R30,000 total (testing + NRCS fees).

---

## Phase 4: Production

**Goal:** Manufacture and sell.

- [ ] Finalise BOM with production suppliers (DigiKey, LCSC, local)
- [ ] Order PCBs with assembly (JLCPCB, PCBWay, or local)
- [ ] Order enclosures (injection moulding tooling if volume justifies)
- [ ] Establish QC process: visual inspection, functional test, hi-pot spot-check
- [ ] Create installation guide for electricians
- [ ] Package: unit + leak sensor probe + temp sensor + cable + installation guide
- [ ] Set up warranty and returns process

---

## Component Summary (Production BOM Additions)

| Ref | Part | Purpose | Est. Cost |
|-----|------|---------|-----------|
| U3 | ACS712ELCTR-20A-T (SOIC-8) | AC current sensing | ~R20 |
| C_acs_byp | 100nF ceramic (0805) | ACS712 VCC decoupling | ~R1 |
| C_acs_filt | 1nF ceramic (0603) | ACS712 output filter | ~R1 |
| R_div1 | 10kΩ (0603) | Voltage divider high side | ~R1 |
| R_div2 | 18kΩ (0603) | Voltage divider low side | ~R1 |
| R4 | 100kΩ (0603) — moved to base | Q2 base pulldown | ~R2 |
| D1 | SMBJ5.0A | 5V TVS (must populate for prod) | ~R5 |

**Additional BOM cost for current sensing: ~R26 per unit.**
