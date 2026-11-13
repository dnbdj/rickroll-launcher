#!/usr/bin/env python3
"""Build the two release zips.

The macOS zip has to be written by hand rather than with Compress-Archive:
Windows' zip writer records no unix permissions, so every file extracted on a
Mac came out 0644 and nothing could be executed. This sets the mode bits
(0755 on scripts) and wraps everything in a real .app bundle, so a download is
double-clickable instead of "permission denied" and a file with no icon.

Usage:
    python tools/build-release.py <repo-root> <output-dir>
"""

import os
import pathlib
import sys
import zipfile

VERSION = "1.0.1"
LABEL = "1.1"

WINDOWS_FILES = [
    "Launcher.ps1",
    "Launcher.cmd",
    "Rickroll.Core.psm1",
    "Rickroll.UI.ps1",
    "Rickroll.ps1",
    "Rickroll.cmd",
    "Stop-Rickroll.ps1",
    "Stop-Rickroll.cmd",
]

INFO_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Rickroll Launcher</string>
    <key>CFBundleDisplayName</key>
    <string>Rickroll Launcher</string>
    <key>CFBundleIdentifier</key>
    <string>com.dnbdj.rickroll-launcher</string>
    <key>CFBundleVersion</key>
    <string>{version}</string>
    <key>CFBundleShortVersionString</key>
    <string>{version}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>launch</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.13</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
"""

LAUNCH = """#!/bin/bash
# Finder runs this on double-click. The app is only Python and shell scripts,
# so this script is the installation: find a Python 3 that has tkinter and
# start the GUI, otherwise open the terminal version, which needs only bash.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
RES="$(cd "$HERE/../Resources" && pwd)"

# Modes survive this zip, but repair them anyway: some extractors drop them.
chmod +x "$RES/rickroll_mac_gui.py" "$RES/rickroll-mac.sh" "$RES/stop-rickroll-mac.sh" 2>/dev/null

for candidate in "$(command -v python3 2>/dev/null)" /usr/bin/python3 /usr/local/bin/python3 /opt/homebrew/bin/python3; do
  [ -n "$candidate" ] || continue
  [ -x "$candidate" ] || continue
  if "$candidate" -c 'import tkinter' >/dev/null 2>&1; then
    exec "$candidate" "$RES/rickroll_mac_gui.py"
  fi
done

# No Python 3 with tkinter: run the shell version in Terminal instead.
exec /usr/bin/open -a Terminal "$RES/rickroll-mac.sh"
"""

MAC_README = """Rickroll Launcher - macOS beta {label}
====================================

Double-click "Rickroll Launcher.app". That is the whole install: no pip, no
packages, nothing to move into /Applications (though you can).

First launch only
-----------------
The app is not signed with an Apple developer certificate, so macOS refuses it
once with "cannot be opened because the developer cannot be verified". Fix it
by right-clicking (or Control-clicking) the app, choosing Open, then Open
again. After that it opens normally.

If macOS still refuses it, clear the download flag in Terminal:
    xattr -dr com.apple.quarantine "Rickroll Launcher.app"

What it needs
-------------
* Google Chrome, Brave, Microsoft Edge or Chromium - the first one it finds.
* Python 3 with tkinter. macOS provides this with:
      xcode-select --install
  Without it the app opens the terminal version instead, which needs only bash,
  so it still runs.

Stopping
--------
"Force stop" in the window, or just close the window, or from a terminal:
    bash stop-rickroll-mac.sh
It also stops itself after the number of seconds you set.

One limitation
--------------
macOS has no public API for creating Spaces, so unlike the Windows build this
cannot spread windows across desktops. Every window opens on the Space you are
on.

Terminal version
----------------
    bash rickroll-mac.sh                            # 8 windows, 120 seconds
    WINDOWS=20 DURATION=300 bash rickroll-mac.sh
"""


def as_lf(data):
    return data.replace(b"\r\n", b"\n")


def add(zf, name, data, mode, is_dir=False):
    info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
    info.create_system = 3  # unix, so the mode bits are honoured on extraction
    kind = 0o040000 if is_dir else 0o100000
    info.external_attr = ((mode | kind) << 16)
    info.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(info, b"" if is_dir else as_lf(data))


def build_windows(root, out):
    path = out / f"rickroll-launcher-windows-beta{LABEL}.zip"
    with zipfile.ZipFile(path, "w") as zf:
        for name in WINDOWS_FILES:
            add(zf, name, (root / name).read_bytes(), 0o644)
    return path


def build_macos(root, out):
    path = out / f"rickroll-launcher-macos-beta{LABEL}.zip"
    app = "Rickroll Launcher.app"
    with zipfile.ZipFile(path, "w") as zf:
        add(zf, f"{app}/", b"", 0o755, is_dir=True)
        add(zf, f"{app}/Contents/", b"", 0o755, is_dir=True)
        add(zf, f"{app}/Contents/MacOS/", b"", 0o755, is_dir=True)
        add(zf, f"{app}/Contents/Resources/", b"", 0o755, is_dir=True)
        add(zf, f"{app}/Contents/Info.plist", INFO_PLIST.format(version=VERSION).encode(), 0o644)
        add(zf, f"{app}/Contents/MacOS/launch", LAUNCH.encode(), 0o755)
        add(zf, f"{app}/Contents/Resources/rickroll_mac_gui.py",
            (root / "rickroll_mac_gui.py").read_bytes(), 0o755)
        add(zf, f"{app}/Contents/Resources/rickroll-mac.sh",
            (root / "rickroll-mac.sh").read_bytes(), 0o755)
        add(zf, f"{app}/Contents/Resources/stop-rickroll-mac.sh",
            (root / "stop-rickroll-mac.sh").read_bytes(), 0o755)
        add(zf, f"{app}/Contents/Resources/README.txt",
            MAC_README.format(label=LABEL).encode(), 0o644)
    return path


def main():
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    out = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "dist").resolve()
    out.mkdir(parents=True, exist_ok=True)
    for path in (build_windows(root, out), build_macos(root, out)):
        print(f"{path}  {os.path.getsize(path)} bytes")


if __name__ == "__main__":
    main()
