-- features/changes.lua: after an update a message that says so; the first time, the window on the About tab; at every
-- world a Messages line with the window's key (0.15.196; open_on_start is gone). (0.15.193, owner) the What's New tab
-- is gone: changes.txt is shown by FlameKit's DLL in its Change Log window (the About tab's Change Log button).
--
-- changes.txt lists the versions, newest first: a line with the version and its date ("0.15.0 Nov 12, 2026"), then
-- its lines, then an empty line. The
-- last version this player has seen is kept in seen_version.json; when the mod's version is another one, a message
-- (kit.note: FlameKit's Messages window) says once, the first time the game is in a world, that the tab has what is new.
-- (The What's New tab and open_on_start are gone; FlameKit's DLL opens the window once from ui_open.dat and deletes it.)

local F = { id = "changes", title = "Change Log" }  -- no panel: not a tab

local kit
local pending = false  -- a new version: the message is still to be shown
local first_time = false  -- (0.15.196) nothing seen before: the first time FlameKit is used
local opened_this_game = false
local steps = 0

-- Asks FlameKit's DLL to open its window on a tab.
local function open_window(tab)
  local f = io.open(emf.dir .. "\\ui_open.dat", "w")
  if not f then return end
  f:write(tab)
  f:close()
  kit.debug("info", "changes: FlameKit's window asked to open on " .. tab)
end

-- Once a game, a moment after the world is there: the Messages line with the window's key, and the update message or (the first time) the window on the About tab.
function F.client_tick(world)
  if opened_this_game then return end
  steps = steps + 1
  if steps < 180 or steps % 60 ~= 0 then return end  -- a moment after the world is there
  local player = emf.local_player()
  if not player or player == 0 then return end
  opened_this_game = true
  -- (0.15.196, owner) every world: how to open FlameKit's window, in the Messages window
  local key = tostring(kit.setting("window_key", "F4") or "")
  kit.note(string.format("Press %s for FlameKit Main Menu", key ~= "" and key or "F4"), "#9fd2ff")  -- (0.15.199) no ESC: it does not open it
  if pending then
    pending = false
    kit.store.save("seen_version", { version = kit.version })
    if first_time then
      -- (0.15.196, owner) the first time FlameKit is used: its window opens on the About tab
      open_window("about")
    else
      kit.note(string.format("%s was updated to v%s.", kit.name, kit.version), "#9fd2ff")
    end
  end
end

-- Reads the last version this player has seen (seen_version.json): a new version or a first install is told once.
function F.setup(k)
  kit = k
  local seen = kit.store.load("seen_version", {}).version
  if type(seen) ~= "string" then seen = nil end
  pending = seen ~= kit.version
  first_time = seen == nil  -- no version seen yet: FlameKit was just installed
end

return F
