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
version_line=$(grep -E '^    static let currentVersion = SemanticVersion\(tag: "[^"]+"\)!$' "$source_file" || true)
[ "$(printf '%s\n' "$version_line" | grep -c .)" -eq 1 ] || \
    fail "expected exactly one ProductIdentity.currentVersion declaration"

version=$(printf '%s\n' "$version_line" | sed -E 's/.*tag: "([^"]+)".*/\1/')
if ! printf '%s\n' "$version" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*)|([0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))(\.((0|[1-9][0-9]*)|([0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)))*)?(\+([0-9A-Za-z-]+)(\.[0-9A-Za-z-]+)*)?$'; then
    fail "could not parse semantic version from ProductIdentity.swift"
fi

max_core_value=9223372036854775807
max_core_digits=${#max_core_value}
validate_core_component() {
    component=$1
    component_digits=${#component}
    [ "$component_digits" -lt "$max_core_digits" ] && return 0
    [ "$component_digits" -gt "$max_core_digits" ] && return 1
    LC_ALL=C test "$component" \< "$max_core_value"
}

core=${version%%[-+]*}
core_major=${core%%.*}
core_rest=${core#*.}
core_minor=${core_rest%%.*}
core_patch=${core_rest#*.}
for component in "$core_major" "$core_minor" "$core_patch"; do
    validate_core_component "$component" || fail "semantic-version core number exceeds supported range"
done

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
