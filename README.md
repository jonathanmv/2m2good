# 2m2better

A deliberately small, local macOS break companion. After 60 minutes of active keyboard or mouse use, 2m2better's quiet floating orb offers one two-minute reset. It accepts a short spoken response or the always-visible buttons, guides the routine with voice and motion, and then gets out of the way.

## What is in the pilot

- A small floating orb plus a menu-bar fallback; no dashboard, history, streaks, or account.
- Active-use timing that pauses while the Mac is idle.
- Warm check-ins with **Start**, **Later** (one hour), and **Tomorrow**.
- Speech recognition for natural affirmatives such as “yeah,” “yes,” “yep,” “let’s do it,” and “let’s go,” plus “start,” “later,” “tomorrow,” “in 20 minutes,” or “in two hours.”
- A library of gentle, standing-compatible desk-break movements. Each offered session combines six different 20-second movements into a fresh two-minute reset.
- On first launch, choose one or more areas to support: **Lower back**, **Neck**, **Shoulders**, or **Hands + wrists**, or keep the balanced mix. The choice can be reviewed from the menu bar and biases the next reset without becoming a dashboard or body-data profile.
- Every session is exactly 120 seconds, with a gentle standing invitation, spoken guidance, simple motion cues, Pause, Next, End, and safety wording.
- **Next** immediately composes a new session from 2:00 and avoids every move in the current session. Moves are recorded when shown, so skipped and switched sessions also reduce near-term repetition.
- The Done screen closes itself after about 10 seconds; Return or Enter closes it immediately.
- Selection state is bounded to 18 recently shown and 24 recently completed movement identifiers, alongside the selected areas, in local macOS preferences. Older routine history is migrated into conservative move-focus history once, and an existing install keeps its history and continues on the balanced mix instead of being asked to set up again. All processing uses Apple’s on-device/system frameworks; the app has no network integration or analytics.

## Build and run

Requires macOS 14 or newer on an arm64 or x86_64 Mac, plus Xcode 15 or
newer or the matching Apple Command Line Tools.

```sh
./scripts/build-app.sh
open ".build/app/2m2better.app"
```

The app appears as a small orb near the upper-right of the screen and as a leaf in the menu bar. On a fresh install, a compact setup asks which body areas the standing reset should support; every shipped movement is standing-only, so the reset is presented as a standing one rather than a seated alternative. Click the orb or **Offer a break now** in the menu bar to trigger a break immediately; use **Choose body areas…** there to review or change the selection, which stays available while the orb is idle so an offered or running reset is never discarded.

This development Mac currently has a newer command-line compiler paired with a slightly mismatched newest SDK. On this machine only, build with its compatible installed SDK:

```sh
BREAK_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ./scripts/build-app.sh
```

## Early developer-preview terminal installer

Technically comfortable macOS preview users can inspect and run the source
bootstrap from the public repository. It is explicitly **not** a signed or
notarized consumer installer and is not a general release channel. It clones
into a new user-selected directory, runs `scripts/build-app.sh`, and opens the
local app; it never uses `sudo` or modifies an existing checkout.

[`docs/DEVELOPER_PREVIEW.md`](docs/DEVELOPER_PREVIEW.md) owns the validated
prerequisites, options, safety behavior, and limitations of this path. Read the
installer, then print its plan without cloning or building:

```sh
curl -fsSL https://raw.githubusercontent.com/jonathanmv/2m2good/main/scripts/install-preview.sh -o install-preview.sh
sh install-preview.sh --dry-run --ref main --destination "$HOME/2m2good-developer-preview"
```

Download it to a file rather than piping it into a shell: a failed `curl -fsSL`
prints nothing, and a piped shell would then run an empty script and exit
successfully as if the preview had worked.

After reviewing the displayed repository, ref, destination, build command,
output, and launch behavior, rerun without `--dry-run` to confirm and build.
The installer checks its prerequisites before it creates anything and reports
the missing one. This path provides no hosted release artifact,
signing/notarization, automatic updates, rollback, or integrity guarantee.

## Permissions

On the first spoken check-in, macOS asks for **Microphone** and **Speech Recognition** access. **Try Voice** shows whether it is requesting permission, listening, or could not understand a command. Both permissions are optional: Start, Later, Tomorrow, Pause, Next, and End always work as buttons. Permissions can be changed later in **System Settings → Privacy & Security**.

The app does not need Accessibility permission. It reads only macOS’s aggregate “time since last keyboard/mouse event,” not the keys pressed or the content of events.

While a routine is actively guiding, the app polls those same aggregate ages once a second for a reset - or for input inside the last polling second - that indicates local work resumed. Keyboard evidence qualifies immediately. Pointer evidence has to hold on two consecutive polls, because reaching for 2m2better's own controls moves the pointer age too; a single nudge or a reach therefore never cancels a routine, while continuous mousing does. Input that continues after a protected sample is still noticed later instead of being consumed by it. A five-second grace period covers starting and settling into the companion; using a routine control - Pause, Resume, Next, End, hovering one of those buttons, or opening the menu-bar menu - adds a three-second tolerance, capped at thirty seconds of protection per routine so protection can never be renewed indefinitely. A qualifying reset returns to the check-in screen with a brief, non-judgmental explanation, clears the pending session, and offers a fresh Start, Later, or Tomorrow choice. Pause is protected: activity while paused never cancels, and activity after Resume is eligible again. Idle timing, check-in, and completion screens do not use this detector.

This integrity check is local-only and deliberately coarse. It stores no key values, pointer coordinates or paths, application content, account information, analytics, or network data, and does not install an event monitor or require Accessibility permission. Activity from another app is indistinguishable from resumed work; the grace period, the two-poll pointer rule, and the budgeted control tolerance are the conservative boundary for keeping its buttons and menu usable.

## Fast testing

The normal active-work interval is 3,600 seconds. Override it when launching the executable:

```sh
BREAK_INTERVAL_SECONDS=5 ".build/app/2m2better.app/Contents/MacOS/BreakCompanion"
```

`BREAK_IDLE_THRESHOLD_SECONDS` can also replace the default 60-second idle threshold. Values are clamped to sensible testing minimums.

Run the packaged logic checks with:

```sh
".build/app/2m2better.app/Contents/MacOS/BreakCompanion" --self-check
```

The Swift package and XCTest target are included for use in a standard Xcode toolchain (`swift test`).

## Pilot boundaries

This prototype intentionally does not launch at login, collect wellbeing data, sync, coach, score, or expose a browsable routine catalog. “Tomorrow” means 24 hours from the response. For a later iteration, that could become a user-selected quiet-hours-aware morning without changing the core state machine.

A quiet idle orb shifts from soft green through muted orange to calm red as the next check-in approaches. The same timing is available to VoiceOver as remaining time and interval progress, so color is never the only signal.
