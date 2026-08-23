#!/bin/bash
set -e

APP_NAME="Pointrans"
APP_BUNDLE="${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"

echo "=== Building application ==="
./build.sh

echo "=== Creating DMG package ==="
rm -f "$DMG_NAME"

# Create a temporary staging directory
TMP_DIR=$(mktemp -d -t pointtrans-dmg-stage)
cp -R "$APP_BUNDLE" "$TMP_DIR/"

# Create a symlink to Applications directory so the user can easily install by dragging and dropping
ln -s /Applications "$TMP_DIR/Applications"

# Create the DMG file using hdiutil
hdiutil create -volname "${APP_NAME}" -srcfolder "$TMP_DIR" -ov -format UDZO "$DMG_NAME"

# Clean up temporary directory
rm -rf "$TMP_DIR"

echo "=== DMG Package Created Successfully: ${DMG_NAME} ==="
