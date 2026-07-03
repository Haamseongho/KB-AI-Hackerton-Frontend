#!/usr/bin/env bash
set -euo pipefail

API_BASE_URL="${API_BASE_URL:-http://13.124.81.217:8080}"
WS_BASE_URL="${WS_BASE_URL:-ws://13.124.81.217:8080}"
DEVICE_ID="${1:-${DEVICE_ID:-}}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter command not found. Install Flutter SDK and add it to PATH." >&2
  exit 1
fi

flutter pub get

args=(
  run
  --dart-define=API_BASE_URL="${API_BASE_URL}"
  --dart-define=WS_BASE_URL="${WS_BASE_URL}"
)

if [[ -n "${DEVICE_ID}" ]]; then
  args+=(-d "${DEVICE_ID}")
fi

flutter "${args[@]}"
