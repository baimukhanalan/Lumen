#!/bin/bash
#
# Build Lumen.app (via build.sh) and package it into a distributable .dmg.
# Works locally and in CI (macOS runner). Output: dist/Lumen-<version>.dmg
#
# Signing/notarization is applied only if the standard Apple secrets are
# present in the environment; otherwise an unsigned DMG is produced (Gatekeeper
# will require right-click → Open on first launch).

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
APP="$HERE/build/Lumen.app"
DIST="$ROOT/dist"

# Version: an explicit LUMEN_VERSION (e.g. from the release tag) wins, else the
# app's Info.plist is the source of truth.
VER="${LUMEN_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$HERE/Info.plist" 2>/dev/null || echo 1.0.0)}"

echo "==> Building app"
"$HERE/build.sh"

echo "==> Optional codesign (Developer ID)"
if [ -n "${MACOS_SIGN_IDENTITY:-}" ]; then
    codesign --force --deep --options runtime \
        --sign "$MACOS_SIGN_IDENTITY" "$APP"
    echo "    signed with $MACOS_SIGN_IDENTITY"
else
    echo "    MACOS_SIGN_IDENTITY not set — leaving ad-hoc signature (unsigned release)"
fi

echo "==> Staging DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$DIST"
DMG="$DIST/Lumen-$VER.dmg"
rm -f "$DMG"
hdiutil create -volname "Lumen" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> Optional notarization"
if [ -n "${AC_API_KEY_ID:-}" ] && [ -n "${AC_API_ISSUER:-}" ] && [ -n "${AC_API_KEY_PATH:-}" ]; then
    xcrun notarytool submit "$DMG" \
        --key "$AC_API_KEY_PATH" --key-id "$AC_API_KEY_ID" --issuer "$AC_API_ISSUER" \
        --wait
    xcrun stapler staple "$DMG"
    echo "    notarized + stapled"
else
    echo "    notarization secrets not set — skipping"
fi

echo "==> Done: $DMG"
