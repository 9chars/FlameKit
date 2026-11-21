-- features/companions/02_fullrec.lua: part 2 of the companion code (the server side), split from npc_probe.lua in 0.15.362
-- (owner 2026-11-20 18:11). The parts run in order in ONE shared environment (features/companions.lua): what was a
-- top-level local is a name in that environment, seen by every part.
-- ===== The full recorder (logging all of an entity's data) ===========================================================
-- Every component an entity has (found once by trying every component name), every plain field of each (the generated
-- list in npc_fields.lua), every half second, into its own file beside the mod (fullrec_<entity>.txt): a full snapshot
-- first, then only the fields that changed, each line with the tick and the clock. FlameKit's own writes and decisions
-- go into the same file as EVENT lines (fullrec_event), so cause and effect line up.
FIELDS = (function() local ok, f = pcall(require, "features.npc_fields") return ok and f or {} end)()
fullrecs = {}  -- entity -> { file, untill, next, comps = {names}, last = {}, n }
function fr_val(v)
  if type(v) == "number" then
    if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format("%d", v) end
    return string.format("%.4f", v)
  end
  return tostring(v)
end
function fr_read(c, path)
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
function fr_write(r, text)
  if not r.file then return end
  r.file:write(text, "\n")
end
function fr_stamp(world) return string.format("t=%d %s", world:tick(), os.date and os.date("%H:%M:%S") or "") end
function fullrec_event(world, id, text)  -- called from every part of the probe below
  local r = fullrecs[id]
  if r then fr_write(r, fr_stamp(world) .. " EVENT " .. text) end
end
function fullrec_start(world, id, secs)
  if fullrecs[id] and fullrecs[id].file then pcall(function() fullrecs[id].file:close() end) end
  local f = io.open(emf.dir .. "\\fullrec_" .. tostring(id) .. "_" .. (os.date and os.date("%H%M%S") or tostring(world:tick())) .. ".txt", "w")  -- one file per recording
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
function fullrec_step(world, id, r)
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

