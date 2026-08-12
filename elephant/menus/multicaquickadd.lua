-- Multica Quick Add — hub
-- Capture opens a free-text dmenu (not the search filter).
-- Workspace / Project / Send-to open child menus via elephant menu protocol.

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
RefreshOnChange = { common.state_dir .. "/selections.json" }
SearchName = true
FixedOrder = true
HideFromProviderlist = false
History = false
HistoryWhenEmpty = false
Keywords = { "multica", "quick", "issue", "agent", "mqa" }

Actions = {
  open_workspace = "lua:OpenWorkspaceMenu",
  open_project = "lua:OpenProjectMenu",
  open_createdby = "lua:OpenCreatedByMenu",
}

local function open_menu(name)
  os.execute("elephant menu " .. tostring(name) .. " >/dev/null 2>&1")
end

function GetEntries(_query)
  -- Intentionally ignore query for filtering targets: Capture is free-text dmenu.
  local entries = {}
  local sel = common.selection() or {}
  local ready = sel.ready == true or sel.ready == "true"
  local ws = sel.workspace_name or "—"
  local proj = sel.project_title or "No project"
  local agent = sel.created_by_name or "Not set"
  local hint = sel.hint or ""
  local err = sel.error

  if ready then
    table.insert(entries, {
      Text = "✦  Capture",
      Subtext = (hint ~= "" and hint or (agent .. " · " .. proj)) .. "  ·  free-text prompt",
      Value = "capture",
      Icon = common.icon_capture(),
      Keywords = { "capture", "send", "issue", "new", agent, proj },
      Actions = { send = "lua:Capture" },
    })
  else
    table.insert(entries, {
      Text = "✦  Capture",
      Subtext = err or "Set Send to (agent) first",
      Value = "capture-disabled",
      Icon = common.icon_capture(),
      Keywords = { "capture" },
      Actions = { send = "lua:NeedAgent" },
    })
  end

  table.insert(entries, {
    Text = "🏢  Workspace",
    Subtext = ws,
    Value = "workspace",
    Icon = common.icon_workspace(),
    Keywords = { "workspace", ws },
    Actions = { open = "lua:OpenWorkspaceMenu" },
  })

  table.insert(entries, {
    Text = "📁  Project",
    Subtext = proj,
    Value = "project",
    Icon = common.icon_project(),
    Keywords = { "project", proj },
    Actions = { open = "lua:OpenProjectMenu" },
  })

  local agent_icon = (sel.created_by_kind == "squad") and common.icon_squad() or common.icon_agent()
  local agent_label = (sel.created_by_kind == "squad") and "👥  Send to" or "🤖  Send to"
  table.insert(entries, {
    Text = agent_label,
    Subtext = agent,
    Value = "createdby",
    Icon = agent_icon,
    Keywords = { "agent", "squad", "team", agent },
    Actions = { open = "lua:OpenCreatedByMenu" },
  })

  table.insert(entries, {
    Text = "↻  Refresh catalog",
    Subtext = "Reload projects, agents, and squads",
    Value = "refresh",
    Icon = "view-refresh",
    Keywords = { "refresh", "reload" },
    Actions = { open = "lua:Refresh" },
  })

  return entries
end

function Capture(_value, _args, _query)
  -- Always free-text dmenu — never use Walker search as the issue body.
  common.capture()
end

function NeedAgent(_value, _args, _query)
  os.execute(
    "notify-send 'Multica Quick Add' 'Pick Send to (agent/squad) first'"
  )
  -- Do not auto-open Send to (that felt like getting stuck in a submenu).
end

function OpenWorkspaceMenu(_value, _args, _query)
  open_menu("multicaworkspace")
end

function OpenProjectMenu(_value, _args, _query)
  open_menu("multicaproject")
end

function OpenCreatedByMenu(_value, _args, _query)
  open_menu("multicacreatedby")
end

function Refresh(_value, _args, _query)
  os.execute(common.shell_quote(common.script()) .. " --refresh --no-notify >/dev/null 2>&1")
  os.execute("touch " .. common.shell_quote(common.state_dir .. "/selections.json") .. " 2>/dev/null")
  os.execute("notify-send 'Multica Quick Add' 'Catalog refreshed'")
end
