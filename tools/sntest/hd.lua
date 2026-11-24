-- (0.15.538) the animal hold: animal_hold_server.txt is "1 <time>" from the raid's start, rewritten while it runs,
-- "0" when it is over; never held past HOLD_MAX_S. usage: texlua tools/sntest/hd.lua flamekit/features/spawn_nodes.lua
package.path = (arg[0]:match("(.*/)") or "./") .. "?.lua;" .. package.path
package.path = (arg[1]:match("(.*/)features/") or "./") .. "?.lua;" .. package.path
local M = require("mock")
emf.enemy_order = function() return 7 end
emf.enemy_order_cancel = function() end
local F = dofile(arg[1])
F.setup(M.kit)
local W = M.world
local fails = 0
local function ok(c, what) if c then print("ok   " .. what) else fails = fails + 1 print("FAIL " .. what) end end
local function run(sec) for _ = 1, math.floor(sec * 60) do F.tick(W) M.advance(1 / 60) end end
local function file()
  local f = io.open(emf.dir .. "\\animal_hold_server.txt", "r")
  if not f then return nil end
  local t = f:read("*a") f:close() return t
end
local function stamp() local t = file() return t and tonumber(t:match("^1 (%d+)")) end
os.remove(emf.dir .. "\\animal_hold_server.txt")
M.player(1, 0, 0, 0)
run(2)
ok(file() == "0\n", "no raid at the start: the file says 0")
F._handle(W, "acc1", 1, { op = "new_group" }, {})
for k, v in pairs({ per_wave = 3, max_alive = 3, waves = 1, wave_gap = 0, duration = 0 }) do F._handle(W, "acc1", 1, { op = "set", g = 1, key = k, value = v }, {}) end
M.ents[1].x = 10 F._handle(W, "acc1", 1, { op = "add_node", g = 1 }, {})
M.ents[1].x = 0
F._handle(W, "acc1", 1, { op = "start", g = 1 }, {})
ok(stamp() ~= nil, "held the moment the raid starts (before its first tick)")
local s1 = stamp()
run(12)
local s2 = stamp()
ok(s2 and s2 > s1, string.format("rewritten while the raid runs (%s -> %s)", tostring(s1), tostring(s2)))
for _ = 1, 40 do
  for id, m in pairs(F._test_S.mon) do if not m.dead and M.ents[id] then M.ents[id].hp = 0 end end
  run(1)
end
run(25)
ok(F._test_S.raid[1] == nil and file() == "0\n", "the raid over: the file says 0 (the animals walk again)")
-- the time limit: a raid whose monster never dies is let go after 30 min, and not held again until it is over
F._handle(W, "acc1", 1, { op = "start", g = 1 }, {})
ok(stamp() ~= nil, "a second raid: held again")
for _ = 1, 31 * 6 do run(10) end
ok(file() == "0\n", "after 30 min the hold lets go even though the raid still has a monster alive")
run(30)
ok(file() == "0\n", "and stays let go")
local seen = {}
for _, l in ipairs(M.logs) do if l:find("animal hold", 1, true) then seen[#seen + 1] = l end end
for _, l in ipairs(seen) do print("  " .. l) end
local err = 0 for _, l in ipairs(M.logs) do if l:find("tick: ", 1, true) or l:find("attempt to", 1, true) or l:find("animal hold: .*:%d+:") then err = err + 1 print("  " .. l) end end
ok(err == 0, "no errors in the log")
print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
