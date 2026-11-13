#!/usr/bin/env python3
"""Rickroll Launcher - macOS GUI (beta 1.1).

A tkinter front-end for the prank: opens a pile of Chromium browser windows
with the song playing in each one, then cleans up after itself.

Why this exists: the Windows launcher is WinForms plus Win32 calls, neither of
which exist on macOS. This is the same prank rebuilt on core Python so it runs
on a Mac with no installs at all (tkinter ships with Python 3).

One honest limitation: macOS has no public API for creating Spaces, so this
cannot spread windows across desktops the way the Windows build does. Every
window opens on the Space you are currently on.

Usage:
    python3 rickroll_mac_gui.py
    python3 rickroll_mac_gui.py --selftest

Requires: Google Chrome, Brave, Edge or Chromium installed.
"""

import json
import os
import pathlib
import platform
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import tkinter as tk
from tkinter import messagebox
from urllib.request import Request, urlopen

APP_VERSION = "1.0.6"
RELEASES_URL = "https://api.github.com/repos/dnbdj/rickroll-launcher/releases"

# The selftest points this at a temp file so it never touches real stats.
_STATS_OVERRIDE = {"path": None}
VIDEO_URL = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&autoplay=1"

BROWSER_PATHS = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
]

BG = "#0E0F15"
CARD = "#161824"
INNER = "#1B1E2C"
STROKE = "#272A3C"
TEXT = "#E8E9F0"
MUTED = "#8A8FA6"
ACCENT = "#FF2E74"
ACCENT_HI = "#FF4E8B"
ACCENT_LO = "#D6215E"
LIVE_BG = "#241C2C"
LIVE_LINE = "#4A2340"
DANGER = "#FF6B6B"
DANGER_BG = "#2A1B22"

FONT = "Helvetica Neue"
STEP_DELAY_MS = 800


def stats_file():
    """Where the leaderboard lives. Not next to the app: the bundle is replaced
    on update, and Application Support is where a Mac app is expected to write.
    """
    if _STATS_OVERRIDE["path"]:
        return pathlib.Path(_STATS_OVERRIDE["path"])
    if sys.platform == "darwin":
        base = pathlib.Path.home() / "Library" / "Application Support" / "Rickroll Launcher"
    else:
        base = pathlib.Path.home() / ".rickroll-launcher"
    return base / "leaderboard.json"


def format_duration(seconds):
    if seconds <= 0:
        return "0s"
    if seconds < 60:
        return f"{seconds}s"
    minutes, rest = divmod(int(seconds), 60)
    if minutes < 60:
        return f"{minutes}m {rest:02d}s"
    hours, minutes = divmod(minutes, 60)
    return f"{hours}h {minutes:02d}m"


def version_tuple(text):
    """'v1.0.2-beta' -> (1, 0, 2). Anything unparseable gives ()."""
    parts = []
    for chunk in str(text).strip().lower().lstrip("v").split("-")[0].split("."):
        if not chunk.isdigit():
            break
        parts.append(int(chunk))
    return tuple(parts)


def newest_release(payload):
    """Newest published release in a GitHub releases payload, or None.

    Drafts are skipped and prereleases count, so a beta channel still sees new
    builds - the same rule the Windows launcher applies.
    """
    best = None
    for release in payload if isinstance(payload, list) else []:
        if not isinstance(release, dict):
            continue
        if release.get("draft") or not release.get("published_at"):
            continue
        if not version_tuple(release.get("tag_name", "")):
            continue
        if best is None or release["published_at"] > best["published_at"]:
            best = release
    if best is None:
        return None
    tag = str(best.get("tag_name", ""))
    return {
        "version": version_tuple(tag),
        "label": tag.lstrip("vV") or tag,
        "url": best.get("html_url") or "",
        "notes": best.get("body") or "",
    }


def fetch_releases(url=RELEASES_URL, timeout=10):
    """The repository's releases, straight from the GitHub API."""
    request = Request(url, headers={
        "User-Agent": f"RickrollLauncher/{APP_VERSION}",
        "Accept": "application/vnd.github+json",
    })
    with urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def collect_diagnostics():
    """Everything that could explain "nothing happens" on a Mac.

    Plain text, so it can be pasted into a chat. Deliberately opens no windows
    and needs no display.
    """
    lines = []

    def add(text=""):
        lines.append(text)

    add(f"Rickroll Launcher {APP_VERSION} - diagnostics")
    add(f"when           : {time.strftime('%Y-%m-%d %H:%M:%S')}")
    mac_version = platform.mac_ver()[0]
    add(f"macOS          : {mac_version or 'not macOS (' + platform.system() + ')'}")
    add(f"machine        : {platform.machine()}")
    add(f"python         : {sys.version.split()[0]} at {sys.executable}")

    try:
        import tkinter as _tk
        add(f"tkinter        : {_tk.TkVersion}")
    except Exception as exc:  # noqa: BLE001
        add(f"tkinter        : MISSING ({exc}) - the GUI cannot start, the terminal version still can")

    gui = pathlib.Path(__file__).resolve()
    add(f"gui script     : {gui}")
    for name in ("rickroll_mac_gui.py", "rickroll-mac.sh", "stop-rickroll-mac.sh"):
        path = gui.parent / name
        state = "ok" if path.exists() else "MISSING"
        mode = "executable" if os.access(path, os.X_OK) else "NOT executable"
        add(f"  {name:<24} {state}, {mode}")

    try:
        app_dir = gui.parents[2]
    except IndexError:
        app_dir = None
    if app_dir is not None and app_dir.suffix == ".app":
        add(f"bundle         : {app_dir}")
    else:
        add("bundle         : not running from a .app (fine if you launched the .py directly)")

    add("browsers       :")
    for path in BROWSER_PATHS:
        found = os.path.isfile(path) and os.access(path, os.X_OK)
        add(f"  {'found  ' if found else 'missing'} {path}")
    for name in ("google-chrome", "chromium", "brave-browser", "microsoft-edge"):
        add(f"  which {name}: {shutil.which(name) or 'not found'}")

    try:
        handle, probe = tempfile.mkstemp(prefix="rickroll-write-test")
        os.close(handle)
        os.remove(probe)
        add(f"temp dir       : {tempfile.gettempdir()} (writable)")
    except Exception as exc:  # noqa: BLE001
        add(f"temp dir       : {tempfile.gettempdir()} (NOT writable: {exc})")

    if sys.platform == "darwin" and app_dir is not None:
        try:
            result = subprocess.run(
                ["xattr", "-p", "com.apple.quarantine", str(app_dir)],
                capture_output=True, text=True, timeout=5, check=False,
            )
            value = result.stdout.strip()
            add(f"quarantine     : {value or 'none'}")
            if value:
                add("                 macOS will refuse the first launch until you right-click > Open,")
                add("                 or clear it with: xattr -dr com.apple.quarantine \"Rickroll Launcher.app\"")
        except Exception as exc:  # noqa: BLE001
            add(f"quarantine     : could not read ({exc})")

    try:
        runs = json.loads(stats_file().read_text(encoding="utf-8")).get("Runs") or []
        add(f"leaderboard    : {len(runs)} run(s) at {stats_file()}")
    except (OSError, ValueError):
        add(f"leaderboard    : no runs saved yet ({stats_file()})")

    try:
        found = newest_release(fetch_releases())
        if found is None:
            add("latest release : none published")
        else:
            current = version_tuple(APP_VERSION)
            newer = bool(current) and found["version"] > current
            add(f"latest release : {found['label']} ({'newer than this build' if newer else 'same or older'})")
            add(f"                 {found['url']}")
    except Exception as exc:  # noqa: BLE001 - offline is a normal answer here
        add(f"latest release : check failed ({exc})")

    return lines


def diagnose():
    text = "\n".join(collect_diagnostics())
    print(text)

    target = pathlib.Path.home() / "Desktop"
    if not target.is_dir():
        target = pathlib.Path(tempfile.gettempdir())
    path = target / "rickroll-diagnose.txt"
    try:
        path.write_text(text + "\n", encoding="utf-8")
        print(f"\nSaved a copy to {path}")
    except Exception as exc:  # noqa: BLE001
        print(f"\nCould not save a copy: {exc}")
    return 0


class FlatButton(tk.Frame):
    """A flat, dark button. tk.Button ignores colours on macOS, a Label does not."""

    def __init__(self, parent, text, command, bg, hover, press, fg, font, padx=22, pady=11):
        super().__init__(parent, bg=bg, highlightthickness=0, bd=0)
        self._command = command
        self._enabled = True
        self._bg = bg
        self._hover = hover
        self._press = press
        self._fg = fg
        self._label = tk.Label(self, text=text, bg=bg, fg=fg, font=font, padx=padx, pady=pady, cursor="hand2")
        self._label.pack(fill="both", expand=True)
        for widget in (self, self._label):
            widget.bind("<Enter>", self._on_enter)
            widget.bind("<Leave>", self._on_leave)
            widget.bind("<ButtonPress-1>", self._on_press)
            widget.bind("<ButtonRelease-1>", self._on_release)

    def _paint(self, bg):
        if not self._enabled:
            return
        self.configure(bg=bg)
        self._label.configure(bg=bg)

    def _on_enter(self, _event):
        self._paint(self._hover)

    def _on_leave(self, _event):
        self._paint(self._bg)

    def _on_press(self, _event):
        self._paint(self._press)

    def _on_release(self, _event):
        self._paint(self._hover)
        if self._enabled and self._command:
            self._command()

    def set_text(self, text):
        self._label.configure(text=text)

    def set_colors(self, bg, hover, press, fg):
        self._bg, self._hover, self._press = bg, hover, press
        # Store fg too: set_enabled() repaints from these fields, so a colour set
        # here used to be overwritten the next time the button was enabled.
        self._fg = fg
        self.configure(bg=bg)
        self._label.configure(bg=bg, fg=fg)

    def set_enabled(self, enabled):
        self._enabled = enabled
        self._label.configure(cursor="hand2" if enabled else "arrow")
        if not enabled:
            self.configure(bg=INNER)
            self._label.configure(bg=INNER, fg=MUTED)
        else:
            self._paint(self._bg)
            self._label.configure(fg=self._fg)


class Stepper(tk.Frame):
    """A small - value + control, matching the Windows launcher's steppers."""

    def __init__(self, parent, label, value, minimum, maximum, step, on_change):
        super().__init__(parent, bg=INNER, highlightbackground=STROKE, highlightthickness=1, bd=0)
        self.value = value
        self.minimum = minimum
        self.maximum = maximum
        self.step = step
        self.on_change = on_change

        tk.Label(self, text=label.upper(), bg=INNER, fg=MUTED, font=(FONT, 9)).grid(row=0, column=0, columnspan=3, sticky="w", padx=10, pady=(8, 2))

        self._minus = FlatButton(self, "-", self._dec, INNER, STROKE, STROKE, TEXT, (FONT, 13, "bold"), padx=7, pady=1)
        self._minus.grid(row=1, column=0, padx=(8, 2), pady=(0, 8))

        self._value_label = tk.Label(self, text=str(value), bg=INNER, fg=TEXT, font=(FONT, 13, "bold"), width=4)
        self._value_label.grid(row=1, column=1, pady=(0, 8))

        self._plus = FlatButton(self, "+", self._inc, INNER, STROKE, STROKE, TEXT, (FONT, 13, "bold"), padx=7, pady=1)
        self._plus.grid(row=1, column=2, padx=(2, 8), pady=(0, 8))

    def _apply(self, delta):
        new_value = max(self.minimum, min(self.maximum, self.value + delta))
        if new_value != self.value:
            self.value = new_value
            self._value_label.configure(text=str(new_value))
        self.on_change()

    def _dec(self):
        self._apply(-self.step)

    def _inc(self):
        self._apply(self.step)

    def get(self):
        return self.value


class Launcher(tk.Tk):
    def __init__(self, auto_check=True):
        super().__init__()
        self.title("Rickroll Launcher")
        self.configure(bg=BG)
        self.geometry("880x620")
        self.minsize(760, 520)

        self.profile_dir = os.path.join(tempfile.gettempdir(), "rickroll-profile")
        self.running = False
        self.opened = 0
        self.total = 0
        self.ends_at = None
        self.browser = None
        self.procs = []
        self.job = None
        self.started_at = None
        self.runs = []
        self.update_state = "idle"
        self.update_info = None  # not "update": that name is tkinter's own method
        self.log_entries = []
        self.log_channel = "All"
        self.current_page = "Prank"
        self.pages = {}
        self.nav_buttons = {}
        self._update_result = None
        self._update_deadline = 0.0

        self._build_ui()
        self.protocol("WM_DELETE_WINDOW", self._on_close)
        self.log("Launcher ready.", "quiet")
        self.log(f"Prank profile: {self.profile_dir}", "quiet")
        self.log("Panic stop: press Force stop. Closing this window also cleans up.", "quiet")
        self.runs = self._load_runs()
        self._render_stats()
        if auto_check:
            self.after(600, lambda: self._check_updates(auto=True))

    # ---------------------------------------------------------------- layout

    def _build_ui(self):
        shell = tk.Frame(self, bg=BG)
        shell.pack(fill="both", expand=True)

        sidebar = tk.Frame(shell, bg="#0B0C12", width=156)
        sidebar.pack(side="left", fill="y")
        sidebar.pack_propagate(False)

        brand = tk.Frame(sidebar, bg="#0B0C12")
        brand.pack(fill="x", padx=14, pady=(18, 2))
        tk.Label(brand, text="Rickroll", bg="#0B0C12", fg=TEXT, font=(FONT, 17, "bold")).pack(anchor="w")
        tk.Label(brand, text=f"macOS beta {APP_VERSION}", bg="#0B0C12", fg=MUTED, font=(FONT, 9)).pack(anchor="w")

        self.nav_buttons = {}
        for key, glyph in (("Prank", "\u25b6"), ("Logs", "\u2261"), ("Leaderboard", "\u2605"), ("Updates", "\u21bb")):
            button = FlatButton(sidebar, f"{glyph}  {key}", lambda name=key: self._show_page(name),
                                "#0B0C12", INNER, INNER, MUTED, (FONT, 11), padx=10, pady=7)
            button.pack(fill="x", padx=10, pady=2)
            self.nav_buttons[key] = button

        content = tk.Frame(shell, bg=BG)
        content.pack(side="left", fill="both", expand=True)

        footer = tk.Frame(content, bg=BG)
        footer.pack(side="bottom", fill="x", padx=18, pady=(0, 12))
        self.version_label = tk.Label(footer, text=f"v{APP_VERSION}", bg=BG, fg=MUTED, font=(FONT, 10))
        self.version_label.pack(side="right")
        self.status_dot = tk.Label(footer, text="\u25cf", bg=BG, fg=MUTED, font=(FONT, 11))
        self.status_dot.pack(side="left")
        self.status_label = tk.Label(footer, text="Idle", bg=BG, fg=MUTED, font=(FONT, 11))
        self.status_label.pack(side="left", padx=(6, 0))

        host = tk.Frame(content, bg=BG)
        host.pack(side="top", fill="both", expand=True)

        self.pages = {}
        for key in ("Prank", "Logs", "Leaderboard", "Updates"):
            page = tk.Frame(host, bg=BG)
            page.place(x=0, y=0, relwidth=1, relheight=1)
            self.pages[key] = page

        self._build_prank_page(self.pages["Prank"])
        self._build_logs_page(self.pages["Logs"])
        self._build_board_page(self.pages["Leaderboard"])
        self._build_updates_page(self.pages["Updates"])
        self._show_page("Prank")

    def _show_page(self, key):
        page = self.pages.get(key)
        if page is None:
            return
        self.current_page = key
        page.tkraise()
        for name, button in self.nav_buttons.items():
            active = (name == key)
            button.set_colors(INNER if active else "#0B0C12", INNER, INNER, ACCENT if active else MUTED)
            button.set_enabled(True)

    def _build_prank_page(self, page):
        header = tk.Frame(page, bg=BG)
        header.pack(fill="x", padx=18, pady=(16, 8))
        tk.Label(header, text="Prank", bg=BG, fg=TEXT, font=(FONT, 16, "bold")).pack(side="left")
        tk.Label(header, text="  plan it, then press start", bg=BG, fg=MUTED, font=(FONT, 10)).pack(side="left", pady=(4, 0))

        controls = tk.Frame(page, bg=CARD, highlightbackground=STROKE, highlightthickness=1)
        controls.pack(fill="x", padx=18, pady=(2, 10))
        inner = tk.Frame(controls, bg=CARD)
        inner.pack(fill="x", padx=14, pady=14)

        self.start_button = FlatButton(inner, "Start prank  \u25b6", self._toggle, ACCENT, ACCENT_HI, ACCENT_LO, "#FFFFFF", (FONT, 14, "bold"))
        self.start_button.pack(side="left")

        self.force_button = FlatButton(inner, "Force stop", self._force_stop, INNER, DANGER_BG, DANGER_BG, DANGER, (FONT, 11, "bold"))
        self.force_button.pack(side="left", padx=(10, 0))

        # Packed right to left, so this reads Windows then Seconds like the Windows app.
        self.duration_stepper = Stepper(inner, "Seconds", 120, 0, 3600, 30, self._on_option_change)
        self.duration_stepper.pack(side="right")
        self.windows_stepper = Stepper(inner, "Windows", 8, 1, 40, 1, self._on_option_change)
        self.windows_stepper.pack(side="right", padx=(0, 8))

        self.plan_label = tk.Label(page, text="", bg=BG, fg="#BFC4D6", font=(FONT, 10), anchor="w", justify="left")
        self.plan_label.pack(fill="x", padx=20)

        tk.Label(page, text="macOS cannot create Spaces from a script, so every window opens on the Space you are on.",
                 bg=BG, fg=MUTED, font=(FONT, 9), anchor="w").pack(fill="x", padx=20, pady=(4, 0))
        self.plan_label.configure(text=self._plan_text())

    def _build_logs_page(self, page):
        card = tk.Frame(page, bg=CARD, highlightbackground=STROKE, highlightthickness=1)
        card.pack(fill="both", expand=True, padx=18, pady=(16, 12))

        header = tk.Frame(card, bg=CARD)
        header.pack(fill="x", padx=12, pady=(10, 6))
        tk.Label(header, text="Logs", bg=CARD, fg=TEXT, font=(FONT, 13, "bold")).pack(side="left")
        FlatButton(header, "Clear", self._clear_log, CARD, INNER, INNER, MUTED, (FONT, 10), padx=12, pady=3).pack(side="right")

        self.channel_buttons = {}
        for name in ("Errors", "Prank", "App", "All"):
            button = FlatButton(header, name, lambda channel=name: self._set_log_channel(channel),
                                INNER, STROKE, STROKE, MUTED, (FONT, 9), padx=9, pady=3)
            button.pack(side="right", padx=(0, 4))
            self.channel_buttons[name] = button

        self.log_box = tk.Text(card, bg="#101220", fg="#C3C8D8", insertbackground=TEXT, relief="flat", bd=0, wrap="none", font=("Menlo", 11), padx=10, pady=8)
        self.log_box.pack(fill="both", expand=True, padx=12, pady=(0, 12))
        for tag, colour in (("time", "#5A5F73"), ("info", "#C3C8D8"), ("ok", "#4ADE80"),
                            ("warn", "#FBBF24"), ("err", "#FF6B6B"), ("quiet", "#7C8299")):
            self.log_box.tag_configure(tag, foreground=colour)
        self.log_box.configure(state="disabled")
        self._paint_channels()

    def _build_board_page(self, page):
        header = tk.Frame(page, bg=BG)
        header.pack(fill="x", padx=18, pady=(16, 8))
        tk.Label(header, text="Leaderboard", bg=BG, fg=TEXT, font=(FONT, 16, "bold")).pack(side="left")
        tk.Label(header, text="  on this Mac", bg=BG, fg=MUTED, font=(FONT, 10)).pack(side="left", pady=(4, 0))
        self.reset_button = FlatButton(header, "Reset", self._reset_stats, INNER, STROKE, STROKE, MUTED, (FONT, 9), padx=12, pady=3)
        self.reset_button.pack(side="right")

        stats = tk.Frame(page, bg=CARD, highlightbackground=STROKE, highlightthickness=1)
        stats.pack(fill="x", padx=18, pady=(2, 10))
        stats_inner = tk.Frame(stats, bg=CARD)
        stats_inner.pack(fill="x", padx=14, pady=12)

        self.stat_values = {}
        for key, caption in (("Runs", "RUNS"), ("Best", "BEST RUN"), ("Longest", "LONGEST RUN"), ("Windows", "WINDOWS OPENED")):
            column = tk.Frame(stats_inner, bg=CARD)
            column.pack(side="left", padx=(0, 30))
            tk.Label(column, text=caption, bg=CARD, fg=MUTED, font=(FONT, 8)).pack(anchor="w")
            value = tk.Label(column, text="-", bg=CARD, fg=TEXT, font=(FONT, 15, "bold"))
            value.pack(anchor="w")
            self.stat_values[key] = value

        tk.Label(page, text="RECENT RUNS", bg=BG, fg=MUTED, font=(FONT, 8)).pack(anchor="w", padx=20)

        self.board_empty = tk.Label(page, text="No runs yet - start the prank, stop it, and it lands here.",
                                    bg=BG, fg=MUTED, font=(FONT, 10))
        self.board_rows = []
        for _ in range(5):
            row = tk.Frame(page, bg=INNER, highlightbackground=STROKE, highlightthickness=1)
            when = tk.Label(row, text="", bg=INNER, fg=TEXT, font=(FONT, 10), anchor="w", width=18)
            count = tk.Label(row, text="", bg=INNER, fg="#BFC4D6", font=(FONT, 10), anchor="w")
            duration = tk.Label(row, text="", bg=INNER, fg=TEXT, font=(FONT, 10, "bold"), anchor="e")
            when.pack(side="left", padx=(12, 0))
            count.pack(side="left", padx=(16, 0))
            duration.pack(side="right", padx=(0, 12))
            self.board_rows.append({"frame": row, "when": when, "windows": count, "duration": duration})
        self._pack_board_rows()

    def _build_updates_page(self, page):
        header = tk.Frame(page, bg=BG)
        header.pack(fill="x", padx=18, pady=(16, 8))
        tk.Label(header, text="Updates", bg=BG, fg=TEXT, font=(FONT, 16, "bold")).pack(side="left")
        tk.Label(header, text="  straight from GitHub", bg=BG, fg=MUTED, font=(FONT, 10)).pack(side="left", pady=(4, 0))

        card = tk.Frame(page, bg=CARD, highlightbackground=STROKE, highlightthickness=1)
        card.pack(fill="x", padx=18, pady=(2, 10))
        inner = tk.Frame(card, bg=CARD)
        inner.pack(fill="x", padx=16, pady=16)

        tk.Label(inner, text="INSTALLED VERSION", bg=CARD, fg=MUTED, font=(FONT, 8)).grid(row=0, column=0, sticky="w")
        tk.Label(inner, text=f"v{APP_VERSION}", bg=CARD, fg=TEXT, font=(FONT, 12, "bold")).grid(row=1, column=0, sticky="w", pady=(2, 12))

        tk.Label(inner, text="LATEST AVAILABLE", bg=CARD, fg=MUTED, font=(FONT, 8)).grid(row=0, column=1, sticky="w", padx=(40, 0))
        self.latest_value = tk.Label(inner, text="not checked", bg=CARD, fg="#BFC4D6", font=(FONT, 12, "bold"))
        self.latest_value.grid(row=1, column=1, sticky="w", padx=(40, 0), pady=(2, 12))

        tk.Label(inner, text="LAST CHECKED", bg=CARD, fg=MUTED, font=(FONT, 8)).grid(row=2, column=0, sticky="w")
        self.last_checked_value = tk.Label(inner, text="never", bg=CARD, fg="#BFC4D6", font=(FONT, 10))
        self.last_checked_value.grid(row=3, column=0, sticky="w")

        self.update_button = FlatButton(inner, "Check for updates", self._update_click, ACCENT, ACCENT_HI, ACCENT_LO, "#FFFFFF", (FONT, 11, "bold"), padx=18, pady=9)
        self.update_button.grid(row=3, column=1, sticky="w", padx=(40, 0))

        self.update_notes = tk.Label(page, text="Asks api.github.com for the newest release, prereleases included.",
                                     bg=BG, fg=MUTED, font=(FONT, 9), justify="left", anchor="nw", wraplength=520)
        self.update_notes.pack(fill="both", expand=True, padx=20, pady=(4, 12), anchor="w")

    # ------------------------------------------------------------------ log

    def log(self, message, level="info", channel="App"):
        entry = {
            "time": time.strftime("%H:%M:%S"),
            "level": level,
            "message": message,
            "channel": channel,
        }
        self.log_entries.append(entry)
        if len(self.log_entries) > 400:
            del self.log_entries[:-400]
        if self._shows(entry):
            self._append_log(entry)

    def _shows(self, entry):
        if self.log_channel == "All":
            return True
        if self.log_channel == "Errors":
            return entry["level"] in ("warn", "err")
        return entry["channel"] == self.log_channel

    def _append_log(self, entry):
        self.log_box.configure(state="normal")
        self.log_box.insert("end", entry["time"] + "  ", ("time",))
        self.log_box.insert("end", entry["message"] + "\n", (entry["level"],))
        self.log_box.see("end")
        self.log_box.configure(state="disabled")

    def _render_log(self):
        self.log_box.configure(state="normal")
        self.log_box.delete("1.0", "end")
        self.log_box.configure(state="disabled")
        for entry in self.log_entries:
            if self._shows(entry):
                self._append_log(entry)

    def _paint_channels(self):
        for name, button in self.channel_buttons.items():
            active = (name == self.log_channel)
            button.set_colors(STROKE if active else INNER, STROKE, STROKE, ACCENT if active else MUTED)
            button.set_enabled(True)

    def _set_log_channel(self, name):
        self.log_channel = name
        self._paint_channels()
        self._render_log()

    def _clear_log(self):
        self.log_entries = []
        self._render_log()

    # --------------------------------------------------------------- status

    def _set_status(self, text, color=MUTED):
        self.status_label.configure(text=text, fg=color)
        self.status_dot.configure(fg=color)

    def _plan_text(self):
        windows = self.windows_stepper.get()
        seconds = self.duration_stepper.get()
        if seconds > 0:
            return f"Plan: {windows} window(s) on this Space, auto-stop after {seconds}s."
        return f"Plan: {windows} window(s) on this Space, runs until you stop it."

    def _on_option_change(self):
        if hasattr(self, "plan_label"):
            self.plan_label.configure(text=self._plan_text())
        self.log(self._plan_text(), "quiet")

    # ---------------------------------------------------------- leaderboard

    def _load_runs(self):
        try:
            data = json.loads(stats_file().read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return []
        runs = data.get("Runs") if isinstance(data, dict) else None
        return [run for run in (runs or []) if isinstance(run, dict)]

    def _save_runs(self, runs):
        path = stats_file()
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps({"Runs": runs[:50]}, indent=2), encoding="utf-8")
        except OSError as exc:
            self.log(f"Could not save the leaderboard: {exc}", "warn")

    def _record_run(self, seconds, forced):
        if self.opened <= 0 and seconds <= 0:
            return
        runs = self._load_runs()
        runs.insert(0, {
            "At": time.strftime("%Y-%m-%d %H:%M"),
            "Windows": int(self.opened),
            "Seconds": int(seconds),
            "Forced": bool(forced),
        })
        self._save_runs(runs)
        self.runs = runs[:50]
        self._render_stats()

    def _render_stats(self):
        best = max((int(run.get("Windows", 0)) for run in self.runs), default=0)
        longest = max((int(run.get("Seconds", 0)) for run in self.runs), default=0)
        total = sum(int(run.get("Windows", 0)) for run in self.runs)

        self.stat_values["Runs"].configure(text=str(len(self.runs)))
        self.stat_values["Best"].configure(text=str(best))
        self.stat_values["Longest"].configure(text=format_duration(longest))
        self.stat_values["Windows"].configure(text=str(total))

        self._pack_board_rows()

    def _pack_board_rows(self):
        runs = getattr(self, "runs", None) or []
        for index, row in enumerate(self.board_rows):
            if index < len(runs):
                run = runs[index]
                row["when"].configure(text=str(run.get("At", "")))
                row["windows"].configure(text=f"{int(run.get('Windows', 0))} windows")
                row["duration"].configure(text=format_duration(int(run.get("Seconds", 0))))
                if not row["frame"].winfo_manager():
                    row["frame"].pack(fill="x", padx=18, pady=2)
            elif row["frame"].winfo_manager():
                row["frame"].pack_forget()

        if runs:
            if self.board_empty.winfo_manager():
                self.board_empty.pack_forget()
        elif not self.board_empty.winfo_manager():
            self.board_empty.pack(anchor="w", padx=20, pady=(6, 0))

    def _reset_stats(self):
        if not messagebox.askyesno("Reset leaderboard", "Clear the leaderboard? This cannot be undone."):
            return
        self.runs = []
        self._save_runs([])
        self._render_stats()
        self.log("Leaderboard cleared.", "quiet")

    # -------------------------------------------------------------- updates

    def _update_click(self):
        if self.update_state == "available" and self.update_info and self.update_info["url"]:
            self.log(f"Opening {self.update_info['url']}", "quiet")
            try:
                subprocess.Popen(["open", self.update_info["url"]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception as exc:  # noqa: BLE001 - surface anything to the log
                self.log(f"Could not open the browser: {exc}", "err")
            return
        self._check_updates()

    def _check_updates(self, auto=False):
        if self.update_state == "checking":
            return
        self.update_state = "checking"
        self.update_button.set_text("Checking...")
        self.update_button.set_enabled(False)
        if not auto:
            self.log("Checking GitHub for the newest release.", "quiet")
        self._update_result = None
        self._update_deadline = time.time() + 30
        threading.Thread(target=self._fetch_updates, daemon=True).start()
        self.after(120, self._poll_updates)

    def _fetch_updates(self):
        found = error = None
        try:
            found = newest_release(fetch_releases())
        except Exception as exc:  # noqa: BLE001 - offline, rate limited, no DNS
            error = str(exc)
        # No tkinter calls from this thread: the main loop picks the result up.
        self._update_result = (found, error)

    def _poll_updates(self):
        """Collect the worker's result on the main thread, or give up after 30s."""
        if self._update_result is None:
            if time.time() > self._update_deadline:
                self._finish_update_check(None, "the request timed out")
                return
            self.after(120, self._poll_updates)
            return
        found, error = self._update_result
        self._update_result = None
        self._finish_update_check(found, error)

    def _finish_update_check(self, found, error):
        self.update_button.set_enabled(True)
        self.last_checked_value.configure(text=time.strftime("%H:%M:%S"))

        if error is not None:
            self.update_state = "error"
            self.update_button.set_text("Check for updates")
            self.version_label.configure(text=f"v{APP_VERSION} \u00b7 check failed", fg=MUTED)
            self.latest_value.configure(text="check failed", fg=MUTED)
            self.update_notes.configure(text=f"Could not reach GitHub: {error}\nIt tries again the next time the app opens.")
            self.log(f"Update check failed: {error}", "warn")
            return

        if found is None:
            self.update_state = "current"
            self.update_button.set_text("Check for updates")
            self.version_label.configure(text=f"v{APP_VERSION} \u00b7 no releases", fg=MUTED)
            self.latest_value.configure(text="none published", fg=MUTED)
            self.update_notes.configure(text="The repository has no published releases yet.")
            self.log("Update check: no published releases found.", "quiet")
            return

        self.update_info = found
        current = version_tuple(APP_VERSION)
        if not current:
            # Never claim "up to date" when this build cannot say what it is.
            self.update_state = "error"
            self.update_button.set_text("Check for updates")
            self.version_label.configure(text=f"v{APP_VERSION} \u00b7 unknown version", fg=MUTED)
            self.latest_value.configure(text=found["label"], fg=MUTED)
            self.update_notes.configure(text=f"This build's version ({APP_VERSION!r}) is not a version number, so nothing can be compared.")
            self.log(f"This build's version ({APP_VERSION!r}) is not a version number.", "warn")
            return
        if found["version"] > current:
            self.update_state = "available"
            self.update_button.set_text(f"Get {found['label']}  \u2192")
            self.version_label.configure(text=f"v{APP_VERSION} \u00b7 {found['label']} available", fg=ACCENT)
            self.latest_value.configure(text=found["label"], fg=ACCENT)
            self.update_notes.configure(text=found["notes"].strip() or f"{found['label']} is ready on GitHub.")
            self.log(f"Update available: {found['label']} (this build is {APP_VERSION}).", "ok")
            first_line = next((line.strip() for line in found["notes"].splitlines() if line.strip()), "")
            if first_line:
                self.log(f"  {first_line}", "quiet")
        else:
            self.update_state = "current"
            self.update_button.set_text("Check for updates")
            self.version_label.configure(text=f"v{APP_VERSION} \u00b7 up to date", fg=MUTED)
            self.latest_value.configure(text=found["label"], fg="#BFC4D6")
            self.update_notes.configure(text=found["notes"].strip() or "You are on the newest release.")
            self.log(f"Update check: up to date, newest release is {found['label']}.", "quiet")

    # ---------------------------------------------------------------- prank

    def _find_browser(self):
        for path in BROWSER_PATHS:
            if os.path.isfile(path) and os.access(path, os.X_OK):
                return path
        for name in ("google-chrome", "chromium", "brave-browser", "microsoft-edge"):
            found = shutil.which(name)
            if found:
                return found
        return None

    def _toggle(self):
        if self.running:
            self.stop()
        else:
            self.start()

    def start(self):
        if self.running:
            return

        browser = self._find_browser()
        if browser is None:
            self.log("No Chromium browser found (Chrome, Brave, Edge or Chromium). Install one first.", "err")
            self._set_status("No browser found", DANGER)
            return

        self.browser = browser
        self.total = self.windows_stepper.get()
        self.opened = 0
        self.procs = []
        self.ends_at = None
        self.started_at = time.time()
        self.running = True
        os.makedirs(self.profile_dir, exist_ok=True)

        self._set_running_ui(True)
        self._set_status("Starting", ACCENT)
        self.log(f"Starting: {self.total} window(s) on this Space", "ok")
        self.log(f"Browser: {browser}", "quiet")
        self.log("Every window uses a throwaway profile, so your normal browser is untouched.", "quiet")

        self.job = self.after(150, self._open_next)

    def _open_next(self):
        self.job = None
        if not self.running:
            return
        if self.opened >= self.total:
            self._live()
            return

        args = [
            self.browser,
            "--new-window",
            f"--user-data-dir={self.profile_dir}",
            "--no-first-run",
            "--no-default-browser-check",
            "--start-maximized",
            "--disable-sync",
            "--autoplay-policy=no-user-gesture-required",
            VIDEO_URL,
        ]
        try:
            proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.procs.append(proc)
            self.opened += 1
            self.log(f"Opened window {self.opened} of {self.total}")
            self._set_status(f"Starting \u00b7 {self.opened} of {self.total} windows", ACCENT)
        except Exception as exc:  # noqa: BLE001 - surface anything to the log
            self.log(f"Could not open a window: {exc}", "err")

        self.job = self.after(STEP_DELAY_MS, self._open_next)

    def _live(self):
        self.log(f"Live - {self.opened} window(s) playing", "ok")
        seconds = self.duration_stepper.get()
        if seconds > 0:
            self.ends_at = time.time() + seconds
            self._tick()
        else:
            self._set_status("Live \u00b7 until you stop it", ACCENT)

    def _tick(self):
        if not self.running or self.ends_at is None:
            return
        left = int(round(self.ends_at - time.time()))
        if left <= 0:
            self.log("Duration reached - cleaning up.", "quiet")
            self.stop()
            return
        self._set_status(f"Live \u00b7 {left}s left", ACCENT)
        self.after(500, self._tick)

    def stop(self, force=False):
        if self.job is not None:
            self.after_cancel(self.job)
            self.job = None

        was_running = self.running
        self.running = False
        self.ends_at = None

        if force and was_running:
            self.log("Force stop - killing windows now.", "warn")

        closed = self._kill_windows()
        if closed:
            self.log(f"Closed {closed} window process(es).", "ok")
        else:
            self.log("No prank windows were open.", "quiet")

        if was_running:
            elapsed = 0 if self.started_at is None else int(round(time.time() - self.started_at))
            self._record_run(elapsed, force)
            self.log(f"Leaderboard: {self.opened} window(s) in {format_duration(elapsed)}.", "quiet")
        self.started_at = None

        shutil.rmtree(self.profile_dir, ignore_errors=True)
        self.procs = []
        self._set_running_ui(False)
        self._set_status("Idle", MUTED)

    def _kill_windows(self):
        killed = 0
        for proc in list(self.procs):
            if proc.poll() is None:
                try:
                    proc.terminate()
                    killed += 1
                except Exception:  # noqa: BLE001 - a dead process is fine
                    pass
        self.procs = []

        # Catch anything the launcher lost track of, scoped to our own profile.
        if shutil.which("pkill"):
            try:
                result = subprocess.run(["pkill", "-f", self.profile_dir], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                if result.returncode == 0:
                    killed = max(killed, 1)
            except Exception:  # noqa: BLE001
                pass
        return killed

    def _force_stop(self):
        self.stop(force=True)

    def _set_running_ui(self, running):
        if running:
            self.start_button.set_text("Stop  \u25a0")
            self.start_button.set_colors(LIVE_BG, "#2E2338", "#2A1F32", ACCENT)
            self.start_button._fg = ACCENT
        else:
            self.start_button.set_text("Start prank  \u25b6")
            self.start_button.set_colors(ACCENT, ACCENT_HI, ACCENT_LO, "#FFFFFF")
            self.start_button._fg = "#FFFFFF"
        self._set_status("Idle" if not running else self.status_label.cget("text"))

    def _on_close(self):
        try:
            if self.running:
                self.stop(force=True)
            else:
                self._kill_windows()
                shutil.rmtree(self.profile_dir, ignore_errors=True)
        finally:
            self.destroy()


def selftest():
    app = Launcher(auto_check=False)
    app.update_idletasks()
    app.update()
    print(f"selftest: window {app.winfo_width()}x{app.winfo_height()}")
    print(f"selftest: widgets built, log lines {len(app.log_box.get('1.0', 'end').strip().splitlines())}")
    print(f"selftest: browser detected: {app._find_browser()}")
    print(f"selftest: steppers windows={app.windows_stepper.get()} seconds={app.duration_stepper.get()}")

    def visible_rows():
        return sum(1 for row in app.board_rows if row["frame"].winfo_manager())

    for page in ("Prank", "Logs", "Leaderboard", "Updates"):
        app._show_page(page)
    print(f"selftest: pages {sorted(app.pages)} nav {sorted(app.nav_buttons)} current={app.current_page}")

    app.log("selftest app line", "info", "App")
    app.log("selftest prank line", "info", "Prank")
    app.log("selftest error line", "err", "Prank")
    app._set_log_channel("Prank")
    prank_view = app.log_box.get("1.0", "end")
    app._set_log_channel("Errors")
    errors_view = app.log_box.get("1.0", "end")
    app._set_log_channel("All")
    all_view = app.log_box.get("1.0", "end")
    print(f"selftest: log filter -> prank_only={'selftest prank line' in prank_view and 'selftest app line' not in prank_view} "
          f"errors_only={'selftest error line' in errors_view and 'selftest app line' not in errors_view} all={'selftest app line' in all_view}")

    sample = [
        {"tag_name": "v1.0.0-beta", "draft": False, "published_at": "2026-11-12T00:00:00Z", "html_url": "u0", "body": "old"},
        {"tag_name": "v1.0.1-beta", "draft": False, "published_at": "2026-11-13T00:00:00Z", "html_url": "u1", "body": "notes"},
        {"tag_name": "v9.9.9", "draft": True, "published_at": "2027-01-01T00:00:00Z", "html_url": "u9", "body": ""},
    ]
    found = newest_release(sample)
    print(f"selftest: newest release -> {found['label']} (draft skipped: {found['label'] == '1.0.1-beta'})")
    # Expectations are derived from APP_VERSION so bumping it cannot break this.
    problems = []
    base = version_tuple(APP_VERSION)
    bumped = ".".join(str(part) for part in (base[:-1] + (base[-1] + 1,)))
    for tag, expected in (
        (f"v{bumped}-beta", True),
        (f"v{APP_VERSION}", False),
        (f"v{APP_VERSION}-beta", False),
        ("v0.0.1", False),
        ("v99", True),
    ):
        newer = version_tuple(tag) > base
        if newer != expected:
            problems.append(f"{tag} newer than {APP_VERSION} gave {newer}, expected {expected}")
        print(f"selftest: {tag} newer than {APP_VERSION}: {newer} (expected {expected}, {'ok' if newer == expected else 'WRONG'})")

    app._finish_update_check({"version": (9, 9, 9), "label": "9.9.9", "url": "https://example.com", "notes": "first note\nsecond"}, None)
    print(f"selftest: available -> state={app.update_state} button='{app.update_button._label.cget('text')}' footer='{app.version_label.cget('text')}'")
    app._finish_update_check(found, None)
    print(f"selftest: up to date -> state={app.update_state} button='{app.update_button._label.cget('text')}' footer='{app.version_label.cget('text')}'")
    app._finish_update_check(None, "no network")
    print(f"selftest: failure -> state={app.update_state} footer='{app.version_label.cget('text')}' enabled={app.update_button._enabled}")
    app._finish_update_check(None, None)
    print(f"selftest: no releases -> state={app.update_state} footer='{app.version_label.cget('text')}'")

    stats_tmp = pathlib.Path(tempfile.gettempdir()) / "rickroll-selftest-leaderboard.json"
    if stats_tmp.exists():
        stats_tmp.unlink()
    _STATS_OVERRIDE["path"] = str(stats_tmp)

    app.runs = []
    app._render_stats()
    print(f"selftest: leaderboard empty -> runs={app.stat_values['Runs'].cget('text')} rows={visible_rows()} emptyShown={bool(app.board_empty.winfo_manager())}")

    app.opened = 12
    app._record_run(95, False)
    app.opened = 8
    app._record_run(300, True)
    print(f"selftest: leaderboard -> runs={app.stat_values['Runs'].cget('text')} best={app.stat_values['Best'].cget('text')} longest={app.stat_values['Longest'].cget('text')} opened={app.stat_values['Windows'].cget('text')} rows={visible_rows()}")

    app.runs = []
    app.runs = app._load_runs()
    print(f"selftest: leaderboard reload -> runs={len(app.runs)} newest={app.runs[0]['Windows']} forced={app.runs[0]['Forced']} at={app.runs[0]['At']}")

    app.runs = []
    app._save_runs([])
    app.runs = app._load_runs()
    app._render_stats()
    print(f"selftest: leaderboard reset -> runs={app.stat_values['Runs'].cget('text')} stored={len(app._load_runs())} rows={visible_rows()}")

    stats_tmp.unlink(missing_ok=True)
    _STATS_OVERRIDE["path"] = None
    app.runs = []
    app._render_stats()

    app.after(1200, app.destroy)
    app.mainloop()
    print("selftest: built, shown and closed without errors")
    if problems:
        print("selftest FAILED: " + "; ".join(problems))
        sys.exit(1)


def main():
    if "--diagnose" in sys.argv:
        return diagnose()
    if "--selftest" in sys.argv:
        selftest()
        return 0
    Launcher().mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
