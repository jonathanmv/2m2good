#!/bin/sh
# Install the latest 2m2better developer-preview release from GitHub Releases.
#
# This file is the stable public entry point used by:
#   curl -fsSL https://raw.githubusercontent.com/jonathanmv/2m2good/main/scripts/install.sh | sh
#
# It intentionally has no credentials, update feed, sudo path, signing step, or
# Gatekeeper bypass. The package is verified with the GitHub-published SHA-256
# manifest before it is copied into the invoking user's ~/Applications.
set -eu

SCRIPT_NAME="2m2better installer"
REPOSITORY="jonathanmv/2m2good"
RELEASE_API_URL="https://api.github.com/repos/$REPOSITORY/releases/latest"
APPLICATION_NAME="2m2better.app"
APPLICATION_EXECUTABLE="BreakCompanion"
BUNDLE_IDENTIFIER="local.break-companion.pilot"

fail() {
    printf '%s: ERROR: %s\n' "$SCRIPT_NAME" "$1" >&2
    exit 1
}

usage() {
    cat <<'EOF'
2m2better macOS developer-preview installer

Usage:
  install.sh [--replace] [--no-launch] [--dry-run]

The default installs the latest non-draft, non-prerelease GitHub Release for
this Mac's architecture into ~/Applications/2m2better.app. If that app already
exists, the installer asks only 2m2better to quit, waits for it to exit, then
replaces it safely; the old app bundle is moved to a timestamped .previous
backup and is not deleted.

Options:
  --replace    Accepted for compatibility; existing apps are now updated by default.
  --no-launch  Install and index the app, but do not ask macOS to open it.
  --dry-run    Check macOS and architecture, then print the plan without
               contacting GitHub or changing files.
  -h, --help   Show this help.

The release ZIP and its exact .sha256 manifest are both selected from the
public GitHub Release API. No sudo, account, credentials, telemetry, separate
update server, user-data deletion, Developer ID signing, notarization, or
Gatekeeper bypass is used.
EOF
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "$2"
}

# GitHub's API returns browser_download_url values that either point at the
# repository download route or redirect to one of these two GitHub asset hosts.
# Keeping this allowlist beside the download code makes the sole-source policy
# auditable without trusting a URL merely because it appeared in JSON.
is_allowed_asset_url() {
    case "$1" in
        "https://github.com/$REPOSITORY/releases/download/"*) return 0 ;;
        https://objects.githubusercontent.com/*) return 0 ;;
        https://release-assets.githubusercontent.com/*) return 0 ;;
        *) return 1 ;;
    esac
}

is_allowed_api_url() {
    case "$1" in
        "$RELEASE_API_URL"|"$RELEASE_API_URL"\?*) return 0 ;;
        *) return 1 ;;
    esac
}

architecture=$(uname -m 2>/dev/null || printf unknown)
case "$architecture" in
    arm64|x86_64) ;;
    *) fail "unsupported Mac architecture '$architecture'; published assets support arm64 and x86_64." ;;
esac

launch=1
replace=0
dry_run=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --replace)
            replace=1
            shift
            ;;
        --no-launch)
            launch=0
            shift
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            fail "unexpected '--'; this installer has no positional arguments."
            ;;
        *)
            fail "unknown option '$1'; use --help for usage."
            ;;
    esac
done

[ -n "${HOME:-}" ] || fail 'HOME is not set; the installer only targets the invoking user.'
case "$HOME" in
    /*) ;;
    *) fail "HOME must be an absolute path (got '$HOME')." ;;
esac
[ -d "$HOME" ] || fail "the invoking user's home directory does not exist: $HOME"
[ -w "$HOME" ] || fail "the invoking user's home directory is not writable: $HOME (sudo is not used)"

install_root="$HOME/Applications"
installed_app="$install_root/$APPLICATION_NAME"
if [ -e "$install_root" ] || [ -L "$install_root" ]; then
    [ -d "$install_root" ] || fail "installation directory is not a directory: $install_root"
    [ ! -L "$install_root" ] || fail "installation directory is a symlink; refusing to follow it: $install_root"
fi
if [ -e "$installed_app" ] || [ -L "$installed_app" ]; then
    [ ! -L "$installed_app" ] || fail "existing installation is a symlink; refusing to replace it: $installed_app"
    [ -d "$installed_app" ] || fail "existing installation is not an app bundle directory: $installed_app"
fi

if [ "$(uname -s 2>/dev/null || printf unknown)" != "Darwin" ]; then
    fail 'this installer supports macOS only; no files or network requests were made.'
fi
require_command sw_vers 'sw_vers is required to check the macOS version.'
macos_version=$(sw_vers -productVersion 2>/dev/null || true)
macos_major=${macos_version%%.*}
case "$macos_major" in
    ''|*[!0-9]*) fail "could not parse macOS version '$macos_version'." ;;
esac
[ "$macos_major" -ge 14 ] || fail "macOS 14 (Sonoma) or newer is required; detected macOS $macos_version."

if [ "$dry_run" -eq 1 ]; then
    printf '%s\n' '2m2better INSTALL PLAN'
    printf '  Release source:   GitHub Releases (%s)\n' "$REPOSITORY"
    printf '  Architecture:     %s\n' "$architecture"
    printf '  Release asset:    2m2better-v<latest-version>-macos-%s.zip\n' "$architecture"
    printf '  Checksum asset:   2m2better-v<latest-version>-macos-%s.zip.sha256\n' "$architecture"
    printf '  Install location: %s\n' "$installed_app"
    if [ "$replace" -eq 1 ]; then
        printf '%s\n' '  Existing app:     update after verification; --replace is accepted for compatibility; retain a timestamped .previous backup'
    else
        printf '%s\n' '  Existing app:     update after verification; ask only 2m2better to quit; retain a timestamped .previous backup'
    fi
    if [ "$launch" -eq 1 ]; then
        printf '%s\n' '  After install:    refresh Spotlight indexing and open the app'
    else
        printf '%s\n' '  After install:    refresh Spotlight indexing; do not open the app'
    fi
    printf '%s\n' '  Trust limitation: ad-hoc developer-preview package; not Developer ID signed or notarized. No Gatekeeper bypass.'
    printf '%s\n' 'Dry run complete: GitHub was not contacted and no files were changed.'
    exit 0
fi

require_command curl 'curl is required to obtain the GitHub Release assets.'
require_command plutil 'macOS plutil is required to parse the GitHub Release response.'
require_command shasum 'shasum is required to verify the exact SHA-256 checksum.'
require_command ditto 'macOS ditto is required to extract the app ZIP safely.'

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/2m2better-install.XXXXXX") || fail 'could not create a temporary installer directory.'
staging_root=
cleanup() {
    if [ -n "${staging_root:-}" ] && [ -d "$staging_root" ]; then
        rmdir "$staging_root" 2>/dev/null || true
    fi
    if [ -n "${work_dir:-}" ] && [ -d "$work_dir" ]; then
        rm -rf "$work_dir"
    fi
}
trap cleanup EXIT HUP INT TERM

# Download one response and reject a redirect that leaves GitHub. curl's -o
# keeps response bytes separate from its %{url_effective} diagnostic.
download() {
    url=$1
    destination=$2
    kind=$3
    case "$kind" in
        api)
            is_allowed_api_url "$url" || fail "refusing non-GitHub release API URL: $url"
            ;;
        asset)
            is_allowed_asset_url "$url" || fail "release asset used an unapproved HTTPS GitHub URL: $url"
            ;;
        *)
            fail "internal error: unknown download kind '$kind'"
            ;;
    esac

    effective_file="$destination.effective-url"
    if ! curl -fsSL --location --max-redirs 5 --connect-timeout 15 --max-time 120 \
        --proto '=https' --proto-redir '=https' \
        -H 'Accept: application/vnd.github+json' \
        -o "$destination" -w '%{url_effective}' "$url" > "$effective_file"; then
        rm -f "$effective_file"
        fail "GitHub Releases could not download $url."
    fi
    effective_url=$(cat "$effective_file")
    rm -f "$effective_file"
    case "$kind" in
        api) is_allowed_api_url "$effective_url" || fail "release API redirected outside approved GitHub API hosts: $effective_url" ;;
        asset) is_allowed_asset_url "$effective_url" || fail "release asset redirected outside approved GitHub asset hosts: $effective_url" ;;
    esac
}

app_is_running() {
    running=$(osascript -e "tell application id \"$BUNDLE_IDENTIFIER\" to get running" 2>/dev/null) || return 2
    [ "$running" = true ]
}

quit_running_app() {
    require_command osascript 'osascript is required to ask the existing 2m2better app to quit gracefully.'
    if app_is_running; then
        :
    else
        status=$?
        [ "$status" -eq 1 ] || fail 'could not verify whether 2m2better is running; nothing was replaced.'
        return 0
    fi

    printf '%s\n' 'Asking the existing 2m2better app to quit gracefully before replacement...'
    if ! osascript -e "tell application id \"$BUNDLE_IDENTIFIER\" to quit"; then
        fail '2m2better could not be asked to quit gracefully; nothing was replaced.'
    fi

    waited=0
    while :; do
        if app_is_running; then
            :
        else
            status=$?
            [ "$status" -eq 1 ] || fail 'could not verify that 2m2better quit; nothing was replaced.'
            break
        fi
        [ "$waited" -lt 60 ] || fail '2m2better did not quit within one minute; nothing was replaced.'
        sleep 1
        waited=$((waited + 1))
    done
}

extract_release_value() {
    key=$1
    plutil -extract "$key" raw -o - "$release_json" 2>/dev/null
}

# plutil is part of macOS and parses JSON without adding a Python/jq runtime
# prerequisite. The bounded array walk rejects malformed or unexpectedly huge
# asset lists rather than guessing at a URL.
asset_url_for_name() {
    expected_name=$1
    asset_index=0
    found=0
    found_url=
    while [ "$asset_index" -lt 1000 ]; do
        if ! asset_name=$(plutil -extract "assets.$asset_index.name" raw -o - "$release_json" 2>/dev/null); then
            break
        fi
        if [ "$asset_name" = "$expected_name" ]; then
            if [ "$found" -eq 1 ]; then
                return 2
            fi
            found_url=$(plutil -extract "assets.$asset_index.browser_download_url" raw -o - "$release_json" 2>/dev/null) || return 2
            found=1
        fi
        asset_index=$((asset_index + 1))
    done
    [ "$found" -eq 1 ] || return 1
    printf '%s\n' "$found_url"
}

release_json="$work_dir/release.json"
printf '%s\n' "Checking the latest GitHub Release for $architecture..."
download "$RELEASE_API_URL" "$release_json" api

release_tag=$(extract_release_value tag_name) || fail 'latest GitHub Release did not contain a tag_name.'
release_url=$(extract_release_value html_url) || fail 'latest GitHub Release did not contain an html_url.'
draft=$(extract_release_value draft) || fail 'latest GitHub Release did not contain a draft flag.'
prerelease=$(extract_release_value prerelease) || fail 'latest GitHub Release did not contain a prerelease flag.'
[ "$draft" = false ] || fail "refusing draft release '$release_tag'."
[ "$prerelease" = false ] || fail "refusing prerelease '$release_tag'."
case "$release_url" in
    "https://github.com/$REPOSITORY/releases/tag/"*) ;;
    *) fail "latest release page is not the approved $REPOSITORY GitHub Releases page: $release_url" ;;
esac

case "$release_tag" in
    v*) release_version=${release_tag#v} ;;
    *) fail "latest release tag '$release_tag' must use the existing v<version> release identity." ;;
esac
# This is the same SemVer shape used by release-identity.sh. The API response
# is not allowed to turn a tag into shell syntax or an unrelated asset name.
semver_re='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*)|([0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))(\.((0|[1-9][0-9]*)|([0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)))*)?(\+([0-9A-Za-z-]+)(\.[0-9A-Za-z-]+)*)?$'
printf '%s\n' "$release_version" | grep -Eq "$semver_re" || fail "latest release tag '$release_tag' is not valid semantic versioning."

artifact_name="2m2better-v${release_version}-macos-${architecture}.zip"
checksum_name="${artifact_name}.sha256"
if ! artifact_url=$(asset_url_for_name "$artifact_name"); then
    fail "latest release '$release_tag' is missing or has an invalid duplicate for required asset $artifact_name."
fi
if ! checksum_url=$(asset_url_for_name "$checksum_name"); then
    fail "latest release '$release_tag' is missing or has an invalid duplicate for required asset $checksum_name."
fi
is_allowed_asset_url "$artifact_url" || fail "required asset $artifact_name has an unapproved URL: $artifact_url"
is_allowed_asset_url "$checksum_url" || fail "required asset $checksum_name has an unapproved URL: $checksum_url"

printf 'Release:            %s\n' "$release_tag"
printf 'Architecture:       %s\n' "$architecture"
printf 'Release asset:      %s\n' "$artifact_name"
printf 'Install location:   %s\n' "$installed_app"
printf '%s\n' 'Downloading and verifying the exact SHA-256 manifest before installation...'
artifact_file="$work_dir/$artifact_name"
checksum_file="$work_dir/$checksum_name"
download "$artifact_url" "$artifact_file" asset
download "$checksum_url" "$checksum_file" asset

if ! expected_checksum=$(awk -v expected="$artifact_name" '
BEGIN { count = 0; valid = 1 }
NF == 2 {
    name = $2
    sub(/^\*/, "", name)
    if (name == expected) {
        count++
        digest = $1
        if (length(digest) != 64 || digest !~ /^[0-9A-Fa-f]+$/) valid = 0
    }
}
END {
    if (count != 1 || !valid) exit 1
    print tolower(digest)
}
' "$checksum_file"); then
    fail "checksum asset $checksum_name is malformed or does not name exactly $artifact_name."
fi
actual_checksum=$(shasum -a 256 "$artifact_file" | awk '{print tolower($1)}')
[ "$actual_checksum" = "$expected_checksum" ] || fail "SHA-256 mismatch for $artifact_name. Nothing was installed."
printf 'Verified SHA-256:    %s\n' "$actual_checksum"

extracted_dir="$work_dir/extracted"
mkdir "$extracted_dir"
if ! ditto -x -k "$artifact_file" "$extracted_dir"; then
    fail "could not extract verified release asset $artifact_name. Nothing was installed."
fi
extracted_app="$extracted_dir/$APPLICATION_NAME"
[ ! -L "$extracted_app" ] || fail "verified ZIP contained a symlink instead of the expected app bundle. Nothing was installed."
[ -d "$extracted_app" ] || fail "verified ZIP did not contain the expected $APPLICATION_NAME bundle. Nothing was installed."
[ ! -L "$extracted_app/Contents/Info.plist" ] || fail "verified app bundle contained a symlinked Info.plist. Nothing was installed."
[ -f "$extracted_app/Contents/Info.plist" ] || fail "verified app bundle is missing Contents/Info.plist. Nothing was installed."
[ ! -L "$extracted_app/Contents/MacOS/$APPLICATION_EXECUTABLE" ] || fail "verified app bundle contained a symlinked executable. Nothing was installed."
[ -x "$extracted_app/Contents/MacOS/$APPLICATION_EXECUTABLE" ] || fail "verified app bundle is missing its executable. Nothing was installed."

if [ -e "$install_root" ] || [ -L "$install_root" ]; then
    [ -d "$install_root" ] || fail "installation directory became non-directory during setup: $install_root"
else
    mkdir "$install_root" || fail "could not create $install_root (sudo is not used)."
fi
staging_root=$(mktemp -d "$install_root/.2m2better-install.XXXXXX") || fail "could not create a staging directory in $install_root."
staged_app="$staging_root/$APPLICATION_NAME"
mv "$extracted_app" "$staged_app" || fail 'could not stage the verified app bundle; nothing was installed.'

if [ -e "$installed_app" ] || [ -L "$installed_app" ]; then
    [ ! -L "$installed_app" ] || fail "installation appeared as a symlink; refusing to replace it: $installed_app"
    [ -d "$installed_app" ] || fail "installation appeared as a non-directory; refusing to replace it: $installed_app"
    quit_running_app
    backup="$install_root/.2m2better.app.previous.$$.app"
    backup_number=0
    while [ -e "$backup" ] || [ -L "$backup" ]; do
        backup_number=$((backup_number + 1))
        backup="$install_root/.2m2better.app.previous.$$.${backup_number}.app"
    done
    mv "$installed_app" "$backup" || fail "could not move the existing app to its backup: $backup"
    if ! mv "$staged_app" "$installed_app"; then
        if mv "$backup" "$installed_app"; then
            fail 'could not install the verified app; the previous app was restored.'
        fi
        fail "could not install the verified app and could not restore the previous app; previous app remains at $backup."
    fi
    printf 'Previous app retained: %s\n' "$backup"
else
    mv "$staged_app" "$installed_app" || fail 'could not install the verified app; nothing was replaced.'
fi

if command -v mdimport >/dev/null 2>&1; then
    if mdimport -f "$installed_app" >/dev/null 2>&1; then
        printf 'Spotlight indexing: refreshed\n'
    else
        printf 'Spotlight indexing: could not be refreshed automatically; run mdimport -f "%s" if needed.\n' "$installed_app" >&2
    fi
else
    printf 'Spotlight indexing: mdimport is unavailable; run mdimport -f "%s" if needed.\n' "$installed_app" >&2
fi

printf '%s\n' 'Trust limitation: this developer-preview package is ad-hoc signed, not Developer ID signed, and not notarized.'
printf '%s\n' 'macOS may require Finder Open or Privacy & Security approval. This installer does not bypass Gatekeeper.'
printf 'Installed app:       %s\n' "$installed_app"
if [ "$launch" -eq 1 ]; then
    if command -v open >/dev/null 2>&1 && open "$installed_app"; then
        printf '%s\n' 'Launch:               requested from macOS.'
    else
        printf 'Launch:               could not be requested; open "%s" manually.\n' "$installed_app" >&2
    fi
else
    printf 'Launch:               skipped (--no-launch); run open "%s" when ready.\n' "$installed_app"
fi
printf '%s\n' '2m2better developer preview installation complete.'
