#!/usr/bin/env bash

CIDER_NATIVE_EXECUTABLE_PATTERN="${CIDER_NATIVE_EXECUTABLE_PATTERN:-/Cider[.]app/Contents/MacOS/Cider$}"

stop_native_cider_processes() {
  if pgrep -f "$CIDER_NATIVE_EXECUTABLE_PATTERN" >/dev/null; then
    pkill -TERM -f "$CIDER_NATIVE_EXECUTABLE_PATTERN" || true
    sleep 1
  fi

  if pgrep -f "$CIDER_NATIVE_EXECUTABLE_PATTERN" >/dev/null; then
    pkill -KILL -f "$CIDER_NATIVE_EXECUTABLE_PATTERN" || true
  fi
}

launch_cider_app() {
  "${CIDER_OPEN_COMMAND:-/usr/bin/open}" -n "$@"
}
