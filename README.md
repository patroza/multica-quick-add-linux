# Multica Quick Add (Linux)

Linux port of [tim-smart/multica-quick-add](https://github.com/tim-smart/multica-quick-add): a Spotlight-style capture bar that sends free-text prompts to Multica’s **quick-create** API.

## UIs (pick one)

| UI | Command | Notes |
| --- | --- | --- |
| **Quickshell panel** (recommended) | `multica-quick-add --panel` | Real floating window: live typing + dropdowns (Tim-like) |
| **GTK4 panel** | `multica-quick-add --panel-gtk` | Same idea in GTK/Adwaita for comparison |
| **Walker hub** (legacy) | `multica-quick-add --hub` | List/submenu experiment; not great for free-text |

## Requirements

- Multica CLI logged in (`multica setup` / `multica login`)
- `jq`, `curl`, `notify-send`
- **Quickshell panel:** [quickshell](https://quickshell.org/) (`qs`)
- **GTK panel:** Python 3 + `python-gobject`, GTK4, libadwaita (optional `gtk4-layer-shell`)

## Install

```sh
git clone https://github.com/patroza/multica-quick-add-walker.git
cd multica-quick-add-walker
./install.sh
```

This links CLI tools into `~/.local/bin`, installs the Quickshell config at  
`~/.config/quickshell/multica-quick-add/`, and tries to enable a user systemd unit for the panel daemon.

### Hotkey (niri)

```kdl
Super+Shift+Space hotkey-overlay-title="Multica Quick Add" {
  spawn-sh "multica-quick-add --panel";
}
```

## Usage

```sh
# Toggle Quickshell panel (starts daemon if needed)
multica-quick-add --panel

# GTK comparison panel
multica-quick-add --panel-gtk

# Non-interactive send (uses saved / flag selection)
multica-quick-add --agent-id <uuid> "Investigate flaky checkout"

# Selection helpers
multica-quick-add --print-selection
mqa-bootstrap   # full JSON for panel UIs
```

### Quickshell panel UX

- Type in the text field (characters echo live)
- Choose workspace / project / agent-or-squad
- **⌘/Ctrl+Enter** or **Send** submits; plain **Enter** is a newline; **Esc** dismisses
- Remembers last selection under `~/.local/state/multica-quick-add/`

IPC (daemon must be running):

```sh
qs -c multica-quick-add ipc call panel toggle
qs -c multica-quick-add ipc call panel open
qs -c multica-quick-add ipc call panel close
```

## Layout

```
bin/multica-quick-add      # CLI + launchers
bin/mqa-bootstrap          # JSON bootstrap for panels
lib/multica-quick-add.sh   # shared Multica API / state
panel/quickshell/shell.qml # Quickshell UI
panel/gtk/...panel.py      # GTK UI
elephant/menus/            # legacy Walker hub
```

## License

Small utility; no warranty. Multica remains under its own licenses.
