-- features/build_anywhere.lua: Free build's debug log (nothing in the game changes). Logs, on change, the cursor flag
-- words (ClientCursor in the player's own game, ServerCursor on the server: primaryFlags / secondaryFlags, with the
-- player's position) and the server's view of the building tool (NetworkCursor currentBuildingItemId, cursorEntityId,
-- serverFlags; ServerCursor cursorEntityId and building item). At most LOG_MAX lines a minute; LOG switches it off.
-- Free build itself: features/experimental.lua and FlameKit Native (build_anywhere.cpp).
-- Uses only core modules (HANDOFF rule 0b).

local players = require("core.players")

local F = { id = "build_anywhere", title = "Build Anywhere" }
local kit

local LOG, LOG_MAX = true, 200   -- changes logged per minute at most
local said, steps = 0, 0
local last = {}                  -- "<side>:<id>" -> "<primary>/<secondary>"

local function get(world, c, id)
  local ok, v = pcall(world.get, world, c, id)
  return ok and v or nil
end

local function field(v, k)
  local ok, x = pcall(function() return v[k] end)
  return ok and x or nil
end

local function bits(n)
  n = math.floor(tonumber(n) or 0)
  local on = {}
  for b = 0, 31 do if (n >> b) & 1 == 1 then on[#on + 1] = tostring(b) end end
  return string.format("0x%08X [%s]", n, table.concat(on, ","))
end

local function look(world, side, comp, id)
  local c = get(world, comp, id)
  if not c then return end
  local p, s = tonumber(field(c, "primaryFlags")) or 0, tonumber(field(c, "secondaryFlags")) or 0
  local key = side .. ":" .. id
  local v = p .. "/" .. s
  if last[key] == v then return end
  last[key] = v
  if not LOG or said >= LOG_MAX then return end
  said = said + 1
  local x, y, z = world:position(id)
  emf.log(string.format("build anywhere: %s %s of %d: primary %s, secondary %s at %.1f %.1f %.1f", side, comp, id,
    bits(p), bits(s), x or 0, y or 0, z or 0))
end

-- the server's own view of the building tool, logged when it changes: NetworkCursor.currentBuildingItemId and
-- .cursorEntityId, ServerCursor.cursorEntityId and the building item.
local tool_last = {}
local function val(v)
  if type(v) == "userdata" or type(v) == "table" then
    local okv, x = pcall(function() return v.value end)
    if okv and x ~= nil then return tostring(x) end
    local okh, h = pcall(function() return v.hash end)
    if okh and h ~= nil then return tostring(h) end
  end
  return tostring(v)
end
local function look_tool(world, id)
  local parts = {}
  local nc = get(world, "NetworkCursor", id)
  if nc then
    parts[#parts + 1] = "net item " .. val(field(nc, "currentBuildingItemId"))
    parts[#parts + 1] = "net cursor " .. val(field(nc, "cursorEntityId"))
    parts[#parts + 1] = "net flags " .. val(field(nc, "serverFlags"))
  else
    parts[#parts + 1] = "no NetworkCursor"
  end
  local sc = get(world, "ServerCursor", id)
  if sc then
    parts[#parts + 1] = "server cursor " .. val(field(sc, "cursorEntityId"))
    local ci = field(sc, "currentBuildingItemInstance")
    parts[#parts + 1] = "server item " .. (ci and val(field(ci, "itemId")) or "nil")
  end
  local line = table.concat(parts, ", ")
  if tool_last[id] == line then return end
  tool_last[id] = line
  if said >= LOG_MAX then return end
  said = said + 1
  emf.log(string.format("build anywhere: tool signals of %d: %s", id, line))
end

function F.tick(world)  -- the server
  steps = steps + 1
  if steps % 3600 == 0 then said = 0 end
  if not LOG or steps % 2 ~= 0 then return end
  for _, id in ipairs(players.ids(world)) do
    look(world, "server", "ServerCursor", id)
    pcall(look_tool, world, id)
  end
end

local csteps = 0
function F.client_tick(world)  -- the player's own game
  csteps = csteps + 1
  if csteps % 3600 == 0 then said = 0 end
  if not LOG or csteps % 2 ~= 0 then return end
  local me = emf.local_player()
  if me and me ~= 0 then look(world, "client", "ClientCursor", me) end
end

function F.setup(k)
  kit = k
  if LOG then emf.log("build anywhere: Free build debug log on (cursor flags, building tool; nothing in the game changes)") end
end

return F
