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

# Sign with a stable identity (Apple Development / Developer ID) so macOS keeps
# permission grants (Accessibility, etc.) across rebuilds. Falls back to ad-hoc.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development|Developer ID/{print $2; exit}')
if [ -n "$IDENTITY" ]; then
  echo "▸ Signing with identity $IDENTITY"
  codesign --force --deep --sign "$IDENTITY" "$APP"
else
  echo "▸ Ad-hoc signing (no stable identity found)"
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

echo "✓ Built $(pwd)/$APP"
echo "  Run it with:  open $APP"
