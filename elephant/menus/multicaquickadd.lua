-- Multica Quick Add menu for Elephant / Walker
-- Lists agents and squads; activating one opens a free-text prompt and
-- submits Multica quick-create (same path as bin/multica-quick-add).

local home = os.getenv("HOME") or ""
local state_dir = (os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/multica-quick-add"

-- Resolve CLI without host-specific paths. Prefer PATH / install symlink;
-- optional override: MULTICA_QUICK_ADD=/path/to/bin/multica-quick-add
local script = os.getenv("MULTICA_QUICK_ADD") or ""
if script == "" then
  local which = io.popen("command -v multica-quick-add 2>/dev/null")
  if which then
    script = (which:read("*l") or ""):gsub("%s+$", "")
    which:close()
  end
end
if script == "" then
  script = home .. "/.local/bin/multica-quick-add"
end

Name = "multicaquickadd"
NamePretty = "Multica Quick Add"
Icon = "mail-message-new"
Description = "Capture a thought → Multica agent (quick-create)"
Cache = true
RefreshOnChange = { state_dir .. "/cache" }
SearchName = true
FixedOrder = true
HideFromProviderlist = false
History = true
HistoryWhenEmpty = true

local function shell_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function read_cmd(cmd)
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

local function latest_catalog_path()
  local data = read_cmd("ls -1t " .. state_dir .. "/cache/catalog.*.json 2>/dev/null | head -1")
  if not data then
    return nil
  end
  return data:gsub("%s+$", "")
end

function GetEntries()
  local entries = {}

  table.insert(entries, {
    Text = "⚙ Configure defaults…",
    Subtext = "workspace · project · agent",
    Value = "configure",
    Actions = {
      open = "lua:Configure",
    },
  })

  table.insert(entries, {
    Text = "✏ Capture with last agent…",
    Subtext = "reuse last-used Multica selection",
    Value = "capture",
    Actions = {
      open = "lua:CaptureLast",
    },
  })

  -- Warm catalog (writes cache). Ignore failures (not logged in).
  os.execute(shell_quote(script) .. " --refresh >/dev/null 2>&1")

  local catalog_path = latest_catalog_path()
  if not catalog_path or catalog_path == "" then
    table.insert(entries, {
      Text = "Not logged in / no cache",
      Subtext = "run: multica setup",
      Value = "login",
      Actions = {
        open = "notify-send 'Multica Quick Add' 'Run multica setup, then reopen this menu'",
      },
    })
    return entries
  end

  -- agents: id\tname
  local agents = read_cmd(
    "jq -r '(.agents // [])[] | [.id, (.name // .id)] | @tsv' " .. shell_quote(catalog_path) .. " 2>/dev/null"
  )
  if agents then
    for line in agents:gmatch("[^\r\n]+") do
      local id, name = line:match("([^\t]+)\t(.*)")
      if id then
        table.insert(entries, {
          Text = "🤖 " .. (name or id),
          Subtext = "agent · quick-create",
          Value = "agent:" .. id,
          Keywords = { "multica", "agent", name or id },
          Actions = {
            open = "lua:CaptureAgent",
          },
        })
      end
    end
  end

  local squads = read_cmd(
    "jq -r '(.squads // [])[] | [.id, (.name // .id)] | @tsv' " .. shell_quote(catalog_path) .. " 2>/dev/null"
  )
  if squads then
    for line in squads:gmatch("[^\r\n]+") do
      local id, name = line:match("([^\t]+)\t(.*)")
      if id then
        table.insert(entries, {
          Text = "👥 " .. (name or id),
          Subtext = "squad · quick-create",
          Value = "squad:" .. id,
          Keywords = { "multica", "squad", name or id },
          Actions = {
            open = "lua:CaptureSquad",
          },
        })
      end
    end
  end

  return entries
end

function Configure(_value, _args, _query)
  os.execute(shell_quote(script) .. " --configure &")
end

function CaptureLast(_value, _args, _query)
  os.execute(shell_quote(script) .. " &")
end

function CaptureAgent(value, _args, _query)
  local id = tostring(value or ""):gsub("^agent:", "")
  if id == "" then
    return
  end
  os.execute(shell_quote(script) .. " --agent-id " .. shell_quote(id) .. " &")
end

function CaptureSquad(value, _args, _query)
  local id = tostring(value or ""):gsub("^squad:", "")
  if id == "" then
    return
  end
  os.execute(shell_quote(script) .. " --squad-id " .. shell_quote(id) .. " &")
end
