-- features/loose_loot.lua (0.15.389, 0.15.390, 0.15.399): a new loose item (the DLL's news) near an object broken with a
-- tool or a monster killed goes by the player's Auto Loot; nothing else is taken.
-- texlua flamekit_native/notes/tests/loose_loot_test.lua   (from the repo's top folder)
package.path = "flamekit/?.lua;" .. package.path
local fails = 0
local function check(ok, what) print((ok and "ok   " or "FAIL ") .. what) if not ok then fails = fails + 1 end end
local ents = {}
local hit_fn, pickup_fn, delivered, choice, now = nil, nil, {}, "bag", 1000
emf = { log = function() end, on_hit = function(fn) hit_fn = fn return true end,
  destroy = function(w, id) ents[id] = nil end, spawn = function() return 0 end }
package.loaded["core.player_prefs"] = { setup = function() end, get = function() return choice end }
package.loaded["core.msg_feed"] = { name = function(w, id) return "Drone(5)" end }
package.loaded["core.loot_news"] = { setup = function() return true end, tick = function() end, on_pickup = function(fn) pickup_fn = fn end }
package.loaded["core.loot_route"] = { DEFAULT = "game",
  player_of = function(w, a) if a == 1 or a == 900 then return 1 end return nil end,
  deliver = function(w, p, acc, ch, item, count, l, r, x, y, z, g, b, from) delivered[#delivered + 1] = { ch = ch, item = item, from = from } end }
local W = { get = function(self, c, id) local e = ents[id] return e and e.c[c] end,
  position = function(self, id) local e = ents[id] if e and e.p then return e.p[1], e.p[2], e.p[3] end end,
  account = function() return "0xa1" end, tick = function() return now end }
local function pickup(id, item, x, z)  -- the game makes it; the DLL's news comes
  ents[id] = { c = { PickupItem = { itemId = item, pickupAmount = 2, level = 0, rarity = 0 } }, p = { x, 0, z } }
  pickup_fn(W, id, x, 0, z, now)
end
ents[1] = { c = { PlayerState = {} }, p = { 0, 0, 0 } }
ents[500] = { c = { Health = {} }, p = { 10, 0, 10 } }
ents[600] = { c = { Health = {}, Faction = { faction = 2 } }, p = { 5, 0, 5 } }
local F = require("features.loose_loot")
F.setup({ guard = function(F, fn) return fn end })
pickup(700, 11, 12, 10)   -- nothing broken yet: stays
hit_fn(W, { attacker = 1, target = 500, attack = "melee", amount = 5, killed = true })  -- a sword: not noted
pickup(701, 12, 11, 10)
check(#delivered == 0 and ents[700] and ents[701], "no tool break: nothing taken")
hit_fn(W, { attacker = 1, target = 500, attack = "tool", amount = 5, killed = true, position = { x = 10, y = 0, z = 10 } })
now = now + 300
pickup(702, 13, 15, 12)   -- the trunk's drop, 5 s later
pickup(703, 14, 60, 60)   -- far away
check(#delivered == 1 and delivered[1].item == 13 and delivered[1].from == "chopped", "the tree's new drop to the bag")
check(ents[700] and ents[703] and not ents[702], "the old item and the far one stay")
now = now + 1200          -- 20 s after the break: too late
pickup(704, 15, 11, 11)
check(#delivered == 1 and ents[704], "a drop after the window stays")
hit_fn(W, { attacker = 1, target = 600, attack = "melee", amount = 50, killed = true })
pickup(705, 18, 5, 6)
check(#delivered == 2 and delivered[2].item == 18 and delivered[2].from == "Drone(5)", "a monster's loose drop, named")
choice = "game"
hit_fn(W, { attacker = 1, target = 500, attack = "tool", amount = 5, killed = true, position = { x = 10, y = 0, z = 10 } })
pickup(706, 16, 11, 10)
check(#delivered == 2 and ents[706], "Auto Loot game: the drop stays")
choice = "bag"
ents[900] = { c = { Health = {}, Faction = { faction = 1 } }, p = { 0, 0, 0 } }
now = now + 2000
hit_fn(W, { attacker = 1, target = 900, attack = "melee", amount = 5, killed = true })
pickup(708, 19, 1, 1)
check(#delivered == 2 and ents[708], "a companion's death: nothing taken")
print(fails == 0 and "ALL PASSED (loose_loot)" or (fails .. " FAILED"))
