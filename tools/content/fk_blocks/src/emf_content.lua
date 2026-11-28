-- emf_content.lua: helpers for EML content mods built by EMF (docs/modding/content.md, "The helper").
-- Copy this file into your mod's src folder and load it with:   local content = require("emf_content")
-- Everything here edits the game's data while EMF builds content at start; nothing is changed on disk.
--
-- The rules that keep players' saves safe:
-- * GUIDs are FIXED FOREVER: a save stores items, recipes and placed objects by id (FNV-1a of the GUID). Pick new GUIDs
--   once (any GUID generator) and never change them; never delete something a released version added.
-- * Every player in a world, and the dedicated server, needs the mod. A world loaded without it drops what the mod
--   added (placed objects vanish on the next save, items from inventories).
-- * The game's UI data (the crafting menu, icons, text) only exists in the game, not on the dedicated server: these
--   helpers skip it there (loader.is_server).
local M = {}

M.version = 1

local function fail(fmt, ...) error("emf_content: " .. string.format(fmt, ...), 3) end

-- FNV-1a-32 of a text, as the game hashes its own ids and EMF its custom E prompt words.
function M.fnv1a(text)
	local h = 2166136261
	for i = 1, #text do
		h = h ~ text:byte(i)
		h = (h * 16777619) & 0xFFFFFFFF
	end
	return h
end

-- The loca id EMF gives an E prompt's own words (EMF API v25 EmfOffer.text, Lua emf.offer{text = ...}).
function M.verb_id(words) return M.fnv1a("emf.verb:" .. words) end

-- The id of a GUID (ItemId, RecipeId, ...).
function M.id(guid) return game.guid.hash(guid) end

-- ---- text ----

local keenglish = nil  -- the English loca table, read once and written back by M.finish()

local function loca()
	if keenglish then return keenglish end
	local collection = game.assets.get_resources_by_type("keen::LocaTagCollectionResource")[1].data
	local content = game.assets.get_content(game.guid.from_content_hash(collection.keenglishData.hash))
	keenglish = {collection = collection, data = content:read_data():read_resource("keen::LocaTagCollectionResourceData")}
	return keenglish
end

-- Adds text under a loca id (the game falls back to English for every language). Game only: does nothing on the
-- dedicated server. Call M.finish() once at the end of your mod.lua.
function M.add_text(id, text)
	if loader.is_server then return end
	local tags = loca().data.tags
	local at = #tags + 1
	for i, tag in ipairs(tags) do
		if tag.id.value == id then
			if tag.text == text then return end
			fail("the loca id 0x%08x is taken by %q", id, tag.text)
		end
		if tag.id.value > id then at = i break end
	end
	table.insert(tags, at, {id = {value = id}, text = text, arguments = {}, genericArguments = 0})
end

-- Words for an E prompt of your own (emf.offer{text = words}): the game then shows them for everyone with the mod.
function M.add_prompt_words(words) M.add_text(M.verb_id(words), words) end

-- Writes the text back. Call it once, after your last M.add_* call.
function M.finish()
	if loader.is_server or not keenglish then return end
	local buf = buffer.create()
	buf:write_resource("keen::LocaTagCollectionResourceData", keenglish.data)
	keenglish.collection.keenglishData.hash = game.assets.create_content(buf)
	keenglish = nil
end

-- ---- knowledge ----
-- The game keeps what a player knows ("has had this item", "has crafted this recipe") and what a world knows in two
-- static hash maps of keen::GameKnowledgeResource: playerKnowledge (16384 buckets) and worldKnowledge (8192). Each
-- bucket i is {start, count} into keys and values, which are stored bucket after bucket; a key's bucket is
-- key & (buckets - 1). Every vanilla ItemId and RecipeId has a player entry. A new item or recipe gets a copy of its
-- source's entry, both sides (the server keeps the flags).


-- true, or false and why, when the map is not laid out as above (the game changed: nothing is inserted then).
function M._knowledge_check(map)
	local n = #map.entries
	if n == 0 or n & (n - 1) ~= 0 then return false, "the bucket count is not a power of two" end
	if #map.keys ~= #map.values then return false, "keys and values differ in number" end
	local at = 0
	for b = 1, n do
		local e = map.entries[b]
		if e.start ~= at then return false, string.format("bucket %d's start is %d, expected %d", b - 1, e.start, at) end
		for i = at + 1, at + e.count do
			if map.keys[i].id.value & (n - 1) ~= b - 1 then
				return false, string.format("key 0x%08x is in bucket %d", map.keys[i].id.value, b - 1)
			end
		end
		at = at + e.count
	end
	if at ~= #map.keys then return false, "the buckets do not hold every key" end
	return true
end

local function knowledge_find(map, key)
	local e = map.entries[(key & (#map.entries - 1)) + 1]
	for i = e.start + 1, e.start + e.count do
		if map.keys[i].id.value == key then return i end
	end
	return nil
end

-- Copies the entry of from_key under new_key. false when from_key has no entry (nothing changed).
function M._knowledge_copy(map, from_key, new_key)
	local src = knowledge_find(map, from_key)
	if not src then return false end
	if knowledge_find(map, new_key) then fail("the knowledge id 0x%08x is taken (a GUID used twice?)", new_key) end
	local n = #map.entries
	local b = (new_key & (n - 1)) + 1
	local e = map.entries[b]
	local at = e.start + e.count + 1
	table.insert(map.keys, at, {id = {value = new_key}})
	table.insert(map.values, at, map.values[src])  -- EML inserts a copy
	map.values[at].id = {id = {value = new_key}}
	e.count = e.count + 1
	for i = b + 1, n do
		local x = map.entries[i]
		x.start = x.start + 1
	end
	return true
end

M._checked = {}  -- per table: true (checked, fine) or false (laid out otherwise: no entries are added)

-- Copies from_key's entry under new_key in table `which`: true when copied; false and "missing" when from_key has
-- none, false and "layout" when the table is not laid out as expected (a game update: only the entries are skipped,
-- with one warning; the "new" mark and item unlocks are what they cost).
local function copy_knowledge(which, from_key, new_key)
	local res = game.assets.get_resources_by_type("keen::GameKnowledgeResource")[1]
	local map = res and res.data and res.data[which]
	if M._checked[which] == nil then
		local ok, why = false, "the game has no such table"
		if map then ok, why = M._knowledge_check(map) end
		M._checked[which] = ok
		if not ok then
			print(string.format("emf_content: the game's %s table is not laid out as this helper expects (%s): new items "
				.. "and recipes get no entries in it (update emf_content.lua)", which, why))
		end
	end
	if not M._checked[which] then return false, "layout" end
	if not M._knowledge_copy(map, from_key, new_key) then return false, "missing" end
	return true
end

-- An item's entries: the player's "has had it" flag and, when the source item has one, the world's.
function M._item_knowledge(from_id, new_id)
	local ok, why = copy_knowledge("playerKnowledge", from_id, new_id)
	if not ok and why == "missing" then
		print(string.format("emf_content: item 0x%08x has no knowledge entry to copy: 0x%08x gets none", from_id, new_id))
	end
	copy_knowledge("worldKnowledge", from_id, new_id)
end

-- ---- items ----

local function item_registry() return game.assets.get_resources_by_type("keen::ItemRegistryResource")[1].data end

-- Adds an item copied from another (its model, icon, animations and perks), then your changes.
--   guid, name_guid: fixed GUIDs of your own; debug_name: what EMF's "items" and "give" use; name: what players see;
--   clone_of: the source item's GUID; edit(item): optional changes to the copy (fields of keen::ItemInfo);
--   level: the item's level (a number, or {min, max}). Set it for gear you craft: a loot item's range is wide (the
--   Bronze Sword: 1 to 55) and a craft picks a level inside it; the game's crafted items have one level (its own
--   crafting weapons: 3). nil keeps the copied item's range;
--   description_guid, description: optional, a text of your own instead of the copied item's.
-- Returns the item's id.
function M.add_item(def)
	for _, k in ipairs({"guid", "name_guid", "debug_name", "name", "clone_of"}) do
		if not def[k] then fail("add_item: %s is missing", k) end
	end
	if (def.description == nil) ~= (def.description_guid == nil) then
		fail("add_item: description and description_guid go together")
	end
	local src = game.assets.get_resource(def.clone_of, "keen::ItemInfo")
	if not src then fail("add_item: no item %s to copy (the game changed?)", def.clone_of) end
	local item = game.assets.create_resource(src.data, "keen::ItemInfo", def.guid, 0).data
	local id = M.id(def.guid)
	item.itemId = {value = id}
	item.objectId = def.guid
	item.name = def.name_guid
	if def.description_guid then item.description = def.description_guid end
	item.debugName = def.debug_name
	if def.level then
		local lo, hi = def.level, def.level
		if type(def.level) == "table" then lo, hi = def.level[1], def.level[2] or def.level[1] end
		if type(lo) ~= "number" or type(hi) ~= "number" or lo < 1 or hi < lo then
			fail("add_item: level is a number of at least 1, or {min, max} with min <= max")
		end
		item.itemLevelRange.minLevel = math.floor(lo)
		item.itemLevelRange.maxLevel = math.floor(hi)
	end
	if def.edit then def.edit(item) end
	if not loader.is_server then  -- the icon (a UiTextureResource under the item's own GUID) and the name
		local icon = game.assets.get_resource(def.icon_of or def.clone_of, "keen::UiTextureResource")
		if not icon then fail("add_item: no icon on %s", def.icon_of or def.clone_of) end
		game.assets.create_resource(icon.data, "keen::UiTextureResource", def.guid, 0)
		M.add_text(M.id(def.name_guid), def.name)
		if def.description then M.add_text(M.id(def.description_guid), def.description) end
	end
	local reg = item_registry()
	table.insert(reg.itemRefs, def.guid)
	table.insert(reg.dbgNames, def.debug_name)
	M._item_knowledge(src.data.itemId.value, id)  -- "has had it" (a recipe's unlock = {item = ...} reads it)
	return id
end

-- ---- placeable objects ----

local ZERO_GUID = "00000000-0000-0000-0000-000000000000"

-- The parts that make a vanilla object a crafting station that villagers use (strip them from a Workbench copy).
M.STATION_PARTS = {"keen::ecs::Crafting", "keen::ecs::CraftingInteraction", "keen::ecs::ClientCraftingInteraction",
	"keen::ecs::RequiredCraftingProp", "keen::ecs::ActiveNpcTarget"}
-- The parts of the game's E prompt on an object. Without them the object is a plain decoration, and a Lua mod can put
-- its own prompt on a placed one (emf.offer refuses an entity that has the game's).
M.PROMPT_PARTS = {"keen::ecs::InteractionOfferRuntime", "keen::ecs::ClientInteractionOffer",
	"keen::ecs::CheckPlayerInRange"}

-- Adds an object players place in their base: a copy of a vanilla object's template (its model, collider and
-- behaviour) without the parts you strip, and a copy of the item that places it.
--   guid, name_guid, debug_name, name, level, description_guid, description, edit: as add_item (the item);
--   template_guid: the object's fixed GUID (saves store placed objects by it);
--   clone_of: the vanilla placing item's GUID (the Workbench: 2f04a05f-697d-489b-a32f-76bb3439f5bc);
--   strip = {component type names, or lists of them}: removed from the copy, e.g. {M.STATION_PARTS, M.PROMPT_PARTS};
--   a name the template does not have is an error; edit_template(template): optional changes to the copy
--   (keen::ecs::TemplateResource).
-- Saved when placed inside a base; picking it up gives the item back. Returns the item's id.
function M.add_placeable(def)
	for _, k in ipairs({"guid", "template_guid", "name_guid", "debug_name", "name", "clone_of"}) do
		if not def[k] then fail("add_placeable: %s is missing", k) end
	end
	local isrc = game.assets.get_resource(def.clone_of, "keen::ItemInfo")
	if not isrc then fail("add_placeable: no item %s to copy (the game changed?)", def.clone_of) end
	local from_tpl = isrc.data.equipment.placedEntity
	if not from_tpl or from_tpl == ZERO_GUID then
		fail("add_placeable: the item %s places nothing (pick an item that places an object)", def.clone_of)
	end
	local tsrc = game.assets.get_resource(from_tpl, "keen::ecs::TemplateResource")
	if not tsrc then fail("add_placeable: no template %s to copy (the game changed?)", from_tpl) end
	local strip, found = {}, {}
	for _, name in ipairs(def.strip or {}) do
		if type(name) == "table" then  -- a list of names (M.STATION_PARTS)
			for _, n in ipairs(name) do strip[n] = true end
		else
			strip[name] = true
		end
	end
	for _, c in ipairs(tsrc.data.components) do
		if strip[c.type] then found[c.type] = true end
	end
	for name in pairs(strip) do  -- a name that is no component type is a typo; a real one the copy lacks is only noted
		if not found[name] then  -- (the dedicated server's data may not carry the game-only parts)
			if not game.types.get_by_qualified_name(name) then
				fail("add_placeable: %s is not a component type (a typo?)", name)
			end
			print(string.format("emf_content: add_placeable: the template %s has no part %s: nothing to remove",
				tostring(tsrc.data.name), name))
		end
	end
	local tpl = game.assets.create_resource(tsrc.data, "keen::ecs::TemplateResource", def.template_guid, 0).data
	tpl.name = def.debug_name
	for i = #tpl.components, 1, -1 do
		if strip[tpl.components[i].type] then table.remove(tpl.components, i) end
	end
	if def.edit_template then def.edit_template(tpl) end
	local item_def = {}
	for k, v in pairs(def) do item_def[k] = v end
	item_def.edit = function(item)
		item.equipment.placedEntity = def.template_guid
		if def.edit then def.edit(item) end
	end
	return M.add_item(item_def)
end

-- ---- recipes ----

-- keen::KnowledgeQueryData enums, as numbers (EML takes either): compareOperator 2 = Equals, type 3 = SimpleFlag
local EQUALS, SIMPLE_FLAG = 2, 3

local function recipe_registry() return game.assets.get_resources_by_type("keen::RecipeRegistryResource")[1].data end

local function find_recipe(debug_name)
	for _, r in ipairs(recipe_registry().recipes) do
		if r.debugName == debug_name then return r end
	end
	return nil
end

-- The crafting menu's tree of a workshop (0: the player's own crafting). Game only.
local function menu_tree(workshop)
	local col = game.assets.get_resources_by_type("keen::FbUiBundle")[1].data.menu.crafting.recipes
	for i, w in ipairs(col.workshops) do
		if w.value == workshop then return col.trees[i] end
	end
	return nil
end

-- The menu's groups of a workshop with their sets and recipes (to pick a place for yours). Game only.
function M.menu_groups(workshop)
	local out = {}
	if loader.is_server then return out end
	local tree = menu_tree(workshop or 0)
	if not tree then return out end
	for _, g in ipairs(tree.groups) do
		local sets = {}
		for _, s in ipairs(g.sets) do sets[#sets + 1] = #s.entries end
		out[#out + 1] = {group = g.groupId, sets = sets}
	end
	return out
end

-- Adds a recipe, listed in the crafting menu.
--   guid: fixed; debug_name; output = {guid, count}; inputs = {{guid, count}, ...} (1 to 4);
--   like: a vanilla recipe's debugName whose settings (station, unlock, duration) are copied (default: the campfire,
--   own crafting, known once you have had wood logs);
--   unlock: "always", {item = guid} (once the player has had that item) or nil (the copied recipe's);
--   menu = {group = "<groupId GUID>", set = 1}: where it is listed, at the end of that set (see M.menu_groups); nil:
--   right after the copied recipe.
-- Returns the recipe's id.
function M.add_recipe(def)
	for _, k in ipairs({"guid", "debug_name", "output", "inputs"}) do
		if not def[k] then fail("add_recipe: %s is missing", k) end
	end
	if #def.inputs < 1 or #def.inputs > 4 then fail("add_recipe: 1 to 4 inputs") end
	local unlock = def.unlock
	if unlock ~= nil and unlock ~= "always" and not (type(unlock) == "table" and type(unlock.item) == "string") then
		fail('add_recipe: unlock is "always", {item = "<item GUID>"} or nil (the copied recipe\'s), not %s',
			tostring(unlock))
	end
	local like = def.like or "Consumable_Tool_Campfire_PK"
	local source = find_recipe(like)
	if not source then fail("add_recipe: no recipe %s to copy (the game changed?)", like) end
	local recipes = recipe_registry().recipes
	table.insert(recipes, source)
	local r = recipes[#recipes]
	local id = M.id(def.guid)
	r.recipeGuid = def.guid
	r.recipeId = {value = id}
	r.debugName = def.debug_name
	while #r.output > 1 do table.remove(r.output) end
	r.output[1].itemRef = def.output[1]
	r.output[1].item = {value = M.id(def.output[1])}
	r.output[1].count = def.output[2] or 1
	while #r.input > 1 do table.remove(r.input) end
	local template = r.input[1]
	for i, inp in ipairs(def.inputs) do
		if i > 1 then table.insert(r.input, template) end
		local slot = r.input[i]
		slot.itemStack.itemRef = inp[1]
		slot.itemStack.item = {value = M.id(inp[1])}
		slot.itemStack.count = inp[2] or 1
		slot.inputItemCategory.categoryRef = "00000000-0000-0000-0000-000000000000"
		slot.inputItemCategory.category = {value = 0}
		slot.inputItemCategory.count = 0
	end
	r.requiresSheltered = def.sheltered or false
	local done = r.completionRequirementQuery  -- "crafted once", per recipe: the game's own pattern on the new id
	done.knowledgeOrQueryId = {value = id}
	done.compareValue = 2
	done.compareOperator = EQUALS
	done.type = SIMPLE_FLAG
	done.isExplicitPlayerKnowledgeQuery = true
	local ok, why = copy_knowledge("playerKnowledge", source.recipeId.value, id)  -- that flag's entry
	if not ok and why == "missing" then
		print(string.format("emf_content: recipe %s has no knowledge entry to copy: %s is not marked crafted", like,
			def.debug_name))
	end
	local req = r.knowledgeRequirement
	if unlock == "always" then  -- all zero, as the club's and the bow's
		req.knowledgeOrQueryId = {value = 0}
		req.compareValue = 0
		req.compareOperator = 0
		req.type = 0
		req.isExplicitPlayerKnowledgeQuery = false
	elseif unlock then  -- once this player has had the item (the wood axe's pattern on stone)
		req.knowledgeOrQueryId = {value = M.id(unlock.item)}
		req.compareValue = 1
		req.compareOperator = EQUALS
		req.type = SIMPLE_FLAG
		req.isExplicitPlayerKnowledgeQuery = true
	end
	if not loader.is_server then
		local workshop = r.workshopId and r.workshopId.value or 0
		local tree = menu_tree(workshop)
		if not tree then fail("add_recipe: the crafting menu has no tree for workshop %d", workshop) end
		local placed = false
		if def.menu then  -- the group named, its set 1 or the set named, at the end
			for _, g in ipairs(tree.groups) do
				if g.groupId == def.menu.group then
					local set = g.sets[def.menu.set or 1]
					if not set then fail("add_recipe: the group %s has no set %d", def.menu.group, def.menu.set or 1) end
					table.insert(set.entries, {value = id})
					placed = true
					break
				end
			end
		else  -- right after the copied recipe, in its set
			for _, g in ipairs(tree.groups) do
				for _, s in ipairs(g.sets) do
					for i, e in ipairs(s.entries) do
						if not placed and e.value == source.recipeId.value then
							table.insert(s.entries, i + 1, {value = id})
							placed = true
						end
					end
				end
			end
		end
		if not placed then
			fail("add_recipe: %s in workshop %d", def.menu and ("no menu group " .. tostring(def.menu.group))
				or ("the menu does not list " .. like), workshop)
		end
	end
	return id
end

return M
