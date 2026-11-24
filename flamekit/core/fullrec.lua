-- core/fullrec.lua (0.15.532): the full recorder as a shared module (HANDOFF rule 0b), first for Spawn Nodes' raid
-- monsters (owner 2026-11-23 20:42 "theres a long delay before monsters move in on me, there had to be a way to find out
-- what the delay is"). The same way as the companions' recorder (features/companions/02_fullrec.lua, which still has its
-- own copy: rule 0b debt, not moved unasked): every component the entity has (found once by trying every component name
-- of the generated list features/npc_fields.lua, names only), every plain field of each, every half second, into its own
-- file beside the mod: a full snapshot first, then only the fields that changed, each line with the step, the clock and
-- the entity's age. The caller's own events (M.event) go into the same file, so cause and effect line up. Read only.

local M = {}
local FIELDS = (function() local ok, f = pcall(require, "features.npc_fields") return ok and type(f) == "table" and f or {} end)()
local recs = {}  -- entity -> { file, until_tick, comps, last, n, born }

local function val(v)
  if type(v) == "number" then
    if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format("%d", v) end
    return string.format("%.4f", v)
  end
  return tostring(v)
end

-- The value at `path` ("a.b.c"; "#" at the end: an array's length and first 8 values) of component `c`, as text.
local function read(c, path)
  local arr = path:sub(-1) == "#"
  if arr then path = path:sub(1, -2) end
  local v = c
  for seg in path:gmatch("[^.]+") do v = v[seg] end
  if arr then
    local parts = { "#" .. tostring(#v) }
    for i = 1, math.min(#v, 8) do parts[#parts + 1] = val(type(v[i]) == "table" and "{}" or v[i]) end
    return table.concat(parts, " ")
  end
  return val(v)
end

local function stamp(world, r)
  local okt, t = pcall(world.tick, world)
  return string.format("t=%s %s age=%ds", okt and tostring(t) or "?", os.date and os.date("%H:%M:%S") or "", os.time() - r.born)
end

local function write(r, text)
  if r.file then r.file:write(text, "\n") end
end

-- Whether entity `id` is being recorded.
function M.on(id) return recs[id] ~= nil end

-- How many recordings run.
function M.count()
  local n = 0
  for _ in pairs(recs) do n = n + 1 end
  return n
end

-- Starts recording entity `id` for `secs` seconds into emf.dir\<prefix>_<id>_<time>.txt; `head`: a first line of the
-- caller's (what it is). Returns the file name or nil.
function M.start(world, id, secs, prefix, head)
  if recs[id] then return nil end
  local name = string.format("%s_%s_%s.txt", prefix, tostring(id), os.date and os.date("%H%M%S") or tostring(os.time()))
  local f = io.open(emf.dir .. "\\" .. name, "w")
  if not f then return nil end
  local comps = {}
  for cname in pairs(FIELDS) do
    local ok, c = pcall(world.get, world, cname, id)
    if ok and c then comps[#comps + 1] = cname end
  end
  table.sort(comps)
  local okt, t = pcall(world.tick, world)
  local r = { file = f, until_tick = (okt and t or 0) + secs * 60, comps = comps, last = {}, n = 0, born = os.time() }
  recs[id] = r
  write(r, string.format("%s START entity %s%s, %d components: %s", stamp(world, r), tostring(id), head and (" (" .. head .. ")") or "",
    #comps, table.concat(comps, ", ")))
  return name
end

-- An event line of the caller's in entity `id`'s recording (nothing when it is not recorded).
function M.event(world, id, text)
  local r = recs[id]
  if r then write(r, stamp(world, r) .. " EVENT " .. text) end
end

local function stop(id, why)
  local r = recs[id]
  if not r then return end
  write(r, "END " .. why)
  pcall(function() r.file:close() end)
  recs[id] = nil
end
M.stop = stop

-- One recording step for every entity recorded (the caller calls it every half second): the fields that changed, the
-- components that went; a recording ends after its time, or when the entity is gone.
function M.tick(world)
  local okt, now = pcall(world.tick, world)
  for id, r in pairs(recs) do
    local okp, px = pcall(world.position, world, id)
    if not (okp and px) then
      stop(id, "the entity is gone")
    elseif okt and now >= r.until_tick then
      stop(id, "its time is up")
    else
      local out = {}
      for _, cname in ipairs(r.comps) do
        local ok, c = pcall(world.get, world, cname, id)
        if ok and c then
          for _, path in ipairs(FIELDS[cname]) do
            local okv, v = pcall(read, c, path)
            local key = cname .. "." .. path
            v = okv and v or "?"
            if r.last[key] ~= v then
              r.last[key] = v
              out[#out + 1] = key .. "=" .. v
            end
          end
        elseif r.last[cname] ~= "gone" then
          r.last[cname] = "gone"
          out[#out + 1] = cname .. " GONE"
        end
      end
      r.n = r.n + 1
      if #out > 0 then write(r, stamp(world, r) .. " " .. table.concat(out, " | ")) end
      if r.n % 10 == 0 then pcall(function() r.file:flush() end) end
    end
  end
end

-- Ends every recording (a reload or a new world).
function M.stop_all(why)
  for id in pairs(recs) do stop(id, why or "stopped") end
end

return M
