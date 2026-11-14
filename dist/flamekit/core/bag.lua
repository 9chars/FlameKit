-- core/bag.lua: what a player carries.
--
-- A player owns several 8-slot Inventory entities, linked from their InventorySetup. The ones of category Generic
-- are the backpack and the action bar; the one of category Virtual is the worn backpack item, which is a container
-- of its own: it has an InventorySetup with all of its rows (a Large Backpack: four), and the player's link names
-- only the first. Equipment, customization and currency are other categories and are never listed here. The action bar's inventories are named by the player's SlotSelection.

local bag = {}

local GENERIC = 4  -- InventoryCategory::Generic
local VIRTUAL = 5  -- InventoryCategory::Virtual: the slots of the worn backpack

local function get(world, component, id)
  local ok, c = pcall(world.get, world, component, id)
  if ok then return c end
  return nil
end

-- Every non-empty stack in the player's backpack and action bar:
--   {item = id, count = n, gear = true for a weapon or armour piece (it has its own data: level, perks),
--    rarity = 0 Common .. 4 Legendary, level, damage (base damage), broken, gem (the socketed gem's item id): for
--    gear, where they can be read (nil otherwise),
--    hotbar = true on the action bar, slot = the InventorySlotId emf.take wants, owner = the entity to take it from}
-- The second result is false when the player's inventory could not be read at all.
function bag.stacks(world, player)
  local out = {}
  if not player or player == 0 then return out, false end
  local setup = get(world, "InventorySetup", player)
  if not setup then return out, false end

  local bar = {}
  local selection = get(world, "SlotSelection", player)
  if selection then
    for i = 1, #selection.actionbarEntityIds do
      local id = selection.actionbarEntityIds[i]
      if id ~= 0 then bar[id] = true end
    end
  end

  -- the inventories to read: the player's Generic ones, and every row of the worn backpack
  -- `owner`: the entity whose InventorySetup names the inventory (emf.take takes a slot only from its owner): the
  -- player, or for the backpack's further rows the backpack itself
  local ids, seen, owner = {}, {}, {}
  local function add(id, of)
    if id ~= 0 and not seen[id] then
      seen[id] = true
      owner[id] = of
      ids[#ids + 1] = id
    end
  end
  for i = 1, #setup.linksEntities do
    local id, category = setup.linksEntities[i], setup.linksCategories[i]
    if id ~= 0 and category == GENERIC then
      add(id, player)
    elseif id ~= 0 and category == VIRTUAL then
      add(id, player)
      local pack = get(world, "InventorySetup", id)
      if pack then
        for k = 1, #pack.linksEntities do
          if pack.linksCategories[k] == GENERIC then add(pack.linksEntities[k], id) end
        end
      end
    end
  end

  for _, inv_id in ipairs(ids) do
    do
      local inv = get(world, "Inventory", inv_id)
      if inv then
        for s = 1, #inv.slots do
          local stack = inv.slots[s]
          local item, count = stack.id, stack.data.count
          if item ~= 0 and count > 0 then
            local pide = stack.data.pide
            local rarity, level, damage, broken, gem = nil, nil, nil, nil, nil
            if pide ~= 0 then  -- a gear piece's own entity knows its quality, level and damage
              local state = get(world, "ItemState", pide)
              if state then
                rarity = state.itemRarityUi
                if state.itemLevelUi and state.itemLevelUi > 0 then level = state.itemLevelUi end
                if state.baseDamageUi and state.baseDamageUi > 0 then damage = state.baseDamageUi end
                broken = (state.itemState or 0) & 1 == 1
              end
              local slot = get(world, "WeaponGemSlot", pide)
              if slot and slot.weaponGem and slot.weaponGem.id ~= 0 then gem = slot.weaponGem.id end
            end
            out[#out + 1] = {
              item = item,
              count = count,
              gear = pide ~= 0,
              rarity = rarity,
              level = level,
              damage = damage,
              broken = broken,
              gem = gem,
              hotbar = bar[inv_id] == true,
              slot = inv_id | ((s - 1) << 32),
              owner = owner[inv_id],
            }
          end
        end
      end
    end
  end
  return out, true
end

return bag
