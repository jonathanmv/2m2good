# GitHub Releases, packaged installation, and updates

2m2better has one release and download source: **GitHub Releases** for
[`jonathanmv/2m2good`](https://github.com/jonathanmv/2m2good/releases). The app
and installer never use a separate feed, hosted download service, analytics
service, account service, or update server.

## One-line macOS installer

A developer-preview user can install the latest published release with:

```sh
curl -fsSL https://raw.githubusercontent.com/jonathanmv/2m2good/main/scripts/install.sh | sh
```

The public entry point is [`scripts/install.sh`](../scripts/install.sh). It
selects the architecture reported by `uname -m` (`arm64` or `x86_64`), asks the
GitHub Releases API for the latest non-draft, non-prerelease release, and
requires both exact architecture-specific assets:

```text
2m2better-v<version>-macos-arm64.zip
2m2better-v<version>-macos-arm64.zip.sha256
```

Intel Macs use `x86_64` in both names. The installer downloads only approved
GitHub HTTPS URLs, verifies that the checksum manifest contains exactly one
SHA-256 line naming the ZIP, and compares the digest before extracting or
installing anything. Missing, malformed, duplicate, redirected, or mismatched
assets stop the run without touching the app destination.

The app is installed without `sudo` into the invoking user's:

```text
~/Applications/2m2better.app
```

After installation it requests a Spotlight refresh with `mdimport -f` and asks
macOS to open the app (or clearly prints the manual `open` command). If an
existing app is running, the installer asks only 2m2better to quit gracefully
before replacement. The previous app bundle is moved to a timestamped
`.2m2better.app.previous.*.app` backup and is not deleted; `--replace` remains
accepted for compatibility but is no longer required. The installer never
removes user data, follows an installation symlink, uses credentials, or
bypasses Gatekeeper. `--no-launch`, `--dry-run`, and `--help` are available for
review and automation.

### Prerequisites and limitation

The command is for macOS 14 (Sonoma) or newer on arm64 or Intel x86_64. Standard
macOS tools `curl`, `plutil`, `shasum`, `ditto`, `sw_vers`, and `osascript`
are required; `mdimport` and `open` are normally present. Internet access to
GitHub's API, release, and asset hosts is required. No Xcode or Swift compiler
is needed because the installer consumes a published app ZIP.

This is deliberately a developer preview. The package uses the repository's
existing ad-hoc signing path; it has **no Apple Developer ID signature and is
not notarized**. macOS may show a Gatekeeper warning or require Finder **Open**
or Privacy & Security approval. The installer does not claim otherwise and
never adds a security bypass. The app remains local-only for break data; live
timer/session checkpoints and pause history stay in the invoking user's
Application Support/preferences data, outside the replaceable bundle. Its
optional update check sends only the documented GitHub request.

## v0.1.5 reliable offers and pending state

The next developer-preview release is **v0.1.5 (build 6)**. It brings the
merged pending-offer visibility and orb-color fixes to installed users:

- After enough active keyboard or mouse use, a pause offer appears reliably
  with the full **Start**, **Later**, and **Tomorrow** choices. Idle time and
  sleep do not advance the reminder, and **Offer a break now** provides the
  same clear offer on demand.
- A pending offer remains clearly visible while it awaits a decision. If the
  choices are collapsed, a warm due-colored orb keeps that pending state
  apparent; clicking the orb or choosing **Show pause choices** restores the
  full choices.
- **Settings…** remains actionable from the orb, a pending offer, a routine,
  and the completion screen, so the pause rhythm and supported areas can be
  changed without losing the current state or offer.
- A small, styled chevron-up collapse control (or Escape) postpones the choice
  without selecting a response. A pause prompt also shows brief context about
  the last completed pause, or **Last pause taken — none yet** when there is no
  completed history; it does not add a browsable history.
- Relaunches and update handoff preserve an in-progress timer or active pause
  session, so an update does not discard the current session.
- The one-line installer updates an existing installation through the same
  verified replacement flow: it asks a running app to quit gracefully, retains
  the previous bundle for rollback, replaces the app, and relaunches it while
  preserving user data. `--replace` remains accepted for older scripts.

The tag and both architecture asset pairs remain the existing `v<version>` and
`2m2better-v<version>-macos-{arm64,x86_64}.zip` contract. The app bundle
continues to include the maintainable single-file `Resources/2m2better.png`
icon. `scripts/build-app.sh` copies it into `Contents/Resources` and generates
both `CFBundleIconFile` and `CFBundleIconFiles` in `Contents/Info.plist`.
Packaging tests inspect the generated bundle and exercise LaunchServices
registration so Finder can identify the app. This app icon is separate from
the unchanged menu-bar `leaf.fill` symbol.

## Release identity and assets

The authoritative semantic version is `ProductIdentity.currentVersion` in
[`Sources/BreakCompanion/ProductIdentity.swift`](../Sources/BreakCompanion/ProductIdentity.swift).
[`scripts/release-identity.sh`](../scripts/release-identity.sh) reads that
value for packaging, while [`scripts/build-app.sh`](../scripts/build-app.sh)
places the same version and build number in `Info.plist`. Do not hand-edit
`Info.plist` or create a second version source.

A release tag must be `v<version>` and match the source identity. On a supported
Mac, validate and create the two local assets with:

```sh
BREAK_SDK_PATH=/path/to/MacOSX.sdk ./scripts/package-release.sh
./scripts/test-release-packaging.sh
./scripts/test-update-handoff.sh
```

`BREAK_SDK_PATH` is needed only on the development Mac when its compiler and
newest SDK do not match; normal hosted runners use their selected Xcode SDK.
The package script uses the existing build script, checks the bundle identity,
verifies its ad-hoc signature, runs the packaged `--self-check`, and writes the
architecture-specific ZIP and `.sha256` file to `.build/releases` (or the
chosen `--output-dir`). Upload both files to the GitHub Release for the same
`v<version>` tag.

The checked-in [release workflow](../.github/workflows/release.yml) packages
both architectures on `macos-14` (arm64) and `macos-15-intel` (x86_64), runs the same
packaging and self-check path, and publishes both ZIP/checksum pairs with the
GitHub CLI. It runs for `v*` tag pushes or manually for an existing `v<version>`
tag. Maintainers must keep both architecture assets and their exact checksum
manifests on the release; do not publish a release with only one architecture.
Protect GitHub release permissions and do not substitute signing credentials,
a different host, or an invented checksum service.

## In-app updater compatibility

The in-app updater consumes this same asset contract. It checks
`https://api.github.com/repos/jonathanmv/2m2good/releases/latest`, rejects
invalid/draft/prerelease/non-semantic releases and non-GitHub URLs, selects the
asset for the running architecture, and requires the matching `.sha256` asset.
It downloads the ZIP and checksum over HTTPS, verifies the exact named file
with SHA-256, and removes temporary files on failure. When a newer release is
found, the normal path is a concise prompt with one primary action, **Install
and Relaunch**, and a **Later** choice. The user's explicit install choice
starts the download and exact verification, which is shown only as brief
progress; a successful verification continues directly to the install handoff
without another technical confirmation. The prompt never asks users to review
ZIP names, checksums, GitHub URLs, installation paths, or a Finder step. If a
check or install cannot finish, it shows short recovery copy with **Try Again**
and **Cancel**; technical details go to
`~/Library/Logs/2m2better/update.log` instead.

The install action launches the bundled helper outside the running process. The
helper waits for this process to exit, rechecks the local ZIP digest, validates
the app bundle and icon, and replaces only `~/Applications/2m2better.app`. Live
timer/session checkpoints remain in per-user Application Support outside the
bundle. It moves an existing bundle to a retained
`~/Applications/.2m2better.app.previous.*.app` rollback path before the final
rename. If that rename fails, it restores the old app and retains a rollback
copy for inspection. Preferences live outside the app
bundle and are not copied or deleted. On success it asks macOS to relaunch the
new app and records the result in the same update log. The helper uses no sudo,
credentials, or Gatekeeper bypass.

Automatic checks happen at most once per 24 hours. A found update uses the same
concise prompt as **Check for Updates…**; automatic checks stay quiet when the
service is unavailable, while the menu remains an explicit retry path. Update
requests contain no break activity, preferences, identifiers, or telemetry.
The updater's HTTPS allowlist, redirect policy, response-size limits,
architecture selection, semantic-version checks, and checksum verifier must
remain compatible with the filenames above.

This remains an ad-hoc developer preview: the package is not Developer ID
signed or notarized. A verified checksum proves that the downloaded bytes match
GitHub's published manifest; it does not make the package Apple-trusted or
prove that its contents are benign. macOS may still require Finder **Open** or
Privacy & Security approval, and the updater deliberately does not bypass that
security boundary.

## Source build preview

[`docs/DEVELOPER_PREVIEW.md`](DEVELOPER_PREVIEW.md) documents the separate
source-checkout path for contributors who intentionally want to build from a
branch or commit. It is not the release installer and does not change GitHub
Releases as the sole packaged distribution source.

## Hosted arm64 packaging build fix (v0.1.0)

The tag `v0.1.0` arm64 GitHub Actions packaging job failed under the hosted
Swift compiler at `CompanionStore.swift:276` with "reference to captured var
'self' in concurrently-executing code" for the timer tick closure
`Task { @MainActor in self?.tick() }`. The fix adds an explicit `[weak self]`
capture list to that inner `Task`, matching the outer `startClock()` closure's
existing weak capture; the nil-check and `@MainActor` `tick()` call are
unchanged, so timer behavior is preserved.

Validation performed on this development Mac with `BREAK_SDK_PATH` (see
README's "Build and run" section): `scripts/build-app.sh` builds and
code-signs cleanly with the fix in place, and the existing `swift test`
suite in `Tests/BreakCompanionTests` passes unchanged. A counterfactual
check compiled both the pre-fix and post-fix source under
`-swift-version 6` (Swift 6 language mode, which enables the same strict
actor-isolation checking as the hosted failure) on the installed
MacOSX15.4 SDK; neither variant reproduced the hosted diagnostic. This
confirms the local toolchain (Swift 6.3.3) accepts the unfixed capture that
the hosted CI compiler rejects, so the hosted failure could not be
reproduced locally and is addressed by the capture-list fix itself, which
is the compiler-recommended resolution for this diagnostic.
