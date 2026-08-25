# Future ideas and deferred work

## Session integrity and activity detection - implemented for the v1 launch

The deferred session-integrity idea is implemented. The [`README.md`](README.md)
**Permissions** section is the authoritative description of its interaction,
privacy, accessibility, pause, and recovery policy; it also owns the intentional
out-of-scope boundaries. This section remains a status pointer rather than a
second copy of that policy.

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

- The source checkout has no Developer ID signing or notarization and is not a
  consumer release installer; packaged GitHub Release behavior is documented in
  [`docs/RELEASES.md`](docs/RELEASES.md).
- The checkout must be new; the installer refuses an existing destination and
  does not use `sudo`, collect credentials, install globally, or delete files.
- Installer network access is limited to obtaining the displayed Git source;
  the packaged app's optional updater is a separate behavior covered by
  [`docs/RELEASES.md`](docs/RELEASES.md).

## Pay when a break is not completed

Product hypothesis: a voluntary financial consequence for skipping an agreed break might help some users follow through on their own wellbeing intention.

This is only a concept for later research. 2m2better does not currently include payments, pricing, completion tracking, enforcement, penalties, accounts, or related interface.

Questions that must be answered before considering it:

- Fairness: would this punish people for interruptions, limited resources, illness, or changing circumstances?
- Consent: how would participation remain genuinely optional, reversible, and free of manipulative defaults?
- Privacy: what is the minimum data required, where would it live, and could the concept work without sending activity data anywhere?
- Accessibility: how would completion be defined without disadvantaging people who cannot perform a suggested movement or use pointer input conventionally?
- False positives: how would the system avoid charging when timing, app state, or device availability is wrong?
- Product fit: would a financial penalty undermine the companion’s gentle, permission-based, nonjudgmental promise?
- Legal and ethical review: which consumer-protection, payments, health-adjacent, dark-pattern, and jurisdiction-specific obligations require specialist review?

No implementation decision should be made without user research and explicit legal and ethical review.
