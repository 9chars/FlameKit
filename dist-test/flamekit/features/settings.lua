-- features/settings.lua: the Settings tab of FlameKit's window (F4), and the settings rows other tabs show.
--
-- The Settings tab has FlameKit's own settings only (groups "FlameKit" and "FlameKit label") and the switch that turns
-- each feature on or off (a feature switched off has no tab). Every other setting belongs to its feature and is shown
-- in that feature's tab: F.rows(keys) gives the rows for a list of setting keys, with keys "set:..."; the feature's
-- click hands a "set:..." click to F.click without the prefix (the Minimap tab does; the Auto Junk List's own view
-- sends "opt <key>" through ui_actions.txt, native_ui.lua). No setting is shown in two tabs.
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

-- The settings of the Settings tab itself: FlameKit's own groups, and the features' on/off switches.
local function own(s)
  if s.group == "FlameKit" or s.group == "FlameKit label" then return true end
  for _, f in ipairs(kit.features) do
    if f.enabled_setting == s.key then return true end
  end
  return false
end

local function step_of(s)
  local step = tonumber(s.step) or 1
  local range = (tonumber(s.max) or 0) - (tonumber(s.min) or 0)
  if range / step > 40 then step = math.max(step, math.floor(range / 20 / step + 0.5) * step) end
  return step
end

-- The rows of one setting, their keys starting with `prefix` ("" in this tab, "set:" in another feature's tab).
local function setting_rows(rows, s, prefix)
  local v = value(s)
  local label = tostring(s.label or s.key)
  if s.type == "bool" then
    rows[#rows + 1] = { button = prefix .. "b:" .. s.key, text = (v and "On    " or "Off   ") .. label, selected = v == true, tooltip = s.help }
  elseif s.type == "select" and type(s.options) == "table" then
    rows[#rows + 1] = { text = label, tooltip = s.help }
    for i, o in ipairs(s.options) do
      rows[#rows + 1] = { button = prefix .. "s:" .. s.key .. ":" .. i, text = tostring(o.label or o.value), selected = v == o.value,
        same_line = i > 1 }
    end
  elseif s.type == "slider" or s.type == "int" or s.type == "float" then
    rows[#rows + 1] = { text = label .. ": " .. tostring(v), tooltip = s.help }
    local step = step_of(s)
    rows[#rows + 1] = { button = prefix .. "n:" .. s.key .. ":-", text = "- " .. step }
    rows[#rows + 1] = { button = prefix .. "n:" .. s.key .. ":+", text = "+ " .. step, same_line = true }
    rows[#rows + 1] = { button = prefix .. "n:" .. s.key .. ":d", text = "Default (" .. tostring(s.default) .. ")", same_line = true,
      disabled = v == s.default }
  elseif s.type == "keybind" or s.type == "key" then
    local shown = (v == nil or v == "") and "no key" or tostring(v)
    if capturing == s.key then
      rows[#rows + 1] = { color = "#9fd2ff", text = label .. ": press a key now (the window's key or Esc closes the window)" }
    else
      rows[#rows + 1] = { text = label .. ": " .. shown, tooltip = s.help }
    end
    rows[#rows + 1] = { button = prefix .. "k:" .. s.key .. ":c", text = "Change", selected = capturing == s.key }
    rows[#rows + 1] = { button = prefix .. "k:" .. s.key .. ":n", text = "No key", same_line = true, disabled = v == "" }
    rows[#rows + 1] = { button = prefix .. "k:" .. s.key .. ":d", text = "Default (" .. (s.default == "" and "none" or tostring(s.default)) .. ")",
      same_line = true, disabled = v == s.default }
  end
end

-- For another feature's tab: the rows of these settings (keys "set:..."), in this order.
function F.rows(keys)
  if not list then load_list() end
  local rows = {}
  for _, key in ipairs(keys) do
    local s = find(key)
    if s then setting_rows(rows, s, "set:") end
  end
  return rows
end

-- The setting waiting for a key (its key), or nil.
function F.capturing()
  return capturing
end

-- A setting's help text from mod.json ("" without one): for a button's tooltip.
function F.help(key)
  if not list then load_list() end
  local s = find(key)
  return s and type(s.help) == "string" and s.help or ""
end

-- A short text for a setting's value (the Auto Junk List's own view shows its options as buttons).
function F.value_text(key)
  if not list then load_list() end
  local s = find(key)
  if not s then return "?" end
  local v = value(s)
  if s.type == "bool" then return v and "ON" or "OFF" end
  if s.type == "keybind" or s.type == "key" then
    if capturing == key then return "press a key" end
    return (v == nil or v == "") and "none" or tostring(v)
  end
  return tostring(v)
end

function F.panel(world)
  if not list then load_list() end
  local rows = {}
  if note then rows[#rows + 1] = { color = "#ffb060", text = note } end
  local group, features = nil, {}
  for _, s in ipairs(list) do
    if own(s) then
      local is_feature = s.group ~= "FlameKit" and s.group ~= "FlameKit label"
      if is_feature then
        features[#features + 1] = s
      else
        if s.group ~= group then
          group = s.group
          rows[#rows + 1] = { heading = group or "General" }
        end
        setting_rows(rows, s, "")
      end
    end
  end
  if #features > 0 then
    rows[#rows + 1] = { heading = "Features" }
    rows[#rows + 1] = { dim = true, text = "A feature switched off has no tab. Each feature's own settings are in its tab." }
    for _, s in ipairs(features) do setting_rows(rows, s, "") end
  end
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
