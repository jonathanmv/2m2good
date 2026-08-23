#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
build_dir="$project_dir/.build/app"
app_dir="$build_dir/2M2Better.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
module_cache="$project_dir/.build/manual-module-cache"
sdk_path="${BREAK_SDK_PATH:-$(xcrun --show-sdk-path)}"
architecture="$(uname -m)"

mkdir -p "$macos_dir" "$module_cache"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"

xcrun swiftc \
    -sdk "$sdk_path" \
    -module-cache-path "$module_cache" \
    -target "$architecture-apple-macosx14.0" \
    -swift-version 5 \
    -parse-as-library \
    "$project_dir"/Sources/BreakCompanion/*.swift \
    -o "$macos_dir/BreakCompanion" \
    -framework AppKit \
    -framework AVFoundation \
    -framework CoreGraphics \
    -framework Speech

codesign --force --sign - "$app_dir" >/dev/null
echo "$app_dir"
