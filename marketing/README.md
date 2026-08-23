# 2m2better marketing page

The self-contained local landing page for 2m2better. Its visual and copy
direction comes from [`../docs/BRAND_DIRECTION.md`](../docs/BRAND_DIRECTION.md),
and its reusable visual contract is documented in
[`../docs/DESIGN_TOKENS.md`](../docs/DESIGN_TOKENS.md).

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

`npm test` creates a production build and verifies that the rendered page keeps
the approved product promise, privacy language, and token contract. The page
is local-only; it does not use accounts, analytics, or network services.

The design-token source of truth is `app/design-tokens.css`; new sections should
consume its semantic roles rather than copying raw values into component styles.
