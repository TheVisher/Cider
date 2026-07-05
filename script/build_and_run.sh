#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Cider.xcodeproj"
SCHEME="CiderApp"
CONFIGURATION="Debug"
DERIVED_DATA_PATH="$ROOT_DIR/.deriveddata/CiderCodex"
APP_NAME="Cider"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

VERIFY=0
STREAM_LOGS=0
TELEMETRY=0
QA_VISIBLE=0
LOG_DIR=""
WATCHDOG_PID=""
VERIFY_WINDOW_STATUS_PATH="${TMPDIR:-/tmp}/cider-verify-window-status.txt"

for arg in "$@"; do
  case "$arg" in
    --verify)
      VERIFY=1
      ;;
    --logs)
      STREAM_LOGS=1
      ;;
    --telemetry)
      STREAM_LOGS=1
      TELEMETRY=1
      ;;
    --qa-visible)
      QA_VISIBLE=1
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: $0 [--verify] [--logs|--telemetry] [--qa-visible]" >&2
      exit 2
      ;;
  esac
done

stop_app() {
  local repo_app_pattern="$ROOT_DIR/.*/$APP_NAME.app/Contents/MacOS/$APP_NAME"

  if pgrep -f "$repo_app_pattern" >/dev/null; then
    pkill -f "$repo_app_pattern" || true
    sleep 1
  fi

  if pgrep -f "$repo_app_pattern" >/dev/null; then
    pkill -9 -f "$repo_app_pattern" || true
  fi
}

remove_stale_app_bundles() {
  local stale_app

  while IFS= read -r -d '' stale_app; do
    if [[ "$stale_app" == "$APP_PATH" ]]; then
      continue
    fi

    if [[ -x "$LSREGISTER" ]]; then
      "$LSREGISTER" -u "$stale_app" >/dev/null 2>&1 || true
    fi
    rm -rf "$stale_app"
  done < <(find "$ROOT_DIR" -path "*/$APP_NAME.app" -type d -prune -print0)
}

start_watchdog() {
  local pid="$1"
  local log_dir="$2"
  local stats_path="$log_dir/process-stats.tsv"
  local samples_dir="$log_dir/samples"

  mkdir -p "$samples_dir"
  printf "timestamp\tpid\tstat\tcpu\tmem\trss_kb\tetime\tcommand\n" > "$stats_path"

  (
    local tick=0
    while kill -0 "$pid" >/dev/null 2>&1; do
      local timestamp
      timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      ps -p "$pid" -o pid=,stat=,%cpu=,%mem=,rss=,etime=,command= \
        | awk -v ts="$timestamp" '{$1=$1; print ts "\t" $0}' >> "$stats_path" || true

      if (( tick % 6 == 0 )); then
        sample "$pid" 2 -file "$samples_dir/sample-$(date -u +"%Y%m%dT%H%M%SZ").txt" >/dev/null 2>&1 || true
      fi

      tick=$((tick + 1))
      sleep 5
    done
  ) &
  WATCHDOG_PID="$!"
}

wait_for_accessible_window() {
  local attempts=60
  local last_status=""

  for _ in $(seq 1 "$attempts"); do
    if screen_is_locked; then
      echo "Cannot verify a Cider window while the macOS screen is locked; unlock the session and rerun --verify." >&2
      return 1
    fi

    last_status="$(osascript <<APPLESCRIPT 2>&1 || true
tell application "System Events"
  if not (exists process "$APP_NAME") then
    return "missing-process"
  end if
  tell process "$APP_NAME"
    set frontmost to true
    set windowCount to count of windows
    if windowCount > 0 then
      set windowDescriptions to {}
      repeat with appWindow in windows
        set end of windowDescriptions to ((name of appWindow) & " " & (position of appWindow as text) & " " & (size of appWindow as text))
      end repeat
      return "windows=" & windowCount & " " & (windowDescriptions as text)
    end if
    return "windows=0"
  end tell
end tell
APPLESCRIPT
)"

    if [[ "$last_status" == windows=[1-9]* ]]; then
      echo "$APP_NAME accessible window: $last_status"
      return 0
    fi

    sleep 0.5
  done

  echo "$APP_NAME did not expose an accessible window after launch. Last status: $last_status" >&2
  return 1
}

screen_is_locked() {
  python3 - <<'PY'
import Quartz
import sys

session = Quartz.CGSessionCopyCurrentDictionary() or {}
sys.exit(0 if session.get("CGSSessionScreenIsLocked") else 1)
PY
}

cleanup() {
  if [[ -n "$WATCHDOG_PID" ]]; then
    kill "$WATCHDOG_PID" >/dev/null 2>&1 || true
  fi
}

stop_app
remove_stale_app_bundles
rm -f "$VERIFY_WINDOW_STATUS_PATH"

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

stop_app
remove_stale_app_bundles

if [[ "$STREAM_LOGS" -eq 1 ]]; then
  LOG_DIR="${CIDER_DIAGNOSTICS_DIR:-$HOME/Library/Logs/Cider/dev-session-$(date -u +"%Y%m%dT%H%M%SZ")}"
  mkdir -p "$LOG_DIR"
  echo "Cider diagnostics: $LOG_DIR"
fi

if [[ "$TELEMETRY" -eq 1 ]]; then
  if [[ "$QA_VISIBLE" -eq 1 ]]; then
    /usr/bin/open \
      --stdout "$LOG_DIR/stdout.log" \
      --stderr "$LOG_DIR/stderr.log" \
      --env "CIDER_PERF_MONITOR=1" \
      --env "CIDER_PERF_LOG_PATH=$LOG_DIR/performance.log" \
      --env "CIDER_QA_VISIBLE_WINDOW=1" \
      "$APP_PATH"
  else
    if [[ "$VERIFY" -eq 1 ]]; then
      /usr/bin/open \
        --stdout "$LOG_DIR/stdout.log" \
        --stderr "$LOG_DIR/stderr.log" \
        --env "CIDER_PERF_MONITOR=1" \
        --env "CIDER_PERF_LOG_PATH=$LOG_DIR/performance.log" \
        --env "CIDER_VERIFY_VISIBLE_WINDOW=1" \
        --env "CIDER_VERIFY_WINDOW_STATUS_PATH=$VERIFY_WINDOW_STATUS_PATH" \
        "$APP_PATH"
    else
      /usr/bin/open \
        --stdout "$LOG_DIR/stdout.log" \
        --stderr "$LOG_DIR/stderr.log" \
        --env "CIDER_PERF_MONITOR=1" \
        --env "CIDER_PERF_LOG_PATH=$LOG_DIR/performance.log" \
        "$APP_PATH"
    fi
  fi
else
  if [[ "$QA_VISIBLE" -eq 1 ]]; then
    /usr/bin/open --env "CIDER_QA_VISIBLE_WINDOW=1" "$APP_PATH"
  elif [[ "$VERIFY" -eq 1 ]]; then
    /usr/bin/open \
      --env "CIDER_VERIFY_VISIBLE_WINDOW=1" \
      --env "CIDER_VERIFY_WINDOW_STATUS_PATH=$VERIFY_WINDOW_STATUS_PATH" \
      "$APP_PATH"
  else
    /usr/bin/open "$APP_PATH"
  fi
fi

if [[ "$VERIFY" -eq 1 || "$STREAM_LOGS" -eq 1 ]]; then
  for _ in {1..20}; do
    if pgrep -f "$APP_PATH/Contents/MacOS/$APP_NAME" >/dev/null; then
      echo "$APP_NAME is running from $APP_PATH"
      break
    fi
    sleep 0.25
  done

  if ! pgrep -f "$APP_PATH/Contents/MacOS/$APP_NAME" >/dev/null; then
    echo "$APP_NAME did not start after launch." >&2
    exit 1
  fi
fi

if [[ "$VERIFY" -eq 1 ]]; then
  if ! wait_for_accessible_window; then
    if [[ -f "$VERIFY_WINDOW_STATUS_PATH" ]]; then
      echo "$APP_NAME verification window status:" >&2
      cat "$VERIFY_WINDOW_STATUS_PATH" >&2
    fi
    exit 1
  fi
fi

if [[ "$STREAM_LOGS" -eq 1 ]]; then
  trap cleanup EXIT INT TERM
  APP_PID="$(pgrep -f "$APP_PATH/Contents/MacOS/$APP_NAME" | tail -1)"
  echo "$APP_NAME pid: $APP_PID"

  if [[ "$TELEMETRY" -eq 1 ]]; then
    start_watchdog "$APP_PID" "$LOG_DIR"
    echo "Telemetry enabled:"
    echo "  performance: $LOG_DIR/performance.log"
    echo "  stdout:      $LOG_DIR/stdout.log"
    echo "  stderr:      $LOG_DIR/stderr.log"
    echo "  stats:       $LOG_DIR/process-stats.tsv"
    echo "  samples:     $LOG_DIR/samples"
  fi

  /usr/bin/log stream \
    --style compact \
    --info \
    --predicate "process == \"$APP_NAME\" OR subsystem == \"com.cider.app\"" \
    | tee "$LOG_DIR/unified.log"
fi
