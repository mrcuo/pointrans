#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
APP_PATH="$DIST_DIR/Pointrans.app"
DMG_PATH="$DIST_DIR/Pointrans-2.0.0.dmg"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  "$SCRIPT_DIR/build-release.sh"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing $APP_PATH" >&2
  exit 1
fi

STAGE_DIR="$(mktemp -d -t pointrans-dmg-stage)"
cleanup() { rm -rf "$STAGE_DIR"; }
trap cleanup EXIT

ditto "$APP_PATH" "$STAGE_DIR/Pointrans.app"
ln -s /Applications "$STAGE_DIR/Applications"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "Pointrans" \
  -srcfolder "$STAGE_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DMG_PATH"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

hdiutil imageinfo "$DMG_PATH" >/dev/null
echo "Created $DMG_PATH"
