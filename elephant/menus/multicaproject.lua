-- Multica · pick project (submenu of multicaquickadd)

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


Name = "multicaproject"
NamePretty = "Multica · Project"
Icon = "folder"
Description = "Choose Multica project (optional)"
Parent = "multicaquickadd"
Cache = false
RefreshOnChange = { common.state_dir .. "/selections.json" }
FixedOrder = true
HideFromProviderlist = true
SearchName = false
History = false

function GetEntries()
  local entries = {}
  local sel = common.selection() or {}
  local ws = sel.workspace_id or ""
  local current = sel.project_id or ""

  if ws == "" then
    table.insert(entries, {
      Text = "No workspace selected",
      Subtext = "Go back and pick a workspace first",
      Value = "nows",
    })
    return entries
  end

  -- Use cache only; never force-refresh inside GetEntries (loop risk).
  local path = common.catalog_path(ws)
  if not path then
    table.insert(entries, {
      Text = "Catalog unavailable",
      Subtext = "Try Refresh on the Multica hub",
      Value = "nocat",
    })
    return entries
  end

  -- No project
  local none_current = (current == "")
  table.insert(entries, {
    Text = (none_current and "●  " or "○  ") .. "No project",
    Subtext = "Quick-create without a project",
    Value = "__none__",
    Icon = "folder-new",
    Keywords = { "none", "clear", "no project" },
    Actions = { open = "lua:SelectProject" },
    State = none_current and { "active", "current" } or nil,
  })

  local lines = common.run(
    "jq -r '(.projects // [])[] | [.id, (.title // .name // .id)] | @tsv' "
      .. common.shell_quote(path)
      .. " 2>/dev/null"
  ) or ""

  for line in lines:gmatch("[^\r\n]+") do
    local id, title = line:match("([^\t]+)\t(.*)")
    if id then
      local is_current = (id == current)
      table.insert(entries, {
        Text = (is_current and "●  " or "○  ") .. (title or id),
        Subtext = is_current and "current project" or id,
        Value = id,
        Icon = common.icon_project(),
        Keywords = { title or id, id, "project" },
        Actions = { open = "lua:SelectProject" },
        State = is_current and { "active", "current" } or nil,
      })
    end
  end

  return entries
end

function SelectProject(value, _args, _query)
  local id = tostring(value or "")
  if id == "" or id == "nows" or id == "nocat" then
    return
  end
  common.set_and_return("--set-project-id " .. common.shell_quote(id) .. " --no-notify")
end
