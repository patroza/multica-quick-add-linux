# Multica Quick Add — Walker / Elephant

Linux port of [tim-smart/multica-quick-add](https://github.com/tim-smart/multica-quick-add): capture free-text prompts and submit them to Multica’s **quick-create** API so an agent or squad turns them into well-formed issues.

Upstream is a native macOS menu-bar panel. This fork uses [Walker](https://github.com/abenz1267/walker) + [Elephant](https://github.com/abenz1267/elephant) with a **hub menu** that remembers workspace, project, and agent/squad.

## Multica hub

Open the hub (`multica-quick-add --hub` or Walker prefix `mqa`):

| Row | Action |
| --- | --- |
| **✦ Capture** | Type a prompt and send with the current selection |
| **🏢 Workspace** | Submenu — pick workspace (● marks current) |
| **📁 Project** | Submenu — pick project or “No project” |
| **🤖 / 👥 Send to** | Submenu — pick agent or squad |
| **↻ Refresh catalog** | Reload projects/agents/squads from Multica |

Selections persist under `~/.local/state/multica-quick-add/`. Changing a target reopens the hub with the new values visible.

## Requirements

- Walker and Elephant
- Multica CLI configured and logged in (`multica setup` / `multica login`)
- `jq`, `curl`, `notify-send`
- Optional: `fzf` (CLI wizard fallback when Walker is unavailable)

## Install

```sh
git clone https://github.com/patroza/multica-quick-add-walker.git
cd multica-quick-add-walker
./install.sh
```

Installs:

- `~/.local/bin/multica-quick-add`
- Elephant menus: hub + workspace / project / created-by submenus
- Walker provider `menus:multicaquickadd` and prefix `mqa` (when config exists)

Credentials stay in local `~/.multica/config.json` only.

## Usage

```sh
# Open hub (recommended)
multica-quick-add --hub
walker -m menus:multicaquickadd
# or type prefix: mqa

# Capture immediately with last selection
multica-quick-add
multica-quick-add "Investigate flaky checkout"

# CLI wizard (pickers then prompt)
multica-quick-add --pick

# Inspect / mutate selection (used by the hub)
multica-quick-add --print-selection
multica-quick-add --set-workspace-id <uuid>
multica-quick-add --set-project-id ''          # clear project
multica-quick-add --set-agent-id <uuid>
multica-quick-add --set-squad-id <uuid>
```

Successful submit shows **Sent to \<agent\>**. Multica enqueues the task; the agent creates the issue asynchronously.

### Example compositor bind (niri)

```kdl
// ~/.config/niri/bindings.kdl
Super+Shift+Space hotkey-overlay-title="Multica Quick Add" {
  spawn-sh "multica-quick-add --hub";
}
```

## Comparison with upstream

| Upstream (macOS) | This fork |
| --- | --- |
| Floating panel with pickers | Elephant hub + submenus + prompt dmenu |
| Remember last workspace/project/agent | Same (per-workspace project & created-by) |
| Multica CLI lists + quick-create API | Same |
| Image paste/drop | `--attachment PATH` |

## Development

```sh
./tests/test-payload.sh
```

## License

Small utility; no warranty. Multica and Multica CLI remain under their own licenses.
