import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
cut = s.index('local function drive_read(')
head, body = s[:cut], s[cut:]
end = body.index('\nlocal function drive_step(world, id, h)')
parts, tail = body[:end], body[end:]
def sub(pat, rep, n, flags=0):
    global parts
    new, k = re.subn(pat, rep, parts, flags=flags)
    assert k == n, (pat[:60], k, n)
    parts = new
# face
sub(r'([ \t]*)local o = world:get\("CurrentTransform", id\)\.transform\.orientation\n[ \t]*o\.x, o\.y, o\.z, o\.w = 0, math\.sin\(yaw / 2\), 0, math\.cos\(yaw / 2\)\n',
    r'\1face(world, id, yaw)\n', 4)
# hold_at
sub(r'([ \t]*)a\.homeZonePosition\.x, a\.homeZonePosition\.y, a\.homeZonePosition\.z = ([\w\.]+), ([\w\.]+), ([\w\.]+)\n[ \t]*a\.movementTarget\.x, a\.movementTarget\.y, a\.movementTarget\.z = \2, \3, \4\n[ \t]*a\.movementTargetIsValid = true\n',
    r'\1hold_at(a, \2, \3, \4)\n', 5)
# health
sub(r'([ \t]*)local hp = -1\n[ \t]*pcall\(function\(\) hp = world:get\("Health", id\)\.dataStorage\[1\] end\)\n', r'\1local hp = health(world, id)\n', 5)
# edge_off
sub(r'pcall\(function\(\) a\.combatData\.targetOfMyTarget = true end\)', 'edge_off(a)', 4)
# report_blockers
sub(r'([ \t]*)local bk, bline = blockers\(world, id, h\.player, nx, ny, nz, ([^,]+), ([^)]+)\)\n[ \t]*h\.blocked_by = bk\n[ \t]*log\(string\.format\("([^"]+): %s in his way: %s", tostring\(id\), bline\)\)\n',
    r'\1report_blockers(s, "\4", \2, \3)\n', 3)
# launch 1 (the player's jump at its takeoff crumb)
o1 = '''          local d = math.sqrt(ddx * ddx + ddz * ddz)
          local rise = sg.y1 - ny
          local vup = math.min(16, math.sqrt(2 * 25 * math.max(0.5, rise + DJ_MARGIN)))
          local disc = math.max(0, vup * vup - 2 * 25 * rise)
          local tdown = (vup + math.sqrt(disc)) / 25
          local vh = math.min(10, d / math.max(0.2, tdown))
          local hp = health(world, id)
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
            face(world, id, yaw)
          end
          edge_off(a)
          sg.used = true
          for _ = 1, i do table.remove(trail, 1) end
          h.stuck, h.waiting, h.prog = nil, nil, nil
          status(world, h.player, "companion_stuck", nil)
          h.djump = { t0 = t, untill = t + DJ_TICKS, x1 = sg.x1, y1 = sg.y1, z1 = sg.z1, hp = hp,
                      vx = d > 0.05 and ddx / d * vh or 0, vz = d > 0.05 and ddz / d * vh or 0, vy = vup }
'''
n1 = '''          local d = math.sqrt(ddx * ddx + ddz * ddz)
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
'''
assert parts.count(o1) == 1; parts = parts.replace(o1, n1)
o2 = '''      local vup = math.min(16, math.sqrt(2 * 25 * (rise + DJ_MARGIN)))
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
      edge_off(a)
'''
n2 = '''      local vup, vh = launch_speeds(d, rise)  -- (rise is at least DJ_RISE here)
      local _, vx, vz = launch(world, id, ddx, ddz, d, vup, vh)
      edge_off(a)
'''
assert parts.count(o2) == 1, 'o2'; parts = parts.replace(o2, n2)
# the single-use yaw locals before face()
parts, k = re.subn(r'([ \t]*)local yaw = (math\.atan\([^\n]+\))\n[ \t]*face\(world, id, yaw\)\n', r'\1face(world, id, \2)\n', parts)
print('yaw folded', k)
open(sys.argv[2], 'w', encoding='utf-8').write(head + parts + tail)
