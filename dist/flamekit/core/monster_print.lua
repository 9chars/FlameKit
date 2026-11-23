-- core/monster_print.lua (0.15.383, owner 2026-11-21 12:15 "all the monster names in the battle tab say "Fogger(45)" ???
-- ... it need to say the actual monster's name"; 12:18 "do 1 now"): which kind of monster an entity is. EMF cannot say
-- an entity's template, but world:template(component, id) gives the template half of a component, shared by every
-- entity of one template. A fingerprint of a few such halves names the kind; core/monster_names.lua (made once with the
-- debug command flamekit.monprints on the local server: every kind of core/monsters.lua spawned out of sight, printed,
-- removed) maps fingerprints to FlameKit's names of the kinds.
--   print.of(world, id [, comps])   the fingerprint text, or nil when the entity has none of the components
--   print.FIELDS                    the template fields that make it
--   print.name(world, id)           (0.15.384) the monster's name, or nil

local print_ = {}

-- the template fields looked at (EMF gives template halves as read-only component data, not tables: fields by name)
print_.FIELDS = {
  { "AnimationGraphResourceComponent2", "animationGraph" },
  { "AnimationGraphResourceComponent2", "retargetData" },
  { "EnemyArsenalReference", "arsenal" },
  { "Destructible", "maxHealth" },
}

-- One template field as text, or nil.
function print_.part(world, id, comp, field)
  local ok, v = pcall(function() local t = world:template(comp, id) return t and t[field] end)
  if not ok or v == nil then return nil end
  return tostring(v)
end

-- The fingerprint: the fields joined with "|" ("-" for one the entity has not), nil when it has none of them.
function print_.of(world, id)
  local parts, any = {}, false
  for _, f in ipairs(print_.FIELDS) do
    local v = print_.part(world, id, f[1], f[2])
    parts[#parts + 1] = v or "-"
    if v then any = true end
  end
  return any and table.concat(parts, "|") or nil
end

-- (0.15.384) A monster's name from core/monster_names.lua: its kind (the template's arsenal), else its species (the
-- animation graph, for kinds core/monsters.lua does not have), else nil.
local names
-- FlameKit's name for the kind of monster `id` is (by its arsenal, else its animation graph; core/monster_names.lua), or nil.
function print_.name(world, id)
  if names == nil then
    local ok, t = pcall(require, "core.monster_names")
    names = ok and type(t) == "table" and t or false
  end
  if not names then return nil end
  local a = print_.part(world, id, "EnemyArsenalReference", "arsenal")
  if a and names.arsenal[a] then return names.arsenal[a] end
  local g = print_.part(world, id, "AnimationGraphResourceComponent2", "animationGraph")
  return g and names.graph[g] or nil
end

return print_
