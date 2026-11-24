-- reload in the middle of a raid; and the switched-off parts switched on (no errors)
package.path = (arg[0]:match("(.*/)") or "./") .. "?.lua;" .. package.path
package.path = (arg[1]:match("(.*/)features/") or "./") .. "?.lua;" .. package.path  -- the real core modules (0.15.532: core/fullrec.lua)
local M = require("mock")
package.preload["core.threat"] = package.preload["core.threat"]
emf.enemy_order = function() return 7 end
emf.enemy_order_cancel = function() end
local F = dofile(arg[1])
F.setup(M.kit)
local W = M.world
local fails = 0
local function ok(c, what) if c then print("ok   " .. what) else fails = fails + 1 print("FAIL " .. what) end end
local function run(sec) for _ = 1, math.floor(sec * 60) do F.tick(W) M.advance(1 / 60) end end
M.player(1, 0, 0, 0)
run(0.2)
F._handle(W, "acc1", 1, { op = "new_group" }, {})
for k, v in pairs({ per_wave = 3, max_alive = 2, waves = 2, wave_gap = 0, duration = 0, start_delay = 0 }) do F._handle(W, "acc1", 1, { op = "set", g = 1, key = k, value = v }, {}) end
M.ents[1].x = 10 F._handle(W, "acc1", 1, { op = "add_node", g = 1 }, {})
M.ents[1].x = 0
F._handle(W, "acc1", 1, { op = "start", g = 1 }, {})
run(12)  -- long enough for the stuck check (when on) to look at them
local dead_one = nil
for id, m in pairs(F._test_S.mon) do if not m.dead then dead_one = id M.ents[id].hp = 0 break end end
run(1)
local n_before = 0 for _, m in pairs(F._test_S.mon) do if not m.dead then n_before = n_before + 1 end end
-- reload: a fresh copy of the script, same world
local F2 = dofile(arg[1])
F2.setup(M.kit)
for _ = 1, 120 do F2.tick(W) M.advance(1 / 60) end
local S2 = F2._test_S
local n_after, own_after = 0, 0 for _, m in pairs(S2.mon) do if not m.dead then n_after = n_after + 1 if m.own then own_after = own_after + 1 end end end
ok(n_after == n_before and own_after == n_before, string.format("after a reload: the living tagged monsters are its own again (%d of %d)", own_after, n_before))
ok(dead_one and S2.old_bodies[dead_one] == 1, "after a reload: the body is put aside")
ok(S2.raid[1] ~= nil, "after a reload: the raid was taken back")
for _ = 1, 40 do
  for id, m in pairs(S2.mon) do if not m.dead and M.ents[id] then M.ents[id].hp = 0 end end
  for _ = 1, 60 do F2.tick(W) M.advance(1 / 60) end
end
for _ = 1, 1200 do F2.tick(W) M.advance(1 / 60) end
ok(S2.raid[1] == nil, "after a reload the raid still ends")
local err = 0 for _, l in ipairs(M.logs) do if l:find("tick: ", 1, true) or l:find("attempt to", 1, true) then err = err + 1 print("  " .. l) end end
ok(err == 0, "no errors in the log")
print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
