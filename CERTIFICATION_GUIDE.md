# GeyserSwitch — Certification & Compliance Guide

Last updated: 2026-03-08

## 1. Applicable Standards

The GeyserSwitch is a mains-connected household appliance that switches a geyser
heating element (230 VAC, up to 20 A). The following South African and international
standards apply:

| Standard | Title | Relevance |
|----------|-------|-----------|
| **SANS 60335-1** | Safety of household and similar electrical appliances — General requirements | Primary safety standard for the product |
| **SANS 60335-2-xx** | Particular requirements (specific appliance part, TBD by test lab) | May apply depending on classification |
| **VC 8055** | Compulsory specification for safety of electrical apparatus | NRCS compulsory specification |
| **VC 8003** | Compulsory specification for switches for fixed installations | May apply if classified as a switch |
| **IEC 60335-1** | International equivalent of SANS 60335-1 | Test reports in IEC format are accepted |
| **SANS 62368-1** | Audio/video, IT and communication technology equipment — Safety | May apply to the BLE/WiFi module aspects |

> **Note:** The exact applicable parts will be confirmed by the accredited test lab
> during initial consultation. Engage with them early to clarify classification.

---

## 2. NRCS Letter of Authority (LOA)

### What is it?

An LOA is a mandatory document issued by the National Regulator for Compulsory
Specifications (NRCS) that certifies the product meets South African safety and quality
standards. Without a valid LOA, the product **cannot legally be sold** in South Africa
and may be impounded by customs.

- Valid for **3 years** from issue date
- **Not transferable** between entities
- Must be renewed before expiry

### Process overview

| Step | Action | Timeline | Est. Cost |
|------|--------|----------|-----------|
| 1 | Design product for compliance | Ongoing | Internal |
| 2 | Engage accredited test lab for pre-assessment | 1–2 weeks | Free–R5,000 |
| 3 | Submit samples for formal testing (2–3 units) | 2–3 weeks for draft report | R10,000–R22,000 |
| 4 | Address findings and retest if needed | 1–4 weeks | Varies |
| 5 | Register company with NRCS | 1–2 weeks | ~R2,000 |
| 6 | Apply for LOA with final test report | 30–120 days | R2,045.55 |
| 7 | LOA issued | — | — |

**Total budget estimate:** R15,000–R30,000 (testing + fees, excluding redesign costs).

### Accredited test labs in South Africa

- **TÜV SÜD** — Johannesburg (electrical safety for appliances)
- **SABS** — Pretoria (South African Bureau of Standards)
- **Intertek** — various locations
- **SGS** — Johannesburg

All labs must be ILAC-accredited or IECEE CB Scheme members. A CB test report
from any member lab worldwide is accepted by NRCS.

### Required documentation for LOA application

- Full safety test report in IEC format (English)
- Product photographs: rating label, front, rear, internal views, PCB
- Wiring/circuit diagram
- Bill of materials
- Company registration documents
- Test report must be **less than 3 years old**

---

## 3. What the Test Lab Will Evaluate

### 3.1 Dielectric Strength (Hi-Pot Test)

**What:** 1500 VAC (or 2121 VDC) applied between all mains-connected circuits and
all low-voltage/SELV circuits for 60 seconds.

**Pass criteria:** No insulation breakdown, no flashover.

**Design implications:**
- All HV-to-LV boundaries must withstand this voltage
- Critical areas: IRM-03-5 isolation boundary, LTV-354T optocoupler, ACS712 (if added)
- PCB slots between HV and LV zones help

### 3.2 Creepage and Clearance Distances

**What:** Physical measurement of shortest distances between mains-voltage conductors
and low-voltage/accessible conductors.

| Parameter | Minimum (230 VAC, Pollution Degree 2) |
|-----------|---------------------------------------|
| **Clearance** (shortest air path) | ≥ 6.0 mm |
| **Creepage** (shortest surface path) | ≥ 8.0 mm |

**Critical measurement points on the GeyserSwitch PCB:**

| Location | Between | Check |
|----------|---------|-------|
| IRM-03-5 module | AC input pins ↔ 5V output pins | Measure across the module boundary |
| U1 (LTV-354T) optocoupler | Pins 1,2 (LED/mains side) ↔ Pins 3,4 (signal side) | Measure on PCB pads |
| K1 relay (T9GS1L14-5) | Coil pins (A1,A2) ↔ Contact pins (COM,NO) | Measure across relay footprint |
| ACS712 (if added) | Pins 1-4 (mains) ↔ Pins 5-8 (signal) | Measure on PCB, add slot if tight |
| Board boundary | HV zone edge ↔ LV zone edge | Measure at narrowest point |

**How to improve creepage:**
- Route slots/cutouts in the PCB between HV and LV zones
- Remove copper pour from isolation boundaries
- Increase board size if distances are too tight

### 3.3 Protective Devices

**What:** Verification that overcurrent, overvoltage, and surge protection are present
and correctly rated.

| Component | Purpose | Requirement |
|-----------|---------|-------------|
| F1 (0.4A fuse) | Overcurrent protection for PSU input | Correct rating, breaking capacity |
| R2 (7MOV) | Mains surge suppression | Appropriate clamping voltage |
| D1 (SMBJ5.0A) | 5V rail transient protection | Must be populated for production |
| D2 (1N4007) | Relay flyback protection | Correct polarity, adequate voltage rating |

### 3.4 Temperature Rise Test

**What:** Product operates at rated load (e.g., 3 kW geyser element) for extended
period. Thermocouples measure component temperatures.

**Components that will be monitored:**
- Relay contacts (K1) — must not exceed relay's rated temperature
- PCB traces carrying mains current — 6 mm wide, double-sided copper must handle 20 A
- IRM-03-5 power supply — check case temperature
- ACS712 (if added) — IP pins carry full load current
- Enclosure surfaces — must not exceed limits for accessible parts

**Design implications:**
- Ensure copper weight and trace widths are adequate for rated current
- Consider 2 oz copper for mains-current traces if 1 oz is marginal
- Provide ventilation in the enclosure if needed

### 3.5 Earth Continuity / Insulation Class

**What:** Since the GeyserSwitch has no earth/ground connection, it must be classified
as **Class II (double insulated)**.

**Requirements for Class II:**
- Two layers of insulation between mains and any accessible part
- Enclosure must provide supplementary insulation even if one layer fails
- Marked with the Class II symbol (double square) on the rating label
- No reliance on earth for safety

### 3.6 Mechanical and Enclosure Tests

| Test | What | Requirement |
|------|------|-------------|
| **IP rating** | Ingress protection against water and solids | Minimum IP20 for indoor ceiling mount; IP44+ if exposed to drips |
| **Impact test** | Mechanical strength of enclosure | Must withstand specified impact energy without exposing live parts |
| **Strain relief** | Wires pulled with specified force | Solder joints must not be stressed; clamps/glands required |
| **Flammability** | Enclosure and PCB material | PCB: FR4 (V-0 rated). Enclosure: UL94 V-0 or V-1 minimum |

### 3.7 Marking Requirements

The product must carry a **permanent, legible** rating label with:

- Manufacturer name or trademark
- Model number
- Rated voltage: 230 V ~
- Rated frequency: 50 Hz
- Rated current: 20 A (or actual max)
- Protection class symbol (Class II: ☐☐)
- Country of origin
- NRCS LOA number (after approval)

### 3.8 EMC (Electromagnetic Compatibility)

While not always part of the LOA for safety, EMC compliance may be required:

| Standard | Scope |
|----------|-------|
| SANS 55014-1 | EMC — Emissions for household appliances |
| SANS 55014-2 | EMC — Immunity for household appliances |

**Relevant to:**
- Relay switching (arc EMI — mitigated by RC snubber R6+C4)
- ESP32-C6 BLE/WiFi radio emissions
- IRM-03-5 conducted emissions

---

## 4. Key Design-for-Certification Checklist

Use this during PCB layout review before submitting for testing:

- [ ] Creepage ≥ 8 mm at every HV/LV boundary (measure in KiCad)
- [ ] Clearance ≥ 6 mm at every HV/LV boundary
- [ ] PCB slots routed between HV and LV zones
- [ ] No copper pour crossing HV/LV boundaries
- [ ] All protection components populated (F1, R2, D1, D2, D7, D8)
- [ ] RC snubber (R6 + C4) uses X2-rated cap and 1W+ resistor
- [ ] Strain relief designed into enclosure for all wire entries
- [ ] Enclosure material is UL94 V-0 or V-1
- [ ] Rating label designed with all required information
- [ ] Double insulation maintained throughout (Class II)
- [ ] Mains trace widths verified for rated current at operating temperature
- [ ] Component temperature ratings exceed expected operating temperatures
