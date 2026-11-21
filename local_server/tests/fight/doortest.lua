local file = arg[1]
local f = assert(io.open(file)) local text = f:read("a") f:close()
text = text:gsub("\nreturn F%s*$", "\nF._t = { note = note_threat, drive_step = drive_step, drives = drives, name_of = name_of, roster = roster, threats = threats, near_monsters = near_monsters, scan = monster_scan_step, watch = fight_watch }\nreturn F\n")
local logs = {}
local emf = setmetatable({ log = function(s) logs[#logs+1] = s end, net = { send_to = function() end, channel = function() return true end },
  json = { encode = function() return "" end, decode = function() return {} end }, dir = "/tmp" }, { __index = function() return function() end end })
local env = setmetatable({ emf = emf, require = function(n) return setmetatable({}, { __index = function() return function() return {} end end }) end }, { __index = _G })
local F = assert(load(text, "=" .. file, "t", env))()
rawset(env, "DOOR", nil)  -- (0.15.362) no strict globals check: the split companion code keeps shared values in its environment
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
monster(200, 6, 6, 900) monster(201, 10, -3, 600) monster(202, 40, 0, 500)
local W = { tick = function() return tick end, get = function(_, c, e) return comps[e] and comps[e][c] end,
  position = function(_, e) local c = comps[e] and comps[e].CurrentTransform if c then local p = c.transform.position return p.x/S, p.y/S, p.z/S end local p = pos[e] if p then return p[1],p[2],p[3] end end,
  entities = function() return { 1, 100, 200, 201, 202 } end, account = function() return nil end }
T.drives[100] = { player = 1, trail = {} }
T.name_of[100] = "N1"
T.roster.list = { { name = "N1", fight = "Aggressive" } }
local anim_until = 0
DOORON = true
for i = 1, 1500 do
  tick = tick + 1
  local cd = comps[100].DynamicEnemy01BehaviorState.combatData
  -- the C++ stand-in: start the move, the animation plays 40 ticks, the hit lands
  if cd.selectedAttackIndex == 0 or cd.selectedAttackIndex == 1 then
    local tg = cd.lastTargetId
    cd.selectedAttackIndex = 255
    anim_until = tick + 40
    if tg ~= 200 and comps[tg] and comps[tg].NetworkHealth then comps[tg].NetworkHealth.health = comps[tg].NetworkHealth.health - 420 end
  end
  comps[100].Actor.currentServerAction.animationStateId = (tick < anim_until and tick > anim_until - 38) and 1184786262 or 0
  if pos[200] and comps[200].NetworkHealth.health <= 0 then pos[200] = nil end
  if pos[201] and comps[201].NetworkHealth.health <= 0 then pos[201] = nil end
  -- he walks to his target (the native hook stand-in), stops 2 m off
  local a = comps[100].DynamicEnemy01BehaviorState
  local p = comps[100].CurrentTransform.transform.position
  local hx, hz = p.x/S, p.z/S
  local dx, dz = a.homeZonePosition.x - hx, a.homeZonePosition.z - hz
  local d = math.sqrt(dx*dx + dz*dz)
  if d > 2 and (not DOORON or math.sqrt((hx-6)^2+(hz-6)^2) > 3.5) then p.x = (hx + dx/d*0.1)*S p.z = (hz + dz/d*0.1)*S end
  T.scan(W)
  if tick % 37 == 0 then T.note(W, { attacker = 200, target = 100, amount = 238, types = {'pierce'}, attacks = {'melee'} }) T.note(W, { attacker = 201, target = 1, amount = 120, types = {'cut'}, attacks = {'melee'}, health_before = 900, health_after = 780 }) end
  if tick % 60 == 0 then T.watch(W) end
  local ok, err = pcall(T.drive_step, W, 100, T.drives[100])
  if not ok then print("ERROR", err) break end
end
for _, l in ipairs(logs) do if l:find("fight") or l:find("ERROR") then print(l) end end
