-- npc_probe.lua (2026-11-17): FlameKit's companion NPCs, a TEST feature on the owner's local server only (never
-- published). Rebuilt at 17:00 (owner: "under no circumstances do I want any of the old code. no fall back code or
-- anything to do with any of the old AI follow me systems that didnt work"): only what works is left.
--   - the roster: FlameKit's own list of NPCs in the world's data (survives restarts), a main companion per player,
--     controllers and admins;
--   - following = the drive (his AI off, FlameKit's breadcrumb trail, the C++ hook writes his movement input);
--   - water: swims with the player (drive + height and tilt);
--   - staying = no game AI: his AI off, no target, he stands still (owner 17:06);
--   - E opens the wheel (Follow me / Stay here / Put away) in the player's game; "Call my companion" (Experimental
--     panel) respawns his main companion on him;
--   - the full recorder (fullrec) and read-only tools.
-- Console (or emf\commands.txt on the server): flamekit.npc roster ... | drive <npc> <player> | drive <npc> stop |
--   fullrec <entity> [s] | look <entity> | near <x> <y> <z> [r] | remove <entity>
-- Logs "npc probe: ..." in emf\emf_core.log.

local F = { id = "npc_probe", title = "NPC Probe" }
local function log(s) emf.log("npc probe: " .. s) end
local function say(world, player, text)
  pcall(function() require("features.chat").notice_to(world, player, text, "#8cd2ff", 5) end)
end

-- (owner 2026-11-18 07:30: stuck and death notices "stay on the screen until the condition is cleared") a notice in
-- the player's Notices window with no time limit, taken back with clear = true (client npc_wheel_probe.lua)
local function status(world, player, tag, text, colour)
  if not player then return end
  local msg = text and { op = "status", tag = tag, text = text, colour = colour } or { op = "status", tag = tag, clear = true }
  pcall(emf.net.send_to, world, player, "npcwheel", emf.json.encode(msg))
end

-- ===== The full recorder (owner 13:57/13:58: "logging all meta data ... and any other thing that needs to be logged") ==
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
  local f = io.open(emf.dir .. "\\fullrec_" .. tostring(id) .. "_" .. (os.date and os.date("%H%M%S") or tostring(world:tick())) .. ".txt", "w")  -- (14:10) one file per recording, kept
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


-- (owner 16:33: "delete all of that code and start over using the new methods, keep the angle tilt and how high above
-- water he is") the two tuned numbers stay (owner 13:28-13:31); the old float that PLACED his body is gone
local FLOAT_LIFT = 0.45  -- metres above the player's height while swimming
local FLOAT_PITCH = 28   -- degrees, nose up
local SWIM_OUT_STOP = 0.8  -- (owner 11:12) in the water with the player on land he only stops this close
local DJ_AT, DJ_RISE, DJ_MARGIN, DJ_TICKS, DJ_WAIT, DJ_REACH = 1.5, 1.0, 0.7, 150, 60, 6
local DJ_SETTLE = 45  -- (12:56) was 20  -- (owner 12:52) ticks he stands still after a jump-follow landing up top
local DJ_LIFT = 40  -- (12:47) ticks the launch waits for the game to count him in the air
local STUCK_MOVED = 1.5  -- (owner 12:44) the player must have moved this far since he gave up before "back near him" counts  -- (owner 12:38/12:40) jump follow, see drive_step
-- (owner 2026-11-18 13:40/13:46, glider design) put away while the player glides away, back beside him when he lands;
-- the same for a fast travel jump and when he cannot follow (see drive_step and F.tick)
-- (owner 14:03 "the respawn works so well, I wouldn't even wait 5 seconds... wait like 2 seconds maybe. the only case
-- where I would want to change this is if we were testing it more") TP_AFTER 120 ticks (was 300); raise it again for
-- tests about why he could not get somewhere
local GLIDE_STATE, GLIDE_WAIT, GLIDE_FAR, LAND_TICKS, TP_AFTER, FAR_JUMP = 4, 240, 30, 60, 120, 50
local WATER_NEAR = 2  -- (owner 10:55) metres above the swimming player's water surface that still count as "at the water"
local DIVE_PLAYER = 1.8  -- (owner 12:07) the player's depth from which the hound dives with him (at the surface the player reads about 1.3)
local SWIM_ENTER, SWIM_DEPTH = 0.5, 0.9  -- (owner 10:37) swims while his own depth is over 0.5 m, held at about 0.9 m
local SWIM_MAX, SWIM_GAIN = 6, 1.2  -- (owner 10:30) swimming speed he is given: 1 m/s past DRIVE_STOP, +1.2 m/s per metre, at most 6 (his run speed 5.8)
local HOP_TICKS, HOP_HOLD, HOP_EVERY, HOP_MARGIN, HOP_FORWARD = 90, 40, 120, 0.7, 3  -- (owner 10:46) climb-out hop, see drive_step
-- ===== Following: the drive (owner 15:42/15:58 option 2, "it works well" 16:05) ======================================
-- His AI is switched off (DynamicEnemy01BehaviorState.enabled = false; his route planner too). FlameKit keeps the
-- player's breadcrumb trail (a crumb every 0.5 m he walked) and writes the next crumb ahead of the hound into his AI
-- data's movementTarget and the player's spot into homeZonePosition (movementTargetIsValid = true). The C++ server
-- probe (fk_server_probe, drive_post) hooks the game's steering step and right after it writes his movement input
-- (direction, look, Walk/Run/Sprint by distance; nothing within 3 m) inside the same game step; the game's locomotion
-- walks, runs and animates him for everyone. Water: below. No route search, no teleports, no game follow orders.
local drives = {}  -- entity -> { player, trail = {}, water }
-- (owner 19:00: "the dog keeps trying to come back to me. maybe stop that while the dog is attacking" / "the dog is not
-- facing the monster") entity -> { target, untill (tick) }: while it lasts the drive holds him where he stands (the
-- native hook sees the player at his own spot: no movement) and turns his body toward the target every tick.
local holds = {}
local DRIVE_STOP, DRIVE_STEP = 2, 0.25  -- (owner 2026-11-18 11:12 "the follow distance needs to be 2 m", was 3; the C++ kFollowStop matches)  -- (owner 15:54: "your bread crumbs are too spread out": 2 m cut corners)
-- (owner 2026-11-18 08:10: "lets try .25": stuck on trees in tight spaces) a crumb every 0.25 m (was 0.5); a crumb
-- within CRUMB_REACH is reached, and he aims at the first one further away than that (was 0.5)
local CRUMB_REACH = 0.3
local FLOOR_LINK, FLOOR_REACH = 0.7, 3.6  -- (owner 2026-11-18 10:06) floor proof by an unbroken level trail, see drive_step
-- (owner 20:08, after the glider fall 19:52) drops: no crumbs while the player is off the ground (his
-- MovementCollider has no ground contact: jumping, falling, gliding). A crumb more than DROP_HEIGHT below the one
-- before, or more than DROP_GAP away from it (a flight), starts a new piece of trail ("brk"): the
-- hound walks to the last crumb before it and waits there. He goes on when the player is back near him (fresh trail).
-- (owner 20:16 "as long as the drop won't kill him he can follow", 20:18 yes) the hound's own FallDamage (game data,
-- claude_scratch/tpl/falldmg.py): damage from 8 m, lethal at 16 m. A drop counts from 7.5 m, below any damage. A plain
-- hop (back on the ground within DROP_GAP of the takeoff, not 7.5 m lower) is ignored; a longer flight (gliding over
-- a valley) is a gap he cannot walk.
-- (20:37 log) a running jump covers more than 6 m between its takeoff and landing crumbs (about 1 s in the air at run
-- speed): a gap rule in metres stopped him after every jump. A flight is told by its time instead: in the air longer
-- than DROP_AIR_TICKS (2 s; a jump about 1 s, the glider flight in the log 3 s).
local DROP_HEIGHT, DROP_GAP, DROP_RESUME = 7.5, 6, 6
local DROP_AIR_TICKS = 120
local STUCK_TEXT = {  -- (owner 08:18) the status says what holds him
  down = "Companion is afraid to follow (too steep)!",  -- (owner 08:20, his words)
  drop = "Companion is afraid to follow (drop too high)!",  -- (owner 08:41)
  up = "Companion can't get up there!",
  blocked = "Companion can't follow you!",  -- (owner 11:50: "stuck" only for clipping; an obstacle he cannot get over or round)
}
local STUCK_TICKS = 180  -- (07:24) 3 s without 0.3 m of progress toward his crumb: stuck
local CRUMB_LOG = true  -- (20:34 test) every crumb of every companion into the server log
-- (20:36 log of the owner's jumps) "ground contact" stays true for the first and last part of a jump (ground distance
-- 0.18 to 1.99 m, DynamicLocomotion.state 2); standing, walking and running: state 0 and a distance under 0.1 m. So on
-- the ground = contact, distance under 0.1 m and locomotion state 0.
local function player_airborne(world, player)
  local ok, air = pcall(function()
    local r = world:get("MovementCollider", player).results
    local st = tonumber(world:get("DynamicLocomotion", player).state)
    local gd = tonumber(r.m_value.groundDistance) or 1e9
    return not (r.m_isSet and r.m_value.hasGroundCollision and gd < 0.1 and st == 0)
  end)
  return ok and air
end
-- (owner 2026-11-18 12:00/12:02 "definitely do #2.. he'll get blocked by NPC's too ... the message should reflect
-- that, such as 'Blocked by animals!' or 'Blocked by NPC!' Some NPC's won't move ever...") who stands in his way when
-- he gives up: every body within BLOCK_R of him (not himself, not his player), its kind from its components (Animal;
-- ActiveNpcState = a villager NPC; a player; DynamicEnemy01BehaviorState = a monster or a companion), how far, and
-- whether it is in front of him (toward fx, fz). Also his collider's own "touching a character" flags. One scan over
-- the world's entities, only when he gives up. Returns the kind of the nearest one in front ("animal", "npc",
-- "player", "monster") or nil, and a line for the log.
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

local function drive_step(world, id, h)
  local px, py, pz = world:position(h.player)
  local nx, ny, nz = world:position(id)
  if not (px and nx) then drives[id] = nil log("drive " .. tostring(id) .. ": gone, stopped") return end
  local t = world:tick()
  local a = world:get("DynamicEnemy01BehaviorState", id)
  if a.enabled ~= false then a.enabled = false fullrec_event(world, id, "drive: his AI switched off") end
  -- (owner 2026-11-18 09:42/09:47) water log, measuring only (nothing about his movement changes): once a second while
  -- the player or the hound reads any water, and 5 s after: both water readings (raw), the hound's submerge depth,
  -- heights, ground and locomotion state. To learn whether the hound's own water value is live and what it means
  -- before water mode is switched to it (owner 09:42: "his state should change based on when he's in the water").
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
      -- (10:07, water test 1: he drifted away in a straight line) his speed and its direction, the move direction the
      -- drive gave him, the way he faces, and the way to the player, all as compass angles (0 = +z, 90 = +x)
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
      -- (owner 12:11, Invincible Mode question) the PLAYER's air too: the Oxygen numbers and the drowning state
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
  -- Water (owner 16:11/16:33): while the PLAYER swims (his water state > 0.5) the native drive keeps moving the hound
  -- (target = the player, his legs run as he goes), and FlameKit only does what the game cannot for a non-swimmer:
  -- every tick his height = the player's + FLOAT_LIFT, and his body tilted nose up FLOAT_PITCH degrees, keeping the
  -- direction the game turned him. Out of the water: upright, a fresh trail, walking as on land.
  local okw, pw = pcall(function() return tonumber(world:get("DynamicLocomotion", h.player).currentWaterState) end)
  -- (22:38) tells the native edge stop that he swims (no ground check in water): a field his AI would use, unused
  -- with the AI off
  -- (owner 2026-11-18 09:42 "his state should change based on when he's in the water and not mine", 10:37 "yes change
  -- it") water mode follows the HOUND's own water value (his depth below the surface, water test 2: right while he
  -- swims), not the player's. Before (player's value), the player walked out and the hound, still over 8 m deep water,
  -- sank to the bottom and was stuck (10:35). pwet (the player swims) is still used for the trail and the target.
  local pwater = (okw and tonumber(pw)) or 0  -- (10:56) kept by its own name: "pw" is reused below for his path walker
  local pwet = pwater > 0.5
  local okh, hw = pcall(function() return tonumber(world:get("DynamicLocomotion", id).currentWaterState) end)
  hw = okh and hw or 0
  local swim = hw > SWIM_ENTER
  -- (owner 11:50 "he doesn't have to leap in, he just needs to follow") the player came down into the water from the
  -- air (h.leap, recorded below) and is in the water now: the native edge stop is off for the hound too, until he is in
  -- the water himself; he follows the trail to its end and then straight to the player (h.to_swimmer). No distances
  -- or speeds of its own. Over when the player leaves the water.
  if h.leap and not pwet then
    log("leap " .. tostring(id) .. ": the player left the water, edge stop on again")
    h.leap = nil
  end
  pcall(function() a.combatData.targetOfMyTarget = swim or (h.leap ~= nil) end)  -- the native edge stop: off while HE swims
  if swim then
    if not h.water then
      h.water = true
      h.to_swimmer = nil
      if h.leap then
        local hp = -1
        pcall(function() hp = world:get("Health", id).dataStorage[1] end)
        log(string.format("leap %s: followed the player into the water (health %s, was %s)", tostring(id), tostring(hp), tostring(h.leap.hp)))
        h.leap = nil
      end
      -- in the water he swims to the player again: a stuck or drop wait is over, and any stuck notice still on the
      -- screen goes (10:51: one from the old water rule stayed after the reload)
      h.stuck, h.waiting, h.prog = nil, nil, nil
      status(world, h.player, "companion_stuck", nil)
      fullrec_event(world, id, "drive: in the water himself (" .. tostring(hw) .. "): swimming")
      log(string.format("drive %s: in the water himself (depth %.2f), swimming", tostring(id), hw))
    end
    a.homeZonePosition.x, a.homeZonePosition.y, a.homeZonePosition.z = px, py, pz
    a.movementTarget.x, a.movementTarget.y, a.movementTarget.z = px, py, pz
    a.movementTargetIsValid = true
    local tr = world:get("CurrentTransform", id).transform
    local S = 2 ^ 32
    -- (10:37) held at the water surface where HE is (his own depth, kept near SWIM_DEPTH: the 0.9 m he had at the
    -- old, tuned height), not at the player's height (that lifted him onto land or into banks). A quarter of the
    -- difference each tick, smooth. Never pushed down while he stands on the bottom (wading in shallow water).
    local hopping = h.hop_until and t < h.hop_until
    -- (owner 12:07 "he should dive with me, because there are a lot of underwater areas") the player under the water
    -- (his depth over DIVE_PLAYER; at the surface he reads about 1.3): held at the player's height + FLOAT_LIFT (the
    -- old tuned look) instead of at the surface; back to the surface when the player comes up. Same quarter step, at
    -- most 0.08 m a tick, never pushed down while he touches the bottom (below).
    local diving = pwet and pwater > DIVE_PLAYER
    if diving ~= (h.diving or false) then
      h.diving = diving
      log(string.format("drive %s: %s (player depth %.2f)", tostring(id), diving and "dives with the player" or "back to the surface", pwater))
    end
    local want = diving and (py + FLOAT_LIFT - ny) or (hw - SWIM_DEPTH)
    local fix = math.max(-0.08, math.min(0.08, want * 0.25))  -- at most 0.08 m a tick (4.8 m/s)
    if hopping then fix = 0 end  -- (10:46) no surface hold during a climb-out hop
    if fix < 0 then
      local okg, grounded = pcall(function() return world:get("MovementCollider", id).results.m_value.hasGroundCollision end)
      if okg and grounded then fix = 0 end
    end
    tr.position.y = tr.position.y + math.floor(fix * S)
    -- (owner 2026-11-18 10:27/10:30, water test 2) held up here the game counts him as in the air (locomotion state 2),
    -- and in the air his speed stays frozen at what it was when he left the ground: the drive's direction never took
    -- ("vel 12.4 m/s at 346" with the input at 170). So FlameKit sets his swimming speed itself, every tick: toward the
    -- player, nothing within DRIVE_STOP, faster the further he is (SWIM_GAIN per metre, at most SWIM_MAX), no up or
    -- down speed (his height is set above). And he faces where he swims (the yaw is kept in h.swim_yaw: reading it
    -- back from a tilted body gave a wrong, stuck angle, "faces 128" the whole swim).
    local dx, dz = px - nx, pz - nz
    local dist = math.sqrt(dx * dx + dz * dz)
    -- (owner 11:12 "if he's still swimming he hasn't arrived") with the player out of the water, the follow distance
    -- does not hold him in it: he keeps going (to SWIM_OUT_STOP) and the hop and the stuck notice count at any distance
    -- past that (11:00: he floated 3.0 m off the island, the player 0.7 m above him, and nothing pulled him out)
    local stop = pwet and DRIVE_STOP or SWIM_OUT_STOP
    local spd = 0
    if dist > stop then spd = math.min(SWIM_MAX, 1 + (dist - stop) * SWIM_GAIN) end
    if dist > 0.05 then h.swim_yaw = math.atan(dx, dz) end
    local yaw = h.swim_yaw or 0
    -- (owner 10:44 "I walked up over a bank and he can't get out to follow me", 10:46 "I'm good with those fixes")
    -- progress toward the player while he swims: none for HOP_TICKS while the player is higher than him: a hop out,
    -- his speed set straight up (enough for the player's height + HOP_MARGIN, gravity 25) and HOP_FORWARD toward the
    -- player, for HOP_HOLD ticks without the surface hold; again at most every HOP_EVERY ticks. None for STUCK_TICKS:
    -- the orange stuck notice (stuck detection on land does not run in the water), cleared when he gets closer.
    -- (owner 10:49 "I'm getting a stuck message when he isn't stuck (in the water)", 10:50 "go ahead and do the fix")
    -- progress = how far HE has moved toward the player since the last mark (his own way along the line to the
    -- player), not the gap shrinking: keeping pace 3-4 m behind a swimming player never shrank the gap. Sliding
    -- sideways along a bank still counts as no progress. Within DRIVE_STOP he is not trying: no count.
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
      local bk, bline = blockers(world, id, h.player, nx, ny, nz, dx, dz)
      h.blocked_by = bk
      log(string.format("stuck (water): %s in his way: %s", tostring(id), bline))
      -- (owner 11:46 "lets change the other message too. I want 'stuck' to mean he's actually stuck on terrain he can't
      -- get out of like a clipping problem")
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
    return
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
  local trail = h.trail
  local last = trail[#trail]
  -- (20:29, recorder) the player's ground data every tick that it changes: is a crumb laid while he is in the air?
  pcall(function()
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
  if pwet then  -- (10:37) the player swims: no crumbs (no ground), and swimming is not a flight (no break after it)
    -- (owner 11:33 "if I leap into water he should follow", 11:39 "ok, but he's got to make sure I'm in water first")
    -- the player came down INTO the water straight from the air (no ground between): remember where he took off (his
    -- last crumb) and where he went in; the hound leaps the same way from there (below). Walking into the water is
    -- not a leap.
    if not h.pwet_prev then
      if h.air and last then
        local hp = -1
        pcall(function() hp = world:get("Health", id).dataStorage[1] end)
        h.leap = { fx = last.x, fy = last.y, fz = last.z, tx = px, ty = py, tz = pz, hp = hp }
        log(string.format("leap %s: the player leapt into the water from %.1f %.1f %.1f (%.1f m above where he went in at %.1f %.1f %.1f); edge stop off for the hound (health %s)",
          tostring(id), last.x, last.y, last.z, last.y - py, px, py, pz, tostring(hp)))
      else
        h.leap = nil
      end
    end
    airborne = true
    h.air, h.flight = nil, nil
    if h.aseg then  -- (12:38) an air segment that ended in the water
      local sg = h.aseg
      h.aseg = nil
      sg.water = true
      if sg.from then sg.from.takeoff = sg end
      log(string.format("air %s: the player took off at %.1f %.1f %.1f and came down in the water at %.1f %.1f %.1f after %.2f s; jump count %d, second push %s",
        tostring(id), sg.x0, sg.y0, sg.z0, px, py, pz, (t - sg.t0) / 60, sg.jc, tostring(sg.double)))
    end
  elseif airborne then
    h.air = h.air or t
  elseif h.air then  -- landed: a long flight is remembered until the next crumb
    -- (13:46) a glide that came down close (he was not put away) is no break: he walks over to the player
    if t - h.air > DROP_AIR_TICKS and not (h.aseg and h.aseg.states[GLIDE_STATE]) then h.flight = true end
    h.air = nil
  end
  -- (owner 2026-11-18 12:38 "add the player meta data to the bread crumbs, even if we are not using the information
  -- yet ... was I running, jumping, did I take off in the glider, and any other relevant player meta data") what the
  -- player is doing, read every tick: his locomotion state (numbers as the game has them: 0 on the ground, 2 in the
  -- air, 9/10 seen swimming; others not named yet), jump count and type, speed and up/down speed, facing, water depth.
  -- Each crumb keeps it (crumb.m). Every time in the air between two crumbs is an "air segment": where he took off
  -- (the crumb before it gets .takeoff), the highest point, how long, the jump count, every locomotion state seen
  -- (the glider has its own), a second push up mid-air (a double jump), and where he came down (the first crumb
  -- after it gets .landing; into the water: .water). Logged as "air <id>: ...". Nothing uses it yet but the double
  -- jump follow (below).
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
    -- (13:40, glider design) every new locomotion state in the air, when it shows up: which number is the glider
    if not sg.states[pm.st] then
      log(string.format("air %s: player state %d after %.2f s in the air (height %.1f, %.1f m from takeoff, speed %.1f, up %.1f)",
        tostring(id), pm.st, (t - sg.t0) / 60, py, math.sqrt((px - sg.x0) ^ 2 + (pz - sg.z0) ^ 2), pspd, pm.vy))
    end
    sg.states[pm.st] = true
    -- a second push up after he had started to come down (or slow down): a double jump
    if t > sg.t0 + 5 and pm.vy > sg.minvy + 3 then sg.double = true end
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
  -- (owner 13:40 "it should briefly wait to make sure im just just popping it out quick and landing near by. when it
  -- realises I'm not coming back, distance too far, etc, it automatically 'despawns' it waits until I arrive back on
  -- ground and magically spawns back in next to me"; 13:46 the notices) the glider (locomotion state GLIDE_STATE, 13:42)
  -- in this flight and still in the air after GLIDE_WAIT, or GLIDE_FAR away: put away (F.tick does it).
  -- (same message: "this could use the same teleport function as when I move across the map from a fast travel") the
  -- player more than FAR_JUMP from where he was one tick ago: put away too.
  local dog_d = math.sqrt((px - nx) ^ 2 + (pz - nz) ^ 2)
  if h.aseg and h.aseg.states[GLIDE_STATE] and (t - h.aseg.t0 > GLIDE_WAIT or dog_d > GLIDE_FAR) then
    h.go_away = "glide"
    return
  end
  if h.last_px and (px - h.last_px) ^ 2 + (pz - h.last_pz) ^ 2 > FAR_JUMP ^ 2 then
    h.go_away = "fast travel"
    return
  end
  h.last_px, h.last_pz = px, pz
  -- (the general teleport fallback, owner 08:23 "he'll just teleport to me in any situation he cant really get to me",
  -- 13:00 "get the teleport stuff in there", 13:44 proposal yes) he cannot follow (stuck, waiting at a drop, or the
  -- water stucks) for TP_AFTER: put away, back beside the player once he stands on the ground
  if h.stuck or h.waiting or h.sstuck or h.wstuck then
    h.cant_since = h.cant_since or t
    if t - h.cant_since > TP_AFTER then
      h.go_away = "can't follow"
      return
    end
  else
    h.cant_since = nil
  end
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
  -- (15:47) his route planner still runs with the AI off and writes "don't move" into his input every step (only the
  -- look direction got through): switched off too, every tick
  h.pwet_prev = pwet
  local pw = world:get("DynamicPathWalker", id)
  if pw and pw.isWalkingActive ~= false then pw.isWalkingActive = false end
  -- (07:47 a fixed Lua jump boost was here; owner 07:47: "the dog should just be able to adjust his jump height":
  -- the boost is now worked out per jump in the C++ probe from the step's height, see server_probe.cpp)
  -- (owner 2026-11-18 07:15: "my main concern is he clears the jump, but still slides") recorder: his locomotion
  -- state and the game's slide flags, into the server log whenever they change
  pcall(function()
    local loc = world:get("DynamicLocomotion", id)
    local key = string.format("state %s, slide %s, sliding/falling %.2f, friction %.2f", tostring(loc.state),
      tostring(loc.slideDetected), tonumber(loc.slidingFallingFactor) or -1, tonumber(loc.frictionFactor) or -1)
    if key ~= h.slidekey then
      h.slidekey = key
      log(string.format("slide %s: %s at %.1f %.1f %.1f", tostring(id), key, nx, ny, nz))
    end
  end)
  -- (owner 22:46, edge-check test) a lure: one point he walks to for a while instead of the trail (no crumb checks);
  -- only the native edge stop can keep him from walking off a cliff on the way. npc lure <npc> <x> <y> <z> [s]
  -- (owner 12:31/12:38 "we double-jump a lot and he'll need to follow during that situation"; "I don't really want to
  -- change how any of the existing stuff ... other than adding the ability to follow a double jump to higher heights")
  -- only where the player DOUBLE-jumped (jump count 2+, or a second push up mid-air) and came down at least DJ_RISE
  -- higher: when the hound stands at that takeoff crumb (within DJ_AT, about its height) he is launched toward the
  -- landing point: his speed set straight up for the landing height + DJ_MARGIN (gravity 25, at most 16 m/s) and
  -- across so he comes down there (at most 10 m/s). The native edge stop and step jump are off for the flight
  -- (DJ_TICKS at most). Everything else (single jumps, the step jump, drops) is as before. Logs "double jump <id>: ...".
  if h.djump then
    local okl, lst = pcall(function() return tonumber(world:get("DynamicLocomotion", id).state) end)
    if okl and lst == 2 and not h.djump.air then
      h.djump.air = true
      log(string.format("double jump %s: in the air after %d tick(s)", tostring(id), t - h.djump.t0))
    end
    -- (12:47: at 12:45:06 the game counted him in the air only after 14 ticks; the old 10-tick limit ended the flight
    -- early, the drive took over mid-air and he flew 7.6 m, past the ledge) up to DJ_LIFT ticks for the game to count
    -- him in the air; the launch speed is written again until then
    if not h.djump.air and t <= h.djump.t0 + DJ_LIFT then
      pcall(function()
        local v = world:get("Velocity", id).velocity
        v.x, v.y, v.z = h.djump.vx, h.djump.vy, h.djump.vz
      end)
    end
    -- (owner 12:52 "if you think you can tweak it go ahead"; 12:50:40 he went nearly straight up: the speed across did
    -- not hold once he was in the air) in the air the speed across is written again every tick, toward the landing
    -- spot (the up/down speed is left to gravity), until he is over it
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
    -- over the landing spot (within 0.6 m across): no more speed across, he drops onto it
    if not h.djump.over and (nx - h.djump.x1) ^ 2 + (nz - h.djump.z1) ^ 2 < 0.6 ^ 2 then
      h.djump.over = true
      pcall(function()
        local v = world:get("Velocity", id).velocity
        v.x, v.z = 0, 0
      end)
      h.djump.vx, h.djump.vz = 0, 0
    end
    if t > h.djump.untill or (h.djump.air and okl and lst ~= 2) or (not h.djump.air and t > h.djump.t0 + DJ_LIFT) then
      local hp = -1
      pcall(function() hp = world:get("Health", id).dataStorage[1] end)
      log(string.format("double jump %s: down at %.1f %.1f %.1f, %.1f m from the player's landing (%.1f m %s it), health %s (was %s)",
        tostring(id), nx, ny, nz, math.sqrt((nx - h.djump.x1) ^ 2 + (nz - h.djump.z1) ^ 2), math.abs(ny - h.djump.y1),
        ny >= h.djump.y1 - 0.5 and "level with" or "below", tostring(hp), tostring(h.djump.hp)))
      -- (owner 12:52 "one time he cleared the jump, but slid off") after a landing up top he stands still DJ_SETTLE ticks
      if h.djump.air and ny >= h.djump.y1 - 0.5 then h.djsettle = t + DJ_SETTLE end
      h.djump = nil
    else
      pcall(function() a.combatData.targetOfMyTarget = true end)
      return
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
      -- (owner 12:56 "the first two times he had to jump twice": each follow landed within 0.5 m of the player's landing,
      -- level with it, then the native step jump hopped him in place right as the settle ended) the step jump (and the
      -- edge stop) are off while he settles; he stands still, so nothing can carry him over an edge
      pcall(function() a.combatData.targetOfMyTarget = true end)
      a.homeZonePosition.x, a.homeZonePosition.y, a.homeZonePosition.z = nx, ny, nz
      a.movementTarget.x, a.movementTarget.y, a.movementTarget.z = nx, ny, nz
      a.movementTargetIsValid = true
      return
    end
  end
  if not pwet then
    for i = 1, math.min(#trail, 8) do
      local cc = trail[i]
      local sg = cc.takeoff
      -- (owner 12:40 "if jumping higher is his only block to following me, he should do it") any jump of the player's
      -- that came down DJ_RISE or more higher counts too, once the hound has made no progress there for DJ_WAIT ticks
      -- (his own step jump first, as before); a double jump goes at once.
      local blocked_here = h.prog and t - h.prog.t > DJ_WAIT
      if sg and not sg.used and not sg.water and sg.x1 and sg.rise >= DJ_RISE and (sg.jc >= 2 or sg.double or blocked_here) then
        if (cc.x - nx) ^ 2 + (cc.z - nz) ^ 2 < DJ_AT ^ 2 and math.abs(ny - cc.y) < 1.0 then
          local ddx, ddz = sg.x1 - nx, sg.z1 - nz
          local d = math.sqrt(ddx * ddx + ddz * ddz)
          local rise = sg.y1 - ny
          local vup = math.min(16, math.sqrt(2 * 25 * math.max(0.5, rise + DJ_MARGIN)))
          local disc = math.max(0, vup * vup - 2 * 25 * rise)
          local tdown = (vup + math.sqrt(disc)) / 25
          local vh = math.min(10, d / math.max(0.2, tdown))
          local hp = -1
          pcall(function() hp = world:get("Health", id).dataStorage[1] end)
          -- (12:46: at 12:42:54 a Velocity write alone did nothing on the ground: he never left it, state stayed 0) lifted
          -- 0.3 m off the ground first, and the speed is written again every tick until the game counts him in the air
          local okv = pcall(function()
            local tr = world:get("CurrentTransform", id).transform
            tr.position.y = tr.position.y + math.floor(0.3 * 2 ^ 32)
            local v = world:get("Velocity", id).velocity
            if d > 0.05 then v.x, v.z = ddx / d * vh, ddz / d * vh else v.x, v.z = 0, 0 end
            v.y = vup
          end)
          if d > 0.05 then
            local yaw = math.atan(ddx, ddz)
            local o = world:get("CurrentTransform", id).transform.orientation
            o.x, o.y, o.z, o.w = 0, math.sin(yaw / 2), 0, math.cos(yaw / 2)
          end
          pcall(function() a.combatData.targetOfMyTarget = true end)
          sg.used = true
          for _ = 1, i do table.remove(trail, 1) end
          h.stuck, h.waiting, h.prog = nil, nil, nil
          status(world, h.player, "companion_stuck", nil)
          h.djump = { t0 = t, untill = t + DJ_TICKS, x1 = sg.x1, y1 = sg.y1, z1 = sg.z1, hp = hp,
                      vx = d > 0.05 and ddx / d * vh or 0, vz = d > 0.05 and ddz / d * vh or 0, vy = vup }
          log(string.format("double jump %s: follows the player's %s: %.1f m up, %.1f m out, %.1f m/s up, %.1f m/s out (health %s)%s",
            tostring(id), (sg.jc >= 2 or sg.double) and "double jump" or "jump (his own step jump did not get him up)",
            rise, d, vup, vh, tostring(hp), okv and "" or " (could not set his speed)"))
          return
        end
        break
      end
    end
  end
  -- (owner 12:40 "if jumping higher is his only block to following me, he should do it"; 12:44 a ledge 1.6 m up that the
  -- player got onto without a jump the log saw) no progress for DJ_WAIT toward his next crumb, which is DJ_RISE or
  -- more above him and no more than DJ_REACH away: the same launch toward that crumb.
  if not pwet and not h.djump and h.prog and t - h.prog.t > DJ_WAIT and h.prog.c then
    local cc = h.prog.c
    local ddx, ddz = cc.x - nx, cc.z - nz
    local d = math.sqrt(ddx * ddx + ddz * ddz)
    local rise = cc.y - ny
    if rise >= DJ_RISE and rise < 6 and d <= DJ_REACH and not cc.climbed then
      cc.climbed = true
      local vup = math.min(16, math.sqrt(2 * 25 * (rise + DJ_MARGIN)))
      local disc = math.max(0, vup * vup - 2 * 25 * rise)
      local tdown = (vup + math.sqrt(disc)) / 25
      local vh = math.min(10, d / math.max(0.2, tdown))
      local vx, vz = d > 0.05 and ddx / d * vh or 0, d > 0.05 and ddz / d * vh or 0
      pcall(function()
        local tr = world:get("CurrentTransform", id).transform
        tr.position.y = tr.position.y + math.floor(0.3 * 2 ^ 32)
        local v = world:get("Velocity", id).velocity
        v.x, v.y, v.z = vx, vup, vz
        if d > 0.05 then
          local yaw = math.atan(ddx, ddz)
          tr.orientation.x, tr.orientation.y, tr.orientation.z, tr.orientation.w = 0, math.sin(yaw / 2), 0, math.cos(yaw / 2)
        end
      end)
      pcall(function() a.combatData.targetOfMyTarget = true end)
      local hp = -1
      pcall(function() hp = world:get("Health", id).dataStorage[1] end)
      h.stuck, h.waiting, h.prog = nil, nil, nil
      status(world, h.player, "companion_stuck", nil)
      h.djump = { t0 = t, untill = t + DJ_TICKS, x1 = cc.x, y1 = cc.y, z1 = cc.z, hp = hp, vx = vx, vz = vz, vy = vup }
      log(string.format("double jump %s: jumps up to his next crumb (%.1f m up, %.1f m out; no progress for %d ticks): %.1f m/s up, %.1f m/s out",
        tostring(id), rise, d, DJ_WAIT, vup, vh))
      return
    end
  end
  if h.lure then
    if t > h.lure.untill then
      h.lure = nil  -- (23:18) the trail stays: with a fresh one he had no permission to go down the slope he was on
      fullrec_event(world, id, "drive: lure over, following again")
    else
      pcall(function() a.combatData.isTargetInsideLeash = false end)
      a.homeZonePosition.x, a.homeZonePosition.y, a.homeZonePosition.z = h.lure.x, h.lure.y, h.lure.z
      a.movementTarget.x, a.movementTarget.y, a.movementTarget.z = h.lure.x, h.lure.y, h.lure.z
      a.movementTargetIsValid = true
      -- (owner 23:40: "he just slide to the right sideways") faces the lure point while he runs there
      local fx, fz = h.lure.x - nx, h.lure.z - nz
      if fx * fx + fz * fz > 9 then
        local yaw = math.atan(fx, fz)
        local o = world:get("CurrentTransform", id).transform.orientation
        o.x, o.y, o.z, o.w = 0, math.sin(yaw / 2), 0, math.cos(yaw / 2)
      end
      return
    end
  end
  local hd = holds[id]
  if hd and (t > hd.untill or not world:position(hd.target)) then holds[id] = nil hd = nil end
  if hd then
    local gx, _, gz = world:position(hd.target)
    a.homeZonePosition.x, a.homeZonePosition.y, a.homeZonePosition.z = nx, ny, nz
    a.movementTarget.x, a.movementTarget.y, a.movementTarget.z = nx, ny, nz
    a.movementTargetIsValid = true
    local fx, fz = gx - nx, gz - nz
    if fx * fx + fz * fz > 0.04 then
      local yaw = math.atan(fx, fz)
      local o = world:get("CurrentTransform", id).transform.orientation
      o.x, o.y, o.z, o.w = 0, math.sin(yaw / 2), 0, math.cos(yaw / 2)
    end
    if t % 30 == 0 then fullrec_event(world, id, "drive: holding, facing " .. tostring(hd.target)) end
    return
  end
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
    -- (owner 20:43 "I jumped over him and he's confused", log: he ran back and forth 0.3 m around one crumb) a crumb he
    -- has reached (within 0.5 m) is gone for good. Before, the crumb he had just passed stayed the nearest one while the
    -- next crumb was far (3 m after a jump), and once he was 0.5 m past it, it was "ahead" again and he turned back.
    -- The last crumb before a drop stays: he waits there.
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
  -- (owner 2026-11-18 07:23: "this is a big enough issue, where I think we need to add some code for this") stuck:
  -- he heads for a crumb (more than DRIVE_STOP from the player) but has not come 0.3 m closer to it for 3 s (seen:
  -- the 1.3 m step 20:33, the cliff face 23:55, the rock 07:17). Then he stops pushing, stands where he is, the
  -- owner gets "Companion is stuck!" (orange); he goes on when the player is back within 6 m on his level (fresh
  -- trail), or with P / Call.
  -- (10:37) the player swims and the trail ends at the shore (no crumbs on water): once he is at its end, he heads
  -- straight for the player, into the water; the edge stop may let him down to it (still at most 7.5 m).
  -- (owner 10:53 island: the edge stop read the water as a 6.3 m cliff and held him 0.8 m short of the last crumb, so
  -- this never started; 10:55 "is it possible for him to know I'm just in the water?") the player's own water depth
  -- gives the water surface (his height + his depth): when the hound stands near that level (at most WATER_NEAR above
  -- it, not below it by more than 1 m) the drop ahead is the water, not a cliff. Then, once the trail ahead is short
  -- (its last crumb within 3 m, or none), he heads straight for the swimming player; a stuck there is over.
  -- (owner 12:23/12:26 "it happened again", 12:27 "yup make it") once he heads straight for the swimming player he stays
  -- on it while the player is in the water: walking toward the player carried him past 3 m from the trail's last
  -- crumb, the switch went back to the trail, he turned to the crumb, came within 3 m, switched again: a flip every
  -- 0.15 s on the shore (last crumb exactly 3.0 m away). It ends when he is in the water himself (the water branch
  -- returns before this) or the player leaves the water.
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
    -- (12:23 flip-flop every 10 ticks) why: every value the switch looks at
    log(string.format("drive %s: switch: player wet %s (depth %.2f), surface %s, his height %.2f, near water %s, leap %s, player %.1f m, trail %d crumbs, last crumb %s m, tick %d",
      tostring(id), tostring(pwet), pwater, surface and string.format("%.2f", surface) or "-", ny, tostring(near_water), tostring(h.leap ~= nil), dp, #trail,
      lastc and string.format("%.1f", math.sqrt((lastc.x - nx) ^ 2 + (lastc.z - nz) ^ 2)) or "-", t))
  end
  -- (owner 11:25 "the dog doesn't say he's stuck"; 11:39 ok) heading straight for the swimming player there is no crumb to
  -- watch: his own way toward the player counts (as in the water); none for STUCK_TICKS: the orange notice
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
      local bk, bline = blockers(world, id, h.player, nx, ny, nz, tdx, tdz)
      h.blocked_by = bk
      log(string.format("stuck (to the water): %s in his way: %s", tostring(id), bline))
      -- (owner 11:43 "he's not really stuck, he just can't follow me, so the notice should say 'Companion can't follow you!'")
      status(world, h.player, "companion_stuck", "Companion can't follow you!", "#ff9050")
    end
  elseif h.sstuck then
    h.sstuck, h.sprog = nil, nil
    status(world, h.player, "companion_stuck", nil)
  end
  local alive = true
  pcall(function() alive = world:get("Health", id).dataStorage[1] > 0 end)
  if c and alive and not h.waiting and not h.stuck then
    local dc = math.sqrt((c.x - nx) ^ 2 + (c.z - nz) ^ 2)
    if h.prog == nil or h.prog.c ~= c or dc < h.prog.d - 0.3 then
      h.prog = { c = c, d = dc, t = t }
    elseif t - h.prog.t > STUCK_TICKS then
      h.stuck = true
      h.stuck_px, h.stuck_pz = px, pz  -- (12:46) where the player was when he gave up
      h.prog = nil
      -- (owner 08:18: "he's not technically stuck, he's just scared to jump") why, from where the crumb is
      local dy = c.y - ny
      h.stuck_why = dy < -0.8 and "down" or (dy > 0.6 and "up" or "blocked")
      -- (owner 08:41: "he's not stuck, he's afraid to jump") a drop the player took, within 3 m ahead on the trail: the
      -- edge stop held him back from its lip (08:40, a 27 m drop)
      for i = 1, #trail do
        local cc = trail[i]
        if (cc.x - nx) ^ 2 + (cc.z - nz) ^ 2 > 3 ^ 2 then break end
        if cc.brk then h.stuck_why = "drop" break end
      end
      log(string.format("stuck: %s gave up at %.1f %.1f %.1f (crumb %.1f %.1f %.1f, %.1f m away, player %.1f m)", tostring(id),
        nx, ny, nz, c.x, c.y, c.z, dc, dp))
      local bk, bline = blockers(world, id, h.player, nx, ny, nz, c.x - nx, c.z - nz)
      h.blocked_by = bk
      log(string.format("stuck: %s in his way: %s", tostring(id), bline))
      fullrec_event(world, id, "drive: stuck, gave up")
      status(world, h.player, "companion_stuck", STUCK_TEXT[h.stuck_why] or "Companion is stuck!", "#ff9050")
    end
  elseif not c then
    h.prog = nil
  end
  if h.stuck then
    -- (owner 12:44 "I'm getting 'Companion can't get up there!' in the messages window, but not the notice window... so
    -- that should be fixed") the player stood within 6 m when he gave up, so "the player is back near him" was true at
    -- once: notice on, notice off, again every 3 s (a Messages line each time, the Notices window never kept it). He
    -- goes on only when the player has moved (STUCK_MOVED) since he gave up and is near him.
    local moved = not h.stuck_px or (px - h.stuck_px) ^ 2 + (pz - h.stuck_pz) ^ 2 > STUCK_MOVED ^ 2
    if moved and (px - nx) ^ 2 + (pz - nz) ^ 2 < DROP_RESUME ^ 2 and math.abs(py - ny) < 2 then
      -- (owner 08:25) the fresh trail starts where HE stands (08:23: it started where the player was, a bit below him,
      -- and he refused to walk down to it)
      h.trail, h.stuck, h.prog = { { x = nx, y = ny, z = nz } }, nil, nil
      status(world, h.player, "companion_stuck", nil)
      log("stuck: " .. tostring(id) .. " goes on: the player is back near him")
      fullrec_event(world, id, "drive: player back near him, stuck over, fresh trail")
    else
      a.homeZonePosition.x, a.homeZonePosition.y, a.homeZonePosition.z = nx, ny, nz
      a.movementTarget.x, a.movementTarget.y, a.movementTarget.z = nx, ny, nz
      a.movementTargetIsValid = true
      if t % 30 == 0 then fullrec_event(world, id, string.format("drive: stuck, waiting, player %.1f m", dp)) end
      -- (owner 07:35) the notice shows how far the player is, once a second, so he sees when he is within reach
      if t % 60 == 0 then
        local dy = py - ny
        status(world, h.player, "companion_stuck", string.format("%s %.1f m away, %.1f m %s (come within %d m, %d m height)",
          STUCK_TEXT[h.stuck_why] or "Companion is stuck!", dp, math.abs(dy), dy >= 0 and "higher" or "lower", DROP_RESUME, 2), "#ff9050")
      end
      return
    end
  end
  if h.waiting then
    -- at a drop: stand still at the last safe crumb; go on when the player is back near him, on his level
    if (px - nx) ^ 2 + (pz - nz) ^ 2 < DROP_RESUME ^ 2 and math.abs(py - ny) < 2 then
      h.trail, h.waiting = { { x = nx, y = ny, z = nz } }, nil  -- (08:25) starts where he stands, as above
      if h.wait_told then h.wait_told = nil status(world, h.player, "companion_stuck", nil) end
      fullrec_event(world, id, "drive: player back near him, waiting over, fresh trail")
    elseif c and (c.x - nx) ^ 2 + (c.z - nz) ^ 2 > 0.6 ^ 2 then
      h.waiting = nil  -- not at the last safe crumb yet: walks there first (below, as usual)
    else
      a.homeZonePosition.x, a.homeZonePosition.y, a.homeZonePosition.z = nx, ny, nz
      if c then a.movementTarget.x, a.movementTarget.y, a.movementTarget.z = c.x, c.y, c.z end
      a.movementTargetIsValid = true
      if t % 30 == 0 then fullrec_event(world, id, string.format("drive: waiting at a drop, player %.1f m", dp)) end
      -- (owner 08:18) a status for this wait too, with how far the player is (once a second); cleared when he goes on
      if t % 60 == 0 then
        local dy = py - ny
        status(world, h.player, "companion_stuck", string.format("Companion is afraid to follow (drop too high)! %.1f m away, %.1f m %s (come within %d m, %d m height)",
          dp, math.abs(dy), dy >= 0 and "higher" or "lower", DROP_RESUME, 2), "#ff9050")
        h.wait_told = true
      end
      return
    end
  end
  -- the native hook reads these: the next crumb (or the player) and the player
  a.homeZonePosition.x, a.homeZonePosition.y, a.homeZonePosition.z = px, py, pz
  local tx, ty, tz = px, py, pz
  if c then tx, ty, tz = c.x, c.y, c.z end
  -- (owner 22:55) the native edge stop lets him drop more than 2.5 m only where the player went down himself: his
  -- next crumb is that much lower (a crumb after a drop over 7.5 m is a break, so he never gets here for those)
  -- (23:02: the owner walked down a steep slope, crumbs 0.5 m apart each only a little lower, the ray 1.5 m ahead saw
  -- 2.8 m down: stopped wrongly) the trail within 3 m ahead of him counts: if it goes more than 2 m below him there,
  -- the player went down here.
  pcall(function()
    local ok = h.to_swimmer or false
    for i = 1, #trail do
      local cc = trail[i]
      -- (23:19: after a script reload his trail began at the player 4 m away and 1.5 m below: no crumb within 3 m,
      -- he could not come down the slope he stood on) 6 m, and the crumb no more than 7.5 m below him
      -- (owner 08:23 "yeah try the fix": he jumped down a slope, his next crumb landed 8.9 m away, beyond the 6 m) 12 m
      if (cc.x - nx) ^ 2 + (cc.z - nz) ^ 2 > 12 ^ 2 then break end
      if cc.brk then break end
      if cc.y < ny - 0.8 and cc.y > ny - 7.5 then ok = true break end  -- (23:15, with the 30 degree limit)
    end
    -- (owner 2026-11-18 10:00-10:06, trap door) a level floor the edge ray cannot see: the ray went through a closed
    -- trap door and saw the ground 5.5 m below, though the player had walked over it. A crumb is laid only on solid
    -- ground, about every 0.25 m, so an UNBROKEN level trail ahead proves a floor: from him, each crumb no more than
    -- FLOOR_LINK from the one before, none more than 0.8 m above or below him, no break, out to FLOOR_REACH (past his
    -- furthest ray, 3.5 m when sprinting). A jump leaves a gap in the trail (no crumbs in the air): no proof there, so a
    -- hole the player JUMPED over still stops him (owner 10:03). The 7.5 m limit in the native stop still holds.
    local proof = false
    if not ok then
      local lx, lz, far = nx, nz, 0
      for i = 1, #trail do
        local cc = trail[i]
        if cc.brk then break end
        if (cc.x - lx) ^ 2 + (cc.z - lz) ^ 2 > FLOOR_LINK ^ 2 then break end
        if math.abs(cc.y - ny) > 0.8 then break end
        lx, lz = cc.x, cc.z
        far = math.sqrt((cc.x - nx) ^ 2 + (cc.z - nz) ^ 2)
        if far >= FLOOR_REACH then proof = true break end
      end
      if proof ~= (h.floorproof or false) then
        log(string.format("edge %s: %s (unbroken level trail %.1f m ahead) at %.1f %.1f %.1f", tostring(id),
          proof and "floor proven by the trail" or "no floor proof", far, nx, ny, nz))
      end
      ok = proof
    end
    h.floorproof = proof
    a.combatData.isTargetInsideLeash = ok
  end)
  a.movementTarget.x, a.movementTarget.y, a.movementTarget.z = tx, ty, tz
  a.movementTargetIsValid = true
  -- (owner 17:32: "the model doesn't point the direction its going ... make it face the direction its going") while he
  -- moves, his body is turned toward the crumb he is heading for (yaw only, upright), every tick
  if dp > DRIVE_STOP then
    local fx, fz = tx - nx, tz - nz
    if fx * fx + fz * fz > 0.04 then
      local yaw = math.atan(fx, fz)
      local o = world:get("CurrentTransform", id).transform.orientation
      o.x, o.y, o.z, o.w = 0, math.sin(yaw / 2), 0, math.cos(yaw / 2)
    end
  end
  if t % 30 == 0 then
    fullrec_event(world, id, string.format("drive: %s, target %.2f %.2f %.2f, player %.1f m", how, tx, ty, tz, dp))
  end
end


-- ===== Staying (owner 17:06: "I DO NOT WANT TO USE ANYTHING FROM THE GAME THAT USES THIER CRAPPY AI") ==============
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

-- ===== The roster (B4, owner 11:56/11:58): FlameKit's own list of NPCs, kept in the world's data =====================
-- Each NPC has a name (N1, N2 ...) and keeps it whether its body is out in the world or put away. A record: body
-- (template GUID), spot, mode (stay/follow), owner (account), out (true: has a body in the world). The game
-- deletes our bodies on a restart (seen 11:52): out ones come back, stayers at their spot when the world loads,
-- followers next to their owner when he joins. A probe reload finds its bodies again (by entity, faction 11 (7 before 19:31) and the
-- calm switches) instead of spawning a second one.
-- (owner 19:31) companions are PlayerAlly (11), the game's own "on the players' side": friends of players, enemies of
-- monsters. Faction 7 (Player) made every monster attack of theirs do 0 damage (bite test 19:23: 11 = 239 pierce).
local COMPANION_FACTION = 11
local HOUND = "18eefd30-da1d-49f5-a6d8-7da8f2d01f43"  -- Enemy_Skeleton_Hound, the owner's pick
local roster = { list = {}, next_n = 1, loaded = false, main = {} }  -- main: account -> name (owner 13:06: one main companion each)
local pending_life = {}  -- entity -> { r, player, at }: set up half a second after spawning
local waiting = {}       -- name -> { player, tries }: a follower waiting for its owner's body
local ent_of = {}     -- name -> entity (this session only)
local name_of = {}    -- entity -> name

-- (owner 12:36-12:40) who may command an NPC: its controllers (a list of accounts: one for a personal companion,
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
-- (owner 19:47 "make him match my stats") a companion's level is its owner's level, set the way the game's own scaling
-- does it (Level.dataStorage[1], then DynamicEnemyScaling.nextUpdateTime = 0: the game rescales health and hits; seen
-- 18:36: level 30 = 1164 HP, bite 239). Checked at setup and every 10 s (the owner joins later, or levels up).
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
  -- (07:31) a living body again: the death and stuck notices go
  local owner_p = player or player_of(world, r.owner)
  status(world, owner_p, "companion_dead", nil)
  status(world, owner_p, "companion_stuck", nil)
  if r.face_yaw then  -- (07:09) a Call: he faces the way the player faced
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
    drives[id] = { player = player, trail = {}, logcrumbs = true }  -- logcrumbs: (20:34 test) every crumb into the log
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
  pcall(function() world:get("DynamicEnemy01BehaviorState", id).enabled = false end)  -- (owner 17:06) no game AI, ever
  r.out = true
  pending_life[id] = { r = r, player = player, at = world:tick() + 30 }  -- the rest half a second later
  ent_of[r.name], name_of[id] = id, r.name
  log(string.format("roster: %s spawned as %s at %.1f %.1f %.1f (%s)", r.name, tostring(id), x, y, z, r.mode))
  return id
end

-- is this entity still our body (a probe reload keeps the bodies; a restart may give the id to something else)?
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
      -- (12:40) records from before the controller lists: their owner is the only controller
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
      if still_ours(world, ent) then  -- a probe reload: the body is still there
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
    -- (12:48) "0x..." is an account, not a player entity (tonumber read 0x...02 as player 2, whose name is "Player")
    local p = not tostring(args[4]):match("^0x") and tonumber(args[4]) or nil
    local acc = (p and world:account(p)) or args[4]
    if not (acc and acc:match("^0x%x+$")) then emf.reply("roster: no player/account " .. tostring(args[4])) return end
    r.names = r.names or {}
    if p then r.names[acc] = players.name(world, p) end
    if what == "give" then
      r.controllers, r.owner = { acc }, acc
      roster.main[acc] = r.name  -- (13:06) a companion given to a player is his main one
    elseif what == "share" then
      if not controls(r, acc) then r.controllers[#r.controllers + 1] = acc end
    else
      for i = #r.controllers, 1, -1 do if r.controllers[i] == acc then table.remove(r.controllers, i) end end
    end
    roster_save()
    log(string.format("roster: %s %s %s: controllers now %s", r.name, what, acc, table.concat(r.controllers, ",")))
    emf.reply("roster: " .. what .. " done")
  elseif what == "here" then  -- here <name> <player>: (13:09, stuck in a fence post) moved onto the player's spot
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
    -- (12:48) "0x..." is an account, not a player entity (tonumber read 0x...02 as player 2, whose name is "Player")
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

-- (owner 12:49, step 2) E opens a wheel on the presser's own screen (FlameKit's game side, channel flamekit/npcwheel);
-- a game without it gets the old follow/stay switch. The server checks who may command the NPC, again at the pick.

-- ===== E: the wheel (owner 12:49) ====================================================================================
-- E opens a wheel on the presser's own screen (FlameKit's game side, channel flamekit/npcwheel). The server checks who
-- may command the NPC, again at the pick. No other path (owner 17:00: no fallback).
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

-- "Call my companion" (Experimental panel; owner 13:03/13:06/16:54): the main companion's old body, if any (alive, dead
-- or stuck anywhere), is removed and a fresh one is spawned on the player's spot, following him
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
  -- (owner 2026-11-18 07:07/07:08: "spawn like .5 to the ... right of me") 0.5 m to the player's right (his facing:
  -- forward = (sin yaw, cos yaw) as the dog's facing code uses, right = (cos yaw, -sin yaw); if it comes out on the
  -- left, the axes are the other way round)
  local pyaw
  pcall(function()
    local o = world:get("CurrentTransform", player).transform.orientation
    local yaw = math.atan(2 * (o.x * o.z + o.w * o.y), 1 - 2 * (o.x * o.x + o.y * o.y))
    x, z = x + math.cos(yaw) * 0.3, z - math.sin(yaw) * 0.3  -- (owner 07:10: 0.3 m, was 0.5)
    pyaw = yaw
  end)
  local id = spawn_body(world, r, x, y + 0.5, z, player)
  -- (owner 07:09: "make it point the same way I am") his body turned like the player's, now and again when he is
  -- set up half a second later (bring_to_life)
  if id and pyaw then
    r.face_yaw = pyaw
    pcall(function()
      local o = world:get("CurrentTransform", id).transform.orientation
      o.x, o.y, o.z, o.w = 0, math.sin(pyaw / 2), 0, math.cos(pyaw / 2)
    end)
  end
  roster_save()
  -- (owner 13:46 "ANY time he spawns by you, there should be a notice that says 'Companion has spawned near you!'")
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

local hit_watch = {}  -- entity -> true: (18:54) its hits go into the HIT log too (npc spawnwild adds the body)
function F.setup(k)
  -- (18:48, recorder) every hit a companion gives or takes: amount, health around it, types, attack kind, reaction
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
      elseif what == "spawnwild" then  -- spawnwild <guid> <player> [metres]: (owner 17:41, observation) a wild body, its own AI
        local guid, player, m = args[2], tonumber(args[3]) or 1, tonumber(args[4]) or 6
        local x, y, z = world:position(player)
        if not (guid and x) then emf.reply("npc: spawnwild <guid> <player> [metres]") return end
        local ok, id = pcall(emf.spawn, world, guid, x, y + 0.5, z + m)
        if ok and id then hit_watch[id] = true end
        log(string.format("spawnwild %s %.0f m north of %s: %s", guid, m, tostring(player), ok and tostring(id) or ("error: " .. tostring(id))))
        emf.reply("npc: spawnwild " .. tostring(ok and id))
      elseif what == "face" then  -- face <npc> <target> [metres]: (owner 18:32, bite test) the npc put m metres in front of
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
      elseif what == "level" then  -- level <entity> <level>: (owner 18:35 "give that dog stronger stats") the way
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
      elseif what == "combat" then  -- combat <npc> <target> [attack]: (owner 19:22, damage test) the combat numbers a wild
        -- hound has while it bites (fullrec_25792 18:55:03), copied as plain values, AI stays off
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
      elseif what == "faction" then  -- faction <entity> <n>: (19:24 damage test) EMF combat.md: 7 Player, 11 PlayerAlly,
        -- 1 HitAll, 10 Skeleton. The PvP notes: a monster body with faction 7 did 0 damage, with faction 1 it did damage.
        local id, fn = tonumber(args[2]), tonumber(args[3])
        local f = id and world:get("Faction", id)
        if not (f and fn) then emf.reply("npc: faction <entity> <n>") return end
        f.faction = fn
        log(string.format("faction: %s now %d", tostring(id), fn))
        emf.reply("npc: faction")
      elseif what == "attr" then  -- attr <entity> <Strength|Dexterity|Intelligence> <value>: (owner 19:59 "test what we
        -- have and see if it works") dataStorage[1] and [2] (a player has total, base, bonus: Strength 26 11 15)
        local id, comp, v = tonumber(args[2]), args[3], tonumber(args[4])
        local c = id and comp and world:get(comp, id)
        if not (c and v) then emf.reply("npc: attr <entity> <component> <value>") return end
        c.dataStorage[1] = v
        c.dataStorage[2] = v
        log(string.format("attr: %s %s = %s", tostring(id), comp, tostring(v)))
        emf.reply("npc: attr")
      elseif what == "tpground" then  -- tpground <entity> <x> <y> <z>: (owner 22:04, test) EMF's teleport with the game's
        -- ground search: does the walkable search answer at this spot, and where does it put the body?
        local id, x, y, z = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]), tonumber(args[5])
        if not (id and x and y and z) then emf.reply("npc: tpground <entity> <x> <y> <z>") return end
        local c0 = os.clock()
        -- (22:07 fix) the callback must not touch `world` (EMF paused the whole script at 22:06:03 for world:tick())
        local okt, res = pcall(emf.teleport, world, id, x, y, z, { ground = true }, function(moved, mx, my, mz)
          log(string.format("tpground %s -> %.1f %.1f %.1f: moved %s to %s %s %s (%.1f s)", tostring(id), x, y, z,
            tostring(moved), tostring(mx and string.format("%.2f", mx)), tostring(my and string.format("%.2f", my)),
            tostring(mz and string.format("%.2f", mz)), os.clock() - c0))
        end)
        log(string.format("tpground %s -> %.1f %.1f %.1f: queued %s", tostring(id), x, y, z, tostring(okt and res)))
        emf.reply("npc: tpground")
      elseif what == "lure" then  -- lure <npc> <x> <y> <z> [seconds]: (owner 22:46) edge-check test, see drive_step
        local id, x, y, z, sec = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]), tonumber(args[5]), tonumber(args[6]) or 15
        local h = id and drives[id]
        if not (h and x and y and z) then emf.reply("npc: lure <following npc> <x> <y> <z> [seconds]") return end
        h.lure = { x = x, y = y, z = z, untill = world:tick() + math.floor(sec * 60) }
        log(string.format("lure: %s walks toward %.1f %.1f %.1f for %.0f s", tostring(id), x, y, z, sec))
        emf.reply("npc: lure")
      elseif what == "still" then  -- still <entity>: (19:01 bite test) a test target's monster AI off, so it stands
        -- still and does not go for the player (his reflect kills it)
        local id = tonumber(args[2])
        local st = id and world:get("DynamicEnemy01BehaviorState", id)
        if not st then emf.reply("npc: still <entity>") return end
        st.enabled = false
        log("still: " .. tostring(id) .. " AI off")
        emf.reply("npc: still")
      elseif what == "hold" then  -- hold <npc> <target> [seconds]: (owner 19:00) stays put and faces the target
        local id, tg, sec = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 10
        if not (id and tg) then emf.reply("npc: hold <npc> <target> [seconds]") return end
        holds[id] = { target = tg, untill = world:tick() + math.floor(sec * 60) }
        log(string.format("hold: %s holds and faces %s for %.0f s", tostring(id), tostring(tg), sec))
        emf.reply("npc: hold")
      elseif what == "atk" then  -- atk <entity> <index>: (18:45 damage test) combatData.selectedAttackIndex, the number
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

local dead_told = {}  -- entity -> true: (owner 07:23) "Companion has died!" sent once per body
-- (owner 13:40/13:46) put away by the glider, a fast travel or can't follow: name -> { player, account, why, ground }
local returning = {}
local load_seen  -- player -> "ready/teleport count" last logged (13:57)
local load_err   -- (14:08) the travel request read failed once (logged)
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
local companions_core = require("core.companions")  -- (0.15.278) the minimap's companion dots
function F.tick(world)
  if not world:is_server() then return end
  local t = world:tick()
  if t % 30 == 0 then  -- (owner 08:56/09:00) where every companion is, with its owner's character name (the dot's colour)
    local places = {}
    for name, id in pairs(ent_of) do
      local x, _, z = world:position(id)
      local r = find(name)
      if x and r then
        local p = player_of(world, r.owner)
        local okn, cname = pcall(function() return p and require("core.players").name(world, p) end)  -- the dot's colour comes from the same name the far list uses
        places[#places + 1] = { x = x, z = z, owner = (okn and cname) or "", name = name }  -- (0.15.279) the dot shows the companion's name
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
  -- (owner 13:57 "I got the 'Companion spawns near you message.' before the load was done") logging: the game's own
  -- "ready for gameplay" flag the player's client sends (PlayerInput.fromClientIsReadyForGameplay) and his
  -- TeleportCount, for every player, whenever either changes: does the flag go off during a fast travel's loading screen?
  for _, pid in ipairs((function() local ids = {} for _, r in pairs(returning) do ids[#ids + 1] = r.player end
      for _, hh in pairs(drives) do ids[#ids + 1] = hh.player end return ids end)()) do
    local okr, ready = pcall(function() return world:get("PlayerInput", pid).fromClientIsReadyForGameplay end)
    local okc, cnt = pcall(function() return world:get("TeleportCount", pid).counter end)
    -- (14:08) and the player's own fast travel request (PlayerInput.fromClient.teleportAction): does it come before
    -- the teleport (an earlier signal for hiding FlameKit's UI)?
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
      -- (owner 13:57 "is there anyway to wait UNTIL the load is done?", 14:10 "ok") and his game reports it has loaded
      -- (PlayerInput.fromClientIsReadyForGameplay: false from the teleport until the loading screen is over, 14:07)
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
