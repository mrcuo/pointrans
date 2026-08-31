#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$PROJECT_ROOT/build/Artifacts.noindex/Pointrans.app"
EXPECTED_VERSION="$(sed -nE 's/^MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+).*$/\1/p' "$PROJECT_ROOT/Config/Base.xcconfig")"
EXPECTED_BUILD="$(sed -nE 's/^CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+).*$/\1/p' "$PROJECT_ROOT/Config/Base.xcconfig")"
DMG_PATH="$PROJECT_ROOT/dist/Pointrans-$EXPECTED_VERSION.dmg"
MOUNT_DIR="$(mktemp -d -t pointrans-mount)"
INSTALL_DIR="$(mktemp -d -t pointrans-install)"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

verify_signature_policy() {
  local app_path="$1"
  local signature_info

  signature_info="$(codesign -dvvv "$app_path" 2>&1)"
  if grep -Fq 'Signature=adhoc' <<<"$signature_info"; then
    if [[ "${ALLOW_ADHOC_SIGNING:-NO}" != "YES" ]]; then
      echo "Refusing to verify an ad-hoc signed installation candidate: $app_path" >&2
      return 1
    fi
  elif grep -Fq 'Authority=Developer ID Application:' <<<"$signature_info"; then
    spctl --assess --type execute --verbose=2 "$app_path"
  elif grep -Fq 'Authority=Apple Development:' <<<"$signature_info"; then
    grep -E '^TeamIdentifier=[A-Z0-9]{10}$' <<<"$signature_info" >/dev/null
  else
    echo "Unsupported signing chain for installation candidate: $app_path" >&2
    return 1
  fi

  if xattr -p com.apple.quarantine "$app_path" >/dev/null 2>&1; then
    echo "Installation candidate contains quarantine metadata: $app_path" >&2
    return 1
  fi
}

cleanup() {
  local app_path
  while IFS= read -r app_path; do
    "$LSREGISTER" -u "$app_path" >/dev/null 2>&1 || true
  done < <(find "$PROJECT_ROOT/build" -type d -name Pointrans.app -prune -print)
  "$LSREGISTER" -u "$APP_PATH" >/dev/null 2>&1 || true
  "$LSREGISTER" -u "$MOUNT_DIR/Pointrans.app" >/dev/null 2>&1 || true
  "$LSREGISTER" -u "$INSTALL_DIR/Pointrans.app" >/dev/null 2>&1 || true
  hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
  rm -rf "$MOUNT_DIR" "$INSTALL_DIR"
}
trap cleanup EXIT

test -d "$APP_PATH"
test -f "$DMG_PATH"
test "$(find "$PROJECT_ROOT/dist" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d '[:space:]')" = "1"

while IFS= read -r candidate; do
  case "$candidate" in
    "$PROJECT_ROOT"/build/*.noindex/*) ;;
    *)
      echo "Indexable repository application artifact is forbidden: $candidate" >&2
      exit 1
      ;;
  esac
done < <(find "$PROJECT_ROOT/build" "$PROJECT_ROOT/dist" -type d -name Pointrans.app -prune -print)

test "$(defaults read "$APP_PATH/Contents/Info" CFBundleIdentifier)" = "com.tailcasso.Pointrans"
test "$(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString)" = "$EXPECTED_VERSION"
test "$(defaults read "$APP_PATH/Contents/Info" CFBundleVersion)" = "$EXPECTED_BUILD"
test "$(defaults read "$APP_PATH/Contents/Info" LSUIElement)" = "1"
test "$(defaults read "$APP_PATH/Contents/Info" CFBundleIconName)" = "AppIcon"
test "$(defaults read "$APP_PATH/Contents/Info" PointransWorkerURL)" = "https://pointrans-api.cuostudio.workers.dev"
SOURCE_REVISION="$(defaults read "$APP_PATH/Contents/Info" PointransSourceRevision)"
[[ "$SOURCE_REVISION" =~ ^[0-9a-f]{40}(-dirty)?$ ]]

ARCHITECTURES="$(lipo -archs "$APP_PATH/Contents/MacOS/Pointrans")"
[[ "$ARCHITECTURES" == *arm64* && "$ARCHITECTURES" == *x86_64* ]]
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dvvv "$APP_PATH" 2>&1 | grep -F 'runtime' >/dev/null
verify_signature_policy "$APP_PATH"
! codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -Fq 'get-task-allow'
sqlite3 "$APP_PATH/Contents/Resources/Dictionary.sqlite3" 'PRAGMA quick_check;' | grep -Fxq 'ok'
python3 "$PROJECT_ROOT/scripts/verify_compiled_app_icon.py" "$APP_PATH/Contents/Resources/AppIcon.icns"

hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIR" -quiet
test -L "$MOUNT_DIR/Applications"
test -f "$MOUNT_DIR/.metadata_never_index"
ditto "$MOUNT_DIR/Pointrans.app" "$INSTALL_DIR/Pointrans.app"
codesign --verify --deep --strict --verbose=2 "$INSTALL_DIR/Pointrans.app"
verify_signature_policy "$INSTALL_DIR/Pointrans.app"
! codesign -d --entitlements :- "$INSTALL_DIR/Pointrans.app" 2>/dev/null | grep -Fq 'get-task-allow'
test "$(defaults read "$INSTALL_DIR/Pointrans.app/Contents/Info" PointransSourceRevision)" = "$SOURCE_REVISION"

echo "Verified Pointrans $EXPECTED_VERSION ($EXPECTED_BUILD) DMG install image ($ARCHITECTURES, source $SOURCE_REVISION)"
