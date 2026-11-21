-- core/companions.lua (0.15.278): where the companions are, for the minimap (owner, 2026-11-18: "I just can't find
-- where he is" / a small dot "in the player's colour"). Shared module (HANDOFF rule 0b): the companion code (the local
-- test server's features/npc_probe.lua) puts the list here, features/minimap.lua reads it; neither knows the other.
-- Server world only. Without the companion code the list stays empty.

local M = {}

local list = {}  -- { x = , z = , owner = "<the owner's character name>", name = "<the companion's name>" }

-- The companion code: the whole list, as it is now (replaces the last one).
function M.set_places(places)
  list = type(places) == "table" and places or {}
end

-- The minimap: the list as last set.
function M.places()
  return list
end

return M
