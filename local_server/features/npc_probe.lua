-- npc_probe.lua: FlameKit's companions, on the owner's local test server only (never published; the repository keeps
-- the live copy in local_server/). No game AI anywhere: the companion's own AI and route planner are always off.
--   - the roster: FlameKit's own list of companions in the world's data (survives restarts), a main companion per
--     player, controllers and admins;
--   - following = the drive (FlameKit's breadcrumb trail of the player; the C++ server probe writes his movement input),
--     with swimming and diving, jump follow, drops, stuck notices, and put away / back beside the player (glider, fast
--     travel, can't follow);
--   - staying: no target, he stands still;
--   - E opens the wheel (Follow me / Stay here / Attack / Put away; Attack: the fight modes Passive, Defensive,
--     Aggressive, Healing) in the player's game; "Call my companion" (P, Experimental
--     panel) respawns his main companion beside him;
--   - the minimap's companion dots, the full recorder (fullrec), and console tools for tests.
-- Console (or emf\commands.txt on the server): flamekit.npc roster ... | drive <npc> <player> | drive <npc> stop |
--   fullrec <entity> [s] | look <entity> | near <x> <y> <z> [r] | remove <entity> | and the test commands in F.setup
-- Logs "npc probe: ..." in emf\emf_core.log.

local F = { id = "npc_probe", title = "NPC Probe" }
local function log(s) emf.log("npc probe: " .. s) end
local function say(world, player, text, colour)
  pcall(function() require("features.chat").notice_to(world, player, text, colour or "#8cd2ff", 5) end)
end

-- a notice in the player's Notices window that stays until it is taken back (clear = true): the stuck and death
-- notices stay on the screen until the condition is over (client: npc_wheel_probe.lua)
local function status(world, player, tag, text, colour)
  if not player then return end
  local msg = text and { op = "status", tag = tag, text = text, colour = colour } or { op = "status", tag = tag, clear = true }
  pcall(emf.net.send_to, world, player, "npcwheel", emf.json.encode(msg))
end

-- ===== The full recorder (logging all of an entity's data) ===========================================================
-- Every component an entity has (found once by trying every component name), every plain field of each (the generated
-- list in npc_fields.lua), every half second, into its own file beside the mod (fullrec_<entity>.txt): a full snapshot
-- first, then only the fields that changed, each line with the tick and the clock. FlameKit's own writes and decisions
-- go into the same file as EVENT lines (fullrec_event), so cause and effect line up.
local FIELDS = (function() local ok, f = pcall(require, "features.npc_fields") return ok and f or {} end)()
local fullrecs = {}  -- entity -> { file, untill, next, comps = {names}, last = {}, n }
local function fr_val(v)
  if type(v) == "number" then
    if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format("%d", v) end
    return string.format("%.4f", v)
  end
  return tostring(v)
end
local function fr_read(c, path)
  local arr = path:sub(-1) == "#"
  if arr then path = path:sub(1, -2) end
  local v = c
  for seg in path:gmatch("[^.]+") do v = v[seg] end
  if arr then
    local parts = { "#" .. tostring(#v) }
    for i = 1, math.min(#v, 8) do parts[#parts + 1] = fr_val(type(v[i]) == "table" and "{}" or v[i]) end
    return table.concat(parts, " ")
  end
  return fr_val(v)
end
local function fr_write(r, text)
  if not r.file then return end
  r.file:write(text, "\n")
end
local function fr_stamp(world) return string.format("t=%d %s", world:tick(), os.date and os.date("%H:%M:%S") or "") end
local function fullrec_event(world, id, text)  -- called from every part of the probe below
  local r = fullrecs[id]
  if r then fr_write(r, fr_stamp(world) .. " EVENT " .. text) end
end
local function fullrec_start(world, id, secs)
  if fullrecs[id] and fullrecs[id].file then pcall(function() fullrecs[id].file:close() end) end
  local f = io.open(emf.dir .. "\\fullrec_" .. tostring(id) .. "_" .. (os.date and os.date("%H%M%S") or tostring(world:tick())) .. ".txt", "w")  -- one file per recording
  local comps = {}
  for name in pairs(FIELDS) do
    local ok, c = pcall(world.get, world, name, id)
    if ok and c then comps[#comps + 1] = name end
  end
  table.sort(comps)
  local r = { file = f, untill = world:tick() + secs * 60, next = 0, comps = comps, last = {}, n = 0 }
  fullrecs[id] = r
  fr_write(r, string.format("%s START entity %s, %d components: %s", fr_stamp(world), tostring(id), #comps, table.concat(comps, ", ")))
  log(string.format("fullrec %s: %d components, to a new fullrec_%s_<time>.txt for %d s", tostring(id), #comps, tostring(id), secs))
end
local function fullrec_step(world, id, r)
  local out, changed = {}, 0
  for _, name in ipairs(r.comps) do
    local ok, c = pcall(world.get, world, name, id)
    if ok and c then
      for _, path in ipairs(FIELDS[name]) do
        local okv, v = pcall(fr_read, c, path)
        local key = name .. "." .. path
        v = okv and v or "?"
        if r.last[key] ~= v then
          r.last[key] = v
          out[#out + 1] = key .. "=" .. v
          changed = changed + 1
        end
      end
    elseif r.last[name] ~= "gone" then
      r.last[name] = "gone"
      out[#out + 1] = name .. " GONE"
    end
  end
  r.n = r.n + 1
  if #out > 0 then fr_write(r, fr_stamp(world) .. " " .. table.concat(out, " | ")) end
  if r.n % 20 == 0 then pcall(function() r.file:flush() end) end
end


-- ===== The drive's numbers =============================================================================================
-- Swimming: his body is held FLOAT_LIFT above the player's height while diving, tilted nose up FLOAT_PITCH degrees.
local FLOAT_LIFT = 0.45  -- metres
local FLOAT_PITCH = 28  -- degrees, nose up
local SWIM_OUT_STOP = 0.8  -- in the water with the player on land, he only stops this close (he has not arrived while he swims)
-- Jumps (drive_copy, drive_jump_follow): he jumps where the player jumped (the next crumb is a landing) and up every
-- step of STEP_UP or more the player went up; the launch aims DJ_MARGIN over the crumb, a flight lasts at most DJ_TICKS,
-- the launch speed is written for up to DJ_LIFT ticks until the game counts him in the air, and after a jump up he
-- stands still DJ_SETTLE ticks.
local STEP_UP = 0.6  -- (the old ray step jump's threshold; smaller steps his own legs take)
local DJ_MARGIN, DJ_TICKS = 0.7, 150
local DJ_SETTLE = 45
local DJ_LIFT = 40
-- Put away and back (drive_put_away, F.tick): the glider is the player's locomotion state GLIDE_STATE; still gliding
-- after GLIDE_WAIT ticks or GLIDE_FAR metres away, he is put away. The player moving more than FAR_JUMP in one tick
-- (a fast travel) puts him away too, and so does TP_AFTER ticks of not being able to follow. He comes back beside the
-- player once the player has stood on the ground LAND_TICKS (and his game has loaded).
-- (owner 2026-11-19 22:22 "get rid of the 2 seconds, show the error, but teleport him immediately") TP_AFTER 0: put
-- away the moment he cannot follow; the notice then shows 5 s on its own (put_away_for)
local GLIDE_STATE, GLIDE_WAIT, GLIDE_FAR, LAND_TICKS, TP_AFTER, FAR_JUMP = 4, 240, 30, 60, 0, 50
local WATER_NEAR = 2  -- metres above the swimming player's water surface that still count as "at the water"
local DIVE_PLAYER = 1.8  -- the player's depth from which he dives with him (at the surface the player reads about 1.3)
local SWIM_ENTER, SWIM_DEPTH = 0.5, 0.9  -- he swims while his own depth is over 0.5 m, and is held at about 0.9 m
local SWIM_MAX, SWIM_GAIN = 6, 1.2  -- swimming speed: 1 m/s past the stop distance, +1.2 m/s per metre, at most 6
local HOP_TICKS, HOP_HOLD, HOP_EVERY, HOP_MARGIN, HOP_FORWARD = 90, 40, 120, 0.7, 3  -- the climb-out hop, see drive_water
-- ===== Following: the drive ============================================================================================
-- No game AI: his AI (DynamicEnemy01BehaviorState.enabled) and his route planner are off. FlameKit keeps the player's
-- breadcrumb trail and writes the next crumb ahead of the hound into his AI data's movementTarget and the player's spot
-- into homeZonePosition. The C++ server probe (fk_server_probe, after the game's steering step) turns that into his
-- movement input (direction, look, walk/run/sprint by distance, nothing within DRIVE_STOP of the player), with an edge
-- stop of its own; the game's locomotion moves and animates him. combatData.targetOfMyTarget = true turns the native
-- edge stop off; combatData.isTargetInsideLeash = true lets it allow drops up to 7.5 m. No route search and no game
-- follow orders.
-- (owner 2026-11-18 18:04-18:35, local_server/FOLLOW_PLAN.md) THE TRAIL IS THE TRUTH: he goes where the player went,
-- the way the player went (the crumbs' meta data says how). On the trail there is no edge stop (where the player
-- walked there was ground) and no ray step jump; ups come from the crumbs. Whatever he cannot copy, or no progress for
-- STUCK_TICKS: "can't follow", and after TP_AFTER he is respawned beside the player.
local drives = {}  -- entity -> his record h: { player, trail = {}, ... }
-- a hold (console "hold", for tests): he stays where he stands and turns toward a target until the time is up
local holds = {}  -- entity -> { target, untill (tick) }
local DRIVE_STOP, DRIVE_STEP = 2, 0.25  -- he stops within 2 m of the player (the C++ kFollowStop matches); a crumb every 0.25 m
local CRUMB_REACH = 0.3  -- a crumb within this is reached; he aims at the first one further away
-- Drops and flights: no crumbs while the player is off the ground. A crumb more than DROP_HEIGHT below the one before
-- (just below his own fall damage: from 8 m, lethal at 16 m), or the first one after more than DROP_AIR_TICKS in the
-- air (a glide, not a jump), is a break (brk): a way he cannot copy. Smaller drops he follows: he walks off as the
-- player did.
local DROP_HEIGHT = 7.5
local DROP_AIR_TICKS = 120
-- the "can't follow" notice says why ("stuck" itself is only for a real clipping problem)
local STUCK_TEXT = {
  down = "Companion is afraid to follow (too steep)!",
  drop = "Companion is afraid to follow (drop too high)!",
  up = "Companion can't get up there!",
  blocked = "Companion can't follow you!",
}
local STUCK_TICKS = 180  -- 3 s without 0.3 m of progress toward his crumb: he cannot follow
local CRUMB_LOG = true  -- every crumb of every companion into the server log
-- the player is off the ground unless he has ground contact, under 0.1 m from it, and locomotion state 0 (the game keeps
-- "ground contact" for the first and last part of a jump)
local function player_airborne(world, player)
  local ok, air = pcall(function()
    local r = world:get("MovementCollider", player).results
    local st = tonumber(world:get("DynamicLocomotion", player).state)
    local gd = tonumber(r.m_value.groundDistance) or 1e9
    return not (r.m_isSet and r.m_value.hasGroundCollision and gd < 0.1 and st == 0)
  end)
  return ok and air
end
-- Who stands in his way when he gives up: every body within BLOCK_R of him (not himself, not his player), its kind from
-- its components (Animal; ActiveNpcState = a villager; a player; DynamicEnemy01BehaviorState = a monster or a
-- companion), how far, and whether it is in front of him (toward fx, fz); also his collider's "touching a character"
-- flags. Returns the kind of the nearest one in front ("animal", "npc", "player", "monster") or nil, and a log line.
local BLOCK_R = 2.5
local function blockers(world, id, player, nx, ny, nz, fx, fz)
  local fl = math.sqrt(fx * fx + fz * fz)
  if fl > 0.001 then fx, fz = fx / fl, fz / fl end
  local found, best, bestd = {}, nil, math.huge
  local okall = pcall(function()
    for _, e in ipairs(world:entities()) do
      if e ~= id and e ~= player then
        local x, y, z = world:position(e)
        if x and math.abs(x - nx) < BLOCK_R and math.abs(z - nz) < BLOCK_R and math.abs(y - ny) < 2 then
          local d = math.sqrt((x - nx) ^ 2 + (z - nz) ^ 2)
          if d < BLOCK_R then
            local kind
            local function has(c) local ok, v = pcall(world.get, world, c, e) return ok and v ~= nil end
            if has("Animal") then kind = "animal"
            elseif has("ActiveNpcState") then kind = "npc"
            elseif (function() local oka, acc = pcall(world.account, world, e) return oka and acc end)() then kind = "player"
            elseif has("DynamicEnemy01BehaviorState") then kind = "monster" end
            if kind then
              local front = ((x - nx) * fx + (z - nz) * fz) > 0
              local okf, f = pcall(world.get, world, "Faction", e)
              found[#found + 1] = string.format("%s %s %.1f m%s faction %s", kind, tostring(e), d, front and " in front," or " behind,",
                okf and f and tostring(f.faction) or "-")
              if front and d < bestd then best, bestd = kind, d end
            end
          end
        end
      end
    end
  end)
  local col = ""
  pcall(function()
    local r = world:get("MovementCollider", id).results.m_value
    col = string.format("; his collider: touching a character %s, a player %s", tostring(r.hasSpheroidCollision),
      tostring(r.hasPlayerSpheroidCollision))
  end)
  return best, (#found > 0 and table.concat(found, "; ") or (okall and "nobody within " .. BLOCK_R .. " m" or "scan failed")) .. col
end


-- ===== The drive, in parts =============================================================================================
-- drive_step runs once per tick for each following companion. drive_read puts the tick's facts into one table (s), then
-- the parts run in order; a part that returns true has decided this tick (he swims, is put away, jumps, holds or
-- cannot follow) and the rest is skipped. The parts share only s and his record h (kept between ticks).

-- the fight (defined with the fight code further down; returns true while he fights)
local drive_fight
local drive_heal
-- (inventory, see "Inventory" below) inv.open: companion name -> his open chest (he is frozen while it exists); the
-- functions and settings live in this one table (the file is at Lua's 200 locals)
local inv = { open = {} }

-- his body upright and turned toward yaw (radians, 0 = +z)
local function face(world, id, yaw)
  local o = world:get("CurrentTransform", id).transform.orientation
  o.x, o.y, o.z, o.w = 0, math.sin(yaw / 2), 0, math.cos(yaw / 2)
end

-- (owner 2026-11-19 16:37, list #8: his pace from the crumb meta data) the pace for the C++ drive, in
-- combatData.prowlAngle (his game AI is off, so nothing else writes it): 2 walk, 3 run, 4 sprint (LocomotionSpeedSelector).
-- The player's crumb speeds (6700 crumbs, 2026-11-19): ~2-3 m/s walking, ~4-5 running, ~8-9 sprinting.
local PACE_WALK, PACE_RUN, PACE_SPRINT = 2, 3, 4
local PACE_RUN_AT, PACE_SPRINT_AT = 3.5, 7
local function set_pace(a, pace)
  pcall(function() a.combatData.prowlAngle = pace end)
end

-- the native hook's target and its "player" spot both at x, y, z: he stands there
local function hold_at(a, x, y, z)
  a.homeZonePosition.x, a.homeZonePosition.y, a.homeZonePosition.z = x, y, z
  a.movementTarget.x, a.movementTarget.y, a.movementTarget.z = x, y, z
  a.movementTargetIsValid = true
end

-- his health for the logs (-1 when it cannot be read)
local function health(world, id)
  local hp = -1
  pcall(function() hp = world:get("Health", id).dataStorage[1] end)
  return hp
end

-- the native edge stop off for this tick
local function edge_off(a)
  pcall(function() a.combatData.targetOfMyTarget = true end)
end

-- a jump-follow launch: the speeds that carry him d metres across and rise metres up (gravity 25; up at most 16 m/s
-- for rise + DJ_MARGIN, across at most 10 m/s so that he comes down at the spot)
local function launch_speeds(d, rise)
  local vup = math.min(16, math.sqrt(2 * 25 * math.max(0.5, rise + DJ_MARGIN)))
  local disc = math.max(0, vup * vup - 2 * 25 * rise)
  local tdown = (vup + math.sqrt(disc)) / 25
  local vh = math.min(10, d / math.max(0.2, tdown))
  return vup, vh
end

-- the launch itself: lifted 0.3 m first (a speed written on the ground does not take), then his speed up and across
-- toward ddx, ddz, turned that way. Returns whether the speed could be set, and the speed across (x, z).
local function launch(world, id, ddx, ddz, d, vup, vh)
  local vx, vz = d > 0.05 and ddx / d * vh or 0, d > 0.05 and ddz / d * vh or 0
  local ok = pcall(function()
    local tr = world:get("CurrentTransform", id).transform
    tr.position.y = tr.position.y + math.floor(0.3 * 2 ^ 32)
    local v = world:get("Velocity", id).velocity
    v.x, v.y, v.z = vx, vup, vz
  end)
  if d > 0.05 then pcall(face, world, id, math.atan(ddx, ddz)) end
  return ok, vx, vz
end

-- when he gives up: who stands in his way, into the log (h.blocked_by keeps the kind)
local function report_blockers(s, what, dx, dz)
  local bk, bline = blockers(s.world, s.id, s.h.player, s.nx, s.ny, s.nz, dx, dz)
  s.h.blocked_by = bk
  log(string.format("%s: %s in his way: %s", what, tostring(s.id), bline))
end

-- he cannot follow (why: a STUCK_TEXT key): the notice once, he stands (drive_stuck), and drive_put_away respawns him
-- beside the player after TP_AFTER. h.cant is the one "cannot follow" state, on land and in the water.
local function cant_follow(s, why, detail)
  local h = s.h
  if h.cant then return end
  h.cant = why
  log(string.format("can't follow: %s %s: %s (at %.1f %.1f %.1f, player %.1f m away, %.1f m %s)", tostring(s.id), why, detail,
    s.nx, s.ny, s.nz, math.sqrt((s.px - s.nx) ^ 2 + (s.pz - s.nz) ^ 2), math.abs(s.py - s.ny), s.py >= s.ny and "higher" or "lower"))
  fullrec_event(s.world, s.id, "drive: can't follow (" .. why .. ")")
  status(s.world, h.player, "companion_stuck", STUCK_TEXT[why] or STUCK_TEXT.blocked, "#ff9050")
end

-- the "cannot follow" state is over (he moves again, or something else takes over)
local function cant_over(s, why)
  local h = s.h
  if not h.cant then return end
  h.cant, h.cant_since = nil, nil
  log(string.format("can't follow: %s over: %s", tostring(s.id), why))
  status(s.world, h.player, "companion_stuck", nil)
end

-- the tick's facts: where the player and the hound are, his AI kept off, and the water both read (currentWaterState
-- is the depth below the surface); nil when either body is gone
local function drive_read(world, id, h)
  local px, py, pz = world:position(h.player)
  local nx, ny, nz = world:position(id)
  if not (px and nx) then drives[id] = nil log("drive " .. tostring(id) .. ": gone, stopped") return nil end
  local t = world:tick()
  local a = world:get("DynamicEnemy01BehaviorState", id)
  local pet = false
  if not a then
    -- (2026-11-20 12:49, owner: pets "should just use what we made already") a pet (an animal: no monster AI): the
    -- drive works on a table with the same fields (h.shim); roster.pet_flush hands it to the server probe each tick
    if not world:get("DynamicWildlife", id) then error("neither a monster nor an animal") end
    h.shim = h.shim or { movementTarget = { x = nx, y = ny, z = nz }, homeZonePosition = { x = px, y = py, z = pz },
      movementTargetIsValid = false, enabled = false, disabledFeatures = 0,
      combatData = { prowlAngle = 2, targetOfMyTarget = false, isTargetInsideLeash = false, lastTargetId = 0, selectedAttackIndex = 255 } }
    a, pet = h.shim, true
  end
  if a.enabled ~= false then a.enabled = false fullrec_event(world, id, "drive: his AI switched off") end
  local okw, pw = pcall(function() return tonumber(world:get("DynamicLocomotion", h.player).currentWaterState) end)
  -- the player swims (pwet) when his depth is over 0.5; the hound swims (swim) on his OWN depth
  local pwater = (okw and tonumber(pw)) or 0
  local pwet = pwater > 0.5
  local okh, hw = pcall(function() return tonumber(world:get("DynamicLocomotion", id).currentWaterState) end)
  hw = okh and hw or 0
  local swim = hw > SWIM_ENTER
  return { world = world, id = id, h = h, a = a, t = t, px = px, py = py, pz = pz, nx = nx, ny = ny, nz = nz,
           pwater = pwater, pwet = pwet, hw = hw, swim = swim, pet = pet }
end

-- the water log (measuring only): once a second while the player or the hound reads any water, and 5 s after; both
-- water readings, his submerge depth, heights, ground, locomotion state, speed and its direction, the input the drive
-- gave him, his facing, the way to the player (compass angles, 0 = +z), his air and health, the player's air
local function drive_waterlog(s)
  local world, id, h, t = s.world, s.id, s.h, s.t
  local px, py, pz, nx, ny, nz = s.px, s.py, s.pz, s.nx, s.ny, s.nz
  if t % 60 == 0 then
    local function rd(f) local ok, v = pcall(f) if ok then return v end return "err" end
    local hw = rd(function() return world:get("DynamicLocomotion", id).currentWaterState end)
    local pwr = rd(function() return world:get("DynamicLocomotion", h.player).currentWaterState end)
    local wet = (tonumber(hw) or 0) > 0 or (tonumber(pwr) or 0) > 0
    if wet then h.waterlog_until = t + 300 end
    if wet or (h.waterlog_until and t <= h.waterlog_until) then
      local sub = rd(function() return world:get("ServerSubmerge", id).submergeDepth end)
      local chk = rd(function() return world:get("IsInWaterCheck", id).waterSubmersionHeight end)
      local gr = rd(function()
        local r = world:get("MovementCollider", id).results
        return string.format("set=%s ground=%s dist=%.2f", tostring(r.m_isSet), tostring(r.m_value.hasGroundCollision),
          tonumber(r.m_value.groundDistance) or -1)
      end)
      local st = rd(function() return world:get("DynamicLocomotion", id).state end)
      local function ang(x, z) return (math.deg(math.atan(x, z)) + 360) % 360 end
      local mv = rd(function()
        local v = world:get("Velocity", id).velocity
        local vx, vy, vz = tonumber(v.x) or 0, tonumber(v.y) or 0, tonumber(v.z) or 0
        return string.format("vel %.1f m/s at %.0f, up %.1f", math.sqrt(vx * vx + vz * vz), ang(vx, vz), vy)
      end)
      local inp = rd(function()
        local m = world:get("ActorInput", id).desiredWorldMoveInput
        local mx, mz = tonumber(m.x) or 0, tonumber(m.z) or 0
        if mx * mx + mz * mz < 1e-6 then return "input none" end
        return string.format("input %.0f", ang(mx, mz))
      end)
      local face = rd(function()
        local o = world:get("CurrentTransform", id).transform.orientation
        local fx = 2 * (o.x * o.z + o.w * o.y)
        local fz = 1 - 2 * (o.x * o.x + o.y * o.y)
        return string.format("faces %.0f", ang(fx, fz))
      end)
      local air = rd(function() local o = world:get("Oxygen", id).dataStorage return string.format("air %s/%s", tostring(o[1]), tostring(o[2])) end)
      local hpv = rd(function() return world:get("Health", id).dataStorage[1] end)
      local pair = rd(function()
        local o = world:get("Oxygen", h.player).dataStorage
        local acc = "?"
        pcall(function() acc = string.format("%.2f", world:get("DynamicOxygenState", h.player).accumulatedValue) end)
        return string.format("player air %s %s %s %s %s %s (acc %s)", tostring(o[1]), tostring(o[2]), tostring(o[3]), tostring(o[4]),
          tostring(o[5]), tostring(o[6]), acc)
      end)
      hpv = tostring(hpv) .. " | " .. tostring(pair)
      log(string.format("waterlog %s: %s, health %s | hound water=%s (%s) submerge=%s check=%s y=%.2f %s loco=%s | %s, %s, %s, player at %.0f | player water=%s y=%.2f | %.1f m apart%s",
        tostring(id), tostring(air), tostring(hpv), tostring(hw), type(hw), tostring(sub), tostring(chk), ny, tostring(gr), tostring(st),
        tostring(mv), tostring(inp), tostring(face), ang(px - nx, pz - nz), tostring(pwr), py,
        math.sqrt((px - nx) ^ 2 + (pz - nz) ^ 2), h.water and " [water mode]" or ""))
    end
  end
end

-- Water. The leap rule: when the player came down into the water from the air (h.leap, drive_track_player), the edge
-- stop is off until the hound is in the water himself; he follows the trail to its end and then straight to the
-- player. Over when the player leaves the water.
-- While HE swims (returns true): his target is the player; FlameKit sets what the game does not do for a
-- non-swimmer: his height (held at SWIM_DEPTH below the surface, or at the player's height + FLOAT_LIFT while the
-- player dives), his speed (the game keeps an in-air speed frozen, so it is written every tick: toward the player,
-- nothing within the stop distance, SWIM_GAIN per metre, at most SWIM_MAX), and his tilt (nose up FLOAT_PITCH, facing
-- where he swims; the yaw is kept in h.swim_yaw because reading it back from a tilted body goes wrong). No progress
-- while swimming: the climb-out hop, and after STUCK_TICKS "can't follow" (over again when he moves on).
-- Out of the water: upright again and a fresh trail.
local function drive_water(s)
  local world, id, h, a, t = s.world, s.id, s.h, s.a, s.t
  local px, py, pz, nx, ny, nz = s.px, s.py, s.pz, s.nx, s.ny, s.nz
  local pwater, pwet = s.pwater, s.pwet
  local hw, swim = s.hw, s.swim
  if h.leap and not pwet then
    log("leap " .. tostring(id) .. ": the player left the water, edge stop on again")
    h.leap = nil
  end
  pcall(function() a.combatData.targetOfMyTarget = swim or (h.leap ~= nil) end)  -- edge stop off while he swims or leaps
  if swim then
    if not h.water then
      h.water = true
      h.to_swimmer = nil
      if h.leap then
        local hp = health(world, id)
        log(string.format("leap %s: followed the player into the water (health %s, was %s)", tostring(id), tostring(hp), tostring(h.leap.hp)))
        h.leap = nil
      end
      -- in the water he swims to the player: a "can't follow" from land is over
      h.prog = nil
      cant_over(s, "he is in the water")
      fullrec_event(world, id, "drive: in the water himself (" .. tostring(hw) .. "): swimming")
      log(string.format("drive %s: in the water himself (depth %.2f), swimming", tostring(id), hw))
    end
    hold_at(a, px, py, pz)
    local tr = world:get("CurrentTransform", id).transform
    local S = 2 ^ 32
    -- the height: a quarter of the difference each tick, at most 0.08 m, never pushed down while he touches the bottom
    -- (wading), and no hold during a climb-out hop
    local hopping = h.hop_until and t < h.hop_until
    local diving = pwet and pwater > DIVE_PLAYER
    if diving ~= (h.diving or false) then
      h.diving = diving
      log(string.format("drive %s: %s (player depth %.2f)", tostring(id), diving and "dives with the player" or "back to the surface", pwater))
    end
    local want = diving and (py + FLOAT_LIFT - ny) or (hw - SWIM_DEPTH)
    local fix = math.max(-0.08, math.min(0.08, want * 0.25))  -- at most 0.08 m a tick
    if hopping then fix = 0 end
    if fix < 0 then
      local okg, grounded = pcall(function() return world:get("MovementCollider", id).results.m_value.hasGroundCollision end)
      if okg and grounded then fix = 0 end
    end
    tr.position.y = tr.position.y + math.floor(fix * S)
    local dx, dz = px - nx, pz - nz
    local dist = math.sqrt(dx * dx + dz * dz)
    -- with the player out of the water he keeps going to SWIM_OUT_STOP
    local stop = pwet and DRIVE_STOP or SWIM_OUT_STOP
    local spd = 0
    if dist > stop then spd = math.min(SWIM_MAX, 1 + (dist - stop) * SWIM_GAIN) end
    if dist > 0.05 then h.swim_yaw = math.atan(dx, dz) end
    local yaw = h.swim_yaw or 0
    -- Progress = how far HE has moved along the line to the player since the last mark (keeping pace behind a swimming
    -- player counts; sliding sideways along a bank does not). None for HOP_TICKS while the player is higher: a climb-out
    -- hop (speed straight up for the player's height + HOP_MARGIN, HOP_FORWARD toward him, HOP_HOLD ticks, at most every
    -- HOP_EVERY). None for STUCK_TICKS: "can't follow" (cant_follow), over when he moves again.
    local along = 0
    if h.wprog and dist > 0.05 then along = ((nx - h.wprog.x) * dx + (nz - h.wprog.z) * dz) / dist end
    if not h.wprog or along > 0.3 or dist <= stop then
      h.wprog = { x = nx, z = nz, t = t }
      cant_over(s, "he swims on (water)")
    end
    local still = t - h.wprog.t
    local up_speed
    if dist > stop and still > HOP_TICKS and not pwet and py > ny + 0.3 and not hopping and (not h.hop_next or t >= h.hop_next) then
      up_speed = math.min(14, math.sqrt(2 * 25 * (py - ny + HOP_MARGIN)))
      h.hop_until, h.hop_next = t + HOP_HOLD, t + HOP_EVERY
      hopping = true
      log(string.format("hop: %s hops out of the water toward the player (%.1f m higher, %.1f m away): %.1f m/s up", tostring(id),
        py - ny, dist, up_speed))
      fullrec_event(world, id, string.format("drive (water): hop out, %.1f m/s up", up_speed))
    end
    if dist > stop and still > STUCK_TICKS and not h.cant then
      report_blockers(s, "can't follow (water)", dx, dz)
      cant_follow(s, "blocked", "no progress while swimming")
    end
    if hopping then spd = HOP_FORWARD end
    local okv = pcall(function()
      local v = world:get("Velocity", id).velocity
      if up_speed then
        v.x, v.y, v.z = math.sin(yaw) * spd, up_speed, math.cos(yaw) * spd
      elseif hopping then
        v.x, v.z = math.sin(yaw) * spd, math.cos(yaw) * spd  -- up and down left to gravity during the hop
      else
        v.x, v.y, v.z = math.sin(yaw) * spd, 0, math.cos(yaw) * spd
      end
    end)
    if not okv and not h.swim_err then h.swim_err = true log("drive " .. tostring(id) .. ": could not set his swimming speed") end
    local o = tr.orientation
    local hy, hp = yaw / 2, math.rad(-FLOAT_PITCH) / 2
    local cy, sy, cp, sp = math.cos(hy), math.sin(hy), math.cos(hp), math.sin(hp)
    o.w, o.x, o.y, o.z = cy * cp, cy * sp, sy * cp, -sy * sp
    if t % 30 == 0 then fullrec_event(world, id, string.format("drive (water): player %.1f m, his depth %.2f, swimming %.1f m/s at %.0f", dist, hw, spd, (math.deg(yaw) + 360) % 360)) end
    return true
  elseif h.water then
    h.water = nil
    h.wprog, h.hop_until = nil, nil
    cant_over(s, "out of the water")
    pcall(function()
      local o = world:get("CurrentTransform", id).transform.orientation
      local yaw = h.swim_yaw or math.atan(2 * (o.x * o.z + o.w * o.y), 1 - 2 * (o.x * o.x + o.y * o.y))
      o.x, o.y, o.z, o.w = 0, math.sin(yaw / 2), 0, math.cos(yaw / 2)
    end)
    h.trail = {}
    fullrec_event(world, id, "drive: out of the water himself, upright, walking again")
    log(string.format("drive %s: out of the water himself (depth %.2f), walking again", tostring(id), hw))
  end
  return false
end

-- What the player does, every tick: on the ground or in the air, a leap into the water, air segments, and his meta
-- data for the crumbs. While he swims there are no crumbs and swimming is not a flight. Coming down into the water
-- straight from the air (no ground between) is a leap: where he took off and where he went in (h.leap).
-- An air segment (h.aseg) is every time in the air between two crumbs: the takeoff (the crumb before gets .takeoff),
-- the top, how long, the jump count, every locomotion state seen (the glider has its own), a second push up mid-air
-- (a double jump), and the landing (the first crumb after gets .landing; into the water: .water). Logged as "air".
local function drive_track_player(s)
  local world, id, h, t = s.world, s.id, s.h, s.t
  local px, py, pz = s.px, s.py, s.pz
  local pwet = s.pwet
  local trail = h.trail
  local last = trail[#trail]
  pcall(function()  -- the player's ground data whenever it changes (log)
    local r = world:get("MovementCollider", h.player).results
    local st = world:get("DynamicLocomotion", h.player).state
    local key = tostring(r.m_value.hasGroundCollision) .. "/" .. tostring(st)
    if key ~= h.gkey then
      h.gkey = key
      log(string.format("crumbs %s: player ground: contact %s, distance %.4f, locomotion state %s, y %.2f", tostring(id),
        tostring(r.m_value.hasGroundCollision), tonumber(r.m_value.groundDistance) or -1, tostring(st), py))
    end
  end)
  local airborne = player_airborne(world, h.player)
  if pwet then
    if not h.pwet_prev then
      if h.air and last then
        local hp = health(world, id)
        h.leap = { fx = last.x, fy = last.y, fz = last.z, tx = px, ty = py, tz = pz, hp = hp }
        log(string.format("leap %s: the player leapt into the water from %.1f %.1f %.1f (%.1f m above where he went in at %.1f %.1f %.1f); edge stop off for the hound (health %s)",
          tostring(id), last.x, last.y, last.z, last.y - py, px, py, pz, tostring(hp)))
      else
        h.leap = nil
      end
    end
    airborne = true
    h.air, h.flight = nil, nil
    if h.aseg then
      local sg = h.aseg
      h.aseg = nil
      sg.water = true
      if sg.from then sg.from.takeoff = sg end
      log(string.format("air %s: the player took off at %.1f %.1f %.1f and came down in the water at %.1f %.1f %.1f after %.2f s; jump count %d, second push %s",
        tostring(id), sg.x0, sg.y0, sg.z0, px, py, pz, (t - sg.t0) / 60, sg.jc, tostring(sg.double)))
    end
  elseif airborne then
    h.air = h.air or t
  elseif h.air then  -- landed: a long flight (not a glide that came down close) breaks the trail at the next crumb
    if t - h.air > DROP_AIR_TICKS and not (h.aseg and h.aseg.states[GLIDE_STATE]) then h.flight = true end
    h.air = nil
  end
  -- his meta data: locomotion state (0 on the ground, 2 in the air, 4 the glider, 9/10 swimming), jump count and type,
  -- speed and up/down speed, facing
  local pm = { st = -1, jc = -1, jt = -1, vx = 0, vy = 0, vz = 0, yaw = 0 }
  pcall(function()
    local loc = world:get("DynamicLocomotion", h.player)
    pm.st, pm.jc, pm.jt = tonumber(loc.state) or -1, tonumber(loc.jumpCount) or -1, tonumber(loc.jumpType) or -1
  end)
  pcall(function()
    local v = world:get("Velocity", h.player).velocity
    pm.vx, pm.vy, pm.vz = tonumber(v.x) or 0, tonumber(v.y) or 0, tonumber(v.z) or 0
  end)
  pcall(function()
    local o = world:get("CurrentTransform", h.player).transform.orientation
    pm.yaw = (math.deg(math.atan(2 * (o.x * o.z + o.w * o.y), 1 - 2 * (o.x * o.x + o.y * o.y))) + 360) % 360
  end)
  local pspd = math.sqrt(pm.vx * pm.vx + pm.vz * pm.vz)
  if airborne and not pwet then
    local sg = h.aseg
    if not sg then
      sg = { from = last, t0 = t, x0 = px, y0 = py, z0 = pz, top = py, jc = 0, states = {}, spd0 = pspd, vy0 = pm.vy,
             minvy = pm.vy, double = false }
      h.aseg = sg
    end
    if py > sg.top then sg.top = py end
    if pm.jc > sg.jc then sg.jc = pm.jc end
    if not sg.states[pm.st] then  -- each new locomotion state in the air (log)
      log(string.format("air %s: player state %d after %.2f s in the air (height %.1f, %.1f m from takeoff, speed %.1f, up %.1f)",
        tostring(id), pm.st, (t - sg.t0) / 60, py, math.sqrt((px - sg.x0) ^ 2 + (pz - sg.z0) ^ 2), pspd, pm.vy))
    end
    sg.states[pm.st] = true
    if t > sg.t0 + 5 and pm.vy > sg.minvy + 3 then sg.double = true end  -- a second push up: a double jump
    if pm.vy < sg.minvy then sg.minvy = pm.vy end
  elseif h.aseg and not pwet then
    local sg = h.aseg
    h.aseg = nil
    sg.x1, sg.y1, sg.z1, sg.dur = px, py, pz, t - sg.t0
    local fy = sg.from and sg.from.y or sg.y0
    sg.rise = py - fy
    local states = {}
    for k in pairs(sg.states) do states[#states + 1] = tostring(k) end
    table.sort(states)
    sg.state_list = table.concat(states, ",")
    if sg.from then sg.from.takeoff = sg end
    h.landing_seg = sg
    log(string.format("air %s: the player took off at %.1f %.1f %.1f (speed %.1f, up %.1f), top %.1f, came down at %.1f %.1f %.1f "
      .. "(%.1f m %s, %.1f m out) after %.2f s; jump count %d, second push %s, states %s", tostring(id), sg.x0, sg.y0, sg.z0,
      sg.spd0, sg.vy0, sg.top, px, py, pz, math.abs(sg.rise), sg.rise >= 0 and "higher" or "lower",
      math.sqrt((px - sg.x0) ^ 2 + (pz - sg.z0) ^ 2), sg.dur / 60, sg.jc, tostring(sg.double), sg.state_list))
  end
  s.trail, s.last, s.airborne, s.pm, s.pspd = trail, last, airborne, pm, pspd
end

-- Put away (h.go_away; F.tick removes the body and brings him back beside the player once he stands on the ground):
-- a glide still going after GLIDE_WAIT or GLIDE_FAR away, a fast travel (FAR_JUMP in one tick), or TP_AFTER after he
-- could not follow (h.cant).
-- (owner 2026-11-20 06:53 "I think safety net is a good idea") the fall safety net: in the air (locomotion state 2) he
-- remembers the height he left the ground at; more than FALL_SAFE below it, he is put away before he lands and comes back
-- beside the player (his fall damage starts at 8 m). 2026-11-19 21:47 and 21:57: copied jumps that missed (a narrow
-- ledge; a jump the player finished with the glider) fell 20.7 m and 22.5 m and killed him at full health.
local FALL_SAFE = 7.5
local function drive_put_away(s)
  local h, t = s.h, s.t
  local px, pz, nx, nz = s.px, s.pz, s.nx, s.nz
  local lst
  pcall(function() lst = tonumber(s.world:get("DynamicLocomotion", s.id).state) end)
  if lst == 2 then
    h.fall_y0 = h.fall_y0 or s.ny
    if s.ny < h.fall_y0 - FALL_SAFE then
      log(string.format("fall net %s: %.1f m below where he left the ground (%.1f -> %.1f): put away before he lands",
        tostring(s.id), h.fall_y0 - s.ny, h.fall_y0, s.ny))
      h.fall_y0 = nil
      h.go_away = "falling"
      return true
    end
  else
    h.fall_y0 = nil
  end
  local dog_d = math.sqrt((px - nx) ^ 2 + (pz - nz) ^ 2)
  if h.aseg and h.aseg.states[GLIDE_STATE] and (t - h.aseg.t0 > GLIDE_WAIT or dog_d > GLIDE_FAR) then
    h.go_away = "glide"
    return true
  end
  if h.last_px and (px - h.last_px) ^ 2 + (pz - h.last_pz) ^ 2 > FAR_JUMP ^ 2 then
    h.go_away = "fast travel"
    return true
  end
  h.last_px, h.last_pz = px, pz
  if h.cant then
    h.cant_since = h.cant_since or t
    if t - h.cant_since >= TP_AFTER then
      h.go_away = "can't follow"
      return true
    end
  else
    h.cant_since = nil
  end
  return false
end

-- the breadcrumb trail: a crumb every DRIVE_STEP the player moves on the ground, with his meta data (crumb.m) and the
-- air segment that landed there; a drop or a long flight before it marks a break (brk). At most 800 crumbs.
local function drive_lay_crumb(s)
  local world, id, h, t = s.world, s.id, s.h, s.t
  local px, py, pz = s.px, s.py, s.pz
  local pwater, trail, last, airborne, pm, pspd = s.pwater, s.trail, s.last, s.airborne, s.pm, s.pspd
  if airborne then
  elseif not last or (px - last.x) ^ 2 + (pz - last.z) ^ 2 > DRIVE_STEP ^ 2 then
    local brk = last and (last.y - py > DROP_HEIGHT or h.flight)
    h.flight = nil
    trail[#trail + 1] = { x = px, y = py, z = pz, brk = brk or nil,
      m = { t = t, st = pm.st, jc = pm.jc, jt = pm.jt, spd = pspd, vy = pm.vy, yaw = pm.yaw, wd = pwater },
      landing = h.landing_seg }
    h.landing_seg = nil
    if CRUMB_LOG then log(string.format("crumbs %s: crumb %d at y %.2f%s (state %d, speed %.1f, facing %.0f)", tostring(id), #trail, py,
      brk and " (drop)" or "", pm.st, pspd, pm.yaw)) end
    if brk then
      fullrec_event(world, id, string.format("drive: drop in the trail at %.1f %.1f %.1f (from %.1f %.1f %.1f)", px, py, pz,
        last.x, last.y, last.z))
    end
    if #trail > 800 then table.remove(trail, 1) end
  end
end

-- every tick: his route planner off (it still runs with the AI off and writes "don't move" into his input), and the
-- slide recorder (his locomotion state and the game's slide flags, into the log when they change)
local function drive_upkeep(s)
  local world, id, h = s.world, s.id, s.h
  local nx, ny, nz = s.nx, s.ny, s.nz
  local pwet = s.pwet
  h.pwet_prev = pwet
  local pw = world:get("DynamicPathWalker", id)
  if pw and pw.isWalkingActive ~= false then pw.isWalkingActive = false end
  pcall(function()
    local loc = world:get("DynamicLocomotion", id)
    local key = string.format("state %s, slide %s, sliding/falling %.2f, friction %.2f", tostring(loc.state),
      tostring(loc.slideDetected), tonumber(loc.slidingFallingFactor) or -1, tonumber(loc.frictionFactor) or -1)
    if key ~= h.slidekey then
      h.slidekey = key
      log(string.format("slide %s: %s at %.1f %.1f %.1f", tostring(id), key, nx, ny, nz))
    end
  end)
end

-- A jump in flight and the settle after it (returns true while either runs; drive_copy starts the jumps). In the air the
-- native edge stop is off; until the game counts him in the air (up to DJ_LIFT ticks) the launch speed is written
-- again; in the air the speed across is written every tick toward the crumb (up and down left to gravity); over it
-- (within 0.6 m) the speed across goes and he drops onto it. After a jump UP he settles: stands still DJ_SETTLE ticks
-- with the edge stop off, so he neither hops nor slides off. Logs "jump follow".
local function drive_jump_follow(s)
  local world, id, h, a, t = s.world, s.id, s.h, s.a, s.t
  local nx, ny, nz = s.nx, s.ny, s.nz
  if h.djump then
    local okl, lst = pcall(function() return tonumber(world:get("DynamicLocomotion", id).state) end)
    if okl and lst == 2 and not h.djump.air then
      h.djump.air = true
      log(string.format("jump follow %s: in the air after %d tick(s)", tostring(id), t - h.djump.t0))
    end
    if not h.djump.air and t <= h.djump.t0 + DJ_LIFT then
      pcall(function()
        local v = world:get("Velocity", id).velocity
        v.x, v.y, v.z = h.djump.vx, h.djump.vy, h.djump.vz
      end)
    end
    if h.djump.air and not h.djump.over then
      local ddx, ddz = h.djump.x1 - nx, h.djump.z1 - nz
      local dd = math.sqrt(ddx * ddx + ddz * ddz)
      local sp = math.sqrt(h.djump.vx * h.djump.vx + h.djump.vz * h.djump.vz)
      if dd > 0.05 then
        pcall(function()
          local v = world:get("Velocity", id).velocity
          v.x, v.z = ddx / dd * sp, ddz / dd * sp
        end)
      end
    end
    if not h.djump.over and (nx - h.djump.x1) ^ 2 + (nz - h.djump.z1) ^ 2 < 0.6 ^ 2 then
      h.djump.over = true
      pcall(function()
        local v = world:get("Velocity", id).velocity
        v.x, v.z = 0, 0
      end)
      h.djump.vx, h.djump.vz = 0, 0
    end
    if t > h.djump.untill or (h.djump.air and okl and lst ~= 2) or (not h.djump.air and t > h.djump.t0 + DJ_LIFT) then
      local hp = health(world, id)
      log(string.format("jump follow %s: down at %.1f %.1f %.1f, %.1f m from the crumb (%.1f m %s it), health %s (was %s)",
        tostring(id), nx, ny, nz, math.sqrt((nx - h.djump.x1) ^ 2 + (nz - h.djump.z1) ^ 2), math.abs(ny - h.djump.y1),
        ny >= h.djump.y1 - 0.5 and "level with" or "below", tostring(hp), tostring(h.djump.hp)))
      if h.djump.up and h.djump.air and ny >= h.djump.y1 - 0.5 then h.djsettle = t + DJ_SETTLE end
      h.djump = nil
    else
      edge_off(a)
      return true
    end
  end
  if h.djsettle then
    if t > h.djsettle then
      h.djsettle = nil
    else
      pcall(function()
        local v = world:get("Velocity", id).velocity
        v.x, v.z = 0, 0
      end)
      edge_off(a)
      hold_at(a, nx, ny, nz)
      return true
    end
  end
  return false
end

-- a lure (console "lure", for tests of the edge stop): one point he walks to for a while instead of the trail, facing
-- it; only the native edge stop keeps him from walking off a cliff. The trail stays.
local function drive_lure(s)
  local world, id, h, a, t = s.world, s.id, s.h, s.a, s.t
  local nx, nz = s.nx, s.nz
  if h.lure then
    if t > h.lure.untill then
      h.lure = nil
      fullrec_event(world, id, "drive: lure over, following again")
    else
      pcall(function() a.combatData.isTargetInsideLeash = false end)
      hold_at(a, h.lure.x, h.lure.y, h.lure.z)
      local fx, fz = h.lure.x - nx, h.lure.z - nz
      if fx * fx + fz * fz > 9 then
        face(world, id, math.atan(fx, fz))
      end
      return true
    end
  end
  return false
end

-- a hold (console "hold", for tests): he stands where he is and faces the target
local function drive_hold(s)
  local world, id, a, t = s.world, s.id, s.a, s.t
  local nx, ny, nz = s.nx, s.ny, s.nz
  local hd = holds[id]
  if hd and (t > hd.untill or not world:position(hd.target)) then holds[id] = nil hd = nil end
  if hd then
    local gx, _, gz = world:position(hd.target)
    hold_at(a, nx, ny, nz)
    local fx, fz = gx - nx, gz - nz
    if fx * fx + fz * fz > 0.04 then
      face(world, id, math.atan(fx, fz))
    end
    if t % 30 == 0 then fullrec_event(world, id, "drive: holding, facing " .. tostring(hd.target)) end
    return true
  end
  return false
end

-- His target (s.c, the crumb he heads for; nil = the player). Crumbs behind him and the ones he reached (within
-- CRUMB_REACH; the last one stays) are dropped; he heads for the first one further away. He has arrived when he is
-- within DRIVE_STOP of the player across AND in height (a player straight below or above him is not "here").
-- At the water: when the player swims and the hound stands at the water's level (at most WATER_NEAR above the surface
-- the player's depth gives, not more than 1 m below it), or after a leap, and the trail ahead is short (its last crumb
-- within 3 m, or none), he heads straight for the swimming player (h.to_swimmer) and stays on that while the player is
-- in the water. On that way his progress along the line to the player counts; none for STUCK_TICKS: "can't follow".
local function drive_pick_target(s)
  local id, h, t = s.id, s.h, s.t
  local px, py, pz, nx, ny, nz = s.px, s.py, s.pz, s.nx, s.ny, s.nz
  local pwater, pwet = s.pwater, s.pwet
  local trail = s.trail
  local dp = math.sqrt((px - nx) ^ 2 + (pz - nz) ^ 2)
  local here = dp <= DRIVE_STOP and math.abs(py - ny) <= DRIVE_STOP
  local how = "stop"
  local c
  if not here then
    local near, nd = 1, math.huge
    for i, cc in ipairs(trail) do
      local dd = (cc.x - nx) ^ 2 + (cc.z - nz) ^ 2
      if dd < nd then near, nd = i, dd end
    end
    for _ = 1, near - 1 do table.remove(trail, 1) end
    while #trail > 1 and (trail[1].x - nx) ^ 2 + (trail[1].z - nz) ^ 2 < CRUMB_REACH ^ 2 do
      table.remove(trail, 1)
    end
    local pick = #trail
    for i = 1, #trail do
      if (trail[i].x - nx) ^ 2 + (trail[i].z - nz) ^ 2 > CRUMB_REACH ^ 2 then pick = i break end
    end
    c = trail[pick]
    how = string.format("crumb %d of %d", pick, #trail)
  end
  local was_to_swimmer = h.to_swimmer
  h.to_swimmer = nil
  local surface = pwet and (py + pwater) or nil
  local near_water = surface and ny - surface < WATER_NEAR and ny - surface > -1
  local lastc = trail[#trail]
  if (near_water or h.leap) and not here and (was_to_swimmer or not lastc or (lastc.x - nx) ^ 2 + (lastc.z - nz) ^ 2 < 3 ^ 2) then
    c, h.to_swimmer = nil, true
    how = "to the swimming player"
  end
  if h.to_swimmer ~= h.to_swimmer_said then
    h.to_swimmer_said = h.to_swimmer
    h.sprog = nil
    cant_over(s, h.to_swimmer and "straight to the swimming player now" or "back on the trail")
    log(string.format("drive %s: %s", tostring(id), h.to_swimmer and "trail ends at the water: straight to the swimming player" or "back on the trail"))
    log(string.format("drive %s: switch: player wet %s (depth %.2f), surface %s, his height %.2f, near water %s, leap %s, player %.1f m, trail %d crumbs, last crumb %s m, tick %d",  -- every value the switch looked at
      tostring(id), tostring(pwet), pwater, surface and string.format("%.2f", surface) or "-", ny, tostring(near_water), tostring(h.leap ~= nil), dp, #trail,
      lastc and string.format("%.1f", math.sqrt((lastc.x - nx) ^ 2 + (lastc.z - nz) ^ 2)) or "-", t))
  end
  if h.to_swimmer then
    local tdx, tdz = px - nx, pz - nz
    local td = math.sqrt(tdx * tdx + tdz * tdz)
    local along = 0
    if h.sprog and td > 0.05 then along = ((nx - h.sprog.x) * tdx + (nz - h.sprog.z) * tdz) / td end
    if not h.sprog or along > 0.3 then
      h.sprog = { x = nx, z = nz, t = t }
    elseif t - h.sprog.t > STUCK_TICKS and not h.cant then
      report_blockers(s, "can't follow (to the water)", tdx, tdz)
      cant_follow(s, "blocked", "no progress toward the swimming player")
    end
  end
  s.c, s.how, s.dp, s.here = c, how, dp, here
end

-- Copying the player's way to his next crumb (returns true when he jumps). Only on the ground, on the trail, once per
-- crumb. A break (a drop over DROP_HEIGHT, a long flight): "can't follow". The player jumped to it (the crumb is the
-- landing of a jump: jump count 1+ or a second push) or it is STEP_UP or more above him (the player went up without a
-- jump the log saw): he jumps to it. Everything else (level, a small drop, a ledge the player walked off) he walks,
-- and falls where the player fell.
local function drive_copy(s)
  local world, id, h, a, t = s.world, s.id, s.h, s.a, s.t
  local nx, ny, nz = s.nx, s.ny, s.nz
  local c = s.c
  if s.pwet or h.to_swimmer or not c or h.cant or c.jumped then return false end
  if c.brk then
    cant_follow(s, c.y < ny - DROP_HEIGHT and "drop" or "blocked", string.format("the player's way to the next crumb cannot be copied (%.1f m %s, %s)",
      math.abs(c.y - ny), c.y >= ny and "up" or "down", c.y < ny - DROP_HEIGHT and "too high a drop" or "a long flight"))
    return false
  end
  local rise = c.y - ny
  local jumped = c.landing and ((tonumber(c.landing.jc) or 0) >= 1 or c.landing.double)
  if not (jumped or rise >= STEP_UP) then return false end
  local okl, lst = pcall(function() return tonumber(world:get("DynamicLocomotion", id).state) end)
  if okl and lst == 2 then return false end  -- he is in the air himself: not now
  local ddx, ddz = c.x - nx, c.z - nz
  local d = math.sqrt(ddx * ddx + ddz * ddz)
  local vup, vh = launch_speeds(d, rise)
  local hp = health(world, id)
  local okv, vx, vz = launch(world, id, ddx, ddz, d, vup, vh)
  edge_off(a)
  c.jumped = true
  h.prog = nil
  h.djump = { t0 = t, untill = t + DJ_TICKS, x1 = c.x, y1 = c.y, z1 = c.z, hp = hp, vx = vx, vz = vz, vy = vup, up = rise >= STEP_UP }
  log(string.format("jump follow %s: %s: %.1f m %s, %.1f m out, %.1f m/s up, %.1f m/s out (health %s)%s", tostring(id),
    jumped and ("the player jumped here (jump count " .. tostring(c.landing.jc) .. ")") or "a step up",
    math.abs(rise), rise >= 0 and "up" or "down", d, vup, vh, tostring(hp), okv and "" or " (could not set his speed)"))
  return true
end

-- The one stuck rule (returns true while he stands). He heads for a crumb but has not come 0.3 m closer to it for
-- STUCK_TICKS, for any reason: "can't follow" (the notice says up / too steep / blocked from where the crumb is). While
-- he cannot follow he stands; the player coming to him ends it, otherwise drive_put_away respawns him beside the player.
-- (owner 2026-11-19 21:54 yes) the heal's Wolf Shout holds him in place while it plays: for SHOUT_HOLD after a heal the
-- stuck timer starts over (21:33 and 21:38: two shouts 4 s apart made "can't follow: blocked" 0.5 m from his crumb)
local SHOUT_HOLD = 120
local function drive_stuck(s)
  local world, id, h, a, t = s.world, s.id, s.h, s.a, s.t
  local nx, ny, nz = s.nx, s.ny, s.nz
  local c, dp = s.c, s.dp
  if h.cant then
    if s.here then
      cant_over(s, "the player came to him")
      return false
    end
    hold_at(a, nx, ny, nz)
    if t % 30 == 0 then fullrec_event(world, id, string.format("drive: can't follow, standing, player %.1f m", dp)) end
    return true
  end
  local alive = true
  pcall(function() alive = world:get("Health", id).dataStorage[1] > 0 end)
  if c and alive then
    local dc = math.sqrt((c.x - nx) ^ 2 + (c.z - nz) ^ 2)
    if h.prog == nil or h.prog.c ~= c or dc < h.prog.d - 0.3 or t - (h.heal_t or -1e9) < SHOUT_HOLD then
      h.prog = { c = c, d = dc, t = t }
    elseif t - h.prog.t > STUCK_TICKS then
      h.prog = nil
      local dy = c.y - ny
      report_blockers(s, "can't follow", c.x - nx, c.z - nz)
      cant_follow(s, dy < -0.8 and "down" or (dy > 0.6 and "up" or "blocked"),
        string.format("no progress toward his crumb %.1f %.1f %.1f (%.1f m away)", c.x, c.y, c.z, dc))
      hold_at(a, nx, ny, nz)
      return true
    end
  else
    h.prog = nil
  end
  return false
end

-- The native hook's inputs: the target (the crumb, or the player) and the player's spot. On the trail (a crumb as the
-- target) the native edge stop is off: where the player walked there was ground (planks, trap doors and overhangs
-- fooled its ray). Off the trail (straight to a swimming player, or no trail yet) it is on; on the way to the swimming
-- player it lets him drop up to 7.5 m (into the water). While he moves his body faces the target.
local SLOTS = { { -1.6, -0.8 }, { 1.6, -0.8 }, { 0, -2.2 }, { -2.4, -2.2 }, { 2.4, -2.2 } }  -- (12:22) followers 2..6
local SLOT_NEAR, SLOT_GAP = 4, 1.5
local function drive_steer(s)
  local world, id, h, a, t = s.world, s.id, s.h, s.a, s.t
  local px, py, pz, nx, nz = s.px, s.py, s.pz, s.nx, s.nz
  local c, how, dp = s.c, s.how, s.dp
  a.homeZonePosition.x, a.homeZonePosition.y, a.homeZonePosition.z = px, py, pz
  local tx, ty, tz = px, py, pz
  if c then tx, ty, tz = c.x, c.y, c.z end
  -- (owner 2026-11-20 12:22 "N2 didn't spawn with me": it had, at N1's exact spot, and both stopped on the same
  -- point) more than one follower of the same player: going to the player himself (no crumb), the 2nd, 3rd ...
  -- (by entity id) stop at their own place around him (SLOTS: metres right / forward of his facing)
  -- (12:26: a reload starts each trail with a crumb at the player's feet, so near him there was still a crumb) also
  -- on the trail once within SLOT_NEAR of the player
  if not c or (dp and dp <= SLOT_NEAR) then
    local mine = {}
    for oid, oh in pairs(drives) do if oh.player == h.player then mine[#mine + 1] = oid end end
    if #mine > 1 then
      table.sort(mine)
      local k = 0
      for i, oid in ipairs(mine) do if oid == id then k = i - 1 end end
      -- (12:28: his first place was where the other one already stood) his place: the first of SLOTS (his own first)
      -- at least SLOT_GAP from every follower before him; kept while it stays that way
      local o
      if k > 0 then
        local yaw = 0
        pcall(function()
          local q = world:get("CurrentTransform", h.player).transform.orientation
          yaw = math.atan(2 * (q.x * q.z + q.w * q.y), 1 - 2 * (q.x * q.x + q.y * q.y))
        end)
        local function point(i)
          local p = SLOTS[i]
          return px + math.cos(yaw) * p[1] + math.sin(yaw) * p[2], pz - math.sin(yaw) * p[1] + math.cos(yaw) * p[2]
        end
        local function free(x, z)
          for j = 1, k do
            local ox, _, oz = world:position(mine[j])
            if ox and (ox - x) ^ 2 + (oz - z) ^ 2 < SLOT_GAP * SLOT_GAP then return false end
          end
          return true
        end
        local pick = h.slot_i and free(point(h.slot_i)) and h.slot_i
        for n = 0, #SLOTS - 1 do
          if pick then break end
          local i = (k - 1 + n) % #SLOTS + 1
          if free(point(i)) then pick = i end
        end
        pick = pick or ((k - 1) % #SLOTS + 1)
        h.slot_i, o = pick, SLOTS[pick]
        tx, tz = point(pick)
        -- (12:24: they still stood together) the C++ stops him within 2 m of homeZonePosition (the player): for a slot
        -- that point is put 1.5 m past his place, on his way there, so he stops about 0.5 m from his place
        local ux, uz = tx - nx, tz - nz
        local ud = math.sqrt(ux * ux + uz * uz)
        if ud > 0.01 then
          a.homeZonePosition.x, a.homeZonePosition.z = tx + ux / ud * 1.5, tz + uz / ud * 1.5
        else
          a.homeZonePosition.x, a.homeZonePosition.z = tx + 1.5, tz
        end
      end
      local said = o and (k * 10 + h.slot_i) or 0
      if said ~= h.slot_said then  -- (12:27) logged when his place changes
        h.slot_said = said
        log(string.format("slot %s: follower %d of %d for player %s%s", tostring(id), k + 1, #mine, tostring(h.player),
          o and string.format(", place %d: %.1f %.1f (%.1f m from him now)", h.slot_i, tx, tz, math.sqrt((tx - nx) ^ 2 + (tz - nz) ^ 2)) or ", next to him"))
      end
    end
  end
  local on_trail = c ~= nil
  if on_trail then edge_off(a) end
  pcall(function() a.combatData.isTargetInsideLeash = (not on_trail and h.to_swimmer) and true or false end)
  local edge = on_trail and "on the trail: edge stop off" or (h.to_swimmer and "to the swimming player: edge stop on, drops to 7.5 m" or "no trail: edge stop on")
  if not s.here and edge ~= h.edge_said then
    h.edge_said = edge
    log(string.format("edge %s: %s (at %.1f %.1f %.1f)", tostring(id), edge, nx, s.ny, nz))
  end
  a.movementTarget.x, a.movementTarget.y, a.movementTarget.z = tx, ty, tz
  a.movementTargetIsValid = true
  -- (owner 2026-11-19 16:37 "I agree #2") his pace is the player's at the crumb he is heading for
  local pace = PACE_WALK
  if c and c.m and c.m.spd then pace = c.m.spd >= PACE_SPRINT_AT and PACE_SPRINT or (c.m.spd >= PACE_RUN_AT and PACE_RUN or PACE_WALK) end
  set_pace(a, pace)
  if pace ~= h.pace_said and not s.here then
    h.pace_said = pace
    log(string.format("pace %s: %s (the player at that crumb: %s m/s; player %.1f m away)", tostring(id),
      pace == PACE_SPRINT and "sprint" or (pace == PACE_RUN and "run" or "walk"), c and c.m and string.format("%.1f", c.m.spd) or "-", dp))
  end
  if not s.here then
    local fx, fz = tx - nx, tz - nz
    if fx * fx + fz * fz > 0.04 then
      face(world, id, math.atan(fx, fz))
    end
  end
  if t % 30 == 0 then
    fullrec_event(world, id, string.format("drive: %s, target %.2f %.2f %.2f, player %.1f m", how, tx, ty, tz, dp))
  end
end

-- one tick of the drive for one companion (F.tick calls it for every entry in drives)
local function drive_step(world, id, h)
  local s = drive_read(world, id, h)
  if not s then return end
  set_pace(s.a, PACE_WALK)  -- drive_steer sets the trail's pace; the C++ sprints past 6 m from where he is headed
  -- (owner 2026-11-20 08:02 "make it so the companion can't move or do anything until the chest is closed")
  if inv.frozen and inv.frozen(id) then  -- (name_of is declared further down: the inventory part answers; the pin
    -- itself is done by inv.tick, for the owner online or not)
    hold_at(s.a, s.nx, s.ny, s.nz)
    h.atk = nil
    pcall(function() s.a.combatData.lastTargetId = 0 s.a.combatData.selectedAttackIndex = 255 end)
    return
  end
  drive_waterlog(s)
  if drive_water(s) then return end
  drive_track_player(s)
  if drive_put_away(s) then return end
  drive_lay_crumb(s)
  drive_upkeep(s)
  if drive_heal and not s.pet then drive_heal(s) end  -- never takes over the movement (pets: no healing yet)
  if drive_jump_follow(s) then return end
  if drive_fight and not s.pet and drive_fight(s) then return end  -- (pets never fight: owner 09:51)
  if drive_lure(s) then return end
  if drive_hold(s) then return end
  drive_pick_target(s)
  if drive_copy(s) then return end
  if drive_stuck(s) then return end
  drive_steer(s)
end


-- ===== Staying =========================================================================================================
-- No game AI at all: his AI stays off (as while following), his route planner off, and FlameKit gives no target, so
-- the native hook writes nothing and he stands still where he is.
local CALM = (1 << 8) | (1 << 26)  -- EnemyFeature Roaming, Investigate: also marks the body as ours (still_ours)
local function calm(world, npc)
  local d = world:get("DynamicEnemy01BehaviorState", npc)
  d.disabledFeatures = (tonumber(d.disabledFeatures) or 0) | CALM
end
local function stay_at(world, npc, x, y, z)
  local a = world:get("DynamicEnemy01BehaviorState", npc)
  a.enabled = false
  pcall(function() world:get("DynamicPathWalker", npc).isWalkingActive = false end)
  a.movementTargetIsValid = false
  calm(world, npc)
end

-- ===== The roster: FlameKit's own list of companions, kept in the world's data =========================================
-- Each companion has a name (N1, N2 ...) and keeps it whether its body is out in the world or put away. A record: body
-- (template GUID), spot, mode (stay/follow), owner (account), out (true: has a body in the world). The game deletes
-- our bodies on a restart: out ones come back, stayers at their spot when the world loads, followers next to their
-- owner when he joins. A script reload finds its bodies again (by entity, faction and the calm switches) instead of
-- spawning a second one.
-- Companions are PlayerAlly (faction 11), the game's own "on the players' side": friends of players, enemies of
-- monsters (with faction 7, Player, their attacks on monsters did no damage).
local COMPANION_FACTION = 11
local HOUND = "18eefd30-da1d-49f5-a6d8-7da8f2d01f43"  -- Enemy_Skeleton_Hound, the owner's pick
local roster = { list = {}, next_n = 1, loaded = false, main = {} }  -- main: account -> name (one main companion per player)
local pending_life = {}  -- entity -> { r, player, at }: set up half a second after spawning
local waiting = {}       -- name -> { player, tries }: a follower waiting for its owner's body
local ent_of = {}     -- name -> entity (this session only)
local name_of = {}    -- entity -> name

-- who may command a companion: its controllers (a list of accounts: one for a personal companion,
-- several for a shared one) and FlameKit's admins (their own list of accounts, npc_admins.json beside the mod on the
-- server; the shared server password says nothing about who is who, the account does). Anyone else: a notice only.
local store = require("core.store")
local players = require("core.players")
local OWNER_ACCOUNT = "0x485890b753e75ad1"  -- the server owner, the first admin
local admins = store.load("npc_admins", nil)
if type(admins) ~= "table" then admins = { OWNER_ACCOUNT } store.save("npc_admins", admins) end
local function is_admin(account)
  for _, a in ipairs(admins) do if a == account then return true end end
  return false
end
local function controls(r, account)
  for _, a in ipairs(r.controllers or {}) do if a == account then return true end end
  return false
end
local function may_command(r, account) return account and (controls(r, account) or is_admin(account)) end

-- (owner 2026-11-20 08:51 "when the chest spawns and opens I just want it to have the companions name on it") the
-- game's floating name: the chest is spawned with CustomPlayerString.stringId = FNV-1a 64 of his name (the game's own
-- key for a text); the server probe (C++) puts each name of custom_names.txt into the server's name table, which the
-- key needs BEFORE the chest is spawned (the game clears a key it does not know)
function inv.name_key(text)
  local h = 0xcbf29ce484222325
  for i = 1, #text do h = (h ~ text:byte(i)) * 0x100000001b3 end
  return h
end
function inv.write_names()
  if not emf.dir then return end
  local list = {}
  for _, r in ipairs(roster.list) do list[#list + 1] = r.name end
  table.sort(list)
  local text = table.concat(list, "\n") .. "\n"
  if text == inv.names_text then return end
  local f = io.open(emf.dir .. "\\custom_names.txt", "w")
  if not f then return end
  f:write(text)
  f:close()
  inv.names_text = text
  log("names: custom_names.txt now has " .. #list .. " name(s) for the chest labels")
end

local function roster_save()
  if not roster.loaded then return false end
  pcall(inv.write_names)
  local out = { next_n = roster.next_n, main = roster.main, known = roster.known, npcs = {} }
  for _, r in ipairs(roster.list) do
    out.npcs[#out.npcs + 1] = { name = r.name, guid = r.guid, x = r.x, y = r.y, z = r.z, mode = r.mode, fight = r.fight, sus_base = r.sus_base, inv = r.inv, chest = r.chest,
      owner = r.owner, controllers = r.controllers, names = r.names, out = r.out, ent = ent_of[r.name] }
  end
  local okj, text = pcall(emf.json.encode, { npc_roster = out })
  local oks, res = pcall(emf.save_world_data, okj and text or "")
  if not (okj and oks and res) then log("roster: NOT saved (" .. tostring(okj and res or text) .. ")") end
  return oks and res
end

local function find(name)
  for i, r in ipairs(roster.list) do if r.name == name then return r, i end end
end

local function player_of(world, account)
  if not account then return nil end
  for id = 1, 64 do  -- player entities are the low ids (1..1023; a local server has a handful)
    local ok, a = pcall(world.account, world, id)
    if ok and a == account then return id end
  end
end

-- the body's setup: our side, calm, our E prompt, then stay or follow
local on_talk  -- defined below
-- a companion's level is its owner's level, set the way the game's own scaling does it (Level.dataStorage[1], then
-- DynamicEnemyScaling.nextUpdateTime = 0: the game rescales health and hits). Checked at setup and every 10 s (the
-- owner joins later, or levels up).
local function match_level(world, id, r, player)
  local p = player or player_of(world, r.owner)
  if not p then return end
  local pl = world:get("Level", p)
  local lv = world:get("Level", id)
  if not (pl and lv) then return end
  local want = tonumber(pl.dataStorage[1]) or 0
  if want < 1 or lv.dataStorage[1] == want then return end
  lv.dataStorage[1] = want
  local sc = world:get("DynamicEnemyScaling", id)
  if sc then
    if type(sc.nextUpdateTime) == "table" then sc.nextUpdateTime.value = 0 else sc.nextUpdateTime = 0 end
  end
  log(string.format("level: %s (%s) set to its owner's level %d", r.name, tostring(id), want))
end

-- (owner 2026-11-18 21:35 "he definitely needs "Armor"", 21:37 "build it") armor: he takes ARMOR of the damage of every
-- type: his 19 DamageSusceptibility multipliers (one per damage type) are the base ones times ARMOR. The base is read
-- once from a body and kept in the roster (r.sus_base), so it is never scaled twice (the template's half is not
-- readable: world:template gave nothing, 21:38). Checked at setup and every second (the game may set them again, e.g.
-- when it rescales his level); logged when written.
local ARMOR = 1 / 3
-- the skeleton hound's own multipliers (logged 21:22); the 21:38 version scaled the live bodies without keeping the
-- base: values that are exactly these times ARMOR are taken back to these once
local HOUND_SUS = { 0, 1, 0.8, 0.6, 1.5, 0, 0, 0, 0, 1, 1, 1, 1, 0, 1, 1.2, 0.6, 0.8, 1 }
local armor_err = false  -- an armor failure is logged once
local function match_armor(world, id, r)
  local ds = world:get("DamageSusceptibility", id)
  if not ds then return end
  local base = r.sus_base
  if type(base) ~= "table" or #base < 19 then
    local v, scaled = {}, true
    for i = 1, 19 do
      v[i] = tonumber(ds.dataStorage[i]) or 0
      if math.abs(v[i] - HOUND_SUS[i] * ARMOR) > 0.001 then scaled = false end
    end
    base = scaled and HOUND_SUS or v
    r.sus_base = {}
    for i = 1, 19 do r.sus_base[i] = base[i] end
    base = r.sus_base
    roster_save()
    local parts = {}
    for i = 1, 19 do parts[i] = string.format("%.2f", base[i]) end
    log(string.format("armor: %s (%s) base susceptibility kept in the roster: [%s]%s", r.name, tostring(id), table.concat(parts, " "),
      scaled and " (the body was already armored: the hound's own values)" or " (from the body)"))
  end
  local changed = false
  for i = 1, 19 do
    local want = (tonumber(base[i]) or 0) * ARMOR
    if math.abs((tonumber(ds.dataStorage[i]) or 0) - want) > 0.001 then
      ds.dataStorage[i] = want
      changed = true
    end
  end
  if changed then
    local parts = {}
    for i = 1, 19 do parts[i] = string.format("%.2f", tonumber(ds.dataStorage[i]) or -1) end
    log(string.format("armor: %s (%s) susceptibility set to base x %.2f: [%s]", r.name, tostring(id), ARMOR, table.concat(parts, " ")))
  end
end

local function bring_to_life(world, r, id, player)
  ent_of[r.name], name_of[id] = id, r.name
  -- a living body again: the death and stuck notices go
  local owner_p = player or player_of(world, r.owner)
  status(world, owner_p, "companion_dead", nil)
  status(world, owner_p, "companion_stuck", nil)
  if r.face_yaw then  -- a Call: he faces the way the player faced
    local yaw = r.face_yaw
    r.face_yaw = nil
    pcall(function()
      local o = world:get("CurrentTransform", id).transform.orientation
      o.x, o.y, o.z, o.w = 0, math.sin(yaw / 2), 0, math.cos(yaw / 2)
    end)
  end
  pcall(function() world:get("Faction", id).faction = COMPANION_FACTION end)
  pcall(calm, world, id)
  -- (pets, owner 09:51 "they don't die") an animal body takes no damage
  if not world:get("DynamicEnemy01BehaviorState", id) and world:get("DynamicWildlife", id) then
    roster.pet_rules = roster.pet_rules or {}
    if not roster.pet_rules[id] then
      local okr, rule = pcall(emf.hit_rule, { to = id, cancel = true })
      roster.pet_rules[id] = okr and rule or false
      log(string.format("pet %s (%s): takes no damage (%s)", r.name, tostring(id), tostring(okr and rule)))
    end
  end
  inv.prompt(world, id, inv.open[r.name] ~= nil)
  local oka, erra = pcall(match_armor, world, id, r)
  if not oka then log("armor: " .. tostring(erra)) end
  local okm, errm = pcall(match_level, world, id, r, player)
  if not okm then log("level: " .. tostring(errm)) end
  if r.mode == "follow" and player then
    drives[id] = { player = player, trail = {} }
  else
    drives[id] = nil
    pcall(stay_at, world, id, r.x, r.y, r.z)
  end
end

local function spawn_body(world, r, x, y, z, player)
  -- (12:22) not inside another companion: 1.2 m further along x for each one already within 1 m of the spot
  for _ = 1, 6 do
    local busy = false
    for n, e in pairs(ent_of) do
      local ex, _, ez = world:position(e)
      if n ~= r.name and ex and (ex - x) ^ 2 + (ez - z) ^ 2 < 1 then busy = true break end
    end
    if not busy then break end
    x = x + 1.2
  end
  -- (owner 13:57 "yeah do the E menu next") a pet is spawned tame (the game's IsTame tag): the game then gives it its
  -- own "E Pet" prompt (EMF will not put ours on an animal: it has the game's), and pressing it opens his wheel
  -- (InteractionAcceptedEvent, F.setup)
  local pet = false
  for _, m in ipairs(require("core.pets")) do if m[3] == r.guid then pet = true end end
  local ok, id = pcall(emf.spawn, world, r.guid, x, y, z, pet and { IsTame = {} } or nil)
  if pet and not (ok and id and id ~= 0) then
    log(string.format("roster: %s: the tame spawn was refused (%s): spawned wild", r.name, tostring(id)))
    ok, id = pcall(emf.spawn, world, r.guid, x, y, z)
  end
  if not (ok and id and id ~= 0) then
    log(string.format("roster: %s could not be spawned (%s)", r.name, tostring(id)))
    return nil
  end
  pcall(function() world:get("Faction", id).faction = COMPANION_FACTION end)  -- at once, before its AI picks a target
  pcall(function() world:get("DynamicEnemy01BehaviorState", id).enabled = false end)  -- no game AI, ever
  r.out = true
  pending_life[id] = { r = r, player = player, at = world:tick() + 30 }  -- the rest half a second later
  ent_of[r.name], name_of[id] = id, r.name
  log(string.format("roster: %s spawned as %s at %.1f %.1f %.1f (%s)", r.name, tostring(id), x, y, z, r.mode))
  return id
end

-- is this entity still our body (a script reload keeps the bodies; a restart may give the id to something else)?
local function still_ours(world, id)
  if not id or not world:position(id) then return false end
  local ok, yes = pcall(function()
    local a = world:get("DynamicEnemy01BehaviorState", id)
    local f = world:get("Faction", id)
    -- (0.15.313) a pet (an animal: no monster AI) of ours: companion faction and the animal's own data
    if not a then return f and f.faction == COMPANION_FACTION and world:get("DynamicAnimal", id) ~= nil end
    return a and f and (f.faction == COMPANION_FACTION or f.faction == 7) and ((tonumber(a.disabledFeatures) or 0) & CALM) == CALM
  end)
  return ok and yes
end

local function roster_loaded(world, text)
  roster.list, roster.next_n, roster.main, ent_of, name_of = {}, 1, {}, {}, {}
  local okd, data = pcall(emf.json.decode, text or "")
  local saved = okd and type(data) == "table" and data.npc_roster
  if saved then
    roster.next_n = saved.next_n or 1
    roster.main = type(saved.main) == "table" and saved.main or {}
    roster.known = type(saved.known) == "table" and saved.known or {}  -- (roster window) account -> name
    for _, r in ipairs(saved.npcs or {}) do
      -- a record without a controller list: its owner is the only controller
      if not r.controllers then r.controllers = r.owner and { r.owner } or {} end
      r.names = r.names or {}
      roster.list[#roster.list + 1] = r
    end
  end
  roster.loaded = true
  log(string.format("roster: loaded, %d NPC(s)", #roster.list))
  for _, r in ipairs(roster.list) do if r.chest and inv.adopt then pcall(inv.adopt, world, r) end end
  for _, r in ipairs(roster.list) do
    local ent = r.ent
    r.ent = nil
    if r.out then
      local player = player_of(world, r.owner)
      if still_ours(world, ent) then  -- a script reload: the body is still there
        bring_to_life(world, r, ent, player)
        log(string.format("roster: %s found again as %s", r.name, tostring(ent)))
      elseif r.mode == "stay" then
        spawn_body(world, r, r.x, r.y, r.z, nil)
      elseif player then
        local x, y, z = world:position(player)
        if x then spawn_body(world, r, x, y + 0.5, z, player) end
      else
        log(string.format("roster: %s waits for its owner %s", r.name, tostring(r.owner)))
      end
    end
  end
  roster_save()
end

-- a player joined: his followers come to him (spawned, or found again)
local function roster_joined(world, p)
  if not roster.loaded then return end
  for _, r in ipairs(roster.list) do
    if r.out and r.mode == "follow" and r.owner == p.account then
      local ent = ent_of[r.name]
      if still_ours(world, ent) then
        drives[ent] = { player = p.player, trail = {} }
        log(string.format("roster: %s follows %s again", r.name, tostring(p.player)))
      else
        waiting[r.name] = { player = p.player, tries = 0 }  -- spawned once his body is in the world
      end
    end
  end
end

local function roster_cmd(world, args)
  local what = args[2]
  if what == "new" then  -- roster new <player> [guid]: a new NPC next to the player, following him
    local player = tonumber(args[3]) or 1
    local x, y, z = world:position(player)
    if not (roster.loaded and x) then emf.reply("roster: not ready / no player") return end
    local acc = world:account(player)
    local r = { name = "N" .. roster.next_n, guid = args[4] or HOUND, x = x, y = y, z = z + 3, mode = "follow",
      owner = acc, controllers = { acc }, names = { [acc] = players.name(world, player) }, out = false }
    roster.next_n = roster.next_n + 1
    roster.list[#roster.list + 1] = r
    if not roster.main[acc] then roster.main[acc] = r.name end
    spawn_body(world, r, x, y + 0.5, z, player)
    roster_save()
    emf.reply("roster: new " .. r.name)
  elseif what == "list" then
    for _, r in ipairs(roster.list) do
      local who = {}
      for _, a in ipairs(r.controllers or {}) do who[#who + 1] = a .. ((r.names or {})[a] and (" " .. r.names[a]) or "") end
      log(string.format("roster: %s | %s | %s | %s | leader %s | controllers [%s] | %s | spot %.1f %.1f %.1f", r.name,
        r.out and ("out as " .. tostring(ent_of[r.name])) or "put away", r.mode, r.fight or "Passive", tostring(r.owner), table.concat(who, "; "),
        r.guid, r.x or 0, r.y or 0, r.z or 0))
    end
    local mains = {}
    for a, n in pairs(roster.main) do mains[#mains + 1] = a .. " -> " .. n end
    log(string.format("roster: %d NPC(s); main companions %s; admins %s", #roster.list, table.concat(mains, ", "), table.concat(admins, ", ")))
    emf.reply("roster: listed in the log")
  elseif what == "away" or what == "delete" then  -- away <name>: body gone, kept on the list; delete: gone for good
    local r, i = find(args[3] or "")
    if not r then emf.reply("roster: no " .. tostring(args[3])) return end
    -- (owner 2026-11-20 09:35 "yes delete should refuse it") his items would go with him, an open chest would stay
    -- behind with no owner: delete refuses while his chest is open or he carries anything
    if what == "delete" and (inv.open[r.name] or inv.count(r.inv) > 0) then
      local why = inv.open[r.name] and "his chest is open: close it first" or
        string.format("he carries %d item(s): take them out of his chest first", inv.count(r.inv))
      log(string.format("roster: delete %s refused (%s)", r.name, why))
      emf.reply("roster: delete " .. r.name .. " refused: " .. why)
      return
    end
    -- (09:35) away with his chest open: without his body nothing could close it (E is on him, P is blocked): closed
    -- first, his items saved
    if inv.open[r.name] then inv.close(world, r, "put away") end
    local ent = ent_of[r.name]
    if ent then
      local x, y, z = world:position(ent)
      if x and r.mode == "stay" then r.x, r.y, r.z = x, y, z end
      drives[ent], name_of[ent] = nil, nil
      pcall(emf.destroy, world, ent)
    end
    ent_of[r.name], r.out = nil, false
    if what == "delete" then
      table.remove(roster.list, i)
      for a, n in pairs(roster.main) do if n == r.name then roster.main[a] = nil end end
    end
    roster_save()
    log(string.format("roster: %s %s", r.name, what == "away" and "put away" or "deleted"))
    emf.reply("roster: " .. what .. " " .. r.name)
  elseif what == "back" then  -- back <name> <player>: a stayer at its spot, a follower next to the player
    local r = find(args[3] or "")
    local player = tonumber(args[4]) or 1
    if not r then emf.reply("roster: no " .. tostring(args[3])) return end
    if r.out and still_ours(world, ent_of[r.name]) then emf.reply("roster: " .. r.name .. " is already out") return end
    if r.mode == "stay" then
      spawn_body(world, r, r.x, r.y + 0.5, r.z, nil)
    else
      local x, y, z = world:position(player)
      if not x then emf.reply("roster: no player " .. tostring(player)) return end
      r.owner = r.owner or world:account(player)
      spawn_body(world, r, x, y + 0.5, z, player)
    end
    roster_save()
    emf.reply("roster: back " .. r.name)
  elseif what == "give" or what == "share" or what == "unshare" then
    -- give <name> <player|account>: that player's alone; share: one more controller; unshare: one less
    local r = find(args[3] or "")
    if not r then emf.reply("roster: no " .. tostring(args[3])) return end
    -- "0x..." is an account, not a player entity (tonumber would read 0x...02 as player 2)
    local p = not tostring(args[4]):match("^0x") and tonumber(args[4]) or nil
    local acc = (p and world:account(p)) or args[4]
    if not (acc and acc:match("^0x%x+$")) then emf.reply("roster: no player/account " .. tostring(args[4])) return end
    r.names = r.names or {}
    if p then r.names[acc] = players.name(world, p) end
    if what == "give" then
      r.controllers, r.owner = { acc }, acc
      roster.main[acc] = r.name  -- a companion given to a player is his main one
    elseif what == "share" then
      if not controls(r, acc) then r.controllers[#r.controllers + 1] = acc end
    else
      for i = #r.controllers, 1, -1 do if r.controllers[i] == acc then table.remove(r.controllers, i) end end
    end
    roster_save()
    log(string.format("roster: %s %s %s: controllers now %s", r.name, what, acc, table.concat(r.controllers, ",")))
    emf.reply("roster: " .. what .. " done")
  elseif what == "here" then  -- here <name> <player>: moved onto the player's spot
    local r = find(args[3] or "")
    local player = tonumber(args[4]) or 1
    local ent = r and ent_of[r.name]
    local x, y, z = world:position(player)
    if not (ent and x) then emf.reply("roster: here <name> <player>") return end
    local okt = pcall(emf.teleport, world, ent, x, y, z, {})
    log(string.format("roster: %s moved onto player %s: %s", r.name, tostring(player), tostring(okt)))
    emf.reply("roster: here")
  elseif what == "main" then  -- main <name> <player|account>: that player's main companion (the one the functions use)
    local r = find(args[3] or "")
    local p = not tostring(args[4]):match("^0x") and tonumber(args[4]) or nil
    local acc = (p and world:account(p)) or args[4]
    if not (r and acc and acc:match("^0x%x+$")) then emf.reply("roster: main <name> <player|account>") return end
    roster.main[acc] = r.name
    roster_save()
    log(string.format("roster: %s is now the main companion of %s", r.name, acc))
    emf.reply("roster: main set")
  elseif what == "admin" then  -- admin add|remove <player|account>
    -- "0x..." is an account, not a player entity (tonumber would read 0x...02 as player 2)
    local p = not tostring(args[4]):match("^0x") and tonumber(args[4]) or nil
    local acc = (p and world:account(p)) or args[4]
    if not (acc and acc:match("^0x%x+$")) then emf.reply("roster: no player/account " .. tostring(args[4])) return end
    for i = #admins, 1, -1 do if admins[i] == acc then table.remove(admins, i) end end
    if args[3] == "add" then admins[#admins + 1] = acc end
    store.save("npc_admins", admins)
    log("roster: admins now " .. table.concat(admins, ", "))
    emf.reply("roster: admins changed")
  else
    emf.reply("roster: new <player> [guid] | list | away <name> | back <name> <player> | delete <name> | give/share/unshare <name> <player|account> | admin add|remove <player|account>")
  end
end

-- ===== E: the wheel ====================================================================================================
-- ===== Inventory (owner 2026-11-20 07:54/08:02) ===========================================================================
-- "Inventory" on his wheel spawns a large chest next to him with everything he carries; while it is open he is frozen
-- and his wheel offers only "Close Chest", which saves what is in it and removes the chest. It stays open until closed
-- (owner 2026-11-20 09:14: the 5-minute limit is gone, "the companion can't move so it should be safe"). Spawned entities are not saved by the game (a server restart loses them), so his
-- items live in his roster record (r.inv: {item, count, level, rarity}, in the world's data): the chest is only a view.
-- Filling: the items are put into the new chest one after another (inv.PUT_WAIT after the spawn, inv.RETRIES tries on a
-- fresh chest); r.inv is not touched until every put has answered. Open: every inv.SAVE_EVERY his record becomes the
-- chest's contents (core/bag.lua) plus what did not fit, saved when it changed, so a server restart loses at most that
-- much. Gear keeps its level and rarity (tested 2026-11-15, core/ground_loot.lua); a gem socketed into a weapon cannot be
-- put back into the socket (EMF's put knows only level and rarity), so it is kept as a separate item next to the weapon.
-- r.chest = {id, session, state} survives a script reload: the same server run takes the chest up again (an "open" one)
-- or removes it ("filling": r.inv still holds everything); a new server run has lost it (r.inv is the last save).
-- (owner 2026-11-20 09:25 "anyway to make this chest a gigantic chest instead of this small one?") the game's biggest
-- storage chest; before: Prop_Decoration_T5_Storage_40_Chest 0c667e7e-0fbd-4cb9-b58d-c3a20df7eaec (40 slots)
inv.CHEST = "bc834cbd-58f1-494a-97fb-0dc0248eb738"  -- Prop_Decoration_T6_Storage_72_Magic (72 slots)
inv.PUT_WAIT, inv.RETRIES, inv.SAVE_EVERY = 30, 3, 60
inv.SPOT = 1.5  -- m to his left (owner 09:31)

-- (owner 2026-11-20 08:19 "we'll have to test the unlocked parts") every gear piece in the chest: its level, rarity,
-- perks (PerkContainerNew: available/unlocked), durability-broken and gem, logged when the chest is filled and when it
-- closes, so one round trip shows what came back changed. `when`: "filled" or "closing".
function inv.log_gear(world, name, chest, when)
  local okset, setup = pcall(world.get, world, "InventorySetup", chest)
  if not (okset and setup) then return end
  local n = 0
  for i = 1, #(setup.linksEntities or {}) do
    local okv, invc = pcall(world.get, world, "Inventory", setup.linksEntities[i])
    for k = 1, #((okv and invc and invc.slots) or {}) do
      local sl = invc.slots[k]
      local pide = sl.data and sl.data.pide or 0
      if sl.id ~= 0 and pide ~= 0 then
        local st, pc, gs
        pcall(function() st = world:get("ItemState", pide) end)
        pcall(function() pc = world:get("PerkContainerNew", pide) end)
        pcall(function() gs = world:get("WeaponGemSlot", pide) end)
        n = n + 1
        log(string.format("inventory %s gear (%s): item %s level %s rarity %s perks %s/%s unlocked, gem %s, base damage %s, item state %s", name, when,
          tostring(sl.id), tostring(st and st.itemLevelUi), tostring(st and st.itemRarityUi), tostring(pc and pc.availablePerks),
          tostring(pc and pc.unlockedPerks), tostring(gs and gs.weaponGem and gs.weaponGem.id), tostring(st and st.baseDamageUi), tostring(st and st.itemState)))
      end
    end
  end
  if n == 0 then log(string.format("inventory %s gear (%s): none", name, when)) end
end

-- (owner 2026-11-20 08:20 "the companion can still be pushed around while the chest is open, anyway to stop that?")
-- pinned: the spot he stood on when the chest opened (or was taken up after a reload) is kept; anything that moves him
-- (a push) is undone the same tick, and his speed is set to nothing
function inv.pin(world, id)
  local c = inv.open[name_of[id] or ""]
  if not c then return end
  local p = world:get("CurrentTransform", id).transform.position
  if not c.pin or c.pin_id ~= id then c.pin, c.pin_id = { p.x, p.y, p.z }, id return end
  if p.x ~= c.pin[1] or p.y ~= c.pin[2] or p.z ~= c.pin[3] then
    p.x, p.y, p.z = c.pin[1], c.pin[2], c.pin[3]
    pcall(function() local v = world:get("Velocity", id).velocity v.x, v.y, v.z = 0, 0, 0 end)
    if not c.pushed then c.pushed = true log(string.format("inventory %s: pushed while the chest is open: put back", name_of[id])) end
  end
end

-- (owner 2026-11-20 08:22 "I wanted the "E" button to just say "Close" chest. it doesn't have to bring up the whole wheel
-- when the chest is open") his E prompt: "Talk" (the wheel), or while his chest is open the game's door "Close" text
-- and E closes the chest at once (on_talk). EMF's verbs have no "Close": inv.CLOSE_VERB is FNV-1a of the onToOffVerb
-- GUID of Base_Door's InteractionToggle (da5990c2-f8f0-413c-bb4d-fe057f4b4ca1), UNPROVEN: the same hash of its
-- offToOnVerb is not EMF's Open id, so the prompt may show "E" with no word (then the id is wrong).
inv.CLOSE_VERB = 0x3959A87F
-- (owner 2026-11-20 08:32 "the companion doesn't have an E button at all now": EMF refuses a new offer in the same
-- step the old one is taken off, "an earlier offer is still being taken off it: try again in a moment") the old offer
-- comes off now, the new one is made from the next steps on until EMF takes it (inv.want, F.tick)
inv.want = {}  -- entity -> { verb, at, tries }
function inv.prompt(world, id, open)
  -- (13:57) a pet (an animal) keeps the game's own E (EMF refuses ours there): its press opens his wheel (F.setup)
  if not world:get("DynamicEnemy01BehaviorState", id) and world:get("DynamicWildlife", id) then return end
  pcall(emf.offer_remove, world, id)
  inv.want[id] = { verb = open and inv.CLOSE_VERB or "Talk", at = world:tick() + 2, tries = 0 }
end
function inv.want_tick(world)
  local t = world:tick()
  for id, w in pairs(inv.want) do
    if not world:position(id) then
      inv.want[id] = nil
    elseif t >= w.at then
      local ok, res = pcall(emf.offer, world, id, { verb = w.verb }, function(ww, p, npc) on_talk(ww, p, npc) end)
      w.tries = w.tries + 1
      if ok and res then
        inv.want[id] = nil
        log(string.format("prompt: E on %s offered (%s) after %d try(s)", tostring(id),
          w.verb == "Talk" and "Talk" or string.format("verb 0x%08X", w.verb), w.tries))
      elseif w.tries >= 50 then
        inv.want[id] = nil
        log(string.format("prompt: E on %s could NOT be offered after %d tries (%s)", tostring(id), w.tries, tostring(res)))
      else
        w.at = t + 6
      end
    end
  end
end

-- his chest is open: he is frozen (drive_step)
function inv.frozen(id) local n = name_of[id] return n ~= nil and inv.open[n] ~= nil end

-- (owner 2026-11-20 08:57 "upgraded items don't appear to be preserved :( it definitely stripped the upgrades off it")
-- emf.put remakes gear with its level and rarity only: the upgrades (PerkContainerNew.unlockedPerks; 08:56:41 out
-- "perks 4/1", 08:56:47 back "4/0") are now kept in his record and written back onto the new piece once the chest is
-- filled (inv.apply_unlocked)
function inv.gear_list(world, chest)
  local out = {}
  local okset, setup = pcall(world.get, world, "InventorySetup", chest)
  if not (okset and setup) then return out end
  for i = 1, #(setup.linksEntities or {}) do
    local okv, invc = pcall(world.get, world, "Inventory", setup.linksEntities[i])
    for k = 1, #((okv and invc and invc.slots) or {}) do
      local sl = invc.slots[k]
      local pide = sl.data and sl.data.pide or 0
      if sl.id ~= 0 and pide ~= 0 then
        local st, pc
        pcall(function() st = world:get("ItemState", pide) end)
        pcall(function() pc = world:get("PerkContainerNew", pide) end)
        out[#out + 1] = { item = sl.id, pide = pide, level = st and st.itemLevelUi, rarity = st and st.itemRarityUi,
          unlocked = pc and pc.unlockedPerks or 0 }
      end
    end
  end
  return out
end

function inv.apply_unlocked(world, name, c)
  local gear = inv.gear_list(world, c.chest)
  for _, f in ipairs(c.fix or {}) do
    local done = false
    for _, g in ipairs(gear) do
      if not g.used and g.item == f.item and (f.level == nil or g.level == f.level) and (g.unlocked or 0) < f.unlocked then
        g.used = true
        local ok, err = pcall(function() world:get("PerkContainerNew", g.pide).unlockedPerks = f.unlocked end)
        local now
        pcall(function() now = world:get("PerkContainerNew", g.pide).unlockedPerks end)
        log(string.format("inventory %s: upgrades put back on item %s (level %s): unlocked %s -> %s%s", name, tostring(f.item),
          tostring(g.level), tostring(g.unlocked), tostring(now), ok and "" or (" FAILED: " .. tostring(err))))
        done = true
        break
      end
    end
    if not done then log(string.format("inventory %s: upgrades for item %s (level %s, %d unlocked) found no piece to go on", name, tostring(f.item), tostring(f.level), f.unlocked)) end
  end
  c.fix = nil
end

function inv.list(world, chest)
  -- only a chest that is there and set up is read (bag.entity_stacks gives an empty list for anything else, which
  -- would empty his record)
  if not world:position(chest) then return nil end
  local okset, setup = pcall(world.get, world, "InventorySetup", chest)
  if not (okset and setup) then return nil end
  inv.bag = inv.bag or require("core.bag")
  local ok, stacks = pcall(inv.bag.entity_stacks, world, chest)
  if not (ok and type(stacks) == "table") then return nil end
  local out = {}
  local gear = inv.gear_list(world, chest)
  for _, st in ipairs(stacks) do
    out[#out + 1] = { item = st.item, count = st.count, level = st.level, rarity = st.rarity }
    if st.gear then  -- (upgrades) from the matching piece
      for _, g in ipairs(gear) do
        if not g.used and g.item == st.item and g.level == st.level then
          g.used = true
          if (g.unlocked or 0) > 0 then out[#out].unlocked = g.unlocked end
          break
        end
      end
    end
    if st.gem and st.gem ~= 0 then out[#out + 1] = { item = st.gem, count = 1 } end  -- a socketed gem: kept on its own
  end
  return out
end

function inv.sig(list)
  local parts = {}
  for _, e in ipairs(list or {}) do parts[#parts + 1] = table.concat({ e.item, e.count, e.level or "", e.rarity or "", e.unlocked or "" }, ":") end
  table.sort(parts)
  return table.concat(parts, ",")
end

function inv.count(list) local n = 0 for _, e in ipairs(list or {}) do n = n + (e.count or 0) end return n end

-- his record from the open chest (plus what did not fit into it); false when the chest could not be read
function inv.snapshot(world, r, c)
  local list = inv.list(world, c.chest)
  if not list then return false end
  for _, e in ipairs(c.rest) do list[#list + 1] = e end
  local sig = inv.sig(list)
  if sig ~= c.sig then
    c.sig, r.inv = sig, list
    roster_save()
    log(string.format("inventory %s: saved %d stack(s), %d item(s)", r.name, #list, inv.count(list)))
  end
  return true
end

-- (owner 2026-11-20 12:12 "N1's chest spawned in the air... can you make that stay on the ground..?" / "it spawned too
-- close to the other chest I guess": at 12:11 N1 stood about 1 m above N2, likely on another chest, and his chest was
-- spawned at his height) the server probe (C++) looks for the ground under four places around him (his left first, as
-- the owner asked 09:31, then his right, behind, in front; inv.SPOT m): chest_ground.request / .answer (the game's ray
-- straight down). The first place whose ground is near his feet (GROUND_BELOW under to GROUND_ABOVE over: not on top
-- of another chest, not down a drop) gets the chest, on that ground; else the lowest ground found near him; without
-- an answer within GROUND_WAIT (no probe) his left at his height, as before.
inv.ground = {}  -- name -> { player, npc, rr, cands, feet, at }
inv.GROUND_BELOW, inv.GROUND_ABOVE, inv.GROUND_WAIT = 1.2, 0.4, 60
inv.open_chest = function(world, player, npc, rr)
  if not rr then say(world, player, "Not on the list: no inventory.") return end
  if inv.open[rr.name] or inv.ground[rr.name] then return end
  local x, y, z = world:position(npc)
  if not x then return end
  local yaw = 0
  pcall(function()
    local q = world:get("CurrentTransform", npc).transform.orientation
    yaw = math.atan(2 * (q.x * q.z + q.w * q.y), 1 - 2 * (q.x * q.x + q.y * q.y))
  end)
  local c, sn = math.cos(yaw), math.sin(yaw)
  local d = inv.SPOT
  -- forward = (sin yaw, cos yaw); his left = (-cos yaw, sin yaw)
  local cands = { { x - c * d, z + sn * d }, { x + c * d, z - sn * d }, { x - sn * d, z - c * d }, { x + sn * d, z + c * d } }
  local lines = {}
  for i, p in ipairs(cands) do lines[#lines + 1] = string.format("%s#%d %.3f %.3f %.3f", rr.name:gsub("%s", "_"), i, p[1], y, p[2]) end
  local f = emf.dir and io.open(emf.dir .. "\\chest_ground.request", "a")
  if f then f:write(table.concat(lines, "\n") .. "\n") f:close() end
  pcall(os.remove, emf.dir and (emf.dir .. "\\chest_ground.answer") or "")
  inv.ground[rr.name] = { player = player, npc = npc, rr = rr, cands = cands, feet = y, at = world:tick() + inv.GROUND_WAIT,
    key = rr.name:gsub("%s", "_") }
end

function inv.ground_tick(world)
  local text
  local f = emf.dir and io.open(emf.dir .. "\\chest_ground.answer", "r")
  if f then text = f:read("a") f:close() end
  local t = world:tick()
  for name, g in pairs(inv.ground) do
    local hits, all = {}, true
    for i = 1, #g.cands do
      local v = text and text:match(g.key:gsub("%p", "%%%0") .. "#" .. i .. " (%S+)")
      if v == nil then all = false else hits[i] = tonumber(v) end
    end
    if all or t >= g.at then
      inv.ground[name] = nil
      local pick, py, how
      for i = 1, #g.cands do
        local h = hits[i]
        if h and h >= g.feet - inv.GROUND_BELOW and h <= g.feet + inv.GROUND_ABOVE then pick, py, how = i, h, "ground" break end
      end
      if not pick then
        for i = 1, #g.cands do
          local h = hits[i]
          if h and h >= g.feet - 3 and h <= g.feet + 1 and (not py or h < py) then pick, py, how = i, h, "lowest ground" end
        end
      end
      if not pick then pick, py, how = 1, g.feet, all and "no ground found: his height" or "no answer: his height" end
      if text then pcall(os.remove, emf.dir .. "\\chest_ground.answer") end
      log(string.format("inventory %s: chest place %d of 4 (%s): ground answers %s, his feet %.2f", name, pick, how,
        (function() local o = {} for i = 1, #g.cands do o[i] = tostring(hits[i] and string.format("%.2f", hits[i]) or "-") end return table.concat(o, "/") end)(),
        g.feet))
      if g.rr and find(g.rr.name) and not inv.open[g.rr.name] then
        inv.open_at(world, g.player, g.npc, g.rr, g.cands[pick][1], py, g.cands[pick][2])
      end
    end
  end
end

function inv.open_at(world, player, npc, rr, cx, y, cz)
  local px, _, pz = world:position(player)
  local oks, chest = pcall(emf.spawn, world, inv.CHEST, cx, y, cz, { CustomPlayerString = { stringId = inv.name_key(rr.name) } })
  if not (oks and chest and chest ~= 0) then  -- (names) without the label rather than no chest
    log(string.format("inventory %s: the chest with his name label was refused (%s): spawned without it", rr.name, tostring(chest)))
    oks, chest = pcall(emf.spawn, world, inv.CHEST, cx, y, cz)
  end
  if not (oks and chest and chest ~= 0) then
    log(string.format("inventory %s: the chest could not be spawned (%s)", rr.name, tostring(chest)))
    say(world, player, rr.name .. ": The chest could not be opened.")
    return
  end
  local okr, rule = pcall(emf.hit_rule, { to = chest, cancel = true })  -- no damage to it
  local t = world:tick()
  local queue = {}
  for _, e in ipairs(rr.inv or {}) do queue[#queue + 1] = { item = e.item, count = e.count, level = e.level, rarity = e.rarity, unlocked = e.unlocked, tries = 0 } end
  inv.open[rr.name] = { chest = chest, player = player, t0 = t, state = "filling", queue = queue, rest = {}, at = t + inv.PUT_WAIT,
    rule = okr and rule or nil }
  rr.chest = { id = chest, session = emf.session(), state = "filling" }
  roster_save()
  inv.prompt(world, npc, true)
  log(string.format("inventory %s: chest %s opened at %.1f %.1f %.1f (%.1f m from the player) with %d stack(s), %d item(s) to put in",
    rr.name, tostring(chest), cx, y, cz, px and math.sqrt((cx - px) ^ 2 + (cz - pz) ^ 2) or -1, #queue, inv.count(rr.inv)))
  say(world, player, rr.name .. ": Inventory open.")
end

-- why: "the player" or "he died"
function inv.close(world, r, why, by)  -- by: the player who closed it (the notice goes to him)
  local c = inv.open[r.name]
  if not c then return end
  local gone = not world:position(c.chest)  -- removed by something else: his record keeps the last save
  if gone then log(string.format("inventory %s: chest %s is gone; his record keeps the last save", r.name, tostring(c.chest))) end
  if not gone then pcall(inv.log_gear, world, r.name, c.chest, "closing") end
  -- within SAVE_EVERY of the filling the new gear may not be set up yet: his record from before the opening stays
  local fresh = c.ready_t and world:tick() < c.ready_t
  if fresh then log(string.format("inventory %s: closed right after the filling: his record from before stays", r.name)) end
  if c.state == "open" and not gone and not fresh and not inv.snapshot(world, r, c) then
    log(string.format("inventory %s: the chest could not be read: it stays open for now", r.name))
    return false
  end
  -- still filling: r.inv still holds everything (nothing saved from the chest yet)
  if c.rule then pcall(emf.hit_rule_remove, c.rule) end
  pcall(emf.destroy, world, c.chest)
  inv.open[r.name] = nil
  r.chest = nil
  roster_save()
  if ent_of[r.name] then inv.prompt(world, ent_of[r.name], false) end
  log(string.format("inventory %s: chest %s closed (%s): %d stack(s), %d item(s) kept", r.name, tostring(c.chest), why,
    #(r.inv or {}), inv.count(r.inv)))
  local p = by or c.player  -- (09:17) after a log off and back on c.player is an old entity id
  if p and world:position(p) then say(world, p, r.name .. ": Inventory closed" .. (why == "the player" and "." or " (" .. why .. ").")) end
  return true
end

inv.close_chest = function(world, player, npc, rr)
  if rr then inv.close(world, rr, "the player", player) end
end

-- (owner 2026-11-20 09:21 "is there a way to make a check so ONLY the player who owns the companion can open the
-- chest?") the game has no owner lock on a chest a mod spawns; when anyone else opens it (the game's
-- InteractionAcceptedEvent, guest = the player, host = the chest) it is closed at once: everything goes back into his
-- record and the chest is gone before they can take anything
function inv.on_accept(world, e)
  local host, guest = rawget(e, "hostEntityId"), rawget(e, "guestEntityId")
  for name, c in pairs(inv.open) do
    if c.chest == host then
      local r = find(name)
      local acc = guest and world:account(guest)
      if r and r.owner and acc ~= r.owner then
        log(string.format("inventory %s: chest %s opened by player %s (account %s), not the owner: closed", name, tostring(host),
          tostring(guest), tostring(acc)))
        inv.close(world, r, "someone else opened it")
        if guest then say(world, guest, name .. "'s chest: only the companion's owner can open it.") end
      else  -- (09:24) proof the game's open event reaches us for this chest (the check above rests on it)
        log(string.format("inventory %s: chest %s opened by its owner (player %s)", name, tostring(host), tostring(guest)))
      end
      return
    end
  end
end

-- every tick: fill new chests, keep open ones saved, pin him (09:21: "it needs to be pinned for all players so if I log
-- off no one can mess with it")
function inv.tick(world)
  local t = world:tick()
  for name, c in pairs(inv.open) do
    local r = find(name)
    if ent_of[name] then pcall(inv.pin, world, ent_of[name]) end
    if not r then
      inv.open[name] = nil
    elseif c.state == "filling" then
      if t >= c.at and not c.busy then
        local e = table.remove(c.queue, 1)
        if not e then
          -- (2026-11-20 08:24:10 in game: read at once, a fresh gear piece showed level 0 / rarity 0 / damage 0, item
          -- state 64; right 0.5 s later) the first save waits SAVE_EVERY after the filling
          c.state, c.ready_t = "open", t + inv.SAVE_EVERY
          r.chest.state = "open"
          roster_save()
          log(string.format("inventory %s: chest filled%s", name, #c.rest > 0 and string.format(" (%d stack(s) did not fit: kept in his record)", #c.rest) or ""))
          pcall(function()  -- (names) 0 here: the server did not know his name when the chest was spawned
            local k = world:get("CustomPlayerString", c.chest)
            k = k and k.stringId
            if type(k) ~= "number" and k then k = k.value end
            log(string.format("inventory %s: name label key on the chest %s (his name's 0x%016X)", name,
              k == nil and "none" or (math.type(k) == "integer" and string.format("0x%016X", k) or tostring(k)), inv.name_key(name)))
          end)
        else
          c.busy = true
          local opts = (e.level or e.rarity) and { level = e.level, rarity = e.rarity } or nil
          local okp = pcall(emf.put, world, c.chest, e.item, e.count, function(w, added)
            added = tonumber(added) or 0
            c.busy = false
            if added > 0 and (e.unlocked or 0) > 0 then  -- (upgrades) written back once the piece reads right
              c.fix = c.fix or {}
              c.fix[#c.fix + 1] = { item = e.item, level = e.level, unlocked = e.unlocked }
            end
            if added >= e.count then return end
            e.count = e.count - added
            if added == 0 and e.tries < inv.RETRIES then  -- a fresh chest refuses at first: again in a moment
              e.tries = e.tries + 1
              table.insert(c.queue, 1, e)
              c.at = world:tick() + inv.PUT_WAIT
            else
              c.rest[#c.rest + 1] = { item = e.item, count = e.count, level = e.level, rarity = e.rarity, unlocked = e.unlocked }
              log(string.format("inventory %s: %d of item %s did not fit into the chest (kept in his record)", name, e.count, tostring(e.item)))
            end
          end, opts)
          if not okp then
            c.busy = false
            c.rest[#c.rest + 1] = { item = e.item, count = e.count, level = e.level, rarity = e.rarity, unlocked = e.unlocked }
            log(string.format("inventory %s: emf.put refused item %s (kept in his record)", name, tostring(e.item)))
          end
        end
      end
    else
      if c.ready_t and t >= c.ready_t and not c.gear_logged then
        c.gear_logged = true
        if c.fix then pcall(inv.apply_unlocked, world, name, c) end
        pcall(inv.log_gear, world, name, c.chest, "filled")
        inv.snapshot(world, r, c)
      elseif (not c.ready_t or t >= c.ready_t) and (t - c.t0) % inv.SAVE_EVERY == 0 then
        inv.snapshot(world, r, c)
      end
    end
  end
end

-- (a script reload) his chest of this server run: an open one is taken up again, a half-filled one removed (r.inv still
-- holds everything); one of another server run is gone with it (r.inv is the last save)
inv.adopt = function(world, r)
  local ch = r.chest
  if not (type(ch) == "table" and ch.id) then r.chest = nil return end
  if ch.session ~= emf.session() or not world:position(ch.id) then
    log(string.format("inventory %s: the chest of an earlier server run is gone; his record keeps %d item(s)", r.name, inv.count(r.inv)))
    r.chest = nil
    return
  end
  if ch.state ~= "open" then
    pcall(emf.destroy, world, ch.id)
    r.chest = nil
    log(string.format("inventory %s: a half-filled chest %s removed after a reload (his record keeps everything)", r.name, tostring(ch.id)))
    return
  end
  local okr, rule = pcall(emf.hit_rule, { to = ch.id, cancel = true })
  inv.open[r.name] = { chest = ch.id, player = player_of(world, r.owner), t0 = world:tick(), state = "open", queue = {}, rest = {},
    rule = okr and rule or nil }
  log(string.format("inventory %s: chest %s taken up again after a reload", r.name, tostring(ch.id)))
end

-- E opens a wheel on the presser's own screen (FlameKit's game side, channel flamekit/npcwheel). The server checks who
-- may command the companion, again at the pick. There is no other way (a game without FlameKit gets a notice).
-- (owner 2026-11-18 20:09/20:11) "Attack" opens a second wheel with the fight modes: Passive, Defensive, Aggressive,
-- Healing. The mode is kept in the roster (r.fight; a companion without one is Passive) until the player changes it.
-- The game side sends back the label it showed, so a pick is matched by its label.
local WHEEL = "npcwheel"
local WHEEL_LABELS = { "Follow me", "Stay here", "Attack", "Inventory", "Put away" }
inv.WHEEL = { "Close Chest" }  -- (owner 08:02) while his chest is open the wheel offers only this
local FIGHT_MODES = { "Passive", "Defensive", "Aggressive", "Healing" }

local function refuse(world, player, rr)
  local who = {}
  for _, a in ipairs(rr.controllers or {}) do who[#who + 1] = (rr.names or {})[a] or "someone else" end
  say(world, player, rr.name .. ": " .. (#who > 0 and ("This companion belongs to " .. table.concat(who, ", ") .. ".") or "This companion is not yours."))
end


local function do_follow(world, player, npc, rr)
  drives[npc] = { player = player, trail = {} }
  calm(world, npc)
  log(string.format("E: %s follows player %s", tostring(npc), tostring(player)))
  if rr then rr.mode, rr.owner = "follow", world:account(player) roster_save() end
  say(world, player, (rr and (rr.name .. ": ") or "") .. "Following you.")
end

local function do_stay(world, player, npc, rr)
  drives[npc] = nil
  local x, y, z = world:position(npc)
  stay_at(world, npc, x, y, z)
  log(string.format("E: %s stays at %.1f %.1f %.1f", tostring(npc), x, y, z))
  if rr then rr.mode, rr.x, rr.y, rr.z = "stay", x, y, z roster_save() end
  say(world, player, (rr and (rr.name .. ": ") or "") .. "Staying here.")
end

local function do_away(world, player, npc, rr)
  if not rr then say(world, player, "Not on the list: cannot be put away.") return end
  local x, y, z = world:position(npc)
  if x and rr.mode == "stay" then rr.x, rr.y, rr.z = x, y, z end
  drives[npc], name_of[npc] = nil, nil
  pcall(emf.destroy, world, npc)
  ent_of[rr.name], rr.out = nil, false
  roster_save()
  log(string.format("E: %s put away", rr.name))
  say(world, player, rr.name .. ": Put away.")
end

-- the Attack wheel: the four fight modes, the current one named in the title
local function do_attack_menu(world, player, npc, rr)
  if not rr then say(world, player, "Not on the list: no fight modes.") return end
  local oks, sent = pcall(emf.net.send_to, world, player, WHEEL, emf.json.encode({ op = "wheel", npc = npc,
    title = rr.name .. ": Attack (now " .. (rr.fight or "Passive") .. ")", labels = FIGHT_MODES }))
  log(string.format("E: attack wheel for %s (%s, now %s) sent to player %s: %s", tostring(npc), rr.name, rr.fight or "Passive",
    tostring(player), tostring(oks and sent)))
end

-- a fight mode picked: kept in the roster
local function set_fight(world, player, npc, rr, mode)
  if not rr then return end
  local was = rr.fight or "Passive"
  rr.fight = mode
  roster_save()
  log(string.format("fight: %s (%s) %s -> %s (player %s)", rr.name, tostring(npc), was, mode, tostring(player)))
  say(world, player, rr.name .. ": " .. mode .. ".")
end

on_talk = function(world, player, npc)
  log(string.format("E pressed on %s by player %s", tostring(npc), tostring(player)))
  local rr = name_of[npc] and find(name_of[npc])
  local account = world:account(player)
  if rr and not may_command(rr, account) then
    log(string.format("E: %s refused for %s (controllers %s)", rr.name, tostring(account), table.concat(rr.controllers or {}, ",")))
    refuse(world, player, rr)
    return
  end
  if rr and inv.open[rr.name] then  -- (owner 08:22) E closes his open chest at once, no wheel
    inv.close(world, rr, "the player", player)
    return
  end
  local okp, ver = pcall(emf.net.peer, world, player, WHEEL)
  if not (okp and (tonumber(ver) or 0) > 0) then
    say(world, player, "This companion needs FlameKit in your game.")
    return
  end
  local oks, sent = pcall(emf.net.send_to, world, player, WHEEL, emf.json.encode({ op = "wheel", npc = npc,
    title = rr and rr.name or "Companion", labels = (rr and inv.open[rr.name]) and inv.WHEEL or WHEEL_LABELS }))
  log(string.format("E: wheel for %s sent to player %s: %s", tostring(npc), tostring(player), tostring(oks and sent)))
end

-- "Call my companion" (P, the Experimental panel, and every return after a put-away): the main companion's old body,
-- if any (alive, dead or stuck anywhere), is removed and a fresh one is spawned beside the player, following him
local function on_call(world, from)
  local player, account = from.player, from.account
  local x, y, z = world:position(player)
  if not x then return end
  local r = roster.main[account] and find(roster.main[account])
  if not r or not controls(r, account) then
    if r then roster.main[account] = nil roster_save() end
    say(world, player, "You have no companion yet.")
    return
  end
  if inv.open[r.name] then  -- (owner 2026-11-20 08:13) no call while his chest is open
    say(world, player, r.name .. ": Close the chest first.")
    log(string.format("call: %s refused for %s: his chest is open", r.name, tostring(account)))
    return
  end
  local old = ent_of[r.name]
  if old then
    drives[old], name_of[old] = nil, nil
    pcall(emf.destroy, world, old)
    ent_of[r.name] = nil
  end
  r.mode, r.owner = "follow", account
  -- 0.3 m to the player's right (his facing: forward = (sin yaw, cos yaw), right = (cos yaw, -sin yaw))
  local pyaw
  pcall(function()
    local o = world:get("CurrentTransform", player).transform.orientation
    local yaw = math.atan(2 * (o.x * o.z + o.w * o.y), 1 - 2 * (o.x * o.x + o.y * o.y))
    x, z = x + math.cos(yaw) * 0.3, z - math.sin(yaw) * 0.3
    pyaw = yaw
  end)
  local id = spawn_body(world, r, x, y + 0.5, z, player)
  -- his body turned the way the player faces, now and again when he is set up half a second later (bring_to_life)
  if id and pyaw then
    r.face_yaw = pyaw
    pcall(function()
      local o = world:get("CurrentTransform", id).transform.orientation
      o.x, o.y, o.z, o.w = 0, math.sin(pyaw / 2), 0, math.cos(pyaw / 2)
    end)
  end
  roster_save()
  -- every time he spawns beside the player: "Companion has spawned near you!"
  status(world, player, "companion_away", nil)
  status(world, player, "companion_stuck", nil)
  pcall(function() require("features.chat").notice_to(world, player, "Companion has spawned near you!", "#8cd2ff", 5) end)
  log(string.format("call: %s (main of %s) respawned on player %s as %s (old body %s)", r.name, account,
    tostring(player), tostring(id), tostring(old)))
end

local function on_pick(world, from, data)
  local okd, m = pcall(emf.json.decode, data)
  if okd and type(m) == "table" and m.op == "call" then return on_call(world, from) end
  if not (okd and type(m) == "table" and m.op == "pick") then return end
  local npc, player = tonumber(m.npc), from.player
  local rr = npc and name_of[npc] and find(name_of[npc])
  log(string.format("wheel: player %s picked %s (%s) for %s", tostring(player), tostring(m.choice), tostring(m.label), tostring(npc)))
  if not (npc and world:position(npc)) then return end
  if rr and not may_command(rr, from.account) then refuse(world, player, rr) return end
  local label = type(m.label) == "string" and m.label or ""
  local act = ({ ["Follow me"] = do_follow, ["Stay here"] = do_stay, ["Attack"] = do_attack_menu, ["Put away"] = do_away,
    ["Inventory"] = inv.open_chest, ["Close Chest"] = inv.close_chest })[label]
  if rr and inv.open[rr.name] and label ~= "Close Chest" then act = nil end  -- an old wheel: only "Close Chest" now
  for _, mode in ipairs(FIGHT_MODES) do
    if label == mode then act = function(w, pl, n, r) set_fight(w, pl, n, r, mode) end end
  end
  if not act then return end
  local ok, err = pcall(act, world, player, npc, rr)
  if not ok then log("wheel: failed: " .. tostring(err)) say(world, player, "Cannot do that (see the server's log).") end
end

-- ===== Fight (owner 2026-11-18 20:09/20:11/20:47, 2026-11-19 09:03/09:17) =============================================
-- The fight modes (the wheel's Attack menu): Passive and Healing never attack (Healing's healing comes later);
-- Defensive and Aggressive run the attack sequence (drive_fight, below). Threats: monsters that hit him or his player
-- (the hit handler). Aggressive also looks at every monster within FIGHT_RANGE of the player (a scan over the world's
-- entities, spread over steps within SCAN_BUDGET: the world has some 37,000 entities and EMF pauses FlameKit when one
-- call runs over 250 ms). FIGHT_RANGE is also the radius he fights in (owner 2026-11-19 10:40 "the dog should stay
-- centered on me within my radius and kill anything in it"; it replaced the 30 m leash). fight_watch clears old threats and
-- logs his health and defence data. His maximum health: Health.dataStorage[3] (2026-11-18 20:28/20:34: [1] goes down
-- when he is hurt, [3] and [8] stay at the maximum).
local FIGHT_RANGE = 20                -- (owner 2026-11-19 13:58: 20 m, was 15)
local SCAN_BUDGET, SCAN_MAX = 0.03, 6000
local threats = {}         -- companion entity -> { monster entity -> tick of its last hit }
local mscan = nil          -- the scan under way: { list, i, found = { player -> { monster ids } }, steps, t }
local near_monsters = {}   -- player entity -> { monster ids within FIGHT_RANGE } (the last finished scan)
local scan_logged = -3600  -- the first scan is logged too
local clock_ok = pcall(function() return os.clock() end)

local function fight_mode(cid)
  local r = name_of[cid] and find(name_of[cid])
  return r and r.fight or "Passive"
end

-- a monster: the monster AI, not one of ours, a monster faction (not 7 Player, 8, 11 PlayerAlly), and health
-- (NetworkHealth; owner 2026-11-19 19:18 "#1 for sure": 171975, a part of a monster with no health and a constant
-- 20 m/s speed, held him for a minute while 171973 beside it hit him)
local function is_monster(world, id)
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
local function describe(world, id)
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

local function monster_alive(world, id)
  if not world:position(id) then return false end
  local ok, hp = pcall(function() return world:get("NetworkHealth", id).health end)
  return ok and hp ~= nil and hp > 0  -- no health: not a monster (is_monster), so not alive either
end

-- (owner 21:20 "does the dog have any armor or defensive numbers, he seemed to die pretty quick", 21:21 "lets just do
-- more logging first") per companion: what he took and dealt, summed per 10 s while it goes on (fight_watch logs it)
local fight_sums = {}  -- companion entity -> { took = {type -> amount}, hits_on = n, from = {attacker -> true}, dealt, hits_by }
local function sum_of(cid)
  local f = fight_sums[cid]
  if not f then f = { took = {}, hits_on = 0, from = {}, dealt = 0, hits_by = 0 } fight_sums[cid] = f end
  return f
end

-- the hit handler: a monster's hit on a following companion or on his player is a threat for that companion
local function note_threat(world, hit)
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
local function monster_scan_step(world)
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
local function note_my_hit(world, hit)
  local hh = drives[hit.attacker]
  if not hh then return end
  hh.my_hits = hh.my_hits or {}
  if #hh.my_hits < 20 then hh.my_hits[#hh.my_hits + 1] = { tg = hit.target, t = world:tick(), obj = not is_monster(world, hit.target) } end
end

-- once a second: old threats go (dead, gone, or more than FIGHT_RANGE from the player), and his health slots are logged
-- once per body and again the first time he is hurt ([1] his health, [3] his maximum). (The step 2 "would attack"
-- lines are gone: drive_fight's "attacks / bite / lunge / stops fighting" lines replace them.)
local function fight_watch(world)
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
local function action_of(world, id)
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
local FIGHT_BITE, FIGHT_LUNGE, ATTACK_MAX = 2.5, 4, 180
local RAY_WAIT = 2                    -- ticks before a candidate's ray result is read (the C++ casts every step)
local PICK_TRIES, PICK_EVERY = 3, 60  -- (owner 09:17 "3 tries ... might be too few, but we'll start there")
local MOVE_STEP, SIDE = 60, 2
local NO_HIT = 120                    -- (owner 2026-11-18 21:35 "I'd drop that to like 2 seconds")
-- (owner 2026-11-19 11:17 "get the facing fix in asap") between attacks he turns toward it, TURN radians a tick at
-- most (half a turn in 0.1 s), and attacks only when he faces it within FACE_OK degrees
local TURN, FACE_OK = math.rad(30), 15
-- (owner 2026-11-19 14:52 yes; bats at up to 6 m/s moved 2.0-2.4 m in the 0.4 s before a lunge's hit lands) a target
-- faster than FAST m/s that is out of bite reach: he stands at lunge reach facing it and lunges when it slows down
-- (a bat slows when it swoops in); while he waits, no "can't deliver attacks"
local FAST = 3
-- (owner 2026-11-19 16:32 "yeah lets see how that goes"; floating monsters 0.7-0.8 m above him: bites and lunges
-- went under them) a target HIGH m or more above him: he jumps into the attack (upward speed only, the attack's own
-- forward move is kept), as soon as the attack has started
local HIGH = 0.5

local function speed_of(world, m)
  local v = 0
  pcall(function() local w = world:get("Velocity", m).velocity v = math.sqrt(w.x * w.x + w.y * w.y + w.z * w.z) end)
  return v
end

-- he turns toward (fx, fz) by TURN at most this tick; returns how many degrees he is still off afterwards
local function turn_toward(world, id, fx, fz)
  local q = world:get("CurrentTransform", id).transform.orientation
  local yaw = math.atan(2 * (q.x * q.z + q.w * q.y), 1 - 2 * (q.x * q.x + q.y * q.y))
  local diff = (math.atan(fx, fz) - yaw + math.pi) % (2 * math.pi) - math.pi
  local step = math.max(-TURN, math.min(TURN, diff))
  if math.abs(diff) > 0.01 then face(world, id, yaw + step) end
  return math.deg(diff - step)
end
local SKIP_TICKS = 1200

local function fight_candidates(world, cid, h, mode, px, py, pz, nx, ny, nz)
  local list, seen = {}, {}
  local skip = h.fight_skip or {}
  local now = world:tick()
  for m, untill in pairs(skip) do
    local hit_t = threats[cid] and threats[cid][m]
    if now > untill then skip[m] = nil
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
local function face_info(world, id, tg, nx, ny, nz, mx, my, mz)
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

-- ===== Healing (owner 2026-11-19 19:21-21:01) ===========================================================================
-- The game gives him no mana and no health recharge (log 19:21: only Health and Stamina), so his mana is FlameKit's own
-- number (owner 19:25 "I would give him 800 mana and see how that works?"), refilling in every mode. A heal goes through
-- the game's attribute code (emf.attribute_add "health": stops at the maximum, not a hit) and plays Wolf Shout
-- (combatData.selectedAttackIndex 2 -> the C++ starts 0x89A1BC53; owner 20:59 "I want Wolf Shout", 21:01 "every heal
-- would be a good queue that its happening"). Who and when (owner 20:35 "yes that would be good"; 22:04 "when he's in
-- heal mode, he should just always heal me to full, when he's in attack or defense I meant more like when all the
-- attack sequences are all done, he should do full heals on himself and me, but can wait until all attack sequences
-- are done"):
--   Healing: the player (within FIGHT_RANGE) up to full, always; else himself below HEAL_BELOW;
--   Defensive / Aggressive: in an attack sequence only himself, below HEAL_BELOW_FIGHT (the mana lasts the fight); with
--   no attack sequence going on, the player and then himself up to full;
--   Passive: no heals; a slow recovery once he has not been hit for RECOVER_AFTER (no mana, no shout).
-- Not while one of his attacks plays (the shout would cut it). Logs "heal <name>: ...".
local MANA_MAX, MANA_REFILL = 800, 10                     -- refill: a second
local HEAL_PART, HEAL_COST, HEAL_GAP = 0.25, 200, 240     -- 25 % of the target's maximum, 200 mana, 4 s apart
local HEAL_BELOW, HEAL_BELOW_FIGHT = 0.6, 0.4
local HEAL_FULL = 0.99                                    -- "full": a heal only when 1 % or more is missing
local RECOVER_AFTER, RECOVER_PART = 600, 0.02             -- Passive: 10 s without a hit, then 2 % of his maximum a second
local mana_of = {}                                        -- companion name -> mana
-- (owner 2026-11-19 22:09 "is there way to add an healing spakle animations?") the game's heal effects (VFX templates),
-- for the console preview "flamekit.npc healfx <n>" (spawned on the player for 10 s)
local HEAL_FX = {
  { "VFX_Resource_Increase_Health", "2c411630-8a38-41a3-b3d2-a263609a1bdb" },
  { "VFX_Resource_Increase_Health_NoSound", "b8e9aca9-8713-4c4c-b51c-1591e74873b4" },
  { "VFX_Enemy_Skeleton_Melee_Elite_Heal_Ally_Player_Companion", "35183e7f-6b43-45da-a58c-c057f0c2f82e" },
  { "VFX_Enemy_Skeleton_Melee_Elite_Heal_Ally", "100772b0-a866-4d80-b9a8-a6052ccd0149" },
  { "VFX_Skill_Martyr_Heal", "21443035-d89f-40c5-bf61-009b8aaa413a" },
  { "VFX_Ability_Casting_Heal_Channel", "af4436da-8e80-436a-aa35-5cdf1f0b994e" },
  { "VFX_Spell_ChainHeal_SourceTarget_player", "fc4f8028-078d-4051-8cf1-33ddb08e72a6" },
  { "VFX_Spell_ChainHeal_SourceTarget_NoTarget", "c15e5bc4-6dc7-4b86-a27c-91d1db7cd5aa" },
}
local heal_fx_shown = {}
local SHOUT_TICKS = 90                                    -- the shout plays this long before his next attack

drive_heal = function(s)
  local world, id, h, t, a = s.world, s.id, s.h, s.t, s.a
  local name = tostring(name_of[id] or id)
  local mode = fight_mode(id)
  local m = math.min(MANA_MAX, (mana_of[name] or MANA_MAX) + MANA_REFILL / 60)
  mana_of[name] = m
  local hp, hmax
  pcall(function() local d = world:get("Health", id).dataStorage hp, hmax = tonumber(d[1]), tonumber(d[3]) end)
  if not (hp and hmax and hp > 0) then return end
  if mode == "Passive" then
    if hp < hmax and t - (h.hit_t or -1e9) >= RECOVER_AFTER then
      if t % 60 == 0 then
        local okr, res = pcall(emf.attribute_add, world, id, "health", math.ceil(hmax * RECOVER_PART))
        if not h.recover_said then
          h.recover_said = true
          log(string.format("heal %s: recovers (Passive, not hit for %d s): %d/%d, +%d a second%s", name, RECOVER_AFTER / 60,
            hp, hmax, math.ceil(hmax * RECOVER_PART), (okr and res) and "" or " (could not add health: " .. tostring(res) .. ")"))
        end
      end
    elseif h.recover_said and hp >= hmax then
      h.recover_said = nil
      log(string.format("heal %s: recovered (%d/%d)", name, hp, hmax))
    end
    return
  end
  if t - (h.heal_t or -1e9) < HEAL_GAP then return end
  if not h.fight_init then return end  -- the fight's first step clears any move asked for: the shout would be lost
  local who, whp, wmax, whom
  local php, pmax = tonumber(emf.attribute(world, h.player, "health")), tonumber(emf.attribute(world, h.player, "max_health"))
  local px, py, pz = world:position(h.player)
  local near = px and (px - s.nx) ^ 2 + (py - s.ny) ^ 2 + (pz - s.nz) ^ 2 <= FIGHT_RANGE ^ 2
  local player_hurt = php and pmax and php > 0 and php < pmax * HEAL_FULL and near
  if mode == "Healing" then
    if player_hurt then
      who, whp, wmax, whom = h.player, php, pmax, "the player"
    elseif hp < hmax * HEAL_BELOW then
      who, whp, wmax, whom = id, hp, hmax, "himself"
    end
  elseif mode == "Defensive" or mode == "Aggressive" then
    if h.atk then
      if hp < hmax * HEAL_BELOW_FIGHT then who, whp, wmax, whom = id, hp, hmax, "himself" end
    elseif player_hurt then
      who, whp, wmax, whom = h.player, php, pmax, "the player"
    elseif hp < hmax * HEAL_FULL then
      who, whp, wmax, whom = id, hp, hmax, "himself"
    end
  end
  if not who then return end
  if m < HEAL_COST then
    if not h.nomana_said then
      h.nomana_said = true
      log(string.format("heal %s: would heal %s (%d/%d) but has %d mana of %d needed", name, whom, whp, wmax, math.floor(m), HEAL_COST))
    end
    return
  end
  h.nomana_said = nil
  if h.atk and h.atk.atk then return end  -- one of his attacks is playing: after it
  local okq, asked = pcall(function() return (tonumber(a.combatData.selectedAttackIndex) or 255) ~= 255 end)
  if okq and asked then return end
  local amount = math.ceil(wmax * HEAL_PART)
  local okh, res = pcall(emf.attribute_add, world, who, "health", amount)
  pcall(function() a.combatData.selectedAttackIndex = 2 end)  -- Wolf Shout
  mana_of[name] = m - HEAL_COST
  h.heal_t = t
  -- (owner 2026-11-19 22:18 "when the dog heals himself he can do the effect, when he heals the player he can do the
  -- effect on himself and me to highly the heal") the game's health-gain effect (HEAL_FX 1, the only one the owner saw)
  if okh and res then
    local function sparkle(e)
      local x, y, z = world:position(e)
      if not x then return end
      local oks, fid = pcall(emf.spawn, world, HEAL_FX[1][2], x, y, z)
      if oks and fid and fid ~= 0 then heal_fx_shown[#heal_fx_shown + 1] = { id = fid, at = t + 600 } end
    end
    sparkle(id)
    if who == h.player then sparkle(h.player) end
  end
  -- (owner 2026-11-19 21:29 "can you add a notice message that says Companion heals you for <number>!")
  if who == h.player and okh and res then say(world, h.player, string.format("Companion heals you for %d!", amount), "#5ad25a") end  -- green (owner 21:31)
  log(string.format("heal %s: heals %s +%d (%d/%d before; %s mode); mana %d -> %d of %d; Wolf Shout%s", name, whom, amount, whp, wmax,
    mode, math.floor(m), math.floor(m - HEAL_COST), MANA_MAX, (okh and res) and "" or " (could not add health: " .. tostring(res) .. ")"))
end

drive_fight = function(s)
  local world, id, h, a, t = s.world, s.id, s.h, s.a, s.t
  local cd = a.combatData
  local name = tostring(name_of[id] or id)
  local px, py, pz, nx, ny, nz = s.px, s.py, s.pz, s.nx, s.ny, s.nz
  if not h.fight_init then
    h.fight_init = true
    pcall(function() cd.selectedAttackIndex = 255 end)
  end
  local function clear_target()
    pcall(function() if cd.lastTargetId ~= 0 then cd.lastTargetId = 0 end end)
  end
  local function the_end(why)
    if h.atk then log(string.format("fight %s: the attack sequence ends: %s", name, why)) end
    h.atk = nil
    clear_target()
  end
  local mode = fight_mode(id)
  local hp, hmax
  pcall(function() local d = world:get("Health", id).dataStorage hp, hmax = tonumber(d[1]), tonumber(d[3]) end)
  if mode ~= "Defensive" and mode ~= "Aggressive" then the_end("mode " .. mode) return false end
  if s.pwet then the_end("the player swims") return false end
  if not hp or hp <= 0 then the_end("he is down") return false end
  local dpl = math.sqrt((px - nx) ^ 2 + (py - ny) ^ 2 + (pz - nz) ^ 2)
  if dpl > FIGHT_RANGE + FIGHT_BITE then the_end(string.format("he is %.1f m from the player, outside the %d m radius", dpl, FIGHT_RANGE)) return false end
  -- his hits since the last step (the hit handler notes them): on his target or on something else
  local hits = h.my_hits or {}
  h.my_hits = nil
  local A = h.atk
  if not A then
    clear_target()
    if t % 30 ~= 0 then return false end
    local list = fight_candidates(world, id, h, mode, px, py, pz, nx, ny, nz)
    if #list == 0 then return false end
    -- Defensive: something attacked; he fights every monster near the player until the sequence ends (owner
    -- 2026-11-19 10:25: "it should automatically switch to aggressive mode to keep fighting all monsters in the near
    -- area as any monsters around won't stop fighting"); the menu's mode stays Defensive
    A = { phase = "pick", list = list, i = 1, tries = 1, t = t, wide = mode == "Defensive" }
    h.atk = A
    log(string.format("fight %s: the attack sequence starts (%s%s): %d candidate(s), the nearest %s at %.1f m", name, mode,
      A.wide and ", something attacked: he fights like Aggressive until it ends" or "", #list, tostring(list[1].id), list[1].d))
  end
  local function hold_still() hold_at(a, nx, ny, nz) return true end
  local smode = (A.wide and mode == "Defensive") and "Aggressive" or mode
  local function repick(why)
    A.phase, A.target, A.list, A.i, A.tries, A.t, A.checking, A.atk = "pick", nil, nil, 1, 1, t, nil, nil
    A.best_d, A.prog_t, A.stall_said = nil, nil, nil
    A.rep, A.rep_t, A.ok_d, A.ok_t, A.base = 0, nil, nil, t, nil
    A.list = fight_candidates(world, id, h, smode, px, py, pz, nx, ny, nz)
    log(string.format("fight %s: picks again (%s): %d candidate(s)", name, why, #A.list))
  end
  -- picking
  if A.phase == "pick" then
    local c = A.list[A.i]
    while c and not (world:position(c.id) and monster_alive(world, c.id)) do
      A.i = A.i + 1
      c = A.list[A.i]
    end
    if not c then
      clear_target()
      if t - A.t >= PICK_EVERY then
        if A.tries >= PICK_TRIES then
          -- the blocked ones are dropped like a target he gave up on (else the sequence starts again on them at once)
          local n = 0
          h.fight_skip = h.fight_skip or {}
          for m in pairs(A.blocked_ids or {}) do h.fight_skip[m], n = t + SKIP_TICKS, n + 1 end
          the_end(string.format("nothing he can reach after %d tries%s", A.tries,
            n > 0 and string.format(" (%d blocked one(s) not again for %d s)", n, SKIP_TICKS / 60) or ""))
          return false
        end
        A.tries, A.t, A.i, A.checking = A.tries + 1, t, 1, nil
        A.list = fight_candidates(world, id, h, smode, px, py, pz, nx, ny, nz)
        log(string.format("fight %s: try %d: %d candidate(s)", name, A.tries, #A.list))
      end
      return false  -- (owner 18:47) he keeps following while he checks
    end
    if A.checking ~= c.id then
      A.checking, A.check_t = c.id, t
      pcall(function() cd.lastTargetId = c.id end)
      return false  -- (owner 18:47) he keeps following while he checks
    end
    if t - A.check_t < RAY_WAIT then return false end  -- (owner 18:47) he keeps following while he checks
    local okr, reach = pcall(function() return cd.isTargetReachable end)
    local okd, rd = pcall(function() return tonumber(cd.distanceToTarget) end)
    if okr and reach then
      A.phase, A.target, A.t0, A.atk = "fight", c.id, t, nil
      A.rep, A.rep_t, A.ok_d, A.ok_t, A.base = 0, nil, nil, t, nil
      log(string.format("fight %s: attacks %s (%s; %.1f m from him; ray clear; his health %s/%s; it: %s)", name, tostring(c.id), c.why, c.d,
        tostring(hp), tostring(hmax), describe(world, c.id)))
    else
      -- (owner 2026-11-19 14:02 a bat a little higher, "the dog doesn't see it?") where it and he are, and its model
      local cx, cy, cz = world:position(c.id)
      local model = "?"
      pcall(function() model = tostring(world:template("ModelResource", c.id).model) end)
      log(string.format("fight %s: %s is blocked (the ray hits something at %s m of %.1f m), the next one; it at %s, %s; him at %.1f %.1f %.1f; its model %s",
        name, tostring(c.id), okd and rd and string.format("%.1f", rd) or "?", c.d,
        cx and string.format("%.1f %.1f %.1f", cx, cy, cz) or "?", cy and string.format("%.1f m %s him", math.abs(cy - ny), cy >= ny and "above" or "below") or "?",
        nx, ny, nz, model))
      A.blocked_ids = A.blocked_ids or {}
      A.blocked_ids[c.id] = true
      A.i, A.checking = A.i + 1, nil
      return false  -- (owner 18:47) he keeps following while he checks
    end
  end
  -- fighting
  local tg = A.target
  local mx, my, mz = world:position(tg)
  if not (mx and monster_alive(world, tg)) then
    log(string.format("fight %s: %s is dead", name, tostring(tg)))
    if A.atk then  -- (13:57 logging) the attack that killed it (its own hit comes a tick after this)
      log(string.format("fight %s: his %s from %.1f m killed it %.2f s after it started", name, A.atk.ix == 0 and "bite" or "lunge",
        A.atk.d or -1, (t - A.atk.t) / 60))
    end
    repick("his target is dead")
    return hold_still()
  end
  if (mx - px) ^ 2 + (my - py) ^ 2 + (mz - pz) ^ 2 > FIGHT_RANGE ^ 2 then
    repick(string.format("%s left your %d m radius", tostring(tg), FIGHT_RANGE))
    return hold_still()
  end
  pcall(function()
    cd.lastTargetId = tg
    cd.isTargetInsideLeash = false
    cd.targetOfMyTarget = false
  end)
  local d = math.sqrt((mx - nx) ^ 2 + (my - ny) ^ 2 + (mz - nz) ^ 2)
  local okr, reach = pcall(function() return cd.isTargetReachable end)
  local hit_tg, hit_other = false, nil
  for _, e in ipairs(hits) do
    if e.tg == tg then hit_tg = true
    elseif e.obj then hit_other = hit_other or e.tg end  -- an object (another monster is no block)
  end
  if hit_tg then A.rep = 0 end
  if hit_tg or not A.ok_d or d < A.ok_d - 0.3 then A.ok_d, A.ok_t = math.min(d, A.ok_d or d), t end
  local tv = speed_of(world, tg)
  local waiting = d > FIGHT_BITE and tv > FAST
  if waiting then
    A.ok_d, A.ok_t = d, t  -- waiting is not failing
    if not A.wait_said then
      A.wait_said = true
      log(string.format("fight %s: waits: %s moves %.1f m/s (faster than %d); he lunges when it slows (%.1f m away)", name,
        tostring(tg), tv, FAST, d))
    end
  elseif A.wait_said then
    A.wait_said = nil
    log(string.format("fight %s: %s slowed to %.1f m/s (%.1f m away)", name, tostring(tg), tv, d))
  end
  -- a reposition step under way: MOVE_STEP, then he tries again from where he is
  if A.rep_t then
    if t - A.rep_t < MOVE_STEP then
      if A.rep == 1 then return hold_still() end
      local p = A.rep == 2 and A.base.left or A.base.right
      hold_at(a, p.x, p.y, p.z)
      return true
    end
    A.rep_t, A.ok_t, A.ok_d = nil, t, d
    log(string.format("fight %s: tries %s again from here (%.1f m away)", name, tostring(tg), d))
  end
  local why
  if okr and not reach then why = "the ray is blocked"
  elseif hit_other and not hit_tg then why = string.format("his attack hit something else (%s), not it", tostring(hit_other))
  elseif t - A.ok_t >= NO_HIT then why = string.format("no hit on it and no closer for %d s", NO_HIT / 60) end
  if why then
    A.rep = (A.rep or 0) + 1
    if A.rep > 3 then
      h.fight_skip = h.fight_skip or {}
      h.fight_skip[tg] = t + SKIP_TICKS
      log(string.format("fight %s: gives up on %s: %s after the hop, left and right (not again for %d s)", name,
        tostring(tg), why, SKIP_TICKS / 60))
      repick("he can't deliver attacks on his target")
      return hold_still()
    end
    A.rep_t, A.atk = t, nil
    local fx, fz = mx - nx, mz - nz
    local fl = math.max(0.05, math.sqrt(fx * fx + fz * fz))
    if A.rep == 1 or not A.base then
      A.base = { left = { x = nx - fz / fl * SIDE, y = ny, z = nz + fx / fl * SIDE },
                 right = { x = nx + fz / fl * SIDE, y = ny, z = nz - fx / fl * SIDE } }
    end
    log(string.format("fight %s: can't deliver attacks on %s (%s; %.1f m away): %s", name, tostring(tg), why, d,
      A.rep == 1 and "hops toward it" or A.rep == 2 and string.format("moves %d m to the left", SIDE) or string.format("moves %d m to the right", SIDE)))
    if A.rep == 1 then
      local hop = math.min(fl, 2)
      local vup, vh = launch_speeds(hop, math.max(0, math.min(2, my - ny)))
      local okv, vx, vz = launch(world, id, fx / fl * hop, fz / fl * hop, hop, vup, vh)
      edge_off(a)
      h.djump = { t0 = t, untill = t + DJ_TICKS, x1 = nx + fx / fl * hop, y1 = ny, z1 = nz + fz / fl * hop, hp = hp, vx = vx, vz = vz, vy = vup, up = false }
      if not okv then log(string.format("fight %s: the hop: could not set his speed", name)) end
      return hold_still()
    end
    local p = A.rep == 2 and A.base.left or A.base.right
    hold_at(a, p.x, p.y, p.z)
    return true
  end
  -- (owner 2026-11-19 11:17 "the companion should only get just as close as they need to be to land the attack and no
  -- closer": his lunge carries him past it) he runs at it until he is within lunge reach, then stands there
  if d > FIGHT_LUNGE then hold_at(a, mx, my, mz) else hold_at(a, nx, ny, nz) end
  -- (logging, owner 2026-11-19 07:50 fences) a stall with the ray clear: no 0.3 m closer for half a second, not within
  -- bite reach (something lower than the ray's line, or the monster keeps away): once per stall
  if d <= FIGHT_LUNGE or not A.best_d or d < A.best_d - 0.3 then A.best_d, A.prog_t, A.stall_said = math.min(d, A.best_d or d), t, nil end
  if t - (A.prog_t or t) > 30 and not A.stall_said then
    A.stall_said = true
    local st, spd, col = "?", -1, "?"
    pcall(function() st = tostring(world:get("DynamicLocomotion", id).state) end)
    pcall(function() local v = world:get("Velocity", id).velocity spd = math.sqrt(v.x * v.x + v.z * v.z) end)
    pcall(function()
      local r = world:get("MovementCollider", id).results.m_value
      col = string.format("collider: touching %s, a player %s, last slide side %s; ground %s (%.2f m, walkable %s), standing on %s",
        tostring(r.hasSpheroidCollision), tostring(r.hasPlayerSpheroidCollision), tostring(r.lastCollideAndSlideSide),
        tostring(r.hasGroundCollision), tonumber(r.groundDistance) or -1, tostring(r.isGroundWalkable), tostring(r.attachmentEntityId))
    end)
    log(string.format("fight %s: stalled (ray clear) on the way to %s: %.1f m away, %.1f m %s him, no closer for %.1f s; his state %s, speed %.1f m/s; %s",
      name, tostring(tg), d, math.abs(my - ny), my >= ny and "above" or "below", (t - A.prog_t) / 60, st, spd, col))
    report_blockers(s, "fight stall", mx - nx, mz - nz)
  end
  local act = action_of(world, id)
  local at = A.atk
  if at then
    if hit_tg then at.hit = true end
    -- (owner 2026-11-19 13:57 "yes log it": how far a lunge really reaches) every hit as it lands, and where he is
    -- at 0.4 s (the hits so far came 0.40-0.46 s after the start)
    for _, e in ipairs(hits) do
      log(string.format("fight %s: his %s's hit landed %.2f s after the start on %s: he is %.1f m from it, moved %.1f m",
        name, at.ix == 0 and "bite" or "lunge", (t - at.t) / 60, e.tg == tg and "it" or (e.obj and ("object " .. tostring(e.tg)) or ("monster " .. tostring(e.tg))),
        d, math.sqrt((nx - at.x) ^ 2 + (nz - at.z) ^ 2)))
    end
    if t - at.t == 24 then
      log(string.format("fight %s: his %s at 0.4 s: he is %.1f m from it (%.1f at the start), moved %.1f m; it moved %.1f m; he is %.1f m higher than at the start, it is %.1f m above him",
        name, at.ix == 0 and "bite" or "lunge", d, at.d or -1, math.sqrt((nx - at.x) ^ 2 + (nz - at.z) ^ 2),
        math.sqrt((mx - (at.mx or mx)) ^ 2 + (mz - (at.mz or mz)) ^ 2), ny - (at.y or ny), my - ny))
    end
    local asked = (tonumber(cd.selectedAttackIndex) or 255) ~= 255
    if not at.started and not asked then at.started = t end
    if at.jump and at.started and not at.jumped then
      at.jumped = t
      local okj = pcall(function()
        local tr = world:get("CurrentTransform", id).transform
        tr.position.y = tr.position.y + math.floor(0.3 * 2 ^ 32)
        world:get("Velocity", id).velocity.y = at.jump
      end)
      log(string.format("fight %s: jumps into his %s (up %.1f m/s)%s", name, at.ix == 0 and "bite" or "lunge", at.jump,
        okj and "" or " (could not set his speed)"))
    end
    if at.jumped and t > at.jumped and t <= at.jumped + 6 then  -- a speed written on the ground may not take: again until he is in the air
      local air = false
      pcall(function() air = world:get("DynamicLocomotion", id).state == 2 end)
      if not air then pcall(function() world:get("Velocity", id).velocity.y = at.jump end) end
    end
    if at.started and act and act ~= 0 then at.anim = act end
    local over = at.started and at.anim and (act == 0)
    if over or t - at.t > ATTACK_MAX then
      log(string.format("fight %s: %s %s after %.2f s, %s (%s; animation %s); he moved %.1f m, now %.1f m from it (was %.1f); %s", name,
        at.ix == 0 and "bite" or "lunge", over and "over" or "TIMED OUT", (t - at.t) / 60, at.hit and "HIT it" or "MISSED it",
        at.started and string.format("started after %d tick(s)", at.started - at.t) or "never started", tostring(at.anim),
        math.sqrt((nx - (at.x or nx)) ^ 2 + (nz - (at.z or nz)) ^ 2), d, at.d or -1, face_info(world, id, tg, nx, ny, nz, mx, my, mz)))
      A.atk, at = nil, nil
    end
  end
  local off = 0
  if not at then
    local okt, o = pcall(turn_toward, world, id, mx - nx, mz - nz)
    off = okt and o or 0
  end
  -- (healing) a move already asked for (the heal's Wolf Shout) is not overwritten, and the shout plays SHOUT_TICKS first
  local busy = (tonumber(cd.selectedAttackIndex) or 255) ~= 255 or t - (h.heal_t or -1e9) < SHOUT_TICKS
  if not at and d <= FIGHT_LUNGE and math.abs(off) <= FACE_OK and not waiting and not busy then
    -- (owner 2026-11-19 18:47 yes: jump bites at floating monsters hit 5 of 22, jump lunges 20 of 25) a target HIGH or more
    -- above him gets the lunge only
    local ix = (d <= FIGHT_BITE and my - ny < HIGH) and 0 or 1
    local ok = pcall(function() cd.selectedAttackIndex = ix end)
    A.atk = { ix = ix, t = t, x = nx, z = nz, d = d, mx = mx, mz = mz, y = ny }
    if my - ny >= HIGH then A.atk.jump = (launch_speeds(0, my - ny)) end
    log(string.format("fight %s: %s at %s (%.1f m)%s; %s", name, ix == 0 and "bite" or "lunge", tostring(tg), d, ok and "" or " (could not ask)",
      face_info(world, id, tg, nx, ny, nz, mx, my, mz)))
  end
  return true
end

-- ===== Read-only tools =================================================================================================
local function look(world, id)
  local okf, f = pcall(world.get, world, "Faction", id)
  local oka, a = pcall(world.get, world, "DynamicEnemy01BehaviorState", id)
  local x, y, z = world:position(id)
  log(string.format("entity %s at %s: faction %s, AI %s, state %s, offered %s, %s", tostring(id),
    x and string.format("%.1f %.1f %.1f", x, y, z) or "nowhere", okf and f and tostring(f.faction) or "-",
    oka and a and tostring(a.enabled) or "-", oka and a and tostring(a.state) or "-",
    tostring(emf.offered and emf.offered(world, id)), drives[id] and "driven" or "not driven"))
end

local hit_watch = {}  -- entity -> true: its hits go into the HIT log too (npc spawnwild adds the body)
function F.setup(k)
  -- every hit a companion gives or takes: amount, health around it, types, attack kind, reaction
  pcall(emf.on_hit, function(world, hit)
    if not hit or hit.kind ~= "hit" then return end
    pcall(note_threat, world, hit)  -- (fight, step 2) watching only
    pcall(note_my_hit, world, hit)
    local mine = false
    for _, e in pairs(ent_of) do if e == hit.attacker or e == hit.source or e == hit.target then mine = true break end end
    if hit_watch[hit.attacker or 0] or hit_watch[hit.target or 0] then mine = true end
    if not mine then return end
    local okl, line = pcall(function()
      return string.format("HIT %s -> %s (source %s, part %s): amount %s, stamina %s, health %s -> %s, types %s, attack %s, "
        .. "blocked %s, parried %s, crit %s, reaction %s, impact %s, program %s, from_mod %s", tostring(hit.attacker),
        tostring(hit.target), tostring(hit.source), tostring(hit.part), tostring(hit.amount), tostring(hit.stamina),
        tostring(hit.health_before), tostring(hit.health_after), table.concat(hit.types or {}, ","),
        table.concat(hit.attacks or {}, ","), tostring(hit.blocked), tostring(hit.parried), tostring(hit.crit),
        tostring(hit.reaction), tostring(hit.impact), tostring(hit.program), tostring(hit.from_mod))
    end)
    log(okl and line or ("HIT: " .. tostring(line)))
  end)
  pcall(emf.on_event, "InteractionAcceptedEvent", function(world, e)  -- (09:21) only the owner opens his chest
    -- (13:57) the game's own E on a pet of ours (an animal): his wheel, as E on a companion
    local host, guest = rawget(e, "hostEntityId"), rawget(e, "guestEntityId")
    if host and guest and name_of[host] and not world:get("DynamicEnemy01BehaviorState", host) then
      log(string.format("pet %s (%s): the game's E pressed by player %s: his wheel", tostring(name_of[host]), tostring(host), tostring(guest)))
      local okt, errt = pcall(on_talk, world, guest, host)
      if not okt then log("pet E: " .. tostring(errt)) end
    end
    if not next(inv.open) then return end
    local oka, erra = pcall(inv.on_accept, world, e)
    if not oka then log("inventory: open check failed: " .. tostring(erra)) end
  end, "server")
  pcall(emf.on_player_joined, function(world, p)
    log(string.format("join: player %s (account %s)", tostring(p.player), tostring(p.account)))
    pcall(roster.ui_known, world)  -- (roster window) his name kept for when he is offline
    local okr, errr = pcall(roster_joined, world, p)
    if not okr then log("roster: join failed: " .. tostring(errr)) end
  end)
  local okc = emf.net.channel(WHEEL, { version = 1, to = "both", max = 1024, per_10s = 60,
    on_server = function(world, from, data)
      local okw, errw = pcall(on_pick, world, from, data)
      if not okw then log("wheel: " .. tostring(errw)) end
    end,
    on_player = function() end })
  log("wheel channel: " .. tostring(okc))
  -- (owner 2026-11-20 10:00) the Companion Roster window in the players' games: their asks and actions come here
  local okr = emf.net.channel(roster.RCH, { version = 1, to = "both", max = 16384, per_10s = 60,
    on_server = function(world, from, data)
      local oku, erru = pcall(roster.ui_do, world, from, data)
      if not oku then log("roster window: " .. tostring(erru)) end
    end,
    on_player = function() end })
  log("roster window channel: " .. tostring(okr))
  -- the roster lives in the world's data. (loot_filter registers an empty one only to ask for the data; this one,
  -- registered later, does that too.) TODO for the release: one owner of the world data in FlameKit's core.
  pcall(emf.on_world_data, function(world, text)
    local okl, errl = pcall(roster_loaded, world, text)
    if not okl then log("roster: load failed: " .. tostring(errl)) end
  end)
  emf.log("[flamekit] npc probe: loaded (companion test: flamekit.npc)")
  pcall(emf.command, "npc", "roster ... | drive <npc> <player>|stop | fullrec <entity> [s] | look <entity> | near <x> <y> <z> [r] | remove <entity>: companion test",
    function(world, args)
      local what = args[1]
      if what == "roster" then
        local okc2, errc = pcall(roster_cmd, world, args)
        if not okc2 then log("roster: " .. tostring(errc)) emf.reply("roster: failed") end
      elseif what == "drive" then  -- drive <npc> <player> | drive <npc> stop (he stays where he is)
        local id = tonumber(args[2])
        if args[3] == "stop" then
          drives[id or 0] = nil
          local x, y, z = world:position(id or 0)
          if x then pcall(stay_at, world, id, x, y, z) end
          log("drive " .. tostring(id) .. ": stopped, staying")
        elseif id then
          drives[id] = { player = tonumber(args[3]) or 1, trail = {} }
          log("drive " .. tostring(id) .. ": following player " .. tostring(args[3] or 1))
        end
        emf.reply("npc: drive")
      elseif what == "fullrec" then  -- fullrec <entity> [seconds] | fullrec <entity> stop
        local id = tonumber(args[2])
        if args[3] == "stop" then
          if fullrecs[id or 0] then fullrecs[id].untill = 0 end
        elseif id then
          local okr, err = pcall(fullrec_start, world, id, tonumber(args[3]) or 600)
          if not okr then log("fullrec: " .. tostring(err)) end
        end
        emf.reply("npc: fullrec")
      elseif what == "look" then
        local id = tonumber(args[2])
        if id then look(world, id) end
        emf.reply("npc: logged")
      elseif what == "near" then  -- near <x> <y> <z> [r]: every entity with the monster AI within r m (default 15)
        local x, y, z, r = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]), tonumber(args[5]) or 15
        local n = 0
        for _, id in ipairs(world:entities()) do
          local ex, ey, ez = world:position(id)
          if ex and x and math.abs(ex - x) < r and math.abs(ez - z) < r and math.abs(ey - y) < r then
            local oka, a = pcall(world.get, world, "DynamicEnemy01BehaviorState", id)
            if oka and a then n = n + 1 look(world, id) end
          end
        end
        log(string.format("near: %d with the monster AI", n))
        emf.reply("npc: near")
      elseif what == "spawnwild" then  -- spawnwild <guid> <player> [metres]: a wild body with its own AI, to watch
        local guid, player, m = args[2], tonumber(args[3]) or 1, tonumber(args[4]) or 6
        local x, y, z = world:position(player)
        if not (guid and x) then emf.reply("npc: spawnwild <guid> <player> [metres]") return end
        local ok, id = pcall(emf.spawn, world, guid, x, y + 0.5, z + m)
        if ok and id then hit_watch[id] = true end
        log(string.format("spawnwild %s %.0f m north of %s: %s", guid, m, tostring(player), ok and tostring(id) or ("error: " .. tostring(id))))
        emf.reply("npc: spawnwild " .. tostring(ok and id))
      elseif what == "face" then  -- face <npc> <target> [metres]: the npc put m metres in front of
        -- the target, on the line from the target to where the npc stands, turned to face the target
        local id, tg, m = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 1.5
        local nx, _, nz = world:position(id or 0)
        local tx, ty, tz = world:position(tg or 0)
        if not (nx and tx) then emf.reply("npc: face <npc> <target> [metres]") return end
        local dx, dz = nx - tx, nz - tz
        local d = math.sqrt(dx * dx + dz * dz)
        if d < 0.01 then dx, dz, d = 0, 1, 1 end
        local px, pz = tx + dx / d * m, tz + dz / d * m
        local okt = pcall(emf.teleport, world, id, px, ty, pz, {})
        local yaw = math.atan(tx - px, tz - pz)
        local o = world:get("CurrentTransform", id).transform.orientation
        o.x, o.y, o.z, o.w = 0, math.sin(yaw / 2), 0, math.cos(yaw / 2)
        log(string.format("face: %s put %.1f m from %s at %.1f %.1f %.1f, yaw %.0f deg: %s", tostring(id), m, tostring(tg),
          px, ty, pz, math.deg(yaw), tostring(okt)))
        emf.reply("npc: face")
      elseif what == "level" then  -- level <entity> <level>: the way
        -- experimental.lua's set_level does it: Level.dataStorage[1] and DynamicEnemyScaling.nextUpdateTime = 0, so the
        -- game's own next scaling update rescales health and hits to that level
        local id, lvl = tonumber(args[2]), tonumber(args[3])
        local lv = id and world:get("Level", id)
        if not (lv and lvl) then emf.reply("npc: level <entity> <level>") return end
        lv.dataStorage[1] = lvl
        local sc = world:get("DynamicEnemyScaling", id)
        if sc then
          if type(sc.nextUpdateTime) == "table" then sc.nextUpdateTime.value = 0 else sc.nextUpdateTime = 0 end
        end
        log(string.format("level: %s set to %d (scaling update asked: %s)", tostring(id), lvl, tostring(sc ~= nil)))
        emf.reply("npc: level")
      elseif what == "combat" then  -- combat <npc> <target> [attack]: the combat numbers a wild
        -- hound has while it bites (taken from a full recording), copied as plain values, AI stays off
        local id, tg, ix = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
        local st = id and world:get("DynamicEnemy01BehaviorState", id)
        if not (st and tg) then emf.reply("npc: combat <npc> <target> [attack]") return end
        local cd = st.combatData
        st.state = 6
        cd.state = 3
        cd.selectedAttackIndex = ix
        cd.lastTargetId = tg
        cd.isTargetReachable = true
        cd.isTargetInsideLeash = true
        local gx, _, gz = world:position(tg)
        local nx, _, nz = world:position(id)
        if gx and nx then cd.distanceToTarget = math.sqrt((gx - nx) ^ 2 + (gz - nz) ^ 2) end
        log(string.format("combat: %s state 6, combat state 3, attack %d, target %s", tostring(id), ix, tostring(tg)))
        emf.reply("npc: combat")
      elseif what == "faction" then  -- faction <entity> <n>: EMF combat.md: 7 Player, 11 PlayerAlly,
        -- 1 HitAll, 10 Skeleton. The PvP notes: a monster body with faction 7 did 0 damage, with faction 1 it did damage.
        local id, fn = tonumber(args[2]), tonumber(args[3])
        local f = id and world:get("Faction", id)
        if not (f and fn) then emf.reply("npc: faction <entity> <n>") return end
        f.faction = fn
        log(string.format("faction: %s now %d", tostring(id), fn))
        emf.reply("npc: faction")
      elseif what == "attr" then  -- attr <entity> <Strength|Dexterity|Intelligence> <value>:
        -- dataStorage[1] and [2] (a player has total, base, bonus: Strength 26 11 15)
        local id, comp, v = tonumber(args[2]), args[3], tonumber(args[4])
        local c = id and comp and world:get(comp, id)
        if not (c and v) then emf.reply("npc: attr <entity> <component> <value>") return end
        c.dataStorage[1] = v
        c.dataStorage[2] = v
        log(string.format("attr: %s %s = %s", tostring(id), comp, tostring(v)))
        emf.reply("npc: attr")
      elseif what == "tpground" then  -- tpground <entity> <x> <y> <z>: EMF's teleport with the game's
        -- ground search: does the walkable search answer at this spot, and where does it put the body?
        local id, x, y, z = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]), tonumber(args[5])
        if not (id and x and y and z) then emf.reply("npc: tpground <entity> <x> <y> <z>") return end
        local c0 = os.clock()
        -- the callback must not touch `world` (EMF pauses the whole script for that)
        local okt, res = pcall(emf.teleport, world, id, x, y, z, { ground = true }, function(moved, mx, my, mz)
          log(string.format("tpground %s -> %.1f %.1f %.1f: moved %s to %s %s %s (%.1f s)", tostring(id), x, y, z,
            tostring(moved), tostring(mx and string.format("%.2f", mx)), tostring(my and string.format("%.2f", my)),
            tostring(mz and string.format("%.2f", mz)), os.clock() - c0))
        end)
        log(string.format("tpground %s -> %.1f %.1f %.1f: queued %s", tostring(id), x, y, z, tostring(okt and res)))
        emf.reply("npc: tpground")
      elseif what == "lure" then  -- lure <npc> <x> <y> <z> [seconds]: edge stop test, see drive_lure
        local id, x, y, z, sec = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]), tonumber(args[5]), tonumber(args[6]) or 15
        local h = id and drives[id]
        if not (h and x and y and z) then emf.reply("npc: lure <following npc> <x> <y> <z> [seconds]") return end
        h.lure = { x = x, y = y, z = z, untill = world:tick() + math.floor(sec * 60) }
        log(string.format("lure: %s walks toward %.1f %.1f %.1f for %.0f s", tostring(id), x, y, z, sec))
        emf.reply("npc: lure")
      elseif what == "still" then  -- still <entity>: a test target's monster AI off, so it stands
        -- still and does not go for the player (his reflect kills it)
        local id = tonumber(args[2])
        local st = id and world:get("DynamicEnemy01BehaviorState", id)
        if not st then emf.reply("npc: still <entity>") return end
        st.enabled = false
        log("still: " .. tostring(id) .. " AI off")
        emf.reply("npc: still")
      elseif what == "healfx" then  -- healfx <n>: heal effect candidate n on the nearest player for 10 s (owner 22:09)
        local n = tonumber(args[2])
        local c = n and HEAL_FX[n]
        if not c then emf.reply("npc healfx: 1-" .. #HEAL_FX) return end
        local okp, ids = pcall(players.ids, world)
        local pid = tonumber(args[3]) or (okp and ids and ids[1])  -- (22:17) healfx <n> [entity]: on that body
        if not pid then emf.reply("npc healfx: no player") return end
        local x, y, z = world:position(pid)
        if not x then emf.reply("npc healfx: no player") return end
        local oks, fid = pcall(emf.spawn, world, c[2], x, y, z)
        if oks and fid and fid ~= 0 then
          heal_fx_shown[#heal_fx_shown + 1] = { id = fid, at = world:tick() + 600 }
          log(string.format("heal fx %d (%s) shown on %s as entity %s", n, c[1], tostring(pid), tostring(fid)))
          emf.reply("healfx " .. n .. ": " .. c[1])
        else
          log(string.format("heal fx %d (%s) refused (%s)", n, c[1], tostring(fid)))
          emf.reply("healfx " .. n .. ": refused")
        end
      elseif what == "unlock" then  -- unlock <chest> <item> <n>: (08:57) puts the upgrades back on a piece in a chest
        local ch, item, n = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
        local rr = not ch and args[2] and find(args[2])
        if rr and item and n then  -- unlock <companion> <item> <n>: in his record (put back at the next opening)
          for _, e in ipairs(rr.inv or {}) do
            if e.item == item and e.level then
              e.unlocked = math.floor(n)
              roster_save()
              log(string.format("unlock: %s's record: item %s level %s now %d unlocked", rr.name, tostring(item), tostring(e.level), e.unlocked))
              emf.reply("npc: unlock set in the record")
              return
            end
          end
          emf.reply("npc: unlock: no such gear in his record")
          return
        end
        if not (ch and item and n) then emf.reply("npc: unlock <chest>|<companion> <item> <n>") return end
        local c = { chest = ch, fix = { { item = item, unlocked = math.floor(n) } } }
        inv.apply_unlocked(world, "command", c)
        emf.reply("npc: unlock done (see the log)")
      elseif what == "petlog" then  -- petlog <entity> [seconds]: (pets, 12:48) what an animal's own AI does, twice a second
        local id, sec = tonumber(args[2]), tonumber(args[3]) or 30
        if not id then emf.reply("npc: petlog <entity> [seconds]") return end
        roster.petlog = { id = id, untill = world:tick() + math.floor(sec * 60) }
        emf.reply("npc: petlog " .. id .. " for " .. sec .. " s")
      elseif what == "names" then  -- names [copy <from> <to> | set <entity> <id>]: the game's own floating names
        -- (CustomPlayerString.stringId, the key of a name players gave a chest or altar; owner 08:41 "research the
        -- first point and see what it looks like?") lists every entity with one, or copies one onto another
        local function key_of(id)
          local ok, c = pcall(world.get, world, "CustomPlayerString", id)
          if not ok or not c then return nil end
          local k = c.stringId
          if type(k) ~= "number" then k = k.value end  -- (a HashKey64 may read as a number or as {value})
          return k
        end
        local function hex(v)
          if v == nil then return "none" end
          if math.type(v) == "integer" then return string.format("0x%016X", v) end
          return string.format("%.0f (float)", v)
        end
        if args[2] == "spawn" then  -- (08:47: our spawned chest has no CustomPlayerString, emf.add_component only
          -- takes 2 kinds, emf.spawn takes any) spawn <from>: a test chest 2 m from the player with <from>'s name key, 60 s
          local v = key_of(tonumber(args[3]) or 0)
          local okp, ids = pcall(players.ids, world)
          local pid = okp and ids and ids[1]
          local x, y, z
          if pid then x, y, z = world:position(pid) end
          if not (v and x) then emf.reply("npc names: spawn <entity with a name> (near a player)") return end
          local ok, fid = pcall(emf.spawn, world, inv.CHEST, x + 2, y, z, { CustomPlayerString = { stringId = v } })
          if not ok then ok, fid = pcall(emf.spawn, world, inv.CHEST, x + 2, y, z, { CustomPlayerString = { stringId = { value = v } } }) end
          if ok and fid and fid ~= 0 then
            heal_fx_shown[#heal_fx_shown + 1] = { id = fid, at = world:tick() + 3600 }
            log(string.format("names: test chest %s spawned with %s's key %s (reads %s), gone in 60 s", tostring(fid), args[3], hex(v), hex(key_of(fid))))
            emf.reply("npc names: test chest " .. tostring(fid))
          else
            log("names: test chest refused: " .. tostring(fid))
            emf.reply("npc names: refused")
          end
        elseif args[2] == "copy" or args[2] == "set" then
          local from, to = tonumber(args[3]), tonumber(args[4])
          local v = args[2] == "copy" and from and key_of(from) or (args[2] == "set" and math.tointeger(tonumber(args[4])))
          if args[2] == "set" then to = from end
          local c = to and world:get("CustomPlayerString", to)
          if not (v and c) then emf.reply("npc names: copy <from> <to> | set <entity> <number> (both need the component)") return end
          local was = key_of(to)
          if type(c.stringId) == "number" then c.stringId = v else c.stringId.value = v end
          log(string.format("names: %s stringId %s -> %s (now reads %s)", tostring(to), hex(was), hex(v), hex(key_of(to))))
          emf.reply("npc names: set")
        else
          local px, py, pz
          pcall(function() local ids = players.ids(world) px, py, pz = world:position(ids[1]) end)
          local n, named = 0, 0
          for _, id in ipairs(world:entities()) do
            local v = key_of(id)
            if v ~= nil then
              n = n + 1
              local x, y, z = world:position(id)
              local d = (px and x) and math.sqrt((x - px) ^ 2 + (y - py) ^ 2 + (z - pz) ^ 2) or -1
              if v ~= 0 or d >= 0 and d < 30 then
                if v ~= 0 then named = named + 1 end
                local okm, m = pcall(function() return world:template("ModelResource", id).model end)
                log(string.format("names: %s key %s at %.0f m (model %s)", tostring(id), hex(v), d, okm and tostring(m) or "?"))
              end
            end
          end
          log(string.format("names: %d entities have the component, %d with a name key", n, named))
          emf.reply(string.format("npc names: %d / %d", named, n))
        end
      elseif what == "hold" then  -- hold <npc> <target> [seconds]: stays put and faces the target (drive_hold)
        local id, tg, sec = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 10
        if not (id and tg) then emf.reply("npc: hold <npc> <target> [seconds]") return end
        holds[id] = { target = tg, untill = world:tick() + math.floor(sec * 60) }
        log(string.format("hold: %s holds and faces %s for %.0f s", tostring(id), tostring(tg), sec))
        emf.reply("npc: hold")
      elseif what == "atk" then  -- atk <entity> <index>: combatData.selectedAttackIndex, the number
        -- the monster AI keeps for the attack it is doing (wild hound: 0 bite, 1 lunge; ours: 255 = none). Only a value.
        local id, ix = tonumber(args[2]), tonumber(args[3])
        local st = id and world:get("DynamicEnemy01BehaviorState", id)
        if not (st and ix) then emf.reply("npc: atk <entity> <index>") return end
        st.combatData.selectedAttackIndex = ix
        log(string.format("atk: %s selectedAttackIndex = %d", tostring(id), ix))
        emf.reply("npc: atk")
      elseif what == "remove" then
        local id = tonumber(args[2])
        drives[id or 0] = nil
        local ok, res = pcall(emf.destroy, world, id)
        log(string.format("remove %s: %s", tostring(id), tostring(ok and res)))
        emf.reply("npc: removed " .. tostring(ok and res))
      else
        emf.reply("npc: roster ... | drive <npc> <player>|stop | fullrec <entity> [s] | look <entity> | near <x> <y> <z> [r] | remove <entity>")
      end
    end)
end

local dead_told = {}  -- entity -> true: "Companion has died!" sent once per body
-- put away by the glider, a fast travel or can't follow: name -> { player, account, why, ground }
local returning = {}
local load_seen  -- player -> "ready/teleport count" last logged
local load_err   -- the travel request read failed once (logged)
local function put_away_for(world, id, h)
  local name = name_of[id]
  local r = name and find(name)
  drives[id], name_of[id] = nil, nil
  pcall(emf.destroy, world, id)
  if r then ent_of[r.name], r.out = nil, false roster_save() end
  status(world, h.player, "companion_stuck", nil)
  if h.go_away == "can't follow" then  -- (owner 22:22 "show the error") the same words for 5 s, as he is respawned at once
    say(world, h.player, STUCK_TEXT[h.cant] or STUCK_TEXT.blocked, "#ff9050")
  end
  if h.go_away == "glide" then
    status(world, h.player, "companion_away", "Companion put away, waiting for your landing.", "#8cd2ff")
  end
  local okacc, acc = pcall(world.account, world, h.player)
  if name then returning[name] = { player = h.player, account = (r and r.owner) or (okacc and acc), why = h.go_away } end
  log(string.format("away: %s (%s) put away (%s); back beside player %s once he stands on the ground", tostring(name),
    tostring(id), tostring(h.go_away), tostring(h.player)))
end
local companions_core = require("core.companions")  -- the minimap's companion dots
function F.tick(world)
  if not world:is_server() then return end
  local t = world:tick()
  if t % 60 == 13 and next(roster.subs) then pcall(roster.ui_tick, world) end  -- (roster window) changes to its viewers
  if roster.petlog and t % 30 == 0 then pcall(roster.petlog_tick, world) end  -- (pets) the animal AI watched
  if #heal_fx_shown > 0 then  -- (healfx preview) effects go after 10 s
    local keep = {}
    for _, f in ipairs(heal_fx_shown) do
      if f.at <= t then pcall(emf.destroy, world, f.id) else keep[#keep + 1] = f end
    end
    heal_fx_shown = keep
  end
  if next(inv.want) then pcall(inv.want_tick, world) end  -- (his E prompt) made once EMF takes it
  if next(inv.ground) then  -- (12:12) his chest's place on the ground, once the probe answered
    local okg, errg = pcall(inv.ground_tick, world)
    if not okg then log("inventory: ground: " .. tostring(errg)) inv.ground = {} end
  end
  if next(inv.open) then  -- (inventory) fill new chests, keep open ones saved, close forgotten ones
    local oki, erri = pcall(inv.tick, world)
    if not oki then log("inventory: tick failed: " .. tostring(erri)) end
  end
  -- (fight, step 2: watching only) the monster scan, and once a second what each companion would do
  local okw, errw = pcall(monster_scan_step, world)
  if not okw then mscan = nil log("fight scan failed: " .. tostring(errw)) end
  if t % 60 == 0 then
    local okf, errf = pcall(fight_watch, world)
    if not okf then log("fight watch failed: " .. tostring(errf)) end
  end
  if t % 30 == 0 then  -- where every companion is, with its owner's character name (the dot's colour)
    local places = {}
    for name, id in pairs(ent_of) do
      local x, _, z = world:position(id)
      local r = find(name)
      if x and r then
        local p = player_of(world, r.owner)
        local okn, cname = pcall(function() return p and require("core.players").name(world, p) end)  -- the dot's colour comes from the same name the far list uses
        places[#places + 1] = { x = x, z = z, owner = (okn and cname) or "", name = name }  -- the dot shows the companion's name
      end
    end
    companions_core.set_places(places)
  end
  if t % 15 == 0 then
    for name, id in pairs(ent_of) do
      if not dead_told[id] then
        local okh, hp = pcall(function() return world:get("Health", id).dataStorage[1] end)
        if okh and hp and hp <= 0 then
          dead_told[id] = true
          local r = find(name)
          local p = r and player_of(world, r.owner)
          local x, y, z = world:position(id)
          log(string.format("died: %s (%s) at %s", name, tostring(id), x and string.format("%.1f %.1f %.1f", x, y, z) or "?"))
          if p then
            status(world, p, "companion_stuck", nil)
            status(world, p, "companion_dead", "Companion has died!", "#ff4040")
          end
          -- (owner 2026-11-20 08:15 "if the companion dies with the chest open, the chest needs to despawn") closed the
          -- usual way: what is in it is saved first
          if r and inv.open[r.name] then pcall(inv.close, world, r, "he died") end
        end
      end
    end
  end
  if t % 600 == 0 then
    for name, id in pairs(ent_of) do
      local r = find(name)
      if r and world:position(id) then
        local okm, errm = pcall(match_level, world, id, r, nil)
        if not okm then log("level: " .. tostring(errm)) end
      end
    end
  end
  if t % 60 == 0 then  -- armor, every second
    for name, id in pairs(ent_of) do
      local r = find(name)
      if r and world:position(id) then
        local oka, erra = pcall(match_armor, world, id, r)
        if not oka and not armor_err then armor_err = true log("armor: " .. tostring(erra)) end
      end
    end
  end
  for id, r in pairs(fullrecs) do
    if t > r.untill or not world:position(id) then
      fr_write(r, fr_stamp(world) .. " END")
      pcall(function() r.file:close() end)
      fullrecs[id] = nil
      log("fullrec " .. tostring(id) .. ": ended")
    elseif t >= r.next then
      r.next = t + 30
      local okf, errf = pcall(fullrec_step, world, id, r)
      if not okf then log("fullrec " .. tostring(id) .. ": " .. tostring(errf)) end
    end
  end
  for id, pl in pairs(pending_life) do
    if t >= pl.at then
      pending_life[id] = nil
      local okb, errb = pcall(bring_to_life, world, pl.r, id, pl.player)
      log(string.format("roster: %s set up (%s)", pl.r.name, okb and "ok" or tostring(errb)))
    end
  end
  for name, wt in pairs(waiting) do
    local r = find(name)
    local x, y, z = world:position(wt.player)
    wt.tries = wt.tries + 1
    if not r or wt.tries > 600 then waiting[name] = nil
    elseif x then
      waiting[name] = nil
      local okw, errw = pcall(spawn_body, world, r, x, y + 0.5, z, wt.player)
      if not okw then log("roster: " .. tostring(errw)) end
      roster_save()
    end
  end
  for id, h in pairs(drives) do
    local okd, errd = pcall(drive_step, world, id, h)
    if not okd and not h.err_said then h.err_said = true log("drive " .. tostring(id) .. ": " .. tostring(errd)) end
    if h.shim then pcall(roster.pet_flush, world, id, h) end  -- (pets) the drive's answer to the server probe
  end
  pcall(roster.pet_write)  -- (pets) the drive's inputs for the server probe
  pcall(roster.pets_quiet, world)  -- (pets) their own AI kept idle
  for id, h in pairs(drives) do
    if h.go_away then
      local okp, errp = pcall(put_away_for, world, id, h)
      if not okp then log("away: " .. tostring(errp)) drives[id] = nil end
    end
  end
  -- logging: the game's own "ready for gameplay" flag the player's client sends (PlayerInput.fromClientIsReadyForGameplay)
  -- and his TeleportCount, for every player, whenever either changes
  for _, pid in ipairs((function() local ids = {} for _, r in pairs(returning) do ids[#ids + 1] = r.player end
      for _, hh in pairs(drives) do ids[#ids + 1] = hh.player end return ids end)()) do
    local okr, ready = pcall(function() return world:get("PlayerInput", pid).fromClientIsReadyForGameplay end)
    local okc, cnt = pcall(function() return world:get("TeleportCount", pid).counter end)
    -- and the player's own fast travel request (PlayerInput.fromClient.teleportAction)
    local okq, req = pcall(function()
      local ta = world:get("PlayerInput", pid).fromClient.teleportAction
      return string.format("%s/%s/%s", tostring(ta.target), tostring(ta.teleporterType), tostring(ta.versionData))
    end)
    if not okq and not load_err then load_err = true log("load: travel request not readable: " .. tostring(req)) end
    local key = tostring(okr and ready) .. "/" .. tostring(okc and cnt) .. "/" .. tostring(okq and req)
    load_seen = load_seen or {}
    if load_seen[pid] ~= key then
      load_seen[pid] = key
      local x, y, z = world:position(pid)
      log(string.format("load: player %s ready for gameplay %s, teleport count %s, travel request %s, at %s", tostring(pid),
        tostring(okr and ready), tostring(okc and cnt), tostring(okq and req), x and string.format("%.1f %.1f %.1f", x, y, z) or "-"))
    end
  end
  -- back beside the player once he has stood on the ground (not in the air, not swimming) for LAND_TICKS
  for name, rt in pairs(returning) do
    if ent_of[name] then
      returning[name] = nil  -- called back some other way (P, the wheel)
    elseif not world:position(rt.player) then
      -- the player is gone (left the game): the roster brings him back when the player joins
      returning[name] = nil
    else
      local okw, w = pcall(function() return tonumber(world:get("DynamicLocomotion", rt.player).currentWaterState) end)
      -- and his game reports it has loaded (PlayerInput.fromClientIsReadyForGameplay is false from the teleport until
      -- the loading screen is over)
      local okr, ready = pcall(function() return world:get("PlayerInput", rt.player).fromClientIsReadyForGameplay end)
      local on_ground = not player_airborne(world, rt.player) and not (okw and (w or 0) > 0.5) and not (okr and ready == false)
      if on_ground then
        rt.ground = rt.ground or t
        if t - rt.ground >= LAND_TICKS then
          returning[name] = nil
          log(string.format("away: %s back beside player %s (%s over)", name, tostring(rt.player), tostring(rt.why)))
          -- (owner 2026-11-20 12:37 "when I teleported I only see N1 again": this called on_call, which brings the
          -- player's MAIN companion, so N1 came twice and N2 not at all) this companion himself comes back beside him
          local r = find(name)
          if r then
            local okc, said = pcall(roster.ui_back, world, r, rt.player)
            log(string.format("away: %s: %s", name, tostring(said)))
            status(world, rt.player, "companion_away", nil)
            status(world, rt.player, "companion_stuck", nil)
            if okc and roster.main[rt.account or ""] == name then
              pcall(function() require("features.chat").notice_to(world, rt.player, "Companion has spawned near you!", "#8cd2ff", 5) end)
            end
          end
        end
      else
        rt.ground = nil
      end
    end
  end
end

-- ===== The Companion Roster window (owner 2026-11-20 10:00) =============================================================
-- "Companion Roster needs to be its own complete window" (opened by a button next to "Call my companion"): every
-- companion with its owner, kind, mode, items and chest; rename, change the kind (any non-boss monster template),
-- give / share / unshare, set main, put away / bring back, delete. No admin checks for now (owner: "another task for
-- another day"). The players' games ask on the channel flamekit/roster ({op = "get"}) and act ({op = "do", what, name,
-- arg}); a player who asked gets every change for 10 minutes ({op = "roster", list, players}) and the result of each
-- of his actions ({op = "result", text, ok}). Everything is kept in the roster table (the file is at Lua's 200
-- top-level locals). The existing console actions are reused (roster_cmd), their replies become the result line.
roster.RCH = "roster"
roster.subs = {}                   -- player entity -> tick of his last ask
roster.known = roster.known or {}  -- account -> the name last seen (players picked by name, also when offline)
roster.NAME_MAX = 20

function roster.ui_known(world)
  local ok, ids = pcall(players.ids, world)
  for _, pid in ipairs(ok and ids or {}) do
    local acc = world:account(pid)
    local n = acc and players.name(world, pid, nil)
    if n and roster.known[acc] ~= n then
      roster.known[acc] = n
      roster.known_changed = true
    end
  end
end

function roster.ui_state(world)
  local online = {}
  local ok, ids = pcall(players.ids, world)
  for _, pid in ipairs(ok and ids or {}) do local a = world:account(pid) if a then online[a] = true end end
  local list, seen, pl = {}, {}, {}
  local function person(acc, fallback)
    if not acc or seen[acc] then return end
    seen[acc] = true
    pl[#pl + 1] = { a = acc, n = roster.known[acc] or fallback or acc, on = online[acc] or false }
  end
  for acc, n in pairs(roster.known) do person(acc, n) end
  for _, r in ipairs(roster.list) do
    for _, a in ipairs(r.controllers or {}) do person(a, (r.names or {})[a]) end
    list[#list + 1] = { n = r.name, k = r.guid, o = r.owner or "", m = r.mode or "follow", f = r.fight or "Passive",
      out = r.out and true or false, it = inv.count(r.inv), ch = inv.open[r.name] and true or false,
      main = (r.owner and roster.main[r.owner] == r.name) and true or false, c = r.controllers or {} }
  end
  table.sort(pl, function(a, b) return tostring(a.n):lower() < tostring(b.n):lower() end)
  return emf.json.encode({ op = "roster", list = list, players = pl })
end

function roster.ui_send(world, pid, text)
  local ok, res = pcall(emf.net.send_to, world, pid, roster.RCH, text)
  if not (ok and res) then log("roster window: not sent to " .. tostring(pid) .. " (" .. tostring(res) .. ")") end
end

function roster.ui_push(world, force)
  local text = roster.ui_state(world)
  if not force and text == roster.ui_last then return end
  roster.ui_last = text
  local t = world:tick()
  for pid, at in pairs(roster.subs) do
    if t - at > 36000 or not world:position(pid) then roster.subs[pid] = nil else roster.ui_send(world, pid, text) end
  end
end

function roster.ui_tick(world)
  roster.ui_known(world)
  if roster.known_changed then
    roster.known_changed = false
    roster_save()
  end
  roster.ui_push(world, false)
end

-- a new name: 1 to NAME_MAX letters, digits, spaces, - _ ' . (the chest label shows it); not another companion's
function roster.ui_rename(world, r, new)
  new = tostring(new or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
  if new == "" or #new > roster.NAME_MAX then return "A name needs 1 to " .. roster.NAME_MAX .. " characters.", false end
  if new:find("[^%w %-_'%.]") then return "Names can only have letters, digits, spaces and - _ ' .", false end
  for _, o in ipairs(roster.list) do
    if o ~= r and o.name:lower() == new:lower() then return "Another companion is already called " .. o.name .. ".", false end
  end
  if inv.open[r.name] then return r.name .. ": close his chest first.", false end
  local old = r.name
  if old == new then return "That is already his name.", true end
  for _, t in ipairs({ ent_of, returning, mana_of, waiting }) do
    if t[old] ~= nil then t[new], t[old] = t[old], nil end
  end
  for id, n in pairs(name_of) do if n == old then name_of[id] = new end end
  for a, n in pairs(roster.main) do if n == old then roster.main[a] = new end end
  r.name = new
  roster_save()
  log(string.format("roster window: %s renamed to %s", old, new))
  return old .. " is now called " .. new .. ".", true
end

-- another kind: any non-boss monster template (core/monsters.lua); a body that is out is replaced at its spot
function roster.ui_kind(world, r, guid, pid)
  local kind
  for _, m in ipairs(require("core.monsters")) do if m[3] == guid then kind = m end end
  -- (0.15.313, owner 11:40) the Pets section: the game's peaceful animals (core/pets.lua); not driven yet (pets come next)
  for _, m in ipairs(require("core.pets")) do if m[3] == guid then kind = m end end
  if not kind then return "Unknown kind.", false end
  if kind[4] then return "Bosses cannot be companions.", false end
  if inv.open[r.name] then return r.name .. ": close his chest first.", false end
  if r.guid == guid then return r.name .. " already is a " .. kind[2] .. ".", true end
  local was = r.guid
  r.guid, r.sus_base = guid, nil  -- (armor) the new body's own values are read again
  local ent = ent_of[r.name]
  if ent and world:position(ent) then
    local x, y, z = world:position(ent)
    local h = drives[ent]
    drives[ent], name_of[ent], ent_of[r.name] = nil, nil, nil
    pcall(emf.destroy, world, ent)
    spawn_body(world, r, x, y + 0.3, z, r.mode == "follow" and (h and h.player or player_of(world, r.owner)) or nil)
  end
  roster_save()
  log(string.format("roster window: %s is now %s / %s (%s, was %s)", r.name, kind[1], kind[2], guid, tostring(was)))
  if kind[1] == "Pets" then return r.name .. " is now a pet: " .. kind[2] .. ". Pets do not follow yet (they come next).", true end
  return r.name .. " is now a " .. kind[2] .. " (" .. kind[1] .. ").", true
end

-- (owner 11:26 "can you make "Bring back" spawn the companion next to the player? I just put N2 away and brought back
-- and its not near me") next to the player who clicked, 0.3 m to his right and facing his way (as Call): a follower
-- follows him, a stayer stays at that new spot
function roster.ui_back(world, r, pid)
  if r.out and still_ours(world, ent_of[r.name]) then return r.name .. " is already out.", false end
  local x, y, z = world:position(pid)
  if not x then return "You are not in the world.", false end
  local yaw
  pcall(function()
    local o = world:get("CurrentTransform", pid).transform.orientation
    yaw = math.atan(2 * (o.x * o.z + o.w * o.y), 1 - 2 * (o.x * o.x + o.y * o.y))
    x, z = x + math.cos(yaw) * 0.3, z - math.sin(yaw) * 0.3
  end)
  if r.mode == "stay" then r.x, r.y, r.z = x, y, z end
  r.face_yaw = yaw
  local id = spawn_body(world, r, x, y + 0.5, z, r.mode == "follow" and pid or nil)
  if id and yaw then
    pcall(function()
      local o = world:get("CurrentTransform", id).transform.orientation
      o.x, o.y, o.z, o.w = 0, math.sin(yaw / 2), 0, math.cos(yaw / 2)
    end)
  end
  roster_save()
  if not id then return r.name .. " could not be spawned.", false end
  return r.name .. " is back next to you" .. (r.mode == "stay" and " (staying there)." or ", following you."), true
end

-- (pets, owner 12:43/12:48 "n2 is a dog now") petlog: the wildlife AI of an animal body (program "wildlife": it writes
-- ActorInput, DynamicLocomotion, DynamicPathWalker, DynamicWildlife)
function roster.petlog_tick(world)
  local pl = roster.petlog
  local id = pl.id
  if world:tick() > pl.untill or not world:position(id) then roster.petlog = nil log("petlog " .. id .. ": done") return end
  local function rd(f) local ok, v = pcall(f) if ok then return v end return "err" end
  local x, y, z = world:position(id)
  local wl = rd(function() local w = world:get("DynamicWildlife", id) return string.format("state %s (last %s), target %.1f %.1f %.1f, keep until %s, flee %s",
    tostring(w.state), tostring(w.lastState), w.currentTargetPosition.x, w.currentTargetPosition.y, w.currentTargetPosition.z,
    tostring(w.keepRoamingTargetUntilTime), tostring(w.lastFleeTime)) end)
  local ai = rd(function() local a = world:get("ActorInput", id) return string.format("move %.2f %.2f speed %s",
    a.desiredWorldMoveInput.x, a.desiredWorldMoveInput.z, tostring(a.locomotionSpeed)) end)
  local pw = rd(function() local p = world:get("DynamicPathWalker", id) return string.format("walker %s, to %.1f %.1f %.1f",
    tostring(p.state), p.targetPosition.x, p.targetPosition.y, p.targetPosition.z) end)
  local an = rd(function() local a = world:get("DynamicAnimal", id) return "animal state " .. tostring(a.state) end)
  log(string.format("petlog %d at %.1f %.1f %.1f: %s | %s | %s | %s | time %s", id, x, y, z, tostring(wl), tostring(ai), tostring(pw),
    tostring(an), tostring(rd(function() return world:get("SpawnTime", id).time end))))
  -- (owner 14:09 "remove the pick up and pet option") the game's offer on the animal: which sequence / verb it shows
  local function sv(v)
    if type(v) ~= "table" then return tostring(v) end
    local t = {}
    for k, x in pairs(v) do t[#t + 1] = tostring(k) .. "=" .. sv(x) end
    table.sort(t)
    return "{" .. table.concat(t, " ") .. "}"
  end
  local of = rd(function() local o = world:get("InteractionOfferRuntime", id) if not o then return "none" end
    return string.format("default seq %s verb %s, override seq %s verb %s, offerId %s, offered %s, disabled %s, last guest %s offer %s",
      sv(o.defaultSequence), sv(o.defaultVerbId), sv(o.overrideSequence), sv(o.overrideVerbLocaId), sv(o.offerId),
      sv(o.isOffered), sv(o.isDisabled), sv(rd(function() return o.lastAcceptData.guestId end)), sv(rd(function() return o.lastAcceptData.offerId end))) end)
  log(string.format("petlog %d offer: %s | tame %s | emf offer %s", id, tostring(of),
    tostring(rd(function() return world:get("IsTame", id) ~= nil end)), tostring(rd(function() return emf.offered and emf.offered(world, id) end))))
end

-- (pets) the drive's inputs for the server probe, in pet_drive.txt beside the mod: a line per pet "<entity> <target x y
-- z> <player spot x y z> <code>" (code: pace 2 walk / 3 run / 4 sprint, + 10 edge stop off, + 20 drops allowed; 0 = not
-- driven), written each tick it changes; its drive_post reads it. (13:04: the first try kept them in the animal's own
-- AnimalSaved / DynamicWildlife spawn positions: the game moved the dog by them, 20 m jumps every half second.)
roster.pet_lines = {}
function roster.pet_flush(world, id, h)
  local a = h.shim
  local cd = a.combatData
  local code = a.movementTargetIsValid and ((tonumber(cd.prowlAngle) or 2) + (cd.targetOfMyTarget and 10 or 0)
    + (cd.isTargetInsideLeash and 20 or 0)) or 0
  roster.pet_lines[id] = string.format("%d %.3f %.3f %.3f %.3f %.3f %.3f %g", id, a.movementTarget.x, a.movementTarget.y,
    a.movementTarget.z, a.homeZonePosition.x, a.homeZonePosition.y, a.homeZonePosition.z, code)
  cd.targetOfMyTarget = false  -- set again each tick where the edge stop is off (edge_off)
end
function roster.pet_write()
  local list = {}
  for id, line in pairs(roster.pet_lines) do if drives[id] then list[#list + 1] = line end end
  roster.pet_lines = {}
  table.sort(list)
  local text = table.concat(list, "\n") .. "\n"
  if text == roster.pet_text or not emf.dir then return end
  local f = io.open(emf.dir .. "\\pet_drive.tmp", "w")
  if not f then return end
  f:write(text)
  f:close()
  os.remove(emf.dir .. "\\pet_drive.txt")
  os.rename(emf.dir .. "\\pet_drive.tmp", emf.dir .. "\\pet_drive.txt")
  roster.pet_text = text
end

function roster.pets_quiet(world)
  for _, id in pairs(ent_of) do
    local wl = world:get("DynamicWildlife", id)
    if wl and not world:get("DynamicEnemy01BehaviorState", id) then
      if wl.state ~= 3 then wl.state = 3 end
      local pw = world:get("DynamicPathWalker", id)
      if pw and pw.isWalkingActive ~= false then pw.isWalkingActive = false end
      pcall(roster.pet_offer, world, id)
    end
  end
end

-- (owner 14:09 "yeah we need to remove the pick up and pet option, the pet option could be put in the wheel") a tame
-- pet's game offer is verb Pet (0x6D5B6297) with the game's pet sequence (0xB1EB4A70; petlog 14:11:55), which also lets
-- a player pick him up (14:07:42: the body was gone). It is replaced by the plain touch sequence (no screen, EMF's
-- EMF_SEQUENCE_TOUCH) and the word Talk, so E only fires InteractionAcceptedEvent (his wheel, in F.setup).
roster.TOUCH_SEQ, roster.TALK_VERB = 0x3E5189BF, 0xD9861C4B
roster.offer_fixes = {}
function roster.pet_offer(world, id)
  local o = world:get("InteractionOfferRuntime", id)
  if not o then return end
  if o.overrideSequence == roster.TOUCH_SEQ and o.overrideVerbLocaId == roster.TALK_VERB then return end
  local before = string.format("seq %s verb %s", tostring(o.overrideSequence), tostring(o.overrideVerbLocaId))
  o.overrideSequence = roster.TOUCH_SEQ
  o.overrideVerbLocaId = roster.TALK_VERB
  local n = (roster.offer_fixes[id] or 0) + 1
  roster.offer_fixes[id] = n
  if n == 1 or n % 100 == 0 then
    log(string.format("pet %s (%d): the game's offer (%s) set to touch / Talk (time %d)", tostring(name_of[id]), id, before, n))
  end
end

function roster.ui_do(world, from, data)
  local okd, m = pcall(emf.json.decode, data)
  if not (okd and type(m) == "table") then return end
  local pid = from.player
  if not pid then return end
  roster.subs[pid] = world:tick()
  if m.op == "get" then
    roster.ui_known(world)
    roster.ui_send(world, pid, roster.ui_state(world))
    return
  end
  if m.op ~= "do" then return end
  local what, arg = tostring(m.what or ""), m.arg
  local r = find(tostring(m.name or ""))
  local said, good
  if what == "new" then  -- (0.15.310) a hound of the asking player, next to him, following him (roster new)
    local real = emf.reply
    emf.reply = function(t) said = t end
    local okc, errc = pcall(roster_cmd, world, { "roster", "new", tostring(pid) })
    emf.reply = real
    local made = okc and tostring(said or ""):match("^roster: new (.+)$")
    said, good = made and (made .. " is made: a hound next to you, following you.") or ("Not made: " .. tostring(okc and said or errc)), made and true
  elseif not r then
    said, good = "No companion called " .. tostring(m.name) .. ".", false
  elseif what == "rename" then
    said, good = roster.ui_rename(world, r, arg)
  elseif what == "kind" then
    said, good = roster.ui_kind(world, r, tostring(arg or ""), pid)
  elseif what == "back" then
    said, good = roster.ui_back(world, r, pid)
  else
    local args
    if what == "away" or what == "delete" then args = { "roster", what, r.name }
    elseif what == "give" or what == "share" or what == "unshare" then args = { "roster", what, r.name, tostring(arg or "") }
    elseif what == "main" then args = r.owner and { "roster", "main", r.name, r.owner } end
    if not args then
      said, good = what == "main" and (r.name .. " has no owner.") or "Unknown action.", false
    else
      local real = emf.reply
      emf.reply = function(t) said = t end
      local okc, errc = pcall(roster_cmd, world, args)
      emf.reply = real
      if not okc then said = "Failed: " .. tostring(errc) end
      said = tostring(said or "Done."):gsub("^roster: ", "")
      good = okc and not said:find("refused") and not said:find("^no ") and not said:find("already")
      if good then  -- the window's words for what was done
        local who = arg and (roster.known[tostring(arg)] or tostring(arg))
        local owner = r.owner and (roster.known[r.owner] or r.owner)
        local nice = { give = r.name .. " now belongs to " .. tostring(who) .. ".",
          share = tostring(who) .. " can now command " .. r.name .. ".",
          unshare = tostring(who) .. " can no longer command " .. r.name .. ".",
          main = r.name .. " is now " .. tostring(owner) .. "'s main companion.",
          away = r.name .. " is put away.", back = r.name .. " is back.", delete = r.name .. " is deleted." }
        said = nice[what] or said
      end
    end
  end
  log(string.format("roster window: player %s (%s): %s %s %s -> %s", tostring(pid), tostring(from.account), what,
    tostring(m.name), tostring(arg), tostring(said)))
  roster.ui_send(world, pid, emf.json.encode({ op = "result", text = said, ok = good and true or false }))
  roster.ui_push(world, true)
end

return F
