-- features/companions/03_follow.lua: part 3 of the companion code (the server side), split from npc_probe.lua in 0.15.362
-- (owner 2026-11-20 18:11). The parts run in order in ONE shared environment (features/companions.lua): what was a
-- top-level local is a name in that environment, seen by every part.
-- ===== The drive's numbers =============================================================================================
-- Swimming: his body is held FLOAT_LIFT above the player's height while diving, tilted nose up FLOAT_PITCH degrees.
FLOAT_LIFT = 0.45  -- metres
PET_DIVE_STEP = 0.4  -- (owner 15:36, pets only) metres a tick a pet may be moved up or down while swimming
FLOAT_PITCH = 28  -- degrees, nose up
SWIM_OUT_STOP = 0.8  -- in the water with the player on land, he only stops this close (he has not arrived while he swims)
-- Jumps (drive_copy, drive_jump_follow): he jumps where the player jumped (the next crumb is a landing) and up every
-- step of STEP_UP or more the player went up; the launch aims DJ_MARGIN over the crumb, a flight lasts at most DJ_TICKS,
-- the launch speed is written for up to DJ_LIFT ticks until the game counts him in the air, and after a jump up he
-- stands still DJ_SETTLE ticks.
STEP_UP = 0.6  -- (the old ray step jump's threshold; smaller steps his own legs take)
DJ_MARGIN, DJ_TICKS = 0.7, 150
DJ_SETTLE = 45
DJ_LIFT = 40
-- Put away and back (drive_put_away, F.tick): the glider is the player's locomotion state GLIDE_STATE; still gliding
-- after GLIDE_WAIT ticks or GLIDE_FAR metres away, he is put away. The player moving more than FAR_JUMP in one tick
-- (a fast travel) puts him away too, and so does TP_AFTER ticks of not being able to follow. He comes back beside the
-- player once the player has stood on the ground LAND_TICKS (and his game has loaded).
-- (owner 2026-11-19 22:22 "get rid of the 2 seconds, show the error, but teleport him immediately") TP_AFTER 0: put
-- away the moment he cannot follow; the notice then shows 5 s on its own (put_away_for)
GLIDE_STATE, GLIDE_WAIT, GLIDE_FAR, LAND_TICKS, TP_AFTER, FAR_JUMP = 4, 240, 30, 60, 0, 50
WATER_NEAR = 2  -- metres above the swimming player's water surface that still count as "at the water"
DIVE_PLAYER = 1.8  -- the player's depth from which he dives with him (at the surface the player reads about 1.3)
SWIM_ENTER, SWIM_DEPTH = 0.5, 0.9  -- he swims while his own depth is over 0.5 m, and is held at about 0.9 m
F.SWIM_ENTER_SMALL, F.SWIM_DEPTH_SMALL = 0.25, 0.3  -- (owner 17:24) the same for a small pet (cats, bunnies, birds; in F:
-- the file is at Lua's 200 top-level locals)
SWIM_MAX, SWIM_GAIN = 6, 1.2  -- swimming speed: 1 m/s past the stop distance, +1.2 m/s per metre, at most 6
HOP_TICKS, HOP_HOLD, HOP_EVERY, HOP_MARGIN, HOP_FORWARD = 90, 40, 120, 0.7, 3  -- the climb-out hop, see drive_water
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
drives = {}  -- entity -> his record h: { player, trail = {}, ... }
-- a hold (console "hold", for tests): he stays where he stands and turns toward a target until the time is up
holds = {}  -- entity -> { target, untill (tick) }
DRIVE_STOP, DRIVE_STEP = 2, 0.25  -- he stops within 2 m of the player (the C++ kFollowStop matches); a crumb every 0.25 m
CRUMB_REACH = 0.3  -- a crumb within this is reached; he aims at the first one further away
-- Drops and flights: no crumbs while the player is off the ground. A crumb more than DROP_HEIGHT below the one before
-- (just below his own fall damage: from 8 m, lethal at 16 m), or the first one after more than DROP_AIR_TICKS in the
-- air (a glide, not a jump), is a break (brk): a way he cannot copy. Smaller drops he follows: he walks off as the
-- player did.
DROP_HEIGHT = 7.5
DROP_AIR_TICKS = 120
-- the "can't follow" notice says why ("stuck" itself is only for a real clipping problem)
STUCK_TEXT = {
  down = "Companion is afraid to follow (too steep)!",
  drop = "Companion is afraid to follow (drop too high)!",
  up = "Companion can't get up there!",
  blocked = "Companion can't follow you!",
}
STUCK_TICKS = 180  -- 3 s without 0.3 m of progress toward his crumb: he cannot follow
CRUMB_LOG = true  -- every crumb of every companion into the server log
-- the player is off the ground unless he has ground contact, under 0.1 m from it, and locomotion state 0 (the game keeps
-- "ground contact" for the first and last part of a jump)
function player_airborne(world, player)
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
BLOCK_R = 2.5
function blockers(world, id, player, nx, ny, nz, fx, fz)
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
drive_fight = nil
drive_heal = nil
-- (inventory, see "Inventory" below) inv.open: companion name -> his open chest (he is frozen while it exists); the
-- functions and settings live in this one table (the file is at Lua's 200 locals)
inv = { open = {} }

-- his body upright and turned toward yaw (radians, 0 = +z)
function face(world, id, yaw)
  local o = world:get("CurrentTransform", id).transform.orientation
  o.x, o.y, o.z, o.w = 0, math.sin(yaw / 2), 0, math.cos(yaw / 2)
end

-- (owner 2026-11-19 16:37, list #8: his pace from the crumb meta data) the pace for the C++ drive, in
-- combatData.prowlAngle (his game AI is off, so nothing else writes it): 2 walk, 3 run, 4 sprint (LocomotionSpeedSelector).
-- The player's crumb speeds (6700 crumbs, 2026-11-19): ~2-3 m/s walking, ~4-5 running, ~8-9 sprinting.
PACE_WALK, PACE_RUN, PACE_SPRINT = 2, 3, 4
PACE_RUN_AT, PACE_SPRINT_AT = 3.5, 7
function set_pace(a, pace)
  pcall(function() a.combatData.prowlAngle = pace end)
end

-- the native hook's target and its "player" spot both at x, y, z: he stands there
function hold_at(a, x, y, z)
  a.homeZonePosition.x, a.homeZonePosition.y, a.homeZonePosition.z = x, y, z
  a.movementTarget.x, a.movementTarget.y, a.movementTarget.z = x, y, z
  a.movementTargetIsValid = true
end

-- his health for the logs (-1 when it cannot be read)
function health(world, id)
  local hp = -1
  pcall(function() hp = world:get("Health", id).dataStorage[1] end)
  return hp
end

-- the native edge stop off for this tick
function edge_off(a)
  pcall(function() a.combatData.targetOfMyTarget = true end)
end

-- a jump-follow launch: the speeds that carry him d metres across and rise metres up (gravity 25; up at most 16 m/s
-- for rise + DJ_MARGIN, across at most 10 m/s so that he comes down at the spot)
function launch_speeds(d, rise)
  local vup = math.min(16, math.sqrt(2 * 25 * math.max(0.5, rise + DJ_MARGIN)))
  local disc = math.max(0, vup * vup - 2 * 25 * rise)
  local tdown = (vup + math.sqrt(disc)) / 25
  local vh = math.min(10, d / math.max(0.2, tdown))
  return vup, vh
end

-- the launch itself: lifted 0.3 m first (a speed written on the ground does not take), then his speed up and across
-- toward ddx, ddz, turned that way. Returns whether the speed could be set, and the speed across (x, z).
function launch(world, id, ddx, ddz, d, vup, vh)
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
function report_blockers(s, what, dx, dz)
  local bk, bline = blockers(s.world, s.id, s.h.player, s.nx, s.ny, s.nz, dx, dz)
  s.h.blocked_by = bk
  log(string.format("%s: %s in his way: %s", what, tostring(s.id), bline))
end

-- he cannot follow (why: a STUCK_TEXT key): the notice once, he stands (drive_stuck), and drive_put_away respawns him
-- beside the player after TP_AFTER. h.cant is the one "cannot follow" state, on land and in the water.
function cant_follow(s, why, detail)
  local h = s.h
  if h.cant then return end
  h.cant = why
  log(string.format("can't follow: %s %s: %s (at %.1f %.1f %.1f, player %.1f m away, %.1f m %s)", tostring(s.id), why, detail,
    s.nx, s.ny, s.nz, math.sqrt((s.px - s.nx) ^ 2 + (s.pz - s.nz) ^ 2), math.abs(s.py - s.ny), s.py >= s.ny and "higher" or "lower"))
  fullrec_event(s.world, s.id, "drive: can't follow (" .. why .. ")")
  if F.follow_notices(s.world, h.player) then  -- (owner 16:20) a Debug option, default off
    status(s.world, h.player, "companion_stuck", STUCK_TEXT[why] or STUCK_TEXT.blocked, "#ff9050")
  end
end

-- the "cannot follow" state is over (he moves again, or something else takes over)
function cant_over(s, why)
  local h = s.h
  if not h.cant then return end
  h.cant, h.cant_since = nil, nil
  log(string.format("can't follow: %s over: %s", tostring(s.id), why))
  status(s.world, h.player, "companion_stuck", nil)
end

-- the tick's facts: where the player and the hound are, his AI kept off, and the water both read (currentWaterState
-- is the depth below the surface); nil when either body is gone
function drive_read(world, id, h)
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
  -- (owner 17:24 "go ahead and make the adjustment") 17:21:47: the black cat stood in 0.40 m of water, below SWIM_ENTER,
  -- so to the drive he walked; no progress toward the swimming player: put away. A small pet (F.SMALL_PETS) swims
  -- from F.SWIM_ENTER_SMALL and is held F.SWIM_DEPTH_SMALL below the surface (s.small, drive_water)
  local small = pet and F.is_small and F.is_small(id) or false
  local swim = hw > (small and F.SWIM_ENTER_SMALL or SWIM_ENTER)
  return { small = small, world = world, id = id, h = h, a = a, t = t, px = px, py = py, pz = pz, nx = nx, ny = ny, nz = nz,
           pwater = pwater, pwet = pwet, hw = hw, swim = swim, pet = pet }
end

-- the water log (measuring only): once a second while the player or the hound reads any water, and 5 s after; both
-- water readings, his submerge depth, heights, ground, locomotion state, speed and its direction, the input the drive
-- gave him, his facing, the way to the player (compass angles, 0 = +z), his air and health, the player's air
function drive_waterlog(s)
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
function drive_water(s)
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
    local want = diving and (py + FLOAT_LIFT - ny) or (hw - (s.small and F.SWIM_DEPTH_SMALL or SWIM_DEPTH))
    local fix = math.max(-0.08, math.min(0.08, want * 0.25))  -- at most 0.08 m a tick
    -- (owner 15:35 "the pet dog swims but doesn't really follow me all the way down into the water"; 15:36 "only valid
    -- for pets") 15:34: diving, the dog stayed ~2.3 m deep while the player was 4-5.5 m: the game lifts an animal more
    -- than 0.08 m a tick. A pet: half the difference each tick, at most PET_DIVE_STEP.
    if s.pet then
      fix = math.max(-PET_DIVE_STEP, math.min(PET_DIVE_STEP, want * 0.5))
      if diving and t % 60 == 0 then
        log(string.format("dive %s (pet): the player at %.2f, he at %.2f (wants %.2f m, step %.2f)", tostring(id), py, ny, want, fix))
      end
    end
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
function drive_track_player(s)
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
FALL_SAFE = 7.5
function drive_put_away(s)
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
function drive_lay_crumb(s)
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
function drive_upkeep(s)
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
function drive_jump_follow(s)
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
function drive_lure(s)
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
function drive_hold(s)
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
function drive_pick_target(s)
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
function drive_copy(s)
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
SHOUT_HOLD = 120
SLOT_AT = 1.5  -- (15:55) metres from his place around the player that count as "there" (see drive_stuck)
NEAR_LEVEL = 1.5  -- (16:20) within SLOT_NEAR of the player and this much higher or lower: no "can't follow"
-- (16:28: drive_stuck used SLOT_NEAR before it was declared further down: nil, every follower's drive failed) the
-- followers' places (drive_steer) are used within SLOT_NEAR of the player, at least SLOT_GAP apart
SLOT_NEAR, SLOT_GAP = 6, 2.5
function drive_stuck(s)
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
    -- (owner 15:55 "with multiple companions open they're seem to all be fighting to get to me and I'm getting lots of
    -- "Companion can't follow you!" messages") 15:54-15:55: N3, follower 3 of 3, stood at his place (0.4 m from it,
    -- 2.8 m from the player) and made no progress toward the crumb at the player's feet: "can't follow", respawned,
    -- again every 8 s. A follower standing within SLOT_AT of his place (set by drive_steer this half second) has arrived.
    local sa = h.slot_at
    local at_slot = sa and t - sa.t < 30 and (sa.x - nx) ^ 2 + (sa.z - nz) ^ 2 <= SLOT_AT * SLOT_AT
    -- (owner 16:20 "I'm still getting a ton of errors with them saying they can't follow and then they respawn back...
    -- I'm just standing here") 16:20-16:21: N1, follower 5 of 5, stood 1.6 m from his place and 3.3 m from the player,
    -- level with him, never got closer: can't follow, respawned at the same spot every 5 s. Within SLOT_NEAR of the
    -- player and level with him (NEAR_LEVEL) he is with the player: never "can't follow" there
    local with_player = dp and dp <= SLOT_NEAR and math.abs(s.py - ny) < NEAR_LEVEL
    at_slot = at_slot or with_player
    local gap_wait = t - (h.gap_t or -1e9) < 30 or t - (h.settle_t or -1e9) < 30  -- (16:00) waiting for the follower
    -- ahead (drive_steer, TRAIL_GAP); (16:08) settled near the player
    if h.prog == nil or h.prog.c ~= c or dc < h.prog.d - 0.3 or t - (h.heal_t or -1e9) < SHOUT_HOLD or at_slot or gap_wait then
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
-- (owner 15:59 "anyway to space out the pets a little bit more from each other, when they run or I stop they all just
-- bunch right up on me"; 16:00 "pets and companion monsters too") the places 1.5 times as far out (were 1.6-3.3 m from
-- the player, 1.5 m apart), SLOT_NEAR 6 (was 4) so the farther places are still used, and on the trail TRAIL_GAP
SLOTS = { { -2.4, -1.2 }, { 2.4, -1.2 }, { 0, -3.3 }, { -3.6, -3.3 }, { 3.6, -3.3 } }  -- (12:22) followers 2..6
-- (SLOT_NEAR, SLOT_GAP: declared above drive_stuck, which uses SLOT_NEAR too)
TRAIL_GAP_GO = 3.5  -- (16:02) a waiting follower goes on once the one ahead is this far
-- (owner 16:08 "the spacing changes made it hard for me to go up to one of the pets, the run around a lot when I try
-- to move ... maybe theres a small radius we can add so as long as they're in that radius around me, they don't move
-- around so much?") once a follower has arrived (the first within SETTLE_ARRIVE of the player, the others at their
-- place), he stays where he stands while the player is within SETTLE_R of him; past it he follows again
SETTLE_R, SETTLE_ARRIVE, SETTLE_PLACE = 6, 2.7, 2.5
TRAIL_GAP = 2.5  -- (16:00) on the trail a follower stands while another of the player's is closer to the player
                       -- and within this of him (a queue instead of a bunch); drive_stuck counts that as no stuck
function drive_steer(s)
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
        h.slot_at = { x = tx, z = tz, t = t }  -- (15:55) drive_stuck: standing at his place is not "stuck"
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
  -- (owner 16:08) settled: he stands while the player is within SETTLE_R; he settles once he has arrived
  if h.settled and dp and dp > SETTLE_R then
    h.settled = nil
    log(string.format("settle %s: the player is %.1f m away: follows again", tostring(id), dp))
  end
  if not h.settled and dp and dp <= SETTLE_R then
    local sa = h.slot_at
    -- (16:20: N1 stopped 1.6 m from his place) a place counts as reached within SETTLE_PLACE
    local at_place = (sa and sa.t == t) and ((sa.x - nx) ^ 2 + (sa.z - nz) ^ 2 <= SETTLE_PLACE * SETTLE_PLACE) or (not (sa and sa.t == t) and dp <= SETTLE_ARRIVE)
    if at_place then
      h.settled = true
      log(string.format("settle %s: arrived (%.1f m from the player): stays while the player is within %.1f m", tostring(id), dp, SETTLE_R))
    end
  end
  if h.settled then
    h.settle_t = t
    hold_at(a, nx, s.ny, nz)
    return
  end
  -- (owner 15:59 / 16:00) on the trail, further than SLOT_NEAR: he waits while another follower of the same player is
  -- within TRAIL_GAP of him and closer to the player
  if c and dp and dp > SLOT_NEAR then
    local wait_for
    -- (16:02: at exactly 2.5 m he stopped and went on several times a second) a waiting one goes on past GAP_GO
    local gap = h.gap_said and TRAIL_GAP_GO or TRAIL_GAP
    for oid, oh in pairs(drives) do
      if oid ~= id and oh.player == h.player then
        local ox, _, oz = world:position(oid)
        if ox and (ox - nx) ^ 2 + (oz - nz) ^ 2 < gap * gap and (ox - px) ^ 2 + (oz - pz) ^ 2 < dp * dp then
          wait_for = oid
          break
        end
      end
    end
    if wait_for then
      h.gap_t = t
      if not h.gap_said then
        h.gap_said = true
        log(string.format("gap %s: waits for %s (within %.1f m of him, closer to the player)", tostring(id), tostring(wait_for), TRAIL_GAP))
      end
      hold_at(a, nx, s.ny, nz)
      return
    elseif h.gap_said then
      h.gap_said = nil
      log(string.format("gap %s: goes on", tostring(id)))
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
function drive_step(world, id, h)
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
  if drive_water(s) then
    -- (owner 15:44 "I'm getting the Companion can't follow you error, but it hasn't respawned to me") 15:43:38 a pet
    -- swimming at a bank 2 m below the player: "can't follow (water)", but drive_put_away is never reached from the
    -- water, so nothing put him away. The same TP_AFTER rule here (every companion: it is the shared safety net).
    if s.h.cant then
      s.h.cant_since = s.h.cant_since or s.t
      if s.t - s.h.cant_since >= TP_AFTER and not s.h.go_away then
        s.h.go_away = "can't follow"
        log(string.format("can't follow: %s in the water: put away", tostring(id)))
      end
    end
    return
  end
  drive_track_player(s)
  if drive_put_away(s) then return end
  drive_lay_crumb(s)
  drive_upkeep(s)
  if drive_heal then drive_heal(s) end  -- never takes over the movement (pets too: always Healing, owner 15:22)
  if drive_jump_follow(s) then return end
  if drive_fight and not s.pet and drive_fight(s) then return end  -- (pets never fight: owner 09:51)
  if drive_lure(s) then return end
  if drive_hold(s) then return end
  drive_pick_target(s)
  if drive_copy(s) then return end
  if drive_stuck(s) then return end
  drive_steer(s)
end

