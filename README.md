# 2m2good

A deliberately small, local macOS break companion. After 60 minutes of active keyboard or mouse use, 2m2good's quiet floating orb offers one two-minute reset. It accepts a short spoken response or the always-visible buttons, guides the routine with voice and motion, and then gets out of the way.

## What is in the pilot

- A small floating orb plus a menu-bar fallback; no dashboard, history, streaks, or account.
- Active-use timing that pauses while the Mac is idle.
- Warm check-ins with **Start**, **Later** (one hour), and **Tomorrow**.
- Speech recognition for natural affirmatives such as “yeah,” “yes,” “yep,” “let’s do it,” and “let’s go,” plus “start,” “later,” “tomorrow,” “in 20 minutes,” or “in two hours.”
- A library of 24 gentle, standing-compatible desk-break movements. Each offered session combines six different 20-second movements into a fresh two-minute reset.
- Normal check-ins quietly favor conservative movement-focus areas that have appeared less often in recently completed sessions, without exposing scores or body data in the interface.
- Every session is exactly 120 seconds, with a gentle standing invitation, spoken guidance, simple motion cues, Pause, Next, End, and safety wording.
- **Next** immediately composes a new session from 2:00 and avoids every move in the current session. Moves are recorded when shown, so skipped and switched sessions also reduce near-term repetition.
- The Done screen closes itself after about 10 seconds; Return or Enter closes it immediately.
- Selection state is bounded to 18 recently shown and 24 recently completed movement identifiers in local macOS preferences. Older routine history is migrated into conservative move-focus history once. All processing uses Apple’s on-device/system frameworks; the app has no network integration or analytics.

## Build and run

Requires macOS 14 or newer and Apple Command Line Tools (or Xcode).

```sh
./scripts/build-app.sh
open ".build/app/2m2good.app"
```

The app appears as a small orb near the upper-right of the screen and as a leaf in the menu bar. Click either to trigger a break immediately.

This development Mac currently has a newer command-line compiler paired with a slightly mismatched newest SDK. On this machine only, build with its compatible installed SDK:

```sh
BREAK_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ./scripts/build-app.sh
```

## Permissions

On the first spoken check-in, macOS asks for **Microphone** and **Speech Recognition** access. **Try Voice** shows whether it is requesting permission, listening, or could not understand a command. Both permissions are optional: Start, Later, Tomorrow, Pause, Next, and End always work as buttons. Permissions can be changed later in **System Settings → Privacy & Security**.

The app does not need Accessibility permission. It reads only macOS’s aggregate “time since last keyboard/mouse event,” not the keys pressed or the content of events.

## Fast testing

The normal active-work interval is 3,600 seconds. Override it when launching the executable:

```sh
BREAK_INTERVAL_SECONDS=5 ".build/app/2m2good.app/Contents/MacOS/BreakCompanion"
```

`BREAK_IDLE_THRESHOLD_SECONDS` can also replace the default 60-second idle threshold. Values are clamped to sensible testing minimums.

Run the packaged logic checks with:

```sh
".build/app/2m2good.app/Contents/MacOS/BreakCompanion" --self-check
```

The Swift package and XCTest target are included for use in a standard Xcode toolchain (`swift test`).

## Pilot boundaries

This prototype intentionally does not launch at login, collect wellbeing data, sync, coach, score, or expose a browsable routine catalog. “Tomorrow” means 24 hours from the response. For a later iteration, that could become a user-selected quiet-hours-aware morning without changing the core state machine.

A quiet idle orb shifts from soft green through muted orange to calm red as the next check-in approaches. The same timing is available to VoiceOver as remaining time and interval progress, so color is never the only signal.
