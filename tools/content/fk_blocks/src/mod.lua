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

local BLOCKS = {
	{  -- material 187: Building_64_buildings_set_Coldheights_GraniteCityWall_01 (no item in the game)
		guid = "a15c1573-f6fe-480a-8bc8-36559e160767", name_guid = "9bc453d8-0c10-4f5a-998d-22af8dff63f7",
		debug_name = "Block_T5_Stone_Granite_CityWall_FK", name = "Granite City Wall",
		clone_of = GRANITE_BLOCK, material = 187,
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
if not guid_of then print("[fk_blocks] no checked material list: placeVoxelMaterial left as copied") end

for _, b in ipairs(BLOCKS) do
	content.add_item{
		guid = b.guid, name_guid = b.name_guid, debug_name = b.debug_name, name = b.name, clone_of = b.clone_of,
		edit = function(it)
			it.equipment.voxelData.placeVoxelMaterialId = b.material
			local g = b.material_guid or (guid_of and guid_of(b.material))
			if g then it.equipment.voxelData.placeVoxelMaterial = g end
			print(string.format("[fk_blocks] %s placeVoxelMaterial %s", b.debug_name, tostring(it.equipment.voxelData.placeVoxelMaterial)))
		end,
	}
	print(string.format("[fk_blocks] added %s (%s) placing material %d", b.debug_name, b.guid, b.material))
end

content.finish()
