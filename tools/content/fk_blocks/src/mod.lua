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

-- a Buffer's bytes as a Lua string (EML's buffer API has changed between versions)
local function buf_string(buf)
	for _, f in ipairs({function() return buf:read_string(buf:tail() - buf:head()) end, function() return buf:read_string(#buf) end,
	                    function() return buf:read_string(buf:len()) end}) do
		local ok, r = pcall(f)
		if ok and type(r) == "string" and #r > 0 then return r end
	end
	return nil
end

local GRANITE_BLOCK = "896ab2d5-58f7-4711-a313-a0b975a9a5a2"  -- Block_T5_Stone_Granite (material 192)
local GLOWDIRT_BLUE = "40fcec7b-c55b-453d-b5b6-cefd042ddf77"   -- Block_T1_GlowDirt_Blue_CRAFTING (167)

local BLOCKS = {
	{  -- material 187: Building_64_buildings_set_Coldheights_GraniteCityWall_01 (no item in the game)
		guid = "a15c1573-f6fe-480a-8bc8-36559e160767", name_guid = "9bc453d8-0c10-4f5a-998d-22af8dff63f7",
		debug_name = "Block_T5_Stone_Granite_CityWall_FK", name = "Granite City Wall",
		clone_of = GRANITE_BLOCK, material = 187,
		recipe_guid = "7de822f7-cb42-4f34-aab1-966fd06aaffb",  -- FIXED as well (a save marks crafted recipes by its id)
	},
	-- (11:05, owner "do it": the other five real hidden materials; each a copy of the closest game block, with its recipe)
	-- (11:15) off = true: the owner's game crashed again and again (6 starts 11:10-11:13) once these five were in; only
	-- the City Wall (fine 10:59-11:05) stays on until the crash is found. (11:20, owner: test group 1 first: the
	-- House Wall and both House Roofs are on again; Red Glow Dirt and White Block stay off: no crash.) (11:29, owner:
	-- Red Glow Dirt next: on; White Block off.)
	-- (11:29, owner: "take them all out except for the Granite city wall block") 188 House Wall, 189 / 190 House Roof 1 / 2
	-- looked like the game's Granite and Granite roofs: removed. Their GUIDs are retired, never to be used again:
	-- b7e9db6a-84d9-4a1c-8f1c-50ca5467f6d6 37928d8f-5cc1-447d-9215-7400ae6cf196 77e83ac2-808e-4cb7-81d2-7ba858bb41f2
	-- 26bcadbc-0ba2-471e-964f-a61c11edc39d dee8b40e-18a1-49c7-a6db-ae4086263ee7 62785035-7c19-46ef-80c5-5eae9f5d1489
	-- a957e9dd-2408-4d9e-b18c-e32c0553a652 63da9546-d8a5-42df-9eba-60b07b75699f 40e04632-7c67-4052-bbb7-72b18cd146b9
	{  -- material 175: red glow dirt (Glowdirt_02)
		guid = "429f63c5-2e8f-4ba0-becd-646edf4cf8aa", name_guid = "3cde4eb8-1274-4b5a-8ebe-5e1c8b62f306",
		recipe_guid = "660c49b9-cae4-4e06-abcb-726aef0ce322",
		debug_name = "Block_T1_GlowDirt_Red_FK", name = "Red Luminescent Block",  -- (11:36, owner: the blue one's name)
		icon_png = "icons/red_luminescent.png",
		-- (12:34, owner: "Cinder's Cradle Sand" x5 and "Magma Gel" x1; it stays with the "Blocks - Luminescent")
		recipe_inputs = {{"Build_TerrainMaterial_T7_Dirt_AncientLand_Sand", 5}, {"Material_T7_LavaPlant_Magma_Gel", 1}},  -- (11:35/11:44, owner: the copied icon is blue; a picture of its own)
		clone_of = GLOWDIRT_BLUE, material = 175,
	},
	-- (11:35, owner: "forget about the white block I don't want it") 134 White Block removed (it was off: one of it or
	-- the red one crashed the game, and the red one runs fine). Retired GUIDs, never to be used again:
	-- 8f2e04ad-0337-49a8-82d8-617c970106f2 a969dc13-3f13-4619-ac55-989cb0f97ab7 4c7e8056-73c9-45ee-a869-38b5df25b252
}

-- (09:53) The block could not be placed or picked in build mode: the copy kept Granite's placeVoxelMaterial GUID
-- (each material id has its own SolidVoxelMaterial GUID, e.g. 143 = 03b9d9ad..., 192 = Granite's 6dbedd17...).
-- The GUID of every material id is looked up below and checked against the game's own block items first.
local KNOWN = {}  -- material id -> GUID, from the game's own block items
local ITEM_GUID = {}  -- debug name -> GUID (for recipe inputs named by debug name)
for _, r in ipairs(game.assets.get_resources_by_type("keen::ItemInfo") or {}) do
	if r.data and r.data.debugName then ITEM_GUID[tostring(r.data.debugName)] = tostring(r.guid) end
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
	if b.icon_png and not loader.is_server then
		-- (11:44, owner: "just provide a new graphic tile for that one") the icon is a picture shipped with the mod
		-- (icons/*.png, 512 x 512: the blue block's icon turned red). The copied keen::UiTextureResource keeps its layout
		-- (format BC7_unorm_block, size {x, y}, levelCount 10, the levels one after the other in one content); only its
		-- content is replaced by the PNG and its smaller levels. EML's BC7 encoder stops the game on a level under 4 x 4
		-- (11:43 crash: "block_compression encode.rs:91 left 2 right 0"): those are encoded as a 4 x 4 copy (one block,
		-- the same 16 bytes). Any surprise (a size that does not add up): nothing is changed, the copied icon stays.
		local ok, err = pcall(function()
			local icon = game.assets.get_resource(b.guid, "keen::UiTextureResource")
			if not icon then error("no icon under the item's GUID") end
			local d = icon.data
			local w, h, levels = tonumber(d.size.x), tonumber(d.size.y), tonumber(d.levelCount)
			local path
			for _, p in ipairs({b.icon_png, "../" .. b.icon_png, "mods/fk_blocks/" .. b.icon_png}) do
				local okx, there = pcall(io.exists, p)
				if okx and there then path = p break end
			end
			if not path then error("the picture " .. b.icon_png .. " is not found") end
			local level = image.decode(io.read(path), "png")
			if level.width ~= w or level.height ~= h then
				error(string.format("the picture is %dx%d, the icon %dx%d", level.width, level.height, w, h))
			end
			local parts, total = {}, 0
			for k = 1, levels do
				local enc = level
				if level.width < 4 or level.height < 4 then
					enc = image.create(4, 4)
					for y = 0, 3 do
						for x = 0, 3 do
							enc:set_pixel(x, y, level:get_pixel(x % level.width, y % level.height))
						end
					end
				end
				local str = buf_string(image.encode_texture(enc, d.format))
				if not str then error("could not read level " .. k) end
				parts[#parts + 1] = str
				total = total + #str
				if k < levels then  -- the next level: each pixel the average of four
					local lw, lh = math.max(1, level.width // 2), math.max(1, level.height // 2)
					local nxt = image.create(lw, lh)
					for y = 0, lh - 1 do
						for x = 0, lw - 1 do
							local sr, sg, sb, sa = 0, 0, 0, 0
							for dy = 0, 1 do
								for dx = 0, 1 do
									local r, g, bl, a = level:get_pixel(math.min(level.width - 1, 2 * x + dx), math.min(level.height - 1, 2 * y + dy))
									sr, sg, sb, sa = sr + r, sg + g, sb + bl, sa + a
								end
							end
							nxt:set_pixel(x, y, (sr + 2) // 4, (sg + 2) // 4, (sb + 2) // 4, (sa + 2) // 4)
						end
					end
					level = nxt
				end
			end
			local want = tonumber(d.data.hash.size)
			if total ~= want then error(string.format("the new levels are %d bytes, the old %d: not changed", total, want)) end
			d.data.hash = game.assets.create_content(buffer.wrap(table.concat(parts)))
			print(string.format("[fk_blocks]   icon from %s: %dx%d, %d levels, %d bytes", path, w, h, levels, total))
		end)
		if not ok then print(string.format("[fk_blocks]   icon FAILED (the copied icon stays): %s", tostring(err))) end
	end
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
		if src and b.recipe_inputs then  -- the owner's own ingredients instead of the source recipe's
			inputs = {}
			for _, inp in ipairs(b.recipe_inputs) do
				local g = ITEM_GUID[inp[1]]
				if not g then error("no item " .. inp[1] .. " for the recipe") end
				inputs[#inputs + 1] = {g, inp[2]}
				print(string.format("[fk_blocks]   own input %s (%s) x%d", inp[1], g, inp[2]))
			end
			category = false
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
