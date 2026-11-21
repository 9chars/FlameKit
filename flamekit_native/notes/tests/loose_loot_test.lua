-- features/loose_loot.lua (0.15.389, 0.15.390): only new pickups around an object broken with a tool or a monster killed,
-- by the player's Auto Loot.
-- texlua flamekit_native/notes/tests/loose_loot_test.lua   (from the repo's top folder)
package.path = "flamekit/?.lua;" .. package.path
local fails = 0
local function check(ok, what) print((ok and "ok   " or "FAIL ") .. what) if not ok then fails = fails + 1 end end
local ents = {}   -- id -> { comps, pos }
local hit_fn, delivered, destroyed, choice = nil, {}, {}, "bag"
emf = { log = function() end, on_hit = function(fn) hit_fn = fn return true end,
  destroy = function(w, id) destroyed[#destroyed + 1] = id ents[id] = nil end, spawn = function() return 0 end }
package.loaded["core.player_prefs"] = { setup = function() end, get = function() return choice end }
package.loaded["core.msg_feed"] = { name = function(w, id) return "Drone(5)" end }
package.loaded["core.loot_route"] = { DEFAULT = "game",
  player_of = function(w, a) if a == 1 then return 1 elseif a == 900 then return 1 end return nil end,
  deliver = function(w, p, acc, ch, item, count, l, r, x, y, z, g, b, from) delivered[#delivered + 1] = { p = p, ch = ch, item = item, count = count, from = from } end }
local W = { get = function(self, c, id) local e = ents[id] return e and e.c[c] end,
  position = function(self, id) local e = ents[id] if e and e.p then return e.p[1], e.p[2], e.p[3] end end,
  entities = function() local l = {} for id in pairs(ents) do l[#l + 1] = id end table.sort(l) return l end,
  account = function() return "0xa1" end }
local function pickup(id, item, x, z) ents[id] = { c = { PickupItem = { itemId = item, pickupAmount = 2, level = 0, rarity = 0 } }, p = { x, 0, z } } end
ents[1] = { c = { PlayerState = {} }, p = { 0, 0, 0 } }
ents[500] = { c = { Health = {} }, p = { 10, 0, 10 } }          -- a tree
ents[600] = { c = { Health = {}, Faction = { faction = 2 } }, p = { 5, 0, 5 } }  -- a monster
pickup(700, 11, 12, 10)   -- lying there before
pickup(701, 12, 80, 80)   -- far away
local kit = { guard = function(F, fn) return fn end }
local F = require("features.loose_loot")
F.setup(kit)
local function run(n) for _ = 1, n do F.tick(W) end end
hit_fn(W, { attacker = 1, target = 500, attack = "melee", amount = 5 })   -- a sword: nothing
hit_fn(W, { attacker = 1, target = 500, attack = "tool", amount = 5, position = { x = 10, y = 0, z = 10 } })
run(5)
ents[500] = nil
hit_fn(W, { attacker = 1, target = 500, attack = "tool", amount = 5, killed = true, position = { x = 10, y = 0, z = 10 } })
pickup(702, 13, 15, 12)   -- the tree's drop
pickup(703, 14, 60, 60)   -- new but 70 m away
run(80)
check(#delivered == 1 and delivered[1].item == 13 and delivered[1].ch == "bag", "only the tree's new drop went to the bag (" .. #delivered .. ")")
check(ents[700] and ents[703] and not ents[702], "the old pickup and the far one stay")
pickup(704, 15, 11, 11)   -- comes a bit later
run(200)
check(#delivered == 2 and delivered[2].item == 15, "a later drop is taken at the next look")
-- the game's way: nothing
choice = "game"
ents[501] = { c = { Health = {} }, p = { -10, 0, -10 } }
hit_fn(W, { attacker = 1, target = 501, attack = "tool", amount = 5 })
run(5)
hit_fn(W, { attacker = 1, target = 501, attack = "tool", amount = 5, killed = true })
pickup(705, 16, -11, -10)
run(700)
check(#delivered == 2 and ents[705], "Auto Loot game: the drop stays")
-- (0.15.390) a monster killed with one hit dumps its loot on the ground a moment later; an old item beside it stays
choice = "bag"
pickup(706, 17, 6, 5)     -- lying there before, beside it
hit_fn(W, { attacker = 1, target = 600, attack = "melee", amount = 50, killed = true })
ents[600] = nil
run(20)                   -- noted
pickup(707, 18, 5, 6)     -- the drone's essence
run(700)
check(#delivered == 3 and delivered[3].item == 18 and delivered[3].from == "Drone(5)" and ents[706], "the monster's loose drop went to the bag, named; the old item beside it stays")
-- a companion (900 is his) gets no such handling when it is hit; the monster it kills does
ents[900] = { c = { Health = {}, Faction = { faction = 1 } }, p = { 0, 0, 0 } }
hit_fn(W, { attacker = 1, target = 900, attack = "melee", amount = 5, killed = true })
pickup(708, 19, 1, 1)
run(700)
check(#delivered == 3 and ents[708], "a companion's death: nothing taken")
print(fails == 0 and "ALL PASSED (loose_loot)" or (fails .. " FAILED"))
