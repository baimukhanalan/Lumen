#!/bin/bash
#
# build.sh — assemble macos/build/Lumen.app and the lumen-daemon binary using
# ONLY the Command Line Tools toolchain (swiftc + the CLT macOS SDK).
#
# There is no Xcode and no xcodebuild in the target environment, so this script
# compiles a shared static library (LumenCore) and links the two products
# against it, then hand-assembles a proper .app bundle.
#
# The build is idempotent: the build/ directory is recreated from scratch on
# every run. The final app path is printed at the end.

set -euo pipefail

# --- locations --------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$SCRIPT_DIR/Sources"
SHARED_I18N="$REPO_ROOT/shared/i18n"
BUILD="$SCRIPT_DIR/build"
OBJ="$BUILD/obj"
APP="$BUILD/Lumen.app"

# --- toolchain --------------------------------------------------------------
SDK="$(xcrun --show-sdk-path)"
SWIFTC="$(xcrun -f swiftc)"
SWIFT_VERSION_FLAG=(-swift-version 5)

echo "==> Toolchain"
"$SWIFTC" --version | sed 's/^/    /'
echo "    SDK: $SDK"

# Deployment target: match LSMinimumSystemVersion (macOS 12) rather than the
# host OS, so the artifact runs on older Macs. Arch follows the build host.
ARCH="$(uname -m)"
TARGET_TRIPLE="${ARCH}-apple-macos12.0"

COMMON=(-sdk "$SDK" "${SWIFT_VERSION_FLAG[@]}" -target "$TARGET_TRIPLE" -O)
echo "    Target: $TARGET_TRIPLE"

# --- clean ------------------------------------------------------------------
echo "==> Cleaning $BUILD"
rm -rf "$BUILD"
mkdir -p "$OBJ"

# --- 1) shared core: static library + swiftmodule ---------------------------
echo "==> Building LumenCore (static library + module)"
CORE_SOURCES=("$SRC"/LumenCore/*.swift)
"$SWIFTC" "${COMMON[@]}" \
    -module-name LumenCore \
    -emit-module -emit-module-path "$OBJ/LumenCore.swiftmodule" \
    -emit-library -static -o "$OBJ/libLumenCore.a" \
    "${CORE_SOURCES[@]}"

# --- 2) daemon binary -------------------------------------------------------
echo "==> Building lumen-daemon"
DAEMON_SOURCES=("$SRC"/LumenDaemon/*.swift)
"$SWIFTC" "${COMMON[@]}" \
    -module-name lumen_daemon \
    -I "$OBJ" -L "$OBJ" -lLumenCore \
    -o "$OBJ/lumen-daemon" \
    "${DAEMON_SOURCES[@]}"

# --- 3) app binary ----------------------------------------------------------
echo "==> Building Lumen (menu-bar app)"
APP_SOURCES=("$SRC"/Lumen/*.swift)
"$SWIFTC" "${COMMON[@]}" \
    -module-name Lumen \
    -I "$OBJ" -L "$OBJ" -lLumenCore \
    -framework AppKit -framework SwiftUI -framework Combine \
    -o "$OBJ/Lumen" \
    "${APP_SOURCES[@]}"

# --- 4) assemble the .app bundle -------------------------------------------
echo "==> Assembling $APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources/i18n"

cp "$OBJ/Lumen"        "$APP/Contents/MacOS/Lumen"
cp "$OBJ/lumen-daemon" "$APP/Contents/Resources/lumen-daemon"
cp "$SCRIPT_DIR/Info.plist" "$APP/Contents/Info.plist"

# Localization bundles.
if compgen -G "$SHARED_I18N/*.json" > /dev/null; then
    cp "$SHARED_I18N"/*.json "$APP/Contents/Resources/i18n/"
else
    echo "    WARNING: no i18n JSON found at $SHARED_I18N"
fi

# PkgInfo (harmless, expected by some tooling).
printf 'APPL????' > "$APP/Contents/PkgInfo"

chmod 755 "$APP/Contents/MacOS/Lumen" "$APP/Contents/Resources/lumen-daemon"

# Ad-hoc code signature so the app runs locally without Gatekeeper friction.
# (A real Developer ID signature + notarization is added in release CI.)
if command -v codesign > /dev/null 2>&1; then
    echo "==> Ad-hoc signing (codesign -s -)"
    codesign --force --deep -s - "$APP" 2>/dev/null || \
        echo "    (ad-hoc signing skipped/failed — app still runs locally)"
fi

echo ""
echo "==> Build complete"
echo "    App:    $APP"
echo "    Daemon: $APP/Contents/Resources/lumen-daemon"
echo "    Run:    open \"$APP\""
