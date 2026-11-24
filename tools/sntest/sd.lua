-- (0.15.543) "First monsters after": no monster before the start notice + that time (10 s default); 0: right after the
-- notice; the start siren is the single one. usage: texlua tools/sntest/sd.lua flamekit/features/spawn_nodes.lua
package.path = (arg[0]:match("(.*/)") or "./") .. "?.lua;" .. package.path
package.path = (arg[1]:match("(.*/)features/") or "./") .. "?.lua;" .. package.path
local M = require("mock")
emf.enemy_order = function() return 7 end
emf.enemy_order_cancel = function() end
local sent = {}
local send_to = emf.net.send_to
emf.net.send_to = function(w, p, ch, text) sent[#sent + 1] = text if send_to then return send_to(w, p, ch, text) end return true end
local F = dofile(arg[1])
F.setup(M.kit)
local W = M.world
local fails = 0
local function ok(c, what) if c then print("ok   " .. what) else fails = fails + 1 print("FAIL " .. what) end end
local function run(sec) for _ = 1, math.floor(sec * 60) do F.tick(W) M.advance(1 / 60) end end
local S = F._test_S
local function alive() local n = 0 for _, m in pairs(S.mon) do if not m.dead then n = n + 1 end end return n end
M.player(1, 0, 0, 0)
run(0.2)
F._handle(W, "acc1", 1, { op = "new_group" }, {})
for k, v in pairs({ per_wave = 2, max_alive = 3, waves = 1, wave_gap = 0, duration = 0 }) do F._handle(W, "acc1", 1, { op = "set", g = 1, key = k, value = v }, {}) end
M.ents[1].x = 5 F._handle(W, "acc1", 1, { op = "add_node", g = 1 }, {}) M.ents[1].x = 0
ok(S.data.groups["1"].start_delay == nil or S.data.groups["1"].start_delay == 10, "default: 10 s")
F._handle(W, "acc1", 1, { op = "start", g = 1 }, {})
run(4)  -- the place answer never comes in the mock: the notice goes after PLACE_WAIT (3 s)
local notice_seen = false for _, l in ipairs(M.logs) do if l:find("first monsters come in 10 s", 1, true) then notice_seen = true end end
ok(notice_seen, "the start notice went out and said when")
ok(alive() == 0, "4 s after the start: no monster yet (" .. alive() .. ")")
run(8)
ok(alive() == 0, "12 s after the start (9 s after the notice): still none (" .. alive() .. ")")
run(3)
ok(alive() > 0, "after the notice + 10 s the monsters come (" .. alive() .. ")")
local twice, once = 0, 0
for _, t in ipairs(sent) do if t:find('"raid_siren_twice"', 1, true) then twice = twice + 1 elseif t:find('"raid_siren"', 1, true) then once = once + 1 end end
for _, l in ipairs(M.logs) do end
ok(twice == 0, "the start siren is no longer the double one (" .. twice .. " double, " .. once .. " single)")
-- 0 s
for _ = 1, 20 do for id, m in pairs(S.mon) do if not m.dead and M.ents[id] then M.ents[id].hp = 0 end end run(1) end
run(30)
F._handle(W, "acc1", 1, { op = "set", g = 1, key = "start_delay", value = 0 }, {})
F._handle(W, "acc1", 1, { op = "set", g = 1, key = "cooldown", value = 1 }, {})
F._handle(W, "acc1", 1, { op = "start", g = 1 }, {})
run(4.5)
ok(alive() > 0, "0 s: the monsters come right after the notice (" .. alive() .. ")")
local err = 0 for _, l in ipairs(M.logs) do if l:find("tick: ", 1, true) or l:find("attempt to", 1, true) then err = err + 1 print("  " .. l) end end
ok(err == 0, "no errors in the log")
print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
