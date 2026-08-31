#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
python3 "$PROJECT_ROOT/scripts/generate_brand_assets.py"
DERIVED_DATA="$PROJECT_ROOT/build/DerivedData.noindex"
ARTIFACT_DIR="$PROJECT_ROOT/build/Artifacts.noindex"
DIST_DIR="$PROJECT_ROOT/dist"
OUTPUT_APP="$ARTIFACT_DIR/Pointrans.app"
SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:-${POINTRANS_LOCAL_SIGN_IDENTITY:-}}"
ARCHIVE_ROOT="$(mktemp -d -t pointrans-archive)"
ARCHIVE_PATH="$ARCHIVE_ROOT/Pointrans.xcarchive"
BUILT_APP="$ARCHIVE_PATH/Products/Applications/Pointrans.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

unregister_build_apps() {
  local root app_path

  # Xcode registers every built .app with Launch Services, including test and
  # analyze products in separate DerivedData roots. Unregister the complete
  # repository build tree so these non-installable copies can never appear as
  # extra Pointrans entries in Launchpad or Spotlight.
  for root in "$ARCHIVE_ROOT" "$PROJECT_ROOT/build"; do
    if [[ ! -d "$root" ]]; then
      continue
    fi

    while IFS= read -r app_path; do
      "$LSREGISTER" -u "$app_path" >/dev/null 2>&1 || true
    done < <(find "$root" -type d -name Pointrans.app -prune -print)
  done
}

cleanup() {
  unregister_build_apps
  rm -rf -- "$ARCHIVE_ROOT"
}
trap cleanup EXIT
SOURCE_COMMIT="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
SOURCE_REVISION="$SOURCE_COMMIT"
if [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain --untracked-files=all)" ]]; then
  SOURCE_REVISION="${SOURCE_COMMIT}-dirty"
fi

mkdir -p "$ARTIFACT_DIR" "$DIST_DIR"

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/"Apple Development:/ { print $2; exit }')"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  if [[ "${ALLOW_ADHOC_SIGNING:-NO}" == "YES" ]]; then
    SIGN_IDENTITY="-"
  else
    echo "No valid Apple Development or Developer ID Application signing identity is available." >&2
    echo "Set ALLOW_ADHOC_SIGNING=YES only for a non-installable development artifact." >&2
    exit 1
  fi
fi

if [[ "$SIGN_IDENTITY" != "-" ]] &&
   ! security find-identity -v -p codesigning | grep -Fq "\"$SIGN_IDENTITY\""; then
  echo "Requested signing identity is not available: $SIGN_IDENTITY" >&2
  exit 1
fi

xcodebuild \
  -project "$PROJECT_ROOT/Pointrans.xcodeproj" \
  -scheme Pointrans \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  POINTRANS_SOURCE_REVISION="$SOURCE_REVISION" \
  archive

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Release app was not produced at $BUILT_APP" >&2
  exit 1
fi

if [[ -e "$OUTPUT_APP" ]]; then
  rm -rf -- "$OUTPUT_APP"
fi
ditto "$BUILT_APP" "$OUTPUT_APP"
xattr -cr "$OUTPUT_APP"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --options runtime --sign - \
    --entitlements "$PROJECT_ROOT/Config/Pointrans.entitlements" \
    "$OUTPUT_APP"
  echo "Warning: ad-hoc signing is CDHash-bound; macOS may require permissions again after replacement." >&2
elif [[ "$SIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$PROJECT_ROOT/Config/Pointrans.entitlements" \
    "$OUTPUT_APP"
else
  codesign --force --options runtime --timestamp=none \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$PROJECT_ROOT/Config/Pointrans.entitlements" \
    "$OUTPUT_APP"
fi
xattr -cr "$OUTPUT_APP"

ARCHITECTURES="$(lipo -archs "$OUTPUT_APP/Contents/MacOS/Pointrans")"
if [[ "$ARCHITECTURES" != *arm64* || "$ARCHITECTURES" != *x86_64* ]]; then
  echo "Expected a Universal 2 binary, found: $ARCHITECTURES" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$OUTPUT_APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :PointransSourceRevision' "$OUTPUT_APP/Contents/Info.plist")" = "$SOURCE_REVISION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$OUTPUT_APP/Contents/Info.plist")" = "AppIcon"
python3 "$PROJECT_ROOT/scripts/verify_compiled_app_icon.py" "$OUTPUT_APP/Contents/Resources/AppIcon.icns"
echo "Built $OUTPUT_APP ($ARCHITECTURES, source $SOURCE_REVISION, signing identity $SIGN_IDENTITY)"
