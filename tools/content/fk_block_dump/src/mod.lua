-- fk_block_dump (FlameKit research, owner 2026-11-28 08:58 "yes lets start the process"): prints what custom blocks need
-- to know into emf\content.log. It reads only: no resource is changed or created.
local A = game.assets
local function p(...) print("[fk_block_dump] " .. string.format(...)) end
local function s(v) local ok, r = pcall(tostring, v) return ok and r or ("<" .. tostring(r) .. ">") end
local function cut(t, n) t = s(t) if #t > n then return t:sub(1, n) .. "...(" .. #t .. " chars)" end return t end
local function count(ty) local ok, l = pcall(A.get_resources_by_type, ty) return ok and l and #l or -1 end

p("server: %s", s(loader and loader.is_server))
-- the resource types that matter, and how many of each this data has
-- every solid voxel material: its type (Terrain/Building), its item and its PBR building material
local mats = A.get_resources_by_type("keen::SolidVoxelMaterial") or {}
p("SolidVoxelMaterial: %d", #mats)
for i, r in ipairs(mats) do
  local d = r.data
  p("mat %d guid %s part %s type %s item %s pbr %s hp %s hard %s", i, s(r.guid), s(r.part_index or r.part), s(d.type), s(d.materialItem), s(d.pbrBuildingMaterial), s(d.healthPoints), s(d.hardness))
end
if mats[1] then p("mat 1 in full: %s", cut(mats[1].data, 4000)) end

-- the PBR building materials (their textures, by Image GUID)
local pbr = A.get_resources_by_type("keen::PbrBuildingMaterial") or {}
p("PbrBuildingMaterial: %d", #pbr)
for i, r in ipairs(pbr) do
  local d = r.data
  p("pbr %d guid %s side albedo %s top albedo %s mapping %s", i, s(r.guid), s(d.baseMaterialSide and d.baseMaterialSide.albedoMap), s(d.baseMaterialTop and d.baseMaterialTop.albedoMap), s(d.mapping))
end
if pbr[1] then p("pbr 1 in full: %s", cut(pbr[1].data, 6000)) end

-- the baked table the renderer reads: layers and their textures
for i, r in ipairs(A.get_resources_by_type("keen::BuildingMaterialBlendingResource") or {}) do
  local d = r.data
  local b = d.renderingDataBlock
  p("blending %d guid %s layerCount %s debugName %s data %s bytes, patchPoints %s, textures %s, feedbacks %s", i, s(r.guid), s(d.layerCount),
    s(b and b.debugName), s(b and b.data and #b.data), s(b and b.patchPoints and #b.patchPoints), s(b and b.textures and #b.textures), s(b and b.textureFeedbacks and #b.textureFeedbacks))
  if b and b.textures and b.textures[1] then p("blending texture 1: %s", cut(b.textures[1], 1500)) end
  if b and b.patchPoints and b.patchPoints[1] then for k = 1, math.min(8, #b.patchPoints) do p("patch point %d: %s", k, s(b.patchPoints[k])) end end
end

-- the root objects' links, the material lists and palettes
for _, r in ipairs(A.get_resources_by_type("keen::Game38RootObjects") or {}) do
  p("root: buildingMaterialBlending %s, terraformingEfficiencyRegistry %s", s(r.data.buildingMaterialBlending), s(r.data.terraformingEfficiencyRegistry))
end
for i, r in ipairs(A.get_resources_by_type("keen::VoxelMaterialList") or {}) do p("VoxelMaterialList %d guid %s part %s: %s", i, s(r.guid), s(r.part_index or r.part), cut(r.data, 1500)) end
local pal = A.get_resources_by_type("keen::BuildingMaterialPaletteResource") or {}
p("BuildingMaterialPaletteResource: %d", #pal)
for i = 1, math.min(3, #pal) do p("palette %d guid %s: %s", i, s(pal[i].guid), cut(pal[i].data, 2500)) end
for i, r in ipairs(A.get_resources_by_type("keen::BuildingMaterialParametersResource") or {}) do p("params %d guid %s materials %s", i, s(r.guid), s(r.data.materials and #r.data.materials)) end

-- (v0.2) every item that places a voxel: equipment.voxelData = {isBuildingVoxel, placeVoxelMaterial, placeVoxelMaterialId}
local n, ids, full = 0, {}, nil
for _, r in ipairs(A.get_resources_by_type("keen::ItemInfo") or {}) do
  local e = r.data.equipment
  local vd = e and e.voxelData
  local id = vd and tonumber(vd.placeVoxelMaterialId)
  if vd and (id and id > 0 or (vd.isBuildingVoxel == true)) then
    n = n + 1
    ids[id or -1] = (ids[id or -1] or 0) + 1
    p("voxel item %s guid %s building %s material %s id %s voxelObject %s", s(r.data.debugName), s(r.guid), s(vd.isBuildingVoxel), s(vd.placeVoxelMaterial), s(id), s(e.voxelObject))
    if not full and s(r.data.debugName):find("Block_T1_Wood_Rough_CRAFTING") then full = r end
  end
end
p("items that place a voxel: %d", n)
local list = {}
for id, c in pairs(ids) do list[#list + 1] = id end
table.sort(list)
local t = {}
for _, id in ipairs(list) do t[#t + 1] = id .. "x" .. ids[id] end
p("material ids used by items: %s", table.concat(t, " "))
if full then p("Block_T1_Wood_Rough_CRAFTING equipment in full: %s", cut(full.data.equipment, 9000)) end
-- (v0.2) the blending table's layout: patch points by layer (offset / stride) and the parameters per material
for _, r in ipairs(A.get_resources_by_type("keen::BuildingMaterialBlendingResource") or {}) do
  local b = r.data.renderingDataBlock
  local pp = b.patchPoints
  local last = pp[#pp]
  p("patch points: %d; the last: %s", #pp, s(last))
  for k = 1, #pp, 48 do p("patch point %d: %s", k, s(pp[k])) end
  p("texture 2: %s", cut(b.textures[2], 600))
  p("texture %d (last): %s", #b.textures, cut(b.textures[#b.textures], 600))
end
for _, r in ipairs(A.get_resources_by_type("keen::BuildingMaterialParametersResource") or {}) do
  for k = 1, math.min(6, #r.data.materials) do p("material params %d: %s", k, cut(r.data.materials[k], 400)) end
end
-- (v0.3) per building material layer (voxel material id = 128 + layer): its textures' debug names, by patch point
local used = {}
for _, r in ipairs(A.get_resources_by_type("keen::ItemInfo") or {}) do
  local vd = r.data.equipment and r.data.equipment.voxelData
  local id = vd and tonumber(vd.placeVoxelMaterialId)
  if id and id >= 128 then used[id] = (used[id] and used[id] .. "," or "") .. s(r.data.debugName) end
end
for _, r in ipairs(A.get_resources_by_type("keen::BuildingMaterialBlendingResource") or {}) do
  local b = r.data.renderingDataBlock
  local per = {}
  for _, pp in ipairs(b.patchPoints) do
    if s(pp.type) == "Texture" then
      local layer = math.floor(pp.offset / 392)
      local within = pp.offset - layer * 392
      per[layer] = per[layer] or {}
      table.insert(per[layer], {within, pp.parameterIndex})
    end
  end
  local params = (A.get_resources_by_type("keen::BuildingMaterialParametersResource") or {})[1]
  for layer = 0, r.data.layerCount - 1 do
    local names = {}
    for _, e in ipairs(per[layer] or {}) do
      if e[1] == 12 or e[1] == 72 or e[1] == 192 or e[1] == 252 then  -- albedo of side, top, edge, edgeTop
        local t = b.textures[e[2] + 1]
        local dn = t and t.texture and s(t.texture.debugName) or "?"
        names[#names + 1] = (e[1] == 12 and "side=" or e[1] == 72 and "top=" or e[1] == 192 and "edge=" or "edgeTop=") .. dn
      end
    end
    local pm = params and params.data.materials[layer + 1]
    p("layer %d id %d textures %d item %s | %s | mapping %s", layer, 128 + layer, #(per[layer] or {}), used[128 + layer] or "NONE", table.concat(names, " "), s(pm and pm.mapping))
  end
  p("data bytes after the layers (%d x 392 = %d of %d): first 64 bytes:", r.data.layerCount, r.data.layerCount * 392, #b.data)
  local t = {}
  for k = r.data.layerCount * 392 + 1, math.min(#b.data, r.data.layerCount * 392 + 64) do t[#t + 1] = string.format("%02x", b.data[k]) end
  p("%s", table.concat(t, " "))
end
p("done")
