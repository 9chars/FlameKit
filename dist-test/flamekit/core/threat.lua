-- core/threat.lua (0.15.522): puts a player straight into a monster's threat table, the way FlameKit already does for
-- PvP players since 0.15.69 (features/experimental.lua, alarm; measured there in game). Server world only.
--
-- A monster's threat table is DynamicAggro: 6 slots of AggroTarget, each with the candidate (entityId, targetId), its
-- faction, a state (Alarmed = 3: the AI picks its fight from the Alarmed slots) and an aggro value (hits and damage
-- raise it, time lowers it; the game's picker chooses between the Alarmed slots by aggro, at most every 2-2.5 s).
-- M.alarm puts the player into his slot (or a free one: the game's own candidates are never pushed out) as Alarmed,
-- faction 7 (Player), with a starting aggro by distance (closest highest) and afterwards keeps it from falling under
-- M.FLOOR while the player is near, so the game's own aggro decides between players. M.event also sends the game's own
-- AddThreatTargetEvent (the monster is told the player threatens it).

local M = { ALARMED = 3, PLAYER_FACTION = 7, FLOOR = 20, THREAT = 100 }

-- An entity id from a game value (a table with id, or the number).
local function eid(v)
  if type(v) == "table" then return v.id end
  return v
end

-- Writes `value` into holder[field], also when the field is a table with an id.
local function set_id(holder, field, value)
  local v = holder[field]
  if type(v) == "table" then
    if v.id ~= value then v.id = value return true end
  elseif v ~= value then
    holder[field] = value
    return true
  end
  return false
end

function M.start_aggro(dist) return math.max(40, 100 - 3 * (dist or 20)) end

-- Puts player `player` into monster `monster`'s threat table. Returns "added", "kept", "full" (no free slot) or "none"
-- (no threat table).
function M.alarm(world, monster, player, dist)
  local ag = world:get("DynamicAggro", monster)
  if not ag then return "none" end
  local slot, fresh
  for i = 1, 6 do
    if eid(ag.targets[i].entityId) == player and tonumber(tostring(ag.targets[i].state)) ~= 0 then slot = ag.targets[i] break end
  end
  if not slot then
    for i = 1, 6 do
      if tonumber(tostring(ag.targets[i].state)) == 0 then slot, fresh = ag.targets[i], true break end
    end
  end
  if not slot then return "full" end
  set_id(slot, "entityId", player)
  set_id(slot, "targetId", player)
  if tonumber(tostring(slot.state)) ~= M.ALARMED then slot.state = M.ALARMED end
  if tonumber(tostring(slot.faction)) ~= M.PLAYER_FACTION then slot.faction = M.PLAYER_FACTION end
  if fresh then
    slot.aggro = M.start_aggro(dist)
  elseif slot.aggro < M.FLOOR then
    slot.aggro = M.FLOOR
  end
  return fresh and "added" or "kept"
end

-- The game's own event: monster `monster` is threatened by `player`. True when sent.
function M.event(monster, player)
  return emf.emit("server", "AddThreatTargetEvent", { attackerId = monster, targetId = player, threatValue = M.THREAT }) ~= false
end

-- (0.15.527) What a monster's AI does, for the log: its behaviour state (DynamicEnemy01BehaviorState.state, the raw
-- number: 0.15.68 measured 6 = in a fight) or nil (no enemy AI), and its target (SelectedTargets slot 1) or nil.
function M.ai(world, id)
  local ai = world:get("DynamicEnemy01BehaviorState", id)
  local st = world:get("SelectedTargets", id)
  local t = st and st.targets and st.targets[1] and st.targets[1].targetEntityId
  if type(t) == "table" then t = t.id end
  return ai and tonumber(tostring(ai.state)) or nil, t
end

-- (0.15.527) The threat table without the aggro values ("state:entity" of the slots in use): changes only when a
-- slot's candidate or state changes, not every time the aggro moves.
function M.key(world, id)
  local ag = world:get("DynamicAggro", id)
  if not ag then return "none" end
  local parts = {}
  for i = 1, 6 do
    local t = ag.targets[i]
    local st = tonumber(tostring(t.state)) or -1
    if st ~= 0 then parts[#parts + 1] = st .. ":" .. tostring(eid(t.entityId)) end
  end
  return table.concat(parts, ",")
end

-- A threat table for the log: "slot: state entity faction aggro" for the slots in use.
function M.line(world, id)
  local ag = world:get("DynamicAggro", id)
  if not ag then return "no threat table" end
  local parts = {}
  for i = 1, 6 do
    local t = ag.targets[i]
    local st = tonumber(tostring(t.state)) or -1
    if st ~= 0 then parts[#parts + 1] = string.format("%d: %d e%s f%s a%.0f", i, st, tostring(eid(t.entityId)), tostring(t.faction), t.aggro or -1) end
  end
  return #parts > 0 and table.concat(parts, "; ") or "empty"
end

return M
