-- core/loot_spots.lua (0.15.170, owner: "I see its corpse on the ground not the loot"): finds the loot spot a creature
-- leaves where it died. Many creatures (EMF re_content.md 4.1: the 76 LootContainer_Enemy_* templates, for example
-- Scavengers) do not hold their loot in their own body: the game spawns a separate loot container at the death
-- (Inventory, InventorySetup, DefaultInventory, DestroyOnLoot, an interaction offer, DoNotSave, SpawnTime; no Health)
-- and the body fades. Told apart from what must never be taken the way EMF's Loot Magnet does (mods/loot_magnet,
-- magnet_glue.h is_loot_container): not a player's grave (CreateItemLoot, ForceSave), not a loose pickup (PickupItem),
-- not a player or creature (Health, PlayerState). Its loot = a container within RADIUS m of the death that appeared at
-- or after it, by the game's clock (the container's SpawnTime against the death event's timeStamp).
-- (0.15.171: the death event's timeStamp is 0 on this build) without a time, every monster loot spot within RADIUS m
-- counts: those spots only ever hold monster loot (DoNotSave, DestroyOnLoot, a loot table; never a chest or a grave),
-- so taking a neighbour's puts monster loot on the ground too, which is what Loot Drop is for. (Noting the spots there
-- at the death, as Loot Magnet does without a clock, takes a Lua walk of several steps: the new spot would already be
-- there and be taken for an old one.)
-- (0.15.399, owner 15:05 "replace all that scanning with the DLL") no walk of the world any more: the candidates are
-- the containers FlameKit's DLL reported new (core/loot_news.lua) within RADIUS m of the death in the last SINCE_TICKS.
-- Shared core code (HANDOFF rule 0b): any feature may use it; it uses no feature.

local M = {}
local ground = require("core.ground_loot")  -- (0.15.172) its loot marks look like loot spots: never taken
local news = require("core.loot_news")     -- (0.15.399) the new containers, from the DLL

M.RADIUS = 4
local SINCE_TICKS = 60 * 20  -- (0.15.399) a container reported new up to 20 s before the question counts
local SLACK_NS = 5e8  -- half a second: a container spawned in the death's own step counts

local wanted = {}  -- death id -> { x, z, t (death time, ns), fn(container ids) }

local function get(world, c, id)
  local ok, v = pcall(world.get, world, c, id)
  if ok then return v end
  return nil
end

-- (0.15.393, owner 13:45 "dropped a ton of Critter Carapace and nothing picked it up") some monsters' loot piles are
-- saved (no DoNotSave) but carry the monster's Faction (flamekit.lootnear, 13:46: Inventory InventorySetup DefaultInventory
-- DestroyOnLoot Faction SpawnTime StaticCollider, empty until opened); a world chest or urn has no Faction
local function is_loot_container(world, id)
  return get(world, "DestroyOnLoot", id) and get(world, "DefaultInventory", id)
    and (get(world, "DoNotSave", id) or get(world, "Faction", id))
    and not get(world, "CreateItemLoot", id) and not get(world, "ForceSave", id) and not get(world, "Health", id)
    and not get(world, "PlayerState", id) and not get(world, "PickupItem", id)
    and (get(world, "Inventory", id) or get(world, "InventorySetup", id))
end

local function spawn_time(world, id)
  local st = get(world, "SpawnTime", id)
  local v = st and st.spawnTime
  if type(v) == "table" then v = v.value end
  return tonumber(v)
end

-- The death's time from an EntityDiedEvent (nil when the event has none).
function M.death_time(e)
  local t = e and e.timeStamp
  if type(t) == "table" then t = t.value end
  return tonumber(t)
end

-- Asks for the loot spots of death `id` at x, z (died at time `t`, ns); `fn(world, ids)` runs at the next step
-- (ids may be empty). Without a time (0 or nil) every loot spot within RADIUS m counts.
function M.find(id, x, z, t, fn)
  if not (x and z) then return false end
  wanted[id] = { x = x, z = z, t = (t and t > 0) and t or nil, fn = fn }
  return true
end

-- (0.15.399) each step: every question waiting is answered from the DLL's new containers (no walk)
function M.tick(world)
  if not next(wanted) then return end
  news.tick(world, true, true)  -- the newest news first
  local asked = wanted
  wanted = {}
  local okt, now = pcall(world.tick, world)
  now = okt and tonumber(now) or 0
  for did, w in pairs(asked) do
    local found = {}
    for _, id in ipairs(news.containers(w.x, w.z, M.RADIUS, now - SINCE_TICKS)) do
      if not ground.is_mark(id) and is_loot_container(world, id) then
        local st = w.t and spawn_time(world, id)
        if (not w.t) or (st and st >= w.t - SLACK_NS) then found[#found + 1] = id end
      end
    end
    pcall(w.fn, world, found)
  end
end

return M
