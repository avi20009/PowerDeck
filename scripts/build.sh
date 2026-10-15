#!/bin/bash
# Builds PowerDeck.app into ./build.  Usage: scripts/build.sh [--open]
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="PowerDeck"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ ! -f "$BUILD_DIR/AppIcon.icns" ]; then
  ICONSET="$BUILD_DIR/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  swiftc -O scripts/make_icon.swift -o "$BUILD_DIR/make_icon"
  "$BUILD_DIR/make_icon" "$BUILD_DIR/icon_1024.png"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$BUILD_DIR/icon_1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$BUILD_DIR/icon_1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$BUILD_DIR/AppIcon.icns"
fi
cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [ "${1:-}" = "--open" ]; then
  pkill -x "$APP_NAME" 2>/dev/null || true
  open "$APP"
fi
