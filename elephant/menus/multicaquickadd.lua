-- Multica Quick Add — hub
-- Shows current workspace / project / agent and opens submenus to change them.
-- Primary action: capture a prompt with the current selection.

local home = os.getenv("HOME") or ""
do
  local candidates = {
    home .. "/.local/share/multica-quick-add/multica_common.lua",
    home .. "/.config/elephant/lib/multica_common.lua",
  }
  local which = io.popen("command -v multica-quick-add 2>/dev/null")
  if which then
    local bin = (which:read("*l") or ""):gsub("%s+$", "")
    which:close()
    if bin ~= "" then
      local root = io.popen("readlink -f " .. bin .. " 2>/dev/null | xargs dirname | xargs dirname")
      if root then
        local r = (root:read("*l") or ""):gsub("%s+$", "")
        root:close()
        if r ~= "" then
          table.insert(candidates, 1, r .. "/elephant/lib/multica_common.lua")
        end
      end
    end
  end
  local loaded = false
  for _, path in ipairs(candidates) do
    local fh = io.open(path, "r")
    if fh then
      fh:close()
      common = dofile(path)
      loaded = true
      break
    end
  end
  if not loaded then
    error("multica: missing multica_common.lua (run install.sh)")
  end
end


Name = "multicaquickadd"
NamePretty = "Multica"
Icon = "mail-message-new"
Description = "Quick-create issues for Multica agents"
Cache = false
-- Only watch selections.json — NOT the whole state dir. Watching cache/ made
-- --refresh rewrite catalog → RefreshOnChange → GetEntries → --refresh forever.
RefreshOnChange = { common.state_dir .. "/selections.json" }
SearchName = true
FixedOrder = true
HideFromProviderlist = false
History = false
HistoryWhenEmpty = false
Keywords = { "multica", "quick", "issue", "agent", "mqa" }

function GetEntries()
  local entries = {}
  local sel = common.selection() or {}
  local ready = sel.ready == true or sel.ready == "true"
  local ws = sel.workspace_name or "—"
  local proj = sel.project_title or "No project"
  local agent = sel.created_by_name or "Not set"
  local hint = sel.hint or ""
  local err = sel.error

  -- Do not auto --refresh here (that + RefreshOnChange on cache = fork bomb).

  -- 1) Capture (primary)
  if ready then
    table.insert(entries, {
      Text = "✦ Capture",
      Subtext = hint ~= "" and hint or (agent .. " · " .. proj),
      Value = "capture",
      Icon = common.icon_capture(),
      Keywords = { "capture", "new", "send", "prompt", "issue" },
      Actions = {
        open = "lua:Capture",
      },
    })
  else
    table.insert(entries, {
      Text = "✦ Capture",
      Subtext = err or "Choose an agent first",
      Value = "capture-disabled",
      Icon = common.icon_capture(),
      Keywords = { "capture" },
      Actions = {
        open = "lua:NeedAgent",
      },
    })
  end

  -- 2) Workspace
  table.insert(entries, {
    Text = "🏢  Workspace",
    Subtext = ws,
    Value = "workspace",
    Icon = common.icon_workspace(),
    Keywords = { "workspace", "org", ws },
    -- Elephant Lua API requires "SubMenu" (capital M), not "Submenu".
    SubMenu = "multicaworkspace",
  })

  -- 3) Project
  table.insert(entries, {
    Text = "📁  Project",
    Subtext = proj,
    Value = "project",
    Icon = common.icon_project(),
    Keywords = { "project", proj },
    SubMenu = "multicaproject",
  })

  -- 4) Agent / squad
  local agent_icon = (sel.created_by_kind == "squad") and common.icon_squad() or common.icon_agent()
  local agent_label = "🤖  Send to"
  if sel.created_by_kind == "squad" then
    agent_label = "👥  Send to"
  end
  table.insert(entries, {
    Text = agent_label,
    Subtext = agent,
    Value = "createdby",
    Icon = agent_icon,
    Keywords = { "agent", "squad", "assignee", agent },
    SubMenu = "multicacreatedby",
  })

  -- 5) Refresh
  table.insert(entries, {
    Text = "↻  Refresh catalog",
    Subtext = "Reload projects, agents, and squads",
    Value = "refresh",
    Icon = "view-refresh",
    Keywords = { "refresh", "reload", "sync" },
    Actions = {
      open = "lua:Refresh",
    },
  })

  if not sel.workspace_id or sel.workspace_id == "" then
    table.insert(entries, {
      Text = "⚠  Not configured",
      Subtext = "Run multica login, then pick a workspace",
      Value = "login",
      Icon = "dialog-warning",
      Actions = {
        open = "notify-send 'Multica Quick Add' 'Run: multica setup   then open this hub again'",
      },
    })
  end

  return entries
end

function Capture(_value, _args, _query)
  common.capture()
end

function NeedAgent(_value, _args, _query)
  os.execute(
    "notify-send 'Multica Quick Add' 'Pick an agent or squad under Send to, then Capture again'"
  )
end

function Refresh(_value, _args, _query)
  -- Sync refresh only (user-initiated). Do not chain --hub here; Walker is
  -- already open on this menu and RefreshOnChange will reload labels.
  os.execute(common.shell_quote(common.script()) .. " --refresh --no-notify >/dev/null 2>&1")
  -- Touch selections so hub text reloads without opening a second Walker.
  os.execute("touch " .. common.shell_quote(common.state_dir .. "/selections.json") .. " 2>/dev/null")
  os.execute("notify-send 'Multica Quick Add' 'Catalog refreshed'")
end
