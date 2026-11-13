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
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import tkinter as tk
from urllib.request import Request, urlopen

APP_VERSION = "1.0.1"
RELEASES_URL = "https://api.github.com/repos/dnbdj/rickroll-launcher/releases"
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
        self.update_state = "idle"
        self.update_info = None  # not "update": that name is tkinter's own method
        self._update_result = None
        self._update_deadline = 0.0

        self._build_ui()
        self.protocol("WM_DELETE_WINDOW", self._on_close)
        self.log("Launcher ready.", "quiet")
        self.log(f"Prank profile: {self.profile_dir}", "quiet")
        self.log("Panic stop: press Force stop. Closing this window also cleans up.", "quiet")
        if auto_check:
            self.after(600, lambda: self._check_updates(auto=True))

    # ---------------------------------------------------------------- layout

    def _build_ui(self):
        header = tk.Frame(self, bg=BG)
        header.pack(fill="x", padx=22, pady=(18, 8))
        tk.Label(header, text="Rickroll", bg=BG, fg=TEXT, font=(FONT, 22, "bold")).pack(side="left")
        tk.Label(header, text=f"  macOS beta {APP_VERSION}", bg=BG, fg=MUTED, font=(FONT, 12)).pack(side="left", pady=(8, 0))

        controls = tk.Frame(self, bg=CARD, highlightbackground=STROKE, highlightthickness=1)
        controls.pack(fill="x", padx=22, pady=(6, 10))
        inner = tk.Frame(controls, bg=CARD)
        inner.pack(fill="x", padx=16, pady=16)

        self.start_button = FlatButton(inner, "Start prank  \u25b6", self._toggle, ACCENT, ACCENT_HI, ACCENT_LO, "#FFFFFF", (FONT, 14, "bold"))
        self.start_button.pack(side="left")

        self.force_button = FlatButton(inner, "Force stop", self._force_stop, INNER, DANGER_BG, DANGER_BG, DANGER, (FONT, 12, "bold"))
        self.force_button.pack(side="left", padx=(10, 0))

        self.windows_stepper = Stepper(inner, "Windows", 8, 1, 40, 1, self._on_option_change)
        self.windows_stepper.pack(side="right")
        self.duration_stepper = Stepper(inner, "Seconds", 120, 0, 3600, 30, self._on_option_change)
        self.duration_stepper.pack(side="right", padx=(0, 8))

        hint = tk.Label(
            self,
            text="macOS cannot create Spaces from a script, so every window opens on the Space you are on.",
            bg=BG,
            fg=MUTED,
            font=(FONT, 10),
            anchor="w",
        )
        hint.pack(fill="x", padx=24, pady=(0, 10))

        log_card = tk.Frame(self, bg=CARD, highlightbackground=STROKE, highlightthickness=1)
        log_card.pack(fill="both", expand=True, padx=22, pady=(0, 10))

        log_header = tk.Frame(log_card, bg=CARD)
        log_header.pack(fill="x", padx=14, pady=(10, 6))
        tk.Label(log_header, text="Logs", bg=CARD, fg=TEXT, font=(FONT, 13, "bold")).pack(side="left")
        FlatButton(log_header, "Clear", self._clear_log, CARD, INNER, INNER, MUTED, (FONT, 10), padx=12, pady=3).pack(side="right")

        self.log_box = tk.Text(log_card, bg="#101220", fg="#C3C8D8", insertbackground=TEXT, relief="flat", bd=0, wrap="none", font=("Menlo", 11), padx=10, pady=8)
        self.log_box.pack(fill="both", expand=True, padx=12, pady=(0, 12))
        self.log_box.tag_configure("time", foreground="#5A5F73")
        self.log_box.tag_configure("info", foreground="#C3C8D8")
        self.log_box.tag_configure("ok", foreground="#4ADE80")
        self.log_box.tag_configure("warn", foreground="#FBBF24")
        self.log_box.tag_configure("err", foreground="#FF6B6B")
        self.log_box.tag_configure("quiet", foreground="#7C8299")
        self.log_box.configure(state="disabled")

        footer = tk.Frame(self, bg=BG)
        footer.pack(fill="x", padx=22, pady=(0, 16))
        self.status_dot = tk.Label(footer, text="\u25cf", bg=BG, fg=MUTED, font=(FONT, 11))
        self.status_dot.pack(side="left")
        self.status_label = tk.Label(footer, text="Idle", bg=BG, fg=MUTED, font=(FONT, 11))
        self.status_label.pack(side="left", padx=(6, 0))

        self.update_button = FlatButton(footer, "Check for updates", self._update_click, INNER, STROKE, STROKE, MUTED, (FONT, 10), padx=12, pady=4)
        self.update_button.pack(side="right")
        self.version_label = tk.Label(footer, text=f"v{APP_VERSION}", bg=BG, fg=MUTED, font=(FONT, 10))
        self.version_label.pack(side="right", padx=(0, 10))

    # ------------------------------------------------------------------ log

    def log(self, message, level="info"):
        stamp = time.strftime("%H:%M:%S")
        self.log_box.configure(state="normal")
        self.log_box.insert("end", stamp + "  ", ("time",))
        self.log_box.insert("end", message + "\n", (level,))
        self.log_box.see("end")
        self.log_box.configure(state="disabled")

    def _clear_log(self):
        self.log_box.configure(state="normal")
        self.log_box.delete("1.0", "end")
        self.log_box.configure(state="disabled")

    # --------------------------------------------------------------- status

    def _set_status(self, text, color=MUTED):
        self.status_label.configure(text=text, fg=color)
        self.status_dot.configure(fg=color)

    def _on_option_change(self):
        windows = self.windows_stepper.get()
        seconds = self.duration_stepper.get()
        if seconds > 0:
            self.log(f"Plan: {windows} window(s), auto-stop after {seconds}s.", "quiet")
        else:
            self.log(f"Plan: {windows} window(s), runs until stopped.", "quiet")

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

        if error is not None:
            self.update_state = "error"
            self.update_button.set_text("Check for updates")
            self.version_label.configure(text=f"v{APP_VERSION} \u00b7 check failed", fg=MUTED)
            self.log(f"Update check failed: {error}", "warn")
            return

        if found is None:
            self.update_state = "current"
            self.update_button.set_text("Check for updates")
            self.version_label.configure(text=f"v{APP_VERSION} \u00b7 no releases", fg=MUTED)
            self.log("Update check: no published releases found.", "quiet")
            return

        self.update_info = found
        if found["version"] > version_tuple(APP_VERSION):
            self.update_state = "available"
            self.update_button.set_text(f"Get {found['label']}  \u2192")
            self.version_label.configure(text=f"v{APP_VERSION} \u00b7 {found['label']} available", fg=ACCENT)
            self.log(f"Update available: {found['label']} (this build is {APP_VERSION}).", "ok")
            first_line = next((line.strip() for line in found["notes"].splitlines() if line.strip()), "")
            if first_line:
                self.log(f"  {first_line}", "quiet")
        else:
            self.update_state = "current"
            self.update_button.set_text("Check for updates")
            self.version_label.configure(text=f"v{APP_VERSION} \u00b7 up to date", fg=MUTED)
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

    sample = [
        {"tag_name": "v1.0.0-beta", "draft": False, "published_at": "2026-11-12T00:00:00Z", "html_url": "u0", "body": "old"},
        {"tag_name": "v1.0.1-beta", "draft": False, "published_at": "2026-11-13T00:00:00Z", "html_url": "u1", "body": "notes"},
        {"tag_name": "v9.9.9", "draft": True, "published_at": "2027-01-01T00:00:00Z", "html_url": "u9", "body": ""},
    ]
    found = newest_release(sample)
    print(f"selftest: newest release -> {found['label']} (draft skipped: {found['label'] == '1.0.1-beta'})")
    problems = []
    for tag, expected in (("v1.0.2-beta", True), ("1.0.1", False), ("v1.0", False), ("v1.0.0", False), ("v2", True)):
        newer = version_tuple(tag) > version_tuple(APP_VERSION)
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

    app.after(1200, app.destroy)
    app.mainloop()
    print("selftest: built, shown and closed without errors")
    if problems:
        print("selftest FAILED: " + "; ".join(problems))
        sys.exit(1)


def main():
    if "--selftest" in sys.argv:
        selftest()
        return
    Launcher().mainloop()


if __name__ == "__main__":
    main()
