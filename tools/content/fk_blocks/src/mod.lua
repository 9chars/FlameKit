-- fk_blocks (FlameKit, owner 2026-11-28 09:41 "yes": the first test block). New block items for building materials the
-- game has but no item places (research: tools/content/fk_block_dump, HANDOFF #21). A block item is a copy of a game
-- block (its icon, its behaviour) whose equipment.voxelData.placeVoxelMaterialId is the hidden material's number.
-- Nothing of the game's own blocks or materials changes.
--
-- THE GUIDs BELOW ARE FIXED FOREVER: a save stores items by ItemId = FNV-1a(GUID); a new GUID would make every saved
-- block item vanish. Never change them; a new block gets new GUIDs of its own.
if not loader.features.patch then
	return
end

local content = require("emf_content")

local GRANITE_BLOCK = "896ab2d5-58f7-4711-a313-a0b975a9a5a2"  -- Block_T5_Stone_Granite (material 192)
local GRANITE_ROOF_1 = "77bfc638-dcc1-4d6f-bb6a-b893333b9c89"  -- Block_Roof_T5_Granite_Ornamented (194, roof)
local GRANITE_ROOF_2 = "c91f1559-916d-49c4-a319-4eb279ee1c43"  -- Block_Roof_T5_Granite_Shingles (195, roof)
local GLOWDIRT_BLUE = "40fcec7b-c55b-453d-b5b6-cefd042ddf77"   -- Block_T1_GlowDirt_Blue_CRAFTING (167)
local ROUGH_STONE = "bea90ffd-00fb-4737-9d57-f87d7da49ca8"     -- Block_T1_Stone_Rough_CRAFTING (155)

local BLOCKS = {
	{  -- material 187: Building_64_buildings_set_Coldheights_GraniteCityWall_01 (no item in the game)
		guid = "a15c1573-f6fe-480a-8bc8-36559e160767", name_guid = "9bc453d8-0c10-4f5a-998d-22af8dff63f7",
		debug_name = "Block_T5_Stone_Granite_CityWall_FK", name = "Granite City Wall",
		clone_of = GRANITE_BLOCK, material = 187,
		recipe_guid = "7de822f7-cb42-4f34-aab1-966fd06aaffb",  -- FIXED as well (a save marks crafted recipes by its id)
	},
	-- (11:05, owner "do it": the other five real hidden materials; each a copy of the closest game block, with its recipe)
	-- (11:15) off = true: the owner's game crashed again and again (6 starts 11:10-11:13) once these five were in; only
	-- the City Wall (fine 10:59-11:05) stays on until the crash is found.
	{  -- material 188: Building_65_buildings_set_Coldheights_GraniteHouseWall_01
		guid = "b7e9db6a-84d9-4a1c-8f1c-50ca5467f6d6", name_guid = "37928d8f-5cc1-447d-9215-7400ae6cf196",
		recipe_guid = "77e83ac2-808e-4cb7-81d2-7ba858bb41f2",
		debug_name = "Block_T5_Stone_Granite_HouseWall_FK", off = true, name = "Granite House Wall",
		clone_of = GRANITE_BLOCK, material = 188,
	},
	{  -- material 189: Building_67_buildings_set_ColdHeights_GraniteHouseRoof_01 (roof mapping)
		guid = "26bcadbc-0ba2-471e-964f-a61c11edc39d", name_guid = "dee8b40e-18a1-49c7-a6db-ae4086263ee7",
		recipe_guid = "62785035-7c19-46ef-80c5-5eae9f5d1489",
		debug_name = "Block_Roof_T5_Granite_HouseRoof1_FK", off = true, name = "Granite House Roof 1",
		clone_of = GRANITE_ROOF_1, material = 189,
	},
	{  -- material 190: Building_68_buildings_set_ColdHeights_GraniteHouseRoof_02 (roof mapping)
		guid = "a957e9dd-2408-4d9e-b18c-e32c0553a652", name_guid = "63da9546-d8a5-42df-9eba-60b07b75699f",
		recipe_guid = "40e04632-7c67-4052-bbb7-72b18cd146b9",
		debug_name = "Block_Roof_T5_Granite_HouseRoof2_FK", off = true, name = "Granite House Roof 2",
		clone_of = GRANITE_ROOF_2, material = 190,
	},
	{  -- material 175: red glow dirt (Glowdirt_02)
		guid = "429f63c5-2e8f-4ba0-becd-646edf4cf8aa", name_guid = "3cde4eb8-1274-4b5a-8ebe-5e1c8b62f306",
		recipe_guid = "660c49b9-cae4-4e06-abcb-726aef0ce322",
		debug_name = "Block_T1_GlowDirt_Red_FK", off = true, name = "Red Glow Dirt",
		clone_of = GLOWDIRT_BLUE, material = 175,
	},
	{  -- material 134: white (a DEPRECATED material with a real 1024 px texture)
		guid = "8f2e04ad-0337-49a8-82d8-617c970106f2", name_guid = "a969dc13-3f13-4619-ac55-989cb0f97ab7",
		recipe_guid = "4c7e8056-73c9-45ee-a869-38b5df25b252",
		debug_name = "Block_T1_Stone_White_FK", off = true, name = "White Block",
		clone_of = ROUGH_STONE, material = 134,
	},
}

-- (09:53) The block could not be placed or picked in build mode: the copy kept Granite's placeVoxelMaterial GUID
-- (each material id has its own SolidVoxelMaterial GUID, e.g. 143 = 03b9d9ad..., 192 = Granite's 6dbedd17...).
-- The GUID of every material id is looked up below and checked against the game's own block items first.
local KNOWN = {}  -- material id -> GUID, from the game's own block items
for _, r in ipairs(game.assets.get_resources_by_type("keen::ItemInfo") or {}) do
	local e = r.data and r.data.equipment
	local vd = e and e.voxelData
	local id = vd and tonumber(vd.placeVoxelMaterialId)
	if vd and vd.isBuildingVoxel and id and id >= 128 then KNOWN[id] = tostring(vd.placeVoxelMaterial) end
end

-- keen::VoxelWorldResource.materialGuids (256 GUIDs, by material id; the resolved list is no resource: 09:56 run).
-- Used only when every known pair matches.
local function material_guids()
	local worlds = game.assets.get_resources_by_type("keen::VoxelWorldResource") or {}
	print(string.format("[fk_blocks] VoxelWorldResource resources: %d", #worlds))
	for wi, r in ipairs(worlds) do
		local mg = r.data and r.data.materialGuids
		if mg then
			local good, bad = 0, 0
			for id, g in pairs(KNOWN) do
				if tostring(mg[id + 1]) == g then good = good + 1 else bad = bad + 1 end
			end
			if wi <= 3 or (good > 20 and bad == 0) then
				print(string.format("[fk_blocks] world %d (%s): %d known materials match, %d differ", wi, tostring(r.guid), good, bad))
			end
			if good > 20 and bad == 0 then
				for _, id in ipairs({134, 175, 187, 188, 189, 190}) do
					print(string.format("[fk_blocks]   material %d = %s", id, tostring(mg[id + 1])))
				end
				return function(id) return tostring(mg[id + 1]) end
			end
		end
	end
	return nil
end
local guid_of = material_guids()
-- (10:24-10:43) Setting the material's "known" check (TerraformingEfficiencyRegistryResource.buildingConfigs
-- knowledgeQuery) to its source's was tried and is not needed: the owner tested the block without it. Removed.

if not guid_of then print("[fk_blocks] no checked material list: placeVoxelMaterial left as copied") end

local function add_block(b)
	local new_id = content.add_item{
		guid = b.guid, name_guid = b.name_guid, debug_name = b.debug_name, name = b.name, clone_of = b.clone_of,
		edit = function(it)
			it.equipment.voxelData.placeVoxelMaterialId = b.material
			local g = b.material_guid or (guid_of and guid_of(b.material))
			if g then it.equipment.voxelData.placeVoxelMaterial = g end
			print(string.format("[fk_blocks] %s placeVoxelMaterial %s", b.debug_name, tostring(it.equipment.voxelData.placeVoxelMaterial)))
		end,
	}
	print(string.format("[fk_blocks] added %s (%s) placing material %d", b.debug_name, b.guid, b.material))
	-- (10:02) still not placeable or in build mode's block list: build mode offers only the items of a
	-- keen::VoxelBlueprintMaterialPool (by ItemId). The new block goes into every pool that has its source, after it.
	local src_id = tonumber(game.assets.get_resource(b.clone_of, "keen::ItemInfo").data.itemId.value)
	local pools = game.assets.get_resources_by_type("keen::VoxelBlueprintMaterialPoolRegistryResource") or {}
	local added = 0
	for _, r in ipairs(pools) do
		for _, pool in ipairs(r.data.materialPools or {}) do
			for i, m in ipairs(pool.materials) do
				if tonumber(m.value) == src_id then
					table.insert(pool.materials, i + 1, {value = new_id})
					added = added + 1
					print(string.format("[fk_blocks]   into pool %s (%d items now)", tostring(pool.debugName), #pool.materials))
					break
				end
			end
		end
	end
	print(string.format("[fk_blocks] %s: %d pool registries, put into %d pools", b.debug_name, #pools, added))
	-- (10:32) From the action bar the preview shows, the swing plays and nothing is placed (the "not allowed" sound).
	-- keen::VoxelBlueprintItemRegistryResource.blueprintItems holds the shape of every placeable item by ItemId (the
	-- build menu's shapes are registered items; a block placed from the action bar is its own shape). The new block
	-- gets a copy of its source's entry under its own ItemId, in id order when the list is sorted.
	for _, r in ipairs(game.assets.get_resources_by_type("keen::VoxelBlueprintItemRegistryResource") or {}) do
		local list = r.data.blueprintItems or {}
		local src_at, sorted = nil, true
		for i, e in ipairs(list) do
			local v = tonumber(e.itemId.value)
			if v == src_id then src_at = i end
			if i > 1 and v < tonumber(list[i - 1].itemId.value) then sorted = false end
		end
		if src_at then
			local at = #list + 1
			if sorted then
				at = 1
				while at <= #list and tonumber(list[at].itemId.value) < new_id do at = at + 1 end
			end
			table.insert(list, at, list[src_at])  -- EML inserts a copy
			list[at].itemId = {value = new_id}
			print(string.format("[fk_blocks] %s: shape copied from its source (%d shapes, sorted %s, at %d)", b.debug_name, #list,
				tostring(sorted), at))
		else
			print(string.format("[fk_blocks] %s: its source has no shape entry (%d shapes)", b.debug_name, #list))
		end
	end
	-- (10:56, owner: "add the custom recipes") the recipe: a copy of its source block's own recipe (the same station,
	-- ingredients, amount made, unlock and time), listed right after it, making the new block instead.
	if b.recipe_guid then
		local zero = "00000000-0000-0000-0000-000000000000"
		local src
		for _, r in ipairs(game.assets.get_resources_by_type("keen::RecipeRegistryResource")[1].data.recipes) do
			local out = r.output and r.output[1]
			if out and tonumber(out.item.value) == src_id then
				print(string.format("[fk_blocks] %s: source recipe %s (workshop %s, makes %d)", b.debug_name, tostring(r.debugName),
					tostring(r.workshopId and r.workshopId.value), tonumber(out.count) or -1))
				src = src or r
			end
		end
		local inputs, category = {}, false
		if src then
			for _, slot in ipairs(src.input) do
				if tostring(slot.inputItemCategory.categoryRef) ~= zero then category = true end
				if tostring(slot.itemStack.itemRef) ~= zero then
					inputs[#inputs + 1] = {tostring(slot.itemStack.itemRef), tonumber(slot.itemStack.count)}
					print(string.format("[fk_blocks]   input %s x%d", inputs[#inputs][1], inputs[#inputs][2]))
				end
			end
		end
		if not src then
			print(string.format("[fk_blocks] %s: its source has no recipe: none added", b.debug_name))
		elseif category or #inputs < 1 or #inputs > 4 then
			print(string.format("[fk_blocks] %s: the source recipe has %d item inputs%s: none added", b.debug_name, #inputs,
				category and " and a category input" or ""))
		else
			local ok, err = pcall(content.add_recipe, {
				guid = b.recipe_guid, debug_name = b.debug_name .. "_Recipe", like = src.debugName,
				output = {b.guid, tonumber(src.output[1].count) or 1}, inputs = inputs,
			})
			print(string.format("[fk_blocks] %s: recipe %s %s", b.debug_name, b.recipe_guid, ok and "added" or ("FAILED: " .. tostring(err))))
		end
	end
end

-- one block failing (a game update moved its source) leaves the others in place
for _, b in ipairs(BLOCKS) do
	local ok, err = true, nil
	if b.off then print(string.format("[fk_blocks] %s is off", b.debug_name)) else ok, err = pcall(add_block, b) end
	if not ok then print(string.format("[fk_blocks] %s FAILED: %s", b.debug_name, tostring(err))) end
end

content.finish()
