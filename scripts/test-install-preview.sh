#!/bin/sh
# Safe shell-level tests for scripts/install-preview.sh.
# All destinations are private mktemp children. The fake git never reaches the
# network: it either refuses a clone or copies a local stub checkout whose stub
# build script only creates a directory, and the fake open records instead of
# launching, so these tests cannot fetch, compile, or start an app.
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
installer="$script_dir/install-preview.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/2m2good-installer-test.XXXXXX")
test_root=$(CDPATH= cd "$test_root" && pwd)
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
    printf '%s\n' "$haystack" | grep -Fq -e "$needle" || \
        fail_test "expected output to contain: $needle"
}

assert_lacks() {
    haystack=$1
    needle=$2
    if printf '%s\n' "$haystack" | grep -Fq -e "$needle"; then
        fail_test "expected output not to contain: $needle"
    fi
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
[ -z "${PREVIEW_TEST_GIT_LOG:-}" ] || printf '%s\n' "$*" >> "$PREVIEW_TEST_GIT_LOG"
if [ "${1:-}" = "--version" ]; then
    printf 'git version %s\n' "${PREVIEW_TEST_GIT_VERSION:-2.48.1}"
    exit 0
fi
if [ "${1:-}" = "-C" ] && [ "${3:-}" = "rev-parse" ]; then
    printf '%s\n' "${PREVIEW_TEST_GIT_REVISION:-d0ee7e5574877a042f83bf480c51db083d5eb32e}"
    exit 0
fi
if [ -n "${PREVIEW_TEST_GIT_STUB_REPO:-}" ]; then
    case "${1:-}" in
        clone)
            for argument in "$@"; do clone_target=$argument; done
            cp -R "$PREVIEW_TEST_GIT_STUB_REPO/." "$clone_target/"
            exit 0
            ;;
        init)
            mkdir -p .git
            exit 0
            ;;
        remote|fetch)
            exit 0
            ;;
        checkout)
            cp -R "$PREVIEW_TEST_GIT_STUB_REPO/." .
            exit 0
            ;;
    esac
fi
if [ "${1:-}" = "clone" ] && [ -n "${PREVIEW_TEST_GIT_PARTIAL_CLONE:-}" ]; then
    for argument in "$@"; do clone_target=$argument; done
    printf 'partial checkout\n' > "$clone_target/partial-marker.txt"
    printf 'fake git: clone interrupted after writing\n' >&2
    exit 1
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
for command_name in curl codesign; do
    cat > "$fake_bin/$command_name" <<'EOF'
#!/bin/sh
exit 0
EOF
done
cat > "$fake_bin/open" <<'EOF'
#!/bin/sh
[ -z "${PREVIEW_TEST_OPEN_LOG:-}" ] || printf '%s\n' "${1:-}" >> "$PREVIEW_TEST_OPEN_LOG"
exit 0
EOF
chmod +x "$fake_bin"/*

# A stub checkout whose build script reports its bundle on stdout exactly the
# way scripts/build-app.sh does, so the installer's post-build path runs
# without a real clone, toolchain, or app launch.
stub_repo="$test_root/stub-repo/scripts"
mkdir -p "$stub_repo"
cat > "$stub_repo/build-app.sh" <<'EOF'
#!/bin/sh
set -eu
project_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
app_dir="$project_dir/.build/app/${PREVIEW_TEST_APP_BUNDLE_NAME:-2M2Better.app}"
executable="$app_dir/Contents/MacOS/${PREVIEW_TEST_APP_EXECUTABLE_NAME:-BreakCompanion}"
if [ -z "${PREVIEW_TEST_BUILD_PRODUCES_NOTHING:-}" ]; then
    mkdir -p "$app_dir/Contents/MacOS"
    printf '#!/bin/sh\nexit 0\n' > "$executable"
    chmod +x "$executable"
fi
printf '%s\n' "$app_dir"
EOF
chmod +x "$stub_repo/build-app.sh"

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

for empty_option in --repo --ref --destination; do
    if output=$(run_installer --dry-run "$empty_option" "" --destination "$test_root/empty-value" 2>&1); then
        fail_test "empty $empty_option value unexpectedly succeeded"
    fi
    assert_contains "$output" "$empty_option requires a non-empty"
done
[ ! -e "$test_root/home/2m2good-developer-preview" ] || \
    fail_test 'an empty --destination fell back to the home default'
[ ! -e "$test_root/empty-value" ] || fail_test 'an empty option value created a destination'

if output=$(run_installer --dry-run --repo "file:///tmp/repository" 2>&1); then
    fail_test 'non-HTTPS repository unexpectedly succeeded'
fi
assert_contains "$output" 'repository must be an HTTPS URL'

if output=$(run_installer --dry-run --ref 'feature with spaces' --destination "$test_root/bad-ref" 2>&1); then
    fail_test 'invalid ref unexpectedly succeeded'
fi
assert_contains "$output" 'ref must be a non-empty branch'

hex_tag_output=$(run_installer --dry-run --ref 20250823 --destination "$test_root/hex-tag" 2>&1) || \
    fail_test "hex-shaped branch/tag ref was rejected: $hex_tag_output"
assert_contains "$hex_tag_output" '20250823'
assert_contains "$hex_tag_output" 'Dry run complete'
[ ! -e "$test_root/hex-tag" ] || fail_test 'hex-shaped ref dry run created a destination'

full_sha=d0ee7e5574877a042f83bf480c51db083d5eb32e
sha_output=$(run_installer --dry-run --ref "$full_sha" --destination "$test_root/full-sha" 2>&1) || \
    fail_test "full-SHA ref was rejected: $sha_output"
assert_contains "$sha_output" "$full_sha"
assert_contains "$sha_output" 'Dry run complete'
[ ! -e "$test_root/full-sha" ] || fail_test 'full-SHA dry run created a destination'

# The fake git refuses to clone, so these exercise the post-destination
# checkout-failure path without any network access or real checkout.
if output=$(run_installer --confirm --no-launch --ref beef1234 --destination "$test_root/abbrev-clone" 2>&1); then
    fail_test 'refused clone unexpectedly succeeded'
fi
assert_contains "$output" "source checkout for ref 'beef1234' failed"
assert_contains "$output" 'Git reported the cause above'
assert_contains "$output" "If 'beef1234' was meant as a commit SHA"
assert_lacks "$output" 'is not a branch or tag on this remote'
[ ! -e "$test_root/abbrev-clone" ] || fail_test 'empty destination survived a failed checkout'

if output=$(run_installer --confirm --no-launch --ref main --destination "$test_root/branch-clone" 2>&1); then
    fail_test 'refused branch clone unexpectedly succeeded'
fi
assert_contains "$output" "source checkout for ref 'main' failed"
assert_lacks "$output" 'was meant as a commit SHA'
[ ! -e "$test_root/branch-clone" ] || fail_test 'empty destination survived a failed branch checkout'

partial="$test_root/partial-clone"
if output=$(PREVIEW_TEST_GIT_PARTIAL_CLONE=1 run_installer --confirm --no-launch --destination "$partial" 2>&1); then
    fail_test 'partial clone unexpectedly succeeded'
fi
assert_contains "$output" 'left intact for inspection'
[ "$(cat "$partial/partial-marker.txt")" = 'partial checkout' ] || \
    fail_test 'partial checkout was not preserved'

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

# The stub checkout lets these exercise everything after the clone: the
# installer must take the app bundle path from the build script's own output,
# whatever that bundle is named.
built="$test_root/built-preview"
output=$(PREVIEW_TEST_GIT_STUB_REPO="$test_root/stub-repo" \
    run_installer --confirm --no-launch --destination "$built" 2>&1) || \
    fail_test "post-build run failed: $output"
assert_contains "$output" "$built/.build/app/2M2Better.app"
assert_contains "$output" 'Built without launching'
[ -x "$built/.build/app/2M2Better.app/Contents/MacOS/BreakCompanion" ] || \
    fail_test 'stub build did not leave its app bundle in place'

renamed="$test_root/renamed-preview"
open_log="$test_root/open-log.txt"
output=$(PREVIEW_TEST_GIT_STUB_REPO="$test_root/stub-repo" \
    PREVIEW_TEST_APP_BUNDLE_NAME=2m2better.app \
    PREVIEW_TEST_OPEN_LOG="$open_log" \
    run_installer --confirm --destination "$renamed" 2>&1) || \
    fail_test "post-build run with a renamed bundle failed: $output"
assert_contains "$output" "$renamed/.build/app/2m2better.app"
[ "$(cat "$open_log")" = "$renamed/.build/app/2m2better.app" ] || \
    fail_test "installer launched the wrong path: $(cat "$open_log")"

renamed_executable="$test_root/renamed-executable-preview"
output=$(PREVIEW_TEST_GIT_STUB_REPO="$test_root/stub-repo" \
    PREVIEW_TEST_APP_BUNDLE_NAME=2m2better.app \
    PREVIEW_TEST_APP_EXECUTABLE_NAME=2m2better \
    run_installer --confirm --no-launch --destination "$renamed_executable" 2>&1) || \
    fail_test "post-build run with a renamed product executable failed: $output"
assert_contains "$output" "$renamed_executable/.build/app/2m2better.app"

# The full-SHA path must fetch only the requested commit, never clone a default
# branch first.
revision="$test_root/revision-preview"
git_log="$test_root/git-log.txt"
output=$(PREVIEW_TEST_GIT_STUB_REPO="$test_root/stub-repo" \
    PREVIEW_TEST_GIT_LOG="$git_log" \
    run_installer --confirm --no-launch --ref "$full_sha" --destination "$revision" 2>&1) || \
    fail_test "full-SHA post-build run failed: $output"
assert_contains "$output" "$revision/.build/app/2M2Better.app"
assert_contains "$(cat "$git_log")" "fetch --depth 1 origin $full_sha"
assert_lacks "$(cat "$git_log")" 'clone'

missing="$test_root/missing-bundle-preview"
if output=$(PREVIEW_TEST_GIT_STUB_REPO="$test_root/stub-repo" \
    PREVIEW_TEST_BUILD_PRODUCES_NOTHING=1 \
    run_installer --confirm --no-launch --destination "$missing" 2>&1); then
    fail_test 'a build that produced no app bundle unexpectedly succeeded'
fi
assert_contains "$output" 'build did not produce the expected app'
[ -d "$missing" ] || fail_test 'a failed build removed its checkout'

printf '%s\n' 'installer tests: PASS (safe dry-run, post-build, and failure harness)'
