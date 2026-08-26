#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKER_DIR="$PROJECT_ROOT/Worker"

if [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain --untracked-files=all)" ]]; then
  echo "Refusing to deploy from a dirty worktree. Commit the exact source first." >&2
  exit 1
fi

SOURCE_REVISION="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
PRODUCT_VERSION="$(sed -nE 's/^MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+).*$/\1/p' "$PROJECT_ROOT/Config/Base.xcconfig")"

if [[ ! "$SOURCE_REVISION" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Unable to resolve a full Git source revision." >&2
  exit 1
fi
if [[ ! "$PRODUCT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Unable to resolve a valid product version." >&2
  exit 1
fi

cd "$WORKER_DIR"
npx wrangler deploy \
  --strict \
  --var "SOURCE_REVISION:$SOURCE_REVISION" \
  --var "PRODUCT_VERSION:$PRODUCT_VERSION"

POINTRANS_EXPECTED_VERSION="$PRODUCT_VERSION" \
POINTRANS_EXPECTED_COMMIT="$SOURCE_REVISION" \
node "$PROJECT_ROOT/scripts/verify-production-worker.mjs" --identity-only
