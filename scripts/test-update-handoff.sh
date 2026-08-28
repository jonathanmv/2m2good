#!/bin/sh
# Executable-interface tests for the in-app update handoff. The fixture invokes
# the real helper with a real macOS ZIP, process wait, staging, rollback, and
# relaunch path; it does not inspect helper source text.
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
helper_source="$script_dir/../Resources/update-handoff.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/2m2better-update-handoff-test.XXXXXX")
cleanup() { rm -rf "$test_root"; }
trap cleanup EXIT HUP INT TERM

fail_test() {
    printf 'update handoff tests: FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    haystack=$1
    needle=$2
    printf '%s\n' "$haystack" | grep -Fq -e "$needle" || fail_test "expected output to contain: $needle"
}

make_fixture() {
    fixture_root=$1
    fixture_app="$fixture_root/2m2better.app"
    mkdir -p "$fixture_app/Contents/MacOS" "$fixture_app/Contents/Resources"
    cat > "$fixture_app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIconFile</key><string>2m2better.png</string>
<key>CFBundleExecutable</key><string>BreakCompanion</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
EOF
    printf '#!/bin/sh\nprintf new-app\n' > "$fixture_app/Contents/MacOS/BreakCompanion"
    chmod +x "$fixture_app/Contents/MacOS/BreakCompanion"
    cp "$script_dir/../Resources/2m2better.png" "$fixture_app/Contents/Resources/2m2better.png"
    ditto -c -k --sequesterRsrc --keepParent "$fixture_app" "$fixture_root/update.zip"
    shasum -a 256 "$fixture_root/update.zip" | awk '{print $1}'
}

make_fake_open() {
    fake_bin=$1
    cat > "$fake_bin/open" <<'EOF'
#!/bin/sh
printf '%s\n' "${1:-}" >> "$UPDATE_HANDOFF_OPEN_LOG"
exit 0
EOF
    chmod +x "$fake_bin/open"
}

# A normal handoff waits for the old process, retains the old app for rollback,
# preserves a preference outside the bundle, and asks macOS to relaunch the new
# app. The helper's second checksum check protects the handoff window too.
success_root="$test_root/success"
success_home="$success_root/home"
mkdir -p "$success_home/Applications" "$success_home/Library/Preferences" "$success_home/Library/Application Support/2m2better" "$success_root/fake-bin"
printf '%s\n' 'keep user preference' > "$success_home/Library/Preferences/local.break-companion.pilot.plist"
printf '%s\n' 'keep timer and session state' > "$success_home/Library/Application Support/2m2better/companion-state.json"
success_digest=$(make_fixture "$success_root")
success_download_dir="$success_root/2m2better-update-test-uuid"
mkdir "$success_download_dir"
mv "$success_root/update.zip" "$success_download_dir/update.zip"
mkdir -p "$success_home/Applications/2m2better.app"
printf '%s\n' 'old app' > "$success_home/Applications/2m2better.app/marker"
mkdir "$success_root/handoff-directory"
cp "$helper_source" "$success_root/handoff-directory/update-handoff.sh"
chmod 700 "$success_root/handoff-directory/update-handoff.sh"
make_fake_open "$success_root/fake-bin"
(sleep 1) & old_pid=$!
success_output=$(HOME="$success_home" TMPDIR="$success_root" \
    PATH="$success_root/fake-bin:/usr/bin:/bin" \
    UPDATE_HANDOFF_OPEN_LOG="$success_root/open.log" \
    "$success_root/handoff-directory/update-handoff.sh" --archive "$success_download_dir/update.zip" \
    --pid "$old_pid" --sha256 "$success_digest" 2>&1) || \
    fail_test "successful handoff failed: $success_output"
assert_contains "$success_output" '2m2better update handoff completed.'
[ -x "$success_home/Applications/2m2better.app/Contents/MacOS/BreakCompanion" ] || fail_test 'new app was not installed'
[ "$("$success_home/Applications/2m2better.app/Contents/MacOS/BreakCompanion")" = 'new-app' ] || fail_test 'new app executable did not run'
[ "$(cat "$success_home/Library/Preferences/local.break-companion.pilot.plist")" = 'keep user preference' ] || fail_test 'user preferences changed'
[ "$(cat "$success_home/Library/Application Support/2m2better/companion-state.json")" = 'keep timer and session state' ] || fail_test 'timer/session state changed'
[ "$(cat "$success_root/open.log")" = "$success_home/Applications/2m2better.app" ] || fail_test 'new app was not relaunched'
backup_count=0
backup_marker=
for backup in "$success_home/Applications"/.2m2better.app.previous.*.app; do
    if [ -d "$backup" ]; then
        backup_count=$((backup_count + 1))
        backup_marker="$backup/marker"
    fi
done
[ "$backup_count" -eq 1 ] || fail_test 'rollback app was not retained'
[ "$(cat "$backup_marker")" = 'old app' ] || fail_test 'rollback app contents were not retained'
[ -z "$(find "$success_home/Applications" -maxdepth 1 -name '.2m2better-update.*' -print)" ] || fail_test 'temporary staging directory remained'
[ ! -d "$success_root/handoff-directory" ] || fail_test 'temporary handoff directory remained'
[ ! -d "$success_download_dir" ] || fail_test 'downloaded update temporary directory remained'
report="$success_home/Library/Logs/2m2better/update.log"
assert_contains "$(cat "$report")" 'Preferences were not changed'

# A final-rename failure restores the old app and leaves a report rather than
# exposing a half-installed bundle. The fake mv fails only for the new bundle's
# final destination; every rollback move uses the real command.
failure_root="$test_root/failure"
failure_home="$failure_root/home"
mkdir -p "$failure_home/Applications/2m2better.app" "$failure_root/fake-bin"
printf '%s\n' 'old app' > "$failure_home/Applications/2m2better.app/marker"
failure_digest=$(make_fixture "$failure_root")
mkdir "$failure_root/handoff-directory"
cp "$helper_source" "$failure_root/handoff-directory/update-handoff.sh"
chmod 700 "$failure_root/handoff-directory/update-handoff.sh"
make_fake_open "$failure_root/fake-bin"
cat > "$failure_root/fake-bin/mv" <<EOF
#!/bin/sh
if [ "\${2:-}" = "$failure_home/Applications/2m2better.app" ]; then
    case "\${1:-}" in
        *'.2m2better-update.'*/2m2better.app) exit 1 ;;
    esac
fi
exec /bin/mv "\$@"
EOF
chmod +x "$failure_root/fake-bin/mv"
(sleep 1) & failure_pid=$!
if failure_output=$(HOME="$failure_home" TMPDIR="$failure_root" \
    PATH="$failure_root/fake-bin:/usr/bin:/bin" \
    UPDATE_HANDOFF_OPEN_LOG="$failure_root/open.log" \
    "$failure_root/handoff-directory/update-handoff.sh" --archive "$failure_root/update.zip" \
    --pid "$failure_pid" --sha256 "$failure_digest" 2>&1); then
    fail_test 'final rename failure unexpectedly succeeded'
fi
assert_contains "$failure_output" 'the previous app was restored and retained at'
[ "$(cat "$failure_home/Applications/2m2better.app/marker")" = 'old app' ] || fail_test 'old app was not restored after failed rename'
failure_backup_count=0
for backup in "$failure_home/Applications"/.2m2better.app.previous.*.app; do
    if [ -d "$backup" ]; then
        failure_backup_count=$((failure_backup_count + 1))
        [ "$(cat "$backup/marker")" = 'old app' ] || fail_test 'rollback copy changed after restoration'
    fi
done
[ "$failure_backup_count" -eq 1 ] || fail_test 'rollback path was not retained after restoration'
failure_report="$failure_home/Library/Logs/2m2better/update.log"
assert_contains "$(cat "$failure_report")" 'The running app was not replaced, or the previous app was restored.'
[ "$(cat "$failure_root/open.log")" = "$failure_report" ] || fail_test 'failure report was not opened'

# A changed archive is rejected after the process wait, before extraction or
# touching the destination.
tamper_root="$test_root/tamper"
tamper_home="$tamper_root/home"
mkdir -p "$tamper_home/Applications/2m2better.app" "$tamper_root/fake-bin"
printf '%s\n' 'old app' > "$tamper_home/Applications/2m2better.app/marker"
tamper_digest=$(make_fixture "$tamper_root")
mkdir "$tamper_root/handoff-directory"
cp "$helper_source" "$tamper_root/handoff-directory/update-handoff.sh"
chmod 700 "$tamper_root/handoff-directory/update-handoff.sh"
make_fake_open "$tamper_root/fake-bin"
(sleep 1) & tamper_pid=$!
printf '%s\n' 'tampered' >> "$tamper_root/update.zip"
if tamper_output=$(HOME="$tamper_home" TMPDIR="$tamper_root" \
    PATH="$tamper_root/fake-bin:/usr/bin:/bin" \
    UPDATE_HANDOFF_OPEN_LOG="$tamper_root/open.log" \
    "$tamper_root/handoff-directory/update-handoff.sh" --archive "$tamper_root/update.zip" \
    --pid "$tamper_pid" --sha256 "$tamper_digest" 2>&1); then
    fail_test 'changed archive unexpectedly succeeded'
fi
assert_contains "$tamper_output" 'changed after checksum verification'
[ "$(cat "$tamper_home/Applications/2m2better.app/marker")" = 'old app' ] || fail_test 'tamper failure changed old app'

printf '%s\n' 'update handoff tests: PASS (wait, verified replacement, preferences, relaunch, rollback, tamper failure, and cleanup)'
