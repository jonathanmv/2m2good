"use client";

import { useEffect, useRef, useState } from "react";

const AREAS = [
  { label: "neck", title: "Neck", cue: "turn a little, stay comfortable" },
  { label: "shoulders", title: "Shoulders", cue: "let them move a little" },
  { label: "hands + wrists", title: "Hands + wrists", cue: "open and soften your hands" },
  { label: "lower back", title: "Lower back", cue: "shift gently and change position" },
] as const;

const BREAK_PROMPT = "Ready for a gentle reset?";
const PREVIEW_SECONDS = 12;
const CUE_SECONDS = PREVIEW_SECONDS / AREAS.length;
const LAST_CUE_INDEX = AREAS.length - 1;
const INSTALL_COMMAND = `curl -fsSL https://raw.githubusercontent.com/jonathanmv/2m2good/main/scripts/install.sh | sh`;

type OrbState = "resting" | "approaching" | "due";
type DemoState = "ready" | "active" | "paused" | "done";

const Arrow = () => <span aria-hidden="true">↘</span>;

function OrbFace() {
  return (
    <>
      <span className="orb-eye" />
      <span className="orb-eye" />
    </>
  );
}

function DemoPreview() {
  const [demoState, setDemoState] = useState<DemoState>("ready");
  const [cueIndex, setCueIndex] = useState(0);
  const [cueElapsed, setCueElapsed] = useState(0);
  const remaining = PREVIEW_SECONDS - (cueIndex * CUE_SECONDS + cueElapsed);

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
  const cue = area.cue;
  const isRunning = demoState === "active" || demoState === "paused";
  const status =
    demoState === "ready"
      ? "A short preview of the reset"
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
        <span className="demo-preview-label">Preview</span>
      </div>

      <div className="demo-status" aria-live="polite">
        <span className="status-dot" aria-hidden="true" />
        <span>{status}</span>
      </div>

      <div className="demo-cue" aria-live="polite">
        {demoState === "done" ? null : <span className="demo-cue-area">{area.title}</span>}
        {demoState === "done" ? "Take what you need, then carry on." : cue}
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
        <button
          className="button button-demo-start"
          type="button"
          onClick={startPreview}
          disabled={demoState !== "ready"}
        >
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
        <button
          className="button button-demo-control"
          type="button"
          onClick={() => setDemoState("done")}
          disabled={!isRunning}
        >
          End
        </button>
        <button className="demo-reset" type="button" onClick={resetPreview} disabled={demoState !== "done"}>
          Try again
        </button>
      </div>

      <p className="demo-footnote" id="demo-note">
        Click-only preview. The app keeps these controls visible for a quiet path through the reset.
      </p>
    </div>
  );
}

export default function Home() {
  const demoRef = useRef<HTMLElement>(null);
  const heroVisualRef = useRef<HTMLDivElement>(null);
  const [areaIndex, setAreaIndex] = useState(0);
  const [reducedMotion, setReducedMotion] = useState(false);
  const [orbState, setOrbState] = useState<OrbState>("resting");
  const [orbFloating, setOrbFloating] = useState(false);
  const [copyStatus, setCopyStatus] = useState("Copy command");
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
      setOrbFloating(
        heroVisual !== null && heroVisual.getBoundingClientRect().bottom < 0 && demo.bottom > 0,
      );
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

  async function copyInstaller() {
    try {
      await navigator.clipboard.writeText(INSTALL_COMMAND);
      setCopyStatus("Copied");
    } catch {
      setCopyStatus("Select the command to copy it");
    }
  }

  const orbMessage =
    orbState === "resting"
      ? "The next pause is a little way off."
      : orbState === "approaching"
        ? "A pause is getting closer."
        : "The reset is close.";

  return (
    <>
      <div
        className={`floating-orb orb-state-${orbState}`}
        data-visible={orbFloating}
        aria-hidden="true"
      >
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
            <a href="#areas">Your areas</a>
            <a href="#demo">Try the preview</a>
            <a href="#privacy">Privacy</a>
          </div>
          <a className="nav-action" href="#developer-preview">
            Developer preview <Arrow />
          </a>
        </nav>

        <section className="hero shell" id="top">
          <div className="hero-copy">
            <p className="eyebrow">A small companion for screen-heavy days</p>
            <h1>
              Give your body a little room to move, then come back to your day.
            </h1>
            <p className="area-promise" aria-live="polite" aria-atomic="true">
              2 mins to better your <span className="area-word">{area.label}</span>.
            </p>
            <p className="area-fallback">
              neck · shoulders · hands + wrists · lower back
            </p>
            <p className="hero-lede">
              2m2better offers one gentle, local reset for the part of you that
              needs a change of position. Choose Start, come back later, or stay
              with what you&apos;re doing.
            </p>
            <div className="hero-actions">
              <a className="button button-primary" href="#demo">
                Try the reset <Arrow />
              </a>
              <a className="text-link" href="#areas">
                See the areas
              </a>
            </div>
          </div>

          <div className="hero-visual" ref={heroVisualRef}>
            <div className={`orb-stage orb-state-${orbState}`} aria-label="Break proximity preview">
              <div className="stage-note note-one">
                <span>quietly nearby</span>
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
                <strong>teal → clay → quiet plum</strong>
                <span>as the preview gets closer</span>
              </div>
            </div>
          </div>
        </section>

        <section className="areas-section" id="areas">
          <div className="shell areas-grid">
            <div className="areas-copy">
              <p className="eyebrow">A little more specific</p>
              <h2>Meet your body where it is.</h2>
              <p>
                The invitation stays small, while the focus can feel personal.
                2m2better rotates through four plain-language areas and keeps the
                choice easy to change.
              </p>
            </div>
            <div className="area-list" aria-label="Available movement areas">
              {AREAS.map((item, index) => (
                <div className={`area-row ${index === areaIndex ? "area-row-active" : ""}`} key={item.label}>
                  <span className="area-row-index">0{index + 1}</span>
                  <strong>{item.title}</strong>
                  <span>{item.cue}</span>
                </div>
              ))}
            </div>
          </div>
        </section>

        <section className="checkin-section" aria-labelledby="checkin-title">
          <div className="shell checkin-grid">
            <div className="checkin-copy">
              <p className="eyebrow">The first moment</p>
              <h2 id="checkin-title">One suggestion. Your call.</h2>
              <p>
                A quiet orb offers the next reset without asking you to plan a
                routine. Start now, choose later, or leave it for another day.
              </p>
            </div>
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
                <button type="button" className="start-choice">Start</button>
                <div className="quiet-choices">
                  <button type="button">Later</button>
                  <button type="button">Tomorrow</button>
                </div>
              </div>
              <p className="button-note">The three responses stay visible for a quiet, click-only decision.</p>
            </div>
          </div>
        </section>

        <section className="demo-section" id="demo" ref={demoRef} aria-labelledby="demo-title">
          <div className="shell demo-grid">
            <div className="demo-copy">
              <p className="eyebrow">Scroll-led preview</p>
              <h2 id="demo-title">See the pause before you install it.</h2>
              <p>
                As you approach this section, the orb shifts from distant teal
                toward its warmer clay signal. Start the preview with
                a click and keep every control in reach.
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

        <section className="principles" aria-labelledby="principles-title">
          <div className="shell principles-inner">
            <div>
              <p className="eyebrow eyebrow-light">The shape of it</p>
              <h2 id="principles-title">Small enough to keep.</h2>
            </div>
            <div className="principle-list">
              <article>
                <span>01</span>
                <div>
                  <h3>Ask, never command</h3>
                  <p>Start, later, tomorrow, or not this time. There is no wrong answer.</p>
                </div>
              </article>
              <article>
                <span>02</span>
                <div>
                  <h3>Support, don&apos;t score</h3>
                  <p>No streaks, scores, dashboards, or performance story to keep up with.</p>
                </div>
              </article>
              <article>
                <span>03</span>
                <div>
                  <h3>Leave room for you</h3>
                  <p>Move in a comfortable range. Pause, skip, or end whenever you need.</p>
                </div>
              </article>
            </div>
          </div>
        </section>

        <section className="privacy shell" id="privacy" aria-labelledby="privacy-title">
          <div className="privacy-orbit" aria-hidden="true">
            <div className="privacy-orb orb-surface orb-state-resting"><OrbFace /></div>
          </div>
          <div className="privacy-copy">
            <p className="eyebrow">Personal means personal</p>
            <h2 id="privacy-title">Your breaks stay close to home.</h2>
            <p>
              The companion runs locally on your Mac once installed. No account,
              analytics, or in-app network connection. Spoken movement guidance
              complements the on-screen routine; the check-in stays click-only.
            </p>
            <div className="privacy-notes" aria-label="Privacy commitments">
              <span>no account</span>
              <span>no analytics</span>
              <span>buttons always available</span>
            </div>
          </div>
        </section>

        <section className="installer" id="developer-preview" aria-labelledby="installer-title">
          <div className="shell installer-inner">
            <div className="installer-copy">
              <p className="eyebrow">Early developer preview</p>
              <h2 id="installer-title">Install the companion. Keep the choice yours.</h2>
              <p>
                This is a developer preview, not a consumer download. The public
                installer selects your Mac architecture, verifies a GitHub Release,
                and installs the local app for macOS 14 or newer.
              </p>
              <ul className="requirements">
                <li>macOS 14+ on arm64 or x86_64</li>
                <li>GitHub HTTPS access and standard macOS tools</li>
                <li>ZIP and exact SHA-256 checksum assets in the release</li>
              </ul>
            </div>
            <div className="command-card">
              <div className="command-heading">
                <span>Public installer</span>
                <span>auditable · verified GitHub Release</span>
              </div>
              <pre><code>{INSTALL_COMMAND}</code></pre>
              <button className="copy-button" type="button" onClick={copyInstaller}>
                {copyStatus}
              </button>
              <p className="copy-invite" aria-live="polite">
                Copy this into your terminal, or ask your coding agent to install it for you.
              </p>
              <p className="command-note">
                The one-liner downloads the installer from the public repository,
                verifies a matching GitHub Release ZIP and checksum, and installs
                to ~/Applications. This ad-hoc-signed developer preview has no
                Developer ID signature or notarization; macOS may require approval.
              </p>
            </div>
          </div>
        </section>

        <section className="closing">
          <div className="shell closing-inner">
            <div className="closing-orb orb-surface orb-state-resting" aria-hidden="true"><OrbFace /></div>
            <p>A little room to move.</p>
            <h2>Then back to your day.</h2>
            <a className="button button-light" href="#developer-preview">
              View the developer preview <Arrow />
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
