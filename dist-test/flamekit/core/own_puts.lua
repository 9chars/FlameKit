-- core/own_puts.lua (0.15.388, owner 2026-11-21 12:53 "items you pick axe go straight to the bag ... I'd still like those
-- logged in the loot messages also"): the items FlameKit itself puts into a player's bag. The game reports those with
-- a PickupEvent from entity 0, the same as what a pickaxe mines straight into the bag; the Loot tab already has its own
-- line for them (Auto Loot), so it claims them here and leaves out only those.
--   puts.note(player, item, count)    before emf.put into a player (kept 10 s)
--   puts.claim(player, item, count)   true when that put is FlameKit's (and forgets that much of it)
-- Shared core code (HANDOFF rule 0b): any feature may use it; it uses no feature.

local puts = {}
local KEEP_S = 10
local list = {}  -- { player, item, left, at }

-- The clock in seconds.
local function now() return os.time() end

-- Notes that FlameKit is about to put `count` of `item` into `player`'s bag (kept KEEP_S).
function puts.note(player, item, count)
  player, item, count = tonumber(player), tonumber(item), math.floor(tonumber(count) or 0)
  if not (player and item) or count <= 0 then return end
  list[#list + 1] = { player = player, item = item, left = count, at = now() }
end

-- True when a pickup of `item` by `player` is one of FlameKit's own puts (and forgets that much of it).
function puts.claim(player, item, count)
  player, item, count = tonumber(player), tonumber(item), math.floor(tonumber(count) or 0)
  local t, keep, hit = now(), {}, false
  for _, p in ipairs(list) do
    if t - p.at <= KEEP_S then
      if not hit and p.player == player and p.item == item then
        hit = true
        p.left = p.left - count
      end
      if p.left > 0 then keep[#keep + 1] = p end
    end
  end
  list = keep
  return hit
end

return puts
