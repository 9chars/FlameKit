-- core/skills.lua (0.15.209): which skill tree nodes a player has unlocked. Server world only.
--
-- The game keeps a player's skills in UnlockedSkillNodes: knownSkillNodes[1..256] (the node ids, 0 = empty). Node ids come from the game's skill tree
-- (SkillTreeResource, resource type 0xe4b6994f, 243 nodes at build 1287369): see flamekit_native/notes/skills.md and
-- skill_tree.tsv there. Read only: FlameKit never changes a player's skills.

local M = {
  DOUBLE_JUMP = 0xffd5f940,  -- the node whose unlock item is Ability_DoubleJump (checked on the owner's player)
  broken = false,
}

local function num(v)
  if type(v) == "table" then v = v.value or v.id or v[1] end
  return math.tointeger(tonumber(tostring(v))) or 0
end

-- true when the player has the node, false when not, nil when it cannot be read (then the caller decides)
function M.has(world, entity, node)
  if M.broken then return nil end
  local result
  local ok, err = pcall(function()
    local u = world:get("UnlockedSkillNodes", entity)
    if not u then return end
    result = false
    for k = 1, 256 do
      if num(u.knownSkillNodes[k]) & 0xffffffff == node then
        result = true  -- a node is in the list only once unlocked (owner's player: 95 of 243, Double Jump among them)
        return
      end
    end
  end)
  if not ok then
    M.broken = true
    emf.log("skills: the player's skills cannot be read on this game version (" .. tostring(err) .. ")")
    return nil
  end
  return result
end

return M
