#!/usr/bin/env python3
"""Multica Quick Add — GTK4/Adwaita floating panel (comparison UI).

Same Tim-style flow as the Quickshell panel: live text entry + pickers.
Styled dark to match; optional gtk4-layer-shell when available.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import threading
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, GLib, Gtk, Pango  # noqa: E402

try:
    gi.require_version("Gtk4LayerShell", "1.0")
    from gi.repository import Gtk4LayerShell as LayerShell

    HAS_LAYER = True
except Exception:  # noqa: BLE001
    HAS_LAYER = False


CSS = b"""
window.mqa, .mqa-panel {
  background-color: #12121a;
  border-radius: 18px;
  border: 1px solid #2e2e3a;
  color: #e4e4ef;
}
.mqa-header-title {
  color: #e4e4ef;
  font-weight: 700;
  font-size: 14px;
}
.mqa-header-sub {
  color: #6c6c80;
  font-size: 11px;
}
.mqa-badge {
  background-color: #1e3a5f;
  border-radius: 8px;
  border: 1px solid #2a4a70;
  color: #89b4fa;
  font-weight: 700;
  min-width: 28px;
  min-height: 28px;
}
.mqa-prompt-frame {
  background-color: #1a1a24;
  border-radius: 14px;
  border: 1px solid #2e2e3a;
  padding: 4px;
}
textview.mqa-prompt, textview.mqa-prompt text {
  background: transparent;
  color: #e4e4ef;
  font-size: 17px;
}
.mqa-dropdown {
  background-color: #22222e;
  border-radius: 10px;
  color: #e4e4ef;
  padding: 6px 10px;
  min-height: 36px;
}
button.mqa-send {
  background: #89b4fa;
  color: #0b1020;
  border-radius: 10px;
  font-weight: 700;
  min-width: 96px;
  min-height: 36px;
  border: none;
}
button.mqa-send:hover {
  background: #9ac0fb;
}
button.mqa-send:disabled {
  background: #22222e;
  color: #6c6c80;
}
.status-error { color: #f38ba8; font-size: 12px; }
.status-info  { color: #6c6c80; font-size: 12px; }
"""


def run_json(cmd: list[str]) -> dict:
    env = os.environ.copy()
    home = Path.home()
    env["PATH"] = f"{home / '.local' / 'bin'}:{env.get('PATH', '')}"
    # Avoid interactive BASH_ENV/direnv noise in child bash scripts
    env.pop("BASH_ENV", None)
    proc = subprocess.run(cmd, check=False, capture_output=True, text=True, env=env)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or f"exit {proc.returncode}")
    return json.loads(proc.stdout)


def notify(title: str, body: str) -> None:
    if shutil.which("notify-send"):
        subprocess.Popen(  # noqa: S603
            ["notify-send", "--app-name=Multica Quick Add", title, body],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


class MulticaPanel(Adw.Application):
    def __init__(self) -> None:
        super().__init__(application_id="dev.multica.QuickAddGtk")
        self._bootstrap: dict = {}
        self._win: Gtk.Window | None = None
        self._prompt: Gtk.TextView | None = None
        self._ws: Gtk.DropDown | None = None
        self._proj: Gtk.DropDown | None = None
        self._created: Gtk.DropDown | None = None
        self._status: Gtk.Label | None = None
        self._send: Gtk.Button | None = None

    def do_activate(self) -> None:  # noqa: N802
        if self._win is not None:
            self._win.present()
            self._focus_prompt()
            self._reload_async()
            return

        win = Gtk.Window(application=self, title="Multica Quick Add (GTK)")
        win.add_css_class("mqa")
        win.set_default_size(720, 268)
        win.set_resizable(True)
        win.set_decorated(False)
        win.set_modal(False)

        if HAS_LAYER:
            LayerShell.init_for_window(win)
            LayerShell.set_layer(win, LayerShell.Layer.TOP)
            LayerShell.set_anchor(win, LayerShell.Edge.TOP, True)
            LayerShell.set_margin(win, LayerShell.Edge.TOP, 96)
            LayerShell.set_keyboard_mode(win, LayerShell.KeyboardMode.ON_DEMAND)
            LayerShell.set_namespace(win, "multica-quick-add")

        css = Gtk.CssProvider()
        css.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        outer.add_css_class("mqa-panel")
        outer.set_margin_top(18)
        outer.set_margin_bottom(18)
        outer.set_margin_start(18)
        outer.set_margin_end(18)

        # Header
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        badge = Gtk.Label(label="M")
        badge.add_css_class("mqa-badge")
        badge.set_halign(Gtk.Align.CENTER)
        badge.set_valign(Gtk.Align.CENTER)
        titles = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        t1 = Gtk.Label(label="Quick Add", xalign=0)
        t1.add_css_class("mqa-header-title")
        t2 = Gtk.Label(label="GTK · ⌘/Ctrl+Enter to send · Esc dismiss · Enter newline", xalign=0)
        t2.add_css_class("mqa-header-sub")
        titles.append(t1)
        titles.append(t2)
        header.append(badge)
        header.append(titles)
        outer.append(header)

        # Prompt
        frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        frame.add_css_class("mqa-prompt-frame")
        scroll = Gtk.ScrolledWindow()
        scroll.set_min_content_height(88)
        scroll.set_vexpand(True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        prompt = Gtk.TextView()
        prompt.add_css_class("mqa-prompt")
        prompt.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        prompt.set_accepts_tab(False)
        prompt.set_top_margin(10)
        prompt.set_left_margin(12)
        prompt.set_right_margin(12)
        prompt.set_bottom_margin(10)
        scroll.set_child(prompt)
        frame.append(scroll)
        outer.append(frame)

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        ws = Gtk.DropDown.new_from_strings(["…"])
        proj = Gtk.DropDown.new_from_strings(["No project"])
        created = Gtk.DropDown.new_from_strings(["…"])
        for dd in (ws, proj, created):
            dd.add_css_class("mqa-dropdown")
            dd.set_hexpand(True)
            row.append(dd)

        send = Gtk.Button(label="Send")
        send.add_css_class("mqa-send")
        send.connect("clicked", self._on_send)
        row.append(send)
        outer.append(row)

        status = Gtk.Label(xalign=0)
        status.add_css_class("status-error")
        status.set_wrap(True)
        status.set_ellipsize(Pango.EllipsizeMode.END)
        outer.append(status)

        key = Gtk.EventControllerKey()
        key.connect("key-pressed", self._on_key)
        win.add_controller(key)

        win.set_child(outer)
        win.connect("close-request", self._on_close)

        self._win = win
        self._prompt = prompt
        self._ws = ws
        self._proj = proj
        self._created = created
        self._status = status
        self._send = send

        win.present()
        self._focus_prompt()
        self._reload_async()

    def _focus_prompt(self) -> None:
        if self._prompt:
            self._prompt.grab_focus()

    def _set_status(self, text: str, error: bool = True) -> None:
        if not self._status:
            return
        self._status.set_text(text)
        self._status.remove_css_class("status-error")
        self._status.remove_css_class("status-info")
        self._status.add_css_class("status-error" if error else "status-info")

    def _on_close(self, *_args) -> bool:
        self.quit()
        return False

    def _on_key(self, _ctrl, keyval, _keycode, state) -> bool:
        if keyval == Gdk.KEY_Escape:
            self.quit()
            return True
        # Enter = newline. Submit only with Ctrl/Cmd/Super+Enter.
        submit_mod = (
            Gdk.ModifierType.CONTROL_MASK
            | Gdk.ModifierType.META_MASK
            | Gdk.ModifierType.SUPER_MASK
        )
        if keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter) and (state & submit_mod):
            self._on_send(None)
            return True
        return False

    def _reload_async(self) -> None:
        self._set_status("Loading…", error=False)
        if self._send:
            self._send.set_sensitive(False)

        def work() -> None:
            try:
                data = run_json(["mqa-bootstrap"])
                GLib.idle_add(self._apply_bootstrap, data)
            except Exception as exc:  # noqa: BLE001
                GLib.idle_add(self._set_status, f"Load failed: {exc}", True)
                GLib.idle_add(lambda: self._send.set_sensitive(True) if self._send else None)

        threading.Thread(target=work, daemon=True).start()

    def _apply_bootstrap(self, data: dict) -> None:
        self._bootstrap = data
        if not data.get("ok"):
            self._set_status(data.get("message") or data.get("error") or "Not logged in", True)
            if self._send:
                self._send.set_sensitive(True)
            return

        workspaces = data.get("workspaces") or []
        projects = data.get("projects") or []
        agents = data.get("agents") or []
        squads = data.get("squads") or []
        sel = data.get("selection") or {}

        self._ws.set_model(Gtk.StringList.new([w.get("name") or w.get("id") for w in workspaces] or ["—"]))
        self._proj.set_model(
            Gtk.StringList.new(["No project"] + [p.get("title") or p.get("id") for p in projects])
        )
        created_labels = [f"Agent · {a.get('name')}" for a in agents] + [
            f"Squad · {s.get('name')}" for s in squads
        ]
        self._created.set_model(Gtk.StringList.new(created_labels or ["—"]))

        ws_id = sel.get("workspace_id") or ""
        for i, w in enumerate(workspaces):
            if w.get("id") == ws_id:
                self._ws.set_selected(i)
                break
        proj_id = sel.get("project_id") or ""
        self._proj.set_selected(0)
        if proj_id:
            for i, p in enumerate(projects):
                if p.get("id") == proj_id:
                    self._proj.set_selected(i + 1)
                    break
        kind = sel.get("created_by_kind") or ""
        cid = sel.get("created_by_id") or ""
        self._created.set_selected(0)
        if kind == "agent":
            for i, a in enumerate(agents):
                if a.get("id") == cid:
                    self._created.set_selected(i)
                    break
        elif kind == "squad":
            for i, s in enumerate(squads):
                if s.get("id") == cid:
                    self._created.set_selected(len(agents) + i)
                    break

        self._set_status("", False)
        if self._send:
            self._send.set_sensitive(True)
        self._focus_prompt()

    def _prompt_text(self) -> str:
        buf = self._prompt.get_buffer()
        start = buf.get_start_iter()
        end = buf.get_end_iter()
        return buf.get_text(start, end, True).strip()

    def _on_send(self, _btn) -> None:
        prompt = self._prompt_text()
        if not prompt:
            self._set_status("Type an issue first", True)
            return
        data = self._bootstrap
        if not data.get("ok"):
            self._set_status("Not logged in — run multica login", True)
            return
        workspaces = data.get("workspaces") or []
        projects = data.get("projects") or []
        agents = data.get("agents") or []
        squads = data.get("squads") or []

        wi = self._ws.get_selected()
        if wi < 0 or wi >= len(workspaces):
            self._set_status("Pick a workspace", True)
            return
        ws_id = workspaces[wi]["id"]

        pi = self._proj.get_selected()
        proj_id = "" if pi <= 0 else projects[pi - 1]["id"]

        ci = self._created.get_selected()
        if ci < 0:
            self._set_status("Pick an agent or squad", True)
            return
        if ci < len(agents):
            kind, cid = "agent", agents[ci]["id"]
        else:
            si = ci - len(agents)
            if si < 0 or si >= len(squads):
                self._set_status("Pick an agent or squad", True)
                return
            kind, cid = "squad", squads[si]["id"]

        self._set_status("Sending…", error=False)
        if self._send:
            self._send.set_sensitive(False)

        cmd = [
            "multica-quick-add",
            "--no-notify",
            "--workspace-id",
            ws_id,
            "--project-id",
            proj_id,
        ]
        if kind == "squad":
            cmd += ["--squad-id", cid]
        else:
            cmd += ["--agent-id", cid]
        cmd.append(prompt)

        def work() -> None:
            try:
                env = os.environ.copy()
                env["PATH"] = f"{Path.home() / '.local' / 'bin'}:{env.get('PATH', '')}"
                env.pop("BASH_ENV", None)
                proc = subprocess.run(cmd, check=False, capture_output=True, text=True, env=env)
                if proc.returncode == 0:
                    GLib.idle_add(self._send_ok, prompt)
                else:
                    err = (proc.stderr or proc.stdout or "Send failed").strip()
                    GLib.idle_add(self._set_status, err.replace("error: ", ""), True)
                    GLib.idle_add(lambda: self._send.set_sensitive(True) if self._send else None)
            except Exception as exc:  # noqa: BLE001
                GLib.idle_add(self._set_status, str(exc), True)
                GLib.idle_add(lambda: self._send.set_sensitive(True) if self._send else None)

        threading.Thread(target=work, daemon=True).start()

    def _send_ok(self, prompt: str) -> None:
        notify("Sent", prompt[:120])
        self.quit()


def main() -> int:
    Adw.init()
    app = MulticaPanel()
    return app.run(sys.argv)


if __name__ == "__main__":
    raise SystemExit(main())
