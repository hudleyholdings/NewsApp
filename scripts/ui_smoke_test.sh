#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:-$ROOT_DIR/build/NewsApp.app}"

if [ ! -d "$APP_DIR" ]; then
  echo "Missing app bundle: $APP_DIR"
  exit 1
fi

TMP_HOME="$(mktemp -d)"
LOG_FILE="$ROOT_DIR/build/ui-smoke.log"
SCREENSHOT_FILE="$ROOT_DIR/build/ui-smoke.png"

PID=""
cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_HOME"
}
trap cleanup EXIT

HOME="$TMP_HOME" "$APP_DIR/Contents/MacOS/NewsApp" > "$LOG_FILE" 2>&1 &
PID="$!"

sleep 8

if ! kill -0 "$PID" 2>/dev/null; then
  echo "NewsApp exited during smoke test"
  tail -80 "$LOG_FILE" 2>/dev/null || true
  exit 1
fi

osascript -e 'tell application "System Events" to set frontmost of process "NewsApp" to true' 2>/dev/null || true
sleep 1

osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
  tell process "NewsApp"
    if exists button "Don't Reopen" of window 1 then
      click button "Don't Reopen" of window 1
    end if
  end tell
end tell
APPLESCRIPT
sleep 2

WINDOW_COUNT="$(osascript -e 'tell application "System Events" to count windows of process "NewsApp"' 2>/dev/null || echo unknown)"
if [[ "$WINDOW_COUNT" != "unknown" && "$WINDOW_COUNT" -lt 1 ]]; then
  echo "NewsApp launched but no window was visible"
  tail -80 "$LOG_FILE" 2>/dev/null || true
  exit 1
fi

screencapture -x "$SCREENSHOT_FILE" 2>/dev/null || true

echo "UI smoke passed: pid=$PID windows=$WINDOW_COUNT log=$LOG_FILE screenshot=$SCREENSHOT_FILE"
