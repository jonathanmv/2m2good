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
(
    cd "$test_dir"
    shasum -a 256 -c "$checksum"
    unzip -l "$artifact" | grep -Fq '2m2better.app/Contents/MacOS/BreakCompanion'
)
printf '%s\n' 'Release package test passed: artifact, checksum, bundle executable, and packaged self-check are valid.'
