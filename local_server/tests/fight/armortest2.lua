local f = assert(io.open(arg[1])) local text = f:read("a") f:close()
text = text:gsub("\nreturn F%s*$", "\nF._a = match_armor F._r = roster\nreturn F\n")
local logs = {}
local emf = setmetatable({ log = function(s) logs[#logs+1] = s end, net = { send_to = function() end, channel = function() return true end }, json = { encode = function() return "" end, decode = function() return {} end }, save_world_data = function() return true end }, { __index = function() return function() end end })
local env = setmetatable({ emf = emf, require = function() return setmetatable({}, { __index = function() return function() return {} end end }) end }, { __index = _G })
local F = assert(load(text, "=x", "t", env))()
F._r.loaded = true
local hound = { 0, 1, 0.8, 0.6, 1.5, 0, 0, 0, 0, 1, 1, 1, 1, 0, 1, 1.2, 0.6, 0.8, 1 }
-- case 1: a body already armored by the 21:38 version
local live = {} for i, v in ipairs(hound) do live[i] = v / 3 end
local W = { get = function(_, c, e) if c == "DamageSusceptibility" then return { dataStorage = live } end end }
local r = { name = "N1" }
F._a(W, 100, r) F._a(W, 100, r)
-- case 2: a fresh body; then a reload (the same record r) does not scale twice
local live2 = {} for i, v in ipairs(hound) do live2[i] = v end
local W2 = { get = function(_, c, e) if c == "DamageSusceptibility" then return { dataStorage = live2 } end end }
local r2 = { name = "N2" }
F._a(W2, 101, r2) F._a(W2, 101, r2)
print(live[5], live2[5], r.sus_base[5], r2.sus_base[5])
for _, l in ipairs(logs) do print(l) end
