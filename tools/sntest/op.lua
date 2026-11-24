-- (0.15.546) open to every player for testing: a player who is not an admin gets the groups and nodes and can act.
-- usage: texlua tools/sntest/op.lua flamekit/features/spawn_nodes.lua
package.path = (arg[0]:match("(.*/)") or "./") .. "?.lua;" .. package.path
package.path = (arg[1]:match("(.*/)features/") or "./") .. "?.lua;" .. package.path
local M = require("mock")
package.loaded["core.admins"] = { is = function() return false end, setup = function() end }  -- nobody is an admin
local F = dofile(arg[1])
F.setup(M.kit)
local W = M.world
local fails = 0
local function ok(c, what) if c then print("ok   " .. what) else fails = fails + 1 print("FAIL " .. what) end end
M.player(2, 0, 0, 0)
for _ = 1, 20 do F.tick(W) M.advance(1 / 60) end
local st = F._handle(W, "acc2", 2, { op = "new_group" }, {})
ok(st and st.admin == true, "a player who is not an admin is treated as one")
ok(st and st.groups and #st.groups == 1, "and could make a group")
M.ents[2].x = 5
st = F._handle(W, "acc2", 2, { op = "add_node", g = 1 }, {})
ok(st and st.nodes and #st.nodes == 1, "and add a node")
print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
