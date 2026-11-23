-- core/loot_news.lua (0.15.399, owner 2026-11-21 15:05 "eliminate any scanning for loot drops, monster body loot,
-- chopping or axing... replace all that scanning with the DLL"): the new loose items and new containers of the server
-- world, as FlameKit's DLL reports them the moment the game makes them (flamekit_native/src/loot_news.cpp), so no
-- feature walks the world's entities for loot. The DLL writes loot_news.txt beside this mod after each server step that
-- brought news: lines "<number> <p|c> <entity> <tick>" (p a loose item, c a container; tick: the server step that made
-- it), the numbers counting up. This module
-- reads it only while someone waits for news (a drop after a kill or a chop, a loot pile after a death), at most every
-- READ_EVERY steps, and hands on the lines it has not seen. (0.15.399 first try, 15:15: the DLL sent them as events;
-- EMF delivers no 4-byte event to Lua.)
-- Shared core code (HANDOFF rule 0b): any feature may use it; it uses no feature.
--   news.setup()                         nothing to ask for any more (kept for the callers)
--   news.tick(world, waiting, now)       each server step: reads the file when `waiting` (or to learn where it stands);
--                                        `now`: at once, not waiting for READ_EVERY
--   news.on_pickup(fn)                   fn(world, id, x, y, z, tick) for each new loose item (tick: when it was made)
--   news.containers(x, z, r, since)      the new containers within r m of x, z since world tick `since` (ids)
--   news.LOG                             the first lines of each kind in emf_core.log (debug: kept, can be switched off)

local news = { LOG = true }
local pickup_fns = {}
local containers = {}  -- { id, x, z, tick }, the newest last, kept KEEP_TICKS
local KEEP_TICKS = 60 * 30
local READ_EVERY = 6   -- steps (a tenth of a second)
local said = { p = 0, c = 0 }
local last_n = nil     -- the newest number handed on (nil: not read yet: the lines there then are old)
local last_read = -1000

-- Where entity `id` is (x, y, z), or nil when it is gone.
local function where(world, id)
  local ok, x, y, z = pcall(world.position, world, id)
  if ok and x then return x, y, z end
  return nil
end

-- The world's step count (0 when it cannot be read).
local function tick_of(world)
  local ok, t = pcall(world.tick, world)
  return ok and tonumber(t) or 0
end

-- One line of news: a loose item ("p") goes to every on_pickup function; a container ("c") is kept for news.containers (KEEP_TICKS, at most 400).
local function handle(world, kind, id, t)
  local x, y, z = where(world, id)
  if news.LOG and said[kind] < 20 then
    said[kind] = said[kind] + 1
    emf.log(string.format("loot news: new %s %d at %s", kind == "p" and "loose item" or "container", id,
      x and string.format("%.1f %.1f %.1f", x, y, z) or "? (gone)"))
  end
  if not x then return end
  if kind == "p" then
    for _, fn in ipairs(pickup_fns) do
      local ok, err = pcall(fn, world, id, x, y, z, t)
      if not ok then emf.log("loot news: " .. tostring(err)) end
    end
  else
    containers[#containers + 1] = { id = id, x = x, z = z, tick = t }
    if #containers > 400 or t - containers[1].tick > KEEP_TICKS then
      local keep = {}
      for _, c in ipairs(containers) do if t - c.tick <= KEEP_TICKS then keep[#keep + 1] = c end end
      containers = keep
    end
  end
end

-- Reads loot_news.txt (written by FlameKit Native) and handles the lines not seen yet.
local function read(world, t)
  local f = io.open(emf.dir .. "\\loot_news.txt", "rb")
  if not f then return end
  local text = f:read("a")
  f:close()
  local newest = 0
  local fresh = {}
  for n, kind, id, made in (text or ""):gmatch("(%d+) ([pc]) (%d+) (%d+)") do
    n = tonumber(n)
    if n > newest then newest = n end
    if last_n and n > last_n then fresh[#fresh + 1] = { n, kind, tonumber(id), tonumber(made) } end
  end
  if last_n and newest < last_n then  -- the DLL started again (the server restarted): its numbers too
    last_n = newest
    return
  end
  if not last_n then last_n = newest return end
  table.sort(fresh, function(a, b) return a[1] < b[1] end)
  for _, e in ipairs(fresh) do handle(world, e[2], e[3], e[4] or t) end
  if newest > last_n then last_n = newest end
end

-- Every server step: reads the news every READ_EVERY steps while a feature waits for loot (`waiting`), at once with `now`.
function news.tick(world, waiting, now)
  if last_n ~= nil and not waiting then return end
  local t = tick_of(world)
  if t - last_read < READ_EVERY and not now then return end
  last_read = t
  local ok, err = pcall(read, world, t)
  if not ok then emf.log("loot news: " .. tostring(err)) end
end

-- Nothing to set up (the news comes from FlameKit Native); kept so features can call it.
function news.setup() return true end

-- Registers fn(world, id, x, y, z, tick), called for every new loose item.
function news.on_pickup(fn) pickup_fns[#pickup_fns + 1] = fn end

-- The new containers (loot piles) within r m of x, z made since step `since`.
function news.containers(x, z, r, since)
  local out = {}
  for _, c in ipairs(containers) do
    if c.tick >= (since or 0) and (c.x - x) ^ 2 + (c.z - z) ^ 2 <= r * r then out[#out + 1] = c.id end
  end
  return out
end

return news
