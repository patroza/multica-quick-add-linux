#!/usr/bin/env python3
"""Multica Quick Add — GTK4/Adwaita floating panel (comparison UI).

Aligned with the Quickshell panel:
- load Multica data before first show (no empty→full flash)
- warm reopen keeps pickers + restores draft instantly, quiet refresh
- draft text survives dismiss until successful Send
- dropdown changes persist selection; focus returns to prompt
- Esc dismisses; Enter = newline; Ctrl/Cmd/Super+Enter sends
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
from gi.repository import Adw, Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

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


def _string_list_labels(model: Gtk.StringList | None) -> list[str]:
    if model is None:
        return []
    return [model.get_string(i) for i in range(model.get_n_items())]


def _same_labels(model: Gtk.StringList | None, labels: list[str]) -> bool:
    return _string_list_labels(model) == labels


class MulticaPanel(Adw.Application):
    def __init__(self) -> None:
        super().__init__(
            application_id="dev.multica.QuickAddGtk",
            flags=Gio.ApplicationFlags.FLAGS_NONE,
        )
        self._bootstrap: dict = {}
        self._win: Gtk.Window | None = None
        self._prompt: Gtk.TextView | None = None
        self._ws: Gtk.DropDown | None = None
        self._proj: Gtk.DropDown | None = None
        self._created: Gtk.DropDown | None = None
        self._status: Gtk.Label | None = None
        self._send: Gtk.Button | None = None
        self._visible = False
        self._applying = False
        self._ready_once = False
        self._last_draft = ""
        self._busy = False
        self._draft_path = Path(
            os.environ.get("XDG_STATE_HOME") or (Path.home() / ".local" / "state")
        ) / "multica-quick-add" / "draft.txt"

    def do_activate(self) -> None:  # noqa: N802
        # Single-instance: re-invoking the hotkey toggles close.
        if self._win is not None:
            if self._visible:
                self._dismiss()
                return
            self._present_existing()
            return

        win = Gtk.Window(application=self, title="Multica Quick Add")
        win.add_css_class("mqa")
        win.set_default_size(720, 268)
        win.set_resizable(True)
        win.set_decorated(False)
        win.set_modal(False)

        if HAS_LAYER:
            LayerShell.init_for_window(win)
            LayerShell.set_layer(win, LayerShell.Layer.OVERLAY)
            LayerShell.set_anchor(win, LayerShell.Edge.TOP, True)
            LayerShell.set_anchor(win, LayerShell.Edge.LEFT, False)
            LayerShell.set_anchor(win, LayerShell.Edge.RIGHT, False)
            LayerShell.set_margin(win, LayerShell.Edge.TOP, 96)
            LayerShell.set_keyboard_mode(win, LayerShell.KeyboardMode.EXCLUSIVE)
            LayerShell.set_namespace(win, "multica-quick-add")

        css = Gtk.CssProvider()
        css.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        outer.add_css_class("mqa-panel")
        for m in ("top", "bottom", "start", "end"):
            getattr(outer, f"set_margin_{m}")(18)

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        badge = Gtk.Label(label="M")
        badge.add_css_class("mqa-badge")
        badge.set_halign(Gtk.Align.CENTER)
        badge.set_valign(Gtk.Align.CENTER)
        titles = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        t1 = Gtk.Label(label="Quick Add", xalign=0)
        t1.add_css_class("mqa-header-title")
        layer_note = "layer-shell" if HAS_LAYER else "window"
        t2 = Gtk.Label(
            label=f"GTK ({layer_note}) · ⌘/Ctrl+Enter send · Esc dismiss · Enter newline",
            xalign=0,
        )
        t2.add_css_class("mqa-header-sub")
        titles.append(t1)
        titles.append(t2)
        header.append(badge)
        header.append(titles)
        outer.append(header)

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
        # Prompt-local keys (submit) — Esc handled at window CAPTURE
        pkey = Gtk.EventControllerKey()
        pkey.connect("key-pressed", self._on_prompt_key)
        prompt.add_controller(pkey)
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
            dd.connect("notify::selected", self._on_selection_changed)
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

        # CAPTURE so Esc dismisses even when a DropDown still has focus
        key = Gtk.EventControllerKey()
        key.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        key.connect("key-pressed", self._on_key)
        win.add_controller(key)

        win.set_child(outer)
        win.connect("close-request", self._on_close)
        win.connect("hide", self._on_hide)

        self._win = win
        self._prompt = prompt
        self._ws = ws
        self._proj = proj
        self._created = created
        self._status = status
        self._send = send

        # Cold path: load before first present (matches Quickshell revealPending)
        self._reload_async(reveal=True, quiet=False)

    def _present_existing(self) -> None:
        if not self._win:
            return
        # Warm path: draft + pickers already stable — show immediately
        if self._ready_once and self._bootstrap.get("ok"):
            if self._prompt:
                buf = self._prompt.get_buffer()
                buf.set_text(self._last_draft or "", -1)
            self._set_status("", False)
            self._reveal_window()
            self._reload_async(reveal=False, quiet=True)
            return
        self._reload_async(reveal=True, quiet=False)

    def _dismiss(self) -> None:
        if self._prompt:
            buf = self._prompt.get_buffer()
            start = buf.get_start_iter()
            end = buf.get_end_iter()
            raw = buf.get_text(start, end, True)
            self._last_draft = raw
            self._save_draft(raw)
            buf.set_text("", -1)
        self._set_status("", False)
        self._busy = False
        if self._win:
            self._win.hide()
        self._visible = False
        # Leave dropdown models intact for warm reopen (QS parity)

    def _save_draft(self, text: str) -> None:
        try:
            self._draft_path.parent.mkdir(parents=True, exist_ok=True)
            if not text:
                self._draft_path.unlink(missing_ok=True)
            else:
                self._draft_path.write_text(text, encoding="utf-8")
        except OSError:
            pass

    def _clear_draft(self) -> None:
        try:
            self._draft_path.unlink(missing_ok=True)
        except OSError:
            pass

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
        self._dismiss()
        return True

    def _on_hide(self, *_args) -> None:
        self._visible = False

    def _on_key(self, _ctrl, keyval, _keycode, state) -> bool:
        if keyval == Gdk.KEY_Escape:
            self._dismiss()
            return True
        return False

    def _on_prompt_key(self, _ctrl, keyval, _keycode, state) -> bool:
        submit_mod = (
            Gdk.ModifierType.CONTROL_MASK
            | Gdk.ModifierType.META_MASK
            | Gdk.ModifierType.SUPER_MASK
        )
        if keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter) and (state & submit_mod):
            self._on_send(None)
            return True
        # plain Enter → newline (default TextView)
        return False

    def _reload_async(self, reveal: bool = False, quiet: bool = False) -> None:
        if not quiet and not self._ready_once:
            self._set_status("Loading…", error=False)
            if self._send:
                self._send.set_sensitive(False)

        def work() -> None:
            try:
                data = run_json(["mqa-bootstrap"])
                GLib.idle_add(self._apply_bootstrap, data, reveal, quiet)
            except Exception as exc:  # noqa: BLE001
                GLib.idle_add(self._set_status, f"Load failed: {exc}", True)
                GLib.idle_add(lambda: self._send.set_sensitive(True) if self._send else None)
                if reveal:
                    GLib.idle_add(self._reveal_window)

        threading.Thread(target=work, daemon=True).start()

    def _reveal_window(self) -> bool:
        if self._win and not self._visible:
            self._win.present()
            self._visible = True
            self._focus_prompt()
        elif self._visible:
            self._focus_prompt()
        return False

    def _apply_bootstrap(self, data: dict, reveal: bool = False, quiet: bool = False) -> None:
        self._bootstrap = data
        if not data.get("ok"):
            if not quiet:
                self._set_status(data.get("message") or data.get("error") or "Not logged in", True)
                if self._ws:
                    self._applying = True
                    self._ws.set_model(Gtk.StringList.new(["—"]))
                    self._proj.set_model(Gtk.StringList.new(["No project"]))
                    self._created.set_model(Gtk.StringList.new(["—"]))
                    GLib.idle_add(self._end_applying)
            if self._send:
                self._send.set_sensitive(True)
            if reveal:
                self._reveal_window()
            return

        workspaces = data.get("workspaces") or []
        projects = data.get("projects") or []
        agents = data.get("agents") or []
        squads = data.get("squads") or []
        sel = data.get("selection") or {}

        assert self._ws and self._proj and self._created
        self._applying = True

        ws_labels = [w.get("name") or w.get("id") for w in workspaces] or ["—"]
        proj_labels = ["No project"] + [p.get("title") or p.get("id") for p in projects]
        created_labels = [f"Agent · {a.get('name')}" for a in agents] + [
            f"Squad · {s.get('name')}" for s in squads
        ] or ["—"]

        # Assign models only when labels change — avoids quiet-refresh flash
        if not _same_labels(self._ws.get_model(), ws_labels):
            self._ws.set_model(Gtk.StringList.new(ws_labels))
        if not _same_labels(self._proj.get_model(), proj_labels):
            self._proj.set_model(Gtk.StringList.new(proj_labels))
        if not _same_labels(self._created.get_model(), created_labels):
            self._created.set_model(Gtk.StringList.new(created_labels))

        wi = 0
        ws_id = sel.get("workspace_id") or ""
        for i, w in enumerate(workspaces):
            if w.get("id") == ws_id:
                wi = i
                break
        pi = 0
        proj_id = sel.get("project_id") or ""
        if proj_id:
            for i, p in enumerate(projects):
                if p.get("id") == proj_id:
                    pi = i + 1
                    break
        ci = 0
        kind = sel.get("created_by_kind") or ""
        cid = sel.get("created_by_id") or ""
        if kind == "agent":
            for i, a in enumerate(agents):
                if a.get("id") == cid:
                    ci = i
                    break
        elif kind == "squad":
            for i, s in enumerate(squads):
                if s.get("id") == cid:
                    ci = len(agents) + i
                    break

        if self._ws.get_selected() != wi:
            self._ws.set_selected(wi)
        if self._proj.get_selected() != pi:
            self._proj.set_selected(pi)
        max_ci = max(0, len(created_labels) - 1)
        ci = min(ci, max_ci)
        if self._created.get_selected() != ci:
            self._created.set_selected(ci)

        # Draft: disk is durable; never replace text the user is already editing
        draft = data.get("draft") if isinstance(data.get("draft"), str) else ""
        if not self._last_draft and draft:
            self._last_draft = draft
        if self._prompt and self._prompt.get_buffer().get_char_count() == 0 and self._last_draft:
            self._prompt.get_buffer().set_text(self._last_draft, -1)

        if not quiet:
            self._set_status("", False)
        if self._send and not self._busy:
            self._send.set_sensitive(True)
        self._ready_once = True

        if not workspaces:
            self._set_status("No workspaces — check multica auth", True)
        elif not agents and not squads:
            self._set_status("No agents/squads in workspace", True)

        if reveal:
            self._reveal_window()
        elif self._visible:
            self._focus_prompt()

        GLib.idle_add(self._end_applying)

    def _end_applying(self) -> bool:
        self._applying = False
        return False

    def _on_selection_changed(self, *_args) -> None:
        if self._applying or self._busy:
            return
        self._persist_selection()
        self._focus_prompt()

    def _persist_selection(self) -> None:
        data = self._bootstrap
        if not data.get("ok") or not self._ws or not self._proj or not self._created:
            return
        workspaces = data.get("workspaces") or []
        projects = data.get("projects") or []
        agents = data.get("agents") or []
        squads = data.get("squads") or []

        wi = self._ws.get_selected()
        if wi < 0 or wi >= len(workspaces):
            return
        ws_id = workspaces[wi]["id"]
        pi = self._proj.get_selected()
        proj_id = "" if pi <= 0 or pi - 1 >= len(projects) else projects[pi - 1]["id"]

        cmd = [
            "multica-quick-add",
            "--no-notify",
            "--set-workspace-id",
            ws_id,
            "--set-project-id",
            proj_id,
        ]
        ci = self._created.get_selected()
        if 0 <= ci < len(agents):
            cmd += ["--set-agent-id", agents[ci]["id"]]
        else:
            si = ci - len(agents)
            if 0 <= si < len(squads):
                cmd += ["--set-squad-id", squads[si]["id"]]

        def work() -> None:
            try:
                env = os.environ.copy()
                env["PATH"] = f"{Path.home() / '.local' / 'bin'}:{env.get('PATH', '')}"
                env.pop("BASH_ENV", None)
                subprocess.run(cmd, check=False, capture_output=True, text=True, env=env)
            except Exception:  # noqa: BLE001
                pass

        threading.Thread(target=work, daemon=True).start()

    def _prompt_text(self) -> str:
        assert self._prompt
        buf = self._prompt.get_buffer()
        start = buf.get_start_iter()
        end = buf.get_end_iter()
        return buf.get_text(start, end, True).strip()

    def _on_send(self, _btn) -> None:
        if self._busy:
            return
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

        assert self._ws and self._proj and self._created
        wi = self._ws.get_selected()
        if wi < 0 or wi >= len(workspaces):
            self._set_status("Pick a workspace", True)
            return
        ws_id = workspaces[wi]["id"]

        pi = self._proj.get_selected()
        proj_id = "" if pi <= 0 or pi - 1 >= len(projects) else projects[pi - 1]["id"]

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

        self._busy = True
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
                    GLib.idle_add(self._send_fail, err.replace("error: ", ""))
            except Exception as exc:  # noqa: BLE001
                GLib.idle_add(self._send_fail, str(exc))

        threading.Thread(target=work, daemon=True).start()

    def _send_fail(self, err: str) -> None:
        self._busy = False
        self._set_status(err or "Send failed", True)
        if self._send:
            self._send.set_sensitive(True)

    def _send_ok(self, prompt: str) -> None:
        notify("Sent", prompt[:120])
        self._clear_draft()
        self._last_draft = ""
        self._busy = False
        if self._prompt:
            self._prompt.get_buffer().set_text("", -1)
        self._set_status("", False)
        if self._send:
            self._send.set_sensitive(True)
        if self._win:
            self._win.hide()
        self._visible = False


def main() -> int:
    Adw.init()
    app = MulticaPanel()
    return app.run(sys.argv)


if __name__ == "__main__":
    raise SystemExit(main())
