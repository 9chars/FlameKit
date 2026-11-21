-- Differential test: runs drive_step from two versions of npc_probe.lua through the same scripted scenario in a fake
-- world, and compares every component, the companion's record (h), every log line and every network message, tick by
-- tick. Usage: texlua harness.lua <old.lua> <new.lua> <seed> [ticks]
COV = nil
WALL = nil
NOSNAP = nil
local OLD, NEW, SEED, TICKS = arg[1], arg[2], tonumber(arg[3]) or 1, tonumber(arg[4]) or 6000
local S = 2 ^ 32

local function ser(v, seen, path)
  seen = seen or {}
  local tv = type(v)
  if tv == "number" then
    if v ~= v then return "nan" end
    return string.format("%.17g", v)
  elseif tv ~= "table" then return tostring(v) end
  if seen[v] then return "<ref " .. seen[v] .. ">" end
  seen[v] = path or "root"
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. ser(v[k], seen, (path or "") .. "." .. tostring(k)) end
  return "{" .. table.concat(out, ",") .. "}"
end

local function load_version(file)
  local f = assert(io.open(file, "r")) local text = f:read("a") f:close()
  text = text:gsub("\nreturn F%s*$", "\nF._drive_step = drive_step F._drives = drives F._holds = holds\nreturn F\n")
  local rec = { log = {} }
  local emf = setmetatable({
    log = function(s) rec.log[#rec.log + 1] = s end,
    net = { send_to = function(w, p, ch, d) rec.log[#rec.log + 1] = "NET " .. tostring(p) .. " " .. ch .. " " .. d end,
            channel = function() return true end },
    json = { encode = function(t) return ser(t) end, decode = function() return {} end },
    dir = "/tmp",
  }, { __index = function(_, k) return function() end end })
  local env = setmetatable({ emf = emf, require = function(n)
    if n == "core.store" or n == "core.players" or n == "core.companions" then
      return setmetatable({}, { __index = function() return function() return {} end end })
    end
    error("no module " .. n)
  end }, { __index = _G })
  local chunk = assert(load(text, "=" .. file, "t", env))
  local F = chunk()
  -- (0.15.362) no strict globals check: the split companion code keeps shared values in its environment
  return F, rec
end

-- the world --------------------------------------------------------------------------------------------------------
local PLAYER, HOUND, ANIMAL = 1, 100, 200
local function terrain(x, z)
  if z > 40 then return -6 end           -- the lake bed
  if x > 20 and x < 40 then return 2 end -- a ledge 2 m up
  if x < -20 then return -10 end         -- a cliff 10 m down
  return 0
end
local function water_level(x, z) if z > 40 then return 0 end return nil end

local function new_world()
  local W = { t = 0, comps = {}, pos = {} }
  local function c(e, name, tbl) W.comps[e] = W.comps[e] or {} W.comps[e][name] = tbl end
  local function mover(e)
    c(e, "DynamicLocomotion", { currentWaterState = 0, state = 0, slideDetected = false, slidingFallingFactor = 0, frictionFactor = 1, jumpCount = 0, jumpType = 0 })
    c(e, "MovementCollider", { results = { m_isSet = true, m_value = { hasGroundCollision = true, groundDistance = 0, hasSpheroidCollision = false, hasPlayerSpheroidCollision = false } } })
    c(e, "Velocity", { velocity = { x = 0, y = 0, z = 0 } })
    c(e, "CurrentTransform", { transform = { position = { x = 0, y = 0, z = 0 }, orientation = { x = 0, y = 0, z = 0, w = 1 } } })
    c(e, "Oxygen", { dataStorage = { 30, 30, 0, 0, 0, 30 } })
    c(e, "Health", { dataStorage = { 100, 100 } })
    c(e, "ActorInput", { desiredWorldMoveInput = { x = 0, y = 0, z = 0 } })
  end
  mover(PLAYER) mover(HOUND)
  c(PLAYER, "DynamicOxygenState", { accumulatedValue = 0 })
  c(HOUND, "DynamicEnemy01BehaviorState", { enabled = true, homeZonePosition = { x = 0, y = 0, z = 0 }, movementTarget = { x = 0, y = 0, z = 0 },
    movementTargetIsValid = false, combatData = { targetOfMyTarget = false, isTargetInsideLeash = false } })
  c(HOUND, "ServerSubmerge", { submergeDepth = 0 })
  c(HOUND, "IsInWaterCheck", { waterSubmersionHeight = 0 })
  c(HOUND, "DynamicPathWalker", { isWalkingActive = true })
  c(HOUND, "Faction", { faction = 11 })
  c(ANIMAL, "Animal", {})
  c(ANIMAL, "Faction", { faction = 3 })
  W.pos[ANIMAL] = { 3, 0, 3 }
  function W:tick() return self.t end
  function W:get(name, e) local cc = self.comps[e] return cc and cc[name] end
  function W:entities() return { PLAYER, HOUND, ANIMAL } end
  function W:account(e) if e == PLAYER then return "0xabc" end return nil end
  function W:set_pos(e, x, y, z)
    local p = self.comps[e].CurrentTransform.transform.position
    p.x, p.y, p.z = math.floor(x * S), math.floor(y * S), math.floor(z * S)
  end
  function W:position(e)
    if self.gone and self.gone[e] then return nil end
    local cc = self.comps[e]
    if cc and cc.CurrentTransform then
      local p = cc.CurrentTransform.transform.position
      return p.x / S, p.y / S, p.z / S
    end
    local p = self.pos[e]
    if p then return p[1], p[2], p[3] end
    return nil
  end
  return W
end

-- the scenario: the player's moves (the same random choices for both versions) ---------------------------------------
local DIRECTED = {
  [1001] = { {kind="walk",dir=90,len=160}, {kind="djhere",dir=90,len=70}, {kind="stand",len=300}, {kind="walk",dir=90,len=100}, {kind="stand",len=300} },
  [1002] = { {kind="walk",dir=270,len=260}, {kind="stand",len=40}, {kind="come",len=10}, {kind="stand",len=300} },
  [1003] = { {kind="walk",dir=0,len=500,wall=true}, {kind="stand",len=400,wall=true}, {kind="stand",len=300}, {kind="walk",dir=180,len=200}, {kind="stand",len=100} },
  [1004] = { {kind="walk",dir=0,len=420}, {kind="stand",len=300,wall=37.2,pos={0,0,39.9}}, {kind="walk",dir=0,len=30,wall=37.2}, {kind="stand",len=200,wall=37.2}, {kind="stand",len=200} },
  [1005] = { {kind="walk",dir=0,len=500,wall=true}, {kind="stand",len=140,wall=true}, {kind="walk",dir=180,len=150,wall=true}, {kind="stand",len=300} },
  [1006] = { {kind="walk",dir=90,len=150}, {kind="djhere",dir=90,len=70}, {kind="walk",dir=90,len=60}, {kind="stand",len=400} },
}
local function scenario(seed)
  if DIRECTED[seed] then
    for _, st in ipairs(DIRECTED[seed]) do st.dir = st.dir or 0 st.r = 1 end
    return DIRECTED[seed]
  end
  local rnd = (function() local s = seed * 7919 + 13 return function(n) s = (s * 1103515245 + 12345) % 2147483648 return s % n end end)()
  local steps = {}
  local kinds = { "walk", "walk", "walk", "jump", "djump", "glide", "travel", "swim", "dive", "stand", "block", "hold", "lure", "ledge", "cliff", "lake", "djledge", "come", "come", "leapout", "shore" }
  for _ = 1, 60 do
    local k = kinds[rnd(#kinds) + 1]
    steps[#steps + 1] = { kind = k, dir = rnd(360), len = 60 + rnd(300), r = rnd(1000) }
  end
  return steps
end

local function run(file, seed)
  local F, rec = load_version(file)
  local W = new_world()
  local px, py, pz, pvy = 0, 0, 0, 0
  W:set_pos(PLAYER, 0, 0, 0)
  W:set_pos(HOUND, 1, 0, -1)
  local h = { player = PLAYER, trail = {} }
  F._drives[HOUND] = h
  local steps = scenario(seed)
  local si, st_t = 1, 0
  local snaps = {}
  local blocked = false
  for tick = 1, TICKS do
    W.t = tick
    rec.log = {}
    -- the player
    local step = steps[si]
    if not step then break end
    st_t = st_t + 1
    if st_t > step.len then si, st_t = si + 1, 0 step = steps[si] if not step then break end end
    local k = step.kind
    local yaw = math.rad(step.dir)
    local ploc = W:get("DynamicLocomotion", PLAYER)
    local pcol = W:get("MovementCollider", PLAYER).results.m_value
    local pv = W:get("Velocity", PLAYER).velocity
    blocked = (k == "block") or (step.r % 5 == 0 and st_t > step.len / 2)
    WALL = step.wall
    if st_t == 1 and step.pos then px, py, pz = step.pos[1], step.pos[2], step.pos[3] end
    if st_t == 1 and k == "djhere" then pvy = 9 ploc.jumpCount = 1 end
    if k == "djhere" and st_t == 25 then pvy = 9 ploc.jumpCount = 2 end
    if st_t == 1 and k == "hold" then F._holds[HOUND] = { target = ANIMAL, untill = tick + 100 } end
    if st_t == 1 and k == "lure" then h.lure = { x = px + 5, y = py, z = pz + 5, untill = tick + 120 } end
    if st_t == 1 and k == "travel" then px, pz = px + 120, pz + 30 end
    if st_t == 1 and k == "ledge" then px, pz = 25, 0 end
    if st_t == 1 and k == "cliff" then px, pz = -25, 0 end
    if st_t == 1 and k == "lake" then px, pz = 0, 45 end
    if st_t == 1 and k == "djledge" then px, py, pz = 17, 0, 0 step.dir = 90 yaw = math.rad(90) pvy = 9 ploc.jumpCount = 1 end
    if k == "djledge" and st_t == 25 then pvy = 9 ploc.jumpCount = 2 end
    if k == "djledge" and st_t > 60 then step.dir = 90 end
    if st_t == 1 and k == "come" then local hx0, hy0, hz0 = W:position(HOUND) px, py, pz = hx0 + 1.5, hy0, hz0 + 1.5 end
    if st_t == 1 and k == "leapout" then px, py, pz = 0, 3, 39.5 step.dir = 0 yaw = 0 pvy = 4 end
    if k == "leapout" and st_t == 40 then px, py, pz = 0, 0, 30 end
    if st_t == 1 and k == "shore" then local hx0, _, hz0 = W:position(HOUND) px, pz = hx0, math.max(hz0 + 4, 42) end
    W:get("ActorInput", HOUND).desiredWorldMoveInput.x = (tick % 7 == 0) and 1 or 0
    if st_t == 1 and (k == "jump" or k == "djump") then pvy = (k == "djump") and 9 or 6 ploc.jumpCount = 1 end
    if k == "djump" and st_t == 25 then pvy = 9 ploc.jumpCount = 2 end
    local speed = (k == "stand" or k == "hold" or k == "come" or k == "shore") and 0 or ((k == "glide" or k == "djhere") and 0.15 or 0.09)
    if k == "djhere" and py <= terrain(px, pz) + 0.01 and pvy <= 0 and st_t > 5 then speed = 0 end
    local mx, mz = math.sin(yaw) * speed, math.cos(yaw) * speed
    px, pz = px + mx, pz + mz
    local ground = terrain(px, pz)
    local wl = water_level(px, pz)
    local swimming = wl and (k == "swim" or k == "dive" or k == "lake" or py < wl)
    if swimming then
      local depth = (k == "dive") and 3 or 1.3
      py = wl - depth
      pvy = 0
      ploc.currentWaterState = depth
      ploc.state = 9
      pcol.hasGroundCollision, pcol.groundDistance = false, 2
    else
      ploc.currentWaterState = 0
      if k == "glide" and st_t > 20 then
        ploc.state = 4
        py = math.max(ground + 5, py)
        pcol.hasGroundCollision, pcol.groundDistance = false, 5
      elseif py > ground + 0.01 or pvy > 0 then
        pvy = pvy - 25 / 60
        py = py + pvy / 60
        if py <= ground then py, pvy = ground, 0 end
        local inair = py > ground + 0.01
        ploc.state = inair and 2 or 0
        pcol.hasGroundCollision, pcol.groundDistance = not inair, inair and (py - ground) or 0
      else
        py, pvy = ground, 0
        ploc.state = 0
        ploc.jumpCount = 0
        pcol.hasGroundCollision, pcol.groundDistance = true, 0
      end
    end
    pv.x, pv.y, pv.z = mx * 60, pvy, mz * 60
    W:set_pos(PLAYER, px, py, pz)
    -- the hound (a stand-in for the game and the C++ hook)
    local a = W:get("DynamicEnemy01BehaviorState", HOUND)
    local hx, hy, hz = W:position(HOUND)
    local hv = W:get("Velocity", HOUND).velocity
    local hloc = W:get("DynamicLocomotion", HOUND)
    local hg = terrain(hx, hz)
    local hwl = water_level(hx, hz)
    if hwl and hy < hwl - 0.3 then
      hloc.currentWaterState = hwl - hy
      hloc.state = 9
      local wx, wz = hx + hv.x / 60, hz + hv.z / 60
      if terrain(wx, wz) < hy - 0.2 and not blocked and not (WALL and wz > 38.5 and false) then hx, hz = wx, wz end  -- a bank higher than him stops him
      hy = hy + hv.y / 60
      if hy < hg then hy = hg end
    elseif hy > hg + 0.05 or hv.y > 0.5 then
      hloc.currentWaterState = hwl and math.max(0, hwl - hy) or 0
      hloc.state = 2
      hv.y = hv.y - 25 / 60
      hx, hy, hz = hx + hv.x / 60, hy + hv.y / 60, hz + hv.z / 60
      if hy <= terrain(hx, hz) then hy = terrain(hx, hz) hv.x, hv.y, hv.z = 0, 0, 0 hloc.state = 0 end
    else
      hloc.currentWaterState = hwl and math.max(0, hwl - hy) or 0
      hloc.state = 0
      local tx, tz = a.movementTarget.x, a.movementTarget.z
      local dx, dz = tx - hx, tz - hz
      local d = math.sqrt(dx * dx + dz * dz)
      local home = math.sqrt((a.homeZonePosition.x - hx) ^ 2 + (a.homeZonePosition.z - hz) ^ 2)
      if a.movementTargetIsValid and not blocked and d > 0.05 and home > 2 then
        local stepd = math.min(d, 0.1)
        local nx2, nz2 = hx + dx / d * stepd, hz + dz / d * stepd
        local ng = terrain(nx2, nz2)
        local edge_ok = a.combatData.targetOfMyTarget or a.combatData.isTargetInsideLeash or ng >= hg - 2.5
        if ng - hg < 1.3 and edge_ok and not (WALL and nz2 > (type(WALL) == "number" and WALL or 38.5)) then hx, hz, hy = nx2, nz2, ng end
      end
    end
    W:set_pos(HOUND, hx, hy, hz)
    -- the drive
    local ok, err = pcall(F._drive_step, W, HOUND, h)
    if not ok then rec.log[#rec.log + 1] = "ERROR " .. tostring(err) end
    if h.go_away then  -- what F.tick does: put away, then back beside the player
      rec.log[#rec.log + 1] = "GO_AWAY " .. h.go_away
      h = { player = PLAYER, trail = {} }
      F._drives[HOUND] = h
      W:set_pos(HOUND, px + 0.3, py, pz)
    end
    if DUMP then for _, l in ipairs(rec.log) do if not l:find("waterlog") then print(tick, l) end end end
    if COV then for _, l in ipairs(rec.log) do
      local key = l:gsub("^npc probe: ", ""):gsub("%d+%.?%d*", "#"):sub(1, 60)
      COV[key] = (COV[key] or 0) + 1
    end end
    if not NOSNAP then snaps[tick] = ser({ comps = W.comps, h = h, log = rec.log, holds = F._holds }) end
  end
  return snaps, steps
end

if arg[5] == "dump" then
  DUMP = true
  run(OLD, SEED)
  os.exit(0)
end
if arg[5] == "lines" then
  NOSNAP = true
  local hit = {}
  debug.sethook(function(_, line)
    local info = debug.getinfo(2, "S")
    if info.source == "=" .. OLD then hit[line] = true end
  end, "l")
  for sd = 1, tonumber(arg[6]) or 40 do run(OLD, sd) end
  for sd = 1001, 1006 do run(OLD, sd) end
  debug.sethook()
  local f = io.open(OLD) local n = 0
  for ln in f:lines() do
    n = n + 1
    local lo, hi = tonumber(arg[7]), tonumber(arg[8])
    if n >= lo and n <= hi and not hit[n] then
      local code = ln:gsub("^%s+", "")
      if code ~= "" and not code:match("^%-%-") and code ~= "end" and code ~= "else" then print(n .. ": " .. ln) end
    end
  end
  os.exit(0)
end
if arg[5] == "cov" then
  COV = {}
  for sd = 1, tonumber(arg[6]) or 40 do run(OLD, sd) end
  local ks = {} for k in pairs(COV) do ks[#ks + 1] = k end table.sort(ks)
  for _, k in ipairs(ks) do print(string.format("%6d  %s", COV[k], k)) end
  os.exit(0)
end
local a = run(OLD, SEED)
local b = run(NEW, SEED)
local n = math.max(#a, #b)
for i = 1, n do
  if a[i] ~= b[i] then
    print(string.format("seed %d: FIRST DIFFERENCE at tick %d", SEED, i))
    local x, y = a[i] or "", b[i] or ""
    local j = 1
    while j <= #x and x:sub(j, j) == y:sub(j, j) do j = j + 1 end
    print("old: ..." .. x:sub(math.max(1, j - 300), j + 300))
    print("new: ..." .. y:sub(math.max(1, j - 300), j + 300))
    os.exit(1)
  end
end
print(string.format("seed %d: identical over %d ticks", SEED, n))
