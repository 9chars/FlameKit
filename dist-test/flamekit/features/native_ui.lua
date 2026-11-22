-- features/native_ui.lua: the Lua side of FlameKit's own window (drawn by flamekit_native.dll, not by EMF).
--
-- The DLL only draws and takes clicks; everything it shows comes from here, and every change goes through here, so
-- the DLL never reads the game itself. The two talk through two small files in emf\mods\flamekit, each with one
-- writer (EMF has no channel between a native mod and a Lua mod yet: EMF_REQUESTS.md, 8):
--
--   ui_list.dat     written here when it changed: the Auto Junk List window's content, a line per entry, then "end"
--                   (a file without "end" is half written: the DLL reads it again later)
--                     O <0|1 auto> <drop|delete>                            the options
--                     B<tab><item id hex><tab><count><tab><debug name><tab><rarity 0-4|-1><tab><item level><tab><type><tab><name>
--                                                                           an item you carry that is not junk (but can be)
--                     J<tab>... the same                                    an entry of the junk list (id 0: unknown)
--                     P <click key> <0|1 lit> <label><tab><tooltip>         one of the feature's settings, as a button
--                     W <tab><text>                                          a warning over the bag, in red (0.15.49: Auto-Collect
--                                                                            Scattered Loot is on while junk is dropped)
--                                                                           (features/settings.lua: "b:lf_show_all")
--                   (B and J are item tiles: core/items.lua items.tip; the DLL draws every item tile and its tooltip the same
--                   way: the name in its rarity's colour, item level, rarity, type, carried, command name)
--   ui_actions.txt  written by the DLL (replaced whole): the last clicks, a line "<number> <what> <argument>":
--                     junk <debug name> | keep <debug name> | dump - | auto 0|1 | action drop|delete
--                   The numbers only grow. A number not seen before is done once. At a (re)load the numbers already
--                   in the file are taken as done, so a click is never done twice.
--   ui_tabs.dat     written here when it changed: the window's tabs and, while the DLL shows one of the generic tabs,
--                   that tab's rows (the same rows the old panel draws, from the feature's panel(world)); fields are
--                   separated by tabs, newlines in a text are written as \n; then "end"
--                     tab <feature id> <title>
--                     view <feature id> <generation>          (the rows below belong to this generation)
--                     r <kind h|t|b|s|i> <same line 0|1> <selected 0|1> <disabled 0|1> <dim 0|1> <colour rrggbb|-> <button number|0> <text> <tooltip>
--                       kind l: a label on a line of buttons; kind d (0.15.73): a drop-down, its text the entry
--                       chosen, then one field per entry: <number>\31<h heading|o entry|s chosen>\31<rrggbb|->\31<label>
--                       (a click on an entry comes back as a row button's number)
--                       and for an item tile (kind i: a row with item = <id>, count = <n>, text = its name, tooltip =
--                       what a click does): <item id hex> <count> <rarity> <item level> <type> <command name>
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

-- Keeps kit and the Auto Junk List's game half (the list view's data).
function F.setup(k)
  kit = k
  junk_list = require("features.loot_filter.client")
end

-- Text on one line (line breaks become spaces).
local function one_line(text)
  return (tostring(text or ""):gsub("[\r\n]", " "))
end

-- Writes ui_list.dat: the Auto Junk List's view (its options, the bag's items, the junk list) for FlameKit Native.
local function write_list(world)
  local in_bag, junk, opts = junk_list.ui_lists(world)
  if not in_bag then return end
  local lines = { string.format("O %d %s", opts.auto and 1 or 0, opts.action) }
  -- the Auto Junk List's other settings, as buttons on its view (the Settings tab does not show them)
  local settings = require("features.settings")
  local function opt(click, lit, label, key)  -- a button, and its tooltip: the setting's help from mod.json
    lines[#lines + 1] = string.format("P %s %d %s\t%s", click, lit and 1 or 0, label, one_line(settings.help(key)))
  end
  opt("b:lf_show_all", kit.setting("lf_show_all", false), "Show All Bag Items: " .. settings.value_text("lf_show_all"), "lf_show_all")
  opt("k:lf_dump_key:c", settings.capturing() == "lf_dump_key", "Set Dump Key: " .. settings.value_text("lf_dump_key"), "lf_dump_key")
  local items = kit.items
  -- One item tile's line: kind (B bag, J junk), item id, count, names, rarity, level, type.
  local function tile(kind, e)
    local t = items.tip(e.item, e.debug_name)
    return table.concat({ kind, string.format("%x", e.item or 0), tostring(e.count or 0), e.debug_name, tostring(t.rarity), t.level,
      one_line(t.type), one_line(e.name) }, "\t")
  end
  local warning = junk_list.ui_warning()  -- the Auto-Collect Scattered Loot conflict: a red line over the bag
  if warning then lines[#lines + 1] = "W\t" .. one_line(warning) end
  for _, e in ipairs(in_bag) do lines[#lines + 1] = tile("B", e) end
  for _, e in ipairs(junk) do lines[#lines + 1] = tile("J", e) end
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

-- Text for one field of ui_tabs.dat (no tabs; line breaks as \n).
local function clean(text)
  return (tostring(text or ""):gsub("[\t\r]", " "):gsub("\n", "\\n"))
end

local function tab_features()  -- the features with a tab, switched on
  local list = {}
  for _, f in ipairs(kit.features) do
    if (f.panel or f.own_view) and kit.enabled(f) then list[#list + 1] = f end
  end
  return list
end

-- The loaded feature with id `id`.
local function feature(id)
  for _, f in ipairs(kit.features) do
    if f.id == id then return f end
  end
end

-- Rows (a feature's tab or the Experimental window) as ui_tabs.dat "r" lines, and the click keys by button number.
local function rows_lines(rows)
  local body, map = {}, {}
  for _, r in ipairs(rows) do
    -- (0.15.309) kind e: a text box (r.edit = its click key, r.text = the text in it); the typed text comes back with
    -- the click ("<generation>/<number>/<text as hex>")
    local kind = r.separator and "s" or r.heading and "h" or r.item and "i" or r.options and "d" or r.edit and "e"
      or r.label and "l" or (r.button or r.slot) and "b" or "t"
    local number = 0
    if (kind == "b" or kind == "i" or kind == "e") and (r.button or r.slot or r.edit) then
      map[#map + 1] = r.button or r.slot or r.edit
      number = #map
    end
    local colour = type(r.color) == "string" and r.color:match("^#?(%x%x%x%x%x%x)$") or "-"
    local fields = { "r", kind, r.same_line and "1" or "0", r.selected and "1" or "0", r.disabled and "1" or "0",
      r.dim and "1" or "0", colour, tostring(number), clean(r.heading or r.text), clean(r.tooltip) }
    if kind == "d" then  -- a drop-down: its entries, each "<number>\31<h|o|s>\31<rrggbb|->\31<label>"
      for _, o in ipairs(r.options) do
        local n = 0
        if o.key then
          map[#map + 1] = o.key
          n = #map
        end
        local c = type(o.color) == "string" and o.color:match("^#?(%x%x%x%x%x%x)$") or "-"
        fields[#fields + 1] = table.concat({ tostring(n), o.heading and "h" or o.selected and "s" or "o", c,
          (clean(o.text):gsub("\31", " ")) }, "\31")
      end
    elseif kind == "i" then  -- an item tile: its details for the tooltip (core/items.lua items.tip)
      local debug_name = kit.items.debug_name(r.item)
      local t = kit.items.tip(r.item, debug_name)
      for _, v in ipairs({ string.format("%x", r.item), tostring(r.count or 0), tostring(t.rarity), t.level, clean(t.type),
                           clean(debug_name or "") }) do fields[#fields + 1] = v end
    end
    body[#body + 1] = table.concat(fields, "\t")
  end
  return table.concat(body, "\n"), map
end

-- Writes ui_tabs.dat: the tabs and the rows of the tab shown now, for FlameKit Native.
local function write_tabs(world)
  local lines = {}
  for _, f in ipairs(tab_features()) do lines[#lines + 1] = "tab\t" .. f.id .. "\t" .. clean(f.title) end
  local f = view_id and feature(view_id)
  if f and view_id ~= "loot_filter" then  -- the Auto Junk List has its own view in the DLL (ui_list.dat)
    local rows = kit.call(f, "panel", world)
    if type(rows) == "table" then
      local text, map = rows_lines(rows)
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

-- FlameKit's Experimental window (0.15.74): the rows of features/experimental.lua F.window_rows in ui_exp.dat, a line
-- "gen <generation>", the "r" lines (as in ui_tabs.dat), then "end". Written when they change (looked at every 10
-- steps, and at once after a click); a click comes back as "exp <generation>/<button number>".
local exp_gen, exp_keys, last_exp, exp_now = 0, {}, nil, true
-- Writes ui_exp.dat: the Experimental window's rows, when they changed.
local function write_exp(world)
  local f = feature("experimental")
  local rows = f and kit.enabled(f) and f.window_rows and kit.call(f, "window_rows", world)
  if type(rows) ~= "table" then rows = {} end
  local text, map = rows_lines(rows)
  if text == last_exp then return end
  last_exp = text
  exp_gen = exp_gen + 1
  exp_keys[exp_gen] = map
  exp_keys[exp_gen - 3] = nil
  local out = io.open(emf.dir .. "\\ui_exp.dat", "w")
  if not out then
    kit.debug("warn", "native ui: ui_exp.dat could not be written")
    last_exp = nil
    return
  end
  out:write("gen\t" .. exp_gen .. "\n" .. text .. (text ~= "" and "\n" or "") .. "end\n")
  out:close()
  kit.debug("debug", "native ui: ui_exp.dat: %d row(s), generation %d", #rows, exp_gen)
end

-- (0.15.309, owner 2026-11-20 10:00: "Companion Roster needs to be its own complete window") the Companion Roster
-- window: the same kind of window as the Experimental one, its rows from features/npc_wheel_probe.lua F.roster_rows in
-- ui_roster.dat; a click comes back as "ros <generation>/<button number>[/<typed text as hex>]" and goes to
-- F.roster_click(world, key, text). The DLL shows and hides it when ui_roster_toggle.request appears (written by the
-- feature's button).
local ros_gen, ros_keys, last_ros, ros_now = 0, {}, nil, true
-- Writes ui_roster.dat: the Companion Roster window's rows, when they changed.
local function write_ros(world)
  local f = feature("npc_wheel_probe")
  local rows = f and kit.enabled(f) and f.roster_rows and kit.call(f, "roster_rows", world)
  if type(rows) ~= "table" then rows = {} end
  local text, map = rows_lines(rows)
  if text == last_ros then return end
  last_ros = text
  ros_gen = ros_gen + 1
  ros_keys[ros_gen] = map
  ros_keys[ros_gen - 3] = nil
  local out = io.open(emf.dir .. "\\ui_roster.dat", "w")
  if not out then
    kit.debug("warn", "native ui: ui_roster.dat could not be written")
    last_ros = nil
    return
  end
  out:write("gen\t" .. ros_gen .. "\n" .. text .. (text ~= "" and "\n" or "") .. "end\n")
  out:close()
  kit.debug("debug", "native ui: ui_roster.dat: %d row(s), generation %d", #rows, ros_gen)
end

-- Text from hex digits (what a player typed, sent by FlameKit Native).
local function unhex(h)
  return (tostring(h or ""):gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end))
end

-- One click or typed value from FlameKit's window: hands it to the feature it belongs to.
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
    exp_now = true
  elseif what == "wp" then  -- a click on a minimap marker (0.15.75): the waypoint there, or "clear"
    local f = feature("experimental")
    if f and f.minimap_waypoint then kit.call(f, "minimap_waypoint", world, arg) end
  elseif what == "exp" then  -- a click in the Experimental window
    local gen, number = tostring(arg):match("^(%d+)/(%d+)$")
    local map = gen and exp_keys[tonumber(gen)]
    local key = map and map[tonumber(number)]
    local f = feature("experimental")
    if f and key then
      kit.call(f, "click", world, key)
    else
      kit.debug("info", "native ui: a click in the Experimental window on %s was dropped (it changed before it arrived)", tostring(arg))
    end
    exp_now = true
    tabs_now = true
  elseif what == "ros" then  -- a click in the Companion Roster window (a text box's Enter carries the text)
    local gen, number, typed = tostring(arg):match("^(%d+)/(%d+)/?(%x*)$")
    local map = gen and ros_keys[tonumber(gen)]
    local key = map and map[tonumber(number)]
    local f = feature("npc_wheel_probe")
    if f and key and f.roster_click then
      kit.call(f, "roster_click", world, key, typed ~= "" and unhex(typed) or nil)
    else
      kit.debug("info", "native ui: a click in the Companion Roster window on %s was dropped (it changed before it arrived)", tostring(arg))
    end
    ros_now = true
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

-- Reads ui_actions.txt (FlameKit Native's clicks, numbered) and acts on the new ones.
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

-- Every step of the player's game: reads the clicks, and writes the list, tabs, Experimental and roster files in turn (each every 10 steps, or at once when asked).
function F.client_tick(world)
  steps = steps + 1
  if steps % 3 == 0 then read_actions(world) end
  if steps % 10 == 0 or last_list == nil then write_list(world) end
  if steps % 10 == 5 or tabs_now then
    tabs_now = false
    write_tabs(world)
  end
  if steps % 10 == 7 or exp_now then
    exp_now = false
    write_exp(world)
  end
  if steps % 10 == 3 or ros_now then
    ros_now = false
    write_ros(world)
  end
end

return F
