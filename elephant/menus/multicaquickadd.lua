-- Multica Quick Add — hub
-- Type an issue in the search box, Enter on ✦ Send to submit.
-- Workspace / Project / Send-to open child menus (via elephant menu protocol).

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

-- Global menu actions (merged onto every row → Walker keybinds work anytime).
Actions = {
  open_workspace = "lua:OpenWorkspaceMenu",
  open_project = "lua:OpenProjectMenu",
  open_createdby = "lua:OpenCreatedByMenu",
}

local function open_menu(name)
  -- Prefer elephant's menu protocol (ProviderUpdated → Walker switches provider).
  -- Avoid walker -m exclusive mode for the hub so children can display.
  os.execute("elephant menu " .. tostring(name) .. " >/dev/null 2>&1")
end

function GetEntries(query)
  local q = common.trim(query or "")
  local entries = {}
  local sel = common.selection() or {}
  local ready = sel.ready == true or sel.ready == "true"
  local ws = sel.workspace_name or "—"
  local proj = sel.project_title or "No project"
  local agent = sel.created_by_name or "Not set"
  local hint = sel.hint or ""
  local err = sel.error

  -- 1) Primary: type issue text in the search box, Enter on this row to send.
  -- Include the query in Text so fuzzy match keeps this row selected while typing.
  if ready then
    local text
    local sub
    if q == "" then
      text = "✦  Type an issue…"
      sub = (hint ~= "" and hint or (agent .. " · " .. proj)) .. "  ·  Enter to send"
    else
      text = "✦  Send  ·  " .. q
      sub = hint ~= "" and hint or (agent .. " · " .. proj)
    end
    -- Action name "send" (not "open") so Walker can Close after submit,
    -- while picker rows use "open" with after=Nothing.
    table.insert(entries, {
      Text = text,
      Subtext = sub,
      Value = q,
      Icon = common.icon_capture(),
      Keywords = { "capture", "send", "issue", q, agent, proj },
      Actions = {
        send = "lua:Capture",
      },
    })
  else
    table.insert(entries, {
      Text = "✦  Type an issue…",
      Subtext = err or "Choose an agent first (Send to)",
      Value = "",
      Icon = common.icon_capture(),
      Keywords = { "capture", q },
      Actions = {
        send = "lua:NeedAgent",
      },
    })
  end

  -- 2–4) Target pickers — elephant menu protocol (not SubMenu / not walker -m).
  table.insert(entries, {
    Text = "🏢  Workspace",
    Subtext = ws .. "  ·  ctrl+w",
    Value = "workspace",
    Icon = common.icon_workspace(),
    Keywords = { "workspace", "org", "ctrl+w", ws },
    Actions = {
      open = "lua:OpenWorkspaceMenu",
    },
  })

  table.insert(entries, {
    Text = "📁  Project",
    Subtext = proj .. "  ·  ctrl+p",
    Value = "project",
    Icon = common.icon_project(),
    Keywords = { "project", "ctrl+p", proj },
    Actions = {
      open = "lua:OpenProjectMenu",
    },
  })

  local agent_icon = (sel.created_by_kind == "squad") and common.icon_squad() or common.icon_agent()
  local agent_label = "🤖  Send to"
  if sel.created_by_kind == "squad" then
    agent_label = "👥  Send to"
  end
  table.insert(entries, {
    Text = agent_label,
    Subtext = agent .. "  ·  ctrl+t",
    Value = "createdby",
    Icon = agent_icon,
    Keywords = { "agent", "squad", "team", "ctrl+t", agent },
    Actions = {
      open = "lua:OpenCreatedByMenu",
    },
  })

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

function Capture(value, _args, query)
  -- Prefer explicit value (row Value = typed query); fall back to live query.
  local prompt = common.trim(value or "")
  if prompt == "" then
    prompt = common.trim(query or "")
  end
  if prompt == "" then
    -- Fall back to free-text dmenu if opened with empty query.
    common.capture()
    return
  end
  common.run_bg(common.shell_quote(common.script()) .. " " .. common.shell_quote(prompt))
end

function NeedAgent(_value, _args, _query)
  os.execute(
    "notify-send 'Multica Quick Add' 'Pick an agent or squad under Send to, then try again'"
  )
  open_menu("multicacreatedby")
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
