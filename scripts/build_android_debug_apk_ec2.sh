#!/usr/bin/env bash
set -euo pipefail

API_BASE_URL="${API_BASE_URL:-http://13.124.81.217:8080}"
WS_BASE_URL="${WS_BASE_URL:-ws://13.124.81.217:8080}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter command not found. Install Flutter SDK and add it to PATH." >&2
  exit 1
fi

flutter pub get
flutter build apk \
  --debug \
  --dart-define=API_BASE_URL="${API_BASE_URL}" \
  --dart-define=WS_BASE_URL="${WS_BASE_URL}"

echo "Built: build/app/outputs/flutter-apk/app-debug.apk"
