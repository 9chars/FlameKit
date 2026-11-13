# Game memory layouts worked out for the minimap (client world, build 1287369, 2026-11-11)

## Custom map markers: singleton "MapMarkerRegistry"
- +0x38 u32 count, +0x40 pointer to the first node, +0x88 pointer to the last node.
- Node, 0xc0 bytes: +0x00 x (i64, 1 m = 2^32), +0x08 y, +0x10 z, +0x18 u32 colour number, +0x1c u32 marker type id
  (the registry's markerId = FNV-1a 32 of the type GUID's 16 bytes), +0x20 char name[128], +0xa0 u64 name length,
  +0xa8 u64 index, +0xb0 previous node, +0xb8 next node.

## Custom names (flame altars, chests, ...): singleton "CustomPlayerStringsSystem"
- +0x1e0 u32 capacity (0x400), +0x1e4 u32 count, +0x1e8 pointer to the pool (singleton + 0x248).
- Entry, 0x140 bytes: +0x00/+0x08 list pointers, +0x10 u64 key (= CustomPlayerString.stringId of the entity),
  +0x18 pointer to the text (= entry + 0x38), +0x20 u64 length, +0x28 u64 capacity (0x100), +0x38 char text[0x100].
- Only filled with the names of things near the player.

## Marker types
- MapMarker.markerType (GUID) -> FNV-1a 32 over its 16 bytes = key of keen::MapMarkerRegistryResource.mapMarkers.

## Place names
- A marker entity's template component LocaTagComponent.locaTag (GUID) -> FNV-1a 32 over its 16 bytes = id in the
  language's text list (keen::LocaTagCollectionResource.languages[].data, one content blob per language).
- Text list blob: u32 offset of the rows (8), u32 row count; rows of 24 bytes sorted by id: u32 id, u32 text offset
  (relative to that field), u32 text length, u32 args offset, u32 args count, u32 genericArguments.
- Marker types that are only a name on the map (showLabel): 58c32c26 lakes and small places, 0d43c5d0 town parts,
  61342e2e passages and gates. They are not the biome regions.

## Quest marks and the game's own map list: client singleton "G38UiPlayData" (build 1287369, found 2026-11-12)
- Quest list: u64 8 at +0x34ee0 (the number of places), then 8 places of 0x50 bytes from +0x34ef8:
  +0x00 u32, +0x04 u32, +0x08 u32 (three numbers naming the quest step; 0 = empty place), +0x10 u32 marker number
  (FNV-1a 32 of MapMarker.markerId's 16 bytes; 0 = the step points at no marker), +0x14 bytes 00 01 01 00,
  +0x18 u32, +0x1c u32 (2/2 or 1/1). Seen: quest "A Nice Day For Fishing" -> the farm marker "Fishing Island".
- Map list (what the big map draws), entries of 0xa0 bytes around +0x377588 (the start of the list was not found):
  +0x00 u32 entity id, +0x08 u32 marker number (as above), +0x10 x, +0x18 y, +0x20 z (i64, 1 m = 2^32),
  +0x28 f32, +0x2c f32, +0x30 u32 marker type id, +0x34 u32 visibility, +0x38 u32 marker number again,
  +0x40 u64 a time or 0, +0x8c u32, +0x90 u32 1.
