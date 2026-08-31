#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/scripts/generate_xcode_project.py"
"$SCRIPT_DIR/scripts/create-dmg.sh"
"$SCRIPT_DIR/scripts/verify-delivery.sh"
