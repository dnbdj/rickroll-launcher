#!/usr/bin/env python3
"""Build and verify the two release zips.

The macOS zip has to be written by hand rather than with Compress-Archive:
Windows' zip writer records no unix permissions, so every file extracted on a
Mac came out 0644 and nothing could be executed. That bug shipped once, so this
script now checks its own output - modes, plist, line endings, version - and
exits non-zero instead of producing a broken artifact.

Usage:
    python tools/build-release.py [root] [out] [--version X.Y.Z] [--label N]

--version stamps APP_VERSION inside the packaged Mac app, so the shipped app
reports the version that matches the tag. --label names the files.
"""

import argparse
import pathlib
import plistlib
import re
import sys
import zipfile

VERSION = "1.0.9"
LABEL = "1.0.9"

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

MAC_EXECUTABLES = [
    "Force Stop.command",
    "Rickroll Launcher.app/Contents/MacOS/launch",
    "Rickroll Launcher.app/Contents/Resources/rickroll_mac_gui.py",
    "Rickroll Launcher.app/Contents/Resources/rickroll-mac.sh",
    "Rickroll Launcher.app/Contents/Resources/stop-rickroll-mac.sh",
]

MAC_PLAIN_FILES = [
    "Rickroll Launcher.app/Contents/Info.plist",
    "Rickroll Launcher.app/Contents/Resources/README.txt",
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

FORCE_STOP_NAME = "Force Stop.command"

FORCE_STOP = """#!/bin/bash
# Double-click this when the launcher window is buried under prank windows.
# .command files are opened by Terminal, so this needs no install step.
HERE="$(cd "$(dirname "$0")" && pwd)"
STOP="$HERE/Rickroll Launcher.app/Contents/Resources/stop-rickroll-mac.sh"

if [ ! -f "$STOP" ]; then
  echo "Could not find Rickroll Launcher.app next to this file."
  echo "Keep the app and this script in the same folder."
  printf 'Press return to close.'
  read -r _
  exit 1
fi

bash "$STOP"
printf '\\nPress return to close.'
read -r _ || true
exit 0
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
"Force stop" in the window, or just close the window. If the launcher window is
buried under prank windows, double-click "Force Stop.command" next to the app:
it closes them, says so, and waits for you to press return.

From a terminal:
    bash "Rickroll Launcher.app/Contents/Resources/stop-rickroll-mac.sh"

It also stops itself after the number of seconds you set.

Nothing happened when I opened it
---------------------------------
The app is unsigned, so macOS can refuse it - see "First launch only" above.
If it still does nothing, run this in Terminal and send the file it saves to
your Desktop:

    python3 "Rickroll Launcher.app/Contents/Resources/rickroll_mac_gui.py" --diagnose

That prints your macOS and Python versions, whether the bundle's files are
executable, which browsers it can find, whether the download is quarantined,
and whether GitHub has a newer release.

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


class VerifyError(Exception):
    pass


def as_lf(data):
    return data.replace(b"\r\n", b"\n")


def add(zf, name, data, mode, is_dir=False):
    info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
    info.create_system = 3  # unix, so the mode bits are honoured on extraction
    kind = 0o040000 if is_dir else 0o100000
    info.external_attr = ((mode | kind) << 16)
    info.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(info, b"" if is_dir else as_lf(data))


def stamped(data, version):
    """The Mac app must report the version that is on the tag."""
    text = data.decode("utf-8")
    text, count = re.subn(r'^APP_VERSION = "[^"]*"', f'APP_VERSION = "{version}"', text, count=1, flags=re.M)
    if count != 1:
        raise VerifyError("could not find APP_VERSION in rickroll_mac_gui.py")
    return text.encode("utf-8")


def build_windows(root, out, label):
    path = out / f"rickroll-launcher-windows-beta{label}.zip"
    with zipfile.ZipFile(path, "w") as zf:
        for name in WINDOWS_FILES:
            add(zf, name, (root / name).read_bytes(), 0o644)
    return path


def build_macos(root, out, version, label):
    path = out / f"rickroll-launcher-macos-beta{label}.zip"
    app = "Rickroll Launcher.app"
    gui = stamped((root / "rickroll_mac_gui.py").read_bytes(), version)
    with zipfile.ZipFile(path, "w") as zf:
        add(zf, f"{app}/", b"", 0o755, is_dir=True)
        add(zf, f"{app}/Contents/", b"", 0o755, is_dir=True)
        add(zf, f"{app}/Contents/MacOS/", b"", 0o755, is_dir=True)
        add(zf, f"{app}/Contents/Resources/", b"", 0o755, is_dir=True)
        add(zf, f"{app}/Contents/Info.plist", INFO_PLIST.format(version=version).encode(), 0o644)
        add(zf, f"{app}/Contents/MacOS/launch", LAUNCH.encode(), 0o755)
        add(zf, f"{app}/Contents/Resources/rickroll_mac_gui.py", gui, 0o755)
        add(zf, f"{app}/Contents/Resources/rickroll-mac.sh",
            (root / "rickroll-mac.sh").read_bytes(), 0o755)
        add(zf, f"{app}/Contents/Resources/stop-rickroll-mac.sh",
            (root / "stop-rickroll-mac.sh").read_bytes(), 0o755)
        add(zf, f"{app}/Contents/Resources/README.txt",
            MAC_README.format(label=label).encode(), 0o644)
        add(zf, FORCE_STOP_NAME, FORCE_STOP.encode(), 0o755)
    return path


def mode_of(info):
    return (info.external_attr >> 16) & 0o777


def verify_windows(path):
    with zipfile.ZipFile(path) as zf:
        if zf.testzip() is not None:
            raise VerifyError(f"{path.name}: corrupt entry")
        names = set(zf.namelist())
        missing = [name for name in WINDOWS_FILES if name not in names]
        if missing:
            raise VerifyError(f"{path.name}: missing {', '.join(missing)}")
        for name in names:
            if b"\r\n" in zf.read(name):
                raise VerifyError(f"{path.name}: {name} has CRLF line endings")
    return f"{len(names)} files"


def verify_macos(path, version):
    with zipfile.ZipFile(path) as zf:
        if zf.testzip() is not None:
            raise VerifyError(f"{path.name}: corrupt entry")

        for name in MAC_EXECUTABLES:
            info = zf.getinfo(name)
            if mode_of(info) != 0o755:
                raise VerifyError(f"{name}: mode {oct(mode_of(info))}, expected 0o755")
        for name in MAC_PLAIN_FILES:
            if mode_of(zf.getinfo(name)) != 0o644:
                raise VerifyError(f"{name}: expected mode 0o644")
        for info in zf.infolist():
            if b"\r\n" in zf.read(info):
                raise VerifyError(f"{info.filename}: has CRLF line endings")

        plist = plistlib.loads(zf.read("Rickroll Launcher.app/Contents/Info.plist"))
        if plist.get("CFBundleExecutable") != "launch":
            raise VerifyError("Info.plist does not point at the launch script")
        if plist.get("CFBundleShortVersionString") != version:
            raise VerifyError("Info.plist version does not match --version")
        if "Rickroll Launcher.app/Contents/MacOS/launch" not in zf.namelist():
            raise VerifyError("Info.plist names an executable that is not in the bundle")

        gui = zf.read("Rickroll Launcher.app/Contents/Resources/rickroll_mac_gui.py").decode("utf-8")
        if f'APP_VERSION = "{version}"' not in gui:
            raise VerifyError("packaged Mac app does not carry the release version")
        if "RELEASES_URL" not in gui:
            raise VerifyError("packaged Mac app is missing the update check")

    return f"{len(zf.namelist())} entries, app version {version}"


def main():
    parser = argparse.ArgumentParser(description="Build and verify the release zips.")
    parser.add_argument("root", nargs="?", default=".")
    parser.add_argument("out", nargs="?", default="dist")
    parser.add_argument("--version", default=VERSION)
    parser.add_argument("--label", default=None)
    args = parser.parse_args()

    if not re.fullmatch(r"\d+(\.\d+)*", args.version):
        print(f"FAIL: --version must be a dotted number like 1.0.2, got {args.version!r}", file=sys.stderr)
        return 1

    root = pathlib.Path(args.root).resolve()
    out = pathlib.Path(args.out).resolve()
    label = args.label or LABEL
    out.mkdir(parents=True, exist_ok=True)

    windows = build_windows(root, out, label)
    mac = build_macos(root, out, args.version, label)

    try:
        summary = {
            windows: verify_windows(windows),
            mac: verify_macos(mac, args.version),
        }
    except VerifyError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    for path, detail in summary.items():
        print(f"{path}  {path.stat().st_size} bytes  ({detail})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
