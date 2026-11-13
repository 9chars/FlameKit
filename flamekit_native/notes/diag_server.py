# Dev only: writes the server's copy of experimental.lua with DIAG logging added (fog timer, health, stamina, landed hits).
# usage: diag_server.py <working copy's flamekit folder> <server's emf\mods\flamekit folder>
import os, sys
src=os.path.join(sys.argv[1], 'features', 'experimental.lua')
dst=os.path.join(sys.argv[2], 'features', 'experimental.lua')
s=open(src).read()
old="    go_request = nil\n  end\nend\n"
assert old in s
s=s.replace(old,"""    go_request = nil
  end
  for _, p in pairs(online) do
    local ok, line = pcall(function()
      local c = world:get('FogResistance', p.entity)
      local t = {}
      if c then for i = 1, 6 do t[i] = tostring(c.dataStorage[i]) end end
      return 'DIAG fog ' .. table.concat(t, ' ') .. ' hp ' .. tostring(emf.attribute(world, p.entity, 'health')) .. ' st ' .. tostring(emf.attribute(world, p.entity, 'stamina')) .. '/' .. tostring(emf.attribute(world, p.entity, 'max_stamina'))
    end)
    if p.lift and p.lift > 0 then
      DIAG_n = (DIAG_n or 0) + 1
      if DIAG_n % 6 == 0 then
        pcall(function()
          local v = world:get('Velocity', p.entity).velocity
          local d = world:get('DynamicLocomotion', p.entity)
          local x, y, z = world:position(p.entity)
          local q = world:get('CurrentTransform', p.entity).transform
          local okq, rot = pcall(function() return string.format('%.2f %.2f %.2f %.2f', q.orientation.x, q.orientation.y, q.orientation.z, q.orientation.w) end)
          emf.log(string.format('DIAG climb state %s vel %.1f %.1f %.1f in %.1f %.1f %.1f pos %.1f %.1f %.1f rot %s flags %s', tostring(d.state), v.x, v.y, v.z,
            d.inputVelocity.x, d.inputVelocity.y, d.inputVelocity.z, x or 0, y or 0, z or 0, tostring(rot), tostring(d.flags)))
        end)
      end
    end
    line = tostring(line)
    if line ~= DIAG_last and os.time() ~= DIAG_t then DIAG_last = line; DIAG_t = os.time(); emf.log(line) end
  end
end
""")
old="function F.setup(k)\n  kit = k\n"
assert old in s
s=s.replace(old,old+"""  local last = 0
  pcall(emf.on_hit, function(world, hit)
    if hit.amount > 0 and hit.target < 1000 and os.time() ~= last then
      last = os.time()
      emf.log(string.format('DIAG hit kind %s target %s amount %s types %s attack %s instant %s killed %s hp %s -> %s', tostring(hit.kind),
        tostring(hit.target), tostring(hit.amount), table.concat(hit.types or {}, ','), tostring(hit.attack), tostring(hit.instant), tostring(hit.killed), tostring(hit.health_before), tostring(hit.health_after)))
    end
  end, { kinds = 'all' })
""")
open(dst,'w').write(s)
