#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXECUTABLE="$PROJECT_ROOT/dist/Pointrans.app/Contents/MacOS/Pointrans"
SAMPLE_FILE="$(mktemp -t pointrans-cpu)"
LOG_FILE="$(mktemp -t pointrans-log)"

"$EXECUTABLE" >"$LOG_FILE" 2>&1 &
APP_PID=$!

cleanup() {
  kill "$APP_PID" 2>/dev/null || true
  wait "$APP_PID" 2>/dev/null || true
  rm -f "$SAMPLE_FILE" "$LOG_FILE"
}
trap cleanup EXIT

for _ in $(seq 1 60); do
  sleep 5
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "Pointrans exited during idle measurement" >&2
    exit 1
  fi
  ps -p "$APP_PID" -o %cpu= >>"$SAMPLE_FILE"
done

awk '
  { total += $1; if ($1 > maximum) maximum = $1; count += 1 }
  END {
    if (count == 0) exit 1
    printf "Idle CPU: average %.3f%%, max sample %.3f%%, samples %d over 5 minutes\n", total / count, maximum, count
  }
' "$SAMPLE_FILE"
