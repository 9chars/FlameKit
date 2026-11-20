import re, sys
p = 'local_server/features/npc_probe.lua'
s = open(p, encoding='utf-8').read()
def rep(o, n, c=1):
    global s
    assert s.count(o) == c, (o[:80], s.count(o)); s = s.replace(o, n)
def cut(start_marker, end_marker, new):
    # replace from start_marker (inclusive) up to end_marker (exclusive)
    global s
    a = s.index(start_marker); b = s.index(end_marker, a)
    assert s.count(start_marker) == 1
    s = s[:a] + new + s[b:]

# ---- numbers -------------------------------------------------------------------------------------------------------
rep('''-- Jump follow (drive_jump_follow): he launches from within DJ_AT of a takeoff crumb toward a landing DJ_RISE or more
-- higher, aiming DJ_MARGIN over it; a flight lasts at most DJ_TICKS. When he makes no progress for DJ_WAIT toward a
-- crumb that is DJ_RISE or more up and at most DJ_REACH away, he jumps up to it too. The launch speed is written for
-- up to DJ_LIFT ticks until the game counts him in the air; after a landing up top he stands still DJ_SETTLE ticks.
local DJ_AT, DJ_RISE, DJ_MARGIN, DJ_TICKS, DJ_WAIT, DJ_REACH = 1.5, 1.0, 0.7, 150, 60, 6
local DJ_SETTLE = 45
local DJ_LIFT = 40
local STUCK_MOVED = 1.5  -- the player must have moved this far since he gave up before "back near him" counts''',
'''-- Jumps (drive_copy, drive_jump_follow): he jumps where the player jumped (the next crumb is a landing) and up every
-- step of STEP_UP or more the player went up; the launch aims DJ_MARGIN over the crumb, a flight lasts at most DJ_TICKS,
-- the launch speed is written for up to DJ_LIFT ticks until the game counts him in the air, and after a jump up he
-- stands still DJ_SETTLE ticks.
local STEP_UP = 0.6  -- (the old ray step jump's threshold; smaller steps his own legs take)
local DJ_MARGIN, DJ_TICKS = 0.7, 150
local DJ_SETTLE = 45
local DJ_LIFT = 40''')
rep('''local DRIVE_STOP, DRIVE_STEP = 2, 0.25  -- he stops within 2 m of the player (the C++ kFollowStop matches); a crumb every 0.25 m
local CRUMB_REACH = 0.3  -- a crumb within this is reached; he aims at the first one further away
local FLOOR_LINK, FLOOR_REACH = 0.7, 3.6  -- the floor proof, see drive_steer
local FLOOR_FIRST = 1.5  -- (owner 17:46 "sure") the first link, from where he stands to the nearest crumb, may be this long
''','''local DRIVE_STOP, DRIVE_STEP = 2, 0.25  -- he stops within 2 m of the player (the C++ kFollowStop matches); a crumb every 0.25 m
local CRUMB_REACH = 0.3  -- a crumb within this is reached; he aims at the first one further away
''')
rep('''-- Drops and flights: no crumbs while the player is off the ground. A crumb more than DROP_HEIGHT below the one before
-- (just below his own fall damage: from 8 m, lethal at 16 m), or the first one after more than DROP_AIR_TICKS in the
-- air (a glide, not a jump), starts a new piece of trail (brk): he walks to the last crumb before it and waits there,
-- and goes on when the player is back within DROP_RESUME on his level.
local DROP_HEIGHT, DROP_RESUME = 7.5, 6
local DROP_AIR_TICKS = 120
local DROP_AT = 1.5  -- (owner 17:59 "yes") he is at the last safe crumb within this (the native edge ray looks 1.5 m ahead and holds him back from the lip)
-- the stuck notice says what holds him ("stuck" itself is only for a real clipping problem)''',
'''-- Drops and flights: no crumbs while the player is off the ground. A crumb more than DROP_HEIGHT below the one before
-- (just below his own fall damage: from 8 m, lethal at 16 m), or the first one after more than DROP_AIR_TICKS in the
-- air (a glide, not a jump), is a break (brk): a way he cannot copy. Smaller drops he follows: he walks off as the
-- player did.
local DROP_HEIGHT = 7.5
local DROP_AIR_TICKS = 120
-- the "can't follow" notice says why ("stuck" itself is only for a real clipping problem)''')
rep('''local STUCK_TICKS = 180  -- 3 s without 0.3 m of progress toward his crumb: he gives up''',
    '''local STUCK_TICKS = 180  -- 3 s without 0.3 m of progress toward his crumb: he cannot follow''')

# ---- the following block comment ------------------------------------------------------------------------------------
rep('''-- movement input (direction, look, walk/run/sprint by distance, nothing within DRIVE_STOP of the player), with an edge
-- stop and a step jump of its own; the game's locomotion moves and animates him. combatData.targetOfMyTarget = true
-- turns the native edge stop and step jump off; combatData.isTargetInsideLeash = true lets him drop down (see
-- drive_steer). No route search and no game follow orders.''',
'''-- movement input (direction, look, walk/run/sprint by distance, nothing within DRIVE_STOP of the player), with an edge
-- stop of its own; the game's locomotion moves and animates him. combatData.targetOfMyTarget = true turns the native
-- edge stop off; combatData.isTargetInsideLeash = true lets it allow drops up to 7.5 m. No route search and no game
-- follow orders.
-- (owner 2026-11-18 18:04-18:35, local_server/FOLLOW_PLAN.md) THE TRAIL IS THE TRUTH: he goes where the player went,
-- the way the player went (the crumbs' meta data says how). On the trail there is no edge stop (where the player
-- walked there was ground) and no ray step jump; ups come from the crumbs. Whatever he cannot copy, or no progress for
-- STUCK_TICKS: "can't follow", and after TP_AFTER he is respawned beside the player.''')

# ---- helpers: cant_follow / cant_over (after report_blockers) -------------------------------------------------------
rep('''local function report_blockers(s, what, dx, dz)
  local bk, bline = blockers(s.world, s.id, s.h.player, s.nx, s.ny, s.nz, dx, dz)
  s.h.blocked_by = bk
  log(string.format("%s: %s in his way: %s", what, tostring(s.id), bline))
end
''','''local function report_blockers(s, what, dx, dz)
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
''')

# ---- drive_water: the one state ------------------------------------------------------------------------------------
rep('''      -- in the water he swims to the player: any stuck or drop wait is over
      h.stuck, h.waiting, h.prog = nil, nil, nil
      status(world, h.player, "companion_stuck", nil)''','''      -- in the water he swims to the player: a "can't follow" from land is over
      h.prog = nil
      cant_over(s, "he is in the water")''')
rep('''      if h.wstuck then
        h.wstuck = nil
        status(world, h.player, "companion_stuck", nil)
        log("stuck (water): " .. tostring(id) .. " moves again")
      end''','''      cant_over(s, "he swims on (water)")''')
rep('''    if dist > stop and still > STUCK_TICKS and not h.wstuck then
      h.wstuck = true
      log(string.format("stuck (water): %s makes no progress (player %.1f m, %.1f m higher)", tostring(id), dist, py - ny))
      report_blockers(s, "stuck (water)", dx, dz)
      status(world, h.player, "companion_stuck", "Companion can't follow you!", "#ff9050")
    end''','''    if dist > stop and still > STUCK_TICKS and not h.cant then
      report_blockers(s, "can't follow (water)", dx, dz)
      cant_follow(s, "blocked", "no progress while swimming")
    end''')
rep('''    if h.wstuck then h.wstuck = nil status(world, h.player, "companion_stuck", nil) end''','''    cant_over(s, "out of the water")''')
rep('''-- where he swims; the yaw is kept in h.swim_yaw because reading it back from a tilted body goes wrong).''','''-- where he swims; the yaw is kept in h.swim_yaw because reading it back from a tilted body goes wrong). No progress
-- while swimming: the climb-out hop, and after STUCK_TICKS "can't follow" (over again when he moves on).''')
rep('''-- HOP_EVERY). None for STUCK_TICKS: the "can't follow" notice, cleared when he moves again.''','''-- HOP_EVERY). None for STUCK_TICKS: "can't follow" (cant_follow), over when he moves again.''')

# ---- drive_put_away -------------------------------------------------------------------------------------------------
rep('''-- a glide still going after GLIDE_WAIT or GLIDE_FAR away, a fast travel (FAR_JUMP in one tick), or TP_AFTER of not
-- being able to follow (stuck, waiting at a drop, or stuck in or on the way to the water).''','''-- a glide still going after GLIDE_WAIT or GLIDE_FAR away, a fast travel (FAR_JUMP in one tick), or TP_AFTER after he
-- could not follow (h.cant).''')
rep('''  if h.stuck or h.waiting or h.sstuck or h.wstuck then
    h.cant_since = h.cant_since or t''','''  if h.cant then
    h.cant_since = h.cant_since or t''')

# ---- drive_jump_follow: only the flight and the settle --------------------------------------------------------------
cut('-- Jump follow (returns true while a launch flies', '-- a lure (console "lure"', '''-- A jump in flight and the settle after it (returns true while either runs; drive_copy starts the jumps). In the air the
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

''')

# ---- drive_pick_target ----------------------------------------------------------------------------------------------
cut('-- His target (s.c, the crumb he heads for; nil = the player).', '-- Stuck and waiting (returns true while he stands).', '''-- His target (s.c, the crumb he heads for; nil = the player). Crumbs behind him and the ones he reached (within
-- CRUMB_REACH; the last one stays) are dropped; he heads for the first one further away. He has arrived when he is
-- within DRIVE_STOP of the player across AND in height (a player straight below or above him is not "here").
-- At the water: when the player swims and the hound stands at the water's level (at most WATER_NEAR above the surface
-- the player's depth gives, not more than 1 m below it), or after a leap, and the trail ahead is short (its last crumb
-- within 3 m, or none), he heads straight for the swimming player (h.to_swimmer) and stays on that while the player is
-- in the water. On that way his progress along the line to the player counts; none for STUCK_TICKS: "can't follow".
local function drive_pick_target(s)
  local world, id, h, t = s.world, s.id, s.h, s.t
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
-- crumb. A break (a drop over DROP_HEIGHT, a long flight): "can't follow". The player jumped to it (the crumb is a
-- landing) or it is STEP_UP or more above him (the player went up without a jump the log saw): he jumps to it.
-- Everything else (level, a small drop) he walks, and falls where the player fell.
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
  if not (c.landing or rise >= STEP_UP) then return false end
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
    c.landing and ("the player jumped here (jump count " .. tostring(c.landing.jc) .. ")") or "a step up",
    math.abs(rise), rise >= 0 and "up" or "down", d, vup, vh, tostring(hp), okv and "" or " (could not set his speed)"))
  return true
end

''')

# ---- drive_stuck -----------------------------------------------------------------------------------------------------
cut('-- Stuck and waiting (returns true while he stands).', '-- The native hook\'s inputs:', '''-- The one stuck rule (returns true while he stands). He heads for a crumb but has not come 0.3 m closer to it for
-- STUCK_TICKS, for any reason: "can't follow" (the notice says up / too steep / blocked from where the crumb is). While
-- he cannot follow he stands; the player coming to him ends it, otherwise drive_put_away respawns him beside the player.
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
    if h.prog == nil or h.prog.c ~= c or dc < h.prog.d - 0.3 then
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

''')

# ---- drive_steer -----------------------------------------------------------------------------------------------------
cut('-- The native hook\'s inputs:', '-- one tick of the drive for one companion', '''-- The native hook's inputs: the target (the crumb, or the player) and the player's spot. On the trail (a crumb as the
-- target) the native edge stop is off: where the player walked there was ground (planks, trap doors and overhangs
-- fooled its ray). Off the trail (straight to a swimming player, or no trail yet) it is on; on the way to the swimming
-- player it lets him drop up to 7.5 m (into the water). While he moves his body faces the target.
local function drive_steer(s)
  local world, id, h, a, t = s.world, s.id, s.h, s.a, s.t
  local px, py, pz, nx, nz = s.px, s.py, s.pz, s.nx, s.nz
  local c, how, dp = s.c, s.how, s.dp
  a.homeZonePosition.x, a.homeZonePosition.y, a.homeZonePosition.z = px, py, pz
  local tx, ty, tz = px, py, pz
  if c then tx, ty, tz = c.x, c.y, c.z end
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

''')

# ---- drive_step order ------------------------------------------------------------------------------------------------
rep('''  drive_pick_target(s)
  if drive_stuck(s) then return end
  drive_steer(s)''','''  drive_pick_target(s)
  if drive_copy(s) then return end
  if drive_stuck(s) then return end
  drive_steer(s)''')
rep('''-- waits) and the rest is skipped.''','''-- cannot follow) and the rest is skipped.''')
open(p, 'w', encoding='utf-8').write(s)
print("ok")
