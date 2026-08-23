# Early developer-preview installation

The terminal path is an **early developer preview** for technically comfortable
macOS users. It checks out the source, builds the app with the repository's
existing script, and optionally opens the resulting app. It is not a consumer
installer, a general release channel, or a hosted app download.

## Inspect and run it

The installer is readable at
[`scripts/install-preview.sh`](../scripts/install-preview.sh). The current
public source repository and preview ref are:

- Repository: `https://github.com/jonathanmv/2m2good.git`
- Default ref: `main`
- Output: the app bundle that `scripts/build-app.sh` reports, under
  `<destination>/.build/app`

Download the script to a file first, then read it. Do not pipe it straight into
a shell: `curl -f` prints nothing when the download fails, so a piped shell
would read an empty script and exit successfully as though the run had worked.
Downloading first fails loudly and leaves the exact bytes you are about to run
on disk:

```sh
curl -fsSL https://raw.githubusercontent.com/jonathanmv/2m2good/main/scripts/install-preview.sh -o install-preview.sh
less install-preview.sh
```

Then print and validate the plan without cloning, building, launching, or
making an installer network request:

```sh
sh install-preview.sh --dry-run --ref main --destination "$HOME/2m2good-developer-preview"
```

After reviewing the plan, run the same command without `--dry-run`. It pauses
for confirmation before creating the destination:

```sh
sh install-preview.sh --ref main --destination "$HOME/2m2good-developer-preview"
```

For a deliberately non-interactive invocation, add `--confirm` only after
reviewing the printed plan. `--no-launch` builds without opening the app.
`--repo URL` accepts an HTTPS Git repository, and `--ref REF` accepts a branch,
tag, or full 40-character commit SHA. Only a full 40-character SHA is treated as
an exact commit revision, because a remote can only be asked for a complete
object id; every other value, including a branch or tag whose name happens to
look hexadecimal, is resolved as a branch or tag. A failed checkout reports
Git's own cause and, for a hexadecimal-looking ref, adds the reminder that an
abbreviated SHA cannot be fetched from a remote. The selected ref is shown
before the checkout; a moving branch is not an integrity guarantee.

The installer refuses an existing destination, including a symlink, and never
clones into an existing checkout. It may create missing parent directories,
but it does not use `sudo`, ask for credentials, overwrite files, remove files,
write to `/Applications`, install a login item, or add an update service. A
failed checkout or build is left in place for inspection rather than being
silently deleted. The only exception is scaffolding this run created and nothing
else: a destination left completely empty is removed, and on the full-SHA path a
repository that was initialized but never fetched into is discarded when it is
the destination's only entry, so the same path can be reused after a checkout
that wrote nothing. A partial checkout is always preserved.

## Requirements

The installer validates these requirements before creating its destination:

- macOS 14 (Sonoma) or newer, on an `arm64` or `x86_64` Mac.
- Xcode 15 or later, or the matching Apple Command Line Tools, selected so
  `xcrun` can find an Apple Swift compiler and a macOS SDK. The direct build
  requires Swift 5.9 or later and the macOS 14 SDK.
- Git 2.20 or later. The installer disables Git's terminal credential prompt;
  this preview expects the public repository to be reachable without an
  account or credential entry.
- `curl` to obtain the curl-driven script, plus the macOS `codesign` and `open`
  commands. The app is ad-hoc signed into the new checkout so macOS can run the
  local build; this is not Developer ID signing or notarization.
- HTTPS access to GitHub (or to the HTTPS repository supplied with `--repo`) to
  obtain the source. The project has no third-party package download in this
  direct build path; Apple frameworks come from the local SDK.

If `xcrun` cannot find the toolchain or SDK, the installer reports the missing
requirement and stops before creating the destination. A compatible SDK can be
selected explicitly for a known local toolchain with `BREAK_SDK_PATH`, the same
override accepted by `scripts/build-app.sh`:

```sh
BREAK_SDK_PATH=/path/to/MacOSX.sdk \
  sh scripts/install-preview.sh --dry-run --destination "$HOME/2m2good-developer-preview"
```

## What happens after confirmation

1. The installer creates the new destination exclusively.
2. It obtains the displayed repository and ref shallowly. A branch or tag is
   cloned directly. A full 40-character commit SHA is fetched into a new empty
   repository and checked out detached, so exactly that commit is downloaded and
   the remote's default branch does not have to be available.
3. It runs `(cd <destination> && ./scripts/build-app.sh)`.
4. It takes the app bundle path from that script's own output, verifies the
   bundle it names, and, unless `--no-launch` was selected, runs `open` on that
   path. The bundle name is never duplicated in the installer, so renaming it in
   `scripts/build-app.sh` is enough.

The network is used by the installer only to obtain the preview source. The
built app retains the pilot's local-only behavior: no account, runtime network
integration, sync, analytics, or remote update service. The app still requests
optional macOS microphone and speech-recognition permissions when voice input
is used; its buttons remain available without them.

This path provides no hosted release artifact, Developer ID signature,
notarization, automatic updates, rollback, pinned-download verification, or
other integrity guarantee. Source, branch/revision, build output, and launch
behavior remain visible so the user can inspect them directly.

## Safe installer checks

The shell harness uses temporary directories, fake prerequisite commands, and
installer dry runs. It never reaches the network, changes a home directory, or
touches an existing checkout: its fake Git either refuses a checkout or copies a
local stub checkout whose stub build script only creates a directory, and its
fake `open` records the path it was given instead of launching anything. That
stub covers the post-build path, including a renamed app bundle and product
executable, a build that produces no bundle, and the full-SHA fetch:

```sh
./scripts/test-install-preview.sh
```
