# Rickroll Launcher

A prank app. It opens a pile of browser windows with **Never Gonna Give You Up** playing in every one, spread across several Windows virtual desktops, and then cleans up after itself.

## Download

Grab the latest build from **[Releases](https://github.com/dnbdj/rickroll-launcher/releases)**.

- **Windows** — `rickroll-launcher-windows-beta1.0.zip`. Unzip and run `Launcher.cmd`.
- **macOS** — `rickroll-launcher-macos-beta1.0.zip`. Run `python3 rickroll_mac_gui.py`.

## Windows

Requires Windows 10/11 with the built-in PowerShell 5.1, plus Edge, Chrome or Brave.

`Launcher.cmd` opens the launcher: a dark tabbed window with

- **Prank** — start/stop, force stop, window and duration steppers, and a live summary of the plan
- **Logs** — timestamped, colour-coded channels (`All`, `App`, `Prank`, `Errors`) with a channel picker
- **Leaderboard** — placeholder, scoring format still to be decided
- **Updates** — checks a manifest on launch; press the button to fetch, or the arrow for release notes and other options

A global panic hotkey (**Ctrl+Alt+Q** by default, configurable in the `...` menu) stops the prank from any desktop, including the ones it created.

Prefer the console? `Rickroll.ps1` takes `-Windows`, `-Desktops`, `-DurationSeconds`, `-DryRun`.

## macOS

`rickroll_mac_gui.py` is the same flow built on Python 3 + tkinter, so nothing needs installing beyond Python itself. The bash script `rickroll-mac.sh` does the same from a terminal.

macOS has no public API for creating Spaces, so the Mac build cannot spread windows across desktops — they open on the Space you are on. It has also not been run on real Mac hardware yet.

## Stopping it

| Platform | How |
| --- | --- |
| Windows | `Ctrl+Alt+Q`, the **Force stop** button, or `Stop-Rickroll.cmd` |
| macOS | the **Force stop** button, closing the window, or `./stop-rickroll-mac.sh` |

Every window runs under a throwaway browser profile in the temp folder, which is how the stop commands close exactly the prank windows and never your real browsing session. Desktops created by the prank are removed on stop unless you tick *Keep desktops on stop*.
