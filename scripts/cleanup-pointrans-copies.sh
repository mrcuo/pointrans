#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LEGACY_DIST_APP="$PROJECT_ROOT/dist/Pointrans.app"
LEGACY_DERIVED_DATA="$PROJECT_ROOT/build/DerivedData"
ARTIFACTS_DIR="$PROJECT_ROOT/build/Artifacts.noindex"
DERIVED_DATA="$PROJECT_ROOT/build/DerivedData.noindex"
TEST_DATA="$PROJECT_ROOT/build/Tests.noindex"
ANALYZE_DATA="$PROJECT_ROOT/build/Analyze.noindex"
CORE_TEST_DATA="$PROJECT_ROOT/build/CoreTestsDerivedData.noindex"
BUILD_FOR_TESTING_DATA="$PROJECT_ROOT/build/BuildForTesting.noindex"
ANALYZE_DERIVED_DATA="$PROJECT_ROOT/build/AnalyzeDerivedData.noindex"
EXPECTED_BUNDLE_ID="com.tailcasso.Pointrans"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ "${CONFIRM_BUILD_CLEANUP:-}" != "YES" ]]; then
  echo "Refusing cleanup without CONFIRM_BUILD_CLEANUP=YES." >&2
  echo "Only repository-owned Pointrans build artifacts are eligible." >&2
  exit 2
fi

remove_app() {
  local app_path="$1"
  local bundle_id

  if [[ ! -d "$app_path" ]]; then
    return
  fi

  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$bundle_id" != "$EXPECTED_BUNDLE_ID" ]]; then
    echo "Refusing to remove unexpected bundle at $app_path" >&2
    exit 1
  fi

  "$LSREGISTER" -u "$app_path" >/dev/null 2>&1 || true
  rm -rf -- "$app_path"
  echo "Removed $app_path"
}

unregister_apps_below() {
  local root="$1"

  if [[ ! -d "$root" ]]; then
    return
  fi

  while IFS= read -r app_path; do
    "$LSREGISTER" -u "$app_path" >/dev/null 2>&1 || true
  done < <(find "$root" -type d -name Pointrans.app -prune -print)
}

remove_app "$LEGACY_DIST_APP"
unregister_apps_below "$PROJECT_ROOT/build"

if [[ -d "$ARTIFACTS_DIR/Pointrans.app" ]]; then
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ARTIFACTS_DIR/Pointrans.app/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
    echo "Refusing to remove unexpected bundle at $ARTIFACTS_DIR/Pointrans.app" >&2
    exit 1
  fi
fi

for generated_dir in "$LEGACY_DERIVED_DATA" "$ARTIFACTS_DIR" "$DERIVED_DATA" "$TEST_DATA" "$ANALYZE_DATA" "$CORE_TEST_DATA" "$BUILD_FOR_TESTING_DATA" "$ANALYZE_DERIVED_DATA"; do
  if [[ -d "$generated_dir" ]]; then
    unregister_apps_below "$generated_dir"
    rm -rf -- "$generated_dir"
    echo "Removed $generated_dir"
  fi
done

mkdir -p "$PROJECT_ROOT/build" "$PROJECT_ROOT/dist"
echo "Repository build cleanup complete. /Applications and user data were not touched."
