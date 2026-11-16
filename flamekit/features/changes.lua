-- features/changes.lua: after an update a message that says so, and open_on_start. (0.15.193, owner) the What's New tab
-- is gone: changes.txt is shown by FlameKit's DLL in its Change Log window (the About tab's Change Log button).
--
-- changes.txt lists the versions, newest first: a line with the version and its date ("0.15.0 Nov 12, 2026"), then
-- its lines, then an empty line. The
-- last version this player has seen is kept in seen_version.json; when the mod's version is another one, a message
-- (kit.note: FlameKit's Messages window) says once, the first time the game is in a world, that the tab has what is new.
-- The tab: this version's lines, and under them the versions before it. At every world when the setting open_on_start
-- is on (since 0.15.188 no longer after an update by itself) FlameKit's window is opened on this tab: emf\mods\flamekit\ui_open.dat gets the tab's id;
-- FlameKit's DLL opens the window once and deletes the file.

local F = { id = "changes", title = "Change Log" }  -- no panel: not a tab

local kit
local pending = false  -- a new version: the message is still to be shown
local opened_this_game = false
local steps = 0

-- Asks FlameKit's DLL to open its window on this tab.
local function open_window()
  local f = io.open(emf.dir .. "\\ui_open.dat", "w")
  if not f then return end
  f:write(F.id)
  f:close()
  kit.debug("info", "changes: FlameKit's window asked to open (open_on_start)")
end

function F.client_tick(world)
  if opened_this_game then return end
  steps = steps + 1
  if steps < 180 or steps % 60 ~= 0 then return end  -- a moment after the world is there
  local player = emf.local_player()
  if not player or player == 0 then return end
  opened_this_game = true
  if pending then
    pending = false
    kit.store.save("seen_version", { version = kit.version })
    kit.note(string.format("%s was updated to v%s.", kit.name, kit.version), "#9fd2ff")
    -- (0.15.188, owner: "so many frequent updates, that its just becoming annoying for users") no longer opens the
    -- window on What's New after an update: the Messages line is enough; open_on_start still opens it at every world
    if kit.setting("open_on_start", false) == true then open_window() end
  elseif kit.setting("open_on_start", false) == true then
    open_window()
  end
end

function F.setup(k)
  kit = k
  local seen = kit.store.load("seen_version", {}).version
  if type(seen) ~= "string" then seen = nil end
  pending = seen ~= kit.version
end

return F
