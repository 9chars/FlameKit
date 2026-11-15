-- core/loot_spots.lua (0.15.170, owner: "I see its corpse on the ground not the loot"): finds the loot spot a creature
-- leaves where it died. Many creatures (EMF re_content.md 4.1: the 76 LootContainer_Enemy_* templates, for example
-- Scavengers) do not hold their loot in their own body: the game spawns a separate loot container at the death
-- (Inventory, InventorySetup, DefaultInventory, DestroyOnLoot, an interaction offer, DoNotSave, SpawnTime; no Health)
-- and the body fades. Told apart from what must never be taken the way EMF's Loot Magnet does (mods/loot_magnet,
-- magnet_glue.h is_loot_container): not a player's grave (CreateItemLoot, ForceSave), not a loose pickup (PickupItem),
-- not a player or creature (Health, PlayerState). Its loot = a container within RADIUS m of the death that appeared at
-- or after it, by the game's clock (the container's SpawnTime against the death event's timeStamp).
-- The world is walked in parts of PER_STEP entities a step (EMF's 250 ms rule), one walk for all deaths waiting.
-- Shared core code (HANDOFF rule 0b): any feature may use it; it uses no feature.

local M = {}

M.RADIUS = 4
local PER_STEP = 3000
local SLACK_NS = 5e8  -- half a second: a container spawned in the death's own step counts

local wanted = {}  -- death id -> { x, z, t (death time, ns), fn(container ids) }
local walk = nil   -- { list, i, found = { death id -> { container ids } } }

local function get(world, c, id)
  local ok, v = pcall(world.get, world, c, id)
  if ok then return v end
  return nil
end

local function is_loot_container(world, id)
  return get(world, "DestroyOnLoot", id) and get(world, "DefaultInventory", id) and get(world, "DoNotSave", id)
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

-- Asks for the loot spots of death `id` at x, z (died at time `t`, ns); `fn(world, ids)` runs once the next walk is
-- done (ids may be empty). Without a time nothing is found (a loot spot already there must not be taken).
function M.find(id, x, z, t, fn)
  if not (x and z and t) then return false end
  wanted[id] = { x = x, z = z, t = t, fn = fn }
  return true
end

function M.tick(world)
  if not walk then
    if not next(wanted) then return end
    local ok, list = pcall(world.entities, world)
    if not ok or type(list) ~= "table" then return end
    walk = { list = list, i = 1, found = {}, asked = wanted }
    wanted = {}
  end
  local stop = math.min(#walk.list, walk.i + PER_STEP - 1)
  for k = walk.i, stop do
    local id = walk.list[k]
    if get(world, "InteractionOfferRuntime", id) then  -- most entities: one look
      local okp, x, _, z = pcall(world.position, world, id)
      if okp and x then
        for did, w in pairs(walk.asked) do
          if (x - w.x) ^ 2 + (z - w.z) ^ 2 <= M.RADIUS * M.RADIUS and is_loot_container(world, id) then
            local s = spawn_time(world, id)
            if s and s >= w.t - SLACK_NS then
              walk.found[did] = walk.found[did] or {}
              table.insert(walk.found[did], id)
            end
          end
        end
      end
    end
  end
  walk.i = stop + 1
  if walk.i > #walk.list then
    local done = walk
    walk = nil
    for did, w in pairs(done.asked) do pcall(w.fn, world, done.found[did] or {}) end
  end
end

return M
