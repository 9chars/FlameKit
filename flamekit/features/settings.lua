-- features/settings.lua: the Settings tab of FlameKit's window (F6): every setting from mod.json, grouped as there.
--
-- FlameKit's window draws these rows (the general row drawer in flamekit_native.dll); a click comes back as click(world,
-- key). The settings stay EMF's own settings (mod.json, emf.setting / emf.set_setting), so EMF's Mods tab and EMF.exe
-- show the same values. Per type:
--   bool     one button "On/Off  <label>"
--   select   the label, then a button per option
--   slider   "<label>: <value>", then - and + (bigger steps on long ranges) and Default
--   keybind  "<label>: <key>", then Change (the next key pressed in FlameKit's window: FlameKit's DLL sends it as
--            "key <name>" through ui_actions.txt), No key and Default
--   text     not shown (map_hide is set by the Minimap tab's marker filters)

local F = { id = "settings", title = "Settings" }

local kit
local list = nil        -- the settings from mod.json, in order
local capturing = nil   -- the keybind setting waiting for a key
local note = nil        -- a line under the heading after a change that needs one

local function load_list()
  list = {}
  local f = io.open(emf.dir .. "\\mod.json", "r")
  if not f then return end
  local text = f:read("a") or ""
  f:close()
  local data = emf.json.decode((text:gsub("^\239\187\191", "")))
  if type(data) == "table" and type(data.settings) == "table" then
    for _, s in ipairs(data.settings) do
      if type(s) == "table" and type(s.key) == "string" and s.type ~= "text" then list[#list + 1] = s end
    end
  end
  kit.debug("info", "settings: %d setting(s) read from mod.json", #list)
end

local function find(key)
  for _, s in ipairs(list or {}) do
    if s.key == key then return s end
  end
end

local function value(s)
  return kit.setting(s.key, s.default)
end

local function set(s, v)
  local ok, done = pcall(emf.set_setting, s.key, v)
  kit.debug("info", "settings: %s = %s (%s)", s.key, tostring(v), ok and done ~= false and "saved" or "refused")
  if not ok or done == false then note = "That value was refused: " .. tostring(s.label) end
end

local function step_of(s)
  local step = tonumber(s.step) or 1
  local range = (tonumber(s.max) or 0) - (tonumber(s.min) or 0)
  if range / step > 40 then step = math.max(step, math.floor(range / 20 / step + 0.5) * step) end
  return step
end

function F.panel(world)
  if not list then load_list() end
  local rows = {}
  if note then rows[#rows + 1] = { color = "#ffb060", text = note } end
  local group = nil
  for _, s in ipairs(list) do
    if s.group ~= group then
      group = s.group
      rows[#rows + 1] = { heading = group or "General" }
    end
    local v = value(s)
    local label = tostring(s.label or s.key)
    if s.type == "bool" then
      rows[#rows + 1] = { button = "b:" .. s.key, text = (v and "On    " or "Off   ") .. label, selected = v == true, tooltip = s.help }
    elseif s.type == "select" and type(s.options) == "table" then
      rows[#rows + 1] = { text = label, tooltip = s.help }
      for i, o in ipairs(s.options) do
        rows[#rows + 1] = { button = "s:" .. s.key .. ":" .. i, text = tostring(o.label or o.value), selected = v == o.value,
          same_line = i > 1 }
      end
    elseif s.type == "slider" or s.type == "int" or s.type == "float" then
      rows[#rows + 1] = { text = label .. ": " .. tostring(v), tooltip = s.help }
      local step = step_of(s)
      rows[#rows + 1] = { button = "n:" .. s.key .. ":-", text = "- " .. step }
      rows[#rows + 1] = { button = "n:" .. s.key .. ":+", text = "+ " .. step, same_line = true }
      rows[#rows + 1] = { button = "n:" .. s.key .. ":d", text = "Default (" .. tostring(s.default) .. ")", same_line = true,
        disabled = v == s.default }
    elseif s.type == "keybind" or s.type == "key" then
      local shown = (v == nil or v == "") and "no key" or tostring(v)
      if capturing == s.key then
        rows[#rows + 1] = { color = "#9fd2ff", text = label .. ": press a key now (F6 or Esc closes the window)" }
      else
        rows[#rows + 1] = { text = label .. ": " .. shown, tooltip = s.help }
      end
      rows[#rows + 1] = { button = "k:" .. s.key .. ":c", text = "Change", selected = capturing == s.key }
      rows[#rows + 1] = { button = "k:" .. s.key .. ":n", text = "No key", same_line = true, disabled = v == "" }
      rows[#rows + 1] = { button = "k:" .. s.key .. ":d", text = "Default (" .. (s.default == "" and "none" or tostring(s.default)) .. ")",
        same_line = true, disabled = v == s.default }
    end
  end
  rows[#rows + 1] = { separator = true }
  rows[#rows + 1] = { dim = true, text = "Hold the pointer key (above) to use FlameKit's pinned windows while you play. "
    .. "Ctrl+Shift+F12: FlameKit's log level. The logs are in emf\\mods\\flamekit\\logs in the game's folder." }
  return rows
end

function F.click(world, key)
  note = nil
  local kind, name, arg = tostring(key):match("^(%a):([%w_]+):?(.*)$")
  local s = name and find(name)
  if not s then return end
  if kind ~= "k" then capturing = nil end
  if kind == "b" then
    set(s, not (value(s) == true))
  elseif kind == "s" then
    local o = s.options and s.options[tonumber(arg)]
    if o then set(s, o.value) end
  elseif kind == "n" then
    local v = tonumber(value(s)) or tonumber(s.default) or 0
    if arg == "d" then
      v = s.default
    else
      v = v + (arg == "+" and 1 or -1) * step_of(s)
      v = math.max(tonumber(s.min) or v, math.min(tonumber(s.max) or v, v))
    end
    set(s, v)
  elseif kind == "k" then
    if arg == "c" then
      capturing = capturing ~= s.key and s.key or nil
    else
      capturing = nil
      set(s, arg == "n" and "" or s.default)
    end
  end
end

-- A key pressed in FlameKit's window while a tab of rows is shown: the new key of the setting waiting for one.
function F.key(world, name)
  if not capturing then return end
  local s = find(capturing)
  capturing = nil
  if s and type(name) == "string" and name ~= "" then set(s, name) end
end

function F.setup(k)
  kit = k
end

return F
