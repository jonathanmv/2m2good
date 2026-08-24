# Future ideas and deferred work

## Session integrity and activity detection - implemented for the v1 launch

An active routine now watches only macOS’s aggregate time-since-last keyboard,
mouse-movement, mouse-button, and scroll activity signals. A conservative
five-second initial grace period and three-second protection after companion
controls prevent the companion’s own Start, Pause,
Resume, Next, and End interactions from immediately cancelling a routine. That
protection is also granted by hovering a routine control or opening the
menu-bar menu, and is capped at thirty seconds per routine so it can never be
renewed indefinitely. Next starts a brand-new routine, so detection restarts
with it: a fresh grace period and a fresh protection budget. Input that keeps going while a sample is protected still
qualifies once the protection ends, because activity inside the last polling
second counts as well as a drop in the aggregate age. Keyboard evidence
qualifies at once; pointer evidence must hold on two consecutive unprotected
polls, and every grace, paused, or protected poll discards the pointer evidence
gathered so far, so reaching for a control, withdrawing from one, or nudging the
mouse cannot cancel a routine while continuous mousing still does. Keystrokes
while the companion panel holds keyboard focus are companion interaction, which
keeps keyboard navigation of its controls usable. The recovery check-in is
silent and does not open the microphone or take focus.
Pause is an explicitly protected state: activity while paused is ignored, while
activity after Resume can qualify as resumed work.

A qualifying activity reset stops guidance, gives no completion credit, clears
the pending session with the existing local history semantics, and returns to a
fresh check-in with Start, Later, and Tomorrow controls. The explanation is
non-judgmental and the next Start begins at the first movement. No activity
values, pointer locations, application content, accounts, analytics, or network
data are recorded, and Accessibility permission remains out of scope.

Intentionally out of scope are identifying which application caused activity,
interpreting keys or pointer paths, distinguishing a person from another local
input source, Accessibility/event-stream monitoring, and preserving partial
progress as completion. The detector remains limited to active `.routine`
state; idle timing, check-in, pause, and completion behavior otherwise retain
their existing roles.

## Early developer-preview terminal installation - limited preview implemented

The early developer-preview path described here is now implemented as a
transparent curl-driven source bootstrap for technically comfortable macOS
users. It is deliberately **not** a signed or notarized consumer installer and
is not a general release channel. The script obtains the source from the
public Git repository, shows the selected repository/ref, destination, build
command, output, and launch behavior, then builds into a new user-selected
checkout with `scripts/build-app.sh`.

See [`README.md`](README.md) for the command and
[`docs/DEVELOPER_PREVIEW.md`](docs/DEVELOPER_PREVIEW.md) for the validated
macOS/Apple toolchain/Git requirements, safe dry-run behavior, and shell-level
tests. The preview remains intentionally limited:

- There are no hosted release artifacts, Developer ID signing, notarization,
  automatic updates, rollback, or pinned-download/integrity guarantees.
- The checkout must be new; the installer refuses an existing destination and
  does not use `sudo`, collect credentials, install globally, or delete files.
- Installer network access is limited to obtaining the displayed Git source;
  the built app remains local-only with no account, runtime network integration,
  sync, or analytics.

## Pay when a break is not completed

Product hypothesis: a voluntary financial consequence for skipping an agreed break might help some users follow through on their own wellbeing intention.

This is only a concept for later research. 2m2better does not currently include payments, pricing, completion tracking, enforcement, penalties, accounts, or related interface.

Questions that must be answered before considering it:

- Fairness: would this punish people for interruptions, limited resources, illness, or changing circumstances?
- Consent: how would participation remain genuinely optional, reversible, and free of manipulative defaults?
- Privacy: what is the minimum data required, where would it live, and could the concept work without sending activity data anywhere?
- Accessibility: how would completion be defined without disadvantaging people who cannot perform a suggested movement or use voice and pointer input conventionally?
- False positives: how would the system avoid charging when recognition, timing, app state, or device availability is wrong?
- Product fit: would a financial penalty undermine the companion’s gentle, permission-based, nonjudgmental promise?
- Legal and ethical review: which consumer-protection, payments, health-adjacent, dark-pattern, and jurisdiction-specific obligations require specialist review?

No implementation decision should be made without user research and explicit legal and ethical review.
