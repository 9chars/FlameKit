-- usage: texlua tools/sntest/ai.lua flamekit/features/spawn_nodes.lua: (0.15.553) the 2026-11-23 test code is gone (no AI
-- log, no path census, no recordings, no path push) and the hunt order still goes out (was: the 0.15.527 AI log lines)
package.path = (arg[0]:match("(.*/)") or "./") .. "?.lua;" .. package.path
package.path = (arg[1]:match("(.*/)features/") or "./") .. "?.lua;" .. package.path  -- the real core/threat.lua
local M = require("mock")
package.preload["core.threat"] = nil
local F = dofile(arg[1])
F.setup(M.kit)
local W = M.world
local fails = 0
local function ok(c, what) if c then print("ok   " .. what) else fails = fails + 1 print("FAIL " .. what) end end
local function run(sec) for _ = 1, math.floor(sec * 60) do F.tick(W) M.advance(1 / 60) end end
emf.enemy_order = function() return 77 end
emf.enemy_order_cancel = function() end
M.player(1, 0, 0, 0)
run(0.2)
F._handle(W, "acc1", 1, { op = "new_group" }, {})
for k, v in pairs({ per_wave = 1, max_alive = 1, waves = 1, duration = 0, start_delay = 0 }) do F._handle(W, "acc1", 1, { op = "set", g = 1, key = k, value = v }, {}) end
M.ents[1].x = 20 F._handle(W, "acc1", 1, { op = "add_node", g = 1 }, {})
M.ents[1].x = 0
F._handle(W, "acc1", 1, { op = "start", g = 1 }, {})
run(4)  -- (0.15.543) the first monsters come after the start notice (3 s in the mock)
local id = nil for i, m in pairs(F._test_S.mon) do id = i end
M.ents[id].ai_state = 1
run(1)
M.ents[id].knows = 1
run(1)
M.ents[id].ai_state, M.ents[id].target = 6, 1
run(1)
run(11)
ok(not (M.ents[id].pf and M.ents[id].pf.queryPriority == 1), "path push is off")
M.ents[id].path = 1
M.ents[id].x = M.ents[id].x - 3
run(1)
local function has(p) return M.count(p) > 0 end
ok(not has("spawn nodes: ai"), "no AI log lines")
ok(not has("path census"), "no path census")
ok(not has("recording monster") and not has("fullrec"), "no full recordings")
ok(not has("path push"), "no path push")
ok(F._test_S.orders[id] and F._test_S.orders[id].id == 77, "the hunt order still goes out (order 77 at player 1)")
ok(M.count("ground teleport") >= 1 and M.count("ground move queued") == 0, "no ground teleport any more")
local rf = io.popen('ls ' .. emf.dir .. '/*spawn_nodes_rec_* 2>/dev/null; ls "' .. emf.dir .. '"\\spawn_nodes_rec_* 2>/dev/null'):read("a")
ok(rf == "", "no recording files")
ok(M.count("hunt_tick: ") == 0, "no errors")
print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
