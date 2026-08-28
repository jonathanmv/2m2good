#!/bin/sh
# Executable-interface tests for scripts/install.sh.
#
# The harness supplies small command doubles for macOS-only utilities and a
# deterministic GitHub API/assets fixture. It exercises the installer through
# its command-line interface; it does not inspect installer source text.
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
installer="$script_dir/install.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/2m2better-install-test.XXXXXX")
test_root=$(CDPATH= cd "$test_root" && pwd)
fake_bin="$test_root/fake-bin"
home="$test_root/home"
mkdir -p "$fake_bin" "$home" "$test_root/fixtures"

cleanup() { rm -rf "$test_root"; }
trap cleanup EXIT HUP INT TERM

fail_test() {
    printf 'installer tests: FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    haystack=$1
    needle=$2
    printf '%s\n' "$haystack" | grep -Fq -e "$needle" || fail_test "expected output to contain: $needle"
}

assert_not_exists() {
    [ ! -e "$1" ] && [ ! -L "$1" ] || fail_test "unexpected path exists: $1"
}

cat > "$fake_bin/uname" <<'EOF'
#!/bin/sh
case "${1:-}" in
    -s) printf '%s\n' Darwin ;;
    -m) printf '%s\n' "${INSTALL_TEST_ARCH:-arm64}" ;;
    *) exit 1 ;;
esac
EOF

cat > "$fake_bin/sw_vers" <<'EOF'
#!/bin/sh
[ "${1:-}" = -productVersion ] || exit 1
printf '%s\n' "${INSTALL_TEST_MACOS_VERSION:-14.0}"
EOF

cat > "$fake_bin/plutil" <<'EOF'
#!/bin/sh
set -eu
key=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -extract) key=$2; shift 2 ;;
        -o) shift 2 ;;
        *) shift ;;
    esac
done
[ -n "$key" ] || exit 1
tag=${INSTALL_TEST_TAG:-v1.2.3}
version=${tag#v}
arch=${INSTALL_TEST_ARCH:-arm64}
artifact="2m2better-v${version}-macos-${arch}.zip"
checksum="${artifact}.sha256"
base="https://github.com/jonathanmv/2m2good/releases/download/$tag"
case "$key" in
    tag_name) printf '%s\n' "$tag" ;;
    html_url) printf '%s\n' "https://github.com/jonathanmv/2m2good/releases/tag/$tag" ;;
    draft|prerelease) printf '%s\n' false ;;
    assets.*.name)
        rest=${key#assets.}
        index=${rest%%.*}
        mode=${INSTALL_TEST_MODE:-success}
        case "$mode:$index" in
            missing:0) printf '%s\n' "$checksum" ;;
            missing:*) exit 1 ;;
            duplicate:0|duplicate:1) printf '%s\n' "$artifact" ;;
            duplicate:2) printf '%s\n' "$checksum" ;;
            duplicate:*) exit 1 ;;
            *:0) printf '%s\n' "$artifact" ;;
            *:1) printf '%s\n' "$checksum" ;;
            *) exit 1 ;;
        esac
        ;;
    assets.*.browser_download_url)
        rest=${key#assets.}
        index=${rest%%.*}
        mode=${INSTALL_TEST_MODE:-success}
        case "$mode:$index" in
            invalid-url:0) printf '%s\n' 'https://example.invalid/not-a-github-asset.zip' ;;
            invalid-url:1|*:1|*:2) printf '%s/%s\n' "$base" "$checksum" ;;
            duplicate:0|duplicate:1) printf '%s/%s\n' "$base" "$artifact" ;;
            *:0) printf '%s/%s\n' "$base" "$artifact" ;;
            *) exit 1 ;;
        esac
        ;;
    *) exit 1 ;;
esac
EOF

cat > "$fake_bin/curl" <<'EOF'
#!/bin/sh
set -eu
output=
url=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o|-w|-H|--max-redirs|--connect-timeout|--max-time|--proto|--proto-redir)
            [ "$#" -ge 2 ] || exit 2
            if [ "$1" = -o ]; then output=$2; fi
            if [ "$1" = -w ]; then write_format=$2; fi
            shift 2
            ;;
        --location|--fail|--silent|--show-error|-s|-S|-f|-L)
            shift
            ;;
        *) url=$1; shift ;;
    esac
done
[ -n "$output" ] || exit 2
[ -n "$url" ] || exit 2
mkdir -p "$(dirname "$output")"
case "$url" in
    https://api.github.com/repos/jonathanmv/2m2good/releases/latest*)
        printf '%s\n' '{"tag_name":"v1.2.3","html_url":"https://github.com/jonathanmv/2m2good/releases/tag/v1.2.3","draft":false,"prerelease":false,"assets":[]}' > "$output"
        ;;
    *.sha256)
        if [ "${INSTALL_TEST_MODE:-success}" = mismatch ]; then
            printf '%064d  %s\n' 0 "$(basename "${url%.sha256}")" > "$output"
        else
            printf '%s  %s\n' "$INSTALL_TEST_DIGEST" "$(basename "${url%.sha256}")" > "$output"
        fi
        ;;
    *)
        cat "$INSTALL_TEST_ARTIFACT" > "$output"
        ;;
esac
printf '%s' "$url"
EOF

cat > "$fake_bin/ditto" <<'EOF'
#!/bin/sh
set -eu
# The verified fixture represents a ZIP with the expected top-level app bundle.
destination=
for argument in "$@"; do destination=$argument; done
mkdir -p "$destination/2m2better.app/Contents/MacOS"
printf '%s\n' '<?xml version="1.0"?><plist><dict/></plist>' > "$destination/2m2better.app/Contents/Info.plist"
printf '#!/bin/sh\nexit 0\n' > "$destination/2m2better.app/Contents/MacOS/BreakCompanion"
chmod +x "$destination/2m2better.app/Contents/MacOS/BreakCompanion"
EOF

cat > "$fake_bin/mdimport" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$INSTALL_TEST_MDMIMPORT_LOG"
exit 0
EOF

cat > "$fake_bin/open" <<'EOF'
#!/bin/sh
printf '%s\n' "${1:-}" >> "$INSTALL_TEST_OPEN_LOG"
exit 0
EOF

cat > "$fake_bin/osascript" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$INSTALL_TEST_OSASCRIPT_LOG"
case "$*" in
    *'get running'*)
        if [ "${INSTALL_TEST_RUNNING_APP:-0}" = 1 ] && [ ! -e "${INSTALL_TEST_QUIT_MARKER:-}" ]; then
            printf '%s\n' true
        else
            printf '%s\n' false
        fi
        ;;
    *)
        if [ -n "${INSTALL_TEST_QUIT_MARKER:-}" ]; then
            : > "$INSTALL_TEST_QUIT_MARKER"
        fi
        ;;
esac
exit 0
EOF

chmod +x "$fake_bin"/*

artifact_fixture="$test_root/fixtures/release.zip"
printf '%s\n' 'deterministic release ZIP fixture' > "$artifact_fixture"
digest=$(shasum -a 256 "$artifact_fixture" | awk '{print $1}')
export INSTALL_TEST_ARTIFACT="$artifact_fixture"
export INSTALL_TEST_DIGEST="$digest"

run_installer() {
    PATH="$fake_bin:/usr/bin:/bin" \
    HOME="$home" \
    INSTALL_TEST_MDMIMPORT_LOG="$test_root/mdimport.log" \
    INSTALL_TEST_OPEN_LOG="$test_root/open.log" \
    "$installer" "$@"
}

# Architecture selection is visible in the executable plan and supports both
# published asset architectures.
arm_plan=$(INSTALL_TEST_ARCH=arm64 run_installer --dry-run 2>&1)
assert_contains "$arm_plan" 'Architecture:     arm64'
assert_contains "$arm_plan" 'macos-arm64.zip'
intel_plan=$(INSTALL_TEST_ARCH=x86_64 run_installer --dry-run 2>&1)
assert_contains "$intel_plan" 'Architecture:     x86_64'
assert_contains "$intel_plan" 'macos-x86_64.zip'

# A valid release is downloaded, checked against the exact manifest, installed
# below the invoking HOME, indexed, opened, and reported with the trust limit.
output=$(INSTALL_TEST_ARCH=arm64 run_installer 2>&1) || fail_test "valid installation failed: $output"
installed="$home/Applications/2m2better.app"
[ -x "$installed/Contents/MacOS/BreakCompanion" ] || fail_test 'valid release was not installed'
assert_contains "$output" "Installed app:       $installed"
assert_contains "$output" 'Spotlight indexing: refreshed'
assert_contains "$output" 'Trust limitation: this developer-preview package is ad-hoc signed, not Developer ID signed, and not notarized.'
assert_contains "$output" 'does not bypass Gatekeeper'
[ "$(cat "$test_root/open.log")" = "$installed" ] || fail_test 'installed app was not launched'
[ "$(cat "$test_root/mdimport.log")" = "-f $installed" ] || fail_test 'Spotlight was not refreshed for the installed app'

# Existing installations are updated by the same public command. The API,
# checksum, backup, and replacement protections still apply without requiring
# a special flag; --replace remains accepted for compatibility.
existing="$test_root/existing.app"
mkdir -p "$existing"
printf '%s\n' 'do not overwrite' > "$existing/marker"
existing_home="$test_root/existing-home"
mkdir -p "$existing_home/Applications/2m2better.app" "$existing_home/Library/Application Support/2m2better"
printf '%s\n' 'keep this app' > "$existing_home/Applications/2m2better.app/marker"
printf '%s\n' 'keep timer and session state' > "$existing_home/Library/Application Support/2m2better/companion-state.json"
quit_marker="$test_root/2m2better-quit.marker"
update_output=$(HOME="$existing_home" INSTALL_TEST_MODE=success \
    INSTALL_TEST_RUNNING_APP=1 INSTALL_TEST_QUIT_MARKER="$quit_marker" \
    INSTALL_TEST_OSASCRIPT_LOG="$test_root/osascript.log" \
    PATH="$fake_bin:/usr/bin:/bin" INSTALL_TEST_MDMIMPORT_LOG="$test_root/mdimport-existing.log" \
    INSTALL_TEST_OPEN_LOG="$test_root/open-existing.log" "$installer" --no-launch 2>&1) || \
    fail_test "existing installation update failed: $update_output"
assert_contains "$update_output" 'Previous app retained:'
assert_contains "$(cat "$test_root/osascript.log")" 'local.break-companion'
[ -e "$quit_marker" ] || fail_test 'running 2m2better was not asked to quit before replacement'
[ -x "$existing_home/Applications/2m2better.app/Contents/MacOS/BreakCompanion" ] || fail_test 'replacement app was not installed'
previous_count=0
previous_marker=
for previous in "$existing_home/Applications"/.2m2better.app.previous.*.app; do
    if [ -d "$previous" ]; then
        previous_count=$((previous_count + 1))
        previous_marker="$previous/marker"
    fi
done
[ "$previous_count" -eq 1 ] || fail_test 'previous app backup was not retained'
[ "$(cat "$previous_marker")" = 'keep this app' ] || fail_test 'previous app backup lost its contents'
[ "$(cat "$existing_home/Library/Application Support/2m2better/companion-state.json")" = 'keep timer and session state' ] || fail_test 'timer/session state outside the app bundle changed'
unset INSTALL_TEST_RUNNING_APP INSTALL_TEST_QUIT_MARKER INSTALL_TEST_OSASCRIPT_LOG

# A checksum mismatch is rejected before extraction or installation.
mismatch_home="$test_root/mismatch-home"
mkdir -p "$mismatch_home"
if output=$(HOME="$mismatch_home" INSTALL_TEST_MODE=mismatch \
    PATH="$fake_bin:/usr/bin:/bin" INSTALL_TEST_MDMIMPORT_LOG="$test_root/mdimport-mismatch.log" \
    INSTALL_TEST_OPEN_LOG="$test_root/open-mismatch.log" "$installer" --no-launch 2>&1); then
    fail_test 'checksum mismatch unexpectedly succeeded'
fi
assert_contains "$output" 'SHA-256 mismatch'
assert_not_exists "$mismatch_home/Applications/2m2better.app"
assert_not_exists "$test_root/open-mismatch.log"

# Missing and malformed/duplicate release assets are rejected before any app
# is staged.
for mode in missing duplicate; do
    mode_home="$test_root/$mode-home"
    mkdir -p "$mode_home"
    if output=$(HOME="$mode_home" INSTALL_TEST_MODE="$mode" \
        PATH="$fake_bin:/usr/bin:/bin" INSTALL_TEST_MDMIMPORT_LOG="$test_root/mdimport-$mode.log" \
        INSTALL_TEST_OPEN_LOG="$test_root/open-$mode.log" "$installer" --no-launch 2>&1); then
        fail_test "$mode release asset fixture unexpectedly succeeded"
    fi
    assert_contains "$output" 'missing or has an invalid duplicate for required asset'
    assert_not_exists "$mode_home/Applications/2m2better.app"
done

invalid_home="$test_root/invalid-url-home"
mkdir -p "$invalid_home"
if output=$(HOME="$invalid_home" INSTALL_TEST_MODE=invalid-url \
    PATH="$fake_bin:/usr/bin:/bin" INSTALL_TEST_MDMIMPORT_LOG="$test_root/mdimport-invalid.log" \
    INSTALL_TEST_OPEN_LOG="$test_root/open-invalid.log" "$installer" --no-launch 2>&1); then
    fail_test 'invalid release asset URL unexpectedly succeeded'
fi
assert_contains "$output" 'unapproved URL'
assert_not_exists "$invalid_home/Applications/2m2better.app"

printf '%s\n' 'installer tests: PASS (architecture, release selection, checksum, assets, replacement safety, indexing, launch, and trust messaging)'
