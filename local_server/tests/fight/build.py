import re, sys
src = open('local_server/features/npc_probe.lua', encoding='utf-8').read().split('\n')
def L(a, b):  # 1-indexed inclusive
    return src[a-1:b]
def body(a, b, ret_true=True):
    out = []
    for ln in L(a, b):
        if ret_true and re.fullmatch(r'[ \t]*return[ \t]*', ln):
            ln = ln.replace('return', 'return true')
        out.append(ln)
    return out
assert src[220] == 'local function drive_step(world, id, h)' and src[1043] == 'end'

P_BASE = '  local world, id, h, a, t = s.world, s.id, s.h, s.a, s.t'
P_POS = '  local px, py, pz, nx, ny, nz = s.px, s.py, s.pz, s.nx, s.ny, s.nz'
P_WET = '  local pwater, pwet = s.pwater, s.pwet'

parts = []
def part(name, doc, prologue, lines, epilogue=None, ret=None):
    out = ['-- ' + d for d in doc]
    out.append('local function %s(s)' % name)
    out += prologue
    out += lines
    if epilogue: out += epilogue
    if ret: out.append(ret)
    out.append('end')
    out.append('')
    parts.append('\n'.join(out))

header = '''-- ===== The drive, in parts (owner 2026-11-18 15:39: "#3 go ahead and do this one, we'll retest everything") ========
-- drive_step runs once per tick for each following companion. It reads the tick's facts into one table (s) and runs
-- the parts in order; a part that returns true has decided this tick (he holds, waits, jumps or is put away) and the
-- rest is skipped. The parts share only s and the companion's own record h (kept between ticks).

-- his body upright and turned toward yaw (radians, 0 = +z)
local function face(world, id, yaw)
  local o = world:get("CurrentTransform", id).transform.orientation
  o.x, o.y, o.z, o.w = 0, math.sin(yaw / 2), 0, math.cos(yaw / 2)
end

-- the native hook's target and the "player" spot both at x, y, z: he stands there (or walks there)
local function hold_at(a, x, y, z)
  a.homeZonePosition.x, a.homeZonePosition.y, a.homeZonePosition.z = x, y, z
  a.movementTarget.x, a.movementTarget.y, a.movementTarget.z = x, y, z
  a.movementTargetIsValid = true
end

-- his health (-1 when it cannot be read), for the logs
local function health(world, id)
  local hp = -1
  pcall(function() hp = world:get("Health", id).dataStorage[1] end)
  return hp
end

-- the native edge stop and step jump off for this tick (see server_probe.cpp: combatData.targetOfMyTarget)
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

-- (12:46: at 12:42:54 a Velocity write alone did nothing on the ground: he never left it, state stayed 0) the launch
-- itself: lifted 0.3 m off the ground first, then his speed up and across (toward ddx, ddz), turned that way. The
-- speed is written again every tick until the game counts him in the air (drive_jump_follow). Returns whether the
-- speed could be set, and the speed across (x, z).
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

-- a stuck notice: who stands in his way (logged; h.blocked_by keeps the kind)
local function report_blockers(s, what, dx, dz)
  local bk, bline = blockers(s.world, s.id, s.h.player, s.nx, s.ny, s.nz, dx, dz)
  s.h.blocked_by = bk
  log(string.format("%s: %s in his way: %s", what, tostring(s.id), bline))
end
'''

# read
read = ['-- the tick\'s facts: where the player and the hound are, the water both read; nil when either is gone',
        'local function drive_read(world, id, h)']
read += L(222, 227)[:2]
read.append('  if not (px and nx) then drives[id] = nil log("drive " .. tostring(id) .. ": gone, stopped") return nil end')
assert src[223].strip().startswith('if not (px and nx)')
read += L(225, 227)
read += L(284, 299)
read.append('  return { world = world, id = id, h = h, a = a, t = t, px = px, py = py, pz = pz, nx = nx, ny = ny, nz = nz,')
read.append('           pwater = pwater, pwet = pwet, hw = hw, swim = swim }')
read.append('end')
read.append('')
parts.append('\n'.join(read))

part('drive_waterlog', ['the water log (measuring only)'],
  ['  local world, id, h, t = s.world, s.id, s.h, s.t', P_POS], L(228, 283))
part('drive_water', ['water: the leap rule, swimming (returns true while he swims), and coming out of the water'],
  [P_BASE, P_POS, P_WET, '  local hw, swim = s.hw, s.swim'], body(300, 437), None, '  return false')
part('drive_track_player', ['what the player does: on the ground or in the air, a leap into the water, air segments, his meta data for the crumbs'],
  ['  local world, id, h, t = s.world, s.id, s.h, s.t', '  local px, py, pz = s.px, s.py, s.pz', '  local pwet = s.pwet'], L(438, 542),
  ['  s.trail, s.last, s.airborne, s.pm, s.pspd = trail, last, airborne, pm, pspd'])
part('drive_put_away', ['put away: a glide, a fast travel jump, or he cannot follow for TP_AFTER (F.tick does it)'],
  ['  local h, t = s.h, s.t', '  local px, pz, nx, nz = s.px, s.pz, s.nx, s.nz'], body(543, 570), None, '  return false')
part('drive_lay_crumb', ['the breadcrumb trail: a crumb every DRIVE_STEP the player walks on the ground'],
  ['  local world, id, h, t = s.world, s.id, s.h, s.t', '  local px, py, pz = s.px, s.py, s.pz', '  local pwater, trail, last, airborne, pm, pspd = s.pwater, s.trail, s.last, s.airborne, s.pm, s.pspd'],
  L(571, 586))
part('drive_upkeep', ['every tick: his route planner off, the slide recorder'],
  ['  local world, id, h = s.world, s.id, s.h', '  local nx, ny, nz = s.nx, s.ny, s.nz', '  local pwet = s.pwet'], L(587, 604))
part('drive_jump_follow', ['jump follow: a launch in flight, the settle after it, and new launches (returns true while any of these runs)'],
  [P_BASE, '  local nx, ny, nz = s.nx, s.ny, s.nz', '  local pwet, trail = s.pwet, s.trail'], body(607, 768), None, '  return false')
part('drive_lure', ['a lure (test): one point he walks to for a while instead of the trail'],
  [P_BASE, '  local nx, nz = s.nx, s.nz'], L(605, 606) + body(769, 787), None, '  return false')
part('drive_hold', ['a hold (test): he stays put and faces a target'],
  ['  local world, id, a, t = s.world, s.id, s.a, s.t', '  local nx, ny, nz = s.nx, s.ny, s.nz'], body(788, 803), None, '  return false')
part('drive_pick_target', ['his target: the next crumb, or straight to the swimming player; the stuck watch on the way to the water'],
  ['  local world, id, h, t = s.world, s.id, s.h, s.t', P_POS, P_WET, '  local trail = s.trail'], L(804, 900),
  ['  s.c, s.how, s.dp = c, how, dp'])
part('drive_stuck', ['stuck and waiting: he gives up, stands, and goes on when the player is back near him (returns true while he stands)'],
  [P_BASE, P_POS, '  local trail, c, dp = s.trail, s.c, s.dp'], body(901, 981), None, '  return false')
part('drive_steer', ['the native hook\'s inputs: the target, the edge stop\'s permission (the trail and the floor proof), his facing'],
  [P_BASE, P_POS, '  local trail, c, how, dp = s.trail, s.c, s.how, s.dp'], L(982, 1043))

main = '''local function drive_step(world, id, h)
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
end'''

new = '\n'.join(src[:220]) + '\n' + header + '\n' + '\n'.join(parts) + main + '\n' + '\n'.join(src[1044:])
open(sys.argv[1], 'w', encoding='utf-8').write(new)
