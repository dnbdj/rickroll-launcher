#!/bin/bash
# Closes every prank window opened by rickroll-mac.sh, using the throwaway
# browser profile they all share, so your normal browser is never touched.
set -u

PROFILE="${TMPDIR:-/tmp}/rickroll-profile"

if pgrep -f "$PROFILE" >/dev/null 2>&1; then
  pkill -f "$PROFILE"
  echo "Closed the prank windows."
else
  echo "No prank windows found."
fi

rm -rf "$PROFILE"
