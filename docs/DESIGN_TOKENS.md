# 2m2better marketing design tokens

The marketing site uses a small, body-aware token system rather than a generic wellness or productivity palette. It keeps the page feeling like a quiet current inside a focused workday: paper and ink for orientation, moss for the resting companion, and one warm orange-to-red signal as a break approaches.

## Source of truth

All raw marketing values live in [`marketing/app/design-tokens.css`](../marketing/app/design-tokens.css). `marketing/app/globals.css` imports that file and consumes its roles. New landing-page sections should use semantic variables from the token file. The landing page now routes its semantic layout spacing, dimensions, typography, radii, borders, shadows, colors, and motion through named tokens; preserve exact existing values when adding a narrowly scoped role instead of snapping a section to a nearby scale step. Do not introduce a one-off color, radius, shadow, or animation value in component styles.

The old short color aliases in the token file are legacy compatibility aliases that the current page no longer consumes. New work should use the semantic names below.

## Usage map

| Role | Use |
| --- | --- |
| `--color-surface-canvas`, `--color-surface-raised`, `--color-surface-action` | page paper, quiet raised surfaces, and primary action surfaces |
| `--color-content-primary`, `--color-content-secondary`, `--color-content-accent` | reading hierarchy and moss emphasis |
| `--color-content-signal`, `--color-content-signal-soft` | the single warm invitation/signal family |
| `--color-border-subtle`, `--border-quiet`, `--border-on-dark` | quiet structure, never dashboard-like card chrome |
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

- `distant` / `resting` → `--orb-proximity-distant` (moss green), the state's identity color: it renders the hero caption swatch, `--orb-halo-distant` carries the same moss hue at low alpha for the halo, and the resting orb surfaces shade from `--orb-resting-light` into `--color-pigment-moss-deep`
- `near` / `approaching` → `--orb-proximity-near` (warm orange)
- `imminent` / `due` → `--orb-proximity-imminent` (warm red)

Apply a state class plus `orb-surface` to an orb, or put the state class on a wrapper so its custom properties are inherited:

```tsx
<div className="orb-state-resting">
  <div className="orb-surface" aria-label="The next reset is still a while away" />
</div>
```

`--orb-shadow-*` is a compact inset shading cue per state, sized for the small orbs. A section that needs its own depth assigns a different complete token on the orb element itself, for example `--orb-surface: var(--orb-surface-near)` plus `--orb-shadow: var(--orb-shadow-near)`. Assign a whole surface or shadow token; do not expect a `:root` token to read a variable set later on the element, because custom properties are substituted where they are declared.

Color and motion are supporting cues only. The state must also be communicated by visible text, a label, or an explicit control. The reduced-motion rule in `globals.css` stops orb, halo, and blink animation and freezes the rotating area word behind its static `.area-fallback` list, while retaining the same state colors, labels, focus styles, and controls.

## Brand application

[`BRAND_DIRECTION.md`](BRAND_DIRECTION.md) owns the name and its written form. Keep invitations concise and permission-based: the selected area can name a gentle reset for the neck, shoulders, hands + wrists, or lower back, but tokens must not introduce posture correction, pain, treatment, productivity guilt, or medical language. Keep the orb compact and expressive; use the local orb shading only for depth, never as a page-wide competitor-like gradient.
