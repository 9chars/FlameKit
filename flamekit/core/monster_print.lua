-- core/monster_print.lua (0.15.383, owner 2026-11-21 12:15 "all the monster names in the battle tab say "Fogger(45)" ???
-- ... it need to say the actual monster's name"; 12:18 "do 1 now"): which kind of monster an entity is. EMF cannot say
-- an entity's template, but world:template(component, id) gives the template half of a component, shared by every
-- entity of one template. A fingerprint of a few such halves names the kind; core/monster_names.lua (made once with the
-- debug command flamekit.monprints on the local server: every kind of core/monsters.lua spawned out of sight, printed,
-- removed) maps fingerprints to FlameKit's names of the kinds.
--   print.of(world, id [, comps])   the fingerprint text, or nil when the entity has none of the components
--   print.COMPS                     the components that make it

local print_ = {}

-- the template halves looked at (server-side components; ModelResource is the client's only)
print_.COMPS = { "DefaultInventory", "Enemy01BehaviorState", "AnimationGraphResourceComponent2", "CharacterSetup", "NpcSetup", "Wildlife" }

-- FNV-1a 32 over a text
local function fnv(s)
  local h = 2166136261
  for i = 1, #s do
    h = h ~ s:byte(i)
    h = (h * 16777619) % 4294967296
  end
  return string.format("%08x", h)
end

-- a table's fields in a fixed order (nested tables too), as one text
local function flat(v, depth, out)
  local t = type(v)
  if t == "table" then
    if depth > 6 then out[#out + 1] = "~" return end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    out[#out + 1] = "{"
    for _, k in ipairs(keys) do
      out[#out + 1] = tostring(k) .. "="
      flat(v[k], depth + 1, out)
      out[#out + 1] = ","
    end
    out[#out + 1] = "}"
  elseif t == "number" then
    out[#out + 1] = string.format("%.6g", v)
  else
    out[#out + 1] = tostring(v)
  end
end

-- One component's template half as a short hash, or nil.
function print_.part(world, id, comp)
  local ok, v = pcall(world.template, world, comp, id)
  if not ok or v == nil then return nil end
  local out = {}
  flat(v, 0, out)
  return fnv(table.concat(out))
end

function print_.of(world, id, comps)
  local parts, any = {}, false
  for _, c in ipairs(comps or print_.COMPS) do
    local h = print_.part(world, id, c)
    parts[#parts + 1] = h or "-"
    if h then any = true end
  end
  return any and table.concat(parts, ".") or nil
end

return print_
