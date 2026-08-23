#!/bin/sh
# Safe shell-level tests for scripts/install-preview.sh.
# All destinations are private mktemp children; the fake git refuses every
# operation except --version, so these tests cannot clone, build, or launch.
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
installer="$script_dir/install-preview.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/2m2good-installer-test.XXXXXX")
fake_bin="$test_root/fake-bin"
fake_sdk="$test_root/fake-sdk"
mkdir -p "$fake_bin" "$fake_sdk" "$test_root/home"

cleanup() {
    rm -rf "$test_root"
}
trap cleanup EXIT HUP INT TERM

fail_test() {
    printf 'installer test: FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    haystack=$1
    needle=$2
    printf '%s\n' "$haystack" | grep -Fq "$needle" || \
        fail_test "expected output to contain: $needle"
}

cat > "$fake_bin/uname" <<'EOF'
#!/bin/sh
case "${1:-}" in
    -s) printf '%s\n' Darwin ;;
    -m) printf '%s\n' arm64 ;;
    *) exit 1 ;;
esac
EOF
cat > "$fake_bin/sw_vers" <<'EOF'
#!/bin/sh
[ "${1:-}" = "-productVersion" ] || exit 1
printf '%s\n' "${PREVIEW_TEST_MACOS_VERSION:-14.0}"
EOF
cat > "$fake_bin/git" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
    printf 'git version %s\n' "${PREVIEW_TEST_GIT_VERSION:-2.48.1}"
    exit 0
fi
printf 'fake git: unexpected network or checkout operation\n' >&2
exit 97
EOF
cat > "$fake_bin/xcrun" <<'EOF'
#!/bin/sh
case "${1:-}" in
    --find)
        [ "${2:-}" = swiftc ] || exit 1
        printf '%s\n' "$PREVIEW_TEST_FAKE_BIN/fake-swiftc"
        ;;
    swiftc)
        printf '%s\n' 'Apple Swift version 6.3.2 (swiftlang-test)'
        ;;
    --show-sdk-path)
        printf '%s\n' "$PREVIEW_TEST_FAKE_SDK"
        ;;
    *) exit 1 ;;
esac
EOF
for command_name in curl codesign open; do
    cat > "$fake_bin/$command_name" <<'EOF'
#!/bin/sh
exit 0
EOF
done
chmod +x "$fake_bin"/*

run_installer() {
    PREVIEW_TEST_FAKE_BIN="$fake_bin" PREVIEW_TEST_FAKE_SDK="$fake_sdk" \
        PATH="$fake_bin:/usr/bin:/bin" HOME="$test_root/home" "$installer" "$@"
}

help_output=$(run_installer --help 2>&1)
assert_contains "$help_output" 'early developer-preview installer'

plan_destination="$test_root/preview"
plan_output=$(run_installer \
    --dry-run \
    --repo https://github.com/example/2m2good.git \
    --ref feature/preview \
    --destination "$plan_destination" \
    --no-launch 2>&1)
assert_contains "$plan_output" '2m2good EARLY DEVELOPER PREVIEW'
assert_contains "$plan_output" 'https://github.com/example/2m2good.git'
assert_contains "$plan_output" 'feature/preview'
assert_contains "$plan_output" "$plan_destination"
assert_contains "$plan_output" './scripts/build-app.sh'
assert_contains "$plan_output" 'do not open the app'
assert_contains "$plan_output" 'Dry run complete'
[ ! -e "$plan_destination" ] || fail_test 'dry-run created its destination'

if output=$(run_installer --dry-run --unknown-option 2>&1); then
    fail_test 'unknown option unexpectedly succeeded'
fi
assert_contains "$output" "unknown option '--unknown-option'"

if output=$(run_installer --dry-run --repo "file:///tmp/repository" 2>&1); then
    fail_test 'non-HTTPS repository unexpectedly succeeded'
fi
assert_contains "$output" 'repository must be an HTTPS URL'

if output=$(run_installer --dry-run --ref 'feature with spaces' --destination "$test_root/bad-ref" 2>&1); then
    fail_test 'invalid ref unexpectedly succeeded'
fi
assert_contains "$output" 'ref must be a non-empty branch'

existing="$test_root/existing-checkout"
mkdir "$existing"
printf '%s\n' 'leave this uncommitted marker alone' > "$existing/marker.txt"
if output=$(run_installer --dry-run --destination "$existing" 2>&1); then
    fail_test 'existing destination unexpectedly succeeded'
fi
assert_contains "$output" 'destination already exists'
[ "$(cat "$existing/marker.txt")" = 'leave this uncommitted marker alone' ] || \
    fail_test 'existing destination marker changed'

if output=$(PREVIEW_TEST_GIT_VERSION=2.19.9 run_installer --dry-run --destination "$test_root/old-git" 2>&1); then
    fail_test 'old Git unexpectedly passed prerequisites'
fi
assert_contains "$output" 'Git 2.20 or newer is required'
[ ! -e "$test_root/old-git" ] || fail_test 'prerequisite failure created a destination'

if output=$(PREVIEW_TEST_MACOS_VERSION=13.6 run_installer --dry-run --destination "$test_root/old-macos" 2>&1); then
    fail_test 'unsupported macOS unexpectedly passed prerequisites'
fi
assert_contains "$output" 'macOS 14 (Sonoma) or newer is required'
[ ! -e "$test_root/old-macos" ] || fail_test 'prerequisite failure created a destination'

if output=$(BREAK_SDK_PATH="$test_root/missing-sdk" run_installer --dry-run --destination "$test_root/missing-sdk-preview" 2>&1); then
    fail_test 'missing SDK override unexpectedly passed prerequisites'
fi
assert_contains "$output" 'BREAK_SDK_PATH does not point to an SDK directory'
[ ! -e "$test_root/missing-sdk-preview" ] || fail_test 'SDK prerequisite failure created a destination'

printf '%s\n' 'installer tests: PASS (safe dry-run and failure harness)'
