-- Shared helpers for Multica Elephant hub menus.
-- Loaded via dofile from sibling menu scripts (not a menu itself).

local M = {}

local home = os.getenv("HOME") or ""
M.state_dir = (os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/multica-quick-add"

function M.shell_quote(s)
  return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end

function M.read_cmd(cmd)
  local h = io.popen(cmd)
  if not h then
    return nil
  end
  local data = h:read("*a")
  h:close()
  if not data or data == "" then
    return nil
  end
  return data
end

function M.trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function first_existing(paths)
  for _, p in ipairs(paths) do
    local f = io.open(p, "r")
    if f then
      f:close()
      return p
    end
  end
  return nil
end

-- Resolve multica-quick-add CLI
function M.script()
  local override = os.getenv("MULTICA_QUICK_ADD")
  if override and override ~= "" then
    return override
  end
  local which = M.read_cmd("command -v multica-quick-add 2>/dev/null")
  if which and M.trim(which) ~= "" then
    return M.trim(which)
  end
  return first_existing({
    home .. "/.local/bin/multica-quick-add",
    "/usr/local/bin/multica-quick-add",
  }) or (home .. "/.local/bin/multica-quick-add")
end

function M.multica_bin()
  local which = M.read_cmd("command -v multica 2>/dev/null")
  if which and M.trim(which) ~= "" then
    return M.trim(which)
  end
  return first_existing({
    home .. "/.local/bin/multica",
    "/usr/local/bin/multica",
    "/usr/bin/multica",
  }) or "multica"
end

function M.run_bg(cmdline)
  os.execute(cmdline .. " >/dev/null 2>&1 &")
end

function M.run(cmdline)
  return M.read_cmd(cmdline)
end

function M.selection()
  local raw = M.run(M.shell_quote(M.script()) .. " --print-selection --no-notify 2>/dev/null")
  if not raw then
    return nil
  end
  -- Prefer jq for robust parse (jsonDecode may be available as jsonDecodes)
  local ok, decoded = pcall(function()
    if type(jsonDecode) == "function" then
      return jsonDecode(raw)
    end
    if type(jsonDecodes) == "function" then
      return jsonDecodes(raw)
    end
    return nil
  end)
  if ok and type(decoded) == "table" then
    return decoded
  end
  -- Fallback: extract fields with jq
  local function j(field)
    return M.trim(M.run("printf '%s' " .. M.shell_quote(raw) .. " | jq -r " .. M.shell_quote("." .. field .. " // empty") .. " 2>/dev/null") or "")
  end
  return {
    ready = j("ready") == "true",
    workspace_id = j("workspace_id"),
    workspace_name = j("workspace_name"),
    project_id = j("project_id"),
    project_title = j("project_title"),
    created_by_kind = j("created_by_kind"),
    created_by_id = j("created_by_id"),
    created_by_name = j("created_by_name"),
    hint = j("hint"),
    error = j("error"),
  }
end

function M.catalog_path(workspace_id)
  if not workspace_id or workspace_id == "" then
    return nil
  end
  local p = M.state_dir .. "/cache/catalog." .. workspace_id .. ".json"
  local f = io.open(p, "r")
  if f then
    f:close()
    return p
  end
  return nil
end

function M.ensure_catalog(workspace_id)
  M.run(M.shell_quote(M.script()) .. " --refresh --no-notify 2>/dev/null")
  return M.catalog_path(workspace_id)
end

function M.set_and_return(args)
  -- Persist, notify, then bounce Walker back to the hub via elephant menu.
  M.run_bg(M.shell_quote(M.script()) .. " " .. args .. " --reopen-hub")
end

function M.capture()
  -- Close hub first (walker can't host hub + prompt dmenu at once), then prompt.
  -- Small delay so Walker releases the bus name before the capture process starts.
  M.run_bg(
    "walker --close >/dev/null 2>&1 || walker -q >/dev/null 2>&1 || true; "
      .. "sleep 0.25; "
      .. M.shell_quote(M.script())
  )
end


function M.icon_agent()
  return "user-available"
end

function M.icon_squad()
  return "system-users"
end

function M.icon_project()
  return "folder"
end

function M.icon_workspace()
  return "network-workgroup"
end

function M.icon_capture()
  return "mail-message-new"
end

return M
