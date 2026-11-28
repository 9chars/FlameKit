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
-- (v0.4, owner 09:25 "can you show me here what each of the 11 textures look like?") a 128 x 128 picture of each hidden
-- material's side albedo texture: that mip level of the texture is decoded and printed as a base64 PNG ("pic <id> ...")
local HIDDEN = {129, 131, 134, 137, 139, 156, 175, 187, 188, 189, 190}
local b64c = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64(str)
  local out = {}
  for i = 1, #str, 3 do
    local a, b, c = str:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1, c2, c3, c4 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64
    out[#out + 1] = b64c:sub(c1 + 1, c1 + 1) .. b64c:sub(c2 + 1, c2 + 1) .. (b and b64c:sub(c3 + 1, c3 + 1) or "=") .. (c and b64c:sub(c4 + 1, c4 + 1) or "=")
  end
  return table.concat(out)
end
local function buf_string(buf)
  for _, f in ipairs({function() return buf:read_string(buf:tail() - buf:head()) end, function() return buf:read_string(#buf) end,
                      function() return buf:read_string(buf:len()) end}) do
    local ok, r = pcall(f)
    if ok and type(r) == "string" and #r > 0 then return r end
  end
  return nil
end
for _, r in ipairs(A.get_resources_by_type("keen::BuildingMaterialBlendingResource") or {}) do
  local b = r.data.renderingDataBlock
  for _, id in ipairs(HIDDEN) do
    local layer = id - 128
    local tex
    for _, pp in ipairs(b.patchPoints) do
      if s(pp.type) == "Texture" and pp.offset == layer * 392 + 12 then tex = b.textures[pp.parameterIndex + 1] break end
    end
    local t = tex and tex.texture
    if not t then p("pic %d: no side albedo texture", id) else
      local ok, err = pcall(function()
        local content = A.get_content(t.content.hash)
        local all = buf_string(content:read_data())
        if not all then error("could not read the content as a string") end
        -- (v0.5) the levels lie one after the other from level 0 (BC7: 16 bytes per 4 x 4 block): the first level at most
        -- 128 wide that is inside the content
        local w, h = tonumber(t.width), tonumber(t.height)
        local off, lw, lh, chunk = 0, w, h, nil
        for k = 0, (tonumber(t.levelCount) or 1) - 1 do
          lw, lh = math.max(1, math.floor(w / 2 ^ k)), math.max(1, math.floor(h / 2 ^ k))
          local size = math.ceil(lw / 4) * math.ceil(lh / 4) * 16
          if lw <= 128 and off + size <= #all then chunk = all:sub(off + 1, off + size) break end
          off = off + size
        end
        if not chunk then error(string.format("no level at most 128 wide in the content (%dx%d, %d levels, content %d bytes)", w, h, tonumber(t.levelCount) or -1, #all)) end
        local img, last
        -- (v0.6: EML takes (buffer, format, width, height): "bad argument #2 (a valid keen::PixelFormat variant expected")
        for _, fmt in ipairs({t.format, s(t.format), "BC7_srgb_block", "BC7_unorm_block"}) do
          local okd, im = pcall(image.decode_texture, buffer.wrap(chunk), fmt, lw, lh)
          if not (okd and im) then okd, im = pcall(image.decode_texture, buffer.wrap(chunk), fmt, lw, lh, 0) end
          if okd and im then img = im break end
          last = fmt .. ": " .. s(im)
        end
        if not img then error("decode_texture failed (" .. s(last) .. ")") end
        local png = buf_string(image.encode(img, "png"))
        if not png then error("could not read the PNG") end
        local e = b64(png)
        for k = 1, #e, 3000 do p("pic %d %d %s", id, math.floor((k - 1) / 3000), e:sub(k, k + 2999)) end
        p("pic %d end %d bytes %dx%d of %dx%d %s", id, #png, lw, lh, w, h, s(t.debugName))
      end)
      if not ok then p("pic %d failed: %s", id, s(err)) end
    end
  end
end
p("done")
