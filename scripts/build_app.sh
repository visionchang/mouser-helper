#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MouseHelper"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

echo "==> Building $APP_NAME (release)..."
# shellcheck disable=SC2086
swift build -c release ${SWIFT_EXTRA_ARGS:-}

# shellcheck disable=SC2086
BIN_PATH="$(swift build -c release ${SWIFT_EXTRA_ARGS:-} --show-bin-path)/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "Error: Built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE" "$BUILD_DIR/AppIcon.iconset"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

echo "==> Generating AppIcon.icns..."
ICON_SOURCE="$ROOT_DIR/Resources/AppIconSource.png"
if [[ -f "$ICON_SOURCE" ]]; then
    swift "$ROOT_DIR/scripts/generate_icon.swift" "$RESOURCES_DIR/AppIcon.icns" "$ICON_SOURCE"
else
    swift "$ROOT_DIR/scripts/generate_icon.swift" "$RESOURCES_DIR/AppIcon.icns"
fi

SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -E 'Developer ID Application:|Apple Development:' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "==> Code signing with identity: $SIGN_IDENTITY"
    codesign --force --deep --sign "$SIGN_IDENTITY" --identifier "com.mousehelper.app" "$APP_BUNDLE"
else
    echo "==> No signing identity found; falling back to ad-hoc signing..."
    codesign --force --deep --sign - --identifier "com.mousehelper.app" "$APP_BUNDLE"
fi

echo "==> Done! App bundle created at:"
echo "    $APP_BUNDLE"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> Installing to /Applications/$APP_NAME.app..."
    rm -rf "/Applications/$APP_NAME.app"
    ditto "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    echo "==> Installed at /Applications/$APP_NAME.app"
fi
