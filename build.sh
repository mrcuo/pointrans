#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/scripts/build-release.sh"

if [[ "${AUTO_INSTALL_LATEST:-1}" == "1" ]]; then
  "$SCRIPT_DIR/scripts/install-latest.sh" "$SCRIPT_DIR/dist/Pointrans.app"
  if [[ "${KEEP_BUILD_ARTIFACTS:-0}" != "1" ]]; then
    "$SCRIPT_DIR/scripts/cleanup-pointrans-copies.sh"
  fi
fi
