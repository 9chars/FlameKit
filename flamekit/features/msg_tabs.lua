-- features/msg_tabs.lua (0.15.377, owner 2026-11-21 09:35): the Battle and Loot tabs of the Messages window. Where the
-- world is hosted it hands every hit (emf.on_hit) and every Auto Loot item (core/loot_route.lua) to core/msg_feed.lua,
-- which sends each player the lines meant for them; every game registers the channel that brings them (the lines go
-- into its tabs through kit.note_tab; FlameKit's DLL draws the tabs). The player's switches are in the Settings tab,
-- section Messages (features/settings.lua sends them: core/player_prefs.lua).

local feed = require("core.msg_feed")
local route = require("core.loot_route")
local prefs = require("core.player_prefs")

local F = { id = "msg_tabs", title = "Message tabs" }
local kit

-- (0.15.383) the debug tool behind core/monster_names.lua: "flamekit.monprints" spawns every kind of core/monsters.lua
-- 300 m below the player who typed it (the console: the local player), 5 a step, prints each one's template halves
-- (core/monster_print.lua) the step after, removes it, and writes monster_prints.txt beside FlameKit:
-- "<template guid>\t<group>\t<name>\t<boss>\t<one hash per component, - for none>".
local mp = { queue = nil, out = nil, pending = {} }
local function monprints_tick(world)
  if not mp.queue then return end
  for _, p in ipairs(mp.pending) do
    local parts = {}
    for _, c in ipairs(require("core.monster_print").COMPS) do parts[#parts + 1] = require("core.monster_print").part(world, p.id, c) or "-" end
    mp.out[#mp.out + 1] = table.concat({ p.m[3], p.m[1], p.m[2], tostring(p.m[4]), table.concat(parts, " ") }, "\t")
    pcall(emf.destroy, world, p.id)
  end
  mp.pending = {}
  for _ = 1, 5 do
    local m = table.remove(mp.queue, 1)
    if not m then break end
    local oks, id = pcall(emf.spawn, world, m[3], mp.x, mp.y, mp.z)
    if oks and id and id ~= 0 then mp.pending[#mp.pending + 1] = { id = id, m = m }
    else mp.out[#mp.out + 1] = table.concat({ m[3], m[1], m[2], tostring(m[4]), "spawn refused" }, "\t") end
  end
  if #mp.queue == 0 and #mp.pending == 0 then
    local f = io.open(emf.dir .. "\\monster_prints.txt", "w")
    if f then f:write(table.concat(mp.out, "\n"), "\n") f:close() end
    emf.log(string.format("monprints: %d kind(s) in monster_prints.txt", #mp.out))
    mp.queue = nil
  end
end

function F.tick(world)
  feed.tick(world)
  monprints_tick(world)
end

function F.setup(k)
  kit = k
  prefs.setup()
  local ok = feed.setup(kit)
  if not ok then emf.log("message tabs: the channel flamekit/feed was refused: no Battle and Loot lines") end
  route.set_report(function(world, r) feed.loot(world, r) end)
  local okh, hooked = pcall(emf.on_hit, kit.guard(F, function(world, hit) feed.hit(world, hit) end, "a hit"))
  if not (okh and hooked ~= false) then emf.log("message tabs: emf.on_hit is not there: no Battle lines") end
  -- (0.15.380) loot taken by hand (a body, a chest, the ground)
  local okp = require("core.game_events").on("PickupEvent", kit.guard(F, function(world, e) feed.pickup(world, e) end, "a pickup"))
  if not okp then emf.log("message tabs: PickupEvent refused: hand pickups are not in the Loot tab") end
  pcall(emf.command, "monprints", "debug: the template prints of every monster kind into monster_prints.txt (core/monster_names.lua's source)",
    kit.guard(F, function(world, args)
      local who = emf.sender()
      local pid = (who and who.chat and who.entity and who.entity ~= 0) and who.entity or emf.local_player()
      local ok, x, y, z = pcall(world.position, world, pid)
      if not (ok and x) then emf.reply("monprints: no position for player " .. tostring(pid)) return end
      mp.x, mp.y, mp.z = x, y - 300, z
      mp.queue, mp.out, mp.pending = {}, {}, {}
      for _, m in ipairs(require("core.monsters")) do mp.queue[#mp.queue + 1] = m end
      emf.reply(string.format("monprints: %d kind(s), 5 a step, 300 m below player %s", #mp.queue, tostring(pid)))
    end, "the monprints command"))
  pcall(emf.on_player_left, kit.guard(F, function(world, p) if p and p.player then feed.forget(p.player) end end, "a player leaving"))
end

return F
