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
if [ -f AppIcon.icns ]; then
  cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Sign with a stable identity (Apple Development / Developer ID) so macOS keeps
# permission grants (Accessibility, etc.) across rebuilds. Falls back to ad-hoc.
SIGN_OPTIONS=(--force --deep)
if [ -n "${NOTCHNEST_PROVISIONING_PROFILE:-}" ]; then
  cp "$NOTCHNEST_PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
  SIGN_OPTIONS+=(--entitlements NotchNest.entitlements)
else
  echo "Focus connection disabled: no provisioning profile supplied."
fi
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development|Developer ID/{print $2; exit}')
if [ -n "$IDENTITY" ]; then
  echo "▸ Signing with identity $IDENTITY"
  codesign "${SIGN_OPTIONS[@]}" --sign "$IDENTITY" "$APP"
else
  echo "▸ Ad-hoc signing (no stable identity found)"
  codesign "${SIGN_OPTIONS[@]}" --sign - "$APP" 2>/dev/null || true
fi

echo "✓ Built $(pwd)/$APP"
echo "  Run it with:  open $APP"
