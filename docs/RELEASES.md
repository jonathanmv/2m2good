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
macOS to open the app (or clearly prints the manual `open` command). An existing
app is refused by default. `--replace` is the explicit, documented choice to
replace one; the previous app bundle is moved to a timestamped
`.2m2better.app.previous.*.app` backup and is not deleted. The installer never
removes user data, follows an installation symlink, uses credentials, or
bypasses Gatekeeper. `--no-launch`, `--dry-run`, and `--help` are available for
review and automation.

### Prerequisites and limitation

The command is for macOS 14 (Sonoma) or newer on arm64 or Intel x86_64. Standard
macOS tools `curl`, `plutil`, `shasum`, `ditto`, and `sw_vers` are
required; `mdimport` and `open` are normally present. Internet access to
GitHub's API, release, and asset hosts is required. No Xcode or Swift compiler
is needed because the installer consumes a published app ZIP.

This is deliberately a developer preview. The package uses the repository's
existing ad-hoc signing path; it has **no Apple Developer ID signature and is
not notarized**. macOS may show a Gatekeeper warning or require Finder **Open**
or Privacy & Security approval. The installer does not claim otherwise and
never adds a security bypass. The app remains local-only for break data; its
optional update check sends only the documented GitHub request.

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
```

`BREAK_SDK_PATH` is needed only on the development Mac when its compiler and
newest SDK do not match; normal hosted runners use their selected Xcode SDK.
The package script uses the existing build script, checks the bundle identity,
verifies its ad-hoc signature, runs the packaged `--self-check`, and writes the
architecture-specific ZIP and `.sha256` file to `.build/releases` (or the
chosen `--output-dir`). Upload both files to the GitHub Release for the same
`v<version>` tag.

The checked-in [release workflow](../.github/workflows/release.yml) packages
both architectures on `macos-14` (arm64) and `macos-13` (x86_64), runs the same
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
with SHA-256, and removes temporary files on failure. A verified update is
never installed silently: the user is offered the verified ZIP in Finder and
chooses when and how to open it. The running app and its preferences are never
replaced.

Automatic checks happen at most once per 24 hours; **Check for Updates…** is an
explicit retry path. Update requests contain no break activity, preferences,
identifiers, or telemetry. The updater's URL allowlist and checksum verifier
must remain compatible with the filenames above.

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
README's Prerequisites section): `scripts/build-app.sh` builds and
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
