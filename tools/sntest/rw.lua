-- (0.15.547) core/reward_loot.lua give: runes, legendary runes and the legendary item all into the ground chest, none into a bag. usage (from the repo root): texlua tools/sntest/rw.lua
-- core/reward_loot.give puts everything into chests: loot_chest.put recorder, no emf.put
package.path = "flamekit/?.lua;" .. package.path
local puts, bagputs = {}, 0
emf = { item = function(n) return 7 end, put = function() bagputs = bagputs + 1 end, log = function() end }
package.loaded["core.loot_chest"] = { put = function(w, key, x, y, z, item, n) puts[#puts + 1] = { item = item, n = n } end, tick = function() end }
package.loaded["core.item_db"] = { RUNE = "Rune", LEGENDARY_RUNE = "LegRune", pick = function() return "Sword" end, pick_cosmetic = function() return "Hat" end }
package.loaded["core.bag"] = { entity_stacks = function() return {} end }
package.loaded["core.loot_spots"] = { find = function() end, tick = function() end }
local R = require("core.reward_loot")
local line = R.give({}, 1, 2, 3, 5, 40, false)
local runes, leg, item = 0, 0, 0
for _, p in ipairs(puts) do if p.item == "Rune" then runes = p.n elseif p.item == "LegRune" then leg = p.n else item = item + 1 end end
print((bagputs == 0 and runes >= 10 and leg >= 5 and item == 1) and "ALL OK: everything into the chest: " .. line or ("FAIL " .. bagputs .. " " .. runes .. " " .. leg .. " " .. item))
