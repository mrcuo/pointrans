#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KEEP_APP="/Applications/Pointrans.app"
EXPECTED_BUNDLE_ID="com.tailcasso.Pointrans"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

unregister_app() {
  "$LSREGISTER" -u "$1" >/dev/null 2>&1 || true
}

remove_known_app() {
  local app_path="$1"
  local bundle_id=""

  [[ "$app_path" == "$KEEP_APP" ]] && return
  unregister_app "$app_path"
  if [[ ! -e "$app_path" && ! -L "$app_path" ]]; then
    return
  fi

  if [[ -f "$app_path/Contents/Info.plist" ]]; then
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist" 2>/dev/null || true)"
  fi
  if [[ "$bundle_id" != "$EXPECTED_BUNDLE_ID" ]]; then
    echo "Refusing to remove a bundle that is not Pointrans: $app_path" >&2
    return 1
  fi

  rm -rf -- "$app_path"
  if [[ -e "$app_path" || -L "$app_path" ]]; then
    echo "Duplicate still exists after cleanup: $app_path" >&2
    return 1
  fi
  echo "Removed duplicate: $app_path"
}

# A mounted installer is another LaunchServices-visible application copy.
if mount | grep -Fq ' on /Volumes/Pointrans '; then
  hdiutil detach "/Volumes/Pointrans" -quiet || hdiutil detach "/Volumes/Pointrans" -force -quiet
  echo "Unmounted /Volumes/Pointrans"
fi
unregister_app "/Volumes/Pointrans/Pointrans.app"

remove_known_app "$PROJECT_ROOT/dist/Pointrans.app"
remove_known_app "$PROJECT_ROOT/.claude/worktrees/amazing-driscoll-4b2073/Pointrans.app"
remove_known_app "/Users/tailcasso/Documents/Antigravity/光标翻译/.claude/worktrees/amazing-driscoll-4b2073/Pointrans.app"

# Trash contents belong to the user. Never delete or move them; only stop
# LaunchServices from offering a trashed copy as an installed application.
unregister_app "/Users/tailcasso/.Trash/Pointrans.app"

# Remove only top-level Pointrans test/DerivedData roots created in /private/tmp.
while IFS= read -r temp_root; do
  [[ "$(dirname "$temp_root")" == "/private/tmp" ]] || continue
  [[ "$(basename "$temp_root")" == Pointrans* ]] || continue
  while IFS= read -r temp_app; do
    unregister_app "$temp_app"
  done < <(find "$temp_root" -type d -name Pointrans.app -print 2>/dev/null)
  rm -rf -- "$temp_root"
  echo "Removed test residual: $temp_root"
done < <(find /private/tmp -maxdepth 1 -type d -name 'Pointrans*' -print)

# Release DerivedData is transient once the verified app has been installed.
if [[ -d "$PROJECT_ROOT/build/DerivedData" ]]; then
  while IFS= read -r built_app; do
    unregister_app "$built_app"
  done < <(find "$PROJECT_ROOT/build/DerivedData" -type d -name Pointrans.app -print 2>/dev/null)
  rm -rf -- "$PROJECT_ROOT/build/DerivedData"
  echo "Removed release build residual: $PROJECT_ROOT/build/DerivedData"
fi

# Unregister any older paths that no longer exist but remain in LaunchServices.
while IFS= read -r registered_path; do
  [[ "$registered_path" == "$KEEP_APP" ]] && continue
  case "$registered_path" in
    /private/tmp/Pointrans*|/Volumes/Pointrans/Pointrans.app|"$PROJECT_ROOT"/build/*|"$PROJECT_ROOT"/dist/Pointrans.app|/Users/*/.Trash/Pointrans.app|*/.claude/worktrees/*/Pointrans.app)
      unregister_app "$registered_path"
      ;;
  esac
done < <(
  "$LSREGISTER" -dump 2>/dev/null \
    | awk '/^path:/{path=$0} /^identifier:[[:space:]]+com\.tailcasso\.Pointrans$/{print path}' \
    | sed -E 's/^path:[[:space:]]+//; s/ \(0x[0-9a-f]+\)$//' \
    | sort -u
)

mkdir -p "$PROJECT_ROOT/build" "$PROJECT_ROOT/dist"
touch "$PROJECT_ROOT/build/.metadata_never_index" "$PROJECT_ROOT/dist/.metadata_never_index"

if [[ -d "$KEEP_APP" ]]; then
  "$LSREGISTER" -f "$KEEP_APP" >/dev/null 2>&1 || true
fi

# A Dock restart is visually disruptive, so it is never part of normal builds.
if [[ "${REFRESH_DOCK_AFTER_CLEANUP:-0}" == "1" ]]; then
  killall Dock 2>/dev/null || true
fi

echo "Pointrans cleanup complete. Preserved $KEEP_APP and user data."
