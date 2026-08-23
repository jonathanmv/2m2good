# 2m2better marketing design tokens

The marketing site uses a small, body-aware token system rather than a generic wellness or productivity palette. The palette was intentionally revisited after the token-adoption pass: the dated competitor pass in [`RESEARCH_2026-08-23-LANDING-POSITIONING.md`](RESEARCH_2026-08-23-LANDING-POSITIONING.md), the four-area product research captured by [`BRAND_DIRECTION.md`](BRAND_DIRECTION.md), and the approved landing structure now inform the colors themselves.

## Palette direction

The competitor pages repeatedly use one promise, a short sequence of product moments, and a prominent download CTA. Their visual conventions also cluster around configurable utility chrome, quantified focus or break behavior, streaks and scores, health-treatment language, and traffic-light urgency. 2m2better borrows only the clarity of that sequence. It deliberately avoids competitor-colored interfaces, generic wellness gradients, medical blue/green visual language, dashboards, notification-red urgency, and productivity-guilt signals.

The new palette is a **tide-and-clay** system: cool mineral blue-green gives the page a quiet current, chalk gives the person room to breathe, and restrained clay and plum add human warmth without turning a reset into an alert. It should feel observant, expressive, and quietly confident rather than clinical, spa-like, athletic, or optimized. The body-area research keeps the invitation specific but non-diagnostic—neck, shoulders, hands + wrists, and lower back—so color supports the choice without assigning a color to a body part or implying a condition.

| Role | Chosen direction | Why it serves the two-minute reset |
| --- | --- | --- |
| Canvas | Cool mist | A low-pressure starting field for every area and every answer, including “not now.” |
| Raised surface | Chalk | Gives the check-in, preview, and developer-preview details a clear, friendly place to land without dashboard cards. |
| Recessed surface | Blue mineral | Creates a quiet change of context around the playable preview without adding a productivity state. |
| Primary content | Deep tide ink | Keeps the promise and body-area copy calm, legible, and grounded. |
| Secondary content | Sea-slate | Lowers visual noise for supporting cues while preserving readable text contrast. |
| Accent | Deep tide | Makes the selected area and permission-based invitation feel alive, not medical or competitive. |
| Borders | Translucent tide ink | Adds orientation and separation as a soft shoreline, never a grid of dashboard chrome. |
| Actions | Deep tide and tidal teal | One clear Start/preview path is easy to see; secondary choices remain quiet and equally valid. |
| Focus | Teal with a chalk contrast halo | Makes keyboard agency visible on both light and dark surfaces without changing layout or motion. |
| Orb progression | Distant teal → near clay → imminent plum | Communicates proximity as a gentle emotional shift, not a green/orange/urgency-red warning system. Copy and controls remain the source of truth for state. |

This is a marketing presentation palette, deliberately not a pixel-identical theme for the shipped macOS app. The website and the app share one idea - proximity reads as a gentle emotional shift, never an alert - but they do not share RGB values, and neither one is the source of truth for the other's colors. The native orb keeps the values in `Sources/BreakCompanion/BreakProgress.swift` documented in [`../README.md`](../README.md); changing the site palette must not be read as a change to the app, and aligning the two is a separate product decision.

Orb shading and halos are local to the orb: small highlights, tinted inset shadows, and soft state halos give the companion its expressive depth without putting a page-wide gradient behind the marketing message. The same distant/near/imminent roles are applied to the hero, floating orb, check-in, preview, privacy, and closing orb surfaces. All text roles on canvas, raised, recessed, action, signal, and dark command surfaces are selected for contrast; color and motion remain supporting cues, with labels and visible controls unchanged.

## Source of truth

All raw marketing values live in [`marketing/app/design-tokens.css`](../marketing/app/design-tokens.css). `marketing/app/globals.css` imports that file and consumes its roles. New landing-page sections should use semantic variables from the token file. The landing page now routes its semantic layout spacing, dimensions, typography, radii, borders, shadows, colors, and motion through named tokens; preserve exact existing values when adding a narrowly scoped role instead of snapping a section to a nearby scale step. Do not introduce a one-off color, radius, shadow, or animation value in component styles.

The old short color aliases in the token file are legacy compatibility aliases that the current page no longer consumes. New work should use the semantic names below.

## Usage map

| Role | Use |
| --- | --- |
| `--color-surface-canvas`, `--color-surface-raised`, `--color-surface-recessed`, `--color-surface-signal` | page mist, quiet chalk/mineral surfaces, and the closing clay field |
| `--color-surface-action`, `--color-content-on-action`, `--color-content-on-signal` | clear actions and contrast-safe text on dark action/clay surfaces |
| `--color-content-primary`, `--color-content-secondary`, `--color-content-accent` | reading hierarchy and deep-tide emphasis |
| `--color-content-signal`, `--color-content-signal-soft` | the clay invitation and its contrast-safe light companion |
| `--color-border-subtle`, `--border-quiet`, `--border-on-dark` | quiet structure, never dashboard-like card chrome |
| `--color-focus-ring`, `--color-focus-ring-contrast`, `--shadow-focus` | keyboard agency that remains visible across light and dark surfaces |
| `--font-body`, `--font-display`, `--font-command`, `--type-*` | sans-serif interface copy, editorial display copy, and the monospace stack of the auditable installer command |
| `--space-*` | page gutters, section rhythm, and every padding, margin, and gap role, including their compact-breakpoint variants |
| `--layout-*` | exact region dimensions, reading/card widths, responsive geometry, and orb-stage bounds |
| `--border-faint`, `--border-card`, `--border-control`, `--border-orbit-path`, `--border-chip` | the exact hairline alphas the existing sections established, so tokenizing a border never shifts its weight |
| `--radius-*` | pill actions, compact controls, soft cards, and the organic orb stage |
| `--shadow-*` | restrained separation for the orb, check-in, preview card, and actions |
| `--motion-*` | short interaction transitions, orb state changes, and slow, purposeful orb movement |
| `--type-*` | display/copy scales plus the smaller navigation, demo, installer, and responsive roles that preserve the current output |

Small detail roles stay one per call site even when they share a value today: `--type-stage-strong-size`, `--type-demo-status-size`, `--type-demo-time-size`, `--type-demo-control-size`, `--type-command-size`, `--type-copy-button-size`, `--type-navigation-compact-size`, and `--type-area-note-compact-size` are all 12px, and `--type-weight-wordmark`, `--type-weight-demo-control`, `--type-weight-privacy-note`, and `--type-weight-copy-invite` are all 700. Retuning the hero orb-stage caption must not resize the auditable installer command or the demo controls, so adjust the role you mean and leave the others alone rather than collapsing them back into one shared name.

The representative landing-page path is: `.hero` uses display and hero rhythm roles; `.areas-grid`/`.area-row` use section, row, and border roles; `.demo-card`/`.demo-orb` use card, control, and orb roles; `.orb-state-*` maps proximity state variables before `.orb-surface` consumes them; `.installer-inner`/`.command-card` use installer spacing, type, border, radius, and shadow roles. The built rendered-output test exercises this map against the emitted CSS rather than only checking source text.

Intentional raw geometry exceptions in `globals.css` are limited to CSS composition values that are clearer in place: fractional grid tracks, percentage-based decorative anchors/stops, full-width/100% constraints, aspect ratios, viewport breakpoints, keyframe percentages, the two organic rotation angles on the hand-placed stage note and check-in window, and `z-index` stacking values. The decorative stage ring's percentage stops and the organic note/orbit anchor percentages are geometry, not reusable design roles; exact pixel dimensions and motion offsets around them are tokenized. The zero/full-width resets remain CSS primitives. Rotation angles and stacking order are local composition, not reusable roles: the system deliberately defines no rotation or layer token, so read a raw `rotate()` or `z-index` in a component rule as intentional rather than as a missed token. The visual system deliberately has no score, streak, dashboard-card, medical, or urgency-specific token. A selected body area belongs in product copy/content, not in a body diagram or a diagnostic color system.

## Orb proximity contract

The owned mapping is:

- `distant` / `resting` → `--orb-proximity-distant` (tidal teal), the state's identity color: it renders the hero caption swatch, `--orb-halo-distant` carries the same hue at low alpha for the halo, and the resting orb surfaces shade from `--orb-resting-light` into the deep tide
- `near` / `approaching` → `--orb-proximity-near` (muted clay)
- `imminent` / `due` → `--orb-proximity-imminent` (quiet plum, deliberately not urgency red)

Apply a state class plus `orb-surface` to an orb, or put the state class on a wrapper so its custom properties are inherited:

```tsx
<div className="orb-state-resting">
  <div className="orb-surface" aria-label="The next reset is still a while away" />
</div>
```

`--orb-shadow-*` is a compact inset shading cue per state, sized for the small orbs. A section that needs its own depth assigns a different complete token on the orb element itself, for example `--orb-surface: var(--orb-surface-near)` plus `--orb-shadow: var(--orb-shadow-near)`. Assign a whole surface or shadow token; do not expect a `:root` token to read a variable set later on the element, because custom properties are substituted where they are declared.

The global focus rule in `globals.css` is written as `:focus-visible:focus-visible` on purpose. The doubled pseudo-class raises its specificity above single-class component rules such as `.button-primary` and `.button-light`, so a component's own resting `box-shadow` can never suppress the chalk contrast halo and leave a focused control with only a low-contrast ring on a dark or clay surface. Keep it doubled, and let the rendered-output test resolve the real cascade for every focusable action rather than only checking that the declaration exists.

Color and motion are supporting cues only. The state must also be communicated by visible text, a label, or an explicit control. The reduced-motion rule in `globals.css` stops orb, halo, and blink animation and freezes the rotating area word behind its static `.area-fallback` list, while retaining the same state colors, labels, focus styles, and controls.

## Brand application

[`BRAND_DIRECTION.md`](BRAND_DIRECTION.md) owns the name and its written form. Keep invitations concise and permission-based: the selected area can name a gentle reset for the neck, shoulders, hands + wrists, or lower back, but tokens must not introduce posture correction, pain, treatment, productivity guilt, or medical language. Keep the orb compact and expressive; use the local orb shading only for depth, never as a page-wide competitor-like gradient. The palette is not a body map: area rotation changes the words and cue, not the color system.
