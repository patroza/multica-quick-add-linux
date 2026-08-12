# Multica Quick Add — Walker / Elephant

Linux fork of [tim-smart/multica-quick-add](https://github.com/tim-smart/multica-quick-add): a Spotlight-style capture bar for sending thoughts to Multica agents.

Tim’s original is a native macOS menu-bar panel. This version uses the stack you already run:

| Layer | Role |
| --- | --- |
| **Walker** | UI (dmenu free-text + pickers) |
| **Elephant** | Provider backend + Lua menu of agents/squads |
| **multica CLI** | Auth + catalog (`workspace` / `project` / `agent` / `squad` list) |
| **Multica API** | `POST /api/issues/quick-create` (same endpoint Tim’s app uses) |

## Requirements

- Walker + Elephant (Omarchy defaults are fine)
- `multica` CLI logged in (`multica setup`)
- `jq`, `curl`, `notify-send`

## Install

```sh
./install.sh
```

This:

1. Symlinks `multica-quick-add` → `~/.local/bin`
2. Symlinks the Elephant menu → `~/.config/elephant/menus/multicaquickadd.lua`
3. Adds Walker provider `menus:multicaquickadd` + prefix `mqa`
4. Restarts Walker/Elephant when possible

## Usage

```sh
# Fast path: free-text prompt, last-used workspace/project/agent
multica-quick-add

# First time / change defaults
multica-quick-add --pick
multica-quick-add --configure

# Explicit
multica-quick-add --agent-id <uuid> "Investigate flaky checkout on mobile"
echo "ship the pricing fix" | multica-quick-add --created-by "Pricing"

# From Walker
walker -m menus:multicaquickadd
# or type prefix: mqa
```

On success you get a notification: **Sent to \<agent\>** (the task is *enqueued*; Multica’s agent turns the prompt into a well-formed issue).

## Suggested hotkey (niri)

Tim uses **⌘⇧Space**. You already map **Ctrl+Shift+Space** to Walker itself. For Multica capture, add e.g.:

```kdl
// ~/.config/niri/bindings.kdl
Ctrl+Shift+M hotkey-overlay-title="Multica Quick Add" {
  spawn-sh "multica-quick-add";
}

// Or open the agent menu first:
// Ctrl+Shift+M { spawn-sh "omarchy-launch-walker -m menus:multicaquickadd"; }
```

## How it maps to Tim’s app

| Tim (macOS) | This fork |
| --- | --- |
| Global hotkey → floating `NSPanel` | Global hotkey → Walker input-only dmenu |
| Workspace / project / created-by pickers | Walker dmenu pickers (`--pick`) + remembered state |
| `~/.multica/config.json` | Same |
| Multica CLI for lists | Same |
| Direct quick-create POST | Same |
| Image paste/drop | `--attachment PATH` (paste pipeline later) |
| Menu bar icon | Elephant menu + Walker prefix `mqa` |

State lives in `~/.local/state/multica-quick-add/` (last selections + catalog cache).

## Upstream plan

See [plan-upstream.md](./plan-upstream.md) (copied from Tim’s repo) for the verified Multica API contract.

## Tests

```sh
./tests/test-payload.sh
```

## Status

**Incubating.** Log in with the Multica CLI first (`multica setup` / `multica login` against your server). Offline unit tests cover payload shape only.

Config and tokens stay in your local `~/.multica/config.json` — this repo never ships instance URLs or credentials.
