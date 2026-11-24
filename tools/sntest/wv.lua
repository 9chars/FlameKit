-- (0.15.542) "Next wave after": with 90% the next wave waits until at most 10% of the last wave is alive; with "It has
-- spawned" (0) it comes right after the Between waves time, as before. usage: texlua tools/sntest/wv.lua flamekit/features/spawn_nodes.lua
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
local S = F._test_S
local function alive() local n = 0 for id, m in pairs(S.mon) do if not m.dead and M.ents[id] and (M.ents[id].hp or 0) > 0 then n = n + 1 end end return n end
local function kill(k) for id, m in pairs(S.mon) do if k <= 0 then break end if not m.dead and M.ents[id] and M.ents[id].hp > 0 then M.ents[id].hp = 0 k = k - 1 end end end
M.player(1, 0, 0, 0)
run(0.2)
F._handle(W, "acc1", 1, { op = "new_group" }, {})
for k, v in pairs({ per_wave = 5, max_alive = 10, waves = 2, wave_gap = 5, duration = 0, start_delay = 0 }) do F._handle(W, "acc1", 1, { op = "set", g = 1, key = k, value = v }, {}) end
for k = 1, 2 do M.ents[1].x = 5 * k F._handle(W, "acc1", 1, { op = "add_node", g = 1 }, {}) end
M.ents[1].x = 0
ok(F._test_S and true, "set up")
-- 90 % (the default)
F._handle(W, "acc1", 1, { op = "start", g = 1 }, {})
run(10)
ok(alive() == 10 and S.runs[1] and S.runs[1].wave == 1 and S.runs[1].wait_dead == 10, "90%: wave 1 spawned 10 and waits for its dead (" .. alive() .. " alive, wave " .. tostring(S.runs[1] and S.runs[1].wave) .. ")")
run(30)
ok(S.runs[1] and S.runs[1].wave == 1, "90%: 30 s later, with all 10 alive, still wave 1")
kill(8) run(10)
ok(S.runs[1] and S.runs[1].wave == 1, "90%: 8 dead, 2 alive: still waiting (" .. alive() .. " alive)")
kill(1) run(3)
ok(S.runs[1] and S.runs[1].wave == 1 and not S.runs[1].wait_dead, "90%: 9 dead, 1 alive: Between waves (5 s) started")
run(4)
ok(S.runs[1] == nil or S.runs[1].wave == 2 or alive() > 1, "90%: 5 s later the final wave comes (" .. alive() .. " alive)")
kill(40) run(30)
-- 0 = as before
F._handle(W, "acc1", 1, { op = "set", g = 1, key = "wave_dead", value = 0 }, {})
F._handle(W, "acc1", 1, { op = "stop", g = 1 }, {})
F._handle(W, "acc1", 1, { op = "remove", g = 1 }, {})
run(5)
F._handle(W, "acc1", 1, { op = "start", g = 1 }, {})
run(12)
ok(alive() >= 15, "It has spawned: the second wave came with the first one alive (" .. alive() .. " alive)")
ok(F._handle(W, "acc1", 1, { op = "set", g = 1, key = "wave_dead", value = 33 }, {}) ~= nil and (S.data.groups["1"].wave_dead == 0), "a value not in the list is refused")
local err = 0 for _, l in ipairs(M.logs) do if l:find("tick: ", 1, true) or l:find("attempt to", 1, true) then err = err + 1 print("  " .. l) end end
ok(err == 0, "no errors in the log")
for _, l in ipairs(M.logs) do if l:find("dead", 1, true) and l:find("wave", 1, true) then print("  " .. l) end end
print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
