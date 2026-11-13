-- features/native_ui.lua: the Lua side of FlameKit's own window (drawn by flamekit_native.dll, not by EMF).
--
-- The DLL only draws and takes clicks; everything it shows comes from here, and every change goes through here, so
-- the DLL never reads the game itself. The two talk through two small files in emf\mods\flamekit, each with one
-- writer (EMF has no channel between a native mod and a Lua mod yet: EMF_REQUESTS.md, 8):
--
--   ui_list.dat     written here when it changed: the Auto Junk List window's content, a line per entry, then "end"
--                   (a file without "end" is half written: the DLL reads it again later)
--                     O <0|1 auto> <drop|delete>                            the options
--                     B <item id hex> <count> <debug name> <name>           an item you carry that is not junk (but can be)
--                     J <item id hex, 0 = unknown> <count carried> <debug name> <name>   an entry of the junk list
--                     P <click key> <0|1 lit> <label>                       one of the feature's settings, as a button
--                                                                           (features/settings.lua: "b:lf_keep_hotbar")
--                   (the name, the game's own text in your language, is the rest of the line)
--   ui_actions.txt  written by the DLL (replaced whole): the last clicks, a line "<number> <what> <argument>":
--                     junk <debug name> | keep <debug name> | dump - | auto 0|1 | action drop|delete
--                   The numbers only grow. A number not seen before is done once. At a (re)load the numbers already
--                   in the file are taken as done, so a click is never done twice.
--   ui_tabs.dat     written here when it changed: the window's tabs and, while the DLL shows one of the generic tabs,
--                   that tab's rows (the same rows the old panel draws, from the feature's panel(world)); fields are
--                   separated by tabs, newlines in a text are written as \n; then "end"
--                     tab <feature id> <title>
--                     view <feature id> <generation>          (the rows below belong to this generation)
--                     r <kind h|t|b|s> <same line 0|1> <selected 0|1> <disabled 0|1> <dim 0|1> <colour rrggbb|-> <button number|0> <text> <tooltip>
--   ui_actions.txt  also: view <feature id>|- (the DLL shows that tab, or none) and tab <feature id>/<generation>/<button
--                   number> (a click on a row's button: done only when the generation is still the one shown) and
--                   key <name> (a key pressed in the window: to the Settings rows waiting for a key, else to the shown
--                   tab's feature key(world, name)) and opt <click key> (a P button of the Auto Junk List's view)
-- Both are runtime files: never deployed or diffed.

local F = { id = "native_ui", title = "Native UI" }

local kit, junk_list
local steps = 0
local last_list = nil   -- ui_list.dat as last written
local done = nil        -- the highest action number done (nil: the file is not read yet since this load)
local view_id = nil     -- the generic tab the DLL shows (nil: none)
local generation = 0    -- of the rows written for it
local keys = {}         -- generation -> { button number -> the feature's key }
local last_rows = nil   -- the rows part as last written (a change makes a new generation)
local last_tabs = nil   -- ui_tabs.dat as last written
local tabs_now = true   -- write ui_tabs.dat on the next step (a view or a click changed it)

function F.setup(k)
  kit = k
  junk_list = require("features.loot_filter.client")
end

local function one_line(text)
  return (tostring(text or ""):gsub("[\r\n]", " "))
end

local function write_list(world)
  local in_bag, junk, opts = junk_list.ui_lists(world)
  if not in_bag then return end
  local lines = { string.format("O %d %s", opts.auto and 1 or 0, opts.action) }
  -- the Auto Junk List's other settings, as buttons on its view (the Settings tab does not show them)
  local settings = require("features.settings")
  lines[#lines + 1] = string.format("P b:lf_keep_hotbar %d Never touch the action bar: %s", kit.setting("lf_keep_hotbar", true) and 1 or 0,
    settings.value_text("lf_keep_hotbar"))
  lines[#lines + 1] = string.format("P k:lf_dump_key:c %d Dump key: %s", settings.capturing() == "lf_dump_key" and 1 or 0,
    settings.value_text("lf_dump_key"))
  for _, e in ipairs(in_bag) do
    lines[#lines + 1] = string.format("B %x %d %s %s", e.item, e.count, e.debug_name, one_line(e.name))
  end
  for _, e in ipairs(junk) do
    lines[#lines + 1] = string.format("J %x %d %s %s", e.item or 0, e.count, e.debug_name, one_line(e.name))
  end
  lines[#lines + 1] = "end"
  local text = table.concat(lines, "\n") .. "\n"
  if text == last_list then return end
  local f = io.open(emf.dir .. "\\ui_list.dat", "w")
  if not f then
    kit.debug("warn", "native ui: ui_list.dat could not be written")
    return
  end
  f:write(text)
  f:close()
  last_list = text
  kit.debug("debug", "native ui: ui_list.dat written: %d in the bag, %d on the junk list, auto %s, %s", #in_bag, #junk,
    tostring(opts.auto), opts.action)
end

local function clean(text)
  return (tostring(text or ""):gsub("[\t\r]", " "):gsub("\n", "\\n"))
end

local function tab_features()  -- the features with a tab, switched on
  local list = {}
  for _, f in ipairs(kit.features) do
    if f.panel and kit.enabled(f) then list[#list + 1] = f end
  end
  return list
end

local function feature(id)
  for _, f in ipairs(kit.features) do
    if f.id == id then return f end
  end
end

local function write_tabs(world)
  local lines = {}
  for _, f in ipairs(tab_features()) do lines[#lines + 1] = "tab\t" .. f.id .. "\t" .. clean(f.title) end
  local f = view_id and feature(view_id)
  if f and view_id ~= "loot_filter" then  -- the Auto Junk List has its own view in the DLL (ui_list.dat)
    local rows = kit.call(f, "panel", world)
    if type(rows) == "table" then
      local body, map = {}, {}
      for _, r in ipairs(rows) do
        local kind = r.separator and "s" or r.heading and "h" or (r.button or r.slot) and "b" or "t"
        local number = 0
        if kind == "b" then
          map[#map + 1] = r.button or r.slot
          number = #map
        end
        local colour = type(r.color) == "string" and r.color:match("^#?(%x%x%x%x%x%x)$") or "-"
        body[#body + 1] = table.concat({ "r", kind, r.same_line and "1" or "0", r.selected and "1" or "0", r.disabled and "1" or "0",
          r.dim and "1" or "0", colour, tostring(number), clean(r.heading or r.text), clean(r.tooltip) }, "\t")
      end
      local text = table.concat(body, "\n")
      if text ~= last_rows then
        last_rows = text
        generation = generation + 1
        keys[generation] = map
        keys[generation - 3] = nil
        kit.debug("debug", "native ui: tab %s: %d row(s), generation %d", view_id, #rows, generation)
      end
      lines[#lines + 1] = "view\t" .. view_id .. "\t" .. generation
      lines[#lines + 1] = text
    end
  end
  lines[#lines + 1] = "end"
  local text = table.concat(lines, "\n") .. "\n"
  if text == last_tabs then return end
  local out = io.open(emf.dir .. "\\ui_tabs.dat", "w")
  if not out then
    kit.debug("warn", "native ui: ui_tabs.dat could not be written")
    return
  end
  out:write(text)
  out:close()
  last_tabs = text
end

local function act(world, what, arg)
  kit.debug("info", "native ui: click from FlameKit's window: %s %s", tostring(what), tostring(arg))
  if what == "junk" or what == "keep" then
    junk_list.ui_set(world, arg, what == "junk")
  elseif what == "dump" then
    junk_list.ui_dump(world)
  elseif what == "auto" or what == "action" then
    junk_list.ui_option(world, what, arg)
  elseif what == "view" then
    view_id = arg ~= "-" and arg or nil
    last_rows = nil
    tabs_now = true
  elseif what == "tab" then
    local id, gen, number = tostring(arg):match("^([%w_]+)/(%d+)/(%d+)$")
    local map = gen and keys[tonumber(gen)]
    local key = map and map[tonumber(number)]
    local f = id and feature(id)
    if f and key then
      kit.call(f, "click", world, key)
    else
      kit.debug("info", "native ui: a click on %s was dropped (the tab changed before it arrived)", tostring(arg))
    end
    last_rows = nil
    tabs_now = true
  elseif what == "key" then  -- a key pressed in the window: the setting waiting for a key (any tab's Change) takes it
    local settings = feature("settings")
    if settings and require("features.settings").capturing() then
      kit.call(settings, "key", world, arg)
    else
      local f = view_id and feature(view_id)
      if f then kit.call(f, "key", world, arg) end
    end
    last_rows = nil
    last_list = nil
    tabs_now = true
  elseif what == "opt" then  -- a setting's button on the Auto Junk List's own view
    local settings = feature("settings")
    if settings then kit.call(settings, "click", world, arg) end
    last_list = nil
  end
end

local function read_actions(world)
  local f = io.open(emf.dir .. "\\ui_actions.txt", "r")
  local text = f and f:read("a") or ""
  if f then f:close() end
  local first = done == nil
  local highest = done or 0
  for line in text:gmatch("[^\r\n]+") do
    local n, what, arg = line:match("^(%d+) (%a+) (%S+)$")
    n = tonumber(n)
    if n and n > (done or math.huge) then
      act(world, what, arg)
      last_list = nil  -- the window shows the change at once
    end
    if n and n > highest then highest = n end
  end
  if first then kit.debug("info", "native ui: ui_actions.txt: clicks up to number %d taken as done (from before this load)", highest) end
  if first or highest > done then done = highest end
end

function F.client_tick(world)
  steps = steps + 1
  if steps % 3 == 0 then read_actions(world) end
  if steps % 10 == 0 or last_list == nil then write_list(world) end
  if steps % 10 == 5 or tabs_now then
    tabs_now = false
    write_tabs(world)
  end
end

return F
