local file = arg[1]
local f = assert(io.open(file)) local text = f:read("a") f:close()
text = text:gsub("\nreturn F%s*$", "\nF._t = { note = note_threat, drive_step = drive_step, drives = drives, name_of = name_of, roster = roster, threats = threats, near_monsters = near_monsters, scan = monster_scan_step, watch = fight_watch, myhit = note_my_hit }\nreturn F\n")
local logs = {}
local emf = setmetatable({ log = function(s) logs[#logs+1] = "[" .. tostring(TICK) .. "] " .. s end, net = { send_to = function() end, channel = function() return true end },
  json = { encode = function() return "" end, decode = function() return {} end }, dir = "/tmp" }, { __index = function() return function() end end })
local env = setmetatable({ emf = emf, require = function(n) return setmetatable({}, { __index = function() return function() return {} end end }) end }, { __index = _G })
local F = assert(load(text, "=" .. file, "t", env))()
-- (0.15.362) no strict globals check: the split companion code keeps shared values in its environment
local T = F._t
local S = 2^32
local tick = 0
local comps, pos = {}, {}
local function mover(e, x, y, z)
  comps[e] = { DynamicLocomotion = { currentWaterState = 0, state = 0, jumpCount = 0 }, MovementCollider = { results = { m_isSet = true, m_value = { hasGroundCollision = true, groundDistance = 0 } } },
    Velocity = { velocity = { x = 0, y = 0, z = 0 } }, CurrentTransform = { transform = { position = { x = x*S, y = y*S, z = z*S }, orientation = { x = 0, y = 0, z = 0, w = 1 } } },
    Health = { dataStorage = { 3680, 0, 3680 } }, Actor = { currentServerAction = { animationStateId = 0 } } }
end
mover(1, 0, 0, 0) mover(100, 1, 0, 1)
comps[100].DynamicEnemy01BehaviorState = { enabled = false, homeZonePosition = {x=0,y=0,z=0}, movementTarget = {x=0,y=0,z=0}, combatData = { selectedAttackIndex = 0, lastTargetId = 0, targetOfMyTarget = false, isTargetInsideLeash = false } }
comps[100].DynamicPathWalker = { isWalkingActive = false }
local function monster(e, x, z, hp) pos[e] = {x, 0, z} comps[e] = { DynamicEnemy01BehaviorState = {}, Faction = { faction = 4 }, NetworkHealth = { health = hp } } end
monster(200, 6, 6, 900) monster(201, 10, -3, 600)
for _, a in ipairs(arg) do local v = a:match("^high=(%d+)$") if v then pos[200][2] = tonumber(v) end end monster(202, 40, 0, 500)
local W = { tick = function() return tick end, get = function(_, c, e) return comps[e] and comps[e][c] end,
  position = function(_, e) local c = comps[e] and comps[e].CurrentTransform if c then local p = c.transform.position return p.x/S, p.y/S, p.z/S end local p = pos[e] if p then return p[1],p[2],p[3] end end,
  entities = function() return { 1, 100, 200, 201, 202 } end, account = function() return nil end }
T.drives[100] = { player = 1, trail = {} }
T.name_of[100] = "N1"
T.roster.list = { { name = "N1", fight = "Aggressive" } }
local anim_until = 0
BLOCKED = {}
for _, a in ipairs(arg) do local k, v = a:match("^(%w+)=(%d+)$") if k == "block" then BLOCKED[tonumber(v)] = true elseif k == "from" then BLOCK_FROM = tonumber(v) elseif k == "passiveat" then PASSIVE_AT = tonumber(v) elseif k == "onlyhit" then ONLY_HIT = tonumber(v) elseif k == "fastuntil" then FAST_UNTIL = tonumber(v) elseif k == "inject" then INJ = tonumber(v) elseif k == "wall" then WALL = tonumber(v) elseif k == "objhit" then OBJHIT = tonumber(v) end end
for _, a in ipairs(arg) do if a == "defensive" then T.roster.list[1].fight = "Defensive" end end
for i = 1, 2500 do
  tick = tick + 1 TICK = tick
  local cd = comps[100].DynamicEnemy01BehaviorState.combatData
  -- the C++ stand-in: start the move, the animation plays 40 ticks, the hit lands
  -- the ray stand-in: blocked for the ids in BLOCKED (from tick BLOCK_FROM)
  cd.isTargetReachable = not (BLOCKED[cd.lastTargetId] and tick >= (BLOCK_FROM or 0))
  cd.distanceToTarget = cd.isTargetReachable and 5 or 2
  if cd.selectedAttackIndex == 0 or cd.selectedAttackIndex == 1 then
    local tg = cd.lastTargetId
    cd.selectedAttackIndex = 255
    anim_until = tick + 40
    local pp = comps[100].CurrentTransform.transform.position
    local far = WALL and pos[tg] and math.sqrt((pos[tg][1] - pp.x/S)^2 + (pos[tg][3] - pp.z/S)^2) > 3
    if far then
      if OBJHIT then PENDING = { tick + 20, OBJHIT } end
    elseif comps[tg] and comps[tg].NetworkHealth then comps[tg].NetworkHealth.health = comps[tg].NetworkHealth.health - 420 PENDING = { tick + 20, tg } end
  end
  if FAST_UNTIL and comps[200] then comps[200].Velocity = { velocity = { x = tick < FAST_UNTIL and 6 or 0, y = 0, z = 0 } } end
  if INJ and tick == INJ then T.myhit(W, { attacker = 100, target = 999 }) end
  if PENDING and tick == PENDING[1] then T.myhit(W, { attacker = 100, target = PENDING[2] }) PENDING = nil end
  comps[100].Actor.currentServerAction.animationStateId = (tick < anim_until and tick > anim_until - 38) and 1184786262 or 0
  if pos[200] and comps[200].NetworkHealth.health <= 0 then pos[200] = nil end
  if pos[201] and comps[201].NetworkHealth.health <= 0 then pos[201] = nil end
  -- he walks to his target (the native hook stand-in), stops 2 m off
  local a = comps[100].DynamicEnemy01BehaviorState
  local p = comps[100].CurrentTransform.transform.position
  local hx, hz = p.x/S, p.z/S
  local dx, dz = a.homeZonePosition.x - hx, a.homeZonePosition.z - hz
  local d = math.sqrt(dx*dx + dz*dz)
  local nx2, nz2 = hx + dx/d*0.1, hz + dz/d*0.1
  local blockedw = WALL and pos[200] and math.sqrt((pos[200][1]-nx2)^2 + (pos[200][3]-nz2)^2) < WALL
  if d > 2 and not blockedw then p.x = nx2*S p.z = nz2*S end
  T.scan(W)
  if PASSIVE_AT and tick == PASSIVE_AT then T.roster.list[1].fight = "Passive" logs[#logs+1] = "[" .. tick .. "] TEST: the player sets Passive" end
  if PASSIVE_AT and tick == PASSIVE_AT + 30 then local cd = comps[100].DynamicEnemy01BehaviorState.combatData local hz = comps[100].DynamicEnemy01BehaviorState.homeZonePosition logs[#logs+1] = string.format("[%d] TEST: 30 ticks later: lastTargetId %s, he is sent to %.1f %.1f (the player at 0 0), monster 200 health %s", tick, tostring(cd.lastTargetId), hz.x, hz.z, tostring(comps[200].NetworkHealth.health)) end
  if ONLY_HIT then if tick % 37 == 0 then T.note(W, { attacker = ONLY_HIT, target = 1, amount = 120, types = {'cut'}, attacks = {'melee'}, health_before = 900, health_after = 780 }) end
  elseif tick % 37 == 0 then T.note(W, { attacker = 200, target = 100, amount = 238, types = {'pierce'}, attacks = {'melee'} }) T.note(W, { attacker = 100, target = 200, amount = 350, types = {'pierce'} }) T.note(W, { attacker = 201, target = 1, amount = 120, types = {'cut'}, attacks = {'melee'}, health_before = 900, health_after = 780 }) end
  if tick % 60 == 0 then T.watch(W) end
  if not ONLY_HIT or true then end
  local ok, err = pcall(T.drive_step, W, 100, T.drives[100])
  if not ok then print("ERROR", err) break end
end
for _, l in ipairs(logs) do if (l:find("fight") or l:find("ERROR"))  and not l:find("Health") and not l:find("defence") and not l:find("last 10") and not l:find("player took") and not l:find("threat") or l:find("TEST") then print(l) end end
