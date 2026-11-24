-- (0.15.541) Raid monster markers with EMF's limit (07:52: ~39 marker messages per step, the rest answer 0): a big
-- raid's markers all go up, never more than 30 messages per check, and after Remove every one comes off the screen.
-- usage: texlua tools/sntest/mk.lua flamekit/features/spawn_nodes.lua
package.path = (arg[0]:match("(.*/)") or "./") .. "?.lua;" .. package.path
package.path = (arg[1]:match("(.*/)features/") or "./") .. "?.lua;" .. package.path
local M = require("mock")
emf.enemy_order = function() return 7 end
emf.enemy_order_cancel = function() end
local screen, step_calls, most = {}, 0, 0
local function room() step_calls = step_calls + 1 most = math.max(most, step_calls) return step_calls <= (tonumber(os.getenv("EMF_LIMIT")) or 39) end
emf.send_marker = function(p, id, spec) if not room() then return 0 end screen[id] = true return 1 end
emf.unsend_marker = function(p, id) if not room() then return 0 end local was = screen[id] screen[id] = nil return was and 1 or 0 end
local F = dofile(arg[1])
F.setup(M.kit)
local W = M.world
local fails = 0
local function ok(c, what) if c then print("ok   " .. what) else fails = fails + 1 print("FAIL " .. what) end end
local function run(sec) for _ = 1, math.floor(sec * 60) do step_calls = 0 F.tick(W) M.advance(1 / 60) end end
local function on_screen() local n = 0 for _ in pairs(screen) do n = n + 1 end return n end
M.player(1, 0, 0, 0)
run(0.2)
F._handle(W, "acc1", 1, { op = "new_group" }, {})
for k, v in pairs({ per_wave = 15, max_alive = 20, waves = 1, wave_gap = 0, duration = 0 }) do F._handle(W, "acc1", 1, { op = "set", g = 1, key = k, value = v }, {}) end
for k = 1, 5 do M.ents[1].x = 5 * k F._handle(W, "acc1", 1, { op = "add_node", g = 1 }, {}) end
M.ents[1].x = 0
F._handle(W, "acc1", 1, { op = "start", g = 1 }, {})
run(40)
local alive = 0 for _, m in pairs(F._test_S.mon) do if not m.dead then alive = alive + 1 end end
ok(alive >= 60, "a big raid: " .. alive .. " monsters alive")
ok(on_screen() == alive, string.format("every one of them is marked on the screen (%d of %d)", on_screen(), alive))
ok(most <= 30, "never more than 30 marker messages in one step (most: " .. most .. ")")
F._handle(W, "acc1", 1, { op = "stop", g = 1 }, {})
F._handle(W, "acc1", 1, { op = "remove", g = 1 }, {})
run(4)
ok(on_screen() > 0, "4 s after Remove some are still coming off (" .. on_screen() .. " left): 30 per check")
run(12)
ok(on_screen() == 0, "16 s after Remove every marker is off the screen (" .. on_screen() .. " left)")
ok(most <= 30, "still never more than 30 in one step (most: " .. most .. ")")
local lines = 0 for _, l in ipairs(M.logs) do if l:find("markers:", 1, true) then lines = lines + 1 if os.getenv("SNLOG") == nil and lines <= 3 then print("  " .. l) end end end
local err = 0 for _, l in ipairs(M.logs) do if l:find("tick: ", 1, true) or l:find("attempt to", 1, true) then err = err + 1 print("  " .. l) end end
ok(err == 0, "no errors in the log")
print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
