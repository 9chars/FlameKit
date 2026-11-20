local file = arg[1]
local f = assert(io.open(file)) local text = f:read("a") f:close()
text = text:gsub("\nreturn F%s*$", "\nF._t = { fight_watch = fight_watch, scan = monster_scan_step, note = note_threat, drives = drives, name_of = name_of, roster = roster }\nreturn F\n")
local logs = {}
local emf = setmetatable({ log = function(s) logs[#logs+1] = s end, net = { send_to = function() end, channel = function() return true end },
  json = { encode = function() return "" end, decode = function() return {} end }, dir = "/tmp" }, { __index = function() return function() end end })
local env = setmetatable({ emf = emf, require = function(n) return setmetatable({}, { __index = function() return function() return {} end end }) end }, { __index = _G })
local F = assert(load(text, "=" .. file, "t", env))()
setmetatable(env, { __index = function(_, k) local v = _G[k] if v == nil then error("undefined global " .. k, 2) end return v end, __newindex = function(_, k) error("global write " .. k, 2) end })
local T = F._t
local pos = { [1] = {0,0,0}, [100] = {1,0,1}, [200] = {5,0,5}, [201] = {12,0,0}, [202] = {40,0,0} }
local comps = { [100] = { Health = { dataStorage = { 900, 3680 } }, DynamicEnemy01BehaviorState = {} },
  [200] = { DynamicEnemy01BehaviorState = {}, Faction = { faction = 10 }, NetworkHealth = { health = 300 } },
  [201] = { DynamicEnemy01BehaviorState = {}, Faction = { faction = 10 }, NetworkHealth = { health = 500 } },
  [202] = { DynamicEnemy01BehaviorState = {}, Faction = { faction = 10 }, NetworkHealth = { health = 500 } } }
local tick = 0
local W = { tick = function() return tick end, position = function(_, e) local p = pos[e] if p then return p[1], p[2], p[3] end end,
  get = function(_, c, e) return comps[e] and comps[e][c] end, entities = function() local l = {} for i = 1, 20000 do l[i] = 1000 + i end l[#l+1] = 200 l[#l+1] = 201 l[#l+1] = 202 return l end }
T.drives[100] = { player = 1, trail = {} }
T.name_of[100] = "N1"
T.roster.list = { { name = "N1", fight = "Defensive" } }
for _, mode in ipairs({ "Defensive", "Aggressive", "Passive" }) do
  T.roster.list[1].fight = mode
  if mode == "Defensive" then T.note(W, { attacker = 201, target = 1 }) end
  for i = 1, 200 do tick = tick + 1 T.scan(W) if tick % 60 == 0 then T.fight_watch(W) end end
end
pos[1] = {50, 0, 0}
tick = tick + 60 T.fight_watch(W)
for _, l in ipairs(logs) do print(l) end
