const Arrow = () => <span aria-hidden="true">↘</span>;

export default function Home() {
  return (
    <main>
      <nav className="nav shell" aria-label="Primary navigation">
        <a className="wordmark" href="#top" aria-label="2mintogood home">
          <span className="wordmark-dot" aria-hidden="true" />
          2min<span>to</span>good
        </a>
        <div className="nav-links">
          <a href="#how-it-feels">How it feels</a>
          <a href="#principles">Principles</a>
          <a href="#privacy">Privacy</a>
        </div>
        <a className="nav-action" href="#two-minutes">
          Take two minutes <Arrow />
        </a>
      </nav>

      <section className="hero shell" id="top">
        <div className="hero-copy">
          <p className="eyebrow">A gentle desktop companion for macOS</p>
          <h1>
            A two-minute reset that helps your body{" "}
            <span className="soft-underline">keep up with your mind.</span>
          </h1>
          <p className="hero-lede">
            When you&apos;ve been at the screen for a while, a small orb checks
            in. Stand, move gently, and come right back. No coaching. No
            keeping score.
          </p>
          <div className="hero-actions">
            <a className="button button-primary" href="#how-it-feels">
              See how it feels <Arrow />
            </a>
            <a className="text-link" href="#two-minutes">
              Two minutes, exactly
            </a>
          </div>
        </div>

        <div className="orb-stage" aria-label="Break Companion preview">
          <div className="stage-note note-one">
            <span>small enough to stay</span>
            <strong>out of your way</strong>
          </div>
          <div className="orb-halo" aria-hidden="true" />
          <div
            className="hero-orb"
            role="img"
            aria-label="A calm green orb gently breathing. The next break is still a while away."
          >
            <span className="orb-eye" />
            <span className="orb-eye" />
          </div>
          <div className="progress-caption">
            <span className="progress-swatch" aria-hidden="true" />
            <div>
              <span>next check-in</span>
              <strong>still a while away</strong>
            </div>
          </div>
          <div className="stage-note note-two">
            <strong>green → orange → warm red</strong>
            <span>as a break gets closer</span>
          </div>
        </div>
      </section>

      <section className="flow-section" id="how-it-feels">
        <div className="shell flow-grid">
          <div className="section-intro">
            <p className="eyebrow">It asks. You decide.</p>
            <h2>A nudge, not a negotiation.</h2>
            <p>
              One suggestion. Three easy answers. Saying “later” is normal, not
              a broken streak.
            </p>
          </div>

          <div className="checkin-window" aria-label="Example break check-in">
            <div className="window-top">
              <div className="mini-orb" aria-hidden="true">
                <i />
                <i />
              </div>
              <div>
                <span>A small pause?</span>
                <strong>Ready to stand for a gentle reset?</strong>
              </div>
            </div>
            <div className="choice-stack" aria-label="Available responses">
              <button type="button" className="start-choice">
                Start <span>2 min</span>
              </button>
              <div className="quiet-choices">
                <button type="button">In an hour</button>
                <button type="button">Tomorrow</button>
              </div>
            </div>
            <p className="voice-line">
              <span className="voice-bars" aria-hidden="true">
                <i />
                <i />
                <i />
                <i />
              </span>
              Or just say “yeah”, “later”, or “tomorrow”
            </p>
          </div>
        </div>
      </section>

      <section className="two-minutes shell" id="two-minutes">
        <div className="time-mark" aria-hidden="true">
          2:00
        </div>
        <div className="time-story">
          <p className="eyebrow">Short on purpose</p>
          <h2>Your train of thought can wait two minutes. It won&apos;t leave.</h2>
          <p>
            Six gentle standing movements, guided one at a time by voice. A
            shoulder roll, a soft reach, a little weight shift. Nothing
            athletic. Nothing to learn.
          </p>
          <div className="movement-line" aria-label="Example two-minute session">
            <span>stand</span>
            <i />
            <span>roll</span>
            <i />
            <span>reach</span>
            <i />
            <span>breathe</span>
            <i />
            <span>return</span>
          </div>
        </div>
      </section>

      <section className="principles" id="principles">
        <div className="shell principles-inner">
          <p className="principles-kicker">
            A break companion
            <br />
            that knows its place.
          </p>
          <div className="principle-list">
            <article>
              <span>01</span>
              <div>
                <h3>Protect the flow</h3>
                <p>Easy to accept, easy to postpone, easy to finish.</p>
              </div>
            </article>
            <article>
              <span>02</span>
              <div>
                <h3>Ask, never command</h3>
                <p>You choose now, later, tomorrow, or not at all.</p>
              </div>
            </article>
            <article>
              <span>03</span>
              <div>
                <h3>Voice-first, never voice-only</h3>
                <p>Speak naturally, or use the quiet buttons beside you.</p>
              </div>
            </article>
          </div>
        </div>
      </section>

      <section className="privacy shell" id="privacy">
        <div className="privacy-orbit" aria-hidden="true">
          <div className="privacy-orb">
            <i />
            <i />
          </div>
        </div>
        <div className="privacy-copy">
          <p className="eyebrow">Personal means personal</p>
          <h2>Your breaks stay on your Mac.</h2>
          <p>
            No account to create. No network connection. No analytics watching
            whether you stood up. Just a small companion, working locally.
          </p>
          <div className="privacy-notes" aria-label="Privacy commitments">
            <span>no account</span>
            <span>no network</span>
            <span>no analytics</span>
          </div>
        </div>
      </section>

      <section className="closing">
        <div className="shell closing-inner">
          <div className="closing-orb" aria-hidden="true">
            <i />
            <i />
          </div>
          <p>Two minutes for your body.</p>
          <h2>Then back to what matters.</h2>
          <a className="button button-light" href="#top">
            Meet 2mintogood <span aria-hidden="true">↑</span>
          </a>
        </div>
      </section>

      <footer className="shell footer">
        <a className="wordmark footer-mark" href="#top">
          <span className="wordmark-dot" aria-hidden="true" />
          2min<span>to</span>good
        </a>
        <p>Break Companion for macOS · gentle by design</p>
        <p>Local. Private. Yours.</p>
      </footer>
    </main>
  );
}
