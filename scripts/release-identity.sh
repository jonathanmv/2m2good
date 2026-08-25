#!/bin/sh
# Read the release identity from the Swift declaration used by the app.
# ProductIdentity.currentVersion is the only semantic-version source of truth.
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
project_dir=$(CDPATH= cd "$script_dir/.." && pwd)
source_file="$project_dir/Sources/BreakCompanion/ProductIdentity.swift"

fail() {
    printf 'release identity: ERROR: %s\n' "$1" >&2
    exit 1
}

[ -f "$source_file" ] || fail "missing release identity source: $source_file"
version_line=$(grep -E '^    static let currentVersion = SemanticVersion\(major:' "$source_file" || true)
[ "$(printf '%s\n' "$version_line" | grep -c .)" -eq 1 ] || \
    fail "expected exactly one ProductIdentity.currentVersion declaration"

version=$(printf '%s\n' "$version_line" | sed -E 's/.*major: ([0-9]+), minor: ([0-9]+), patch: ([0-9]+).*/\1.\2.\3/')
case "$version" in
    ''|*[!0-9.]*|.*|*.|*..*) fail "could not parse semantic version from ProductIdentity.swift" ;;
esac

build_line=$(grep -E '^    static let buildNumber = ' "$source_file" || true)
[ "$(printf '%s\n' "$build_line" | grep -c .)" -eq 1 ] || \
    fail "expected exactly one ProductIdentity.buildNumber declaration"
build_number=$(printf '%s\n' "$build_line" | sed -E 's/.*= "([^"]+)".*/\1/')
[ -n "$build_number" ] || fail "could not parse build number from ProductIdentity.swift"

case "${1:---version}" in
    --version) printf '%s\n' "$version" ;;
    --build-number) printf '%s\n' "$build_number" ;;
    --check)
        printf 'Release identity: %s (build %s)\n' "$version" "$build_number"
        ;;
    *) fail "usage: release-identity.sh [--version|--build-number|--check]" ;;
esac
