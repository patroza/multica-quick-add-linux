-- Multica · pick agent or squad (submenu of multicaquickadd)

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


Name = "multicacreatedby"
NamePretty = "Multica · Send to"
Icon = "user-available"
Description = "Choose agent or squad for quick-create"
Parent = "multicaquickadd"
Cache = false
RefreshOnChange = { common.state_dir .. "/selections.json" }
FixedOrder = true
HideFromProviderlist = true
SearchName = false
History = true
HistoryWhenEmpty = true

function GetEntries()
  local entries = {}
  local sel = common.selection() or {}
  local ws = sel.workspace_id or ""
  local cur_kind = sel.created_by_kind or ""
  local cur_id = sel.created_by_id or ""

  if ws == "" then
    table.insert(entries, {
      Text = "No workspace selected",
      Subtext = "Go back and pick a workspace first",
      Value = "nows",
    })
    return entries
  end

  local path = common.catalog_path(ws)
  if not path then
    table.insert(entries, {
      Text = "Catalog unavailable",
      Subtext = "Try Refresh on the Multica hub",
      Value = "nocat",
    })
    return entries
  end

  local agents = common.run(
    "jq -r '(.agents // [])[] | [.id, (.name // .id)] | @tsv' "
      .. common.shell_quote(path)
      .. " 2>/dev/null"
  ) or ""
  for line in agents:gmatch("[^\r\n]+") do
    local id, name = line:match("([^\t]+)\t(.*)")
    if id then
      local is_current = (cur_kind == "agent" and id == cur_id)
      table.insert(entries, {
        Text = (is_current and "●  " or "○  ") .. "🤖  " .. (name or id),
        Subtext = is_current and "current · agent" or "agent",
        Value = "agent:" .. id,
        Icon = common.icon_agent(),
        Keywords = { name or id, id, "agent" },
        Actions = { open = "lua:SelectCreatedBy" },
        State = is_current and { "active", "current" } or nil,
      })
    end
  end

  local squads = common.run(
    "jq -r '(.squads // [])[] | [.id, (.name // .id)] | @tsv' "
      .. common.shell_quote(path)
      .. " 2>/dev/null"
  ) or ""
  for line in squads:gmatch("[^\r\n]+") do
    local id, name = line:match("([^\t]+)\t(.*)")
    if id then
      local is_current = (cur_kind == "squad" and id == cur_id)
      table.insert(entries, {
        Text = (is_current and "●  " or "○  ") .. "👥  " .. (name or id),
        Subtext = is_current and "current · squad" or "squad",
        Keywords = { name or id, id, "squad" },
        Value = "squad:" .. id,
        Icon = common.icon_squad(),
        Actions = { open = "lua:SelectCreatedBy" },
        State = is_current and { "active", "current" } or nil,
      })
    end
  end

  if #entries == 0 then
    table.insert(entries, {
      Text = "No agents or squads",
      Subtext = "Create one in Multica, then refresh",
      Value = "empty",
    })
  end

  return entries
end

function SelectCreatedBy(value, _args, _query)
  local v = tostring(value or "")
  local kind, id = v:match("^(%w+):(.+)$")
  if not kind or not id then
    return
  end
  if kind == "agent" then
    common.set_and_return("--set-agent-id " .. common.shell_quote(id) .. " --no-notify")
  elseif kind == "squad" then
    common.set_and_return("--set-squad-id " .. common.shell_quote(id) .. " --no-notify")
  end
end
