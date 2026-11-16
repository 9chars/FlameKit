-- core/server_settings.lua: the settings that are the same for the whole server and every player on it (the Server
-- tab, features/server_tab.lua, shows and changes them; any feature may read them). Kept where the world is hosted,
-- in server_settings.json beside FlameKit (it survives restarts). Shared core code (HANDOFF rule 0b).

local store = require("core.store")

local S = {}

-- every server setting: key -> { default, label, tooltip }, in the order the Server tab shows them
S.LIST = {
  { key = "loot_to_ground", default = false, label = "Monsters drop their loot on the ground",
    tooltip = "Every monster that dies drops its loot on the ground beside it (the same items, quality and level), so "
      .. "nobody has to press E on the body. Bodies go 8 s after death, a boss's after 45 s." },
}
local by_key = {}
for _, s in ipairs(S.LIST) do by_key[s.key] = s end

local values = nil

local function load()
  if values then return end
  values = store.load("server_settings", {})
  if type(values) ~= "table" then values = {} end
end

function S.get(key)
  load()
  local v = values[key]
  if v == nil and by_key[key] then return by_key[key].default end
  return v
end

-- Changes one (only a known key, only the type its default has). True when it changed.
function S.set(key, value)
  load()
  local s = by_key[key]
  if not s or type(value) ~= type(s.default) then return false end
  if S.get(key) == value then return false end
  values[key] = value
  store.save("server_settings", values)
  return true
end

-- all of them as key -> value (for sending to players)
function S.all()
  local out = {}
  for _, s in ipairs(S.LIST) do out[s.key] = S.get(s.key) end
  return out
end

return S
