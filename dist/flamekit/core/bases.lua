-- core/bases.lua (0.15.233): where the players' bases are, for any feature that must know (first: Fast Dive keeps
-- its crater away from bases). Server world only. Read only.
--
-- A base is a flame altar entity with BaseIdComponent {baseId, buildZoneSize (float3), ...} and a CurrentTransform;
-- the game adds one build zone box per such entity every tick (EMF docs, engine_parts/world_building_daytime.md 3.5,
-- re_villages.md). EMF has no search by component, only world:entities() (some 37,000 on the production server), so
-- the list is made in the background: every REFRESH_S seconds a walk over all entities, at most SLICE_S of the clock
-- (or SLICE_MAX entities) per server step (EMF pauses FlameKit when one call runs over 250 ms).
-- (0.15.234) buildZoneSize read 0 x 0 x 0 for all eight bases on the local server (0.15.233 log), so the zone's size is
-- taken from the altar's TriggerShape (rangeX, rangeZ, an offset from the altar), which the game uses with it for the
-- build zone box. OPEN: whether a range is half the box's width (HALF_RANGE below, the likely reading) or all of it.

local M = {
  REFRESH_S = 120,
  SLICE_S = 0.02,
  SLICE_MAX = 3000,
  HALF_RANGE = true, -- true: a TriggerShape range reaches that far from the centre (half the box's width)
  list = {},        -- { x, z (the box's centre), hx, hz (how far it reaches), ax, ay, az (the altar) } per base
  broken = false,
}

local walk = nil    -- { ids, i, found } while a walk is under way
local next_walk = 0 -- os.time() of the next walk
local said = {}     -- base position key -> true once logged

local clock_ok, clock = pcall(function() return os.clock end)
if not (clock_ok and type(clock) == "function" and pcall(clock)) then clock = nil end

function M.tick(world)
  if M.broken or not world:is_server() then return end
  local ok, err = pcall(function()
    if not walk then
      if os.time() < next_walk then return end
      walk = { ids = world:entities(), i = 1, found = {} }
    end
    local t0, done = clock and clock() or 0, 0
    local ids = walk.ids
    while walk.i <= #ids do
      local id = ids[walk.i]
      walk.i = walk.i + 1
      done = done + 1
      local b = world:get("BaseIdComponent", id)
      if b then
        local x, y, z = world:position(id)
        local ts = world:get("TriggerShape", id)
        if x then
          local rx = ts and tonumber(ts.rangeX) or 0
          local rz = ts and tonumber(ts.rangeZ) or 0
          local ox, oz = 0, 0
          pcall(function()  -- Offset {localOffset, worldOffset, orientationOffset}: the world offset (the box is axis aligned)
            ox = (tonumber(ts.offset.worldOffset.x) or 0) + (tonumber(ts.offset.localOffset.x) or 0)
            oz = (tonumber(ts.offset.worldOffset.z) or 0) + (tonumber(ts.offset.localOffset.z) or 0)
          end)
          local f = M.HALF_RANGE and 1 or 0.5
          local e = { x = x + ox, z = z + oz, hx = rx * f, hz = rz * f, ax = x, ay = y, az = z }
          walk.found[#walk.found + 1] = e
          local key = string.format("%.0f,%.0f", x, z)
          if not said[key] then
            said[key] = true
            local bz = b.buildZoneSize
            emf.log(string.format("bases: a base at %.1f %.1f %.1f: trigger shape %s range %.1f x %.1f x %.1f, offset %.1f %.1f; buildZoneSize %.1f x %.1f x %.1f",
              x, y, z, ts and tostring(ts.shape) or "none", rx, ts and tonumber(ts.rangeY) or 0, rz, ox, oz,
              tonumber(bz.x) or 0, tonumber(bz.y) or 0, tonumber(bz.z) or 0))
          end
        end
      end
      if done >= M.SLICE_MAX or (clock and clock() - t0 > M.SLICE_S) then return end
    end
    M.list = walk.found
    walk = nil
    next_walk = os.time() + M.REFRESH_S
  end)
  if not ok then
    M.broken = true
    walk = nil
    emf.log("bases: the bases cannot be found on this game version (" .. tostring(err) .. ")")
  end
end

-- the base whose build zone (plus `margin` metres around it) holds the point x, z; nil when none
function M.near(x, z, margin)
  margin = margin or 0
  for _, b in ipairs(M.list) do
    if b.hx > 0 and math.abs(x - b.x) <= b.hx + margin and math.abs(z - b.z) <= b.hz + margin then return b end
  end
  return nil
end

return M
