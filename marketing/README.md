# 2mintogood marketing page

The self-contained local landing page for Break Companion. Its visual and copy
direction comes from [`../docs/BRAND_DIRECTION.md`](../docs/BRAND_DIRECTION.md).

## Run locally

Requires Node.js 22.13 or newer.

```bash
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000). If that port is occupied,
the terminal will print the alternate local address.

## Validate

```bash
npm run lint
npm test
```

`npm test` creates a production build and verifies that the rendered page keeps
the approved product promise and privacy language. The page is local-only; it
does not use accounts, analytics, or network services.
