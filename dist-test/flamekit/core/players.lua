-- core/players.lua: who is in the server world (a game you host, or a dedicated server), for party.lua and minimap.lua.
--
-- EMF reports every player that joins and leaves (emf.on_player_joined / emf.on_player_left, Lua 1.20), the host's own
-- player too, and after a reload of FlameKit it reports again every player already there (measured on the owner's
-- server, 0.15.48: "joined: entity id 1" in the same moment as the reload). The list is kept from those events, so no
-- entity ids need to be guessed. A player's entity id is given to the next player who joins after they leave.
-- Only on an EMF without these events: the old way, entity ids 1-64 (players had the lowest ids) and the host's own.

local M = {}

local online = {}       -- entity id -> true, from EMF's events
local events = nil      -- true: EMF's events are there; false: the old way
local kit

function M.setup(k)
  if events ~= nil then return end  -- party.lua and minimap.lua both ask; once is enough
  kit = k
  events = emf.on_player_joined(function(world, p)
    if type(p) == "table" and p.player and p.player ~= 0 then
      online[p.player] = true
      kit.debug("info", "players: entity id %s joined%s", tostring(p.player), p.host and " (the host)" or "")
    end
  end) and true or false
  if events then
    emf.on_player_left(function(world, p)
      if type(p) == "table" and p.player then
        online[p.player] = nil
        kit.debug("info", "players: entity id %s left", tostring(p.player))
      end
    end)
  else
    kit.debug("warn", "players: EMF has no player events: entity ids 1-64 are checked instead")
  end
end

-- The entity ids of the players in this world, lowest first. Each one must still be checked (world:account).
function M.ids(world)
  local ids = {}
  if events then
    for id in pairs(online) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
  end
  for id = 1, 64 do ids[#ids + 1] = id end
  local me = emf.local_player()
  if me and me > 64 then ids[#ids + 1] = me end
  return ids
end

return M
