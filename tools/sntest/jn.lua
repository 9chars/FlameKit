-- (0.15.547) a monster of the world that comes into a raid joins it; FlameKit's test monsters (scale 0.999) do not.
-- usage: texlua tools/sntest/jn.lua flamekit/features/spawn_nodes.lua
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
M.player(1, 0, 0, 0)
run(0.2)
F._handle(W, "acc1", 1, { op = "new_group" }, {})
for k, v in pairs({ per_wave = 2, max_alive = 2, waves = 1, duration = 0, start_delay = 0 }) do F._handle(W, "acc1", 1, { op = "set", g = 1, key = k, value = v }, {}) end
M.ents[1].x = 5 F._handle(W, "acc1", 1, { op = "add_node", g = 1 }, {}) M.ents[1].x = 0
F._handle(W, "acc1", 1, { op = "start", g = 1 }, {})
run(5)
M.next_id = M.next_id + 1
local world_id = M.next_id
M.ents[world_id] = { x = 8, y = 0, z = 0, hp = 300, max = 300, faction = 6 }
M.next_id = M.next_id + 1
local test_id = M.next_id
M.ents[test_id] = { x = 9, y = 0, z = 0, hp = 300, max = 300, faction = 6, scale = 0.999 }
run(12)
ok(S.mon[world_id] ~= nil, "a world monster that came into the raid joined it")
ok(S.mon[test_id] == nil, "a FlameKit test monster did not")
print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
