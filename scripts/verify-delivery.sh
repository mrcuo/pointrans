#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$PROJECT_ROOT/dist/Pointrans.app"
DMG_PATH="$PROJECT_ROOT/dist/Pointrans-2.0.0.dmg"
MOUNT_DIR="$(mktemp -d -t pointrans-mount)"
INSTALL_DIR="$(mktemp -d -t pointrans-install)"

cleanup() {
  hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
  rm -rf "$MOUNT_DIR" "$INSTALL_DIR"
}
trap cleanup EXIT

if [[ ! -d "$APP_PATH" ]]; then
  APP_PATH="/Applications/Pointrans.app"
fi

test -d "$APP_PATH"
test -f "$DMG_PATH"

test "$(defaults read "$APP_PATH/Contents/Info" CFBundleIdentifier)" = "com.tailcasso.Pointrans"
test "$(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString)" = "2.0.0"
test "$(defaults read "$APP_PATH/Contents/Info" LSUIElement)" = "1"

ARCHITECTURES="$(lipo -archs "$APP_PATH/Contents/MacOS/Pointrans")"
[[ "$ARCHITECTURES" == *arm64* && "$ARCHITECTURES" == *x86_64* ]]
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIR" -quiet
test -L "$MOUNT_DIR/Applications"
ditto "$MOUNT_DIR/Pointrans.app" "$INSTALL_DIR/Pointrans.app"
codesign --verify --deep --strict --verbose=2 "$INSTALL_DIR/Pointrans.app"

echo "Verified Pointrans 2.0.0 DMG install image ($ARCHITECTURES)"
