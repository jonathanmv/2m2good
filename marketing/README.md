# 2m2better marketing page

The self-contained local landing page for 2m2better. Its visual and copy
direction comes from [`../docs/BRAND_DIRECTION.md`](../docs/BRAND_DIRECTION.md),
its reusable visual contract is documented in
[`../docs/DESIGN_TOKENS.md`](../docs/DESIGN_TOKENS.md), and the dated
competitor pass behind the current page structure is recorded in
[`../docs/RESEARCH_2026-08-23-LANDING-POSITIONING.md`](../docs/RESEARCH_2026-08-23-LANDING-POSITIONING.md).

## Run the local preview

Requires Node.js 22.13 or newer.

```bash
npm install
npm run build
npm run start -- --host 127.0.0.1 --port 3000
```

Keep that terminal open, then visit
[http://127.0.0.1:3000](http://127.0.0.1:3000). The preview is available only
while the server process is running.

For live editing with automatic refresh, use `npm run dev` instead.

## Validate

```bash
npm run lint
npm run typecheck
npm run build
npm test
```

`npm test` creates a production build and asserts against the rendered HTML and
the built CSS: the rotating hero area word and its static fallback, the
click-only bounded preview and its controls, the single copy-to-clipboard
`curl | sh` installer command (which it also runs against stubbed
`curl` and `sh`), the privacy language, and the lowercase wordmark. It
also parses the emitted CSS to prove the hero, problem/benefits/flow grids,
demo, orb states, installer, and reduced-motion rules resolve through declared
design tokens, to measure the palette's text, focus, and orb-proximity
contrast from the resolved token values, and to replay the real cascade so
every rendered action keeps the focus ring and its contrast halo. The page is
local-only; it does not use accounts, analytics, or network services.

The design-token source of truth is `app/design-tokens.css`;
[`../docs/DESIGN_TOKENS.md`](../docs/DESIGN_TOKENS.md) owns the usage map and
the rules for adding a role.
