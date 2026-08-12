# Multica Quick Add (Linux) — `gtk` branch

Linux port of [tim-smart/multica-quick-add](https://github.com/tim-smart/multica-quick-add).

**This branch** makes the **GTK4/Adwaita** floating panel the default (`--panel`).
`main` keeps Quickshell as the default UI.

## UIs

| UI | Command | Notes |
| --- | --- | --- |
| **GTK4 panel** (this branch) | `multica-quick-add --panel` | Live typing + dropdowns; single-instance toggle |
| **Quickshell panel** | `multica-quick-add --panel-qs` | QML UI from `main` |
| **Walker hub** (legacy) | `multica-quick-add --hub` | List/submenu experiment |

## Requirements

- Multica CLI logged in (`multica setup` / `multica login`)
- `jq`, `curl`, `notify-send`
- **GTK panel:** Python 3 + `python-gobject`, GTK4, libadwaita  
  Optional: `gtk4-layer-shell` (install preloads it for overlay positioning)
- **Quickshell panel (optional):** [quickshell](https://quickshell.org/) (`qs`)

## Install

```sh
git clone https://github.com/patroza/multica-quick-add-linux.git
cd multica-quick-add-linux
git checkout gtk
./install.sh
```

### Hotkey (niri)

```kdl
Super+Shift+Space hotkey-overlay-title="Multica Quick Add" {
  spawn-sh "multica-quick-add --panel";
}
```

## Usage

```sh
# Toggle GTK panel (hotkey target)
multica-quick-add --panel

# Quickshell comparison
multica-quick-add --panel-qs

# Non-interactive send
multica-quick-add --agent-id <uuid> "Investigate flaky checkout"
```

### Panel UX

- Type in the text field (characters echo live)
- Choose workspace / project / agent-or-squad
- **⌘/Ctrl+Enter** or **Send** submits; plain **Enter** is a newline; **Esc** dismisses
- Re-triggering the hotkey toggles the panel (GApplication single-instance)
- Remembers last selection under `~/.local/state/multica-quick-add/`

## Layout

```
bin/multica-quick-add      # CLI + launchers
bin/mqa-bootstrap          # JSON bootstrap for panels
lib/multica-quick-add.sh   # shared Multica API / state
panel/gtk/...panel.py      # GTK UI (default on this branch)
panel/quickshell/shell.qml # Quickshell UI
elephant/menus/            # legacy Walker hub
```

## License

Small utility; no warranty. Multica remains under its own licenses.
