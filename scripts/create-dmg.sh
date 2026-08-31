#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
APP_PATH="$PROJECT_ROOT/build/Artifacts.noindex/Pointrans.app"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  "$SCRIPT_DIR/build-release.sh"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing $APP_PATH" >&2
  exit 1
fi

PRODUCT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$DIST_DIR/Pointrans-$PRODUCT_VERSION.dmg"

# Finder can leave these repository-local metadata files behind after a human
# opens dist. They are never delivery artifacts.
rm -f -- "$DIST_DIR/.DS_Store" "$DIST_DIR/.metadata_never_index"

while IFS= read -r unexpected; do
  if [[ "$unexpected" != "$DMG_PATH" ]]; then
    echo "Unexpected file in dist; refusing to overwrite it: $unexpected" >&2
    exit 1
  fi
done < <(find "$DIST_DIR" -mindepth 1 -maxdepth 1 -print)

STAGE_DIR="$(mktemp -d -t pointrans-dmg-stage)"
cleanup() { rm -rf "$STAGE_DIR"; }
trap cleanup EXIT

ditto "$APP_PATH" "$STAGE_DIR/Pointrans.app"
xattr -cr "$STAGE_DIR/Pointrans.app"
ln -s /Applications "$STAGE_DIR/Applications"
touch "$STAGE_DIR/.metadata_never_index"
if [[ -e "$DMG_PATH" ]]; then
  rm -f -- "$DMG_PATH"
fi
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

xattr -cr "$DMG_PATH"
hdiutil imageinfo "$DMG_PATH" >/dev/null
echo "Created $DMG_PATH"
