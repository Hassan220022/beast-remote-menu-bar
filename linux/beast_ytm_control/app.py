from __future__ import annotations

import json
import os
import subprocess
import threading
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("AyatanaAppIndicator3", "0.1")
from gi.repository import GLib, Gtk  # noqa: E402
from gi.repository import AyatanaAppIndicator3 as AppIndicator3  # noqa: E402

from .server import ServerController, load_token
from .settings import DATA_DIR, DEFAULTS, SETTINGS_FILE, load_settings, save_settings

APP_ID = "org.mikawi.beast-ytm-control"
AUTOSTART_DESKTOP = Path.home() / ".config/autostart/beast-ytm-control.desktop"


class SettingsWindow(Gtk.Window):
    def __init__(self, controller: ServerController, on_saved) -> None:
        super().__init__(title="Beast YTM Control — Settings")
        self.set_default_size(460, 360)
        self.set_border_width(12)
        self.controller = controller
        self.on_saved = on_saved
        self.cfg = load_settings()

        grid = Gtk.Grid(column_spacing=10, row_spacing=10)
        self.add(grid)

        self.host = Gtk.Entry(text=str(self.cfg["bind_host"]))
        self.port = Gtk.SpinButton.new_with_range(1, 65535, 1)
        self.port.set_value(int(self.cfg["port"]))
        self.companion = Gtk.Entry(text=str(self.cfg["companion_base"]))
        self.ttl = Gtk.SpinButton.new_with_range(1, 120, 1)
        self.ttl.set_value(float(self.cfg["state_ttl_seconds"]))
        self.min_interval = Gtk.SpinButton.new_with_range(0.5, 30, 0.1)
        self.min_interval.set_digits(1)
        self.min_interval.set_value(float(self.cfg["companion_min_interval"]))
        self.autostart = Gtk.CheckButton(label="Start at login (user systemd + desktop autostart)")
        self.autostart.set_active(bool(self.cfg["autostart"]))

        rows = [
            ("Bind host", self.host),
            ("Port", self.port),
            ("Companion base URL", self.companion),
            ("State cache TTL (s)", self.ttl),
            ("Companion min interval (s)", self.min_interval),
        ]
        for i, (label, widget) in enumerate(rows):
            grid.attach(Gtk.Label(label=label, xalign=0), 0, i, 1, 1)
            widget.set_hexpand(True)
            grid.attach(widget, 1, i, 1, 1)
        grid.attach(self.autostart, 0, len(rows), 2, 1)

        path = Gtk.Label(label=f"Config: {SETTINGS_FILE}", xalign=0)
        path.set_line_wrap(True)
        grid.attach(path, 0, len(rows) + 1, 2, 1)

        buttons = Gtk.Box(spacing=8)
        save_btn = Gtk.Button(label="Save & Restart API")
        save_btn.connect("clicked", self._save)
        close_btn = Gtk.Button(label="Close")
        close_btn.connect("clicked", lambda *_: self.destroy())
        buttons.pack_end(save_btn, False, False, 0)
        buttons.pack_end(close_btn, False, False, 0)
        grid.attach(buttons, 0, len(rows) + 2, 2, 1)

    def _save(self, *_args) -> None:
        cfg = save_settings(
            {
                "bind_host": self.host.get_text().strip(),
                "port": int(self.port.get_value()),
                "companion_base": self.companion.get_text().strip(),
                "state_ttl_seconds": float(self.ttl.get_value()),
                "companion_min_interval": float(self.min_interval.get_value()),
                "autostart": self.autostart.get_active(),
            }
        )
        try:
            self.controller.restart(cfg)
        except OSError as exc:
            self._error(f"Could not bind API: {exc}")
            return
        set_autostart(cfg["autostart"])
        self.on_saved(cfg)
        self.destroy()

    def _error(self, message: str) -> None:
        dialog = Gtk.MessageDialog(
            transient_for=self,
            flags=0,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text=message,
        )
        dialog.run()
        dialog.destroy()


class PairWindow(Gtk.Window):
    def __init__(self, controller: ServerController, on_done) -> None:
        super().__init__(title="Pair YouTube Music Companion")
        self.set_default_size(420, 220)
        self.set_border_width(12)
        self.controller = controller
        self.on_done = on_done
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(box)
        self.status = Gtk.Label(label="Start pairing, approve in YTM Desktop, then Finish.", xalign=0)
        self.status.set_line_wrap(True)
        self.code = Gtk.Label(label="Code: —", xalign=0)
        self.code.set_selectable(True)
        box.pack_start(self.status, False, False, 0)
        box.pack_start(self.code, False, False, 0)
        row = Gtk.Box(spacing=8)
        start = Gtk.Button(label="Start pairing")
        finish = Gtk.Button(label="Finish pairing")
        close = Gtk.Button(label="Close")
        start.connect("clicked", lambda *_: self._bg(self._start))
        finish.connect("clicked", lambda *_: self._bg(self._finish))
        close.connect("clicked", lambda *_: self.destroy())
        row.pack_start(start, False, False, 0)
        row.pack_start(finish, False, False, 0)
        row.pack_end(close, False, False, 0)
        box.pack_start(row, False, False, 0)

    def _bg(self, fn) -> None:
        threading.Thread(target=fn, daemon=True).start()

    def _api(self, path: str) -> dict[str, Any]:
        url = f"{self.controller.endpoint}{path}"
        req = urllib.request.Request(url, data=b"{}", method="POST", headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=40) as resp:
            return json.loads(resp.read().decode())

    def _start(self) -> None:
        try:
            payload = self._api("/api/pair/start")
            code = payload.get("code", "?")
            GLib.idle_add(self.code.set_text, f"Code: {code}")
            GLib.idle_add(self.status.set_text, "Approve this app in YouTube Music Desktop, then Finish.")
        except Exception as exc:  # noqa: BLE001
            GLib.idle_add(self.status.set_text, f"Start failed: {exc}")

    def _finish(self) -> None:
        try:
            payload = self._api("/api/pair/finish")
            GLib.idle_add(self.status.set_text, payload.get("message", "paired"))
            GLib.idle_add(self.on_done)
        except Exception as exc:  # noqa: BLE001
            GLib.idle_add(self.status.set_text, f"Finish failed: {exc}")


class BeastTrayApp:
    def __init__(self) -> None:
        self.controller = ServerController()
        self.settings_win: SettingsWindow | None = None
        self.pair_win: PairWindow | None = None
        self.status_item = Gtk.MenuItem(label="Status: starting…")
        self.status_item.set_sensitive(False)
        self.track_item = Gtk.MenuItem(label="Track: —")
        self.track_item.set_sensitive(False)
        self.toggle_item = Gtk.MenuItem(label="Stop API")
        self.toggle_item.connect("activate", self._toggle_api)

        menu = Gtk.Menu()
        for item in (
            self.status_item,
            self.track_item,
            Gtk.SeparatorMenuItem(),
            self.toggle_item,
            self._item("Open Settings", self._open_settings),
            self._item("Pair Companion", self._open_pair),
            self._item("Open config folder", self._open_config),
            Gtk.SeparatorMenuItem(),
            self._item("Quit", self._quit),
        ):
            menu.append(item)
            item.show()
        menu.show_all()

        self.indicator = AppIndicator3.Indicator.new(
            APP_ID,
            "audio-x-generic",
            AppIndicator3.IndicatorCategory.APPLICATION_STATUS,
        )
        self.indicator.set_status(AppIndicator3.IndicatorStatus.ACTIVE)
        self.indicator.set_title("Beast YTM Control")
        self.indicator.set_menu(menu)

        cfg = load_settings()
        set_autostart(bool(cfg.get("autostart", True)))
        try:
            self.controller.start(cfg)
        except OSError as exc:
            self._set_status(f"API failed: {exc}")
        else:
            self._set_status(f"API on {self.controller.endpoint}")
        GLib.timeout_add_seconds(3, self._poll_status)

    def _item(self, label: str, cb) -> Gtk.MenuItem:
        item = Gtk.MenuItem(label=label)
        item.connect("activate", cb)
        return item

    def _set_status(self, text: str) -> None:
        self.status_item.set_label(text)
        self.toggle_item.set_label("Stop API" if self.controller.running else "Start API")

    def _toggle_api(self, *_args) -> None:
        if self.controller.running:
            self.controller.stop()
            self._set_status("API stopped")
            return
        try:
            endpoint = self.controller.start(load_settings())
            self._set_status(f"API on {endpoint}")
        except OSError as exc:
            self._set_status(f"API failed: {exc}")

    def _open_settings(self, *_args) -> None:
        if self.settings_win is not None:
            self.settings_win.present()
            return
        win = SettingsWindow(self.controller, on_saved=lambda cfg: self._set_status(f"API on {self.controller.endpoint}"))
        win.connect("destroy", lambda *_: setattr(self, "settings_win", None))
        self.settings_win = win
        win.show_all()

    def _open_pair(self, *_args) -> None:
        if not self.controller.running:
            self._toggle_api()
        if self.pair_win is not None:
            self.pair_win.present()
            return
        win = PairWindow(self.controller, on_done=lambda: self._set_status(f"Paired · {self.controller.endpoint}"))
        win.connect("destroy", lambda *_: setattr(self, "pair_win", None))
        self.pair_win = win
        win.show_all()

    def _open_config(self, *_args) -> None:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        subprocess.Popen(["xdg-open", str(DATA_DIR)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def _poll_status(self) -> bool:
        if not self.controller.running:
            self.track_item.set_label("Track: (API stopped)")
            return True
        token = "yes" if load_token() else "no"
        try:
            with urllib.request.urlopen(f"{self.controller.endpoint}/api/state", timeout=2) as resp:
                data = json.loads(resp.read().decode())
            media = data.get("media") or {}
            title = media.get("title") or "Nothing playing"
            artist = media.get("author") or ""
            playing = "▶" if media.get("isPlaying") else "❚❚"
            self.track_item.set_label(f"{playing} {title}" + (f" — {artist}" if artist else ""))
            self._set_status(f"API on {self.controller.endpoint} · paired={token} · ok={data.get('ok')}")
        except Exception as exc:  # noqa: BLE001
            self.track_item.set_label("Track: unreachable")
            self._set_status(f"API on {self.controller.endpoint} · paired={token} · {exc}")
        return True

    def _quit(self, *_args) -> None:
        self.controller.stop()
        Gtk.main_quit()


def set_autostart(enabled: bool) -> None:
    unit = Path.home() / ".config/systemd/user/beast-ytm-control.service"
    # Keep unit in sync with installed launcher when present.
    if unit.exists():
        if enabled:
            subprocess.run(
                ["systemctl", "--user", "enable", "--now", "beast-ytm-control.service"],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        else:
            subprocess.run(
                ["systemctl", "--user", "disable", "--now", "beast-ytm-control.service"],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
    AUTOSTART_DESKTOP.parent.mkdir(parents=True, exist_ok=True)
    if enabled:
        exec_path = _launcher_path()
        AUTOSTART_DESKTOP.write_text(
            "\n".join(
                [
                    "[Desktop Entry]",
                    "Type=Application",
                    "Name=Beast YTM Control",
                    "Comment=Bridge YouTube Music companion to the macOS menu bar remote",
                    f"Exec={exec_path}",
                    "Icon=audio-x-generic",
                    "Terminal=false",
                    "Categories=AudioVideo;Audio;",
                    "X-GNOME-Autostart-enabled=true",
                    "",
                ]
            )
        )
    elif AUTOSTART_DESKTOP.exists():
        AUTOSTART_DESKTOP.unlink()


def _launcher_path() -> str:
    # Prefer installed path; fall back to module invocation from this tree.
    candidates = [
        Path.home() / ".local/bin/beast-ytm-control",
        Path("/usr/local/bin/beast-ytm-control"),
    ]
    for path in candidates:
        if path.exists():
            return str(path)
    root = Path(__file__).resolve().parents[1]
    return f"/usr/bin/python3 {root / 'run.py'}"


def run_app() -> int:
    # Single-instance-ish: if port already owned by old daemon, still show tray and attach.
    BeastTrayApp()
    Gtk.main()
    return 0
