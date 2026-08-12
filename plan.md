# Multica Quick Add (Walker / Elephant) — Plan

Fork of Tim Smart’s [multica-quick-add](https://github.com/tim-smart/multica-quick-add)
for Linux desktops using Walker + Elephant.

## Goal

Capture a free-text thought from anywhere, route it through Multica’s
**quick-create** flow so a chosen agent (or squad) turns it into a real issue.

## Decisions

- **No native GUI app.** Walker is the panel; Elephant is the agent menu.
- **Primary entry:** `multica-quick-add` → Walker `--dmenu --inputonly` for the
  prompt, last-used workspace/project/created-by.
- **Secondary entry:** Elephant Lua menu listing agents/squads; pick then prompt.
- **Lists** via Multica CLI (`--output json`); **submit** via HTTP to
  `/api/issues/quick-create` (CLI still has no dedicated quick-create command
  as of multica 0.4.16 — same as Tim’s plan).
- **State** in `~/.local/state/multica-quick-add/` (not gsettings).
- **Notifications** via `notify-send`.
- **Attachments:** CLI flag first; clipboard image paste can come later.

## Quick-create API (from upstream plan, verified by Tim)

```
POST {server_url}/api/issues/quick-create?workspace_id=<uuid>
Authorization: Bearer <token>
Content-Type: application/json

{ "prompt": "...", "agent_id": "<uuid>" }   // or squad_id
// optional: project_id, attachment_ids
```

Config: `~/.multica/config.json` (`server_url`, `token`).

## Layout

```
bin/multica-quick-add           # user-facing CLI
lib/multica-quick-add.sh        # shared helpers
elephant/menus/multicaquickadd.lua
install.sh
tests/test-payload.sh
```

## Milestones

1. **Done:** CLI capture + API submit + last-used state + offline payload tests  
2. **Done:** Elephant menu + install wiring  
3. **Next:** E2E against a logged-in Multica workspace  
4. **Later:** clipboard image → temp file → upload; multi-line prompt UX polish  

## Open questions

- Default hotkey without stealing the main Walker binding?
