-- (0.15.544) the countdown "N of TOTAL monsters left to kill" changes within 0.5 s of a death, and shows "0 of TOTAL"
-- right after the last kill (not the last number until the end notice). usage: texlua tools/sntest/ct.lua flamekit/features/spawn_nodes.lua
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
local function living() local t = {} for id, m in pairs(S.mon) do if not m.dead and M.ents[id] and (M.ents[id].hp or 0) > 0 then t[#t + 1] = id end end return t end
M.player(1, 0, 0, 0)
run(0.2)
F._handle(W, "acc1", 1, { op = "new_group" }, {})
for k, v in pairs({ per_wave = 3, max_alive = 3, waves = 1, wave_gap = 0, duration = 0, start_delay = 0 }) do F._handle(W, "acc1", 1, { op = "set", g = 1, key = k, value = v }, {}) end
for k = 1, 2 do M.ents[1].x = 5 * k F._handle(W, "acc1", 1, { op = "add_node", g = 1 }, {}) end
M.ents[1].x = 0
F._handle(W, "acc1", 1, { op = "start", g = 1 }, {})
run(6)
ok(M.last_left() and M.last_left():find("6 of 6", 1, true), "starts at 6 of 6: " .. tostring(M.last_left()))
local l = living()
M.ents[l[1]].hp = 0
run(0.6)
ok(M.last_left() and M.last_left():find("5 of 6", 1, true), "0.6 s after a kill: 5 of 6 (" .. tostring(M.last_left()) .. ")")
M.ents[l[2]].hp = 0 run(0.6)
M.ents[l[3]].hp = 0 run(0.6)
ok(M.last_left() and M.last_left():find("3 of 6", 1, true), "two more kills 0.6 s apart: 3 of 6 (" .. tostring(M.last_left()) .. ")")
for _, id in ipairs(living()) do M.ents[id].hp = 0 end
run(0.8)
ok(M.last_left() and M.last_left():find("0 of 6", 1, true), "0.8 s after the last kill: 0 of 6 (" .. tostring(M.last_left()) .. ")")
run(15)
ok(S.raid[1] == nil, "and the raid ends after its 10 s wait")
local clear = false for _, n in ipairs(M.notices) do if n:find('"snd":"raid_all_clear"', 1, true) and n:find("is over", 1, true) then clear = true end end
ok(clear, "(0.15.549) the raid-over notice comes with the all-clear sound")
local err = 0 for _, ln in ipairs(M.logs) do if ln:find("tick: ", 1, true) or ln:find("attempt to", 1, true) then err = err + 1 print("  " .. ln) end end
ok(err == 0, "no errors in the log")
print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
