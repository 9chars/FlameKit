-- (0.15.547) a group's cooldown survives a reload of the script (it is kept with the group): a "Base raid" / timer
-- trigger does not fire again at once after a reload. usage: texlua tools/sntest/cd.lua flamekit/features/spawn_nodes.lua
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
local function run(f, sec) for _ = 1, math.floor(sec * 60) do f.tick(W) M.advance(1 / 60) end end
M.player(1, 0, 0, 0)
run(F, 0.2)
F._handle(W, "acc1", 1, { op = "new_group" }, {})
for k, v in pairs({ per_wave = 1, max_alive = 1, waves = 1, duration = 0, start_delay = 0, cooldown = 10 }) do F._handle(W, "acc1", 1, { op = "set", g = 1, key = k, value = v }, {}) end
M.ents[1].x = 5 F._handle(W, "acc1", 1, { op = "add_node", g = 1 }, {}) M.ents[1].x = 0
F._handle(W, "acc1", 1, { op = "start", g = 1 }, {})
run(F, 4)
F._handle(W, "acc1", 1, { op = "stop", g = 1 }, {})
run(F, 1)
local ended = F._test_S.last_end[1]
ok(ended ~= nil, "Stop started the cooldown")
local F2 = dofile(arg[1])
F2.setup(M.kit)
run(F2, 3)
ok(F2._test_S.last_end[1] == ended, "after a reload the cooldown is still there (" .. tostring(F2._test_S.last_end[1]) .. ")")
print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
