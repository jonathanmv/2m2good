"use client";

import { useEffect, useRef, useState } from "react";

const AREAS = [
  { label: "neck", title: "Neck", cue: "turn a little, stay comfortable" },
  { label: "shoulders", title: "Shoulders", cue: "let them move a little" },
  { label: "hands + wrists", title: "Hands + wrists", cue: "open and soften your hands" },
  { label: "lower back", title: "Lower back", cue: "shift gently and change position" },
] as const;

const INSTALL_COMMAND = "curl -fsSL https://raw.githubusercontent.com/jonathanmv/2m2good/main/scripts/install.sh | sh";
const BREAK_PROMPT = "Ready for a gentle reset?";
const PREVIEW_SECONDS = 12;
const CUE_SECONDS = PREVIEW_SECONDS / AREAS.length;
const LAST_CUE_INDEX = AREAS.length - 1;

type OrbState = "resting" | "approaching" | "due";
type DemoState = "ready" | "active" | "paused" | "done";
type CopyState = "idle" | "success" | "fallback";

type Choice = "Start" | "Later" | "Tomorrow";

function Arrow() {
  return <span aria-hidden="true">↘</span>;
}

function OrbFace() {
  return (
    <>
      <span className="orb-eye" />
      <span className="orb-eye" />
    </>
  );
}

function CheckinWindow() {
  const [choice, setChoice] = useState<Choice | null>(null);
  const response =
    choice === "Start"
      ? "Your two minutes start here."
      : choice === "Later"
        ? "No problem. Later works."
        : choice === "Tomorrow"
          ? "No problem. Tomorrow works."
          : "The choice stays yours.";

  return (
    <div className="checkin-window" aria-label="Example break check-in">
      <div className="window-top">
        <div className="mini-orb orb-surface orb-state-approaching" aria-hidden="true">
          <OrbFace />
        </div>
        <div>
          <span>A small pause?</span>
          <strong>{BREAK_PROMPT}</strong>
        </div>
      </div>
      <div className="choice-stack" aria-label="Available responses">
        <button
          type="button"
          className="start-choice"
          aria-pressed={choice === "Start"}
          onClick={() => setChoice("Start")}
        >
          Start
        </button>
        <div className="quiet-choices">
          <button type="button" aria-pressed={choice === "Later"} onClick={() => setChoice("Later")}>
            Later
          </button>
          <button type="button" aria-pressed={choice === "Tomorrow"} onClick={() => setChoice("Tomorrow")}>
            Tomorrow
          </button>
        </div>
      </div>
      <p className="button-note" aria-live="polite">
        {response} Buttons stay visible for a quiet, click-only decision.
      </p>
    </div>
  );
}

function DemoPreview() {
  const [demoState, setDemoState] = useState<DemoState>("ready");
  const [cueIndex, setCueIndex] = useState(0);
  const [cueElapsed, setCueElapsed] = useState(0);
  const remaining = Math.max(0, PREVIEW_SECONDS - (cueIndex * CUE_SECONDS + cueElapsed));

  useEffect(() => {
    if (demoState !== "active") return;

    const tick = window.setTimeout(() => {
      if (cueElapsed + 1 < CUE_SECONDS) {
        setCueElapsed(cueElapsed + 1);
        return;
      }
      if (cueIndex === LAST_CUE_INDEX) {
        setCueElapsed(CUE_SECONDS);
        setDemoState("done");
        return;
      }
      setCueIndex(cueIndex + 1);
      setCueElapsed(0);
    }, 1000);

    return () => window.clearTimeout(tick);
  }, [demoState, cueIndex, cueElapsed]);

  const startPreview = () => {
    setCueIndex(0);
    setCueElapsed(0);
    setDemoState("active");
  };

  const resetPreview = () => {
    setCueIndex(0);
    setCueElapsed(0);
    setDemoState("ready");
  };

  const advanceCue = () => {
    setCueIndex((current) => Math.min(LAST_CUE_INDEX, current + 1));
    setCueElapsed(0);
  };

  const area = AREAS[cueIndex];
  const isRunning = demoState === "active" || demoState === "paused";
  const status =
    demoState === "ready"
      ? "A short look at the reset"
      : demoState === "active"
        ? "Moving gently"
        : demoState === "paused"
          ? "Paused when you are ready"
          : "That’s it. Welcome back.";

  return (
    <div className="demo-card" aria-label="Playable 2m2better preview" data-demo-duration={PREVIEW_SECONDS}>
      <div className="demo-card-top">
        <div className="demo-orb orb-surface orb-state-approaching" aria-hidden="true">
          <OrbFace />
        </div>
        <div className="demo-prompt">
          <span>A small pause?</span>
          <strong>{BREAK_PROMPT}</strong>
        </div>
        <span className="demo-preview-label">12 sec preview</span>
      </div>

      <div className="demo-status" aria-live="polite">
        <span className="status-dot" aria-hidden="true" />
        <span>{status}</span>
      </div>

      <div className="demo-cue" aria-live="polite">
        {demoState === "done" ? null : <span className="demo-cue-area">{area.title}</span>}
        {demoState === "done" ? "Take what you need, then carry on." : area.cue}
      </div>

      <div className="demo-progress-row">
        <div
          className="demo-progress"
          role="progressbar"
          aria-label="Preview progress"
          aria-valuemin={0}
          aria-valuemax={PREVIEW_SECONDS}
          aria-valuenow={PREVIEW_SECONDS - remaining}
        >
          <span style={{ width: `${((PREVIEW_SECONDS - remaining) / PREVIEW_SECONDS) * 100}%` }} />
        </div>
        <span className="demo-time" aria-label={`${remaining} seconds remaining`}>
          {remaining.toString().padStart(2, "0")}s
        </span>
      </div>

      <div className="demo-controls" aria-label="Preview controls">
        <button className="button button-demo-start" type="button" onClick={startPreview} disabled={demoState !== "ready"}>
          Start <Arrow />
        </button>
        <button
          className="button button-demo-control"
          type="button"
          onClick={() => setDemoState((current) => (current === "active" ? "paused" : "active"))}
          disabled={!isRunning}
        >
          {demoState === "paused" ? "Resume" : "Pause"}
        </button>
        <button
          className="button button-demo-control"
          type="button"
          onClick={advanceCue}
          disabled={!isRunning || cueIndex === LAST_CUE_INDEX}
        >
          Next cue
        </button>
        <button className="button button-demo-control" type="button" onClick={() => setDemoState("done")} disabled={!isRunning}>
          End
        </button>
        <button className="demo-reset" type="button" onClick={resetPreview} disabled={demoState !== "done"}>
          Try again
        </button>
      </div>

      <p className="demo-footnote" id="demo-note">
        Click-only preview. The app keeps the real reset simple, visible, and easy to stop.
      </p>
    </div>
  );
}

export default function Home() {
  const demoRef = useRef<HTMLElement>(null);
  const heroVisualRef = useRef<HTMLDivElement>(null);
  const commandRef = useRef<HTMLPreElement>(null);
  const [areaIndex, setAreaIndex] = useState(0);
  const [reducedMotion, setReducedMotion] = useState(false);
  const [orbState, setOrbState] = useState<OrbState>("resting");
  const [orbFloating, setOrbFloating] = useState(false);
  const [copyState, setCopyState] = useState<CopyState>("idle");
  const area = AREAS[areaIndex];

  useEffect(() => {
    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    const updateMotionPreference = () => setReducedMotion(media.matches);
    updateMotionPreference();
    media.addEventListener?.("change", updateMotionPreference);
    return () => media.removeEventListener?.("change", updateMotionPreference);
  }, []);

  useEffect(() => {
    if (reducedMotion) return;

    const rotation = window.setInterval(() => {
      setAreaIndex((current) => (current + 1) % AREAS.length);
    }, 3200);
    return () => window.clearInterval(rotation);
  }, [reducedMotion]);

  useEffect(() => {
    let frame = 0;

    const updateOrbState = () => {
      const section = demoRef.current;
      if (!section) return;
      const demo = section.getBoundingClientRect();
      const viewport = window.innerHeight;
      setOrbState(demo.top < viewport * 0.38 ? "due" : demo.top < viewport * 0.92 ? "approaching" : "resting");

      const heroVisual = heroVisualRef.current;
      setOrbFloating(heroVisual !== null && heroVisual.getBoundingClientRect().bottom < 0 && demo.bottom > 0);
    };

    const scheduleUpdate = () => {
      if (frame) return;
      frame = window.requestAnimationFrame(() => {
        frame = 0;
        updateOrbState();
      });
    };

    updateOrbState();
    window.addEventListener("scroll", scheduleUpdate, { passive: true });
    window.addEventListener("resize", scheduleUpdate);
    return () => {
      if (frame) window.cancelAnimationFrame(frame);
      window.removeEventListener("scroll", scheduleUpdate);
      window.removeEventListener("resize", scheduleUpdate);
    };
  }, []);

  function selectInstallerCommand() {
    const command = commandRef.current;
    if (!command) return;
    const selection = window.getSelection();
    if (!selection) return;
    const range = document.createRange();
    range.selectNodeContents(command);
    selection.removeAllRanges();
    selection.addRange(range);
  }

  async function copyInstaller() {
    try {
      if (!navigator.clipboard) throw new Error("Clipboard unavailable");
      await navigator.clipboard.writeText(INSTALL_COMMAND);
      setCopyState("success");
    } catch {
      selectInstallerCommand();
      setCopyState("fallback");
    }
  }

  const orbMessage =
    orbState === "resting"
      ? "The next pause is a little way off."
      : orbState === "approaching"
        ? "A pause is getting closer."
        : "The reset is close.";
  const copyLabel =
    copyState === "success"
      ? "Copied to clipboard"
      : copyState === "fallback"
        ? "Command selected - copy manually"
        : "Copy command";

  return (
    <>
      <div className={`floating-orb orb-state-${orbState}`} data-visible={orbFloating} aria-hidden="true">
        <span className="floating-orb-face orb-surface">
          <OrbFace />
        </span>
        <span className="floating-orb-text">
          <span>break proximity</span>
          <strong>{orbMessage}</strong>
        </span>
      </div>

      <main>
        <nav className="nav shell" aria-label="Primary navigation">
          <a className="wordmark" href="#top" aria-label="2m2better home">
            <span className="wordmark-dot" aria-hidden="true" />
            2m<span>2</span>better
          </a>
          <div className="nav-links">
            <a href="#how-it-works">How it works</a>
            <a href="#faq">FAQ</a>
            <a href="#privacy">Privacy</a>
          </div>
          <a className="nav-action" href="#install">
            Install preview <Arrow />
          </a>
        </nav>

        <section className="hero shell" id="top">
          <div className="hero-copy">
            <p className="eyebrow">For developers with one more prompt to watch</p>
            <h1>Your agent can keep working. Give your body two minutes.</h1>
            <p className="hero-tagline">A two-minute reset that helps your body keep up with your mind.</p>
            <p className="area-promise" aria-live="polite" aria-atomic="true">
              2 mins to better your <span className="area-word">{area.label}</span>.
            </p>
            <p className="area-fallback">neck · shoulders · hands + wrists · lower back</p>
            <p className="hero-lede">
              2m2better is a small, local macOS companion for the stiff feeling that arrives after too long at the screen.
              Take the pause between prompts; come back when you are ready.
            </p>
            <div className="hero-actions">
              <a className="button button-primary" href="#install">
                Copy and paste in your terminal to install
              </a>
              <a className="text-link" href="#how-it-works">
                See how the reset works
              </a>
            </div>
            <p className="hero-note">Free developer preview · macOS 14+ · no account</p>
          </div>

          <div className="hero-visual" ref={heroVisualRef}>
            <div className={`orb-stage orb-state-${orbState}`} aria-label="Break proximity preview">
              <div className="stage-note note-one">
                <span>while work keeps moving</span>
                <strong>one small invitation</strong>
              </div>
              <div className="orb-halo" aria-hidden="true" />
              <div className="hero-orb orb-surface" role="img" aria-label={`2m2better orb. ${orbMessage}`}>
                <OrbFace />
              </div>
              <div className="progress-caption" aria-live="polite">
                <span className="progress-swatch" aria-hidden="true" />
                <div>
                  <span>break proximity</span>
                  <strong>{orbMessage}</strong>
                </div>
              </div>
              <div className="stage-note note-two">
                <strong>your call, always</strong>
                <span>not watching your agent</span>
              </div>
            </div>
          </div>
        </section>

        <section className="problem-section" id="problem" aria-labelledby="problem-title">
          <div className="shell problem-grid">
            <div className="section-marker" aria-hidden="true">
              <span>01</span>
              <span>the body / the day</span>
            </div>
            <div className="problem-copy">
              <p className="eyebrow">The part of the day we forget</p>
              <h2 id="problem-title">The screen gets your attention. Your body still needs some.</h2>
              <p>
                A long stretch of prompts, tabs, and tiny decisions can leave your neck, shoulders, hands + wrists,
                or lower back feeling stiff. Not a crisis. Just a good moment to change position.
              </p>
            </div>
            <div className="problem-aside">
              <span className="aside-line" aria-hidden="true" />
              <p>When an agent is busy, you have a natural in-between moment. 2m2better gives that moment somewhere to go.</p>
            </div>
          </div>
        </section>

        <section className="benefits-section" id="benefits" aria-labelledby="benefits-title">
          <div className="shell benefits-inner">
            <div className="section-intro">
              <p className="eyebrow">What the two minutes give back</p>
              <h2 id="benefits-title">Small by design. Useful by feel.</h2>
            </div>
            <div className="benefits-grid">
              <article className="benefit">
                <span className="benefit-index">01</span>
                <h3>Keep the thread</h3>
                <p>A short reset lets you step away without turning your workday into a new project.</p>
              </article>
              <article className="benefit">
                <span className="benefit-index">02</span>
                <h3>Choose the moment</h3>
                <p>Start, Later, and Tomorrow stay visible. Postponing is allowed; there is no wrong answer.</p>
              </article>
              <article className="benefit">
                <span className="benefit-index">03</span>
                <h3>Keep it close</h3>
                <p>Local processing, no account, no dashboard, and no in-app network connection to manage.</p>
              </article>
            </div>
          </div>
        </section>

        <section className="flow-section" id="how-it-works" aria-labelledby="flow-title">
          <div className="shell flow-grid">
            <div className="flow-copy">
              <p className="eyebrow">How it works</p>
              <h2 id="flow-title">A quiet nudge. A clear choice. Two minutes.</h2>
              <p>
                The companion keeps the moment easy to understand and easy to leave. Spoken guidance is optional;
                the written routine and the controls stay on screen.
              </p>
              <ol className="flow-list">
                <li>
                  <span>01</span>
                  <div><strong>Notice</strong><p>A gentle check-in arrives after a long stretch at the screen.</p></div>
                </li>
                <li>
                  <span>02</span>
                  <div><strong>Choose</strong><p>Start, Later, or Tomorrow - all visible and keyboard accessible.</p></div>
                </li>
                <li>
                  <span>03</span>
                  <div><strong>Reset</strong><p>Move comfortably through one short routine, then carry on.</p></div>
                </li>
              </ol>
            </div>
            <CheckinWindow />
          </div>
        </section>

        <section className="demo-section" id="preview" ref={demoRef} aria-labelledby="demo-title">
          <div className="shell demo-grid">
            <div className="demo-copy">
              <p className="eyebrow">Try a small preview</p>
              <h2 id="demo-title">See the shape of the pause before you install it.</h2>
              <p>
                This 12-second preview moves through the areas the real two-minute reset can visit. Start it with a
                click; keep every control in reach.
              </p>
              <div className="demo-steps" aria-label="Preview flow">
                <span><b>01</b> Start</span>
                <span><b>02</b> Move gently</span>
                <span><b>03</b> Come back</span>
              </div>
            </div>
            <DemoPreview />
          </div>
        </section>

        <section className="principles" id="privacy" aria-labelledby="principles-title">
          <div className="shell principles-inner">
            <div>
              <p className="eyebrow eyebrow-light">Built to stay small</p>
              <h2 id="principles-title">Support your day without taking it over.</h2>
            </div>
            <div className="principle-list">
              <article>
                <span>01</span>
                <div>
                  <h3>Local from the start</h3>
                  <p>Your break companion runs locally on your Mac. No account, analytics, or in-app network connection.</p>
                </div>
              </article>
              <article>
                <span>02</span>
                <div>
                  <h3>No agent awareness</h3>
                  <p>It does not detect or coordinate your coding agent. The agent context is simply a good time to choose a pause.</p>
                </div>
              </article>
              <article>
                <span>03</span>
                <div>
                  <h3>Never a performance test</h3>
                  <p>Move in a comfortable range. Start, postpone, skip, or end whenever you need.</p>
                </div>
              </article>
            </div>
          </div>
        </section>

        <section className="faq-section" id="faq" aria-labelledby="faq-title">
          <div className="shell faq-inner">
            <div className="section-intro">
              <p className="eyebrow">A few useful answers</p>
              <h2 id="faq-title">Before you give it two minutes.</h2>
            </div>
            <div className="faq-list">
              <details open>
                <summary>Does 2m2better know what my coding agent is doing?</summary>
                <p>No. The current developer preview does not detect or coordinate agent activity. The agent angle is just a natural moment to choose a break while work keeps running.</p>
              </details>
              <details>
                <summary>What happens during the reset?</summary>
                <p>You get one gentle, visible movement suggestion for your neck, shoulders, hands + wrists, or lower back. Move comfortably and stop whenever you need; spoken guidance is optional.</p>
              </details>
              <details>
                <summary>Do I need an account or dashboard?</summary>
                <p>No. 2m2better processes locally on your Mac and has no account, dashboard, analytics, or in-app network connection.</p>
              </details>
              <details>
                <summary>Can I say not now?</summary>
                <p>Yes. Start, Later, and Tomorrow stay visible as equal, keyboard-accessible choices. Postponing is part of the design.</p>
              </details>
              <details>
                <summary>What does the free developer preview need?</summary>
                <p>macOS 14 or newer on arm64 or Intel x86_64, GitHub HTTPS access, and standard macOS tools. It is ad-hoc signed and not notarized, so macOS may ask you to approve it.</p>
              </details>
            </div>
          </div>
        </section>

        <section className="installer" id="install" aria-labelledby="installer-title">
          <div className="shell installer-inner">
            <div className="installer-copy">
              <p className="eyebrow">Free developer preview for macOS</p>
              <h2 id="installer-title">Give your body two minutes. Keep your work moving.</h2>
              <p>
                The public installer selects your Mac architecture, verifies a matching GitHub Release ZIP and checksum,
                and installs the local app for macOS 14 or newer.
              </p>
              <ul className="requirements">
                <li>macOS 14+ on arm64 or x86_64</li>
                <li>GitHub HTTPS access and standard macOS tools</li>
                <li>Ad-hoc signed developer preview; no Developer ID or notarization</li>
              </ul>
            </div>
            <div className="command-card">
              <div className="command-heading">
                <span>Copy and paste in your terminal to install</span>
                <span>auditable · verified GitHub Release</span>
              </div>
              <pre ref={commandRef} tabIndex={0} aria-label="Installer command; select this text to copy manually"><code>{INSTALL_COMMAND}</code></pre>
              <button className="copy-button" type="button" onClick={copyInstaller} aria-describedby="copy-status">
                {copyLabel}
              </button>
              <p className="copy-invite" id="copy-status" aria-live="polite">
                {copyState === "success"
                  ? "The installer command is on your clipboard."
                  : copyState === "fallback"
                    ? "Clipboard access was unavailable, so the command is selected. Press ⌘C or Ctrl+C to copy it."
                    : "Copy the one-liner, paste it into Terminal, and review the preview as it installs."}
              </p>
              <p className="command-note">
                The one-liner downloads the installer from the public repository, verifies a matching release ZIP and exact
                checksum, then installs to ~/Applications. macOS may require Finder Open or Privacy &amp; Security approval.
              </p>
            </div>
          </div>
        </section>

        <section className="closing">
          <div className="shell closing-inner">
            <div className="closing-orb orb-surface orb-state-resting" aria-hidden="true"><OrbFace /></div>
            <p>Two minutes for your body.</p>
            <h2>Then back to what you were making.</h2>
            <a className="button button-light" href="#install">
              Copy and paste in your terminal to install
            </a>
          </div>
        </section>

        <footer className="shell footer">
          <a className="wordmark footer-mark" href="#top">
            <span className="wordmark-dot" aria-hidden="true" />
            2m<span>2</span>better
          </a>
          <p>2m2better for macOS · gentle by design</p>
          <p>Local. Private. Yours.</p>
        </footer>
      </main>
    </>
  );
}
