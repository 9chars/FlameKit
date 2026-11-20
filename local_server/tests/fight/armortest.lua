local f = assert(io.open(arg[1])) local text = f:read("a") f:close()
text = text:gsub("\nreturn F%s*$", "\nF._a = match_armor\nreturn F\n")
local logs = {}
local emf = setmetatable({ log = function(s) logs[#logs+1] = s end, net = { send_to = function() end, channel = function() return true end }, json = { encode = function() return "" end, decode = function() return {} end } }, { __index = function() return function() end end })
local env = setmetatable({ emf = emf, require = function() return setmetatable({}, { __index = function() return function() return {} end end }) end }, { __index = _G })
local F = assert(load(text, "=x", "t", env))()
local base = { 0, 1, 0.8, 0.6, 1.5, 0, 0, 0, 0, 1, 1, 1, 1, 0, 1, 1.2, 0.6, 0.8, 1 }
local live = {} for i, v in ipairs(base) do live[i] = v end
local W = { get = function(_, c, e) if c == "DamageSusceptibility" then return { dataStorage = live } end end,
  template = function(_, c, e) if NOTPL then error("no template") end return { dataStorage = base } end }
F._a(W, 100, { name = "N1" })
F._a(W, 100, { name = "N1" })          -- again: nothing to do
for i = 1, 19 do live[i] = base[i] end   -- the game sets them back
F._a(W, 100, { name = "N1" })
for _, l in ipairs(logs) do print(l) end
