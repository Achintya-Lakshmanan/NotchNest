#!/bin/bash
# Builds NotchNest.app (a release-mode .app bundle you can double-click / move to /Applications).
set -e
cd "$(dirname "$0")"

echo "▸ Building release…"
swift build -c release

APP="NotchNest.app"
BIN=".build/release/NotchNest"

echo "▸ Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchNest"
cp Info.plist "$APP/Contents/Info.plist"

# Ad-hoc sign so macOS keeps a stable identity for permission grants.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✓ Built $(pwd)/$APP"
echo "  Run it with:  open $APP"
