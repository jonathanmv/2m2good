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

test("server-renders the 2M2Better landing page and early-access dialog", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  const renderedText = html
    .replace(/<!--.*?-->/g, "")
    .replace(/<[^>]*>/g, " ")
    .replace(/\s+/g, " ");
  assert.match(html, /<title>2m2better · A two-minute reset for your body<\/title>/i);
  assert.match(renderedText, /2m2better/);
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
  assert.match(css, /@import "\.\/design-tokens\.css"/);
  assert.match(css, /@keyframes orb-breathe/);
  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.match(css, /var\(--motion-reduced-duration\)/);
  assert.match(css, /\.orb-halo,[\s\S]*\.dialog-orb/);
  assert.doesNotMatch(css, /#[0-9a-f]{3,8}|rgba?\(/i);
  assert.match(css, /\.coming-soon::backdrop/);
  assert.deepEqual(
    page.match(/https?:\/\/[^"]+/g),
    ["https://forms.gle/ALeWYDcoYHvXYNBo6"],
  );
});

test("marketing token contract owns the landing-page visual vocabulary", async () => {
  const [tokens, page] = await Promise.all([
    readFile(new URL("../app/design-tokens.css", import.meta.url), "utf8"),
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
  ]);

  for (const token of [
    "--color-surface-canvas",
    "--color-content-primary",
    "--font-body",
    "--type-display-size",
    "--space-8",
    "--radius-card",
    "--border-subtle",
    "--shadow-float",
    "--layout-content-max",
    "--motion-duration-orb",
    "--orb-proximity-distant",
    "--orb-proximity-near",
    "--orb-proximity-imminent",
  ]) {
    assert.match(tokens, new RegExp(`${token}\\s*:`));
  }

  assert.match(tokens, /\.orb-state-resting[\s\S]*--orb-surface/);
  assert.match(tokens, /\.orb-state-approaching[\s\S]*--orb-surface/);
  assert.match(tokens, /\.orb-state-due[\s\S]*--orb-surface/);
  assert.match(page, /orb-state-resting/);
  assert.match(page, /orb-state-approaching/);
  assert.match(page, /2m2better/);
  assert.doesNotMatch(page, /2M2Better/);
});

async function builtStylesheet() {
  const dir = new URL("../dist/client/assets/", import.meta.url);
  const sheets = await Promise.all(
    (await readdir(dir))
      .filter((name) => name.endsWith(".css"))
      .map((name) => readFile(new URL(name, dir), "utf8")),
  );
  assert.ok(sheets.length > 0, "expected a built CSS bundle");
  return sheets.join("\n");
}

function unconditionalRules(css) {
  const rules = [];
  const walk = (source) => {
    let index = 0;
    while (index < source.length) {
      const open = source.indexOf("{", index);
      if (open < 0) return;
      const prelude = source.slice(index, open).trim();
      let depth = 0;
      let close = open;
      for (; close < source.length; close += 1) {
        if (source[close] === "{") depth += 1;
        else if (source[close] === "}") {
          depth -= 1;
          if (depth === 0) break;
        }
      }
      const body = source.slice(open + 1, close);
      if (prelude.startsWith("@")) {
        if (/@layer[^;]*$/.test(prelude)) walk(body);
      } else {
        rules.push([prelude, body]);
      }
      index = close + 1;
    }
  };
  walk(css);
  return rules;
}

function declarationsFor(css, selector) {
  const declarations = {};
  for (const [selectors, body] of unconditionalRules(css)) {
    if (!selectors.split(",").some((one) => one.trim() === selector)) continue;
    for (const declaration of body.split(";")) {
      const split = declaration.indexOf(":");
      if (split > 0) {
        declarations[declaration.slice(0, split).trim()] = declaration
          .slice(split + 1)
          .trim();
      }
    }
  }
  return declarations;
}

function substitute(value, declared, inherited, pending = new Set()) {
  return value.replace(
    /var\(\s*(--[\w-]+)\s*(?:,\s*([^()]*(?:\([^()]*\)[^()]*)*))?\)/g,
    (_match, name, fallback) => {
      if (pending.has(name)) return "";
      const next = new Set([...pending, name]);
      if (name in declared) return substitute(declared[name], declared, inherited, next);
      if (name in inherited) return inherited[name];
      return fallback ? substitute(fallback, declared, inherited, next) : "";
    },
  );
}

function rootScope(css, overrides = {}) {
  const declared = { ...declarationsFor(css, ":root"), ...overrides };
  return Object.fromEntries(
    Object.entries(declared).map(([name, value]) => [
      name,
      substitute(value, declared, {}),
    ]),
  );
}

function classOnlySelector(selector) {
  const classes = selector.match(/\.[-\w]+/g);
  if (!classes) return null;
  if (selector.replace(/\.[-\w]+/g, "").trim() !== "") return null;
  return classes.map((one) => one.slice(1));
}

function declarationsForElement(css, classes) {
  const matches = [];
  unconditionalRules(css).forEach(([selectors, body], order) => {
    for (const selector of selectors.split(",")) {
      const required = classOnlySelector(selector.trim());
      if (!required || !required.every((one) => classes.includes(one))) continue;
      matches.push({ specificity: required.length, order, body });
      break;
    }
  });
  matches.sort((a, b) => a.specificity - b.specificity || a.order - b.order);

  const declarations = {};
  for (const { body } of matches) {
    for (const declaration of body.split(";")) {
      const split = declaration.indexOf(":");
      if (split > 0) {
        declarations[declaration.slice(0, split).trim()] = declaration
          .slice(split + 1)
          .trim();
      }
    }
  }
  return declarations;
}

function customPropertiesDown(css, chain, inherited) {
  let scope = inherited;
  for (const classes of chain) {
    const declared = declarationsForElement(css, classes);
    const substituted = {};
    for (const [name, value] of Object.entries(declared)) {
      if (name.startsWith("--")) substituted[name] = substitute(value, declared, scope);
    }
    scope = { ...scope, ...substituted };
  }
  return scope;
}

function computedOn(css, chain, property, inherited) {
  const scope = customPropertiesDown(css, chain, inherited);
  assert.ok(property in scope, `${JSON.stringify(chain)} should resolve ${property}`);
  return scope[property].replace(/\s+/g, " ").trim();
}

const ORB_ELEMENTS = {
  hero: [["orb-stage", "orb-state-resting"], ["hero-orb", "orb-surface"]],
  mini: [["mini-orb", "orb-surface", "orb-state-approaching"]],
  privacy: [["privacy-orbit"], ["privacy-orb", "orb-surface", "orb-state-resting"]],
  closing: [["closing-orb", "orb-surface", "orb-state-resting"]],
  dialog: [["dialog-orb", "orb-surface", "orb-state-resting"]],
};

test("orb state classes resolve to three distinct proximity treatments", async () => {
  const css = await builtStylesheet();
  const root = rootScope(css);

  assert.ok(declarationsFor(css, ".orb-surface")["box-shadow"]);
  assert.ok(declarationsFor(css, ".orb-surface").background);

  const forState = (state, property) =>
    computedOn(css, [[`orb-state-${state}`]], property, root);
  const shadows = {
    resting: forState("resting", "--orb-shadow"),
    approaching: forState("approaching", "--orb-shadow"),
    imminent: forState("imminent", "--orb-shadow"),
  };
  const surfaces = {
    resting: forState("resting", "--orb-surface"),
    approaching: forState("approaching", "--orb-surface"),
    imminent: forState("imminent", "--orb-surface"),
  };

  for (const group of [shadows, surfaces]) {
    for (const [state, value] of Object.entries(group)) {
      assert.doesNotMatch(value, /var\(|^$/, `${state} should fully resolve`);
    }
    assert.equal(new Set(Object.values(group)).size, 3);
  }

  for (const [state, shadow] of Object.entries(shadows)) {
    assert.match(shadow, /^inset -5px -7px 14px \S.*$/, `${state} should stay a compact inset cue`);
  }

  const heroShadow = computedOn(css, ORB_ELEMENTS.hero, "--orb-shadow", root);
  assert.match(heroShadow, /^inset -10px -14px 25px .+, 0 24px 45px .+$/);
});

test("every rendered orb consumes the shared surface and an owned state", async () => {
  const html = await (await render()).text();
  const orbs = [...html.matchAll(/class="([^"]*)"/g)]
    .map(([, value]) => value.split(/\s+/))
    .filter((classes) => classes.some((one) => /^[a-z]+-orb$/.test(one)));

  assert.deepEqual(
    orbs.map((classes) => classes.find((one) => /^[a-z]+-orb$/.test(one))).sort(),
    ["closing-orb", "dialog-orb", "hero-orb", "mini-orb", "privacy-orb"],
  );
  for (const classes of orbs) {
    assert.ok(
      classes.includes("orb-surface"),
      `${classes.join(" ")} should consume the shared orb surface`,
    );
  }

  const stateClasses = new Set(
    [...html.matchAll(/orb-state-[a-z]+/g)].map(([one]) => one),
  );
  assert.deepEqual([...stateClasses].sort(), ["orb-state-approaching", "orb-state-resting"]);

  for (const [name, chain] of Object.entries(ORB_ELEMENTS)) {
    const rendered = orbs.find((classes) => classes.includes(`${name}-orb`));
    assert.deepEqual(
      chain.at(-1).slice().sort(),
      rendered.slice().sort(),
      `${name} orb chain should match the rendered class list`,
    );
  }
});

test("each resting orb keeps its own established depth", async () => {
  const css = await builtStylesheet();
  const root = rootScope(css);
  const effective = (name, property) =>
    computedOn(css, ORB_ELEMENTS[name], property, root);

  const resting = ["hero", "privacy", "closing", "dialog"];
  const surfaces = resting.map((name) => effective(name, "--orb-surface"));
  for (const [index, surface] of surfaces.entries()) {
    assert.doesNotMatch(surface, /var\(|^$/, `${resting[index]} should fully resolve its surface`);
  }
  assert.equal(new Set(surfaces).size, resting.length, "each resting orb keeps a distinct surface");

  const stops = (surface) => (surface.match(/#[0-9a-f]{3,8}|rgba?\(/gi) ?? []).length;
  assert.ok(
    stops(surfaces[0]) > stops(surfaces[1]),
    "the hero orb keeps the deeper multi-stop gradient",
  );

  const shadows = Object.fromEntries(
    resting.map((name) => [name, effective(name, "--orb-shadow")]),
  );
  assert.match(shadows.hero, /^inset -10px -14px 25px .+, 0 24px 45px .+$/);
  assert.equal(shadows.privacy, shadows.closing);
  assert.notEqual(shadows.dialog, shadows.privacy);
  for (const name of ["privacy", "closing", "dialog"]) {
    assert.match(shadows[name], /^inset -5px -7px 14px \S.*$/);
  }
});

test("retuning the approaching state leaves the resting orbs alone", async () => {
  const css = await builtStylesheet();
  const before = rootScope(css);
  const after = rootScope(css, { "--shadow-orb-small": "inset 0 0 0 #ff00ff" });
  const shadowOf = (name, scope) => computedOn(css, ORB_ELEMENTS[name], "--orb-shadow", scope);

  assert.notEqual(
    shadowOf("mini", after),
    shadowOf("mini", before),
    "the approaching orb should follow --shadow-orb-small",
  );
  for (const name of ["hero", "privacy", "closing", "dialog"]) {
    assert.equal(
      shadowOf(name, after),
      shadowOf(name, before),
      `${name} orb should not inherit the approaching state's shadow token`,
    );
  }
});
