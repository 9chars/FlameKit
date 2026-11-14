-- core/items.lua: item ids and names. Call these inside callbacks only (EMF needs a world to look items up).
--
-- An item has an id (a number, the same in every world), a debug name ("Material_T1_Wood_Logs": what lists are
-- saved by, so a file stays readable) and the name the game shows ("Wood Logs", in the player's language).

local items = {}

local debug_names = {}  -- id -> debug name
local shown = {}        -- id or debug name -> the game's name (kept only once the game knows it)

-- "Material_T1_Wood_Logs" -> "Wood Logs": a readable name where the game has none.
function items.pretty(debug_name)
  local s = debug_name:gsub("^%a+_T%d+_", ""):gsub("_", " "):gsub("(%l)(%u)", "%1 %2")
  return s
end

-- An item's debug name by its id, or nil for an unknown id.
function items.debug_name(id)
  local name = debug_names[id]
  if name then return name end
  local ok, info = pcall(emf.item_info, id)
  if ok and info and info.name and info.name ~= "" then
    debug_names[id] = info.name
    return info.name
  end
  return nil
end

-- An item's id by its debug name, or nil.
function items.id(debug_name)
  local ok, id = pcall(emf.item, debug_name)
  if ok and id and id ~= 0 then return id end
  return nil
end

-- What a player typed ("wood logs", "Material_T1_Wood_Logs"): the id and the debug name, or nil.
function items.find(text)
  if not text or text == "" then return nil end
  local tries = { text, (text:gsub("%s+", "_")) }
  for _, t in ipairs(tries) do
    local id = items.id(t)
    if id then return id, items.debug_name(id) or t end
  end
  return nil
end

-- The game's names for an item's quality (0 Common .. 4 Legendary).
items.RARITY_NAME = { [0] = "Common", [1] = "Uncommon", [2] = "Rare", [3] = "Epic", [4] = "Legendary" }

-- An item's kind, read from its debug name ("Material_T1_Twigs" -> material): the word to show and its colour.
-- The first match wins; an item no word fits is "Item" in the usual text colour.
local KINDS = {
  { "weapon", "Weapon", "#d9d4c7" }, { "armor", "Armour", "#d9d4c7" }, { "armour", "Armour", "#d9d4c7" },
  { "shield", "Shield", "#d9d4c7" }, { "ring", "Ring", "#d9d4c7" }, { "amulet", "Amulet", "#d9d4c7" },
  { "food", "Food", "#9ad0c2" }, { "consumable", "Consumable", "#9ad0c2" }, { "potion", "Potion", "#9ad0c2" },
  { "bandage", "Consumable", "#9ad0c2" }, { "drink", "Drink", "#9ad0c2" },
  { "ammo", "Ammunition", "#d8cf8a" }, { "ammunition", "Ammunition", "#d8cf8a" }, { "arrow", "Ammunition", "#d8cf8a" },
  { "spell", "Spell", "#d8cf8a" }, { "staffcharge", "Spell", "#d8cf8a" },
  { "tool", "Tool", "#b0b8c4" }, { "key", "Key", "#b0b8c4" }, { "lockpick", "Lockpick", "#b0b8c4" },
  { "craftingstation", "Crafting station", "#b9a58c" }, { "blueprint", "Blueprint", "#b9a58c" },
  { "npc", "Summoning item", "#e39ad6" }, { "gem", "Gem", "#e39ad6" }, { "rune", "Rune", "#e39ad6" },
  { "seed", "Seed", "#a8c686" }, { "plant", "Plant", "#a8c686" }, { "seedling", "Seedling", "#a8c686" },
  { "building", "Building", "#b9a58c" }, { "prop", "Furniture", "#b9a58c" }, { "furniture", "Furniture", "#b9a58c" },
  { "block", "Building block", "#b9a58c" }, { "material", "Material", "#cdbf9f" }, { "resource", "Material", "#cdbf9f" },
}

function items.kind(debug_name)
  if not debug_name then return "Item", nil end
  local first = (debug_name:match("^(%a+)") or ""):lower()
  if first == "ammo" and debug_name:lower():find("_spell_", 1, true) then return "Spell", "#d8cf8a" end
  for _, k in ipairs(KINDS) do
    if first == k[1] then return k[2], k[3] end
  end
  -- then any whole word of the name ("Unique_Ring_Fire" is a ring; "Material_String" is not)
  local words = {}
  for word in debug_name:lower():gmatch("[^_]+") do words[word] = true end
  for _, k in ipairs(KINDS) do
    if words[k[1]] then return k[2], k[3] end
  end
  return "Item", nil
end

-- Kinds a player keeps: gear can be salvaged into runes, tools and summoning items are never loot to throw away.
-- Features that remove items leave these alone and do not offer them.
-- Blueprints are the building pieces of the construction hammer's bar: they sit in an inventory but are not loot.
local KEEPERS = { Weapon = true, Armour = true, Shield = true, Ring = true, Amulet = true, Tool = true,
                  ["Summoning item"] = true, Blueprint = true }

-- Single items that are never junk either, by their debug name: Runes and Legendary Runes (a currency).
local KEPT_ITEMS = { Material_T1_Token_WeaponUpgrade_Rune01 = true, Material_T2_Token_WeaponUpgrade_Rune02 = true }

-- Trophies (the heads a boss leaves: "_Material_TX_Trophy_Wolf_Heavy_head") are kept too.
function items.is_keeper(debug_name)
  if not debug_name then return false end
  if KEPT_ITEMS[debug_name] then return true end
  if debug_name:lower():find("trophy", 1, true) then return true end
  return KEEPERS[(items.kind(debug_name))] == true
end

-- An item's tier from its debug name ("Weapon_T6_2H_Bow" -> 6), or nil.
function items.tier(debug_name)
  local t = debug_name and debug_name:match("_T(%d+)")
  return t and tonumber(t) or nil
end

-- An item's largest stack, or nil.
function items.max_stack(id)
  local ok, info = pcall(emf.item_info, id)
  if ok and info and info.max_stack and info.max_stack > 0 then return info.max_stack end
  return nil
end

-- What the game itself knows about every item: its rarity, level and type. The minimap's DLL writes them to
-- item_details.dat in this folder at game start (a Lua mod cannot read the game's item definitions); without the
-- file (no DLL, or a game version it does not know) the tooltips show what the debug name tells.
local details = nil       -- item id -> {rarity, level_min, level_max, category, sub}
local details_tried = 0   -- os.time() of the last look for the file

local CATEGORY = { [1] = "Armor", [2] = "Weapon", [3] = "Tool", [4] = "Instrument", [5] = "Fishing rod",
                   [6] = "Furniture and building", [7] = "Food and consumables", [8] = "Ammunition", [9] = "Material",
                   [10] = "Blueprint", [11] = "Token", [12] = "Collectible", [13] = "Animal feed", [15] = "Gem",
                   [16] = "Color palette" }
local AMMUNITION = { [1] = "arrow", [2] = "spell", [3] = "bait" }

function items.data(id)
  if not details and os.time() - details_tried >= 5 then
    details_tried = os.time()
    local f = io.open(emf.dir .. "\\item_details.dat", "r")
    if f then
      local t = {}
      for line in f:lines() do
        local item, rarity, lo, hi, category, sub = line:match("^(%x+) (%d+) (%d+) (%d+) (%d+) (%d+)")
        if item then
          t[tonumber(item, 16)] = { rarity = tonumber(rarity), level_min = tonumber(lo), level_max = tonumber(hi),
                                    category = tonumber(category), sub = tonumber(sub) }
        end
      end
      f:close()
      if next(t) then details = t end
    end
  end
  return details and id and details[id] or nil
end

-- An item's details for FlameKit's item tiles (the DLL draws the tile and its tooltip the same way everywhere):
--   { rarity = 0..4 (Common .. Legendary) or -1, level = "12" / "12-14" / "", type = "Material" / "", command = debug name }
-- Where the game's item details are not there (item_details.dat), the kind and tier from the debug name.
function items.tip(id, debug_name)
  local t = { rarity = -1, level = "", type = "", command = debug_name or "" }
  local d = items.data(id)
  if d then
    if d.level_max > 0 then t.level = d.level_min == d.level_max and tostring(d.level_max) or (d.level_min .. "-" .. d.level_max) end
    if items.RARITY_NAME[d.rarity] then t.rarity = d.rarity end
    local kind = CATEGORY[d.category]
    if kind and d.category == 8 and AMMUNITION[d.sub] then kind = kind .. ", " .. AMMUNITION[d.sub] end
    t.type = kind or ""
  elseif debug_name then
    local tier = items.tier(debug_name)
    t.type = tostring(items.kind(debug_name)) .. (tier and (", tier " .. tier) or "")
  end
  return t
end

-- The name to show for an item (an id or a debug name).
function items.name(item)
  local cached = shown[item]
  if cached then return cached end
  local ok, name, real = pcall(emf.item_name, item)
  if ok and name then
    if real then
      shown[item] = name
      return name
    end
    return items.pretty(name)
  end
  if type(item) == "string" then return items.pretty(item) end
  local debug_name = items.debug_name(item)
  if debug_name then return items.pretty(debug_name) end
  return string.format("item 0x%08x", item)
end

return items
