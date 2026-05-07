#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Cider.xcodeproj"
SCHEME="CiderApp"
CONFIGURATION="Debug"
DERIVED_DATA_PATH="$ROOT_DIR/.deriveddata/CiderCodex"
APP_NAME="Cider"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"

VERIFY=0
STREAM_LOGS=0

for arg in "$@"; do
  case "$arg" in
    --verify)
      VERIFY=1
      ;;
    --logs|--telemetry)
      STREAM_LOGS=1
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: $0 [--verify] [--logs|--telemetry]" >&2
      exit 2
      ;;
  esac
done

stop_app() {
  if pgrep -x "$APP_NAME" >/dev/null; then
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    sleep 1
  fi

  if pgrep -x "$APP_NAME" >/dev/null; then
    pkill -x "$APP_NAME" || true
    sleep 1
  fi

  if pgrep -x "$APP_NAME" >/dev/null; then
    pkill -9 -x "$APP_NAME" || true
  fi
}

stop_app

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app was not found at $APP_PATH" >&2
  exit 1
fi

/usr/bin/open -n "$APP_PATH"

if [[ "$VERIFY" -eq 1 || "$STREAM_LOGS" -eq 1 ]]; then
  for _ in {1..20}; do
    if pgrep -x "$APP_NAME" >/dev/null; then
      echo "$APP_NAME is running from $APP_PATH"
      break
    fi
    sleep 0.25
  done

  if ! pgrep -x "$APP_NAME" >/dev/null; then
    echo "$APP_NAME did not start after launch." >&2
    exit 1
  fi
fi

if [[ "$STREAM_LOGS" -eq 1 ]]; then
  /usr/bin/log stream --style compact --predicate "process == \"$APP_NAME\""
fi
