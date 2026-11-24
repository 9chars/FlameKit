-- (0.15.547) core/reward_loot.lua: give puts runes, legendary runes and the legendary item all into the ground chest
-- (none into a bag); clear_game_loot removes a loose drop the game makes near the death, and leaves one far away or one
-- of FlameKit's own loot marks. usage (from the repo root): texlua tools/sntest/rw.lua
package.path = "flamekit/?.lua;" .. package.path
local fails = 0
local function ok(c, what) if c then print("ok   " .. what) else fails = fails + 1 print("FAIL " .. what) end end
local puts, bagputs, destroyed, pickup_fn = {}, 0, {}, nil
emf = { item = function() return 7 end, put = function() bagputs = bagputs + 1 end, log = function() end,
        destroy = function(w, id) destroyed[#destroyed + 1] = id return true end }
package.loaded["core.loot_chest"] = { put = function(w, key, x, y, z, item, n) puts[#puts + 1] = { item = item, n = n } end, tick = function() end }
package.loaded["core.item_db"] = { RUNE = "Rune", LEGENDARY_RUNE = "LegRune", pick = function() return "Sword" end, pick_cosmetic = function() return "Hat" end }
package.loaded["core.bag"] = { entity_stacks = function() return {} end }
package.loaded["core.loot_spots"] = { find = function() end, tick = function() end }
package.loaded["core.loot_news"] = { on_pickup = function(fn) pickup_fn = fn end, tick = function() end }
package.loaded["core.ground_loot"] = { is_mark = function(id) return id == 99 end }
local R = require("core.reward_loot")
local W = { tick = function() return 1000 end }
R.give(W, 1, 2, 3, 5, 40, false)
local runes, leg, item = 0, 0, 0
for _, p in ipairs(puts) do if p.item == "Rune" then runes = p.n elseif p.item == "LegRune" then leg = p.n else item = item + 1 end end
ok(bagputs == 0 and runes >= 10 and leg >= 5 and item == 1, "give: everything into the chest, nothing into a bag")
R.clear_game_loot(W, 500, 100, 200, 50)
ok(pickup_fn ~= nil, "clear_game_loot listens for loose drops")
pickup_fn(W, 41, 103, 50, 201, 1100)
ok(destroyed[1] == 41, "a loose drop 3 m from the death is removed")
pickup_fn(W, 42, 120, 50, 200, 1100)
ok(#destroyed == 1, "one 20 m away is left")
pickup_fn(W, 99, 100, 50, 200, 1100)
ok(#destroyed == 1, "FlameKit's own loot mark is left")
pickup_fn(W, 43, 100, 50, 200, 1000 + 60 * 11)
ok(#destroyed == 1, "one made 11 s later is left")
print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
