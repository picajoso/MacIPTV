#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build -c release --disable-sandbox
bin_dir="$(swift build -c release --show-bin-path --disable-sandbox)"
app="$PWD/dist/MacIPTV.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/MacIPTV" "$app/Contents/MacOS/MacIPTV"
cp scripts/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$PWD/.build/MacIPTV.iconset"
iconutil -c icns "$PWD/.build/MacIPTV.iconset" -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$PWD/dist/MacIPTV.zip"
echo "Creada: $app"
