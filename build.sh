#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Unlatch.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "[Unlatch] Compiling Swift source files..."

swiftc \
  -target arm64-apple-macosx13.0 \
  -O \
  "$ROOT_DIR/Sources/MultitouchEngine.swift" \
  "$ROOT_DIR/Sources/EventDispatcher.swift" \
  "$ROOT_DIR/Sources/SleepObserver.swift" \
  "$ROOT_DIR/Sources/Updater.swift" \
  "$ROOT_DIR/Sources/AppDelegate.swift" \
  "$ROOT_DIR/Sources/main.swift" \
  -o "$MACOS_DIR/Unlatch"

cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
if [ -f "$ROOT_DIR/AppIcon.icns" ]; then
    cp "$ROOT_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

codesign --force --deep --sign - "$APP_DIR"

echo "[Unlatch] Build complete -> $APP_DIR"
