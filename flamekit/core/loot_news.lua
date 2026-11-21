-- core/loot_news.lua (0.15.399, owner 2026-11-21 15:05 "eliminate any scanning for loot drops, monster body loot,
-- chopping or axing... replace all that scanning with the DLL"): the new loose items and new containers of the server
-- world, as FlameKit's DLL reports them the moment the game makes them (flamekit_native/src/loot_news.cpp: the events
-- TestEvent1 = a loose item's entity id, TestEvent2 = a container's), so no feature walks the world's entities for loot.
-- EMF hands an engine event only to scripts that asked for it when the server started: the first start with this
-- version needs a server restart (as does the new DLL).
-- Shared core code (HANDOFF rule 0b): any feature may use it; it uses no feature.
--   news.setup()                         asks for the events (from a feature's setup; once is enough)
--   news.on_pickup(fn)                   fn(world, id, x, y, z, tick) for each new loose item
--   news.containers(x, z, r, since)      the new containers within r m of x, z since world tick `since` (ids)
--   news.LOG                             the first lines of each kind in emf_core.log (debug: kept, can be switched off)

local events = require("core.game_events")

local news = { LOG = true }
local pickup_fns = {}
local containers = {}  -- { id, x, z, tick }, the newest last, kept KEEP_TICKS
local KEEP_TICKS = 60 * 30
local said = { pickup = 0, container = 0 }
local asked = nil

local function where(world, id)
  local ok, x, y, z = pcall(world.position, world, id)
  if ok and x then return x, y, z end
  return nil
end

local function tick_of(world)
  local ok, t = pcall(world.tick, world)
  return ok and tonumber(t) or 0
end

local function id_of(e)
  local ok, v = pcall(function() return e.data end)
  return ok and tonumber(v) or nil
end

function news.setup()
  if asked ~= nil then return asked end
  local a = events.on("TestEvent1", function(world, e)
    local id = id_of(e)
    if not id then return end
    local x, y, z = where(world, id)
    if news.LOG and said.pickup < 20 then
      said.pickup = said.pickup + 1
      emf.log(string.format("loot news: new loose item %d at %s", id, x and string.format("%.1f %.1f %.1f", x, y, z) or "?"))
    end
    if not x then return end
    local t = tick_of(world)
    for _, fn in ipairs(pickup_fns) do
      local ok, err = pcall(fn, world, id, x, y, z, t)
      if not ok then emf.log("loot news: " .. tostring(err)) end
    end
  end)
  local b = events.on("TestEvent2", function(world, e)
    local id = id_of(e)
    if not id then return end
    local x, y, z = where(world, id)
    if news.LOG and said.container < 20 then
      said.container = said.container + 1
      emf.log(string.format("loot news: new container %d at %s", id, x and string.format("%.1f %.1f %.1f", x, y, z) or "?"))
    end
    if not x then return end
    local t = tick_of(world)
    containers[#containers + 1] = { id = id, x = x, z = z, tick = t }
    if #containers > 400 or (containers[1] and t - containers[1].tick > KEEP_TICKS) then
      local keep = {}
      for _, c in ipairs(containers) do if t - c.tick <= KEEP_TICKS then keep[#keep + 1] = c end end
      containers = keep
    end
  end)
  asked = a and b
  emf.log("loot news: events " .. (asked and "asked for" or "NOT there (the DLL's news cannot be heard: restart the server once)"))
  return asked
end

function news.on_pickup(fn) pickup_fns[#pickup_fns + 1] = fn end

function news.containers(x, z, r, since)
  local out = {}
  for _, c in ipairs(containers) do
    if c.tick >= (since or 0) and (c.x - x) ^ 2 + (c.z - z) ^ 2 <= r * r then out[#out + 1] = c.id end
  end
  return out
end

return news
