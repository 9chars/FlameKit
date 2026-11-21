-- core/msg_feed.lua (0.15.377, owner 2026-11-21 09:35/09:44/09:48): who gets the Battle and Loot lines, and that every
-- line arrives (batches, none dropped). Run from the repository: texlua flamekit_native/notes/tests/msg_feed_test.lua
package.path = "flamekit/?.lua;" .. package.path
local sent = {}   -- player -> { messages }
local peers = { [1] = 1, [2] = 1, [3] = 1, [4] = 0 }  -- player 4's game has no feed channel
local channel
local accounts = { [1] = "0xa1", [2] = "0xa2", [3] = "0xa3", [4] = "0xa4" }
local pos = { [1] = { 0, 0, 0 }, [2] = { 50, 0, 0 }, [3] = { 400, 0, 0 }, [4] = { 10, 0, 0 }, [500] = { 1, 0, 0 }, [600] = { 2, 0, 0 } }
local comps = { [1] = { PlayerState = {} }, [2] = { PlayerState = {} }, [3] = { PlayerState = {} }, [4] = { PlayerState = {} },
  [500] = { Faction = { faction = 3 }, Level = { dataStorage = { 25 } } }, [600] = { Faction = { faction = 11 } } }
local W = {}
function W:get(c, id) return comps[id] and comps[id][c] end
function W:position(id) local p = pos[id] if p then return p[1], p[2], p[3] end end
function W:account(id) return accounts[id] end
function W:character_name(id) return ({ "Ann", "Bob", "Cid", "Dee" })[id] end
function W:tick() return 0 end
local json = {}
emf = {
  local_player = function() return 99 end,
  net = {
    channel = function(name, def) if name == "feed" then channel = def end return true end,
    peer = function(w, pid, name) return peers[pid] or 0 end,
    send_to = function(w, pid, name, data) sent[pid] = sent[pid] or {} sent[pid][#sent[pid] + 1] = data return true end,
  },
  json = { encode = function(t) json[#json + 1] = t return "#" .. #json end, decode = function(s) return json[tonumber(s:sub(2))] end },
  item_name = function(id) return "Iron Sword" end,
  log = function() end,
}
package.loaded["core.players"] = { ids = function() return { 1, 2, 3, 4 } end,
  name = function(w, id, fb) return w:character_name(id) or fb end }
local route = require("core.loot_route")
route.set_owner(function(w, e) if e == 600 then return 2 end end)  -- 600: Bob's companion
local prefs = require("core.player_prefs")
prefs.setup = function() return true end
local values = {}
prefs.get = function(acc, key) return values[acc] and values[acc][key] end
local feed = require("core.msg_feed")
local notes = {}
feed.setup({ is_host = function() return false end, note_tab = function(tab, t) notes[#notes + 1] = { tab, t } end })
feed.set_namer(function(w, e) if e == 600 then return "Rex" end end)
local function check(c, what) if not c then error("FAILED: " .. what, 2) end print("ok   " .. what) end
local function flush() for _ = 1, 30 do feed.tick(W) end end
local function lines(pid, tab)
  local out = {}
  for _, data in ipairs(sent[pid] or {}) do
    local m = emf.json.decode(data)
    if m.tab == tab then for _, l in ipairs(m.lines) do out[#out + 1] = l end end
  end
  return out
end

feed.hit(W, { attacker = 1, target = 500, amount = 120, crit = true })
flush()
check(next(sent) == nil, "Battle messages off for everyone: nothing is sent")
values["0xa1"] = { battle_msgs = true }
values["0xa2"] = { battle_msgs = true }
values["0xa3"] = { battle_msgs = true }
values["0xa4"] = { battle_msgs = true }
feed.hit(W, { attacker = 1, target = 500, amount = 120, crit = true })
for _ = 1, 60 do feed.tick(W) end  -- (who has it on is looked at once a second)
feed.hit(W, { attacker = 1, target = 500, amount = 120, crit = true })
feed.hit(W, { attacker = 500, target = 600, amount = 33 })
feed.hit(W, { attacker = 500, target = 501, amount = 33 })  -- monsters among themselves: nobody
comps[700] = {}  -- (0.15.382) a tree: no faction
pos[700] = { 1, 0, 1 }
feed.hit(W, { attacker = 1, target = 700, amount = 1 })
feed.hit(W, { attacker = 0, target = 1, amount = 9 })  -- no attacker
flush()
local a, b, c = lines(1, "battle"), lines(2, "battle"), lines(3, "battle")
check(#a >= 2 and a[#a - 1]:find("Ann hit Vukah%(25%) for 120 damage %(crit%)") ~= nil, "Ann's own hit, with the monster's kind, level and crit: " .. tostring(a[#a - 1]))
check(#b >= 1 and b[#b]:find("Vukah%(25%) hit Rex for 33 damage") ~= nil, "a hit on Bob's companion goes to Bob, the companion by name")
check(#c == 0, "Cid (400 m away) sees neither")
local objs = 0
for _, l in ipairs(a) do if l:find("Creature") or l:find("something") then objs = objs + 1 end end
check(objs == 0, "a hit on a tree (no faction) and damage with no attacker are left out")
check(sent[4] == nil, "a game without the channel gets nothing")
values["0xa2"].others_battle = false
sent = {}
feed.hit(W, { attacker = 1, target = 500, amount = 5 })
flush()
check(#lines(1, "battle") == 1 and #lines(2, "battle") == 0, "Bob with other players' battle messages off: not Ann's hit")
-- every line arrives: 3000 hits, batches of at most 15 KB, four a batch
sent = {}
for i = 1, 3000 do feed.hit(W, { attacker = 1, target = 500, amount = i }) end
for _ = 1, 30 * 40 do feed.tick(W) end
local got = lines(1, "battle")
check(#got == 3000 and got[1]:find(" for 1 damage$") and got[3000]:find(" for 3000 damage$"), "3000 hits: all 3000 lines arrive, in order (" .. #got .. ")")
local most = 0
for _, data in ipairs(sent[1]) do local m = emf.json.decode(data) local n = 0 for _, l in ipairs(m.lines) do n = n + #l + 4 end most = math.max(most, n) end
check(most <= 15000, "no message over 15 KB (" .. most .. ")")
-- loot: Ann's item, near Bob (others on), not Cid
sent = {}
feed.loot(W, { player = 1, item = 77, count = 2, level = 50, rarity = 4, bag = 2, companion = 0, ground = 0, x = 0, z = 0, from = "Vukah(25)" })
flush()
local la, lb, lc = lines(1, "loot"), lines(2, "loot"), lines(3, "loot")
check(#la == 1 and #lb == 1 and #lc == 0, "a loot line for its player and players near")
channel.on_player(W, {}, sent[1][1])
check(notes[#notes][1] == "loot" and notes[#notes][2] == "Ann: legendary Iron Sword x2 (lvl 50) from Vukah(25) > bag", "the game writes it with the item's name: " .. tostring(notes[#notes][2]))
values["0xa2"].others_loot = false
sent = {}
feed.loot(W, { player = 1, item = 77, count = 1, junk = "delete", x = 0, z = 0 })
flush()
check(#lines(2, "loot") == 0 and lines(1, "loot")[1]:find("junk delete"), "Bob with other players' loot off; a junk line says so")
-- (0.15.380) a pickup by hand: logged for its player (and players near); crafting (from entity 0) is not
sent = {}
values["0xa2"].others_loot = true
-- (0.15.386) the game's event is strict (a field it has not is an error: "PickupEvent has no field itemLevel") and
-- has these fields only (local server log 12:12)
local function strict(t)
  return setmetatable(t, { __index = function(_, k) error("PickupEvent has no field " .. tostring(k)) end })
end
local function ev(by, from, item, count)
  return strict({ hideInUi = false, itemCount = count, itemId = item, pickedUpByEntityId = by, pickedUpFromEntityId = from,
    position = "float3", targetSlotId = "InventorySlotId", timeStamp = 1 })
end
feed.pickup(W, ev(1, 777, 77, 3))
feed.pickup(W, ev(1, 0, 78, 1))
flush()
check(#lines(1, "loot") == 1 and #lines(2, "loot") == 1 and #lines(3, "loot") == 0, "a pickup: Ann and Bob near her, not Cid; crafting left out")
channel.on_player(W, {}, sent[1][1])
check(notes[#notes][2] == "Ann: Iron Sword x3 > picked up", "a pickup line: " .. tostring(notes[#notes][2]))
-- a companion's heal
sent = {}
values["0xa2"].others_battle = true
feed.heal(W, 600, 2, 40)
flush()
check(lines(2, "battle")[1]:find("Rex heals Bob for 40"), "a heal names the companion")
print("ALL PASSED (msg_feed)")
