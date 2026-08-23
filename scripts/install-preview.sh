#!/bin/sh
# 2m2good early developer-preview source installer.
#
# This script deliberately installs only into a new, user-selected directory. It
# does not use sudo, write to /Applications, install a login item, or remove
# anything. Keep the plan and confirmation below readable: this script is also
# intended to be auditable when run through curl.
set -eu

SCRIPT_NAME="2m2good preview installer"
DEFAULT_REPOSITORY="https://github.com/jonathanmv/2m2good.git"
DEFAULT_REF="main"

fail() {
    printf '%s: ERROR: %s\n' "$SCRIPT_NAME" "$1" >&2
    exit 1
}

# Only ever removes the destination this run created while it is still empty:
# rmdir refuses a non-empty directory, so any partial checkout is preserved.
fail_after_destination() {
    if rmdir "$destination" 2>/dev/null; then
        fail "$1 The destination was still empty and was removed, so the same path can be reused: $destination"
    fi
    fail "$1 What was already written was left intact for inspection: $destination"
}

usage() {
    cat <<'EOF'
2m2good early developer-preview installer

Usage:
  install-preview.sh [options]

Options:
  --repo URL          HTTPS Git repository (default: the public 2m2good repo)
  --ref REF           Branch, tag, or full 40-character commit SHA (default: main)
  --destination DIR   New checkout directory (default: ~/2m2good-developer-preview)
  --no-launch         Build the app but do not ask macOS to open it
  --dry-run           Validate, print the plan, and make no changes or network requests
  --confirm           Skip the interactive confirmation after printing the plan
  -h, --help          Show this help

The destination must not already exist. The installer never uses sudo and does
not delete or modify an existing checkout.
EOF
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "$2"
}

repository="$DEFAULT_REPOSITORY"
ref="$DEFAULT_REF"
destination=""
launch=1
dry_run=0
confirm=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo)
            [ "$#" -ge 2 ] || fail "--repo requires an HTTPS repository URL."
            repository=$2
            shift 2
            ;;
        --ref)
            [ "$#" -ge 2 ] || fail "--ref requires a branch, tag, or full 40-character commit SHA."
            ref=$2
            shift 2
            ;;
        --destination)
            [ "$#" -ge 2 ] || fail "--destination requires a directory path."
            destination=$2
            shift 2
            ;;
        --no-launch)
            launch=0
            shift
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        --confirm)
            confirm=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            fail "unexpected --; pass options directly to this installer."
            ;;
        -* )
            fail "unknown option '$1'; use --help for usage."
            ;;
        *)
            fail "unexpected argument '$1'; use --help for usage."
            ;;
    esac
done

if [ -z "$destination" ]; then
    if [ -z "${HOME:-}" ]; then
        fail "HOME is not set; pass an absolute --destination instead."
    fi
    destination="$HOME/2m2good-developer-preview"
fi

case "$repository" in
    https://*) ;;
    *) fail "repository must be an HTTPS URL (refusing '$repository'); the preview does not accept SSH or local paths." ;;
esac

# Keep the ref printable and prevent it from becoming another option. This
# covers normal Git branch/tag names and full hexadecimal commit SHAs.
case "$ref" in
    ""|-*|*[!A-Za-z0-9._/+@-]*)
        fail "ref must be a non-empty branch, tag, or full 40-character commit SHA without spaces or shell punctuation."
        ;;
esac

# Only a complete object id can be requested from a remote, so exactly one
# spelling takes the exact-revision path. Every other name, including one that
# merely looks hexadecimal, is resolved as a branch or tag.
ref_is_revision=0
ref_is_abbreviated_hex=0
if printf '%s\n' "$ref" | grep -Eq '^[0-9a-fA-F]{40}$'; then
    ref_is_revision=1
elif printf '%s\n' "$ref" | grep -Eq '^[0-9a-fA-F]{7,39}$'; then
    ref_is_abbreviated_hex=1
fi

case "$destination" in
    /*) ;;
    *) destination="$PWD/$destination" ;;
esac
destination=$(printf '%s\n' "$destination" | tr -s /)
while [ "$destination" != "/" ] && [ "${destination%/}" != "$destination" ]; do
    destination=${destination%/}
done
[ "$destination" != "/" ] || fail "refusing the filesystem root as --destination."

# The installer is intentionally macOS-only. Check the host before attempting
# any checkout so a bad invocation cannot create a partial destination.
[ "$(uname -s 2>/dev/null || printf unknown)" = "Darwin" ] || \
    fail "this preview installer supports macOS only; no files or network requests were made."

require_command sw_vers "macOS version could not be checked; sw_vers is required."
require_command git "Git is required (Git 2.20+). Install Apple Command Line Tools or Xcode, then retry."
require_command curl "curl is required for the curl-driven preview path; macOS normally includes it."
require_command xcrun "Apple Command Line Tools or Xcode are required (xcrun is missing). Run 'xcode-select --install' or select an Xcode toolchain, then retry."
require_command codesign "macOS codesign is missing; use Apple Command Line Tools or Xcode."
require_command open "macOS 'open' is missing; run this installer on macOS."

macos_version=$(sw_vers -productVersion 2>/dev/null || true)
macos_major=${macos_version%%.*}
case "$macos_major" in
    ""|*[!0-9]*) fail "could not parse macOS version '$macos_version'." ;;
esac
[ "$macos_major" -ge 14 ] || \
    fail "macOS 14 (Sonoma) or newer is required; detected macOS $macos_version. Upgrade macOS or build this source manually on a supported system."

architecture=$(uname -m 2>/dev/null || printf unknown)
case "$architecture" in
    arm64|x86_64) ;;
    *) fail "unsupported Mac architecture '$architecture'; this preview supports arm64 and x86_64." ;;
esac

git_version_line=$(git --version 2>/dev/null || true)
git_version_number=${git_version_line#git version }
git_major=${git_version_number%%.*}
git_minor=${git_version_number#*.}
git_minor=${git_minor%%.*}
case "$git_major:$git_minor" in
    *[!0-9:]*|:*|*:) fail "could not parse Git version '$git_version_line'; Git 2.20+ is required." ;;
esac
if [ "$git_major" -lt 2 ] || { [ "$git_major" -eq 2 ] && [ "$git_minor" -lt 20 ]; }; then
    fail "Git 2.20 or newer is required; detected $git_version_number. Install/update Git through Apple Command Line Tools or Xcode, then retry."
fi

if ! swiftc_path=$(xcrun --find swiftc 2>&1); then
    fail "Apple Swift compiler was not found. Install Apple Command Line Tools or Xcode and select its toolchain; xcrun said: $swiftc_path"
fi
if ! swift_version_line=$(xcrun swiftc --version 2>&1); then
    fail "Apple Swift compiler could not run. Install/select Xcode or Command Line Tools; xcrun said: $swift_version_line"
fi
swift_version=$(printf '%s\n' "$swift_version_line" | sed -n 's/.*Swift version \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1.\2/p' | head -n 1)
[ -n "$swift_version" ] || fail "could not identify the Swift compiler version from: $swift_version_line"
swift_major=${swift_version%%.*}
swift_minor=${swift_version#*.}
if [ "$swift_major" -lt 5 ] || { [ "$swift_major" -eq 5 ] && [ "$swift_minor" -lt 9 ]; }; then
    fail "Swift 5.9 or newer from Xcode/Apple Command Line Tools is required; detected Swift $swift_version."
fi

if [ -n "${BREAK_SDK_PATH:-}" ]; then
    sdk_path=$BREAK_SDK_PATH
    sdk_source="BREAK_SDK_PATH override"
    [ -d "$sdk_path" ] || fail "BREAK_SDK_PATH does not point to an SDK directory: $sdk_path"
else
    if ! sdk_path=$(xcrun --show-sdk-path 2>&1); then
        fail "a macOS SDK could not be found. Install/select Xcode or Apple Command Line Tools; xcrun said: $sdk_path"
    fi
    [ -d "$sdk_path" ] || fail "xcrun reported a missing macOS SDK directory: $sdk_path"
    sdk_source="xcrun default"
fi

# Refuse the destination itself even when it is a dangling symlink. Only its
# parent may be created after confirmation.
if [ -e "$destination" ] || [ -L "$destination" ]; then
    fail "destination already exists: $destination. Choose a new path; existing files and uncommitted work were not changed."
fi
destination_parent=${destination%/*}
[ -n "$destination_parent" ] || destination_parent=/
if [ -e "$destination_parent" ] && [ ! -d "$destination_parent" ]; then
    fail "destination parent is not a directory: $destination_parent"
fi
if [ -d "$destination_parent" ] && [ ! -w "$destination_parent" ]; then
    fail "destination parent is not writable: $destination_parent (sudo is not used)"
fi

printf '\n%s\n' '2m2good EARLY DEVELOPER PREVIEW'
printf '%s\n' 'This is a source checkout and local build, not a consumer release installer.'
printf '%s\n' 'Review these values before continuing:'
printf '  Repository:       %s\n' "$repository"
printf '  Selected ref:      %s\n' "$ref"
printf '  Destination:       %s\n' "$destination"
printf '  Toolchain:         Swift %s at %s\n' "$swift_version" "$swiftc_path"
printf '  macOS SDK:         %s (%s)\n' "$sdk_path" "$sdk_source"
printf '  Build command:     (cd "%s" && ./scripts/build-app.sh)\n' "$destination"
printf '  App output:        the app bundle that scripts/build-app.sh reports, under "%s/.build/app"\n' "$destination"
if [ "$launch" -eq 1 ]; then
    printf '  Launch behavior:   open that reported app bundle after a successful build\n'
else
    printf '  Launch behavior:   do not open the app after a successful build\n'
fi
printf '%s\n' '  Network:            Git source fetch only; the app has no runtime network service, account, or analytics.'
printf '%s\n' '  Safety:             no sudo, credential prompts, global install, update service, or deletion.'
printf '%s\n\n' 'The requested ref is not an integrity guarantee; review the source and ref yourself.'

if [ "$dry_run" -eq 1 ]; then
    printf '%s\n' 'Dry run complete: no checkout, build, launch, or network request was performed.'
    exit 0
fi

if [ "$confirm" -eq 0 ]; then
    if [ ! -r /dev/tty ]; then
        fail "no interactive terminal is available for confirmation; review the plan and rerun with --confirm."
    fi
    printf '%s' 'Continue into this new destination? [y/N] '
    answer=
    IFS= read -r answer < /dev/tty || fail 'confirmation could not be read; no files or network requests were made.'
    case "$answer" in
        y|Y|yes|YES|Yes) ;;
        *) printf '%s\n' 'Cancelled: no files or network requests were made.'; exit 0 ;;
    esac
fi

# mkdir without -p for the final component makes the destination creation
# exclusive. If another process wins the race, nothing is cloned into it.
if ! mkdir -p "$destination_parent"; then
    fail "could not create destination parent: $destination_parent"
fi
if ! mkdir "$destination"; then
    fail "destination appeared during setup: $destination; nothing was cloned into it."
fi

printf '%s\n' 'Fetching source...'
if [ "$ref_is_revision" -eq 1 ]; then
    if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 --no-single-branch -- "$repository" "$destination"; then
        fail_after_destination "source checkout failed."
    fi
    if ! (cd "$destination" && GIT_TERMINAL_PROMPT=0 git fetch --depth 1 origin "$ref" && git checkout --detach FETCH_HEAD); then
        fail_after_destination "revision '$ref' could not be fetched or checked out."
    fi
else
    if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$ref" -- "$repository" "$destination"; then
        clone_failure="source checkout for ref '$ref' failed; Git reported the cause above."
        if [ "$ref_is_abbreviated_hex" -eq 1 ]; then
            clone_failure="$clone_failure If '$ref' was meant as a commit SHA, note that an abbreviated SHA cannot be fetched from a remote; pass the full 40-character SHA."
        fi
        fail_after_destination "$clone_failure"
    fi
fi

exact_revision=$(git -C "$destination" rev-parse HEAD 2>/dev/null || true)
[ -n "$exact_revision" ] || fail "source checkout completed without a readable revision; destination left intact: $destination"
printf 'Checked out revision: %s\n' "$exact_revision"

[ -x "$destination/scripts/build-app.sh" ] || \
    fail "source checkout has no executable scripts/build-app.sh; destination left intact: $destination"
printf '%s\n' 'Building with the repository script...'
# scripts/build-app.sh echoes the app bundle it produced as its last stdout
# line, so the bundle name lives in one place and can be renamed there alone.
if ! build_report=$(cd "$destination" && ./scripts/build-app.sh); then
    printf '%s\n' "$build_report" >&2
    fail "the local build failed; source and build output were left intact for inspection: $destination"
fi
app_path=$(printf '%s\n' "$build_report" | tail -n 1)
case "$app_path" in
    /*) ;;
    *) fail "scripts/build-app.sh did not report an absolute app bundle path (got '$app_path'); destination left intact: $destination" ;;
esac
[ -x "$app_path/Contents/MacOS/BreakCompanion" ] || \
    fail "build did not produce the expected app: $app_path"
printf 'Built app bundle: %s\n' "$app_path"

if [ "$launch" -eq 1 ]; then
    printf 'Launching: %s\n' "$app_path"
    if ! open "$app_path"; then
        fail "the app was built but macOS could not open it. Launch it manually with: open \"$app_path\""
    fi
else
    printf '%s\n' "Built without launching. Run: open \"$app_path\""
fi

printf '%s\n' 'Early developer preview ready.'
printf '%s\n' 'This checkout is intentionally local and unsigned/ad-hoc signed; it has no automatic updates or rollback.'
