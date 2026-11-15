-- core/loot_chest.lua (0.15.154, owner: "all other loot that drops needs to go into a large chest that you spawn and
-- store there"; "if a chest becomes full, you spawn another chest"): loot stored in storage chests FlameKit spawns.
-- (0.15.155, owner: players run around the area, "put it into the next nearest chest. even chests spawned from other
-- player kills could be used") loot goes into the nearest of FlameKit's chests that is not full, anyone's, within
-- NEAR_M of where the loot comes from; none there: a new chest at that spot. A chest a put did not fit into counts as
-- full from then on, and the rest goes into the next one. A chest that was filled and is empty again is removed. Spawned entities are not saved
-- by the game (EMF re_villages.md: "the spawned chest ... gone" after a reload): a server restart loses the chests.
-- Shared core code (HANDOFF rule 0b): any feature may use it; it uses no feature.

local M = {}
local test_tag = require("core.test_tag")

-- (0.15.159) 0.15.154's Prop_Decoration_T4_Storage_56 looked like "a magical chest designed to be used inside a base";
-- 0.15.157's treasure chest (Base_LootChest_Animgraph2_Random) refused every put ("put_items: the game refused a
-- request (error 0x15)"). A storage chest that looks like a chest:
M.CHEST = "0c667e7e-0fbd-4cb9-b58d-c3a20df7eaec"  -- Prop_Decoration_T5_Storage_40_Chest (40 slots)
M.NEAR_M = 50
M.MAX_CHESTS = 100  -- all owners together

local chests = {}   -- chest id -> { x, y, z, filled = true once something went in }
local count = 0
local steps = 0

local function item_id(item)
  if type(item) == "string" then
    local ok, id = pcall(emf.item, item)
    return ok and id or nil
  end
  return item
end

local function spawn_chest(world, x, y, z)
  if count >= M.MAX_CHESTS then return nil end
  -- (0.15.157) with the invisible tag (core/test_tag.lua), so a FlameKit reload can find its chests again
  local ok, id = pcall(emf.spawn, world, M.CHEST, x, y, z, { ScaleComponent = { uniformScale = test_tag.SCALE } })
  if not ok or not id or id == 0 then ok, id = pcall(emf.spawn, world, M.CHEST, x, y, z) end
  if not ok or not id or id == 0 then
    emf.log("loot chest: the game refused a chest (" .. tostring(id) .. ")")
    return nil
  end
  chests[id], count = { x = x, y = y, z = z, born = os.time() }, count + 1
  return id
end

local function chest_for(world, x, y, z)
  local best, bd = nil, M.NEAR_M * M.NEAR_M
  for id, c in pairs(chests) do
    local d = (c.x - x) ^ 2 + (c.z - z) ^ 2
    if not c.full and d <= bd then best, bd = id, d end
  end
  return best or spawn_chest(world, x + 1.5, y, z)
end

-- Puts `n` of `item` (id or name) into the nearest chest near x, y, z (`key` is no longer used), with `level` and `rarity` for gear. A part that does
-- not fit goes into a new chest beside it (once per call: a second full chest means something is wrong). `done(added)`
-- (optional) after the game answered.
function M.put(world, key, x, y, z, item, n, level, rarity, done)
  item = item_id(item)
  if not item or not x or (n or 0) <= 0 then if done then done(0) end return end
  local opts = { level = level, rarity = rarity }
  local function into(chest, left, again)
    if not chest then
      emf.log("loot chest: no chest for the loot (" .. tostring(left) .. " of item " .. tostring(item) .. " lost)")
      if done then done(n - left) end
      return
    end
    local ok = pcall(emf.put, world, chest, item, left, function(w, added)
      added = tonumber(added) or 0
      if added > 0 and chests[chest] then chests[chest].filled = true end
      if added < left and again then
        if chests[chest] then chests[chest].full = true end
        into(chest_for(w, x, y, z), left - added, false)  -- full: the next nearest one, or a new one
      elseif done then
        done(n - (left - added))
      end
    end, opts)
    if not ok then emf.log("loot chest: emf.put refused") if done then done(0) end end
  end
  into(chest_for(world, x, y, z), n, true)
end

-- Removes chests that were filled and are empty again (looked at every 2 s). (0.15.159: a chest counted as filled only
-- from the game's answer to the put; the owner emptied chests that never went) Filled now also means: seen with items
-- at a look. A chest never seen with items 30 s after it was put there (the game refused the items) goes too. Whether
-- a removed chest is really gone is checked 2 s later and logged. Call from a feature's server tick.
local removed = {}  -- chest id -> os.time() it was destroyed (checked once, then forgotten)
function M.tick(world, bag)
  steps = steps + 1
  if not scanned then pcall(rescan, world) end
  if steps % 120 ~= 0 then return end
  local now = os.time()
  for id, at in pairs(removed) do
    if now - at >= 2 then
      removed[id] = nil
      local okp, x = pcall(world.position, world, id)
      emf.log(string.format("loot chest: chest %s %s", tostring(id), (okp and x) and "is STILL THERE after emf.destroy" or "is gone"))
    end
  end
  if count == 0 then return end
  for id, c in pairs(chests) do
    local gone = not pcall(world.position, world, id) or world:position(id) == nil
    local n = gone and 0 or #bag.entity_stacks(world, id)
    if n > 0 then c.filled = true end
    local refused = not c.filled and now - (c.born or now) >= 30
    if gone or (c.filled and n == 0) or refused then
      chests[id], count = nil, count - 1
      if not gone then
        local okd, r = pcall(emf.destroy, world, id)
        removed[id] = now
        emf.log(string.format("loot chest: chest %s %s: destroy %s", tostring(id), refused and "never got items" or "empty",
          okd and tostring(r) or ("error " .. tostring(r))))
      else
        emf.log(string.format("loot chest: chest %s gone (removed by the game)", tostring(id)))
      end
    end
  end
end

return M
