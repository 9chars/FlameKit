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

for _, b in ipairs(BLOCKS) do
	content.add_item{
		guid = b.guid, name_guid = b.name_guid, debug_name = b.debug_name, name = b.name, clone_of = b.clone_of,
		edit = function(it)
			it.equipment.voxelData.placeVoxelMaterialId = b.material
		end,
	}
	print(string.format("[fk_blocks] added %s (%s) placing material %d", b.debug_name, b.guid, b.material))
end

content.finish()
