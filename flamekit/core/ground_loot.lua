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
  local made = 0
  while count > 0 do
    local n = math.min(count, ground.MAX_AMOUNT)
    local ang = math.random() * 2 * math.pi
    local d = spread * (0.6 + 0.4 * math.random())
    local px, py, pz = x + math.cos(ang) * d, y + ground.LIFT, z + math.sin(ang) * d
    local parts = { PickupItem = { itemId = item, level = math.floor(tonumber(level) or 0), rarity = rarity, pickupAmount = n } }
    local ok, id = false, nil
    if template and template ~= ground.PICKUP then ok, id = pcall(emf.spawn, world, template, px, py, pz, parts) end
    if not ok or not id or id == 0 then ok, id = pcall(emf.spawn, world, ground.PICKUP, px, py, pz, parts) end
    if ok and id and id ~= 0 then made = made + 1 else break end
    count = count - n
  end
  return made
end

return ground
