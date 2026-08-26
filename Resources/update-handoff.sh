#!/bin/sh
# Finish an explicitly confirmed, checksum-verified in-app update after the
# running process exits. This helper intentionally has one destination: the
# invoking user's ~/Applications/2m2better.app.
set -eu

SCRIPT_NAME="2m2better updater"
HANDOFF_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work_dir=
staging_root=
archive=
pid=
expected_sha256=

cleanup() {
    if [ -n "${staging_root:-}" ] && [ -d "$staging_root" ]; then
        rm -rf "$staging_root"
    fi
    if [ -n "${work_dir:-}" ] && [ -d "$work_dir" ]; then
        rm -rf "$work_dir"
    fi
    if [ -d "$HANDOFF_DIRECTORY" ]; then
        rm -rf "$HANDOFF_DIRECTORY"
    fi
}
trap cleanup EXIT HUP INT TERM

fail_update() {
    message=$1
    if [ -n "${report:-}" ]; then
        report_directory=${report%/*}
        report_temp="$report.$$"
        if mkdir -p "$report_directory" 2>/dev/null; then
            {
                printf '%s\n' '2m2better update handoff failed.'
                printf 'Reason: %s\n' "$message"
                printf '%s\n' 'The running app was not replaced, or the previous app was restored.'
                printf 'Next action: review this report at %s and try Check for Updates… again.\n' "$report"
            } > "$report_temp" 2>/dev/null && mv "$report_temp" "$report" 2>/dev/null || rm -f "$report_temp"
        fi
        if command -v open >/dev/null 2>&1; then
            open "$report" >/dev/null 2>&1 || true
        fi
    fi
    printf '%s: ERROR: %s\n' "$SCRIPT_NAME" "$message" >&2
    exit 1
}

[ -n "${HOME:-}" ] || { printf '%s: ERROR: HOME is not set.\n' "$SCRIPT_NAME" >&2; exit 1; }
case "$HOME" in
    /*) ;;
    *) printf '%s: ERROR: HOME must be an absolute path.\n' "$SCRIPT_NAME" >&2; exit 1 ;;
esac

report="$HOME/Library/Logs/2m2better/update.log"
install_root="$HOME/Applications"
installed_app="$install_root/2m2better.app"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --archive)
            [ "$#" -ge 2 ] || fail_update '--archive requires the verified ZIP path.'
            archive=$2
            shift 2
            ;;
        --pid)
            [ "$#" -ge 2 ] || fail_update '--pid requires the running app process ID.'
            pid=$2
            shift 2
            ;;
        --sha256)
            [ "$#" -ge 2 ] || fail_update '--sha256 requires the verified artifact digest.'
            expected_sha256=$2
            shift 2
            ;;
        *)
            fail_update "unknown handoff option '$1'."
            ;;
    esac
done

case "$archive" in
    /*) ;;
    *) fail_update 'the verified ZIP path must be absolute.' ;;
esac
case "$pid" in
    ''|*[!0-9]*) fail_update 'the running app process ID was invalid.' ;;
esac
[ "$pid" -gt 0 ] || fail_update 'the running app process ID was invalid.'
printf '%s\n' "$expected_sha256" | grep -Eq '^[0-9A-Fa-f]{64}$' || \
    fail_update 'the verified artifact digest was invalid.'

# Do not race the running application. kill -0 only observes the process; it
# never sends a signal or asks for credentials. The timeout makes a vanished
# helper or an unexpected process lifecycle observable instead of hanging.
waited=0
while kill -0 "$pid" 2>/dev/null; do
    [ "$waited" -lt 300 ] || fail_update 'the running app did not exit within five minutes; nothing was changed.'
    sleep 1
    waited=$((waited + 1))
done

[ -f "$archive" ] || fail_update 'the verified ZIP is no longer available; nothing was changed.'
[ ! -L "$archive" ] || fail_update 'the verified ZIP became a symlink; nothing was changed.'
actual_sha256=$(shasum -a 256 "$archive" 2>/dev/null | awk '{print tolower($1)}') || \
    fail_update 'the verified ZIP could not be hashed; nothing was changed.'
[ "$actual_sha256" = "$(printf '%s' "$expected_sha256" | tr '[:upper:]' '[:lower:]')" ] || \
    fail_update 'the verified ZIP changed after checksum verification; nothing was changed.'

if [ -e "$install_root" ] || [ -L "$install_root" ]; then
    [ -d "$install_root" ] || fail_update "the installation directory is not a directory: $install_root"
    [ ! -L "$install_root" ] || fail_update "the installation directory is a symlink: $install_root"
else
    mkdir "$install_root" || fail_update "could not create $install_root without sudo"
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/2m2better-update-handoff.XXXXXX") || \
    fail_update 'could not create a temporary update directory.'
extracted_dir="$work_dir/extracted"
mkdir "$extracted_dir"
if ! ditto -x -k "$archive" "$extracted_dir"; then
    fail_update 'the verified ZIP could not be extracted; nothing was changed.'
fi
extracted_app="$extracted_dir/2m2better.app"
[ ! -L "$extracted_app" ] || fail_update 'the verified ZIP contained a symlink instead of the app bundle.'
[ -d "$extracted_app" ] || fail_update 'the verified ZIP did not contain 2m2better.app.'
[ ! -L "$extracted_app/Contents" ] || fail_update 'the app bundle Contents directory was a symlink.'
[ -d "$extracted_app/Contents" ] || fail_update 'the app bundle Contents directory is missing.'
plist="$extracted_app/Contents/Info.plist"
executable="$extracted_app/Contents/MacOS/BreakCompanion"
icon="$extracted_app/Contents/Resources/2m2better.png"
[ ! -L "$plist" ] && [ -f "$plist" ] || fail_update 'the app bundle Info.plist is missing or symlinked.'
[ ! -L "$executable" ] && [ -x "$executable" ] || fail_update 'the app bundle executable is missing or symlinked.'
[ ! -L "$icon" ] && [ -f "$icon" ] || fail_update 'the app bundle icon is missing or symlinked.'
icon_name=$(plutil -extract CFBundleIconFile raw -o - "$plist" 2>/dev/null) || \
    fail_update 'the app bundle has no usable icon declaration.'
[ "$icon_name" = '2m2better.png' ] || fail_update 'the app bundle icon declaration did not match its bundled icon.'

# Stage and rename only the app bundle. If the final rename fails, restore the
# old bundle from its retained rollback path. Preferences live outside this
# bundle and are not copied, deleted, or otherwise touched.
staging_root=$(mktemp -d "$install_root/.2m2better-update.XXXXXX") || \
    fail_update "could not create a staging directory in $install_root."
staged_app="$staging_root/2m2better.app"
mv "$extracted_app" "$staged_app" || fail_update 'could not stage the verified app bundle.'

backup=
if [ -e "$installed_app" ] || [ -L "$installed_app" ]; then
    [ ! -L "$installed_app" ] || fail_update "the existing app is a symlink: $installed_app"
    [ -d "$installed_app" ] || fail_update "the existing app is not a bundle directory: $installed_app"
    backup="$install_root/.2m2better.app.previous.$$.app"
    backup_number=0
    while [ -e "$backup" ] || [ -L "$backup" ]; do
        backup_number=$((backup_number + 1))
        backup="$install_root/.2m2better.app.previous.$$.${backup_number}.app"
    done
    mv "$installed_app" "$backup" || fail_update "could not move the existing app to its rollback path: $backup"
    if ! mv "$staged_app" "$installed_app"; then
        if mv "$backup" "$installed_app"; then
            # Keep the restored app usable at its original path and retain a
            # copy of it as an observable rollback artifact for inspection.
            if ditto "$installed_app" "$backup" 2>/dev/null; then
                fail_update "could not install the verified app; the previous app was restored and retained at $backup."
            fi
            fail_update 'could not install the verified app; the previous app was restored, but its rollback copy could not be retained.'
        fi
        fail_update "could not install the verified app and could not restore the previous app; the previous app remains at $backup."
    fi
else
    mv "$staged_app" "$installed_app" || fail_update 'could not install the verified app; nothing was replaced.'
fi

launch_status='macOS was asked to relaunch 2m2better.'
if ! command -v open >/dev/null 2>&1 || ! open "$installed_app" >/dev/null 2>&1; then
    launch_status="Relaunch could not be requested; run open \"$installed_app\" manually."
fi

report_directory=${report%/*}
mkdir -p "$report_directory" 2>/dev/null || true
report_temp="$report.$$"
{
    printf '%s\n' '2m2better update handoff completed.'
    printf 'Installed app: %s\n' "$installed_app"
    if [ -n "$backup" ]; then
        printf 'Rollback app retained: %s\n' "$backup"
    else
        printf '%s\n' 'Rollback app: none (there was no existing app bundle).'
    fi
    printf '%s\n' 'Preferences were not changed; only the app bundle was replaced.'
    printf 'Trust limitation: the package remains an ad-hoc developer preview; macOS security was not bypassed.\n'
    printf 'Next action: %s\n' "$launch_status"
} > "$report_temp" 2>/dev/null && mv "$report_temp" "$report" 2>/dev/null || rm -f "$report_temp"

printf '%s\n' '2m2better update handoff completed.'
