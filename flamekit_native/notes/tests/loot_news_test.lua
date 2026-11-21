-- core/loot_news.lua + core/loot_spots.lua (0.15.399): the DLL's TestEvent2 news are the loot spot candidates (no walk).
-- texlua flamekit_native/notes/tests/loot_news_test.lua   (from the repo's top folder)
package.path = "flamekit/?.lua;" .. package.path
local fails = 0
local function check(ok, what) print((ok and "ok   " or "FAIL ") .. what) if not ok then fails = fails + 1 end end
local handlers, now, ents = {}, 5000, {}
emf = { log = function() end, on_event = function(name, fn) handlers[name] = fn return true end }
local W = { get = function(self, c, id) local e = ents[id] return e and e.c[c] end,
  position = function(self, id) local e = ents[id] if e then return e.p[1], e.p[2], e.p[3] end end,
  tick = function() return now end }
local function pile(id, x, z, comps) ents[id] = { c = comps, p = { x, 0, z } } handlers.TestEvent2(W, { data = id }) end
local news = require("core.loot_news")
local spots = require("core.loot_spots")
check(news.setup(), "the events are asked for")
local loot = { DestroyOnLoot = {}, DefaultInventory = {}, Faction = {}, InventorySetup = {} }
pile(10, 1, 1, loot)                                                    -- a critter's pile
pile(11, 2, 1, { DestroyOnLoot = {}, DefaultInventory = {}, InventorySetup = {} })  -- a chest or urn: no Faction, no DoNotSave
pile(12, 30, 30, loot)                                                  -- far away
local got
spots.find(99, 0, 0, nil, function(w, ids) got = ids end)
spots.tick(W)
check(got and #got == 1 and got[1] == 10, "the pile near the death, not the chest or the far one")
now = now + 60 * 25
got = nil
spots.find(98, 0, 0, nil, function(w, ids) got = ids end)
spots.tick(W)
check(got and #got == 0, "a pile reported 25 s earlier no longer counts")
local seen
news.on_pickup(function(w, id, x, y, z, t) seen = { id, x, t } end)
ents[20] = { c = { PickupItem = {} }, p = { 3, 0, 4 } }
handlers.TestEvent1(W, { data = 20 })
check(seen and seen[1] == 20 and seen[2] == 3 and seen[3] == now, "a new loose item is handed on with its place and tick")
print(fails == 0 and "ALL PASSED (loot_news)" or (fails .. " FAILED"))
