# GeyserSwitch design language

The visual grammar of the app, as established by the dashboard (focal
card, gauge, timer chips, bottom nav) and to be applied to every new
screen. Tokens live in `lib/presentation/theme/app_colors.dart`;
primitives in `lib/presentation/shared/widgets/neu/`. This doc is the
*rules* — the reasoning that makes new screens come out looking like
the same product.

In one line: **clean and elegant, slightly neomorphic — soft depth
rationed to what you can touch, on one quiet surface, with the logo's
temperature ramp spent exactly once per screen.**

---

## 1. Ground

- One surface per screen: `neuBase` (#E8EBF0) edge to edge for soft-UI
  screens (auth, sheets, focal contexts); `paper` (#EFF1F4) with white
  cards for dense/list screens. Never card-on-card-on-card.
- No decorative gradients. The old auth header's baby-blue gradient
  (`7AD9FF`→`BFEFFF`) predates the system and is retired — those hexes
  exist nowhere in the tokens.
- Hairlines (`hairline`) separate; shadows elevate. Don't use both on
  the same element.

## 2. Depth budget — the "slightly" in slightly neomorphic

Depth is an affordance, not a style. Per screen, only elements the user
can **touch** may have depth, and even then only the few that matter:

| Depth    | Meaning                  | Examples                          |
|----------|--------------------------|-----------------------------------|
| Raised   | "press me" / identity    | primary CTA, logo badge           |
| Inset    | input / committed state  | text-field wells, active nav well, enabled timer chips |
| Flat     | read, don't touch        | labels, links, helper text, legal |

Rule of thumb: **≤ 4 depth elements per screen.** If everything is
soft, nothing is. Raised = `neuRaisedShadows()` (dark `neuShadow`
bottom-right, light `neuHighlight` top-left). Inset = the inner-shadow
pair from `neu.dart`.

## 3. Active is inset

The app's signature inversion, used consistently:

- Bottom nav: the selected destination sits in a **grooved active
  well** (debossed, accent-tinted).
- Timer chips (`_TimeChip`): **enabled = inset + bold**, disabled =
  raised + dull — "committed" reads as embedded into the surface.
- Segmented/mode controls (e.g. Sign in / Create account): a carved
  track where the **active lane is deeper-inset with a bold `primary`
  label**; the inactive lane stays flush and `muted`.
- Buttons **press into** the surface (raised → inset ~90 ms), they
  don't lift.

## 4. Color

- `primary` (teal, #2C8C88) is the only interactive accent: focus
  rings, active labels, carets, the CTA fill (+ its faint glow —
  `rgba(44,140,136,.30)`, same "energized" halo as the focal card).
- The **temperature ramp** (periwinkle→red, the logo arc) is identity,
  not UI. It appears **once per screen at most**: the gauge, the
  savings thermometer, or the logo badge. Never as borders, never as
  decoration.
- Semantic colors (`save`, `warning`, `critical`) are separate from the
  accent and only carry meaning (state, alerts, errors).
- Text hierarchy is `ink` → `inkSecondary` → `muted`. Hierarchy comes
  from these three plus weight — not from extra colors or sizes.

## 5. Inputs & states

- Text fields are **wells carved into the ground** (inset, radius 16,
  height ~54), not boxes floating on it. Hint text `muted`, value `ink`
  at w500, leading icon `muted`.
- Focus: 1.5 px `primary` ring around the well + teal caret; the icon
  may tint teal. Nothing moves.
- Error: ring swaps to `critical`; the message sits **below** the well
  in plain language (never inside it — the typed value stays visible).
- Disabled: contents drop to `muted`; the well stays (affordance
  doesn't vanish, it dims).

## 6. Type & spacing

- Platform faces (SF / Roboto via Flutter defaults) — the softness
  comes from the surface, so type stays neutral and confident.
- Screen title ~27 w700 `ink` (tight -1% tracking), subtitle 14
  `inkSecondary`, controls 14–16 w600–700, helpers/legal 11–12 `muted`.
- Section labels: 11 w700 uppercase with wide tracking (as used on the
  glance tiles).
- Corner radii: 24 panels / 16 wells / full-round pills. Generous
  vertical rhythm; the CTA anchors the bottom with breathing room.

## 7. Motion

- Standard transition ~200 ms easeOutCubic: mode-well slide, form
  crossfades (replaces the old 50 ms hard cut, which reads as flicker).
- Press feedback ~90 ms to inset.
- One orchestrated moment per screen maximum; honour reduced-motion.

## 8. Copy

Plain, specific, second person, no exclamation marks. Controls say what
happens ("Sign in", "Turn on notifications"). Errors say what's wrong
and what to do. The voice established by the sensor-offline dialog is
the reference: calm, factual, reassuring without cheerleading.

---

## Applied: the auth screens

Reference mockup (tokens verbatim): the auth rework artifact. Spec:

- Ground `neuBase`, no header band. Status bar → logo badge → title →
  subtitle → mode well → fields → (spacer) → CTA.
- **Logo badge**: raised disc (~84) containing a grooved ring with the
  7-segment ramp arc + teal droplet — the screen's single ramp moment.
  Reuses the gauge's groove grammar (small `CustomPainter`).
- **Mode well** replaces the toggle text-link: Sign in / Create account
  as a grooved two-lane track (active = deeper inset, bold teal). Makes
  sign-up an explicit lane.
- Fields per §5; "Forgot password?" as a flat `inkSecondary` link,
  sign-in lane only.
- CTA: full-width pill, teal, raised + faint teal glow; pressed =
  inset. Sign-up lane adds the terms line in `muted`.
- Keyboard: the badge collapses/scrolls away so the CTA stays reachable
  on small phones.
- Build from existing parts: `NeuInset`, `neuRaisedShadows()`, the
  `_TimeChip` pattern, `AppTextField` restyled once centrally.
