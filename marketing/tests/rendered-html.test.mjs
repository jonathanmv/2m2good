import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the 2M2Better landing page and early-access dialog", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  const renderedText = html
    .replace(/<!--.*?-->/g, "")
    .replace(/<[^>]*>/g, " ")
    .replace(/\s+/g, " ");
  assert.match(html, /<title>2M2Better · A two-minute reset for your body<\/title>/i);
  assert.match(renderedText, /A two-minute reset that helps your body keep up with your mind\./);
  assert.match(renderedText, /A nudge, not a negotiation\./);
  assert.match(renderedText, /Your breaks stay on your Mac\./);
  assert.match(renderedText, /No account to create\. No network connection\. No analytics/);
  assert.match(renderedText, /Coming soon/);
  assert.match(renderedText, /Not public yet\./);
  assert.match(renderedText, /Join early access/);
  assert.match(html, /href="https:\/\/forms\.gle\/ALeWYDcoYHvXYNBo6"/);
  assert.doesNotMatch(html, /pricing|testimonial|subscribe|sign in/i);
  assert.doesNotMatch(html, /<input|<form/i);
  assert.doesNotMatch(html, /2mintogood|Break Companion/);
  assert.doesNotMatch(
    renderedText,
    /\b(pain|injur\w*|treat\w*|cure[sd]?|curing|diagnos\w*|therap\w*|posture|RSI|carpal tunnel|sciatica|prevent\w*|symptom\w*|medical|clinical)\b/i,
  );
});

test("declared og:image dimensions match the shipped image bytes", async () => {
  const bytes = await readFile(new URL("../public/og.png", import.meta.url));
  assert.equal(bytes.subarray(12, 16).toString("ascii"), "IHDR");
  const width = bytes.readUInt32BE(16);
  const height = bytes.readUInt32BE(20);

  const html = await (await render()).text();
  const declared = (property) =>
    Number(
      html.match(
        new RegExp(`<meta property="${property}" content="(\\d+)"`, "i"),
      )?.[1],
    );

  assert.equal(declared("og:image:width"), width);
  assert.equal(declared("og:image:height"), height);
});

test("source preserves the minimal private product story", async () => {
  const [css, page, layout] = await Promise.all([
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
  ]);
  const normalizedPage = page.replace(/\s+/g, " ");

  assert.match(normalizedPage, /Six gentle standing movements/);
  assert.match(normalizedPage, /green → orange → warm red/);
  assert.match(normalizedPage, /Voice-first, never voice-only/);
  assert.match(normalizedPage, /No coaching\. No keeping score\./);
  assert.match(normalizedPage, /No account to create\. No network connection\. No analytics/);
  assert.match(normalizedPage, /dialogRef\.current\?\.showModal\(\)/);
  assert.match(normalizedPage, /event\.key === "Escape"/);
  assert.match(normalizedPage, /onCancel=\{\(event\) =>/);
  assert.match(normalizedPage, /onClose=\{\(\) => openerRef\.current\?\.focus\(\)\}/);
  assert.match(normalizedPage, /aria-labelledby="coming-soon-title"/);
  assert.match(normalizedPage, /https:\/\/forms\.gle\/ALeWYDcoYHvXYNBo6/);
  assert.match(layout, /openGraph/);
  assert.match(layout, /\/og\.png/);
  assert.match(css, /@keyframes orb-breathe/);
  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.match(css, /\.coming-soon::backdrop/);
  assert.deepEqual(
    page.match(/https?:\/\/[^"]+/g),
    ["https://forms.gle/ALeWYDcoYHvXYNBo6"],
  );
});
