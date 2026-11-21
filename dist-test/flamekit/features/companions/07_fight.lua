-- features/companions/07_fight.lua: part 7 of the companion code (the server side), split from npc_probe.lua in 0.15.362
-- (owner 2026-11-20 18:11). The parts run in order in ONE shared environment (features/companions.lua): what was a
-- top-level local is a name in that environment, seen by every part.
-- ===== Fight (owner 2026-11-18 20:09/20:11/20:47, 2026-11-19 09:03/09:17) =============================================
-- The fight modes (the wheel's Attack menu): Passive and Healing never attack (Healing's healing comes later);
-- Defensive and Aggressive run the attack sequence (drive_fight, below). Threats: monsters that hit him or his player
-- (the hit handler). Aggressive also looks at every monster within FIGHT_RANGE of the player (a scan over the world's
-- entities, spread over steps within SCAN_BUDGET: the world has some 37,000 entities and EMF pauses FlameKit when one
-- call runs over 250 ms). FIGHT_RANGE is also the radius he fights in (owner 2026-11-19 10:40 "the dog should stay
-- centered on me within my radius and kill anything in it"; it replaced the 30 m leash). fight_watch clears old threats and
-- logs his health and defence data. His maximum health: Health.dataStorage[3] (2026-11-18 20:28/20:34: [1] goes down
-- when he is hurt, [3] and [8] stay at the maximum).
FIGHT_RANGE = 20                -- (owner 2026-11-19 13:58: 20 m, was 15)
SCAN_BUDGET, SCAN_MAX = 0.03, 6000
threats = {}         -- companion entity -> { monster entity -> tick of its last hit }
mscan = nil          -- the scan under way: { list, i, found = { player -> { monster ids } }, steps, t }
near_monsters = {}   -- player entity -> { monster ids within FIGHT_RANGE } (the last finished scan)
scan_logged = -3600  -- the first scan is logged too
clock_ok = pcall(function() return os.clock() end)

function fight_mode(cid)
  local r = name_of[cid] and find(name_of[cid])
  return r and r.fight or "Passive"
end

-- a monster: the monster AI, not one of ours, a monster faction (not 7 Player, 8, 11 PlayerAlly), and health
-- (NetworkHealth; owner 2026-11-19 19:18 "#1 for sure": 171975, a part of a monster with no health and a constant
-- 20 m/s speed, held him for a minute while 171973 beside it hit him)
function is_monster(world, id)
  if name_of[id] then return false end
  local ok, st = pcall(world.get, world, "DynamicEnemy01BehaviorState", id)
  if not (ok and st) then return false end
  local okh, nh = pcall(world.get, world, "NetworkHealth", id)
  if not (okh and nh) then return false end
  local okf, f = pcall(world.get, world, "Faction", id)
  local fn = okf and f and tonumber(tostring(f.faction))
  return fn ~= nil and fn ~= 7 and fn ~= 8 and fn ~= 11
end

-- (21:18 logging, owner 21:17: "he was attacking mushrooms and things that were not monsters I think") what an entity
-- is, for the log: faction, its model (the template's ModelResource), and which parts it has: legs (DynamicLocomotion),
-- a route planner (DynamicPathWalker), health (NetworkHealth), Animal
function describe(world, id)
  local out = {}
  local okf, f = pcall(world.get, world, "Faction", id)
  out[#out + 1] = "faction " .. (okf and f and tostring(f.faction) or "-")
  local okm, model = pcall(function() return world:template("ModelResource", id).model end)
  if okm and model ~= nil then
    if type(model) == "table" then
      local parts = {}
      for k, v in pairs(model) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
      table.sort(parts)
      model = table.concat(parts, ",")
    end
    out[#out + 1] = "model " .. tostring(model)
  end
  local has = {}
  for _, c in ipairs({ "DynamicLocomotion", "DynamicPathWalker", "NetworkHealth", "Animal", "MovementCollider" }) do
    local ok, v = pcall(world.get, world, c, id)
    if ok and v ~= nil then has[#has + 1] = c end
  end
  out[#out + 1] = "has " .. (#has > 0 and table.concat(has, "+") or "none of the movers")
  return table.concat(out, ", ")
end

function monster_alive(world, id)
  if not world:position(id) then return false end
  local ok, hp = pcall(function() return world:get("NetworkHealth", id).health end)
  return ok and hp ~= nil and hp > 0  -- no health: not a monster (is_monster), so not alive either
end

-- (owner 21:20 "does the dog have any armor or defensive numbers, he seemed to die pretty quick", 21:21 "lets just do
-- more logging first") per companion: what he took and dealt, summed per 10 s while it goes on (fight_watch logs it)
fight_sums = {}  -- companion entity -> { took = {type -> amount}, hits_on = n, from = {attacker -> true}, dealt, hits_by }
function sum_of(cid)
  local f = fight_sums[cid]
  if not f then f = { took = {}, hits_on = 0, from = {}, dealt = 0, hits_by = 0 } fight_sums[cid] = f end
  return f
end

-- the hit handler: a monster's hit on a following companion or on his player is a threat for that companion
function note_threat(world, hit)
  local a, tg = hit.attacker, hit.target
  if not (a and tg) or a == tg then return end
  -- (21:21 logging) his hits taken and dealt, and hits on his player for comparison (the same monster's attack on the
  -- player, who has armor)
  for cid, h in pairs(drives) do
    local amount = tonumber(hit.amount) or 0
    local types = table.concat(hit.types or {}, ",")
    if tg == cid and a ~= cid then
      h.hit_t = world:tick()  -- (healing) the last hit on him
      local f = sum_of(cid)
      f.took[types] = (f.took[types] or 0) + amount
      f.hits_on, f.from[a] = f.hits_on + 1, true
    elseif a == cid then
      local f = sum_of(cid)
      f.dealt, f.hits_by = f.dealt + amount, f.hits_by + 1
    elseif tg == h.player and is_monster(world, a) then
      log(string.format("fight %s: the player took %s (%s, %s) from %s (health %s -> %s)", tostring(name_of[cid] or cid), tostring(hit.amount),
        types, table.concat(hit.attacks or {}, ","), tostring(a), tostring(hit.health_before), tostring(hit.health_after)))
    end
  end
  for cid, h in pairs(drives) do
    if (tg == cid or tg == h.player) and is_monster(world, a) then
      threats[cid] = threats[cid] or {}
      if not threats[cid][a] then
        log(string.format("fight %s: threat %s (it hit %s; %s)", tostring(name_of[cid] or cid), tostring(a), tg == cid and "him" or "his player",
          describe(world, a)))
      end
      threats[cid][a] = world:tick()
    end
  end
end

-- every step: the scan for monsters near the players of Aggressive companions, and of Defensive ones in an attack
-- sequence (they fight like Aggressive until it ends; owner 2026-11-19 10:25) (a new one every second)
function monster_scan_step(world)
  local players = {}
  for cid, h in pairs(drives) do
    local fm = fight_mode(cid)
    if fm == "Aggressive" or (fm == "Defensive" and h.atk and h.atk.wide) then
      local x, y, z = world:position(h.player)
      if x then players[h.player] = { x, y, z } end
    end
  end
  if next(players) == nil then mscan = nil near_monsters = {} return end
  if not mscan then
    if world:tick() % 60 ~= 0 then return end
    mscan = { list = world:entities(), i = 1, found = {}, steps = 0, t = world:tick() }  -- the list now, the walk next
    return
  end
  mscan.steps = mscan.steps + 1
  local t0, done = clock_ok and os.clock() or 0, 0
  local r2 = FIGHT_RANGE * FIGHT_RANGE
  while mscan.i <= #mscan.list do
    if done >= SCAN_MAX or (clock_ok and os.clock() - t0 > SCAN_BUDGET) then return end
    local id = mscan.list[mscan.i]
    mscan.i, done = mscan.i + 1, done + 1
    local ok, x, y, z = pcall(world.position, world, id)
    if ok and x then
      for p, pp in pairs(players) do
        if (x - pp[1]) ^ 2 + (y - pp[2]) ^ 2 + (z - pp[3]) ^ 2 <= r2 and is_monster(world, id) then
          mscan.found[p] = mscan.found[p] or {}
          table.insert(mscan.found[p], id)
        end
      end
    end
  end
  near_monsters = mscan.found
  if world:tick() - scan_logged > 3600 then  -- once a minute: what a scan costs
    scan_logged = world:tick()
    local n = 0
    for _, l in pairs(mscan.found) do n = n + #l end
    log(string.format("fight scan: %d entities in %d step(s), %d monster(s) within %d m of the players", #mscan.list,
      mscan.steps, n, FIGHT_RANGE))
  end
  mscan = nil
end

-- (the attack sequence) a companion's own hits, for drive_fight: on his target, or on something else (an object in
-- the way); drive_fight takes them every step
function note_my_hit(world, hit)
  local hh = drives[hit.attacker]
  if not hh then return end
  hh.my_hits = hh.my_hits or {}
  if #hh.my_hits < 20 then hh.my_hits[#hh.my_hits + 1] = { tg = hit.target, t = world:tick(), obj = not is_monster(world, hit.target) } end
end

-- once a second: old threats go (dead, gone, or more than FIGHT_RANGE from the player), and his health slots are logged
-- once per body and again the first time he is hurt ([1] his health, [3] his maximum). (The step 2 "would attack"
-- lines are gone: drive_fight's "attacks / bite / lunge / stops fighting" lines replace them.)
function fight_watch(world)
  for cid, h in pairs(drives) do
    local px, py, pz = world:position(h.player)
    local th = threats[cid]
    if px and th then
      for m in pairs(th) do
        local mx, my, mz = world:position(m)
        if not mx or not monster_alive(world, m) or (mx - px) ^ 2 + (my - py) ^ 2 + (mz - pz) ^ 2 > FIGHT_RANGE ^ 2 then th[m] = nil end
      end
    end
    local hp, hmax
    pcall(function() local d = world:get("Health", cid).dataStorage hp, hmax = tonumber(d[1]), tonumber(d[3]) end)
    local hurt_now = hp and hmax and hp < hmax
    if not h.health_dumped or (hurt_now and not h.health_dumped_hurt) then
      h.health_dumped = true
      if hurt_now then h.health_dumped_hurt = true end
      local parts = {}
      pcall(function()
        local d = world:get("Health", cid).dataStorage
        for i = 1, 8 do parts[#parts + 1] = string.format("[%d]=%s", i, tostring(d[i])) end
      end)
      log(string.format("fight %s: his Health.dataStorage %s%s (mode %s)", tostring(name_of[cid] or cid), table.concat(parts, " "),
        hurt_now and " (hurt)" or "", fight_mode(cid)))
    end
    -- (owner 2026-11-19 19:21 "does that dog have any mana? can he do heals?") which mana / healing parts his body has,
    -- once per body, and the player's for comparison
    if not h.heal_dumped then
      h.heal_dumped = true
      local function has(e)
        local out = {}
        for _, c in ipairs({ "Mana", "ManaRegeneration", "HealthRecharge", "HealingMod", "RecoverHealthSetup", "Stamina" }) do
          local ok, v = pcall(world.get, world, c, e)
          if ok and v then
            local extra = ""
            pcall(function()
              local d = v.dataStorage
              if d then extra = string.format(" [%s/%s]", tostring(d[1]), tostring(d[3])) end
            end)
            out[#out + 1] = c .. extra
          end
        end
        return #out > 0 and table.concat(out, ", ") or "none"
      end
      log(string.format("fight %s: mana/healing parts: his body: %s; the player's: %s", tostring(name_of[cid] or cid),
        has(cid), h.player and has(h.player) or "?"))
    end
    -- (21:21 logging) his defence data, once per body
    if not h.defence_dumped then
      h.defence_dumped = true
      local function arr(cname, n)
        local ok, v = pcall(function()
          local d = world:get(cname, cid).dataStorage
          local p = {}
          for i = 1, n do p[#p + 1] = string.format("%s", tostring(d[i])) end
          return table.concat(p, " ")
        end)
        return ok and v or "none"
      end
      local function has(cname) local ok, v = pcall(world.get, world, cname, cid) return ok and v ~= nil end
      log(string.format("fight %s: his defence: DamageSusceptibility [%s]; DamageMod [%s]; Armor %s; ArmorPoints %s; Level [%s]; health max %s",
        tostring(name_of[cid] or cid), arr("DamageSusceptibility", 19), arr("DamageMod", 4), has("Armor") and arr("Armor", 8) or "none",
        has("ArmorPoints") and arr("ArmorPoints", 8) or "none", arr("Level", 2), tostring(hmax)))
    end
    -- (21:21 logging) every 10 s with hits: what he took (per damage type, from how many monsters) and dealt
    local fs = fight_sums[cid]
    if fs and world:tick() % 600 < 60 and (fs.hits_on > 0 or fs.hits_by > 0) then
      local took, n_from = {}, 0
      for ty, amt in pairs(fs.took) do took[#took + 1] = string.format("%s %d", ty ~= "" and ty or "?", amt) end
      for _ in pairs(fs.from) do n_from = n_from + 1 end
      table.sort(took)
      log(string.format("fight %s: last 10 s: took %d hit(s) from %d monster(s) [%s]; dealt %d in %d hit(s); his health %s/%s",
        tostring(name_of[cid] or cid), fs.hits_on, n_from, table.concat(took, ", "), fs.dealt, fs.hits_by, tostring(hp), tostring(hmax)))
      fight_sums[cid] = nil
    end
  end
  for cid in pairs(threats) do if not drives[cid] then threats[cid] = nil end end
  for cid in pairs(fight_sums) do if not drives[cid] then fight_sums[cid] = nil end end
end

-- his current action's animation (Actor.currentServerAction.animationStateId: a number while a move plays, 0 idle)
function action_of(world, id)
  local ok, v = pcall(function() return tonumber(world:get("Actor", id).currentServerAction.animationStateId) end)
  return ok and v or nil
end

-- ===== The attack sequence (owner 2026-11-19 09:03 spec, 09:17 decisions; HANDOFF has both verbatim) ===================
-- Defensive and Aggressive only. Once he has a target, attack mode is on and the following (and coming back to the
-- player) stops until the sequence ends (drive_fight returns true).
-- Picking: the candidates, nearest to him first (Defensive: monsters that hit him or the player; Aggressive: those and
-- every monster within FIGHT_RANGE of the player; alive, within FIGHT_RANGE of the player, not skipped). For each one
-- the C++ shoots a ray from his shoulder to its middle (combatData.lastTargetId -> isTargetReachable, every step);
-- blocked (a fence, wall, tree or object) -> the next one; the first clear one is his target. While he checks he keeps
-- following the player (owner 2026-11-19 18:47 yes: monsters on another floor held him still 3 s every 20 s).
-- Fighting: locked on until it is dead. The ray every step; he faces it (the C++ turns him to lastTargetId), runs at it
-- (the native hook stops him 2 m off), lunges from FIGHT_LUNGE and bites from FIGHT_BITE as often as his moves allow
-- (the next one when his move's animation is over, at most ATTACK_MAX). He can't deliver attacks (owner 10:43 yes):
-- the ray is blocked, or his attack hit something else and not it, or no hit on it and no 0.3 m closer for NO_HIT
-- (owner 2026-11-19 10:38: at 4.0 m from a monster, lunges into plants under the ray's line; then the edge stop held
-- him and he stood) -> he repositions, one step at a time, MOVE_STEP each, then tries again from there: a hop toward
-- it, SIDE m to the left, SIDE m to the right; can't again after those three -> he drops it (not picked again for
-- SKIP_TICKS) and picks again. A hit on it starts the steps over.
-- Its radius (owner 10:40): a target more than FIGHT_RANGE from the player is dropped (the next one is picked).
-- The end: nothing reachable on PICK_TRIES tries PICK_EVERY apart (that includes "all dead"), or he is more than
-- FIGHT_RANGE + FIGHT_BITE from the player (outside the radius). (09:17: the "run back when badly hurt" rule is gone.) Passive (or Put away) from the menu ends it at once (the top of drive_fight, every tick) and he
-- follows again. Defensive starts it only on a threat, then fights like Aggressive until it ends (owner 10:25).
-- Logs "fight <name>: ...".
FIGHT_BITE, FIGHT_LUNGE, ATTACK_MAX = 2.5, 4, 180
RAY_WAIT = 2                    -- ticks before a candidate's ray result is read (the C++ casts every step)
PICK_TRIES, PICK_EVERY = 3, 60  -- (owner 09:17 "3 tries ... might be too few, but we'll start there")
MOVE_STEP, SIDE = 60, 2
NO_HIT = 120                    -- (owner 2026-11-18 21:35 "I'd drop that to like 2 seconds")
-- (owner 2026-11-19 11:17 "get the facing fix in asap") between attacks he turns toward it, TURN radians a tick at
-- most (half a turn in 0.1 s), and attacks only when he faces it within FACE_OK degrees
TURN, FACE_OK = math.rad(30), 15
-- (owner 2026-11-19 14:52 yes; bats at up to 6 m/s moved 2.0-2.4 m in the 0.4 s before a lunge's hit lands) a target
-- faster than FAST m/s that is out of bite reach: he stands at lunge reach facing it and lunges when it slows down
-- (a bat slows when it swoops in); while he waits, no "can't deliver attacks"
FAST = 3
-- (owner 2026-11-19 16:32 "yeah lets see how that goes"; floating monsters 0.7-0.8 m above him: bites and lunges
-- went under them) a target HIGH m or more above him: he jumps into the attack (upward speed only, the attack's own
-- forward move is kept), as soon as the attack has started
HIGH = 0.5

function speed_of(world, m)
  local v = 0
  pcall(function() local w = world:get("Velocity", m).velocity v = math.sqrt(w.x * w.x + w.y * w.y + w.z * w.z) end)
  return v
end

-- he turns toward (fx, fz) by TURN at most this tick; returns how many degrees he is still off afterwards
function turn_toward(world, id, fx, fz)
  local q = world:get("CurrentTransform", id).transform.orientation
  local yaw = math.atan(2 * (q.x * q.z + q.w * q.y), 1 - 2 * (q.x * q.x + q.y * q.y))
  local diff = (math.atan(fx, fz) - yaw + math.pi) % (2 * math.pi) - math.pi
  local step = math.max(-TURN, math.min(TURN, diff))
  if math.abs(diff) > 0.01 then face(world, id, yaw + step) end
  return math.deg(diff - step)
end
SKIP_TICKS = 600  -- (owner 17:31 "drop it down to like 10 seconds?": 10 s, was 20)
-- (owner 17:29 "it took the companion dog a bit to respond to that crab that just attacked"; 17:31 "yeah make that
-- change") 17:28:21-24 the crab, 20.6 m off and 4.8 m below, was blocked 3 times and skipped for 20 s; it came up to
-- the player meanwhile and was attacked only at 17:28:44. A skipped monster within F.SKIP_NEAR of the player is a
-- candidate again at once (a hit on him or the player already did that)
F.SKIP_NEAR = 6

function fight_candidates(world, cid, h, mode, px, py, pz, nx, ny, nz)
  local list, seen = {}, {}
  local skip = h.fight_skip or {}
  local now = world:tick()
  for m, untill in pairs(skip) do
    local hit_t = threats[cid] and threats[cid][m]
    local mx, _, mz = world:position(m)
    if now > untill then skip[m] = nil
    elseif mx and (mx - px) ^ 2 + (mz - pz) ^ 2 <= F.SKIP_NEAR * F.SKIP_NEAR then
      skip[m] = nil
      log(string.format("fight %s: %s is no longer skipped: it is within %d m of the player", tostring(name_of[cid] or cid), tostring(m), F.SKIP_NEAR))
    elseif hit_t and hit_t > untill - SKIP_TICKS then
      -- (owner 11:17 yes) it hit him or the player again after he gave up on it: it is a candidate again at once
      skip[m] = nil
      log(string.format("fight %s: %s is no longer skipped: it hit %s again", tostring(name_of[cid] or cid), tostring(m), "him or the player"))
    end
  end
  local function add(m, why)
    if seen[m] or skip[m] then return end
    local mx, my, mz = world:position(m)
    if not (mx and monster_alive(world, m)) then return end
    if (mx - px) ^ 2 + (my - py) ^ 2 + (mz - pz) ^ 2 > FIGHT_RANGE ^ 2 then return end
    seen[m] = true
    list[#list + 1] = { id = m, why = why, d = math.sqrt((mx - nx) ^ 2 + (my - ny) ^ 2 + (mz - nz) ^ 2) }
  end
  for m in pairs(threats[cid] or {}) do add(m, "it hit you or him") end
  if mode == "Aggressive" then
    for _, m in ipairs(near_monsters[h.player] or {}) do
      local mx, my, mz = world:position(m)
      if mx and (mx - px) ^ 2 + (my - py) ^ 2 + (mz - pz) ^ 2 <= FIGHT_RANGE ^ 2 then add(m, "within " .. FIGHT_RANGE .. " m of you") end
    end
  end
  table.sort(list, function(x, y) return x.d < y.d end)
  return list
end

-- (logging, owner 2026-11-19 10:38 "its not facing the target") his facing against the line to the monster, and where the
-- monster is and how fast it moves: "faces it (x deg off; it at ..., moving v m/s, n m above/below him)"
function face_info(world, id, tg, nx, ny, nz, mx, my, mz)
  local off = "?"
  pcall(function()
    local q = world:get("CurrentTransform", id).transform.orientation
    local yaw = math.atan(2 * (q.x * q.z + q.w * q.y), 1 - 2 * (q.x * q.x + q.y * q.y))  -- (Lua 5.4: no math.atan2)
    local want = math.atan(mx - nx, mz - nz)
    local dd = math.deg(want - yaw) % 360
    if dd > 180 then dd = dd - 360 end
    off = string.format("%.0f", dd)
  end)
  local v = speed_of(world, tg)
  return string.format("he faces %s deg off it; it at %.1f %.1f %.1f moving %.1f m/s, %.1f m %s him; him at %.1f %.1f %.1f", off,
    mx, my, mz, v, math.abs(my - ny), my >= ny and "above" or "below", nx, ny, nz)
end
