-- usage: texlua tools/sntest/tr.lua flamekit/features/spawn_nodes.lua (rl.lua the same): a fake world, no game needed
package.path = (arg[0]:match("(.*/)") or "./") .. "?.lua;" .. package.path
local M = require("mock")
local F = dofile(arg[1])
F.setup(M.kit)
local W = M.world
local fails = 0
local function ok(c, what) if c then print("ok   " .. what) else fails = fails + 1 print("FAIL " .. what) end end
local function run(sec) for _ = 1, math.floor(sec * 60) do F.tick(W) M.advance(1 / 60) end end
local function own_alive_at(S, nid) local n = 0 for _, m in pairs(S.mon) do if m.n == nid and m.own and not m.dead then n = n + 1 end end return n end

M.player(1, 0, 0, 0)
run(0.2)  -- the load scan
F._handle(W, "acc1", 1, { op = "new_group" }, {})
for k, v in pairs({ per_wave = 3, max_alive = 1, waves = 2, wave_gap = 0, near_r = 50, duration = 0 }) do F._handle(W, "acc1", 1, { op = "set", g = 1, key = k, value = v }, {}) end
M.ents[1].x = 10 F._handle(W, "acc1", 1, { op = "add_node", g = 1 }, {})
M.ents[1].x = -10 F._handle(W, "acc1", 1, { op = "add_node", g = 1 }, {})
M.ents[1].x = 0
local S = F._test_S
F._handle(W, "acc1", 1, { op = "start", g = 1 }, {})
run(1)
ok(own_alive_at(S, 1) == 1 and own_alive_at(S, 2) == 1, "Most alive 1: one own monster per node after the start")
local first = {} for id, m in pairs(S.mon) do first[m.n] = id end
run(3)  -- the start notice waits up to 3 s for the place
ok(M.last_left() and M.last_left():find("12 of 12", 1, true), "count starts at 12 of 12: " .. tostring(M.last_left()))

-- kill node 1's monster: the next comes at once
M.ents[first[1]].hp = 0
run(1)
ok(S.mon[first[1]] and S.mon[first[1]].dead, "killed monster is dead in the roster")
ok(own_alive_at(S, 1) == 1, "node 1 spawned its next monster right after the kill")
run(6)
ok(M.last_left():find("11 of 12", 1, true), "count went down to 11: " .. tostring(M.last_left()))

-- the body gets up again (Undead): counted apart, does not hold node 1's place, count does not go up
M.ents[first[1]].hp = 5
run(1)
ok(S.mon[first[1]] and not S.mon[first[1]].dead and not S.mon[first[1]].own, "body that got up: alive, counted apart")
local cur1 = nil for id, m in pairs(S.mon) do if m.n == 1 and m.own and not m.dead then cur1 = id end end
M.ents[cur1].hp = 0
run(1)
ok(own_alive_at(S, 1) == 1, "node 1 still spawns while the got-up body lives (not quiet)")
run(6)
ok(M.last_left():find("10 of 12", 1, true), "count only went down (10 of 12): " .. tostring(M.last_left()))

-- a joined monster (a summon) next to node 2: counted apart, node 2 is not held by it
M.next_id = M.next_id + 1
local sid = M.next_id
M.ents[sid] = { x = -9, y = 0, z = 1, hp = 4, max = 4, faction = 10 }
run(3)
ok(S.mon[sid] and not S.mon[sid].own, "summon joined, counted apart")
local cur2 = nil for id, m in pairs(S.mon) do if m.n == 2 and m.own and not m.dead then cur2 = id end end
M.ents[cur2].hp = 0
run(1)
ok(own_alive_at(S, 2) == 1, "node 2 spawns its next one while the summon lives")

-- health not readable: counted 10 s, then forgotten
local h = nil for id, m in pairs(S.mon) do if m.n == 2 and m.own and not m.dead then h = id end end
M.ents[h].hp = nil
run(5)
ok(S.mon[h] ~= nil, "unreadable health: still counted after 5 s")
run(6)
ok(S.mon[h] == nil, "unreadable health: forgotten after 10 s")
ok(M.count("could not be read for 10 s") >= 1, "that was logged")
M.ents[h].hp = 0

-- an own monster that rises (0 health at first): alive for 10 s, not dead at once
M.spawn_hp = 0
local before = M.next_id
for id, m in pairs(S.mon) do if m.own and not m.dead then M.ents[id].hp = 0 end end
run(1)
local riser = nil for id = before + 1, M.next_id do if S.mon[id] then riser = id end end
ok(riser and not S.mon[riser].dead, "a monster coming up with 0 health counts alive")
M.ents[riser].hp = 80
M.spawn_hp = nil
run(1)
ok(not S.mon[riser].dead and S.mon[riser].own, "it came up: still its node's own")

-- kill everything until the raid ends
for _ = 1, 40 do
  for id, m in pairs(S.mon) do if not m.dead and M.ents[id] then M.ents[id].hp = 0 end end
  run(1)
end
run(20)
local over = false for _, s in ipairs(M.notices) do if s:find("is over", 1, true) then over = true end end
ok(over, "the raid ended with its notice")
ok(S.raid[1] == nil, "no raid left")
local spawned_own = M.count("(spawned by its node)")
ok(spawned_own == 12, "exactly 12 own monsters spawned (2 nodes x 3 x 2 waves): " .. spawned_own)

-- a new raid: the bodies of the last one are put aside; one of them getting up is never counted
local a_body = nil for id, m in pairs(S.mon) do if m.dead then a_body = id break end end
F._handle(W, "acc1", 1, { op = "start", g = 1 }, {})
run(1)
ok(a_body and S.mon[a_body] == nil and S.old_bodies[a_body] == 1, "new raid: old bodies put aside")
M.ents[a_body].hp = 6
run(3)
ok(S.mon[a_body] == nil, "an old body getting up is not counted back in")
run(6)
ok(M.last_left():find("12 of 12", 1, true), "new raid counts 12 of 12 again: " .. tostring(M.last_left()))

-- Remove: living ones and all bodies taken away
local nb = #M.destroyed
F._handle(W, "acc1", 1, { op = "remove", g = 1 }, {})
local alive_left = 0 for _, m in pairs(S.mon) do if m.g == 1 and not m.dead then alive_left = alive_left + 1 end end
ok(alive_left == 0, "Remove: nothing of the group alive in the roster")
ok(M.ents[a_body] == nil, "Remove: the old body is gone too")
ok(#M.destroyed > nb, "Remove destroyed entities")
run(5)

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
