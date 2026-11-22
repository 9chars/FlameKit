-- core/test_tag.lua (0.15.156): FlameKit's test monsters are spawned with a ScaleComponent of SCALE (0.1% smaller than
-- normal: not visible), so any feature can tell them apart from the game's own monsters without reading another
-- feature's data (HANDOFF rule 0b). Shared core code: it uses no feature.
local M = {}
M.SCALE = 0.999
-- Whether entity `id` is one of FlameKit's test monsters (its ScaleComponent is SCALE).
function M.is(world, id)
  local ok, sc = pcall(world.get, world, "ScaleComponent", id)
  return ok and sc ~= nil and sc.uniformScale ~= nil and math.abs(sc.uniformScale - M.SCALE) < 0.0003
end
return M
