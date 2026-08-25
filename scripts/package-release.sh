#!/bin/zsh
# Build and package the exact GitHub Releases asset contract used by the updater.
# The app is ad-hoc signed by the existing local build path; this script adds a
# SHA-256 manifest and never claims Developer ID signing or notarization.
set -euo pipefail

project_dir="${0:A:h:h}"
output_dir="$project_dir/.build/releases"
run_build=1

usage() {
    cat <<'EOF'
Package a 2m2better macOS GitHub Release asset.

Usage:
  scripts/package-release.sh [--output-dir DIR] [--skip-build]
  scripts/package-release.sh --dry-run

The output is a ZIP containing the app bundle and a matching .sha256 file.
The updater accepts only these exact names and verifies the checksum before it
shows an update. No update is installed automatically.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output-dir)
            [ "$#" -ge 2 ] || { printf 'package release: --output-dir requires a path\n' >&2; exit 2; }
            output_dir="$2"
            shift 2
            ;;
        --skip-build)
            run_build=0
            shift
            ;;
        --dry-run)
            run_build=2
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'package release: unknown option %s\n' "$1" >&2
            exit 2
            ;;
    esac
done

version="$("$project_dir/scripts/release-identity.sh" --version)"
build_number="$("$project_dir/scripts/release-identity.sh" --build-number)"
architecture="$(uname -m)"
case "$architecture" in
    arm64|x86_64) ;;
    *) printf 'package release: unsupported architecture %s\n' "$architecture" >&2; exit 1 ;;
esac
# The asset prefix follows the established app bundle brand; the version comes
# only from ProductIdentity.currentVersion via release-identity.sh.
artifact_name="2m2better-v${version}-macos-${architecture}.zip"
checksum_name="${artifact_name}.sha256"

printf 'Release identity: %s (build %s)\n' "$version" "$build_number"
printf 'GitHub asset:     %s\n' "$artifact_name"
printf 'Checksum asset:   %s\n' "$checksum_name"
printf 'Output directory:  %s\n' "$output_dir"

if [ "$run_build" -eq 2 ]; then
    printf '%s\n' 'Dry run complete: no build, self-check, or files were written.'
    exit 0
fi

app_path="$project_dir/.build/app/2m2better.app"
if [ "$run_build" -eq 1 ]; then
    build_output="$($project_dir/scripts/build-app.sh)"
    app_path="$(printf '%s\n' "$build_output" | tail -n 1)"
    printf '%s\n' "$build_output" >&2
fi

[ -d "$app_path" ] || { printf 'package release: app bundle not found: %s\n' "$app_path" >&2; exit 1; }
plist="$app_path/Contents/Info.plist"
executable="$app_path/Contents/MacOS/BreakCompanion"
[ -f "$plist" ] || { printf 'package release: Info.plist missing from %s\n' "$app_path" >&2; exit 1; }
[ -x "$executable" ] || { printf 'package release: app executable missing from %s\n' "$app_path" >&2; exit 1; }

plist_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
plist_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
[ "$plist_version" = "$version" ] || { printf 'package release: plist version %s does not match source version %s\n' "$plist_version" "$version" >&2; exit 1; }
[ "$plist_build" = "$build_number" ] || { printf 'package release: plist build %s does not match source build %s\n' "$plist_build" "$build_number" >&2; exit 1; }

codesign --verify --deep --strict "$app_path" >/dev/null
printf '%s\n' 'Running packaged self-check...'
"$executable" --self-check

mkdir -p "$output_dir"
archive="$output_dir/$artifact_name"
checksum="$output_dir/$checksum_name"
rm -f "$archive" "$checksum"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive"
( cd "$output_dir" && shasum -a 256 "$artifact_name" > "$checksum_name" )

printf 'Packaged artifact: %s\n' "$archive"
printf 'Checksum manifest: %s\n' "$checksum"
printf '%s\n' 'Upload both files to the same GitHub Release; the updater refuses any other asset name or an invalid checksum.'
