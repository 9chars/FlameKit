-- npc_probe.lua: FlameKit's companions, on the owner's local test server only (never published; the repository keeps
-- the live copy in local_server/). No game AI anywhere: the companion's own AI and route planner are always off.
--   - the roster: FlameKit's own list of companions in the world's data (survives restarts), a main companion per
--     player, controllers and admins;
--   - following = the drive (FlameKit's breadcrumb trail of the player; the C++ server probe writes his movement input),
--     with swimming and diving, jump follow, drops, stuck notices, and put away / back beside the player (glider, fast
--     travel, can't follow);
--   - staying: no target, he stands still;
--   - E opens the wheel (Follow me / Stay here / Put away) in the player's game; "Call my companion" (P, Experimental
--     panel) respawns his main companion beside him;
--   - the minimap's companion dots, the full recorder (fullrec), and console tools for tests.
-- Console (or emf\commands.txt on the server): flamekit.npc roster ... | drive <npc> <player> | drive <npc> stop |
--   fullrec <entity> [s] | look <entity> | near <x> <y> <z> [r] | remove <entity> | and the test commands in F.setup
-- Logs "npc probe: ..." in emf\emf_core.log.

local F = { id = "npc_probe", title = "NPC Probe" }
local function log(s) emf.log("npc probe: " .. s) end
local function say(world, player, text)
  pcall(function() require("features.chat").notice_to(world, player, text, "#8cd2ff", 5) end)
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
-- Jump follow (drive_jump_follow): he launches from within DJ_AT of a takeoff crumb toward a landing DJ_RISE or more
-- higher, aiming DJ_MARGIN over it; a flight lasts at most DJ_TICKS. When he makes no progress for DJ_WAIT toward a
-- crumb that is DJ_RISE or more up and at most DJ_REACH away, he jumps up to it too. The launch speed is written for
-- up to DJ_LIFT ticks until the game counts him in the air; after a landing up top he stands still DJ_SETTLE ticks.
local DJ_AT, DJ_RISE, DJ_MARGIN, DJ_TICKS, DJ_WAIT, DJ_REACH = 1.5, 1.0, 0.7, 150, 60, 6
local DJ_SETTLE = 45
local DJ_LIFT = 40
local STUCK_MOVED = 1.5  -- the player must have moved this far since he gave up before "back near him" counts
-- Put away and back (drive_put_away, F.tick): the glider is the player's locomotion state GLIDE_STATE; still gliding
-- after GLIDE_WAIT ticks or GLIDE_FAR metres away, he is put away. The player moving more than FAR_JUMP in one tick
-- (a fast travel) puts him away too, and so does TP_AFTER ticks of not being able to follow. He comes back beside the
-- player once the player has stood on the ground LAND_TICKS (and his game has loaded).
local GLIDE_STATE, GLIDE_WAIT, GLIDE_FAR, LAND_TICKS, TP_AFTER, FAR_JUMP = 4, 240, 30, 60, 120, 50
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
-- stop and a step jump of its own; the game's locomotion moves and animates him. combatData.targetOfMyTarget = true
-- turns the native edge stop and step jump off; combatData.isTargetInsideLeash = true lets him drop down (see
-- drive_steer). No route search and no game follow orders.
local drives = {}  -- entity -> his record h: { player, trail = {}, ... }
-- a hold (console "hold", for tests): he stays where he stands and turns toward a target until the time is up
local holds = {}  -- entity -> { target, untill (tick) }
local DRIVE_STOP, DRIVE_STEP = 2, 0.25  -- he stops within 2 m of the player (the C++ kFollowStop matches); a crumb every 0.25 m
local CRUMB_REACH = 0.3  -- a crumb within this is reached; he aims at the first one further away
local FLOOR_LINK, FLOOR_REACH = 0.7, 3.6  -- the floor proof, see drive_steer
local FLOOR_FIRST = 1.5  -- (owner 17:46 "sure") the first link, from where he stands to the nearest crumb, may be this long
-- Drops and flights: no crumbs while the player is off the ground. A crumb more than DROP_HEIGHT below the one before
-- (just below his own fall damage: from 8 m, lethal at 16 m), or the first one after more than DROP_AIR_TICKS in the
-- air (a glide, not a jump), starts a new piece of trail (brk): he walks to the last crumb before it and waits there,
-- and goes on when the player is back within DROP_RESUME on his level.
local DROP_HEIGHT, DROP_RESUME = 7.5, 6
local DROP_AIR_TICKS = 120
local DROP_AT = 1.5  -- (owner 17:59 "yes") he is at the last safe crumb within this (the native edge ray looks 1.5 m ahead and holds him back from the lip)
-- the stuck notice says what holds him ("stuck" itself is only for a real clipping problem)
local STUCK_TEXT = {
  down = "Companion is afraid to follow (too steep)!",
  drop = "Companion is afraid to follow (drop too high)!",
  up = "Companion can't get up there!",
  blocked = "Companion can't follow you!",
}
local STUCK_TICKS = 180  -- 3 s without 0.3 m of progress toward his crumb: he gives up
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
-- waits) and the rest is skipped. The parts share only s and his record h (kept between ticks).

-- his body upright and turned toward yaw (radians, 0 = +z)
local function face(world, id, yaw)
  local o = world:get("CurrentTransform", id).transform.orientation
  o.x, o.y, o.z, o.w = 0, math.sin(yaw / 2), 0, math.cos(yaw / 2)
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

-- the native edge stop and step jump off for this tick
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

-- the tick's facts: where the player and the hound are, his AI kept off, and the water both read (currentWaterState
-- is the depth below the surface); nil when either body is gone
local function drive_read(world, id, h)
  local px, py, pz = world:position(h.player)
  local nx, ny, nz = world:position(id)
  if not (px and nx) then drives[id] = nil log("drive " .. tostring(id) .. ": gone, stopped") return nil end
  local t = world:tick()
  local a = world:get("DynamicEnemy01BehaviorState", id)
  if a.enabled ~= false then a.enabled = false fullrec_event(world, id, "drive: his AI switched off") end
  local okw, pw = pcall(function() return tonumber(world:get("DynamicLocomotion", h.player).currentWaterState) end)
  -- the player swims (pwet) when his depth is over 0.5; the hound swims (swim) on his OWN depth
  local pwater = (okw and tonumber(pw)) or 0
  local pwet = pwater > 0.5
  local okh, hw = pcall(function() return tonumber(world:get("DynamicLocomotion", id).currentWaterState) end)
  hw = okh and hw or 0
  local swim = hw > SWIM_ENTER
  return { world = world, id = id, h = h, a = a, t = t, px = px, py = py, pz = pz, nx = nx, ny = ny, nz = nz,
           pwater = pwater, pwet = pwet, hw = hw, swim = swim }
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
-- where he swims; the yaw is kept in h.swim_yaw because reading it back from a tilted body goes wrong).
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
      -- in the water he swims to the player: any stuck or drop wait is over
      h.stuck, h.waiting, h.prog = nil, nil, nil
      status(world, h.player, "companion_stuck", nil)
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
    -- HOP_EVERY). None for STUCK_TICKS: the "can't follow" notice, cleared when he moves again.
    local along = 0
    if h.wprog and dist > 0.05 then along = ((nx - h.wprog.x) * dx + (nz - h.wprog.z) * dz) / dist end
    if not h.wprog or along > 0.3 or dist <= stop then
      h.wprog = { x = nx, z = nz, t = t }
      if h.wstuck then
        h.wstuck = nil
        status(world, h.player, "companion_stuck", nil)
        log("stuck (water): " .. tostring(id) .. " moves again")
      end
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
    if dist > stop and still > STUCK_TICKS and not h.wstuck then
      h.wstuck = true
      log(string.format("stuck (water): %s makes no progress (player %.1f m, %.1f m higher)", tostring(id), dist, py - ny))
      report_blockers(s, "stuck (water)", dx, dz)
      status(world, h.player, "companion_stuck", "Companion can't follow you!", "#ff9050")
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
    if h.wstuck then h.wstuck = nil status(world, h.player, "companion_stuck", nil) end
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
-- a glide still going after GLIDE_WAIT or GLIDE_FAR away, a fast travel (FAR_JUMP in one tick), or TP_AFTER of not
-- being able to follow (stuck, waiting at a drop, or stuck in or on the way to the water).
local function drive_put_away(s)
  local h, t = s.h, s.t
  local px, pz, nx, nz = s.px, s.pz, s.nx, s.nz
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
  if h.stuck or h.waiting or h.sstuck or h.wstuck then
    h.cant_since = h.cant_since or t
    if t - h.cant_since > TP_AFTER then
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

-- Jump follow (returns true while a launch flies, he settles, or a new launch starts). Where the player jumped up
-- (double jump: jump count 2+ or a second push mid-air; or any jump when the hound has made no progress there for
-- DJ_WAIT) to a landing DJ_RISE or more higher, the hound launches from that takeoff crumb toward the landing. Also,
-- with no progress for DJ_WAIT toward a crumb DJ_RISE or more up and within DJ_REACH, he jumps up to it. The native
-- edge stop and step jump are off for the flight. Logs "double jump".
local function drive_jump_follow(s)
  local world, id, h, a, t = s.world, s.id, s.h, s.a, s.t
  local nx, ny, nz = s.nx, s.ny, s.nz
  local pwet, trail = s.pwet, s.trail
  if h.djump then
    local okl, lst = pcall(function() return tonumber(world:get("DynamicLocomotion", id).state) end)
    if okl and lst == 2 and not h.djump.air then
      h.djump.air = true
      log(string.format("double jump %s: in the air after %d tick(s)", tostring(id), t - h.djump.t0))
    end
    -- until the game counts him in the air (up to DJ_LIFT ticks) the launch speed is written again
    if not h.djump.air and t <= h.djump.t0 + DJ_LIFT then
      pcall(function()
        local v = world:get("Velocity", id).velocity
        v.x, v.y, v.z = h.djump.vx, h.djump.vy, h.djump.vz
      end)
    end
    -- in the air the speed across is written every tick toward the landing spot (up/down left to gravity)
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
    -- over the landing spot (within 0.6 m): no more speed across, he drops onto it
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
      log(string.format("double jump %s: down at %.1f %.1f %.1f, %.1f m from the player's landing (%.1f m %s it), health %s (was %s)",
        tostring(id), nx, ny, nz, math.sqrt((nx - h.djump.x1) ^ 2 + (nz - h.djump.z1) ^ 2), math.abs(ny - h.djump.y1),
        ny >= h.djump.y1 - 0.5 and "level with" or "below", tostring(hp), tostring(h.djump.hp)))
      if h.djump.air and ny >= h.djump.y1 - 0.5 then h.djsettle = t + DJ_SETTLE end  -- landed up top: he settles
      h.djump = nil
    else
      edge_off(a)
      return true
    end
  end
  -- the settle: he stands still, step jump and edge stop off, so he neither hops nor slides off
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
  if not pwet then
    for i = 1, math.min(#trail, 8) do
      local cc = trail[i]
      local sg = cc.takeoff
      -- the player's jumps up, at the takeoff crumbs among the next 8
      local blocked_here = h.prog and t - h.prog.t > DJ_WAIT
      if sg and not sg.used and not sg.water and sg.x1 and sg.rise >= DJ_RISE and (sg.jc >= 2 or sg.double or blocked_here) then
        if (cc.x - nx) ^ 2 + (cc.z - nz) ^ 2 < DJ_AT ^ 2 and math.abs(ny - cc.y) < 1.0 then
          local ddx, ddz = sg.x1 - nx, sg.z1 - nz
          local d = math.sqrt(ddx * ddx + ddz * ddz)
          local rise = sg.y1 - ny
          local vup, vh = launch_speeds(d, rise)
          local hp = health(world, id)
          local okv, vx, vz = launch(world, id, ddx, ddz, d, vup, vh)
          edge_off(a)
          sg.used = true
          for _ = 1, i do table.remove(trail, 1) end
          h.stuck, h.waiting, h.prog = nil, nil, nil
          status(world, h.player, "companion_stuck", nil)
          h.djump = { t0 = t, untill = t + DJ_TICKS, x1 = sg.x1, y1 = sg.y1, z1 = sg.z1, hp = hp, vx = vx, vz = vz, vy = vup }
          log(string.format("double jump %s: follows the player's %s: %.1f m up, %.1f m out, %.1f m/s up, %.1f m/s out (health %s)%s",
            tostring(id), (sg.jc >= 2 or sg.double) and "double jump" or "jump (his own step jump did not get him up)",
            rise, d, vup, vh, tostring(hp), okv and "" or " (could not set his speed)"))
          return true
        end
        break
      end
    end
  end
  -- no progress toward a crumb up a ledge (the player got up without a jump the log saw): he jumps up to it
  if not pwet and not h.djump and h.prog and t - h.prog.t > DJ_WAIT and h.prog.c then
    local cc = h.prog.c
    local ddx, ddz = cc.x - nx, cc.z - nz
    local d = math.sqrt(ddx * ddx + ddz * ddz)
    local rise = cc.y - ny
    if rise >= DJ_RISE and rise < 6 and d <= DJ_REACH and not cc.climbed then
      cc.climbed = true
      local vup, vh = launch_speeds(d, rise)
      local _, vx, vz = launch(world, id, ddx, ddz, d, vup, vh)
      edge_off(a)
      local hp = health(world, id)
      h.stuck, h.waiting, h.prog = nil, nil, nil
      status(world, h.player, "companion_stuck", nil)
      h.djump = { t0 = t, untill = t + DJ_TICKS, x1 = cc.x, y1 = cc.y, z1 = cc.z, hp = hp, vx = vx, vz = vz, vy = vup }
      log(string.format("double jump %s: jumps up to his next crumb (%.1f m up, %.1f m out; no progress for %d ticks): %.1f m/s up, %.1f m/s out",
        tostring(id), rise, d, DJ_WAIT, vup, vh))
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

-- His target (s.c, the crumb he heads for; nil = the player). Crumbs behind him and the ones he reached are dropped (the
-- last one before a break stays: he waits there, h.waiting). Within DRIVE_STOP of the player there is no target.
-- At the water: when the player swims and the hound stands at the water's level (at most WATER_NEAR above the surface
-- the player's depth gives, not more than 1 m below it), or after a leap, and the trail ahead is short (its last crumb
-- within 3 m, or none), he heads straight for the swimming player (h.to_swimmer) and stays on that while the player is
-- in the water; a stuck there is over. On that way his progress along the line to the player counts; none for
-- STUCK_TICKS: the "can't follow" notice.
local function drive_pick_target(s)
  local world, id, h, t = s.world, s.id, s.h, s.t
  local px, py, pz, nx, ny, nz = s.px, s.py, s.pz, s.nx, s.ny, s.nz
  local pwater, pwet = s.pwater, s.pwet
  local trail = s.trail
  local dp = math.sqrt((px - nx) ^ 2 + (pz - nz) ^ 2)
  local how = "stop"
  local c
  if dp > DRIVE_STOP then
    local near, nd = 1, math.huge
    for i, cc in ipairs(trail) do
      local dd = (cc.x - nx) ^ 2 + (cc.z - nz) ^ 2
      if dd < nd then near, nd = i, dd end
    end
    for _ = 1, near - 1 do table.remove(trail, 1) end
    while #trail > 1 and (trail[1].x - nx) ^ 2 + (trail[1].z - nz) ^ 2 < CRUMB_REACH ^ 2 and not trail[2].brk do
      table.remove(trail, 1)
    end
    local pick = #trail
    for i = 1, #trail do
      if (trail[i].x - nx) ^ 2 + (trail[i].z - nz) ^ 2 > CRUMB_REACH ^ 2 then pick = i break end
    end
    h.waiting = nil
    for i = 2, #trail do
      if trail[i].brk then
        if pick >= i then pick = i - 1 end
        h.waiting = (pick == i - 1)
        break
      end
    end
    c = trail[pick]
    how = string.format("crumb %d of %d", pick, #trail)
  else
    h.waiting = nil
  end
  local was_to_swimmer = h.to_swimmer
  h.to_swimmer = nil
  local surface = pwet and (py + pwater) or nil
  local near_water = surface and ny - surface < WATER_NEAR and ny - surface > -1
  local lastc = trail[#trail]
  if (near_water or h.leap) and dp > DRIVE_STOP and (was_to_swimmer or not lastc or (lastc.x - nx) ^ 2 + (lastc.z - nz) ^ 2 < 3 ^ 2) then
    c, h.waiting, h.to_swimmer = nil, nil, true
    how = "to the swimming player"
    if h.stuck then
      h.stuck, h.prog = nil, nil
      status(world, h.player, "companion_stuck", nil)
      log(string.format("stuck: %s goes on: the player swims and the water is right here (%.1f m above its surface)", tostring(id), ny - surface))
    end
  end
  if h.to_swimmer ~= h.to_swimmer_said then
    h.to_swimmer_said = h.to_swimmer
    h.sprog = nil
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
      if h.sstuck then h.sstuck = nil status(world, h.player, "companion_stuck", nil) log("stuck (to the water): " .. tostring(id) .. " moves again") end
    elseif t - h.sprog.t > STUCK_TICKS and not h.sstuck then
      h.sstuck = true
      log(string.format("stuck (to the water): %s makes no progress toward the swimming player (%.1f m)", tostring(id), td))
      report_blockers(s, "stuck (to the water)", tdx, tdz)
      status(world, h.player, "companion_stuck", "Companion can't follow you!", "#ff9050")
    end
  elseif h.sstuck then
    h.sstuck, h.sprog = nil, nil
    status(world, h.player, "companion_stuck", nil)
  end
  s.c, s.how, s.dp = c, how, dp
end

-- Stuck and waiting (returns true while he stands). Stuck: he heads for a crumb but has not come 0.3 m closer to it for
-- STUCK_TICKS; he stops, the notice says why (STUCK_TEXT: down, up, a drop the player took within 3 m ahead, or
-- blocked), with how far the player is, once a second. He goes on when the player has moved STUCK_MOVED since he gave
-- up and is back within DROP_RESUME on his level (a fresh trail from where HE stands), or with Call.
-- Waiting at a drop: he stands at the last safe crumb with its own notice; the same way on.
local function drive_stuck(s)
  local world, id, h, a, t = s.world, s.id, s.h, s.a, s.t
  local px, py, pz, nx, ny, nz = s.px, s.py, s.pz, s.nx, s.ny, s.nz
  local trail, c, dp = s.trail, s.c, s.dp
  local alive = true
  pcall(function() alive = world:get("Health", id).dataStorage[1] > 0 end)
  if c and alive and not h.waiting and not h.stuck then
    local dc = math.sqrt((c.x - nx) ^ 2 + (c.z - nz) ^ 2)
    if h.prog == nil or h.prog.c ~= c or dc < h.prog.d - 0.3 then
      h.prog = { c = c, d = dc, t = t }
    elseif t - h.prog.t > STUCK_TICKS then
      h.stuck = true
      h.stuck_px, h.stuck_pz = px, pz  -- where the player was when he gave up
      h.prog = nil
      local dy = c.y - ny
      h.stuck_why = dy < -0.8 and "down" or (dy > 0.6 and "up" or "blocked")
      for i = 1, #trail do
        local cc = trail[i]
        if (cc.x - nx) ^ 2 + (cc.z - nz) ^ 2 > 3 ^ 2 then break end
        if cc.brk then h.stuck_why = "drop" break end
      end
      log(string.format("stuck: %s gave up at %.1f %.1f %.1f (crumb %.1f %.1f %.1f, %.1f m away, player %.1f m)", tostring(id),
        nx, ny, nz, c.x, c.y, c.z, dc, dp))
      report_blockers(s, "stuck", c.x - nx, c.z - nz)
      fullrec_event(world, id, "drive: stuck, gave up")
      status(world, h.player, "companion_stuck", STUCK_TEXT[h.stuck_why] or "Companion is stuck!", "#ff9050")
    end
  elseif not c then
    h.prog = nil
  end
  if h.stuck then
    local moved = not h.stuck_px or (px - h.stuck_px) ^ 2 + (pz - h.stuck_pz) ^ 2 > STUCK_MOVED ^ 2
    if moved and (px - nx) ^ 2 + (pz - nz) ^ 2 < DROP_RESUME ^ 2 and math.abs(py - ny) < 2 then
      h.trail, h.stuck, h.prog = { { x = nx, y = ny, z = nz } }, nil, nil
      status(world, h.player, "companion_stuck", nil)
      log("stuck: " .. tostring(id) .. " goes on: the player is back near him")
      fullrec_event(world, id, "drive: player back near him, stuck over, fresh trail")
    else
      hold_at(a, nx, ny, nz)
      if t % 30 == 0 then fullrec_event(world, id, string.format("drive: stuck, waiting, player %.1f m", dp)) end
      if t % 60 == 0 then
        local dy = py - ny
        status(world, h.player, "companion_stuck", string.format("%s %.1f m away, %.1f m %s (come within %d m, %d m height)",
          STUCK_TEXT[h.stuck_why] or "Companion is stuck!", dp, math.abs(dy), dy >= 0 and "higher" or "lower", DROP_RESUME, 2), "#ff9050")
      end
      return true
    end
  end
  if h.waiting then
    -- (17:55 logging) the drop wait's state, whenever it changes: walking to the last safe crumb, or waiting there
    local wstate
    if (px - nx) ^ 2 + (pz - nz) ^ 2 < DROP_RESUME ^ 2 and math.abs(py - ny) < 2 then
      wstate = "over: the player is back near him"
    elseif c and (c.x - nx) ^ 2 + (c.z - nz) ^ 2 > DROP_AT ^ 2 then
      wstate = "walks to the last safe crumb first"
    else
      wstate = "waits at the last safe crumb"
    end
    if wstate ~= h.wait_state then
      h.wait_state = wstate
      log(string.format("drop wait %s: %s (that crumb %s m away, player %.1f m, %.1f m %s)", tostring(id), wstate,
        c and string.format("%.2f", math.sqrt((c.x - nx) ^ 2 + (c.z - nz) ^ 2)) or "-", dp, math.abs(py - ny),
        py >= ny and "higher" or "lower"))
    end
    if (px - nx) ^ 2 + (pz - nz) ^ 2 < DROP_RESUME ^ 2 and math.abs(py - ny) < 2 then
      h.trail, h.waiting = { { x = nx, y = ny, z = nz } }, nil
      h.wait_state = nil
      if h.wait_told then h.wait_told = nil status(world, h.player, "companion_stuck", nil) end
      fullrec_event(world, id, "drive: player back near him, waiting over, fresh trail")
    elseif c and (c.x - nx) ^ 2 + (c.z - nz) ^ 2 > DROP_AT ^ 2 then
      h.waiting = nil
    else
      a.homeZonePosition.x, a.homeZonePosition.y, a.homeZonePosition.z = nx, ny, nz
      if c then a.movementTarget.x, a.movementTarget.y, a.movementTarget.z = c.x, c.y, c.z end
      a.movementTargetIsValid = true
      if t % 30 == 0 then fullrec_event(world, id, string.format("drive: waiting at a drop, player %.1f m", dp)) end
      if t % 60 == 0 then
        local dy = py - ny
        status(world, h.player, "companion_stuck", string.format("Companion is afraid to follow (drop too high)! %.1f m away, %.1f m %s (come within %d m, %d m height)",
          dp, math.abs(dy), dy >= 0 and "higher" or "lower", DROP_RESUME, 2), "#ff9050")
        h.wait_told = true
      end
      return true
    end
  elseif h.wait_state then
    h.wait_state = nil
  end
  return false
end

-- The native hook's inputs: the target (the crumb, or the player) and the player's spot. The edge stop's permission
-- (isTargetInsideLeash): it lets him drop more than 2.5 m only where the player went down himself (a crumb within 12 m
-- ahead, before any break, 0.8 to 7.5 m below him) or the way to the swimming player. The floor proof: an unbroken level
-- trail ahead (the nearest crumb within FLOOR_FIRST of him, each next one within FLOOR_LINK of the one before, none
-- more than 0.8 m above or below him) out to FLOOR_REACH, or all the way to where the player stands on the ground,
-- proves a floor the edge ray cannot see (a closed trap door, a boardwalk): then the native edge stop is off. A jump
-- leaves a gap, so a hole the player jumped over still stops him. While he moves his body faces the target.
local function drive_steer(s)
  local world, id, h, a, t = s.world, s.id, s.h, s.a, s.t
  local px, py, pz, nx, ny, nz = s.px, s.py, s.pz, s.nx, s.ny, s.nz
  local trail, c, how, dp = s.trail, s.c, s.how, s.dp
  a.homeZonePosition.x, a.homeZonePosition.y, a.homeZonePosition.z = px, py, pz
  local tx, ty, tz = px, py, pz
  if c then tx, ty, tz = c.x, c.y, c.z end
  local okp, perr = pcall(function()
    local ok = h.to_swimmer or false
    for i = 1, #trail do
      local cc = trail[i]
      if (cc.x - nx) ^ 2 + (cc.z - nz) ^ 2 > 12 ^ 2 then break end
      if cc.brk then break end
      if cc.y < ny - 0.8 and cc.y > ny - 7.5 then ok = true break end
    end
    local proof = false
    if not ok then
      local lx, lz, far, whole, why = nx, nz, 0, #trail > 0, nil
      for i = 1, #trail do
        local cc = trail[i]
        local link = i == 1 and FLOOR_FIRST or FLOOR_LINK
        if cc.brk or (cc.x - lx) ^ 2 + (cc.z - lz) ^ 2 > link ^ 2 or math.abs(cc.y - ny) > 0.8 then
          -- why the unbroken level trail ends here (log)
          why = string.format("; ends at crumb %d of %d: %s", i, #trail, cc.brk and "a break" or
            ((cc.x - lx) ^ 2 + (cc.z - lz) ^ 2 > link ^ 2 and string.format("%.2f m from %s", math.sqrt((cc.x - lx) ^ 2 + (cc.z - lz) ^ 2), i == 1 and "him" or "the crumb before")
              or string.format("%.2f m %s him", math.abs(cc.y - ny), cc.y > ny and "above" or "below")))
          whole = false
          break
        end
        lx, lz = cc.x, cc.z
        far = math.sqrt((cc.x - nx) ^ 2 + (cc.z - nz) ^ 2)
        if far >= FLOOR_REACH then proof = true break end
      end
      -- the whole trail is one unbroken level piece and it ends where the player stands on the ground (within
      -- FLOOR_LINK of its last crumb, on his level): the floor goes all the way to the player
      local to_player = false
      if not proof and whole and not s.airborne and not s.pwet and (px - lx) ^ 2 + (pz - lz) ^ 2 <= FLOOR_LINK ^ 2
          and math.abs(py - ny) <= 0.8 then
        proof, to_player = true, true
      end
      if proof ~= (h.floorproof or false) then
        log(string.format("edge %s: %s (unbroken level trail %.1f m ahead%s%s) at %.1f %.1f %.1f", tostring(id),
          proof and "floor proven by the trail, native edge stop off" or "no floor proof", far,
          to_player and ", to the player" or "", proof and "" or (why or (#trail == 0 and "; no trail" or "; the trail ends there, the player is not on it")), nx, ny, nz))
      end
      ok = proof
    end
    h.floorproof = proof
    a.combatData.isTargetInsideLeash = ok
    -- (owner 2026-11-18 17:20 boardwalk, 17:29 "go ahead") a proven floor is one the edge ray cannot see (it goes
    -- through planks and trap doors and found no ground within 12 m under a boardwalk): the native edge stop (and its
    -- step jump) is off for this tick, not only the drop limit raised
    if proof then edge_off(a) end
  end)
  if not okp and not h.steer_err then
    h.steer_err = true
    log("drive " .. tostring(id) .. ": the edge permission failed: " .. tostring(perr))
  end
  a.movementTarget.x, a.movementTarget.y, a.movementTarget.z = tx, ty, tz
  a.movementTargetIsValid = true
  if dp > DRIVE_STOP then
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
  drive_waterlog(s)
  if drive_water(s) then return end
  drive_track_player(s)
  if drive_put_away(s) then return end
  drive_lay_crumb(s)
  drive_upkeep(s)
  if drive_jump_follow(s) then return end
  if drive_lure(s) then return end
  if drive_hold(s) then return end
  drive_pick_target(s)
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

local function roster_save()
  if not roster.loaded then return false end
  local out = { next_n = roster.next_n, main = roster.main, npcs = {} }
  for _, r in ipairs(roster.list) do
    out.npcs[#out.npcs + 1] = { name = r.name, guid = r.guid, x = r.x, y = r.y, z = r.z, mode = r.mode,
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
  pcall(emf.offer, world, id, { verb = "Talk" }, function(w, p, npc) on_talk(w, p, npc) end)
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
  local ok, id = pcall(emf.spawn, world, r.guid, x, y, z)
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
    for _, r in ipairs(saved.npcs or {}) do
      -- a record without a controller list: its owner is the only controller
      if not r.controllers then r.controllers = r.owner and { r.owner } or {} end
      r.names = r.names or {}
      roster.list[#roster.list + 1] = r
    end
  end
  roster.loaded = true
  log(string.format("roster: loaded, %d NPC(s)", #roster.list))
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
      log(string.format("roster: %s | %s | %s | leader %s | controllers [%s] | %s | spot %.1f %.1f %.1f", r.name,
        r.out and ("out as " .. tostring(ent_of[r.name])) or "put away", r.mode, tostring(r.owner), table.concat(who, "; "),
        r.guid, r.x or 0, r.y or 0, r.z or 0))
    end
    local mains = {}
    for a, n in pairs(roster.main) do mains[#mains + 1] = a .. " -> " .. n end
    log(string.format("roster: %d NPC(s); main companions %s; admins %s", #roster.list, table.concat(mains, ", "), table.concat(admins, ", ")))
    emf.reply("roster: listed in the log")
  elseif what == "away" or what == "delete" then  -- away <name>: body gone, kept on the list; delete: gone for good
    local r, i = find(args[3] or "")
    if not r then emf.reply("roster: no " .. tostring(args[3])) return end
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
-- E opens a wheel on the presser's own screen (FlameKit's game side, channel flamekit/npcwheel). The server checks who
-- may command the companion, again at the pick. There is no other way (a game without FlameKit gets a notice).
local WHEEL = "npcwheel"
local WHEEL_LABELS = { "Follow me", "Stay here", "Put away" }

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

on_talk = function(world, player, npc)
  log(string.format("E pressed on %s by player %s", tostring(npc), tostring(player)))
  local rr = name_of[npc] and find(name_of[npc])
  local account = world:account(player)
  if rr and not may_command(rr, account) then
    log(string.format("E: %s refused for %s (controllers %s)", rr.name, tostring(account), table.concat(rr.controllers or {}, ",")))
    refuse(world, player, rr)
    return
  end
  local okp, ver = pcall(emf.net.peer, world, player, WHEEL)
  if not (okp and (tonumber(ver) or 0) > 0) then
    say(world, player, "This companion needs FlameKit in your game.")
    return
  end
  local oks, sent = pcall(emf.net.send_to, world, player, WHEEL, emf.json.encode({ op = "wheel", npc = npc,
    title = rr and rr.name or "Companion", labels = WHEEL_LABELS }))
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
  local act = ({ ["Follow me"] = do_follow, ["Stay here"] = do_stay, ["Put away"] = do_away })[WHEEL_LABELS[tonumber(m.choice) or 0] or ""]
  if not act then return end
  local ok, err = pcall(act, world, player, npc, rr)
  if not ok then log("wheel: failed: " .. tostring(err)) say(world, player, "Cannot do that (see the server's log).") end
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
  pcall(emf.on_player_joined, function(world, p)
    log(string.format("join: player %s (account %s)", tostring(p.player), tostring(p.account)))
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
  end
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
          local okc, errc = pcall(on_call, world, { player = rt.player, account = rt.account })
          if not okc then log("away: call failed: " .. tostring(errc)) end
        end
      else
        rt.ground = nil
      end
    end
  end
end

return F
