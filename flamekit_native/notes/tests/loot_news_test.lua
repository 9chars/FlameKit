-- core/loot_news.lua + core/loot_spots.lua (0.15.399): the DLL's loot_news.txt ("<n> <p|c> <entity> <tick>") is read
-- only while someone waits; the containers in it are the loot spot candidates (no walk).
-- texlua flamekit_native/notes/tests/loot_news_test.lua   (from the repo's top folder)
package.path = "flamekit/?.lua;" .. package.path
local fails = 0
local function check(ok, what) print((ok and "ok   " or "FAIL ") .. what) if not ok then fails = fails + 1 end end
local dir = os.tmpname() os.remove(dir) os.execute("mkdir -p " .. dir)
local now, ents, lines = 5000, {}, {}
emf = { log = function() end, dir = dir }
local function write() local f = io.open(dir .. "\\loot_news.txt", "wb") f:write(table.concat(lines, "\n") .. "\n") f:close() end
local W = { get = function(self, c, id) local e = ents[id] return e and e.c[c] end,
  position = function(self, id) local e = ents[id] if e then return e.p[1], e.p[2], e.p[3] end end,
  tick = function() return now end }
local news = require("core.loot_news")
local spots = require("core.loot_spots")
lines = { "1 p 5 4000", "2 c 6 4000" } write()   -- old news, there before anyone read
ents[5] = { c = { PickupItem = {} }, p = { 0, 0, 0 } }
local seen = {}
news.on_pickup(function(w, id, x, y, z, t) seen[#seen + 1] = { id = id, t = t } end)
news.tick(W, false)                              -- the first read only learns where the file stands
check(#seen == 0, "the lines there at the first read are old")
local loot = { DestroyOnLoot = {}, DefaultInventory = {}, Faction = {}, InventorySetup = {} }
ents[10] = { c = loot, p = { 1, 0, 1 } }
ents[11] = { c = { DestroyOnLoot = {}, DefaultInventory = {}, InventorySetup = {} }, p = { 2, 0, 1 } }
ents[12] = { c = loot, p = { 30, 0, 30 } }
ents[20] = { c = { PickupItem = {} }, p = { 3, 0, 4 } }
lines = { "1 p 5 4000", "2 c 6 4000", "3 c 10 5000", "4 c 11 5000", "5 c 12 5000", "6 p 20 4990" } write()
now = now + 10
news.tick(W, false)
check(#seen == 0, "nobody waits: not read")
local got
spots.find(99, 0, 0, nil, function(w, ids) got = ids end)
spots.tick(W)
check(got and #got == 1 and got[1] == 10, "the pile near the death, not the chest or the far one")
check(#seen == 1 and seen[1].id == 20 and seen[1].t == 4990, "the new loose item with the step it was made")
now = now + 60 * 25
got = nil
spots.find(98, 0, 0, nil, function(w, ids) got = ids end)
spots.tick(W)
check(got and #got == 0, "a pile made 25 s earlier no longer counts")
lines = { "1 p 21 9000" } write()                -- the server started again: the numbers too
now = now + 10
news.tick(W, true)
lines = { "1 p 21 9000", "2 p 20 9001" } write()
now = now + 10
news.tick(W, true)
check(#seen == 2 and seen[2].id == 20, "after a server restart the new numbers count again")
os.remove(dir .. "\\loot_news.txt")
print(fails == 0 and "ALL PASSED (loot_news)" or (fails .. " FAILED"))
