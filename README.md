# 2m2better

A deliberately small, local macOS break companion. After enough weighted active-use credit (60 minutes by default), 2m2better's quiet floating orb offers one two-minute reset. It keeps the Start, Later, and Tomorrow choices clear, guides the routine with spoken movement guidance and motion, and then gets out of the way.

## What is in the pilot

- A small floating orb plus a menu-bar fallback; no dashboard, browsable pause history, streaks, or account.
- Active-use timing that earns cadence credit at 1x while the Mac is active and discounts inactive time at 0.5x, never below zero; delayed callbacks and sleep gaps never turn the elapsed gap into work credit.
- Warm check-ins with **Start**, **Later** (one hour), and **Tomorrow**, plus a small chevron-up collapse control when the choice needs to wait without changing. An unhandled offer reappears five minutes after it is collapsed and continues every five minutes until the user chooses a response.
- A subtle durable local context line shows the last completed pause with compact relative wording, or **Last pause taken — none yet** on a fresh install.
- Click-only check-in responses: **Start**, **Later** (one hour), and **Tomorrow**, with keyboard-accessible controls.
- A library of gentle, standing-compatible desk-break movements. Each offered session combines six different 20-second movements into a fresh two-minute reset.
- On first launch, choose a pause rhythm (**Every 20 minutes**, **Every hour**, or **Every 3 hours**) and one or more areas to support: **Lower back**, **Neck**, **Shoulders**, or **Hands + wrists**, or keep the balanced mix. Settings stay local and can be reviewed from the menu bar without becoming a dashboard or body-data profile.
- Every session is exactly 120 seconds, with a gentle standing invitation, on-screen and spoken movement guidance, simple motion cues, Pause, Next, End, and safety wording.
- **Next** immediately composes a new session from 2:00 and avoids every move in the current session. Moves are recorded when shown, so skipped and switched sessions also reduce near-term repetition.
- The Done screen closes itself after about 10 seconds; Return or Enter closes it immediately.
- Selection state is bounded to 18 recently shown and 24 recently completed movement identifiers, alongside the selected areas, in local macOS preferences. Older routine history is migrated into conservative move-focus history once, and an existing install keeps its history and continues on the balanced mix instead of being asked to set up again. Break processing and history stay local; the optional updater is documented in [`docs/RELEASES.md`](docs/RELEASES.md).

## Build and run

Requires macOS 14 or newer on an arm64 or x86_64 Mac, plus Xcode 15 or
newer or the matching Apple Command Line Tools.

```sh
./scripts/build-app.sh
open ".build/app/2m2better.app"
```

The app appears as a small orb near the upper-right of the screen on ordinary
desktop Spaces, and as a leaf in the menu bar. On a fresh install, a compact setup asks for a pause rhythm and which body areas the standing reset should support; every shipped movement is standing-only, so the reset is presented as a standing one rather than a seated alternative. Click the orb or **Offer a break now** in the menu bar to trigger a break immediately; use the small chevron-up control (or Escape) to return to the orb without choosing a response, then click the orb or use **Show pause choices** again to restore the choices. If the offer remains unhandled, the same choices reappear five minutes after collapse and every five minutes thereafter; restoring or interacting with the orb does not dismiss it. **Start**, **Later**, or **Tomorrow** stops those repeat reminders. A pending offer is shown in a warm due color in both its full and collapsed presentations. The pause window can be dragged from its non-control background like a normal desktop window. Use **Settings…** there to review or change the selection; it remains actionable from the orb, an undecided offer, a routine, or the completion screen without discarding that state.

The menu also includes **Settings…**, which changes the pause rhythm and body areas, and **Copy diagnostics**, which places a coarse local status report on the clipboard. **About 2m2better…** shows the shared release identity, and **Check for Updates…** checks GitHub Releases only. When a newer release is available, a short prompt offers **Install and Relaunch** or **Later**. Choosing install downloads and verifies in the background, shows brief progress, then hands off to the installer without a second technical confirmation. Installation is never silent. The helper waits for this app to exit, replaces only `~/Applications/2m2better.app`, retains a rollback copy, preserves preferences, and asks macOS to relaunch. Recoverable errors offer **Try Again** and write technical details to the update log. See [`docs/RELEASES.md`](docs/RELEASES.md) for the updater behavior, trust limitation, release asset contract, icon packaging, and validation.

This development Mac currently has a newer command-line compiler paired with a slightly mismatched newest SDK. On this machine only, build with its compatible installed SDK:

```sh
BREAK_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ./scripts/build-app.sh
```

## One-line macOS developer-preview installer

Install the latest published developer-preview release from GitHub Releases:

```sh
curl -fsSL https://raw.githubusercontent.com/jonathanmv/2m2good/main/scripts/install.sh | sh
```

The installer selects the current `arm64` or Intel `x86_64` architecture,
requires matching ZIP and `.sha256` assets in the latest GitHub Release, and
verifies the exact SHA-256 checksum before extracting anything. It installs
without `sudo` to the invoking user's `~/Applications/2m2better.app`, refreshes
Spotlight indexing, and launches the app or prints a manual launch command.
When `~/Applications/2m2better.app` already exists, it asks only 2m2better to
quit gracefully, retains the old app in a timestamped `.previous` backup, and
relaunches the verified replacement; `--replace` remains accepted for older
scripts. It does not delete user data, use credentials, or contact a separate
update server.

Prerequisites are macOS 14 (Sonoma) or newer, GitHub HTTPS access, and the
standard macOS `curl`, `plutil`, `shasum`, `ditto`, `sw_vers`, and `osascript` tools.
Xcode and Swift are not required for the packaged installer. This is an
ad-hoc-signed developer preview: it has no Apple Developer ID signature and is
not notarized, so macOS may require Finder **Open** or Privacy & Security
approval. The installer does not bypass Gatekeeper. Release packaging,
checksum requirements, and updater compatibility are documented in
[`docs/RELEASES.md`](docs/RELEASES.md); the source-build alternative is in
[`docs/DEVELOPER_PREVIEW.md`](docs/DEVELOPER_PREVIEW.md).

## Permissions

The check-in is click-only: **Start**, **Later**, and **Tomorrow** remain visible and keyboard-accessible. The small chevron-up control (or Escape) collapses an undecided offer without choosing a response, so no audio-input or command-recognition permission is needed. During a routine, spoken movement guidance complements the on-screen instructions; the app does not listen for responses.

The app does not need Accessibility permission. It reads only macOS’s aggregate local time since the last keyboard, mouse movement (including drags), mouse-button, or scroll event, not the keys pressed or the content of events. Live timer, pending-offer reminder, and session checkpoints are kept under `~/Library/Application Support/2m2better`, outside the replaceable app bundle. A relaunch preserves an undecided offer and its next reminder; an overdue reminder is delivered once and then moved to the next five-minute deadline.

While a routine is actively guiding, the app polls those same aggregate
keyboard, mouse movement (including drags), mouse-button, and scroll ages once a
second for a reset - or for input inside the last polling second - that indicates
local work resumed. Keyboard evidence qualifies immediately. Pointer evidence has
to hold on two consecutive unprotected polls, because reaching for 2m2better's own
controls moves the pointer age too; every poll taken during the grace period,
while paused, or while a control tolerance is active discards the pointer evidence
gathered so far rather than carrying it across the boundary, so a nudge, a reach,
or withdrawing from a button never cancels a routine, while continuous mousing
does. Keystrokes while the companion's own panel holds keyboard focus count as
companion interaction, so Tab, arrow keys, Escape, and Space can reach Pause,
Next, and End. Input that continues after a protected sample is still noticed
later instead of being consumed by it. A five-second grace period covers starting
and settling into the companion; using a routine control - Pause, Resume, Next,
End, hovering one of those buttons, or opening the menu-bar menu - adds a
three-second tolerance, capped at thirty seconds of protection per routine so
protection can never be renewed indefinitely. Next starts a brand-new routine, so
it restarts detection with a fresh grace period and a fresh protection budget. A
qualifying reset returns to the check-in screen with a brief, non-judgmental
explanation, gives no completion credit, clears the pending session with the
existing local movement-history semantics, and offers a fresh Start, Later, or
Tomorrow choice; that recovery check-in stays silent
and does not take focus, so returning to work is not
interrupted a second time.
Pause is protected: activity while paused never cancels, and activity after Resume
is eligible again. Idle timing, check-in, and completion screens do not use this
detector.

This integrity check is local-only and deliberately coarse. It stores no key
values, pointer coordinates or paths, application content, account information,
analytics, or network data. Completed pause timestamps are kept in local macOS
preferences only, for the small relative-time context shown on a later pause
screen. It does not identify which application caused activity,
distinguish a person from another local input source, or interpret keys or pointer
paths; it also does not install an event monitor or require Accessibility
permission. Activity from another app is indistinguishable from resumed work; the
grace period, the two-poll pointer rule, and the budgeted control tolerance are
the conservative boundary for keeping its buttons and menu usable.

## Fast testing

The default active-work interval is one hour. Choose **Every 20 minutes**, **Every hour**, or **Every 3 hours** in **Settings…**; the selection is stored in local macOS preferences. For a short development loop, override it when launching the executable:

```sh
BREAK_INTERVAL_SECONDS=5 ".build/app/2m2better.app/Contents/MacOS/BreakCompanion"
```

`BREAK_IDLE_THRESHOLD_SECONDS` can also replace the default 180-second (three-minute) idle threshold. Active samples earn cadence credit at 1x; inactive samples discount it at 0.5x, never below zero. A long observation gap is discounted rather than counted as active work credit, and the first active sample resumes from the remaining credit. Values are clamped to sensible testing minimums.

### How an automatic offer appears

The initiating signal is only macOS's aggregate age for recent keyboard and
mouse movement, clicks, drags, and scrolling. After launch, a one-second clock
samples that signal and the active-use timer credits active ticks at 1x while
discounting inactive ticks at 0.5x. Idle, locked, and sleeping gaps never earn
active work credit; observed or system-marked inactivity spends accumulated
credit but never presents a pause. App-uptime gaps likewise never earn work
credit. The first active sample after an inactivity boundary resumes from the
remaining credit and defers a due offer until the next active sample. During an
ongoing active run, when active use reaches the configured cadence, the timer
resets and the store enters a **pending offer** state. On an ordinary desktop
Space, the panel then resizes, moves into the current visible screen, orders
itself in front, and activates so the full **Start**, **Later**, and
**Tomorrow** choice is unmistakable. Collapsing it leaves that same pending decision in a warm orb;
clicking the orb restores the choices. If it remains unhandled, a collapsed offer
returns to the full choices after five minutes and repeats on the same five-minute
cadence after later collapses. A visible offer is reannounced rather than
duplicated. A manual **Offer a break now** follows
the same presentation path, which makes it a useful countercheck when
investigating an automatic reminder.

Run the packaged logic checks with:

```sh
".build/app/2m2better.app/Contents/MacOS/BreakCompanion" --self-check
```

Inspect the deterministic, privacy-safe startup diagnostic with:

```sh
".build/app/2m2better.app/Contents/MacOS/BreakCompanion" --diagnostics
```

For the live app, choose **Copy diagnostics** from the menu bar and inspect the clipboard with `pbpaste`. Both reports contain only the effective cadence, selected body areas, coarse mode, the active-use status (`accumulating active use`, `waiting for active use`, `scheduled check-in`, `pending offer`, `settings open`, `routine in progress`, or `completion screen`), and the pending-offer presentation (`visible pause choices`, `collapsed pending orb`, or `no pending offer`). A pending offer means the store has crossed the active-use threshold and is waiting for a decision; it does not mean that the offer failed to happen. They never include key values, pointer coordinates, app content, agent data, analytics, or network state.

### Full-screen Space behavior

The end-user trigger for this rule is another app entering macOS full-screen,
not an idle-timer or pause-state transition. The old visible symptom was the
orb still covering that app's content because the panel was `.floating` and
explicitly declared `.fullScreenAuxiliary`; that collection flag is AppKit's
permission for an auxiliary window to accompany another app's full-screen
window. Testing also showed that omitting that flag alone is insufficient:
a floating `.canJoinAllSpaces` panel can still appear there. The orb now keeps
`.canJoinAllSpaces` and `.stationary` for ordinary multi-desktop use, adds the
explicit `.fullScreenNone` opt-out, and omits `.fullScreenAuxiliary`. AppKit
therefore leaves it out of a foreign full-screen Space and restores it when
that Space is exited, without changing its position, dragging, timing, pause
behavior, or menu-bar fallback.

This policy is delegated to AppKit because macOS does not provide a supported,
deterministic API for an app to query which other process owns the active
full-screen Space. The behavior-level test checks the actual `NSPanel`
collection policy; CI cannot reliably automate Mission Control or a Netflix
full-screen session. During development, a separate AppKit full-screen probe
reproduced the distinction: the old auxiliary panel remained on-screen over
the probe, a panel with only `.canJoinAllSpaces` also remained visible, and the
otherwise identical panel with `.fullScreenNone` was absent from that Space
while remaining available on an ordinary desktop Space.

Exercise the release installer through its command-line interface with its
network-free macOS command harness:

```sh
./scripts/test-install.sh
./scripts/test-update-handoff.sh
```

The Swift package and XCTest target are included for use in a standard Xcode toolchain (`swift test`). See [`docs/RELEASES.md`](docs/RELEASES.md) for release packaging, icon/LaunchServices validation, updater handoff behavior, and packaged self-check validation; use the `BREAK_SDK_PATH` override above on this development Mac.

## Pilot boundaries

This prototype intentionally does not launch at login, collect wellbeing data, sync, coach, score, or expose a browsable pause-history or routine catalog. “Tomorrow” means 24 hours from the response. The optional updater is the only runtime network activity; its privacy and trust contract is documented in [`docs/RELEASES.md`](docs/RELEASES.md) and does not change the local-only break experience. For a later iteration, “Tomorrow” could become a user-selected quiet-hours-aware morning without changing the core state machine.

A quiet idle orb shifts from soft green through muted orange to calm red as the next check-in approaches. Once an offer is pending, both the full pause panel and collapsed orb stay in the warm due range even though the active-use counter has reset. The same timing is available to VoiceOver as remaining time and interval progress, so color is never the only signal.
