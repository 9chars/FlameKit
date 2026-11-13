-- core/kit.lua: what every feature shares.
--
-- A feature is a Lua file that returns a table:
--   id               "loot_filter"  (letters, digits, _)
--   title            "Auto Junk List"  (its tab in the panel)
--   enabled_setting  the bool setting in mod.json that switches it on and off (optional)
--   setup(kit)       once, while the mod loads: register events, keys and commands here (wrap them in kit.guard)
--   tick(world)      every step of a world you host (the server world): gameplay changes go here
--   client_tick(world)  every step of your own screen's world (HUD lines)
--   panel(world)     the rows of its tab in the panel (see emf.window in EMF's lua.md); keys are the feature's own
--   click(world, key, right_click)  a click on one of its rows
--   setting_changed(key)
--   connected(world) false while this feature cannot reach its server half on a joined server (the label says so)
-- Every call is protected: a feature that raises an error is switched off until the next reload, the others go on.

local kit = { features = {}, name = "FlameKit", version = "?", author = "" }

kit.store = require("core.store")
kit.items = require("core.items")
kit.bag = require("core.bag")
local hub = require("core.hub")
kit.hub = hub

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

local STATUS_STEPS = 480  -- how long a status line stays: about 8 seconds
local status_left = 0     -- client steps until the status line goes
local status_text, status_colour = "", "ffb060"
local hud_written = nil   -- ui_hud.dat as last written

-- A status line in the lower left corner for a few seconds, above the FlameKit label: what a feature just did
-- ("Junk discarded: Twigs x3"), in `colour` ("#rrggbb"; orange without). The player can switch these off. Also
-- written to emf_core.log.
function kit.note(text, colour)
  emf.log(text)
  if not kit.setting("notify", true) then return end
  status_text = tostring(text):gsub("[%c]", " ")
  status_colour = (type(colour) == "string" and colour:match("^#?(%x%x%x%x%x%x)$")) or "ffb060"
  status_left = STATUS_STEPS
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
-- "FlameKit v1.2.3 by Name" label and the status line, written into emf\mods\flamekit\ui_hud.dat when they change:
--   label <text>              ("" when the player switched the label off)
--   status <rrggbb> <text>    (only while a status line is shown)
--   end                       (a file without it is half written: the DLL reads it again later)
-- The updater's line under the label comes from the DLL itself. ui_hud.dat is a runtime file: never deployed.
local function hud_tick(world)
  if status_left > 0 then status_left = status_left - 1 end
  local label = ""
  if kit.setting("show_label", true) then
    label = string.format("%s v%s", kit.name, kit.version)
    if kit.author ~= "" then label = label .. " by " .. kit.author end
    if not kit.connected(world) then label = label .. " (not connected to this server)" end
  end
  local lines = { "label " .. label }
  if status_left > 0 then lines[#lines + 1] = "status " .. status_colour .. " " .. status_text end
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
  kit.debug("debug", "hud: ui_hud.dat written: label '%s'%s", label, status_left > 0 and (", status '" .. status_text .. "'") or "")
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
  emf.notify(kit.name .. ": " .. f.title .. " stopped after an error (see emf_core.log). Save a file to reload.")
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
  hub.setup(kit)

  emf.on_tick(function(world)
    if world:is_server() then
      server_seen = os.time()
      each("tick", world)
    else
      each("client_tick", world)
      hud_tick(world)
    end
    hub.tick(world)
  end)

  emf.on_setting_changed(function(key)
    each("setting_changed", key)
  end)

  emf.log(string.format("%d feature(s) loaded", #kit.features))
end

return kit
