import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
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

function renderedText(html) {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<!--.*?-->/gs, "")
    .replace(/<[^>]*>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function section(html, className) {
  const start = html.indexOf(`class="${className}`);
  assert.notEqual(start, -1, `expected ${className} in rendered page`);
  const end = html.indexOf("</section>", start);
  assert.notEqual(end, -1, `expected closing section for ${className}`);
  return html.slice(start, end);
}

test("server-rendered page exposes the area promise, sequence, and safe product boundary", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  const text = renderedText(html);
  assert.match(html, /<title>2m2better · A little room to move<\/title>/i);
  const brandSpellings = text.match(/2m2better/gi) ?? [];
  assert.ok(brandSpellings.length > 0, "expected the canonical product name in rendered output");
  assert.ok(
    brandSpellings.every((spelling) => spelling === "2m2better"),
    "the product name must be lowercase in rendered output",
  );
  assert.match(text, /Give your body a little room to move, then come back to your day\./);
  assert.match(text, /2 mins to better your neck\s*\./);
  for (const area of ["Neck", "Shoulders", "Hands + wrists", "Lower back"]) {
    assert.ok(text.includes(area), `expected ${area} in rendered output`);
  }
  assert.match(text, /Meet your body where it is\./);
  assert.match(text, /One suggestion\. Your call\./);
  assert.match(text, /Your breaks stay close to home\./);
  assert.match(text, /No account, analytics, or in-app network connection/);

  assert.doesNotMatch(
    text,
    /standing-only|six (?:gentle )?movements|20-second|two minutes, exactly|posture correction|pain relief|prevent RSI|productivity guilt/i,
  );
  assert.doesNotMatch(text, /<input|<form|pricing|testimonial|subscribe|sign in/i);
  assert.doesNotMatch(text, /2mintogood/);
});

test("rendered demo exposes a click-only, bounded, accessible flow", async () => {
  const html = await (await render()).text();
  const text = renderedText(html);
  const demo = section(html, "demo-section");

  assert.ok(html.indexOf('id="demo"') > html.indexOf('id="areas"'));
  assert.match(demo, /aria-labelledby="demo-title"/);
  assert.match(demo, /data-demo-duration="12"/);
  assert.match(demo, /role="progressbar"/);
  assert.match(demo, /aria-label="Preview controls"/);
  assert.match(demo, />Start(?:\s|<)/);
  assert.match(demo, />Pause(?:\s|<)/);
  assert.match(demo, />Next cue(?:\s|<)/);
  assert.match(demo, />End(?:\s|<)/);
  assert.match(demo, /Click-only preview/);
  assert.equal((text.match(/Ready for a gentle reset\?/g) ?? []).length, 2);
  assert.doesNotMatch(demo, /microphone|voice input|Try Voice/i);
});

test("rendered developer-preview section gives an auditable download-then-run command", async () => {
  const html = await (await render()).text();
  const text = renderedText(html);
  const installer = section(html, "installer");

  assert.match(text, /Early developer preview/);
  assert.match(text, /not a signed consumer download/);
  assert.match(text, /macOS 14\+/);
  assert.match(text, /Xcode 15\+/);
  assert.match(text, /Copy this into your terminal, or ask your agent to install it for you\./);
  const command = installer.match(/<pre><code>([\s\S]*?)<\/code><\/pre>/)?.[1] ?? "";
  const steps = command.split("\n").map((line) => line.trim()).filter(Boolean);
  assert.equal(steps.length, 3);
  assert.match(steps[0], /^curl -fsSL https:\/\/raw\.githubusercontent\.com\/jonathanmv\/2m2good\/main\/scripts\/install-preview\.sh -o install-preview\.sh$/);
  assert.match(steps[1], /^cat install-preview\.sh$/);
  assert.match(steps[2], /^sh install-preview\.sh --ref main --destination/);
  assert.doesNotMatch(command, /curl\s*\|\s*sh/i);
  for (const step of steps) {
    assert.doesNotMatch(step, /^(?:less|more|vi|vim|nano|emacs)\b/);
  }
});

test("orb and area fallback are present in the built visual output", async () => {
  const html = await (await render()).text();
  assert.match(html, /orb-state-resting/);
  assert.match(html, /orb-state-approaching/);
  assert.match(html, /aria-live="polite"/);
  assert.match(html, /area-fallback/);

  const assetDir = new URL("../dist/client/assets/", import.meta.url);
  const styles = (
    await Promise.all(
      (await readdir(assetDir))
        .filter((name) => name.endsWith(".css"))
        .map((name) => readFile(new URL(name, assetDir), "utf8")),
    )
  ).join("\n");
  assert.match(styles, /prefers-reduced-motion/);
  assert.match(styles, /area-fallback/);
  assert.match(styles, /orb-state-approaching/);
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
