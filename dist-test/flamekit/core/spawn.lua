-- core/spawn.lua (0.15.476): what spawning monsters on the server needs, shared by features/experimental.lua (test
-- monsters) and features/spawn_nodes.lua (spawn nodes) (HANDOFF rule 0b: features never call each other).
--
-- ON THE GROUND (moved here from features/experimental.lua, 0.15.140, owner: "spawn on top of the terrain so they don't
-- end up inside stuff"): emf.spawn puts a monster exactly at the given place, which on a slope is inside the hill or in
-- the air. So WAIT_STEPS after its spawn each one is moved with emf.teleport and the game's own ground search (fast
-- travel's: the nearest walkable spot within about 10 m up or down). The wait: EMF refuses a creature spawned a moment
-- ago (it reads as dead until the game sets its health). EMF allows 64 teleports under way for all of FlameKit; each
-- queue has its own limit (`max`), and the queues together stay below 64 (the rest is for players).
--
-- LEVEL (moved here from features/experimental.lua): EMF re_companion_orders.md: writing Level.dataStorage and
-- DynamicEnemyScaling.nextUpdateTime = 0 makes the game's next scaling update use the new level.

local M = {}

M.WAIT_STEPS = 120     -- server steps (2 s) between the spawn and the move to the ground
M.GIVEUP_STEPS = 900   -- a teleport whose answer never came (a reload) is not counted any more after 15 s

-- A queue of spawned monsters to put on the ground. opts: max = teleports under way at once (default 20),
-- keep = function(id) -> false when the monster is no longer wanted (then it is skipped). Call q.add(id, x, y, z) after
-- each spawn (yaw: optional, degrees, 0 north (+z), 90 east (+x): the way it faces after the move) and q.tick(world)
-- on every server step.
function M.ground(opts)
  opts = opts or {}
  local max = opts.max or 20
  local keep = opts.keep or function() return true end
  local q = { list = {}, head = 1, busy = {}, n = 0, step = 0 }
  function q.add(id, x, y, z, yaw)
    q.list[#q.list + 1] = { id = id, x = x, y = y, z = z, yaw = yaw, at = q.step + M.WAIT_STEPS }
  end
  function q.tick(world)
    q.step = q.step + 1
    if q.n > 0 and q.step % 60 == 0 then
      for id, at in pairs(q.busy) do
        if q.step - at > M.GIVEUP_STEPS then q.busy[id], q.n = nil, q.n - 1 end
      end
    end
    while q.head <= #q.list and q.n < max do
      local g = q.list[q.head]
      if g.at > q.step then break end
      q.head = q.head + 1  -- (entries stay until the queue is empty: # of a table with holes is not reliable)
      if keep(g.id) and not q.busy[g.id] then
        local x, z = g.x, g.z
        pcall(function()  -- where it is now (it may have walked a little), at the height it was given
          local px, _, pz = world:position(g.id)
          if px and pz then x, z = px, pz end
        end)
        local id = g.id
        local okt, queued = pcall(emf.teleport, world, id, x, g.y, z, { ground = true, yaw = g.yaw }, function()
          if q.busy[id] then q.busy[id], q.n = nil, q.n - 1 end
        end)
        if okt and queued then q.busy[id], q.n = q.step, q.n + 1 end
      end
    end
    if q.head > #q.list then q.list, q.head = {}, 1 end
  end
  return q
end

-- Sets monster `id` to level `level` (the game's next scaling update uses it). False when it has no Level.
function M.set_level(world, id, level)
  local lv = world:get("Level", id)
  if not lv then return false end
  lv.dataStorage[1] = level
  local sc = world:get("DynamicEnemyScaling", id)
  if sc then
    if type(sc.nextUpdateTime) == "table" then sc.nextUpdateTime.value = 0 else sc.nextUpdateTime = 0 end
  end
  return true
end

return M
