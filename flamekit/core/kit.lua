-- core/kit.lua: what every feature shares.
--
-- A feature is a Lua file that returns a table:
--   id               "loot_filter"  (letters, digits, _)
--   title            "Auto Junk List"  (its tab in FlameKit's window, F6)
--   enabled_setting  the bool setting in mod.json that switches it on and off (optional)
--   setup(kit)       once, while the mod loads: register events, keys and commands here (wrap them in kit.guard)
--   tick(world)      every step of a world you host (the server world): gameplay changes go here
--   client_tick(world)  every step of your own screen's world (HUD lines)
--   panel(world)     the rows of its tab in FlameKit's window (features/native_ui.lua: heading, text, button,
--                    separator; same_line, selected, disabled, dim, tooltip, color); keys are the feature's own
--   click(world, key)  a click on one of its rows' buttons
--   key(world, name) a key pressed in FlameKit's window while its tab shows (the key's name as EMF's settings write it)
--   setting_changed(key)
--   connected(world) false while this feature cannot reach its server half on a joined server (the label says so)
-- Every call is protected: a feature that raises an error is switched off until the next reload, the others go on.

local kit = { features = {}, name = "FlameKit", version = "?", author = "" }

kit.store = require("core.store")
kit.items = require("core.items")
kit.bag = require("core.bag")
-- FlameKit's window draws a tab's text this many text heights wide: for features that fit lines of their own. (The old
-- panel that EMF drew, core/hub.lua, was removed in 0.15.26: FlameKit's UI is drawn by FlameKit's DLL only.)
kit.hub = { WIDTH = 46 }

local server_seen = 0  -- os.time() of the last server step: a server world runs only in a game you host

-- True while you host the world (single-player, or friends joined your game). Gameplay changes work only then.
function kit.is_host()
  return os.time() - server_seen <= 2
end

-- True when version text `a` ("0.15.2") is newer than `b`.
function kit.newer(a, b)
  local x, y = {}, {}
  for n in tostring(a):gmatch("%d+") do x[#x + 1] = tonumber(n) end
  for n in tostring(b):gmatch("%d+") do y[#y + 1] = tonumber(n) end
  if #x == 0 then return false end
  for i = 1, math.max(#x, #y) do
    local p, q = x[i] or 0, y[i] or 0
    if p ~= q then return p > q end
  end
  return false
end

function kit.log(...)
  emf.log(...)
end

-- The debug level, from debug.txt in the mod's folder (FlameKit's DLL reads the same file; Ctrl+Shift+F12 in the game
-- changes it): "off", "normal" (also when the file is missing) or "full". Read again every 2 seconds (fresh: now).
local level_name, level_checked = "normal", -10
function kit.debug_level(fresh)
  local now = os.time()
  if fresh or now - level_checked >= 2 then
    level_checked = now
    local f = io.open(emf.dir .. "\\debug.txt", "r")
    local word = f and f:read("l") or ""
    if f then f:close() end
    word = (word or ""):lower():match("^%s*(%a+)") or ""
    level_name = (word == "off" or word == "full") and word or "normal"
  end
  return level_name
end

-- A line for the log (EMF's log, which FlameKit's DLL copies into FlameKit's own log). level: "error" and "warn" are
-- always written, "info" at normal and full, "debug" only at full. fmt and the rest as for string.format.
function kit.debug(level, fmt, ...)
  if level == "info" and kit.debug_level() == "off" then return end
  if level == "debug" and kit.debug_level() ~= "full" then return end
  local text = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
  emf.log(string.upper(level) .. " " .. text)
end

-- A setting's value, or `default` where this EMF does not know the key yet (mod.json is read at game start).
function kit.setting(key, default)
  local ok, value = pcall(emf.setting, key)
  if ok and value ~= nil then return value end
  return default
end

local messages = {}       -- the last messages, oldest first: {n, colour, text}
local message_n = 0       -- the number of the newest message (they only grow; a new number shows the Messages window)
local messages_dirty = false
local hud_written = nil   -- ui_hud.dat as last written
local MOST_MESSAGES = 20

-- A message in FlameKit's Messages window (drawn by FlameKit's DLL; it shows itself for a few seconds when a message
-- comes, and with the last ones while the pointer key is held): what a feature just did ("Junk discarded: Twigs x3"),
-- in `colour` ("#rrggbb"; orange without). The player can switch these off (setting notify), except the ones with
-- `always` (warnings the player has to see). Also written to the log. emf\mods\flamekit\ui_messages.dat:
--   m <number> <rrggbb> <text>     (the last 20, oldest first)
--   end                            (a file without it is half written: the DLL reads it again later)
function kit.note(text, colour, always)
  emf.log(tostring(text))
  if not always and not kit.setting("notify", true) then return end
  message_n = message_n + 1
  messages[#messages + 1] = { n = message_n, colour = (type(colour) == "string" and colour:match("^#?(%x%x%x%x%x%x)$")) or "ffb060",
    text = (tostring(text):gsub("[%c]", " ")) }
  if #messages > MOST_MESSAGES then table.remove(messages, 1) end
  messages_dirty = true
end

-- Notices (since 0.15.54): warnings that stay on screen in FlameKit's Notices window until the feature takes them back,
-- written into emf\mods\flamekit\ui_notices.dat: "n <tag> <rrggbb> <text>" lines, then "end" (DLL: NoticeLayer).
-- kit.notice(tag, text, colour) puts one up (or changes it), kit.notice(tag) takes it back. The file is written at the
-- next step; after a reload of FlameKit it is written again (empty until the features say otherwise).
local notices = {}        -- tag -> { colour, text, order }
local notice_order = 0
local notices_dirty = true

function kit.notice(tag, text, colour)
  if type(tag) ~= "string" or not tag:match("^[%w_%.]+$") then return end
  if text == nil then
    if notices[tag] then
      notices[tag] = nil
      notices_dirty = true
    end
    return
  end
  local c = (type(colour) == "string" and colour:match("^#?(%x%x%x%x%x%x)$")) or "ff5a50"
  local t = (tostring(text):gsub("[%c]", " "))
  local had = notices[tag]
  if had and had.text == t and had.colour == c then return end
  if not had then notice_order = notice_order + 1 end
  notices[tag] = { colour = c, text = t, order = had and had.order or notice_order }
  notices_dirty = true
end

local function write_notices()
  if not notices_dirty then return end
  local list = {}
  for tag, n in pairs(notices) do list[#list + 1] = { tag = tag, n = n } end
  table.sort(list, function(a, b) return a.n.order < b.n.order end)
  local lines = {}
  for _, e in ipairs(list) do lines[#lines + 1] = string.format("n %s %s %s", e.tag, e.n.colour, e.n.text) end
  lines[#lines + 1] = "end"
  local f = io.open(emf.dir .. "\\ui_notices.dat", "w")
  if not f then
    kit.debug("warn", "notices: ui_notices.dat could not be written")
    return
  end
  f:write(table.concat(lines, "\n") .. "\n")
  f:close()
  notices_dirty = false
  kit.debug("info", "notices: %d on screen", #list)
end

local function write_messages()
  if not messages_dirty then return end
  local lines = {}
  for _, m in ipairs(messages) do lines[#lines + 1] = string.format("m %d %s %s", m.n, m.colour, m.text) end
  lines[#lines + 1] = "end"
  local f = io.open(emf.dir .. "\\ui_messages.dat", "w")
  if not f then
    kit.debug("warn", "messages: ui_messages.dat could not be written")
    return
  end
  f:write(table.concat(lines, "\n") .. "\n")
  f:close()
  messages_dirty = false
  kit.debug("debug", "messages: ui_messages.dat written (%d message(s), newest %d)", #messages, message_n)
end

-- True when every feature that talks to a server half can reach it (always in a world you host).
function kit.connected(world)
  if kit.is_host() then return true end
  for _, f in ipairs(kit.features) do
    if f.connected and kit.enabled(f) and kit.call(f, "connected", world) == false then return false end
  end
  return true
end

-- Each step of your own screen's world: the lines in the lower left corner, drawn by FlameKit's DLL (not by EMF): the
-- "FlameKit v1.2.3 by Name" label and the notice, written into emf\mods\flamekit\ui_hud.dat when they change:
--   label <text>              ("" when the player switched the label off)
--   notice <text>             (orange, under the label: this server does not run FlameKit, or an older one)
--   build 1                   (0.15.59: the player is in build mode and ui_hide_build is on: the DLL hides every
--                              window that does not opt out, all but these lines and FlameKit's window)
--   end                       (a file without it is half written: the DLL reads it again later)
-- The updater's line under the label comes from the DLL itself. ui_hud.dat is a runtime file: never deployed.
-- Build mode (0.15.59): the game's building cursor, ClientPlayerInput.data.cursorInput.primaryTransform of your own
-- player in your game's world, is all zero outside build mode (EMF docs, engine_parts/re_villager_jobs.md, for the
-- server's copy of the same input). Any non-zero position: building.
local build_was = nil
local function in_build_mode(world)
  local me = emf.local_player()
  if not me or me == 0 then return false end
  local ok, on = pcall(function()
    local input = world:get("ClientPlayerInput", me)
    if not input then return false end
    local p = input.data.cursorInput.primaryTransform.position
    return p.x ~= 0 or p.y ~= 0 or p.z ~= 0
  end)
  on = ok and on == true
  if on ~= build_was then
    if not ok and build_was == nil then kit.debug("info", "build mode: cannot be read here (%s)", tostring(on)) end
    build_was = on
    kit.debug("info", "build mode: %s", on and "on" or "off")
  end
  return on
end

local function hud_tick(world)
  write_messages()
  write_notices()
  local label = ""
  if kit.setting("show_label", true) then
    label = string.format("%s v%s", kit.name, kit.version)
    if kit.author ~= "" then label = label .. " by " .. kit.author end
  end
  local lines = { "label " .. label }
  if not kit.connected(world) then
    lines[#lines + 1] = "notice This server does not run FlameKit: some features are off"
  elseif kit.server_note then  -- the server runs an older FlameKit (features/server_version.lua)
    local note = kit.server_note(world)
    if note then lines[#lines + 1] = "notice " .. note end
  end
  if kit.setting("ui_hide_build", true) and in_build_mode(world) then lines[#lines + 1] = "build 1" end
  lines[#lines + 1] = "end"
  local text = table.concat(lines, "\n") .. "\n"
  if text == hud_written then return end
  local f = io.open(emf.dir .. "\\ui_hud.dat", "w")
  if not f then
    kit.debug("warn", "hud: ui_hud.dat could not be written")
    return
  end
  f:write(text)
  f:close()
  hud_written = text
  kit.debug("debug", "hud: ui_hud.dat written: label '%s'", label)
end

-- The version and author come from mod.json, so the label never disagrees with the file.
local function read_manifest()
  local f = io.open(emf.dir .. "\\mod.json", "r")
  if not f then return end
  local text = f:read("a") or ""
  f:close()
  local data = emf.json.decode((text:gsub("^\239\187\191", "")))
  if type(data) ~= "table" then return end
  if type(data.version) == "string" then kit.version = data.version end
  if type(data.authors) == "table" and type(data.authors[1]) == "string" then kit.author = data.authors[1] end
end

function kit.enabled(f)
  if f.broken then return false end
  if f.enabled_setting and emf.setting(f.enabled_setting) == false then return false end
  return true
end

local function fail(f, where, err)
  f.broken = tostring(err)
  kit.debug("error", "feature %s stopped in %s: %s", f.id, where, f.broken)
  kit.note(kit.name .. ": " .. f.title .. " stopped after an error (see FlameKit's log). Save a file to reload.", "#ff5a50")
end

-- Wraps a callback of feature `f` (an event, a key, a command): skipped while the feature is off, and an error stops
-- only this feature.
function kit.guard(f, fn, where)
  return function(...)
    if not kit.enabled(f) then return end
    local ok, err = pcall(fn, ...)
    if not ok then fail(f, where or "a callback", err) end
  end
end

-- Calls `method` of feature `f` when it is on; returns what it returned, or nil.
function kit.call(f, method, ...)
  local fn = f[method]
  if not fn or not kit.enabled(f) then return nil end
  local ok, a, b = pcall(fn, ...)
  if not ok then
    fail(f, method, a)
    return nil
  end
  return a, b
end

local function each(method, ...)
  for _, f in ipairs(kit.features) do kit.call(f, method, ...) end
end

-- Loads the features (module names as require takes them) and wires up the game's callbacks.
function kit.start(modules)
  read_manifest()
  for _, name in ipairs(modules) do
    local ok, f = pcall(require, name)
    if ok and type(f) == "table" and f.id and f.title then
      kit.features[#kit.features + 1] = f
    else
      emf.log("feature " .. name .. " was not loaded: " .. tostring(ok and "it must return a table with id and title" or f))
    end
  end

  -- setup runs now, in the mod's first run: events have to be asked for before the game starts its world
  for _, f in ipairs(kit.features) do
    if f.setup then
      local ok, err = pcall(f.setup, kit)
      if not ok then fail(f, "setup", err) end
    end
  end

  emf.on_tick(function(world)
    if world:is_server() then
      server_seen = os.time()
      each("tick", world)
    else
      each("client_tick", world)
      hud_tick(world)
    end
  end)

  emf.on_setting_changed(function(key)
    each("setting_changed", key)
  end)

  emf.log(string.format("%d feature(s) loaded", #kit.features))
end

return kit
