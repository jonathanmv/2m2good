import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, mkdir, readFile, readdir, rm, writeFile, chmod } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

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

async function builtStyles() {
  const assetDir = new URL("../dist/client/assets/", import.meta.url);
  return (
    await Promise.all(
      (await readdir(assetDir))
        .filter((name) => name.endsWith(".css"))
        .map((name) => readFile(new URL(name, assetDir), "utf8")),
    )
  ).join("\n");
}

const CONDITIONAL_AT_RULE = /^@(?:media|supports|container)\b/;

function cssRules(styles) {
  const source = styles.replace(/\/\*[\s\S]*?\*\//g, "");
  const rules = [];

  function matchingBrace(open) {
    let depth = 1;
    for (let index = open + 1; index < source.length; index += 1) {
      if (source[index] === "{") depth += 1;
      if (source[index] === "}") {
        depth -= 1;
        if (depth === 0) return index;
      }
    }
    throw new Error("unterminated CSS block");
  }

  function scan(start, end, conditions) {
    let cursor = start;
    while (cursor < end) {
      const open = source.indexOf("{", cursor);
      if (open === -1 || open >= end) return;
      const close = matchingBrace(open);
      if (close > end) throw new Error("CSS block crossed its parent");
      const header = source.slice(cursor, open).split(";").at(-1).trim();
      const body = source.slice(open + 1, close);
      if (body.includes("{")) {
        scan(
          open + 1,
          close,
          CONDITIONAL_AT_RULE.test(header) ? [...conditions, header] : conditions,
        );
      } else if (header && !header.startsWith("@")) {
        const declarations = new Map();
        for (const declaration of body.split(";")) {
          const separator = declaration.indexOf(":");
          if (separator === -1) continue;
          declarations.set(
            declaration.slice(0, separator).trim(),
            declaration.slice(separator + 1).trim(),
          );
        }
        rules.push({
          selectors: header.split(",").map((selector) => selector.trim()),
          declarations,
          conditions,
        });
      }
      cursor = close + 1;
    }
  }

  scan(0, source.length, []);
  return rules;
}

const REDUCED_MOTION = /prefers-reduced-motion\s*:\s*reduce/;

function rulesFor(rules, selector, condition) {
  return rules.filter(({ selectors, conditions }) =>
    selectors.includes(selector) &&
    (condition
      ? conditions.some((entry) => condition.test(entry))
      : conditions.length === 0),
  );
}

function declarationFor(rules, selector, property, condition) {
  const declaring = rulesFor(rules, selector, condition).filter(({ declarations }) =>
    declarations.has(property),
  );
  const context = condition ? ` under ${condition}` : " outside any media query";
  assert.ok(
    declaring.length > 0,
    `expected built CSS to declare ${property} on ${selector}${context}`,
  );
  return declaring.at(-1).declarations.get(property);
}

function tokensFrom(value) {
  assert.match(
    value,
    /^var\(--[\w-]+/,
    `expected a design-token declaration, received ${value}`,
  );
  return [...value.matchAll(/var\((--[\w-]+)/g)].map(([, token]) => token);
}

function tokenRoot(styles) {
  const root = cssRules(styles).find(({ selectors, declarations, conditions }) =>
    conditions.length === 0 &&
    selectors.includes(":root") &&
    declarations.has("--type-display-size"),
  )?.declarations;
  assert.ok(root, "expected marketing design tokens in the built CSS");
  return root;
}

function resolveToken(root, token) {
  let value = root.get(token);
  assert.ok(value, `expected ${token} in the rendered token contract`);
  for (let depth = 0; depth < 20; depth += 1) {
    const reference = value.match(/var\((--[\w-]+)\)/);
    if (!reference) return value;
    const replacement = root.get(reference[1]);
    assert.ok(replacement, `expected ${reference[1]} in the rendered token contract`);
    value = value.replace(reference[0], replacement);
  }
  throw new Error(`token reference cycle while resolving ${token}`);
}

function parseColor(value) {
  const hex = value.match(/^#([\da-f]{6})([\da-f]{2})?$/i);
  if (hex) {
    return [
      Number.parseInt(hex[1].slice(0, 2), 16) / 255,
      Number.parseInt(hex[1].slice(2, 4), 16) / 255,
      Number.parseInt(hex[1].slice(4, 6), 16) / 255,
      hex[2] === undefined ? 1 : Number.parseInt(hex[2], 16) / 255,
    ];
  }
  const rgba = value.match(/^rgba?\(\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\s*\)$/i);
  assert.ok(rgba, `expected a resolved CSS color, received ${value}`);
  return [
    Number(rgba[1]) / 255,
    Number(rgba[2]) / 255,
    Number(rgba[3]) / 255,
    rgba[4] === undefined ? 1 : Number(rgba[4]),
  ];
}

function blend(foreground, background) {
  const alpha = foreground[3];
  return [
    foreground[0] * alpha + background[0] * (1 - alpha),
    foreground[1] * alpha + background[1] * (1 - alpha),
    foreground[2] * alpha + background[2] * (1 - alpha),
    1,
  ];
}

function relativeLuminance(color) {
  return color
    .slice(0, 3)
    .map((channel) => (channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4))
    .reduce((sum, channel, index) => sum + channel * [0.2126, 0.7152, 0.0722][index], 0);
}

function contrastRatio(foreground, background) {
  assert.equal(
    background[3],
    1,
    "contrast must be measured against an opaque backdrop; composite the background first",
  );
  const composited = blend(foreground, background);
  const foregroundLuminance = relativeLuminance(composited);
  const backgroundLuminance = relativeLuminance(background);
  return (Math.max(foregroundLuminance, backgroundLuminance) + 0.05) /
    (Math.min(foregroundLuminance, backgroundLuminance) + 0.05);
}

function backdrop(root, background, base) {
  const color = parseColor(resolveToken(root, background));
  if (!base) return color;
  return blend(color, parseColor(resolveToken(root, base)));
}

function specificity(selector) {
  const cleaned = selector.replace(/::[\w-]+(?:\([^)]*\))?/g, " ");
  return [
    (cleaned.match(/#[\w-]+/g) ?? []).length,
    (cleaned.match(/\.[\w-]+|\[[^\]]*\]|:[\w-]+(?:\([^)]*\))?/g) ?? []).length,
    (cleaned.match(/(?:^|[\s>+~,])[a-z][\w-]*/gi) ?? []).length,
  ];
}

function matchesElement(selector, element) {
  const compound = selector.trim();
  const parts = compound.match(/^[a-z][\w-]*|\*|\.[\w-]+|:[\w-]+/gi) ?? [];
  if (parts.join("") !== compound) return false;
  return parts.every((part) => {
    if (part === "*") return true;
    if (part.startsWith(".")) return element.classes.includes(part.slice(1));
    if (part.startsWith(":")) return element.states.includes(part);
    return part === element.tag;
  });
}

function cascadeWinner(rules, element, property) {
  const applicable = rules
    .map((rule, order) => ({ rule, order }))
    .filter(({ rule }) => rule.conditions.length === 0 && rule.declarations.has(property))
    .map(({ rule, order }) => ({
      rule,
      order,
      weight: rule.selectors
        .filter((selector) => matchesElement(selector, element))
        .map(specificity)
        .sort((left, right) => right[0] - left[0] || right[1] - left[1] || right[2] - left[2])
        .at(0),
    }))
    .filter(({ weight }) => weight !== undefined)
    .sort(
      (left, right) =>
        left.weight[0] - right.weight[0] ||
        left.weight[1] - right.weight[1] ||
        left.weight[2] - right.weight[2] ||
        left.order - right.order,
    );
  assert.ok(
    applicable.length > 0,
    `expected a rule declaring ${property} for ${element.tag}.${element.classes.join(".")}`,
  );
  return applicable.at(-1).rule.declarations.get(property);
}

test("server-rendered page exposes the landing narrative and safe product boundary", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  const text = renderedText(html);
  assert.match(html, /<title>2m2better · Two minutes for your body<\/title>/i);
  const inlineMarkup = html.replace(/<[^>]*>/g, "");
  const brandSpellings = [
    ...(html.match(/2m2better/gi) ?? []),
    ...(inlineMarkup.match(/2m2better/gi) ?? []),
  ];
  assert.ok(brandSpellings.length > 0, "expected the canonical product name in rendered output");
  assert.ok(
    brandSpellings.every((spelling) => spelling === "2m2better"),
    "the product name must be lowercase in rendered output",
  );
  assert.match(text, /Your agent can keep working\. Give your body two minutes\./);
  assert.match(text, /A two-minute reset that helps your body keep up with your mind\./);
  assert.match(text, /Copy and paste in your terminal to install/);
  assert.match(text, /2 mins to better your neck\s*\./);
  for (const area of ["Neck", "Shoulders", "Hands + wrists", "Lower back"]) {
    assert.ok(text.toLowerCase().includes(area.toLowerCase()), `expected ${area} in rendered output`);
  }
  assert.match(text, /Small by design\. Useful by feel\./);
  assert.match(text, /A quiet nudge\. A clear choice\. Two minutes\./);
  assert.match(text, /No\. The current developer preview does not detect or coordinate agent activity\./);
  assert.match(text, /has no account, dashboard, analytics, or in-app network connection/);
  assert.match(text, /Before you give it two minutes\./);
  assert.match(text, /Free developer preview for macOS/);

  assert.doesNotMatch(
    text,
    /standing-only|six (?:gentle )?movements|20-second|two minutes, exactly|posture correction|pain relief|prevent RSI|productivity guilt|Mac knowledge workers/i,
  );
  assert.doesNotMatch(text, /<input|<form|pricing|testimonial|subscribe|sign in/i);
  assert.doesNotMatch(text, /2mintogood/);
});

test("rendered demo exposes a click-only, bounded, accessible flow", async () => {
  const html = await (await render()).text();
  const text = renderedText(html);
  const demo = section(html, "demo-section");

  assert.ok(html.indexOf('id="preview"') > html.indexOf('id="how-it-works"'));
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
});

test("rendered check-in offers only the three visible keyboard-accessible responses", async () => {
  const html = await (await render()).text();
  const checkin = section(html, "flow-section");
  const responseButtons = checkin.match(/<button\b/g) ?? [];

  assert.match(checkin, /aria-label="Available responses"/);
  assert.equal(responseButtons.length, 3);
  for (const label of ["Start", "Later", "Tomorrow"]) {
    assert.match(checkin, new RegExp(`>${label}<`));
  }
  assert.match(checkin, /Buttons always work|click-only decision/);
});

test("rendered developer-preview section gives one auditable download-then-run command", async () => {
  const html = await (await render()).text();
  const text = renderedText(html);
  const installer = section(html, "installer");

  assert.match(text, /Free developer preview for macOS/);
  assert.match(text, /developer preview/);
  assert.match(text, /macOS 14\+/);
  assert.match(text, /GitHub HTTPS access/);
  assert.match(text, /does not detect or coordinate agent activity/);
  assert.match(text, /verifies a matching GitHub Release ZIP and checksum/);
  assert.match(text, /no Developer ID or notarization/);
  assert.doesNotMatch(text, /available\s+to inspect/);
  const rawCommand = installer.match(/<pre\b[^>]*><code>([\s\S]*?)<\/code><\/pre>/)?.[1] ?? "";
  const command = rawCommand.replace(/&amp;/g, "&").replace(/&quot;/g, '"');
  assert.equal(command.split("\n").length, 1, "the CTA must be one pasteable shell command");
  assert.match(
    command,
    /^curl -fsSL https:\/\/raw\.githubusercontent\.com\/jonathanmv\/2m2good\/main\/scripts\/install\.sh \| sh$/,
  );
  assert.doesNotMatch(command, /\b(?:cat|less|more|vi|vim|nano|emacs)\b/);
  assert.match(installer, /Copy command/);
  assert.match(installer, /select this text to copy manually/);

  const testRoot = await mkdtemp(join(tmpdir(), "2m2better-installer-command-"));
  try {
    const fakeBin = join(testRoot, "bin");
    const home = join(testRoot, "home");
    const curlLog = join(testRoot, "curl.log");
    const shellLog = join(testRoot, "shell.log");
    const scriptLog = join(testRoot, "script.log");
    await mkdir(fakeBin);
    await mkdir(home);
    await writeFile(
      join(fakeBin, "curl"),
      `#!/bin/sh
printf '%s\\n' "$*" > "$COMMAND_TEST_CURL_LOG"
printf '%s\\n' downloaded
`,
    );
    await writeFile(
      join(fakeBin, "sh"),
      `#!/bin/sh
printf '%s\\n' "$*" > "$COMMAND_TEST_SHELL_LOG"
cat > "$COMMAND_TEST_SCRIPT_LOG"
`,
    );
    await chmod(join(fakeBin, "curl"), 0o755);
    await chmod(join(fakeBin, "sh"), 0o755);

    await execFileAsync("/bin/sh", ["-c", command], {
      cwd: testRoot,
      env: {
        ...process.env,
        PATH: `${fakeBin}:/usr/bin:/bin`,
        HOME: home,
        COMMAND_TEST_CURL_LOG: curlLog,
        COMMAND_TEST_SHELL_LOG: shellLog,
        COMMAND_TEST_SCRIPT_LOG: scriptLog,
      },
    });

    assert.equal(
      await readFile(curlLog, "utf8"),
      "-fsSL https://raw.githubusercontent.com/jonathanmv/2m2good/main/scripts/install.sh\n",
    );
    assert.equal(
      await readFile(shellLog, "utf8"),
      "\n",
    );
    assert.equal(await readFile(scriptLog, "utf8"), "downloaded\n");
  } finally {
    await rm(testRoot, { recursive: true, force: true });
  }
});

test("built landing regions resolve their rendered styles through design tokens", async () => {
  const response = await render();
  const html = await response.text();
  const styles = await builtStyles();
  const rules = cssRules(styles);
  const root = rules.find(({ selectors, declarations, conditions }) =>
    conditions.length === 0 &&
    selectors.includes(":root") &&
    declarations.has("--type-display-size"),
  )?.declarations;
  assert.ok(root, "expected marketing design tokens in the built CSS");

  for (const className of ["hero", "problem-grid", "benefits-grid", "flow-grid", "demo-card", "installer-inner", "command-card"]) {
    assert.match(
      html,
      new RegExp(`class="(?:[^"]*\\s)?${className}(?=\\s|")`),
      `expected the ${className} region in the rendered page`,
    );
  }

  for (const [selector, property] of [
    [".hero h1", "font-size"],
    [".problem-grid", "padding-block"],
    [".benefit", "border-top"],
    [".demo-card", "box-shadow"],
    [".installer-inner", "padding-block"],
    [".command-card", "border-radius"],
    [".command-card pre", "font-family"],
  ]) {
    for (const token of tokensFrom(declarationFor(rules, selector, property))) {
      assert.ok(root.has(token), `${selector} ${property} must resolve declared tokens`);
    }
  }

  assert.equal(
    declarationFor(rules, ".orb-state-approaching", "--orb-surface"),
    "var(--orb-surface-near)",
  );
  assert.equal(
    declarationFor(rules, ".orb-state-approaching", "--orb-shadow"),
    "var(--orb-shadow-near)",
  );
  assert.ok(root.has("--orb-surface-near"));
  assert.ok(root.has("--orb-shadow-near"));

  assert.equal(
    declarationFor(rules, "*", "animation-duration", REDUCED_MOTION),
    "var(--motion-reduced-duration)!important",
  );
  assert.ok(root.has("--motion-reduced-duration"));
  assert.deepEqual(
    rules
      .filter(
        ({ selectors, declarations, conditions }) =>
          selectors.includes("*") &&
          declarations.has("animation-duration") &&
          !conditions.some((entry) => REDUCED_MOTION.test(entry)),
      )
      .map(({ conditions }) => conditions.join(" ") || "top level"),
    [],
    "every global animation-duration override must stay inside the reduced-motion query",
  );

  const compact = /max-width\s*:\s*560px|width\s*<=\s*560px/;
  for (const [selector, property] of [
    [".nav-action", "font-size"],
    [".checkin-window", "padding"],
    [".command-card", "padding"],
  ]) {
    for (const token of tokensFrom(declarationFor(rules, selector, property, compact))) {
      assert.ok(root.has(token), `compact ${selector} ${property} must resolve declared tokens`);
    }
  }
});

test("rendered palette roles keep surfaces readable and orb proximity distinct", async () => {
  const html = await (await render()).text();
  const styles = await builtStyles();
  const rules = cssRules(styles);
  const root = tokenRoot(styles);

  for (const role of [
    "--color-surface-canvas",
    "--color-surface-raised",
    "--color-surface-recessed",
    "--color-content-primary",
    "--color-content-secondary",
    "--color-content-accent",
    "--color-content-signal",
    "--color-content-on-action",
    "--color-content-on-signal",
    "--color-border-subtle",
    "--color-focus-ring",
    "--shadow-focus",
  ]) {
    assert.ok(root.has(role), `expected ${role} in the rendered palette contract`);
  }

  const readablePairs = [
    ["--color-content-primary", "--color-surface-canvas"],
    ["--color-content-secondary", "--color-surface-canvas"],
    ["--color-content-accent", "--color-surface-canvas"],
    ["--color-content-signal", "--color-surface-raised"],
    ["--color-content-on-action", "--color-surface-action"],
    ["--color-content-on-signal", "--color-surface-signal"],
    ["--color-content-on-dark-muted", "--color-content-primary"],
    ["--color-content-on-dark-muted", "--color-content-accent"],
    ["--color-content-signal-soft", "--color-content-accent"],
    ["--color-content-on-dark-strong", "--color-alpha-ink-18", "--color-content-primary"],
  ];
  for (const [foreground, background, base] of readablePairs) {
    const ratio = contrastRatio(
      parseColor(resolveToken(root, foreground)),
      backdrop(root, background, base),
    );
    assert.ok(ratio >= 4.5, `${foreground} on ${background} must be readable (got ${ratio.toFixed(2)}:1)`);
  }

  assert.ok(
    contrastRatio(
      parseColor(resolveToken(root, "--color-focus-ring")),
      parseColor(resolveToken(root, "--color-surface-canvas")),
    ) >= 3,
    "the focus ring must remain visible on the canvas",
  );
  assert.ok(
    contrastRatio(
      parseColor(resolveToken(root, "--color-focus-ring-contrast")),
      parseColor(resolveToken(root, "--color-surface-action")),
    ) >= 3,
    "the focus contrast halo must remain visible around dark actions",
  );

  const states = [
    ["resting", "distant"],
    ["approaching", "near"],
    ["due", "imminent"],
  ];
  const proximityColors = states.map(([, proximity]) =>
    resolveToken(root, `--orb-proximity-${proximity}`),
  );
  assert.equal(new Set(proximityColors).size, states.length, "orb proximity colors must progress distinctly");
  for (const [state, proximity] of states) {
    assert.equal(
      declarationFor(rules, `.orb-state-${state}`, "--orb-surface"),
      `var(--orb-surface-${proximity})`,
    );
    assert.equal(
      declarationFor(rules, `.orb-state-${state}`, "--orb-halo"),
      `var(--orb-halo-${proximity})`,
    );
    assert.match(resolveToken(root, `--orb-surface-${proximity}`), /radial-gradient/);
    assert.match(resolveToken(root, `--orb-surface-${proximity}`), /linear-gradient/);
    assert.ok(
      parseColor(resolveToken(root, `--orb-halo-${proximity}`))[3] < 1,
      `expected the ${proximity} orb halo to stay soft rather than become a solid fill`,
    );
  }
  assert.match(html, /break proximity/);
  assert.match(html, /No agent awareness/);
});

test("keyboard focus resolves to the ring and contrast halo on every rendered action", async () => {
  const html = await (await render()).text();
  const rules = cssRules(await builtStyles());

  const focusable = [...html.matchAll(/<(a|button)\b([^>]*)>/g)]
    .filter(([, tag, attributes]) => tag === "button" || /\shref=/.test(attributes))
    .map(([, tag, attributes]) => ({
      tag,
      classes: (attributes.match(/class="([^"]*)"/)?.[1] ?? "").split(/\s+/).filter(Boolean),
      states: [":focus-visible", ":focus"],
    }));
  assert.ok(focusable.length >= 5, "expected the rendered page to offer focusable actions");

  const distinct = new Map(
    focusable.map((element) => [`${element.tag}${element.classes.map((name) => `.${name}`).join("")}`, element]),
  );
  for (const [label, element] of distinct) {
    assert.equal(
      cascadeWinner(rules, element, "outline"),
      "var(--border-focus)",
      `focused ${label} must keep the focus ring`,
    );
    assert.equal(
      cascadeWinner(rules, element, "box-shadow"),
      "var(--shadow-focus)",
      `focused ${label} must keep the contrast halo instead of its own resting shadow`,
    );
  }
});

test("every custom property the built CSS consumes without a fallback is declared", async () => {
  const styles = await builtStyles();
  const declared = new Set([
    ...[...styles.matchAll(/(--[\w-]+)\s*:/g)].map(([, name]) => name),
    ...[...styles.matchAll(/@property\s+(--[\w-]+)/g)].map(([, name]) => name),
  ]);
  const dangling = [
    ...new Set(
      [...styles.matchAll(/var\((--[\w-]+)\s*([,)])/g)]
        .filter(([, , next]) => next === ")")
        .map(([, name]) => name),
    ),
  ].filter((name) => !declared.has(name));

  assert.deepEqual(
    dangling,
    [],
    "an undefined custom property with no fallback invalidates its whole declaration",
  );
});

test("orb and area fallback are present in the built visual output", async () => {
  const html = await (await render()).text();
  assert.match(html, /orb-state-resting/);
  assert.match(html, /orb-state-approaching/);
  assert.match(html, /aria-live="polite"/);
  assert.match(html, /area-fallback/);

  const rules = cssRules(await builtStyles());

  assert.equal(declarationFor(rules, ".area-fallback", "display"), "none");
  assert.equal(
    declarationFor(rules, ".area-fallback", "display", REDUCED_MOTION),
    "block",
  );
  assert.equal(declarationFor(rules, ".area-word", "animation", REDUCED_MOTION), "none");
  assert.equal(
    declarationFor(rules, ".orb-state-approaching", "--orb-halo"),
    "var(--orb-halo-near)",
  );
  assert.equal(
    declarationFor(rules, ".orb-halo", "animation", REDUCED_MOTION),
    "none!important",
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
