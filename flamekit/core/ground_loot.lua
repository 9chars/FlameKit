-- core/ground_loot.lua: puts items on the ground as loose loot, with the quality and level they should have.
--
-- How (tested on the local server, 2026-11-15): the game's generic pickup template spawned with a PickupItem
-- {itemId, level, rarity, pickupAmount}. A player who picks it up gets exactly that item: a sword given rarity 4 and
-- level 10 came out legendary, level 10 (the same sword given rarity 0: common). EMF's emf.give cannot do this (it
-- only knows the item type: the game's defaults). What a loose item cannot carry: a gem socketed into a weapon, and
-- anything else beyond type, level, quality and amount. The game still caps a gear piece's level by its tier.
-- Shared core code (HANDOFF rule 0b): any feature may use it; it uses no feature.

local ground = {}

-- the generic pickup template (EMF docs, re_inventory_api.md; this text form is the one emf.spawn takes)
ground.PICKUP = "a56d2777-daf1-4164-90d4-b7b12749c723"
ground.MAX_AMOUNT = 65535  -- PickupItem.pickupAmount is a u16
-- (0.15.149, owner: a legendary helmet floated in the air) a pickup does not fall: it stays where it is spawned, so it is
-- made just above the given height (a body's position is at its feet), not 1 m above it as before
ground.LIFT = 0.25
-- (0.15.150, owner: "put a sparkle particle effect on them") the game's pickup with an effect of its own (template
-- list from the game's files); untested which effect it shows. A caller picks it with `template`; the default stays plain.
-- 0.15.150 Base_LootPickup_VFX (1b22afc5-...) showed only "a very bright orb" (owner); 0.15.151 tries the one with a model
ground.PICKUP_VFX = "c799a6d4-88ef-4bdf-ba38-9faf23592b6e"  -- Base_LootPickup_Model_VFX

local RARITY = { common = 0, uncommon = 1, rare = 2, epic = 3, legendary = 4 }

-- Drops `count` of `item` (an id or a debug name) at x, y, z, `spread` m to a random side (default 2), with
-- `level` (0: the game's default) and `rarity` (0-4 or a name; default 0). Returns the number of pickups made.
-- `template` (optional): another pickup template (ground.PICKUP_VFX); if the game refuses it, the plain one is used.
function ground.drop(world, item, count, x, y, z, level, rarity, spread, template)
  if type(item) == "string" then
    local ok, id = pcall(emf.item, item)
    item = ok and id or nil
  end
  if not item or not x then return 0 end
  count = math.floor(tonumber(count) or 1)
  rarity = RARITY[rarity] or tonumber(rarity) or 0
  spread = spread or 2
  local made, last = 0, nil
  while count > 0 do
    local n = math.min(count, ground.MAX_AMOUNT)
    local ang = math.random() * 2 * math.pi
    local d = spread * (0.6 + 0.4 * math.random())
    local px, py, pz = x + math.cos(ang) * d, y + ground.LIFT, z + math.sin(ang) * d
    local parts = { PickupItem = { itemId = item, level = math.floor(tonumber(level) or 0), rarity = rarity, pickupAmount = n } }
    local ok, id = false, nil
    if template and template ~= ground.PICKUP then ok, id = pcall(emf.spawn, world, template, px, py, pz, parts) end
    if not ok or not id or id == 0 then ok, id = pcall(emf.spawn, world, ground.PICKUP, px, py, pz, parts) end
    if ok and id and id ~= 0 then made, last = made + 1, id else break end
    count = count - n
  end
  return made, last  -- (0.15.152) also the last pickup's entity id, for a caller that marks it
end

-- (0.15.152-0.15.157) the game's grave flame (VFX_SubEntity_Player_LootCorpse_Tombstone_Flame) was put on dropped
-- items: removed in 0.15.158 (owner: too strong). (0.15.171, owner: "I wish we could find the right sparkle ... that would
-- really help find the item on the ground") the game's fireflies made for loot pickups, on a dropped item's spot until
-- it is picked up (or MARK_S), at most MARK_MAX at once. Not saved: after a FlameKit reload a mark is not tracked.
-- (0.15.172, owner: "the same sparkle effect that appears on a body when it dies") the game's glowing loot spot's base
-- template (a loot container with no model: EMF re_content.md 4.1), as a mark only; untested. core/loot_spots.lua never
-- takes these marks for a monster's loot (ground.is_mark). 0.15.171 had the fireflies (Lootpickup_Scatter_VFX_Bait_T1_
-- Fire_Fly_Above, c2091afd-...).
-- (0.15.173, owner: that is "the loot pile one", not the sparkle) no mark for now: the sparkle on a dead body is an
-- effect component the game adds to the body (transform_to_loot), being read first (features/loot_drop.lua)
-- (0.15.175, owner picked it) glowing specks, a separate effect on the item's spot as the flame was
-- (0.15.177, owner) the fireflies the game puts over loot pickups (0.15.175: VFX_SubEntity_Wildlife_SpiderAnt_Babies_Glowy)
ground.MARK_FX = "c2091afd-f631-4160-ac79-574b951f5a4a"  -- Lootpickup_Scatter_VFX_Bait_T1_Fire_Fly_Above
ground.MARK_S = 600
ground.MARK_MAX = 300
local marks, marks_n = {}, 0  -- effect id -> { item = pickup id, at = os.time() }

-- (0.15.174, owner: the sparkle on a dead body; experiment) that sparkle is put on by the player's game itself
-- (client_transformed_to_loot) when the server sends TransformedToLootEvent {entityId, useVfxDefaultParameters} for the
-- body. The same event for a dropped item, in case the game sparkles it too. Untested; EMF lets a script send it only
-- when it named it at the server start (ground.emits in a feature's setup), so it needs one server restart.
ground.SPARKLE = false  -- (0.15.175) off: no sparkle seen on a dropped item (owner, 0.15.174)
local sparkle_ok = nil  -- nil: not asked yet; false: the event cannot be sent
function ground.emits()
  local ok, said = pcall(emf.emits, { "TransformedToLootEvent" }, "server")
  sparkle_ok = ok and said ~= false
  if not sparkle_ok then emf.log("ground loot: TransformedToLootEvent cannot be sent (" .. tostring(said) .. "): no sparkle on dropped items") end
end
function ground.sparkle(world, pickup)
  if not ground.SPARKLE or not sparkle_ok or not pickup then return false end
  local ok, done = pcall(emf.emit, "server", "TransformedToLootEvent", { entityId = pickup, useVfxDefaultParameters = true })
  return ok and done ~= false
end

function ground.mark(world, pickup)
  if not ground.MARK_FX then return "off" end
  if marks_n >= ground.MARK_MAX then return "too many" end
  local ok, x, y, z = pcall(world.position, world, pickup)
  if not ok or not x then return "item not found" end
  local oks, id = pcall(emf.spawn, world, ground.MARK_FX, x, y, z)
  if not oks or not id or id == 0 then return "refused (" .. tostring(id) .. ")" end
  marks[id], marks_n = { item = pickup, at = os.time() }, marks_n + 1
  return "placed"
end

-- True for one of these marks (so nothing takes a mark for a monster's loot spot).
function ground.is_mark(id) return marks[id] ~= nil end

-- Removes the marks of items that were picked up. Call now and then from a feature's server tick.
function ground.fx_tick(world)
  if marks_n == 0 then return end
  local now = os.time()
  for id, m in pairs(marks) do
    local ok, x = pcall(world.position, world, m.item)
    if not ok or not x or now - m.at >= ground.MARK_S then
      marks[id], marks_n = nil, marks_n - 1
      pcall(emf.destroy, world, id)
    end
  end
end

return ground
