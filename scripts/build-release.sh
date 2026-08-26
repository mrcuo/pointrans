#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA="$PROJECT_ROOT/build/DerivedData"
DIST_DIR="$PROJECT_ROOT/dist"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/Pointrans.app"
DIST_APP="$DIST_DIR/Pointrans.app"
SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:--}"

mkdir -p "$DIST_DIR" "$PROJECT_ROOT/build"
touch "$DIST_DIR/.metadata_never_index" "$PROJECT_ROOT/build/.metadata_never_index"

xcodebuild \
  -project "$PROJECT_ROOT/Pointrans.xcodeproj" \
  -scheme Pointrans \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  build

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Release app was not produced at $BUILT_APP" >&2
  exit 1
fi

rm -rf "$DIST_APP"
ditto "$BUILT_APP" "$DIST_APP"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - \
    --entitlements "$PROJECT_ROOT/Config/Pointrans.entitlements" \
    "$DIST_APP"
else
  codesign --force --deep --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$PROJECT_ROOT/Config/Pointrans.entitlements" \
    "$DIST_APP"
fi

ARCHITECTURES="$(lipo -archs "$DIST_APP/Contents/MacOS/Pointrans")"
if [[ "$ARCHITECTURES" != *arm64* || "$ARCHITECTURES" != *x86_64* ]]; then
  echo "Expected a Universal 2 binary, found: $ARCHITECTURES" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$DIST_APP"
echo "Built $DIST_APP ($ARCHITECTURES)"
