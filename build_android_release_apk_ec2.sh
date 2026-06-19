#!/usr/bin/env bash
set -euo pipefail

API_BASE_URL="${API_BASE_URL:-http://13.124.81.217:8080}"
WS_BASE_URL="${WS_BASE_URL:-ws://13.124.81.217:8080}"
BUILD_FORMAT="${BUILD_FORMAT:-apk}"
SPLIT_PER_ABI="${SPLIT_PER_ABI:-false}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter command not found. Install Flutter SDK and add it to PATH." >&2
  exit 1
fi

case "${BUILD_FORMAT}" in
  apk|appbundle)
    ;;
  *)
    echo "BUILD_FORMAT must be either 'apk' or 'appbundle'." >&2
    exit 1
    ;;
esac

echo "Building Android release ${BUILD_FORMAT}"
echo "API_BASE_URL=${API_BASE_URL}"
echo "WS_BASE_URL=${WS_BASE_URL}"

flutter pub get

args=(
  build
  "${BUILD_FORMAT}"
  --release
  --dart-define=API_BASE_URL="${API_BASE_URL}"
  --dart-define=WS_BASE_URL="${WS_BASE_URL}"
)

if [[ "${BUILD_FORMAT}" == "apk" && "${SPLIT_PER_ABI}" == "true" ]]; then
  args+=(--split-per-abi)
fi

flutter "${args[@]}"

if [[ "${BUILD_FORMAT}" == "appbundle" ]]; then
  echo "Built: build/app/outputs/bundle/release/app-release.aab"
elif [[ "${SPLIT_PER_ABI}" == "true" ]]; then
  echo "Built split APKs under: build/app/outputs/flutter-apk/"
else
  echo "Built: build/app/outputs/flutter-apk/app-release.apk"
fi

echo "Note: android/app/build.gradle.kts currently signs release builds with the debug signing config."
