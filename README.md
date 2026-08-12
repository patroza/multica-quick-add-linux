# Multica Quick Add — Walker / Elephant

Linux port of [tim-smart/multica-quick-add](https://github.com/tim-smart/multica-quick-add): capture a free-text prompt from a global hotkey and submit it to Multica’s **quick-create** API so an agent or squad turns it into a well-formed issue.

The upstream project is a native macOS menu-bar app. This fork uses [Walker](https://github.com/abenz1267/walker) (UI) and [Elephant](https://github.com/abenz1267/elephant) (provider menus) on Wayland/Linux.

| Component | Role |
| --- | --- |
| **Walker** | Free-text dmenu prompt and pickers |
| **Elephant** | Optional agent/squad menu (`menus:multicaquickadd`) |
| **multica CLI** | Auth and catalog (`workspace` / `project` / `agent` / `squad`) |
| **Multica HTTP API** | `POST /api/issues/quick-create` |

## Requirements

- [Walker](https://github.com/abenz1267/walker) and [Elephant](https://github.com/abenz1267/elephant)
- [Multica CLI](https://github.com/multica-ai/multica) configured and logged in (`multica setup` / `multica login`)
- `jq`, `curl`, `notify-send`
- Optional: `fzf` (terminal fallback when Walker is unavailable)

## Install

```sh
git clone https://github.com/patroza/multica-quick-add-walker.git
cd multica-quick-add-walker
./install.sh
```

The install script:

1. Symlinks `multica-quick-add` into `~/.local/bin`
2. Symlinks the Elephant menu into `~/.config/elephant/menus/`
3. Registers the Walker provider `menus:multicaquickadd` and prefix `mqa` when a Walker config is present
4. Restarts Walker/Elephant when helper commands are available

Server URL and credentials come only from the local Multica CLI config (`~/.multica/config.json`). This repository does not ship instance URLs or tokens.

## Usage

```sh
# Prompt with last-used workspace / project / agent
multica-quick-add

# Choose workspace, project, and agent first
multica-quick-add --pick

# Save defaults without submitting
multica-quick-add --configure

# Non-interactive
multica-quick-add --agent-id <uuid> "Investigate flaky checkout on mobile"
echo "ship the pricing fix" | multica-quick-add --created-by "Pricing"
multica-quick-add --attachment ./screenshot.png "UI glitch on settings"

# Walker menu
walker -m menus:multicaquickadd
# or type the prefix: mqa
```

Successful submit shows a notification: **Sent to \<agent\>**. Multica enqueues the quick-create task; the agent creates the issue asynchronously.

### Flags

| Flag | Description |
| --- | --- |
| `--pick` | Force workspace / project / created-by pickers |
| `--configure` | Update last-used selections only |
| `--refresh` | Refresh Multica catalog cache |
| `--workspace-id` | Override workspace |
| `--project-id` | Override project (omit or leave empty for none) |
| `--agent-id` / `--squad-id` | Created-by target |
| `--created-by NAME` | Fuzzy match agent or squad name |
| `--attachment PATH` | Attach a file (repeatable) |
| `--no-notify` | Print result to stdout instead of `notify-send` |

### Example compositor bind (niri)

```kdl
// ~/.config/niri/bindings.kdl
Ctrl+Shift+Space hotkey-overlay-title="Multica Quick Add" {
  spawn-sh "multica-quick-add --pick";
}
```

Any global hotkey that runs `multica-quick-add` (or `--pick`) works the same way under Hyprland, Sway, etc.

## Comparison with upstream

| Upstream (macOS) | This fork |
| --- | --- |
| Global hotkey → floating `NSPanel` | Walker `--dmenu --inputonly` |
| In-panel pickers | Walker dmenu (`--pick`) + persisted last-used values |
| Multica CLI for lists | Same |
| Quick-create HTTP API | Same |
| Image paste/drop | `--attachment PATH` |
| Menu bar icon | Elephant menu + Walker prefix `mqa` |

Local state (last selections and catalog cache) is stored under `~/.local/state/multica-quick-add/`.

API details match the upstream plan; see [plan-upstream.md](./plan-upstream.md).

## Development

```sh
./tests/test-payload.sh
```

Payload construction and “no project” normalization are covered offline. End-to-end submit requires a logged-in Multica CLI.

## License

Same spirit as upstream: small utility, no warranty. Upstream Multica and Multica CLI remain under their own licenses.
