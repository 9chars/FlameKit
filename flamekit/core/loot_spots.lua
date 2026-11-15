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
-- done (ids may be empty). Without a time (0 or nil) every loot spot within RADIUS m counts.
function M.find(id, x, z, t, fn)
  if not (x and z) then return false end
  wanted[id] = { x = x, z = z, t = (t and t > 0) and t or nil, fn = fn }
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
            local st = w.t and spawn_time(world, id)
            if (not w.t) or (st and st >= w.t - SLACK_NS) then
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
