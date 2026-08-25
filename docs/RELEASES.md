# GitHub Releases and updates

2m2better has one release source: **GitHub Releases** for
[`jonathanmv/2m2good`](https://github.com/jonathanmv/2m2good/releases). The app
never contacts a separate feed, host, analytics service, or account service.

## Release identity

The authoritative semantic version is `ProductIdentity.currentVersion` in
[`Sources/BreakCompanion/ProductIdentity.swift`](../Sources/BreakCompanion/ProductIdentity.swift).
`scripts/release-identity.sh` reads that declaration for packaging, while the
app uses it for comparisons, About, and diagnostics. `scripts/build-app.sh`
materializes the same version and build number into `Info.plist`; it does not
keep a second hand-edited bundle version.

Keep the version in valid SemVer form and update the build number deliberately
when a build identity needs to change. Do not update `Info.plist` directly.

## Build and validate release assets

On the development Mac, use the compatible SDK override documented in
[`README.md`](../README.md):

```sh
BREAK_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
  ./scripts/package-release.sh
```

The package script checks the generated bundle's version and build identity,
verifies its code signature, runs the packaged `--self-check`, then creates
these two assets for the current Mac architecture:

```text
2m2better-v<version>-macos-arm64.zip
2m2better-v<version>-macos-arm64.zip.sha256
```

`x86_64` replaces `arm64` on Intel Macs. Run the deterministic package harness
when validating a local release:

```sh
./scripts/test-release-packaging.sh
```

Upload both assets to the GitHub Release whose tag is `v<version>`. The updater
requires the exact architecture-specific ZIP and its matching checksum asset.
It rejects drafts, prereleases, malformed or older tags, missing assets, HTTP
URLs, non-GitHub URLs, oversized responses, and checksum files that do not name
the exact ZIP.

The current local build uses an ad-hoc signature because the repository does
not establish a Developer ID identity or notarization credentials. This is
intentional and is not represented as consumer signing. Release asset integrity
is instead verified by HTTPS GitHub transport plus a SHA-256 manifest before an
update is shown. Protect GitHub release permissions; do not replace this with
an invented signing identity, host, feed, or trust bypass.

## In-app behavior

The app performs at most one automatic release check per 24 hours. The check is
bounded, asynchronous, and sends only a standard GitHub API request containing
the product/version user agent; it sends no break activity, preferences, or
identifiers. **Check for Updates…** in the menu always gives the user an
explicit retry path.

An available release is never installed silently. After the user chooses
**Download and Verify**, the app downloads the ZIP and checksum over HTTPS,
checks the SHA-256 bytes, and removes the temporary download on any failure.
After success it offers to show the verified ZIP in Finder. The running app and
its preferences are never replaced; the user chooses when and how to open the
artifact. If the temporary file disappears, the app reports that recovery path
and permits another check.
