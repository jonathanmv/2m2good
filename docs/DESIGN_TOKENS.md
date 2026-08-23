# 2m2better marketing design tokens

The marketing site uses a small, body-aware token system rather than a generic wellness or productivity palette. It keeps the page feeling like a quiet current inside a focused workday: paper and ink for orientation, moss for the resting companion, and one warm orange-to-red signal as a break approaches.

## Source of truth

All raw marketing values live in [`marketing/app/design-tokens.css`](../marketing/app/design-tokens.css). `marketing/app/globals.css` imports that file and consumes its roles. New landing-page sections should use semantic variables from the token file; do not introduce one-off hex, rgba, spacing, radius, shadow, or animation values in component styles.

The old short color aliases in the token file are compatibility aliases for the current page selectors. New work should prefer the semantic names below.

## Usage map

| Role | Use |
| --- | --- |
| `--color-surface-canvas`, `--color-surface-raised`, `--color-surface-action` | page paper, quiet raised surfaces, and primary action surfaces |
| `--color-content-primary`, `--color-content-secondary`, `--color-content-accent` | reading hierarchy and moss emphasis |
| `--color-content-signal`, `--color-content-signal-soft` | the single warm invitation/signal family |
| `--color-border-subtle`, `--border-quiet`, `--border-on-dark` | quiet structure, never dashboard-like card chrome |
| `--font-body`, `--font-display`, `--type-*` | sans-serif interface copy and editorial display copy |
| `--space-*` and `--layout-*` | page gutters, section rhythm, reading widths, card widths, and orb-stage bounds |
| `--radius-*` | pill actions, compact controls, soft cards, and the organic orb stage |
| `--shadow-*` | restrained separation for the orb, check-in, actions, and dialog |
| `--motion-*` | short interaction transitions and slow, purposeful orb movement |

The visual system deliberately has no score, streak, dashboard-card, medical, or urgency-specific token. A selected body area belongs in product copy/content, not in a body diagram or a diagnostic color system.

## Orb proximity contract

The owned mapping is:

- `distant` / `resting` → `--orb-proximity-distant` (moss green)
- `near` / `approaching` → `--orb-proximity-near` (warm orange)
- `imminent` / `due` → `--orb-proximity-imminent` (warm red)

Apply a state class plus `orb-surface` to an orb, or put the state class on a wrapper so its custom properties are inherited:

```tsx
<div className="orb-state-resting">
  <div className="orb-surface" aria-label="The next reset is still a while away" />
</div>
```

Color and motion are supporting cues only. The state must also be communicated by visible text, a label, or an explicit control. The reduced-motion rule in `globals.css` stops orb, halo, and blink animation while retaining the same state colors, labels, focus styles, and controls.

## Brand application

Use the required lowercase user-facing spelling **`2m2better`**. Keep invitations concise and permission-based: the selected area can name a gentle reset for the neck, shoulders, hands + wrists, or lower back, but tokens must not introduce posture correction, pain, treatment, productivity guilt, or medical language. Keep the orb compact and expressive; use the local orb shading only for depth, never as a page-wide competitor-like gradient.
