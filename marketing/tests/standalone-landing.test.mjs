import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const artifact = await readFile(new URL("../landing.html", import.meta.url), "utf8");

function installerCommand() {
  const match = artifact.match(/<code[^>]*id="install-command"[^>]*>([\s\S]*?)<\/code>/i);
  assert.ok(match, "the standalone artifact must expose an installer command");
  return match[1].trim();
}

test("standalone landing artifact is a self-contained file:// document", () => {
  assert.match(artifact, /^<!doctype html>/i);
  assert.match(artifact, /<html lang="en">/i);
  assert.equal((artifact.match(/<style\b/gi) ?? []).length, 1);
  assert.equal((artifact.match(/<script\b/gi) ?? []).length, 1);
  assert.doesNotMatch(artifact, /<(?:link|script|img|iframe)\b[^>]*(?:href|src)=/i);
  assert.doesNotMatch(artifact, /@import\b|url\s*\(/i);
  assert.doesNotMatch(artifact, /\b(?:fetch|XMLHttpRequest|WebSocket)\s*\(/i);

  const references = [...artifact.matchAll(/\b(?:href|src)="([^"]+)"/gi)].map(([, value]) => value);
  assert.ok(references.every((value) => value.startsWith("#")), "file:// links must stay within the document");
});

test("standalone artifact keeps the approved product boundary and installer CTA", () => {
  const command = installerCommand();
  assert.equal(
    command,
    "curl -fsSL https://raw.githubusercontent.com/jonathanmv/2m2good/main/scripts/install.sh | sh",
  );
  assert.match(artifact, /Copy and paste in your terminal to install/);
  assert.match(artifact, /Start/);
  assert.match(artifact, /Later/);
  assert.match(artifact, /Tomorrow/);
  assert.match(artifact, /does not detect, watch, or coordinate coding agents/i);
  assert.match(artifact, /does not read key values, pointer coordinates, app content/i);
  assert.doesNotMatch(artifact, /Mac knowledge workers|testimonial|pricing|streak|dashboard/i);
});

test("standalone artifact includes accessible motion and clipboard fallbacks", () => {
  assert.match(artifact, /prefers-reduced-motion:\s*reduce/);
  assert.match(artifact, /:focus-visible/);
  assert.match(artifact, /aria-live="polite"/);
  assert.match(artifact, /document\.execCommand\("copy"\)/);
  assert.match(artifact, /Clipboard access was unavailable/);
});
