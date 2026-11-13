# Rickroll Launcher

A prank app. It opens a pile of browser windows with **Never Gonna Give You Up** playing in every one, spread across several Windows virtual desktops, and then cleans up after itself.

## Download

Grab the latest build from **[Releases](https://github.com/dnbdj/rickroll-launcher/releases)**.

- **Windows** — `rickroll-launcher-windows-*.zip`. Unzip and run `Launcher.cmd`.
- **macOS** — `rickroll-launcher-macos-*.zip`. Unzip and double-click **Rickroll Launcher.app** (first time: right-click → **Open**).

## Windows

Requires Windows 10/11 with the built-in PowerShell 5.1, plus Edge, Chrome or Brave.

`Launcher.cmd` opens the launcher: a dark tabbed window with

- **Prank** — start/stop, force stop, window and duration steppers, and a live summary of the plan
- **Logs** — timestamped, colour-coded channels (`All`, `App`, `Prank`, `Errors`) with a channel picker
- **Leaderboard** — local stats from your own runs: how many, best window count, longest session, and the last five, saved in `leaderboard.json`
- **Updates** — checks GitHub for the newest release on launch; press the button to fetch, or the arrow for release notes and other options

A global panic hotkey (**Ctrl+Alt+Q** by default, configurable in the `...` menu) stops the prank from any desktop, including the ones it created.

Prefer the console? `Rickroll.ps1` takes `-Windows`, `-Desktops`, `-DurationSeconds`, `-DryRun`.

## macOS

The Mac download is a real app bundle: unzip it, double-click **Rickroll Launcher.app**, and that is the whole install. It is unsigned, so the first launch needs a right-click → **Open**; the `README.txt` inside the zip covers that and the quarantine command.

The app is `rickroll_mac_gui.py` on Python 3 + tkinter, wrapped by a small launcher that finds a usable Python and falls back to the terminal version if there isn't one. `rickroll-mac.sh` is that terminal version.

It carries the same update check as Windows: on launch it asks GitHub for the newest release, shows your version and whether it is newer, and turns the button into a link to that release when one is available. The check runs off the main thread, so a slow or missing network never freezes the window.

It keeps the same local leaderboard too — runs, best run, longest run, windows opened and the last run — saved in `~/Library/Application Support/Rickroll Launcher/leaderboard.json`.

If the launcher window ends up buried under eight browser windows, double-click **Force Stop.command** — it sits next to the app in the zip and closes the prank without hunting for the window.

And if nothing happens when you open the app, `--diagnose` writes a report to your Desktop explaining why: macOS and Python versions, whether the bundle's files are executable, which browsers it found, whether the download is still quarantined, and whether GitHub has a newer release.

    python3 "Rickroll Launcher.app/Contents/Resources/rickroll_mac_gui.py" --diagnose

macOS has no public API for creating Spaces, so the Mac build cannot spread windows across desktops — they open on the Space you are on. It has also not been run on real Mac hardware yet.

## Stopping it

| Platform | How |
| --- | --- |
| Windows | `Ctrl+Alt+Q`, the **Force stop** button, or `Stop-Rickroll.cmd` |
| macOS | the **Force stop** button, closing the window, the **Force Stop.command** in the zip, or `bash stop-rickroll-mac.sh` |

Every window runs under a throwaway browser profile in the temp folder, which is how the stop commands close exactly the prank windows and never your real browsing session. Desktops created by the prank are removed on stop unless you tick *Keep desktops on stop*.
