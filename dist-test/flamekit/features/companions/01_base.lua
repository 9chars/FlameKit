-- features/companions/01_base.lua: part 1 of the companion code (the server side), split from npc_probe.lua in 0.15.362
-- (owner 2026-11-20 18:11). The parts run in order in ONE shared environment (features/companions.lua): what was a
-- top-level local is a name in that environment, seen by every part.
-- npc_probe.lua: FlameKit's companions, on the owner's local test server only (never published; the repository keeps
-- the live copy in local_server/). No game AI anywhere: the companion's own AI and route planner are always off.
--   - the roster: FlameKit's own list of companions in the world's data (survives restarts), a main companion per
--     player, controllers and admins;
--   - following = the drive (FlameKit's breadcrumb trail of the player; the C++ server probe writes his movement input),
--     with swimming and diving, jump follow, drops, stuck notices, and put away / back beside the player (glider, fast
--     travel, can't follow);
--   - staying: no target, he stands still;
--   - E opens the wheel (Follow me / Stay here / Attack / Put away; Attack: the fight modes Passive, Defensive,
--     Aggressive, Healing) in the player's game; "Call my companion" (P, Experimental
--     panel) respawns his main companion beside him;
--   - the minimap's companion dots, the full recorder (fullrec), and console tools for tests.
-- Console (or emf\commands.txt on the server): flamekit.npc roster ... | drive <npc> <player> | drive <npc> stop |
--   fullrec <entity> [s] | look <entity> | near <x> <y> <z> [r] | remove <entity> | and the test commands in F.setup
-- Logs "companions: ..." in emf\emf_core.log.

F = { id = "companions", title = "Companions" }  -- (0.15.362: was npc_probe)
-- (owner 2026-11-20 18:11 "I'm afraid some of the clean up will make it harder to debug and fix future errors ... I
-- don't want to limit myself on that": debug tools are never removed, only switched off) the companion debug log: the
-- detailed lines (F.DEBUG_ONLY) only while it is on (console "flamekit.npc debug on|off"; saved; companion_debug.txt
-- beside FlameKit tells the server probe too). Off: errors, can't follow, put away / back, fights' start and end,
-- kills, heals, the roster, joins.
F.debug = false
F.DEBUG_ONLY = { "^crumbs ", "^waterlog ", "^slide ", "^slot ", "^gap ", "^settle ", "^pace ", "^edge ", "^dive ", "^air ",
  "^jump follow ", "^leap ", "^load: ", "^hop: ", "^HIT ", "^fight [^:]*: his ", "^fight [^:]*: bite ", "^fight [^:]*: lunge ",
  "^fight [^:]*: waits", "^fight [^:]*: [0-9]+ slowed", "^fight [^:]*: try ", "^fight [^:]*: picks again", "^fight [^:]*: last 10 s",
  "^fight scan:", "^fight [^:]*: mana/healing", "^drive [0-9]+: switch", "^names: '[^']*' %(0x[0-9A-F]+%) is in" }
function log(s)
  if not F.debug then
    for _, p in ipairs(F.DEBUG_ONLY) do if s:find(p) then return end end
  end
  emf.log("companions: " .. s)
end
function say(world, player, text, colour)
  pcall(function() require("features.chat").notice_to(world, player, text, colour or "#8cd2ff", 5) end)
end

-- a notice in the player's Notices window that stays until it is taken back (clear = true): the stuck and death
-- notices stay on the screen until the condition is over (client: npc_wheel_probe.lua)
-- (owner 2026-11-20 16:20) the "can't follow" notices only for players who switched them on (the client's Experimental
-- tab, Debug: "Companion follow notices", default off; it sends op "prefs" on npcwheel): account -> true
function F.set_debug(on)
  F.debug = on and true or false
  pcall(function() require("core.store").save("companion_debug", { on = F.debug }) end)
  local path = emf.dir and (emf.dir .. "\\companion_debug.txt")
  if path then
    if F.debug then
      local f = io.open(path, "w")
      if f then f:write("on\n") f:close() end
    else
      os.remove(path)
    end
  end
  emf.log("companions: companion debug log " .. (F.debug and "on" or "off"))
end
F.notice_pref = {}
function F.follow_notices(world, player)
  local ok, acc = pcall(world.account, world, player)
  return ok and acc and F.notice_pref[acc] == true or false
end

function status(world, player, tag, text, colour)
  if not player then return end
  local msg = text and { op = "status", tag = tag, text = text, colour = colour } or { op = "status", tag = tag, clear = true }
  pcall(emf.net.send_to, world, player, "npcwheel", emf.json.encode(msg))
end
