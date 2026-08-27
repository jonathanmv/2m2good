import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const artifact = await readFile(new URL("../landing.html", import.meta.url), "utf8");

function installerCommand() {
  const match = artifact.match(/<code[^>]*id="install-command"[^>]*>([\s\S]*?)<\/code>/i);
  assert.ok(match, "the standalone artifact must expose an installer command");
  return match[1].trim();
}

function extractInlineScript() {
  const match = artifact.match(/<script>([\s\S]*?)<\/script>/i);
  assert.ok(match, "the standalone artifact must include an inline script");
  return match[1];
}

class FakeElement {
  constructor(id) {
    this.id = id;
    this._text = "";
    this.attributes = new Map();
    this.classes = new Set();
    this.dataset = {};
    this.hidden = false;
    this.disabled = false;
    this.listeners = new Map();
  }

  get textContent() {
    return this._text;
  }

  set textContent(value) {
    this._text = String(value);
  }

  setAttribute(name, value) {
    this.attributes.set(name, String(value));
  }

  getAttribute(name) {
    return this.attributes.has(name) ? this.attributes.get(name) : null;
  }

  addEventListener(type, handler) {
    if (!this.listeners.has(type)) this.listeners.set(type, []);
    this.listeners.get(type).push(handler);
  }

  dispatch(type) {
    const handlers = this.listeners.get(type) ?? [];
    return Promise.all(handlers.map((handler) => handler.call(this)));
  }
}

function createDom({ clipboard, secureContext = true, execCommand = () => true } = {}) {
  const byId = new Map();
  const allElements = [];

  function make(id, classes = []) {
    const element = new FakeElement(id);
    classes.forEach((name) => element.classes.add(name));
    if (id) byId.set(id, element);
    allElements.push(element);
    return element;
  }

  const command = make("install-command");
  command.textContent = installerCommand();
  const copyButton = make("copy-command");
  const copyStatus = make("copy-status");

  ["area-note-1", "area-note-2", "area-note-3", "area-note-4"].forEach((noteId, index) => {
    const note = make(noteId);
    note.hidden = index !== 0;
    const button = make(null, ["area-button"]);
    button.setAttribute("aria-controls", noteId);
    button.setAttribute("aria-pressed", String(index === 0));
  });

  ["Start", "Later", "Tomorrow"].forEach((label) => {
    const choice = make(null, ["choice"]);
    choice.dataset.choice = label;
    choice.setAttribute("aria-pressed", "false");
  });

  const checkinStatus = make(null, ["checkin-status"]);

  const documentStub = {
    getElementById: (id) => byId.get(id) ?? null,
    querySelectorAll: (selector) => allElements.filter((element) => element.classes.has(selector.replace(/^\./, ""))),
    querySelector: (selector) => allElements.find((element) => element.classes.has(selector.replace(/^\./, ""))) ?? null,
    createRange: () => ({ selectNodeContents() {} }),
    execCommand,
  };

  const windowStub = {
    getSelection: () => ({ removeAllRanges() {}, addRange() {} }),
    isSecureContext: secureContext,
  };

  const navigatorStub = { clipboard };

  const sandbox = { document: documentStub, window: windowStub, navigator: navigatorStub, console };
  vm.createContext(sandbox);
  vm.runInContext(extractInlineScript(), sandbox);

  return { command, copyButton, copyStatus, checkinStatus };
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

test("standalone artifact declares accessible motion and focus affordances", () => {
  assert.match(artifact, /prefers-reduced-motion:\s*reduce/);
  assert.match(artifact, /:focus-visible/);
  assert.match(artifact, /aria-live="polite"/);
});

test("copy button copies the installer command to the clipboard on click", async () => {
  const written = [];
  const dom = createDom({
    clipboard: { writeText: async (text) => { written.push(text); } },
  });

  await dom.copyButton.dispatch("click");

  assert.deepEqual(written, [installerCommand()]);
  assert.equal(dom.copyButton.textContent, "Copied to clipboard");
  assert.equal(dom.copyStatus.textContent, "The installer command is on your clipboard.");
});

test("copy button falls back to manual selection when clipboard access is unavailable", async () => {
  const dom = createDom({
    clipboard: undefined,
    execCommand: () => false,
  });

  await dom.copyButton.dispatch("click");

  assert.equal(dom.copyButton.textContent, "Command selected — copy manually");
  assert.equal(
    dom.copyStatus.textContent,
    "Clipboard access was unavailable, so the command is selected. Press ⌘C or Ctrl+C to copy it.",
  );
});
