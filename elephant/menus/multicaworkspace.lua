-- Multica · pick workspace (submenu of multicaquickadd)

local home = os.getenv("HOME") or ""
do
  local candidates = {
    home .. "/.config/elephant/menus/_multica_common.lua",
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
          table.insert(candidates, 1, r .. "/elephant/menus/_multica_common.lua")
        end
      end
    end
  end
  for _, p in ipairs(candidates) do
    local f = io.open(p, "r")
    if f then
      f:close()
      common = dofile(p)
      break
    end
  end
end

Name = "multicaworkspace"
NamePretty = "Multica · Workspace"
Icon = "network-workgroup"
Description = "Choose Multica workspace"
Parent = "multicaquickadd"
Cache = false
RefreshOnChange = { common.state_dir }
FixedOrder = true
HideFromProviderlist = true
SearchName = false
History = false

function GetEntries()
  local entries = {}
  local sel = common.selection() or {}
  local current = sel.workspace_id or ""

  -- List workspaces via multica CLI
  local raw = common.run(common.shell_quote(common.multica_bin()) .. " workspace list --output json 2>/dev/null")
  if not raw then
    table.insert(entries, {
      Text = "Could not list workspaces",
      Subtext = "Is multica logged in?",
      Value = "err",
      Actions = { open = "notify-send 'Multica' 'Run multica login'" },
    })
    return entries
  end

  local lines = common.run(
    "printf '%s' " .. common.shell_quote(raw) .. " | jq -r '.[] | [.id, (.name // .id)] | @tsv' 2>/dev/null"
  ) or ""

  for line in lines:gmatch("[^\r\n]+") do
    local id, name = line:match("([^\t]+)\t(.*)")
    if id then
      local is_current = (id == current)
      local entry = {
        Text = (is_current and "●  " or "○  ") .. (name or id),
        Subtext = is_current and "current workspace" or id,
        Value = id,
        Icon = common.icon_workspace(),
        Keywords = { name or id, id, "workspace" },
        Actions = {
          open = "lua:SelectWorkspace",
        },
      }
      if is_current then
        entry.State = { "active", "current" }
      end
      table.insert(entries, entry)
    end
  end

  if #entries == 0 then
    table.insert(entries, {
      Text = "No workspaces",
      Subtext = "Create one in Multica first",
      Value = "empty",
    })
  end

  return entries
end

function SelectWorkspace(value, _args, _query)
  local id = tostring(value or "")
  if id == "" or id == "err" or id == "empty" then
    return
  end
  common.set_and_return("--set-workspace-id " .. common.shell_quote(id) .. " --no-notify")
end
