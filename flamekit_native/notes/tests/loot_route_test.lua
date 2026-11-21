-- core/loot_route.lua (0.15.376, owner 2026-11-21 09:35 "Auto Loot"): the order of the places, the Auto Junk List first.
-- Run from the repository: texlua flamekit_native/notes/tests/loot_route_test.lua
package.path = "flamekit/?.lua;" .. package.path
local dropped = {}
package.loaded["core.ground_loot"] = {
  drop = function(w, item, n) dropped[#dropped + 1] = { item = item, n = n } return 1, 900 end,
  mark = function() end, sparkle = function() end,
}
local bag_room = 0
local puts = {}
emf = {
  put = function(w, player, item, n, fn, opts)
    local added = math.min(n, bag_room)
    bag_room = bag_room - added
    puts[#puts + 1] = { player = player, item = item, n = added, opts = opts }
    fn(w, added)
    return true
  end,
}
local route = require("core.loot_route")
local comp_room = 0
route.set_companion(function(w, player, account, item, n) local s = math.min(n, comp_room) comp_room = comp_room - s return s end)
local junk = {}
route.set_junk(function(w, account, item, gear) return junk[item] end)
local last
route.set_report(function(w, r) last = r end)
local W = {}
local function check(c, what) if not c then error("FAILED: " .. what, 2) end print("ok   " .. what) end
local function run(choice, n, bag, comp)
  bag_room, comp_room, dropped, puts, last = bag, comp, {}, {}, nil
  route.deliver(W, 7, "0xaa", choice, 0x11, n, 10, 2, 0, 0, 0, false, function() error("nothing goes back here") end)
  return last
end
local r = run("bag", 5, 99, 99)
check(r.bag == 5 and r.companion == 0 and r.ground == 0, "main bag: all into the bag")
r = run("bag", 5, 2, 2)
check(r.bag == 2 and r.companion == 2 and r.ground == 1 and dropped[1].n == 1, "main bag full: then the companions, then the ground")
check(puts[1].opts.level == 10 and puts[1].opts.rarity == 2, "level and quality kept")
r = run("companion", 5, 99, 3)
check(r.companion == 3 and r.bag == 2 and r.ground == 0, "companion bag: the companions first, then the main bag")
r = run("companion", 5, 1, 1)
check(r.companion == 1 and r.bag == 1 and r.ground == 3, "companion bag: both full, then the ground")
r = run("ground", 5, 99, 99)
check(r.ground == 5 and r.bag == 0 and r.companion == 0 and #puts == 0, "ground: all on the ground")
junk[0x11] = "delete"
r = run("bag", 5, 99, 99)
check(r.junk == "delete" and #puts == 0 and #dropped == 0, "junk set to Delete: gone, before any bag")
junk[0x11] = "drop"
r = run("companion", 5, 99, 99)
check(r.junk == "drop" and #puts == 0 and r.ground == 5 and #dropped == 1, "junk set to Drop: on the ground, before any bag")
junk[0x11] = nil
print("ALL PASSED (loot_route)")
