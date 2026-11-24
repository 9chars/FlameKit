-- (0.15.547) Starting level + Level per wave (never above 100), and Loot (normal / reward / both / none), per group.
-- core/spawn.lua's set_level and core/reward_loot.lua are replaced by recorders here.
-- usage: texlua tools/sntest/lv.lua flamekit/features/spawn_nodes.lua
package.path = (arg[0]:match("(.*/)") or "./") .. "?.lua;" .. package.path
package.path = (arg[1]:match("(.*/)features/") or "./") .. "?.lua;" .. package.path
local M = require("mock")
emf.enemy_order = function() return 7 end
emf.enemy_order_cancel = function() end
local levels, gives, clears = {}, {}, {}
package.loaded["core.spawn"] = { set_level = function(w, id, lvl) levels[id] = lvl return true end }
package.loaded["core.reward_loot"] = {
  give = function(w, x, y, z, killer, level, boss) gives[#gives + 1] = { killer = killer, level = level, boss = boss } return "given" end,
  clear_game_loot = function(w, id) clears[#clears + 1] = id end,
  tick = function() end, busy = function() return false end }
local F = dofile(arg[1])
F.setup(M.kit)
local W = M.world
local fails = 0
local function ok(c, what) if c then print("ok   " .. what) else fails = fails + 1 print("FAIL " .. what) end end
local function run(sec) for _ = 1, math.floor(sec * 60) do F.tick(W) M.advance(1 / 60) end end
local S = F._test_S
local function set(k, v) F._handle(W, "acc1", 1, { op = "set", g = 1, key = k, value = v }, {}) end
local function kill_all() for id, m in pairs(S.mon) do if not m.dead and M.ents[id] then M.ents[id].hp = 0 end end end
local function wave_levels(from)
  local t = {} for id, l in pairs(levels) do if id > from then t[#t + 1] = l end end table.sort(t) return t end
M.player(1, 0, 0, 0)
run(0.2)
F._handle(W, "acc1", 1, { op = "new_group" }, {})
for k, v in pairs({ per_wave = 2, max_alive = 3, waves = 3, wave_gap = 0, duration = 0, start_delay = 0, wave_dead = 100 }) do set(k, v) end
M.ents[1].x = 5 F._handle(W, "acc1", 1, { op = "add_node", g = 1 }, {}) M.ents[1].x = 0
-- defaults: game's own level, normal loot: nothing touched
F._handle(W, "acc1", 1, { op = "start", g = 1 }, {})
run(5)
ok(next(levels) == nil, "defaults: no level set (Game's own, No increase)")
for _ = 1, 3 do kill_all() run(3) end
run(15)
ok(#gives == 0 and #clears == 0, "defaults: normal loot: no reward, nothing removed")
-- level 60, +25 each wave: 60, 85, 100 (not 110)
set("start_level", 60) set("level_step", 25) set("loot", "reward")
local mark = M.next_id
F._handle(W, "acc1", 1, { op = "start", g = 1 }, {})
run(4)
for _ = 1, 10 do
  for id, m in pairs(S.mon) do if not m.dead and M.ents[id] then S.hitby[id] = 1 end end  -- player 1 hit them
  kill_all() run(3)
end
run(15)
local ids = {} for id in pairs(levels) do if id > mark then ids[#ids + 1] = id end end table.sort(ids)
local seq = {} for _, id in ipairs(ids) do seq[#seq + 1] = levels[id] end
ok(table.concat(seq, ",") == "60,60,85,85,100,100", "waves 1-3 at 60, 85 and 100 (not 110): " .. table.concat(seq, ","))
ok(#gives == 6 and #clears == 6, "Reward loot: a reward and the game loot removed for each of the 6 (" .. #gives .. ", " .. #clears .. ")")
ok(gives[1].killer == 1 and gives[1].level == 60, "the reward goes to the player who hit it, at its level")
local lv_ok = true for _, gv in ipairs(gives) do if gv.level > 100 then lv_ok = false end end
ok(lv_ok, "no reward above level 100")
-- both: rewards, game loot kept; none: nothing given, game loot removed
gives, clears = {}, {}
set("loot", "both") F._handle(W, "acc1", 1, { op = "start", g = 1 }, {}) run(4)
for _ = 1, 10 do kill_all() run(3) end run(15)
ok(#gives == 6 and #clears == 0, "Reward + normal loot: rewards, the game loot stays (" .. #gives .. ", " .. #clears .. ")")
gives, clears = {}, {}
set("loot", "none") F._handle(W, "acc1", 1, { op = "start", g = 1 }, {}) run(4)
for _ = 1, 10 do kill_all() run(3) end run(15)
ok(#gives == 0 and #clears == 6, "No loot: nothing given, the game loot removed (" .. #gives .. ", " .. #clears .. ")")
-- a value off the list is refused; 110 is not on it
set("start_level", 110)
ok(S.data.groups["1"].start_level == 60, "a starting level of 110 is refused")
local err = 0 for _, l in ipairs(M.logs) do if l:find("tick: ", 1, true) or l:find("attempt to", 1, true) or l:find("spawn nodes: loot: ", 1, true) and l:find("error", 1, true) then err = err + 1 print("  " .. l) end end
ok(err == 0, "no errors in the log")
for _, l in ipairs(M.logs) do if l:find("at level", 1, true) then print("  " .. l) end end
print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
