# 2m2better

A deliberately small, local macOS break companion. After 60 minutes of active keyboard or mouse use, 2m2better's quiet floating orb offers one two-minute reset. It keeps the Start, Later, and Tomorrow choices visible, guides the routine with spoken movement guidance and motion, and then gets out of the way.

## What is in the pilot

- A small floating orb plus a menu-bar fallback; no dashboard, history, streaks, or account.
- Active-use timing that pauses while the Mac is idle and starts a fresh interval when activity returns after at least the idle threshold; delayed timer callbacks and sleep gaps never count as work.
- Warm check-ins with **Start**, **Later** (one hour), and **Tomorrow**.
- Click-only check-in responses: **Start**, **Later** (one hour), and **Tomorrow**, with keyboard-accessible buttons.
- A library of gentle, standing-compatible desk-break movements. Each offered session combines six different 20-second movements into a fresh two-minute reset.
- On first launch, choose one or more areas to support: **Lower back**, **Neck**, **Shoulders**, or **Hands + wrists**, or keep the balanced mix. The choice can be reviewed from the menu bar and biases the next reset without becoming a dashboard or body-data profile.
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

The app appears as a small orb near the upper-right of the screen and as a leaf in the menu bar. On a fresh install, a compact setup asks which body areas the standing reset should support; every shipped movement is standing-only, so the reset is presented as a standing one rather than a seated alternative. Click the orb or **Offer a break now** in the menu bar to trigger a break immediately; use **Choose body areas…** there to review or change the selection, which stays available while the orb is idle so an offered or running reset is never discarded.

The menu also includes **About 2m2better…**, which shows the shared release identity, and **Check for Updates…**, which checks GitHub Releases only. See [`docs/RELEASES.md`](docs/RELEASES.md) for the updater behavior, release asset contract, and packaging validation.

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
It refuses an existing installation by default; download the script and pass
`--replace` only as the explicitly documented choice to retain the old app in a
`.previous` backup. It does not delete user data, use credentials, or contact a
separate update server.

Prerequisites are macOS 14 (Sonoma) or newer, GitHub HTTPS access, and the
standard macOS `curl`, `plutil`, `shasum`, `ditto`, and `sw_vers` tools.
Xcode and Swift are not required for the packaged installer. This is an
ad-hoc-signed developer preview: it has no Apple Developer ID signature and is
not notarized, so macOS may require Finder **Open** or Privacy & Security
approval. The installer does not bypass Gatekeeper. Release packaging,
checksum requirements, and updater compatibility are documented in
[`docs/RELEASES.md`](docs/RELEASES.md); the source-build alternative is in
[`docs/DEVELOPER_PREVIEW.md`](docs/DEVELOPER_PREVIEW.md).

## Permissions

The check-in is click-only: **Start**, **Later**, and **Tomorrow** remain visible and keyboard-accessible, so no audio-input or command-recognition permission is needed. During a routine, spoken movement guidance complements the on-screen instructions; the app does not listen for responses.

The app does not need Accessibility permission. It reads only macOS’s aggregate local time since the last keyboard, mouse movement (including drags), mouse-button, or scroll event, not the keys pressed or the content of events.

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
analytics, or network data. It does not identify which application caused activity,
distinguish a person from another local input source, or interpret keys or pointer
paths; it also does not install an event monitor or require Accessibility
permission. Activity from another app is indistinguishable from resumed work; the
grace period, the two-poll pointer rule, and the budgeted control tolerance are
the conservative boundary for keeping its buttons and menu usable.

## Fast testing

The normal active-work interval is 3,600 seconds. Override it when launching the executable:

```sh
BREAK_INTERVAL_SECONDS=5 ".build/app/2m2better.app/Contents/MacOS/BreakCompanion"
```

`BREAK_IDLE_THRESHOLD_SECONDS` can also replace the default 60-second idle threshold. When no keyboard or mouse activity has been seen for at least that threshold, the next active sample resets the interval before adding only the current timer tick; a sleep gap is never counted as active work. Values are clamped to sensible testing minimums.

Run the packaged logic checks with:

```sh
".build/app/2m2better.app/Contents/MacOS/BreakCompanion" --self-check
```

Exercise the release installer through its command-line interface with its
network-free macOS command harness:

```sh
./scripts/test-install.sh
```

The Swift package and XCTest target are included for use in a standard Xcode toolchain (`swift test`). See [`docs/RELEASES.md`](docs/RELEASES.md) for release packaging and packaged self-check validation; use the `BREAK_SDK_PATH` override above on this development Mac.

## Pilot boundaries

This prototype intentionally does not launch at login, collect wellbeing data, sync, coach, score, or expose a browsable routine catalog. “Tomorrow” means 24 hours from the response. The optional updater is the only runtime network activity; its privacy and trust contract is documented in [`docs/RELEASES.md`](docs/RELEASES.md) and does not change the local-only break experience. For a later iteration, “Tomorrow” could become a user-selected quiet-hours-aware morning without changing the core state machine.

A quiet idle orb shifts from soft green through muted orange to calm red as the next check-in approaches. The same timing is available to VoiceOver as remaining time and interval progress, so color is never the only signal.
