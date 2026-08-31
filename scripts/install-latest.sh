#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_APP="${1:-$PROJECT_ROOT/build/Artifacts.noindex/Pointrans.app}"
INSTALL_APP="/Applications/Pointrans.app"
STAGING_APP="/Applications/.Pointrans.app.installing"
PREVIOUS_APP="/Applications/.Pointrans.app.previous"
EXPECTED_BUNDLE_ID="com.tailcasso.Pointrans"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ "${CONFIRM_INSTALL:-}" != "YES" ]]; then
  echo "Installation is a user-operated action." >&2
  echo "Re-run with CONFIRM_INSTALL=YES after reviewing SOURCE_APP=$SOURCE_APP." >&2
  exit 2
fi

read_plist() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"
}

verify_app() {
  local app_path="$1"
  local bundle_id architectures

  if [[ ! -d "$app_path" ]]; then
    echo "Missing application: $app_path" >&2
    return 1
  fi

  bundle_id="$(read_plist "$app_path" CFBundleIdentifier)"
  if [[ "$bundle_id" != "$EXPECTED_BUNDLE_ID" ]]; then
    echo "Refusing to install unexpected bundle identifier: $bundle_id" >&2
    return 1
  fi

  architectures="$(lipo -archs "$app_path/Contents/MacOS/Pointrans")"
  if [[ "$architectures" != *arm64* || "$architectures" != *x86_64* ]]; then
    echo "Refusing to install a non-Universal 2 build: $architectures" >&2
    return 1
  fi

  codesign --verify --deep --strict "$app_path"
}

verify_app "$SOURCE_APP"

SOURCE_VERSION="$(read_plist "$SOURCE_APP" CFBundleShortVersionString)"
SOURCE_BUILD="$(read_plist "$SOURCE_APP" CFBundleVersion)"
if [[ -d "$INSTALL_APP" ]]; then
  INSTALLED_BUNDLE_ID="$(read_plist "$INSTALL_APP" CFBundleIdentifier 2>/dev/null || true)"
  INSTALLED_BUILD="$(read_plist "$INSTALL_APP" CFBundleVersion 2>/dev/null || true)"
  if [[ "$INSTALLED_BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" && "$SOURCE_BUILD" =~ ^[0-9]+$ && "$INSTALLED_BUILD" =~ ^[0-9]+$ ]]; then
    if (( SOURCE_BUILD < INSTALLED_BUILD )) && [[ "${ALLOW_DOWNGRADE:-0}" != "1" ]]; then
      echo "Refusing to replace build $INSTALLED_BUILD with older build $SOURCE_BUILD." >&2
      echo "Set ALLOW_DOWNGRADE=1 only when an intentional rollback is required." >&2
      exit 1
    fi
  fi
fi

rm -rf -- "$STAGING_APP" "$PREVIOUS_APP"
ditto "$SOURCE_APP" "$STAGING_APP"
xattr -cr "$STAGING_APP"
verify_app "$STAGING_APP"

# Stop only processes whose executable name belongs to this application.
killall Pointrans 2>/dev/null || true
for _ in {1..20}; do
  if ! pgrep -x Pointrans >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

if [[ -d "$INSTALL_APP" ]]; then
  "$LSREGISTER" -u "$INSTALL_APP" >/dev/null 2>&1 || true
  mv "$INSTALL_APP" "$PREVIOUS_APP"
fi

if ! mv "$STAGING_APP" "$INSTALL_APP"; then
  if [[ -d "$PREVIOUS_APP" && ! -d "$INSTALL_APP" ]]; then
    mv "$PREVIOUS_APP" "$INSTALL_APP"
  fi
  echo "Installation failed; the previous application was restored." >&2
  exit 1
fi

if ! verify_app "$INSTALL_APP"; then
  rm -rf -- "$INSTALL_APP"
  if [[ -d "$PREVIOUS_APP" ]]; then
    mv "$PREVIOUS_APP" "$INSTALL_APP"
  fi
  echo "Installed application failed verification; the previous application was restored." >&2
  exit 1
fi

rm -rf -- "$PREVIOUS_APP"
"$LSREGISTER" -f "$INSTALL_APP" >/dev/null 2>&1 || true

if [[ "${LAUNCH_AFTER_INSTALL:-0}" == "1" ]]; then
  open "$INSTALL_APP"
  echo "Installed and launched Pointrans $SOURCE_VERSION ($SOURCE_BUILD) at $INSTALL_APP"
else
  echo "Installed Pointrans $SOURCE_VERSION ($SOURCE_BUILD) at $INSTALL_APP (not launched)"
fi
