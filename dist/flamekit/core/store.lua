-- core/store.lua: a feature's own data as a JSON file in the mod's folder (kept for every world and character).
-- store.load("junk_list", {}) / store.save("junk_list", value). The files end in .json: saving a .lua file would
-- reload the mod.

local store = {}

local function path(name)
  return emf.dir .. "\\" .. name .. ".json"
end

-- The saved table, or `default` when there is none yet or it cannot be read (a file that cannot be read is kept as
-- <name>.bad.json, so a typo made by hand is never overwritten).
function store.load(name, default)
  local f = io.open(path(name), "r")
  if not f then return default end
  local text = f:read("a") or ""
  f:close()
  text = text:gsub("^\239\187\191", "")  -- Notepad's byte order mark
  local value, err = emf.json.decode(text)
  if type(value) ~= "table" then
    emf.log(name .. ".json could not be read (" .. tostring(err) .. "): kept as " .. name .. ".bad.json")
    local bad = io.open(emf.dir .. "\\" .. name .. ".bad.json", "w")
    if bad then
      bad:write(text)
      bad:close()
    end
    return default
  end
  return value
end

function store.save(name, value)
  local text, err = emf.json.encode(value)
  if not text then
    emf.log(name .. ".json was not saved: " .. tostring(err))
    return false
  end
  local f, why = io.open(path(name), "w")
  if not f then
    emf.log(name .. ".json was not saved: " .. tostring(why))
    return false
  end
  f:write(text)
  f:close()
  return true
end

return store
