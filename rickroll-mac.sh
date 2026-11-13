#!/bin/bash
# Rickroll Launcher - macOS edition, beta 1.0
#
# Opens a pile of Chromium browser windows with "Never Gonna Give You Up"
# playing in each one. Audio is forced on with --autoplay-policy, so nobody
# has to click anything.
#
# Two things macOS does differently from the Windows build:
#   * This is a command line script, not a GUI - the Windows launcher is
#     WinForms, which does not exist on macOS.
#   * macOS has no public API for creating Spaces, so this cannot spread the
#     windows across desktops. Every window opens on the Space you are on.
#     (Ctrl+Right still switches Spaces by hand.)
#
# Every window uses a throwaway profile in $TMPDIR/rickroll-profile, which is
# what lets stop-rickroll-mac.sh close exactly these windows and nothing else.
#
# Usage:
#   chmod +x rickroll-mac.sh stop-rickroll-mac.sh
#   ./rickroll-mac.sh                              # 8 windows, 120 seconds
#   WINDOWS=20 DURATION=300 ./rickroll-mac.sh       # bigger, longer
#   WINDOWS=4 DELAY=0.4 ./rickroll-mac.sh           # quicker flood
#   ./stop-rickroll-mac.sh                          # panic stop
#
# Tested on: nothing yet. This is a beta written on Windows and has not been
# run on a real Mac, so treat the first run as a test.
set -u

WINDOWS="${WINDOWS:-8}"
DURATION="${DURATION:-120}"
DELAY="${DELAY:-0.8}"
URL="${URL:-https://www.youtube.com/watch?v=dQw4w9WgXcQ&autoplay=1}"

PROFILE="${TMPDIR:-/tmp}/rickroll-profile"
HERE="$(cd "$(dirname "$0")" && pwd)"

find_browser() {
  local candidates=(
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
    "/Applications/Chromium.app/Contents/MacOS/Chromium"
  )
  local path
  for path in "${candidates[@]}"; do
    if [ -x "$path" ]; then
      echo "$path"
      return 0
    fi
  done
  return 1
}

if ! BROWSER="$(find_browser)"; then
  echo "No Chromium browser found." >&2
  echo "Install Google Chrome, Brave, Edge or Chromium and try again." >&2
  exit 1
fi

echo "Rickroll (macOS beta 1.0)"
echo "  browser : $BROWSER"
echo "  windows : $WINDOWS"
echo "  runtime : ${DURATION}s, then it cleans up"
echo "  video   : $URL"
echo
printf "Continue? [y/N] "
read -r answer
case "$answer" in
  y | Y | yes | YES) ;;
  *)
    echo "Bailed out."
    exit 0
    ;;
esac

cleanup() {
  bash "$HERE/stop-rickroll-mac.sh" >/dev/null 2>&1
}

trap cleanup INT TERM

open_window() {
  "$BROWSER" \
    --new-window \
    --user-data-dir="$PROFILE" \
    --no-first-run \
    --no-default-browser-check \
    --start-maximized \
    --disable-sync \
    --autoplay-policy=no-user-gesture-required \
    "$URL" >/dev/null 2>&1 &
}

count=1
while [ "$count" -le "$WINDOWS" ]; do
  open_window
  echo "  window $count of $WINDOWS"
  count=$((count + 1))
  sleep "$DELAY"
done

echo
echo "Live. Ctrl+C to stop, or run ./stop-rickroll-mac.sh"
echo "It also stops itself after ${DURATION} seconds."
sleep "$DURATION"

cleanup
echo "Cleaned up. You know the rules, and so do I."
