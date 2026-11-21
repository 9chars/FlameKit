-- features/chest_overflow.lua (0.15.410): a take the full bag refused goes from the loot chest to the companions.
-- texlua flamekit_native/notes/tests/chest_overflow_test.lua   (from the repo's top folder)
package.path = "flamekit/?.lua;" .. package.path
local fails = 0
local function check(ok, what) print((ok and "ok   " or "FAIL ") .. what) if not ok then fails = fails + 1 end end
local ents, sentq, on_srv, client_fn, delivered, taken, choice = {}, {}, nil, nil, {}, {}, "companion"
emf = { log = function() end, local_player = function() return 1 end,
  json = { encode = function(t) return t end, decode = function(t) return t end },
  net = { channel = function(name, def) on_srv = def.on_server return true end, send = function(ch, t) sentq[#sentq + 1] = t return true end },
  take = function(w, owner, item, count, fn) taken[#taken + 1] = item fn(w, count) end, put = function() end }
package.loaded["core.player_prefs"] = { setup = function() end, get = function() return choice end }
local pick_fn
package.loaded["core.game_events"] = { on = function(name, fn, where) if name == "PickupEvent" then pick_fn = fn else client_fn = fn end return true end }
package.loaded["core.loot_route"] = { DEFAULT = "game",
  deliver = function(w, p, acc, ch, item, count, l, r, x, y, z, g, b, from, opts) delivered[#delivered + 1] = { p = p, ch = ch, item = item, from = from, opts = opts } end }
package.loaded["core.bag"] = { entity_stacks = function(w, id)
  local e = ents[id] return e and e.stacks or {} end }
local W = { get = function(self, c, id) local e = ents[id] return e and e.c[c] end,
  position = function(self, id) local e = ents[id] if e then return e.p[1], e.p[2], e.p[3] end end,
  account = function() return "0xa1" end, tick = function() return 100 end }
ents[1] = { c = { PlayerState = {}, Inventory = {} }, p = { 0, 0, 0 } }
ents[500] = { c = { RandomLoot = {}, Inventory = {} }, p = { 2, 0, 0 },
  stacks = { { item = 11, count = 1, owner = 500, slot = 500 | (0 << 32) }, { item = 12, count = 3, owner = 500, slot = 500 | (1 << 32) } } }
ents[600] = { c = { Inventory = {} }, p = { 1, 0, 0 }, stacks = { { item = 13, count = 1, owner = 600, slot = 600 } } }  -- his storage chest
local F = require("features.chest_overflow")
F.setup({ guard = function(F, fn) return fn end })
local function take(src, slot, typ) client_fn(W, { type = typ, sourceInventoryId = src, targetInventoryId = 1, sourceSlotId = { entityId = src, slotIndex = slot } }) end
take(500, 1, 0)
check(#sentq == 1 and sentq[1].src == 500 and sentq[1].slot == 1 and not sentq[1].all, "the player's game tells the server about a single take")
on_srv(W, { player = 1 }, sentq[1])
for _ = 1, 31 do F.tick(W) end
check(#delivered == 1 and delivered[1].item == 12 and delivered[1].ch == "companion" and delivered[1].opts.no_ground, "that slot's stack to the companions, never the ground")
take(500, 0, 2)
on_srv(W, { player = 1 }, sentq[#sentq])
for _ = 1, 31 do F.tick(W) end
check(#delivered == 3, "take all: every stack still in the chest")
take(600, 0, 2)
on_srv(W, { player = 1 }, sentq[#sentq])
for _ = 1, 31 do F.tick(W) end
check(#delivered == 3, "his own storage chest: left alone")
ents[500].p = { 30, 0, 0 }
take(500, 0, 0)
on_srv(W, { player = 1 }, sentq[#sentq])
for _ = 1, 31 do F.tick(W) end
check(#delivered == 3, "a chest out of reach: left alone")
ents[500].p = { 2, 0, 0 }
choice = "game"
take(500, 0, 0)
on_srv(W, { player = 1 }, sentq[#sentq])
for _ = 1, 31 do F.tick(W) end
check(#delivered == 3, "Auto Loot game: left alone")
choice = "companion"
local before = #delivered
take(500, 1, 0)
on_srv(W, { player = 1 }, sentq[#sentq])
pick_fn(W, { pickedUpByEntityId = 1, pickedUpFromEntityId = 500 })
for _ = 1, 31 do F.tick(W) end
check(#delivered == before, "a single take that worked (a pickup came): the rest of the stack stays")
print(fails == 0 and "ALL PASSED (chest_overflow)" or (fails .. " FAILED"))
