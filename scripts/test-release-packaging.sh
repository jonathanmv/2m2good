#!/bin/sh
# Build, validate, and exercise the GitHub Release package contract locally.
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
project_dir=$(CDPATH= cd "$script_dir/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/2m2good-release-test.XXXXXX")
cleanup() { rm -rf "$test_dir"; }
trap cleanup EXIT HUP INT TERM

"$project_dir/scripts/build-app.sh" >/dev/null
"$project_dir/scripts/package-release.sh" --skip-build --output-dir "$test_dir" >/dev/null

version=$("$project_dir/scripts/release-identity.sh" --version)
architecture=$(uname -m)
artifact="2m2better-v${version}-macos-${architecture}.zip"
checksum="${artifact}.sha256"
[ -f "$test_dir/$artifact" ] || { printf 'release package test: artifact missing\n' >&2; exit 1; }
[ -f "$test_dir/$checksum" ] || { printf 'release package test: checksum missing\n' >&2; exit 1; }
unpacked="$test_dir/unpacked"
mkdir "$unpacked"
(
    cd "$test_dir"
    shasum -a 256 -c "$checksum"
    unzip -q "$artifact" -d "$unpacked"
)
packaged_app="$unpacked/2m2better.app"
packaged_plist="$packaged_app/Contents/Info.plist"
packaged_icon="$packaged_app/Contents/Resources/2m2better.png"
packaged_helper="$packaged_app/Contents/Resources/update-handoff.sh"
[ -x "$packaged_app/Contents/MacOS/BreakCompanion" ] || { printf 'release package test: bundle executable missing\n' >&2; exit 1; }
[ -x "$packaged_helper" ] || { printf 'release package test: bundled update helper missing\n' >&2; exit 1; }
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$packaged_plist")" = '2m2better.png' ] || {
    printf 'release package test: generated icon key is missing or incorrect\n' >&2
    exit 1
}
[ -f "$packaged_icon" ] || { printf 'release package test: bundled app icon missing\n' >&2; exit 1; }
sips -g pixelWidth -g pixelHeight "$packaged_icon" | grep -Fq 'pixelWidth: 512'
sips -g pixelWidth -g pixelHeight "$packaged_icon" | grep -Fq 'pixelHeight: 512'

# Register the packaged bundle with the same LaunchServices consumer Finder
# uses, then assert the registered record contains this bundle's icon key.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [ -x "$lsregister" ]; then
    registered_path=$(realpath "$packaged_app")
    "$lsregister" -f "$registered_path" >/dev/null 2>&1
    launch_services_dump=$("$lsregister" -dump 2>/dev/null)
    printf '%s\n' "$launch_services_dump" | awk -v path="$registered_path" '
        /^-+$/ {
            if (found && icon) matched = 1
            found = 0
            icon = 0
        }
        index($0, "path:                       " path " ") { found = 1 }
        found && index($0, "CFBundleIconFile = \"2m2better.png\"") { icon = 1 }
        END {
            if (found && icon) matched = 1
            exit matched ? 0 : 1
        }
    ' || {
        "$lsregister" -u "$registered_path" >/dev/null 2>&1 || true
        printf 'release package test: LaunchServices did not register the packaged icon\n' >&2
        exit 1
    }
    "$lsregister" -u "$registered_path" >/dev/null 2>&1 || true
fi
printf '%s\n' 'Release package test passed: artifact, checksum, bundle executable, icon resource, LaunchServices registration, and packaged self-check are valid.'
