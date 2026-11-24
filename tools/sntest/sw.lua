-- (0.15.550) the Spawn Nodes switch (sn_enabled) turned off in the middle of a raid: F.switched_off ends the running
-- group (as Stop: cooldown, queue dropped), forgets the raid's count, and sets the files FlameKit Native reads to
-- "nothing" (animal hold 0, raid lock empty, protection 0, spare empty). Also: kit.lua calls switched_off when the
-- setting turns off and at load, and not for another key.
-- usage: texlua tools/sntest/sw.lua flamekit/features/spawn_nodes.lua
package.path = (arg[0]:match("(.*/)") or "./") .. "?.lua;" .. package.path
package.path = (arg[1]:match("(.*/)features/") or "./") .. "?.lua;" .. package.path
local M = require("mock")
emf.enemy_order = function() return 7 end
emf.enemy_order_cancel = function() end
local F = dofile(arg[1])
F.setup(M.kit)
local W = M.world
local fails = 0
local function ok(c, what) if c then print("ok   " .. what) else fails = fails + 1 print("FAIL " .. what) end end
local function run(f, sec) for _ = 1, math.floor(sec * 60) do f.tick(W) M.advance(1 / 60) end end
local function read(name)
  local f = io.open(emf.dir .. name, "r")
  if not f then return nil end
  local t = f:read("*a") f:close() return t
end
ok(F.enabled_setting == "sn_enabled", "Spawn Nodes has the enabled_setting sn_enabled")
M.player(1, 0, 0, 0)
run(F, 0.2)
F._handle(W, "acc1", 1, { op = "new_group" }, {})
for k, v in pairs({ per_wave = 2, max_alive = 2, waves = 3, duration = 0, start_delay = 0, cooldown = 10, protect = true }) do F._handle(W, "acc1", 1, { op = "set", g = 1, key = k, value = v }, {}) end
M.ents[1].x = 5 F._handle(W, "acc1", 1, { op = "add_node", g = 1 }, {}) M.ents[1].x = 0
F._handle(W, "acc1", 1, { op = "start", g = 1 }, {})
run(F, 4)
local S = F._test_S
ok(S.runs[1] ~= nil, "the raid runs")
ok(read("\\raid_protect_server.txt") == "1\n", "protection file is 1 while it runs")
ok((read("\\animal_hold_server.txt") or ""):match("^1 ") ~= nil, "animal hold is on while it runs")
F.switched_off()
ok(next(S.runs) == nil, "no group runs after switching off")
ok(next(S.raid) == nil and #S.queue == 0, "the raid's count and the queue are gone")
ok(S.last_end[1] ~= nil and S.halted[1] == true, "the group was stopped as by Stop (cooldown started)")
ok(read("\\raid_protect_server.txt") == "0\n", "protection file is 0")
ok(read("\\raid_lock_server.txt") == "", "raid lock file is empty")
ok(read("\\animal_hold_server.txt") == "0\n", "animal hold file is 0")
ok(read("\\spare_server.txt") == "\n", "spare file is empty")

-- kit.lua: switched_off runs when the setting turns off and at load; not for another key, not while on
local setting, on_change = true, nil
local calls = 0
local saved = { setting = emf.setting, on_setting_changed = emf.on_setting_changed, on_tick = emf.on_tick, log = emf.log }
emf.setting = function(k) if k == "x_enabled" then return setting end return nil end
emf.on_setting_changed = function(fn) on_change = fn end
emf.on_tick = function() end
emf.log = function() end
package.loaded["core.kit"] = nil
local okk, kit = pcall(require, "core.kit")
if okk then
  package.preload["sw_feature"] = function() return { id = "x", title = "X", enabled_setting = "x_enabled", switched_off = function() calls = calls + 1 end } end
  local oks, err = pcall(kit.start, { "sw_feature" })
  ok(oks, "kit.start ran (" .. tostring(err) .. ")")
  ok(calls == 0, "not called at load while on")
  setting = false
  if on_change then on_change("other_key") end
  ok(calls == 0, "not called for another key")
  if on_change then on_change("x_enabled") end
  ok(calls == 1, "called once when it turns off")
  setting = true
  if on_change then on_change("x_enabled") end
  ok(calls == 1, "not called when it turns on")
  setting = false
  package.loaded["core.kit"] = nil
  local kit2 = require("core.kit")
  calls = 0
  pcall(kit2.start, { "sw_feature" })
  ok(calls == 1, "called at load while off")
else
  ok(false, "core.kit loads: " .. tostring(kit))
end
for k, v in pairs(saved) do emf[k] = v end
print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
