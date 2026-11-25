-- features/spawn_nodes.lua: the Spawn Nodes system (raids). Started 0.15.476 (owner 2026-11-23 10:53 "I'd like a way to
-- place down "nodes" around the map that could be configured to spawn monsters periodically based on how I set it up",
-- 11:06 "can you group the nodes together ... multiple different groups with multiple different nodes", 11:08 "all 5 of
-- those triggers would be good ... lets go ahead and build it"); monster tracking rewritten 0.15.526.
--
-- ==== WHAT IT IS (as the code works in 0.15.547; the sections below hold the details and the owner's words) ====
-- A NODE is only a saved place (x, y, z, facing, its own "Spawn within" distance) that belongs to a GROUP; nothing of it
-- is in the game world. Only the monsters it spawns are real: ordinary monsters of the game (not FlameKit's test
-- monsters), each tagged with its group in a ScaleComponent (TAG_BASE - group * TAG_STEP: 0.996, 0.99598, ...; the test
-- monsters' tag is 0.999) so a reload or restart finds them again (scan_tick).
-- At most MAX_GROUPS (30) groups and MAX_NODES (200) nodes on the server, all groups together.
--
-- A GROUP's settings (DEFAULTS; the drop-down choices in CHOICES), by the tab's sections:
--   Raid rules: on (Group on: off = its trigger never fires; Start now still works), announce (the notices), mark (Raid
--     monster markers), spare (its monsters' hits on anything but players do nothing: FlameKit Native's spare list),
--     protect (players near its nodes lose the game's base editing permission and players' hits on placed objects do
--     nothing, while it runs), breaks + break_level (its monsters hit player-built blocks).
--   Monsters: family (a monster group of core/monsters.lua, Random, or Bosses), face (which way a new monster faces),
--     per_wave (monsters per node per wave, spawned one by one), max_alive (most alive per node at once),
--     start_level (1-100, default 1) + level_step (added per wave after the first; never above K.MAX_LEVEL 100),
--     loot (normal / reward / both / none: see K.on_death).
--   When: trigger (manual = Start now only; timer = a random time between timer_min and timer_max minutes; wire = a
--     player within wire_r m of its trip wire; time = the game's clock passes `hour`; raid = a player inside a flame
--     altar area whose middle is within raid_r m of one of its nodes), start_delay (the first monsters come this long
--     after the start notice), near_r (a group starts, and its waves come, only while a player is within this of one of
--     its nodes), waves, wave_dead (the Between waves time starts only when this share of the last wave is dead; 0 = when
--     it has spawned), wave_gap (Between waves, s), duration (the raid ends after this many minutes, its living monsters
--     taken away; 0 = no limit), cooldown (minutes before its trigger can fire again; Start now ignores it).
--
-- A RAID: fire() starts a run (waves); wave() gives each node per_wave monsters to spawn; trickle_tick queues them one by
-- one while fewer than max_alive of the node's are alive; spawn_tick spawns them (on the ground within the node's
-- distance, find_surface). The roster S.mon (mon_add / mon_check every 0.25 s) is the only count of who is alive: its
-- own monsters, and "counted apart" ones (summons and monsters of the world that come into the raid: join_tick /
-- try_join; never players, FlameKit's test monsters or loot chests). raid_tick sends the notices (the red start notice
-- with the place from the starter's minimap, wave notices, "N of TOTAL monsters left to kill" from the first monster on,
-- updated as they die (left_tick), the end) and ends the raid when nothing of it is alive for END_GRACE s and a search of
-- the whole world found none (verify_tick). Stop ends the waves; Remove takes the group's monsters and bodies away.
-- While a raid runs: THE ANIMAL HOLD (below), Raid monster markers on every player's game (mark_tick, at most
-- K.MARK_BUDGET messages per check), the raid lock / protection / spare files for FlameKit Native.
--
-- WHO: since 0.15.546 (owner 2026-11-24 08:43 "remove all the admin restrictions ... so other players can test it out")
-- EVERY PLAYER counts as an admin here (is_admin returns true; admins.is is named there to restrict it again).
-- WHERE IT IS SHOWN: the Spawn Nodes tab (F.panel: the group's settings) and, since 0.15.539, the Spawn Nodes window
-- (F.window_rows: group, Start / Stop / Remove, Add node here, Show nodes, Put trip wire here, the nearest nodes), drawn by
-- FlameKit Native from features/native_ui.lua. "Show nodes" (this game's own switch, spawn_nodes_client.json) shows
-- every node and trip wire as markers in that game only.
-- THE CHANNEL "nodes": a player's game asks {op = "get"}; the server answers {op = "state", admin, groups, nodes, status,
-- note, ...}; clicks send {op = new_group, delete_group, set, start, stop, remove, add_node, move_node, delete_node,
-- node_spread, wire_here}; the server sends {op = notice} (a raid notice and its siren) and {op = place_ask} (where are
-- you, by your minimap), answered {op = place}. In a game that hosts the world everything is done right here.
--
-- KEPT (kit.store, on the server): spawn_nodes.json = the groups (with each group's last raid end: its cooldown, since
-- 0.15.547) and nodes; spawn_nodes_raid.json = the running raids and runs, taken back after a FlameKit reload in the same
-- world run (restore; a server restart ends them: another session token). Files for FlameKit Native in this folder:
-- raid_lock_server.txt, raid_protect_server.txt, spare_server.txt, animal_hold_server.txt (and it reads
-- altar_areas_server.txt, base_names_server.txt, where_now.txt).
--
-- (0.15.553, owner 12:33 "clean these up") the 2026-11-23 path investigation's test code is gone: the path census, the
-- AI log (ai_tick), the full recordings (core/fullrec.lua) and the path push. HUNT_ON and THREAT_ON stay on: they are
-- what sends each raid monster at the nearest player (hunt_tick), not logging. STUCK_ON stays off.
-- This file is at Lua's 200 top-level locals: newer constants and modules are in the table K.
--
-- ==== HISTORY NOTES (what each part was added for; the code below has the details) ====
-- (0.15.478) Two raid switches per group: "Monsters damage buildings" (break_tick) and the protection (protect_tick);
-- (0.15.482, owner 12:36 "we need an option to protect animals and pets from damage to" and Remove "by node group ...
-- including the dead ones on the ground") "Monsters spare animals, pets and villagers" (0.15.525: FlameKit Native's
-- spare list, spare_tick; until 0.15.524 an EMF hit rule that also kept them from hurting other monsters) and Remove takes
-- the group's dead bodies too; (0.15.479) the players near its nodes lose the game's base editing permission while it runs
-- (raid_lock_server.txt, FlameKit Native); (0.15.484, owner 12:50) its label "Players cannot damage base structures during raid".
-- (0.15.538) !!! THE ANIMAL HOLD, every raid, always on: from a raid's start until it is over, tamed animals ask the
-- game for no walks and stand still (animal_hold_server.txt -> FlameKit Native). WITHOUT IT RAID MONSTERS STAND
-- AROUND FOR A MINUTE OR MORE: the animals' failing walk searches fill the game's one path search (measured
-- 2026-11-23: monsters unsearched 54-89 s with the animals walking, 0-4 s with them held). See hold_write. !!!
-- Uses only core modules (HANDOFF rule 0b).

local admins = require("core.admins")
local players = require("core.players")
local monsters = require("core.monsters")
local threat = require("core.threat")  -- (0.15.522)
-- (0.15.547) this file is at Lua's 200 top-level locals: newer constants and modules go in K
local K = {
  MARK_BUDGET = 30,      -- (0.15.541) marker messages per check (07:52: 32 in one check all arrived, the 40th and later did not)
  MARK_OFF_TRIES = 15,   -- (0.15.541) a marker take-off is tried this many checks (30 s) at most
  HOLD_FILE = "\\animal_hold_server.txt",  -- (0.15.538) the animal hold (see hold_write)
  HOLD_BEAT_S = 5,       -- rewritten this often while held (FlameKit Native lets go after 30 s without it)
  HOLD_MAX_S = 30 * 60,  -- never held longer than this in one go
  LEFT_MIN_STEPS = 30,   -- (0.15.544) the countdown changes at most every 0.5 s
  MAX_LEVEL = 100,       -- (0.15.547, owner 09:41 "the max level of any monster can only be 100")
  set_level = require("core.spawn").set_level,  -- (0.15.547) a monster's level (shared with the test monsters)
  reward = require("core.reward_loot"),         -- (0.15.547) Spawn Nodes' own Reward loot (the test monsters have their own: kept separate)
  skip = require("core.loot_skip"),             -- (0.15.547) tells Auto Loot (loot_drop) to leave a body alone
  test_tag = require("core.test_tag"),          -- (0.15.547) FlameKit's test monsters: never join a raid
  chests = require("core.loot_chest"),          -- (0.15.547) FlameKit's loot chests: never join a raid
}

-- (0.15.550, owner 12:04) enabled_setting "sn_enabled": the "Spawn Nodes" switch in the Settings tab's Features section.
-- Off in a player's game: no Spawn Nodes tab or window there, and none of its notices or sounds. Off on the server
-- (sn_enabled=0, see below): no raid starts and nothing of it
-- runs; F.switched_off ends the running raids and lets go of the files FlameKit Native reads (see there). The server
-- has no Settings tab: its value is the default (on) unless set in its own copy of FlameKit's settings (the game keeps
-- them in emf\config\flamekit.ini; that the server reads the same file there is NOT tried yet).
local F = { id = "spawn_nodes", title = "Spawn Nodes", enabled_setting = "sn_enabled" }
local kit

local CHANNEL = "nodes"
local ASK_STEPS = 120          -- the player's game asks for the state every 2 s while the tab may show
local ASK_STEPS_PLAYER = 1800  -- a player who is not an admin: every 30 s (he becomes one: seen within 30 s)
local CHECK_STEPS = 60         -- the triggers are checked every second
local CLEAN_STEPS = 120        -- dead or gone monsters are forgotten every 2 s (0.15.515: deaths every FAST_STEPS)
local FAST_STEPS = 15          -- (0.15.515) 0.25 s: deaths seen, the next monster queued, spot checks timed out
local SPAWN_PER_STEP = 4       -- monsters spawned in one server step at most (the rest on the next steps)
local MAX_NODES = 200          -- nodes on the server at most
local MAX_GROUPS = 30          -- groups at most
local SPREAD = 10              -- m: monsters spawn within this of their node (the default; (0.15.485) each node its own)
-- (0.15.485, owner 12:49 "is there a setting to control the spawn radius of the monster near the node and make this a
-- per node setting? ... is it possible to make sure the monster does [not] spawn into an object, terrain or a wall?"):
-- each node's "Spawn within" (node.spread, m), and SPOT_TRIES random spots looked at before one is used: a spot is
-- refused when a building block or terrain a player placed is on the line from the node to it (emf.find_wall, 1 m up),
-- a building block is at it (1 m and 2 m up), or the ground is solid at both SOLID_UP heights over the node's height
-- (a rock or cliff). All refused: the monster appears on the node itself. Not seen: placed objects (chests and the like).
local SPREADS = { 0, 2, 5, 10, 15, 20, 30 }
local SPOT_TRIES = 8
-- (0.15.493, owner 14:30 "I can't find the last monster is it stuck in terrain", 14:32 "I thought your code was doing
-- that making sure the monsters were already spawning above ground? any monster then ends up in the ground or in water
-- or in an object needs to get respawned") 0.15.485 only refused rock at 1.5 m and 3 m over the node's height, so a
-- spot on rising ground (the ground 0.5-1.5 m higher) passed: the monster appeared in the ground and the game's ground
-- search (core/spawn.lua) did not get it out. Now each spot's ground is found (find_surface: from 2 m under the node's
-- height up to SURFACE_UP over it, the first place with solid ground under it and 2 m of air above it) and the
-- monster appears on it; no ground: the spot is not used. And every 2 s each living monster is checked (stuck_tick):
-- in the ground (solid at 0.6 m and 1.4 m over its feet), in water (swimming or under water), or stuck (not 1 m away
-- from where it was STUCK_S seconds ago and no hit given or taken in that time): it is taken away and a new one comes
-- at its node (at most RESPAWN_MAX per node in one raid, then it is only taken away).
local SURFACE_UP = 12
local STUCK_BORN = 5            -- s: (0.15.513: 10; 0.15.516, owner 16:49 "didnt I fucking say 5 seconds earlier?": the
                               -- 10 s grace I added overrode his 5 s) a monster is not looked at as stuck before this age
local STUCK_S = 5  -- (0.15.510, owner 16:13 "30 seconds is wayyy too long", "make it like 5"; was 30; looked at every 2 s)
local STUCK_NEAR = 40          -- m: (0.15.496: 25 monsters were taken away as "stuck" at 14:43-14:46 while they only stood
                               -- waiting, the player more than 50 m away) only a monster with a player this near can be stuck
local RESPAWN_MAX = 10
local WATER_DEPTH = 0.8        -- m: (0.15.497) a monster this deep in water is taken away and comes again out of it
local WET_R = 4                -- m: a spot this close to where a monster was found in water is not used again
-- (0.15.505, owner 15:48 "monsters that fall into the water still are not respawning. also many monsters are still
-- getting stuck in fences and objects": the game's submerge depth stayed 0 for monsters in the water (none logged one),
-- and the monsters at nodes 2 and 3 were stuck 30-68 s at their node again and again, behind the fences) A monster more
-- than FALL_M m under its node's height while no player is down there with it fell (into the water or a drop). A fallen,
-- stuck, buried or wet monster is first moved next to the nearest player within MOVE_NEAR m (a spot 4-8 m from him on
-- the ground, nothing built between them), at most MOVE_MAX times, then taken away and made again at its node. Where one
-- got stuck is not used for a spawn again (BAD_R m).
local FALL_M = 4
local MOVE_NEAR = 60
local MOVE_MAX = 3
local BAD_R = 3
local SOLID_UP = { 1.5, 3.0 }
local ACTIVE_DIST = 100        -- m: (0.15.491) now only how far a monster looks for the player to face
local NEAR_LIST = 8            -- the tab lists this many nodes of the chosen group, nearest first
-- (0.15.478, owner 12:01 "that would be cool if monsters could damage structures, that would be an option for that mode",
-- "prevent players from damaging structures while the raid is active", 12:03 "yes research both we need that setting")
local BREAK_STEPS = 30         -- the building damage is looked at every half second
local BREAK_LOOK = 64          -- m: the nearest player it looks toward (EMF's find_wall: a line of at most 64 m)
local BREAK_MAX = 15           -- hits per half second for all groups together (30 a second; EMF runs 8 breaks a step)
-- (0.15.481, owner 12:26 "anyway to make that more agressive?", 12:27 "yes" to these levels, "high should be the default IMO"):
-- how often each monster hits (server steps), how hard (times the game's top pickaxe: 100, 100, 95, 60, 50 per hardness
-- class), how far (m) and how big a hole (m)
local PICKAXE = { 100, 100, 95, 60, 50 }
local BREAK_LEVELS = { "low", "medium", "high", "extreme" }
local BREAK_LEVEL = {
  low = { every = 180, mult = 1, reach = 4, radius = 1, label = "Low: a hit every 3 s" },
  medium = { every = 90, mult = 2, reach = 5, radius = 1, label = "Medium: every 1.5 s, twice as hard" },
  high = { every = 60, mult = 4, reach = 6, radius = 1.5, label = "High: every 1 s, 4 times as hard" },
  extreme = { every = 30, mult = 8, reach = 6, radius = 1.5, label = "Extreme: every 0.5 s, 8 times as hard" },
}
local NEAR_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }  -- where a monster with no player in reach looks for a wall
-- (0.15.483, owner 12:42 "Players should not be able to damage structures while there are monsters from the raid still
-- alive. If you made a bug that violates this than fix it.": a reload of FlameKit on the server forgot the raid's
-- monsters, so the protection ended at once) Every monster a node spawns carries its group in a ScaleComponent tag:
-- uniformScale = TAG_BASE - group * TAG_STEP (not visible; the test monsters' tag is 0.999, core/test_tag.lua). After a
-- reload (or a new world) FlameKit scans the world for them (SCAN_BUDGET seconds a step at most) and knows them again,
-- alive or dead; until that scan is done the protection stays as it was (the raid lock file is not touched).
local TAG_BASE, TAG_STEP = 0.996, 0.00002
local SCAN_BUDGET, SCAN_MAX = 0.02, 3000   -- s and entities per server step for that scan
local clock_ok, clock = pcall(function() return os.clock end)
if not (clock_ok and type(clock) == "function" and pcall(clock)) then clock = nil end
-- (0.15.556, owner 2026-11-24 21:36 "is there a way to stagger them briefly so the server doesn't crash out?": G-Portal
-- 20:51 and 21:17, EMF paused FlameKit, "the script ran longer than 250 ms") A TIME LIMIT PER SERVER STEP: Spawn Nodes'
-- tick stops its work for this step once it has used K.STEP_BUDGET s (os.clock); what is left waits for the next steps:
-- the queued spawns stay queued (spawn_tick: one always), hunt_tick goes on next time where it stopped (K.hunt_i), and
-- the once-a-second checks (triggers, protection, hold, spare, raid ends, persist) wait one step (never two in a row). K.part times each part; a step over K.SLOW_S is logged with the time of each part (at most K.SLOW_LOG lines),
-- so the next slow step shows what took the time.
K.STEP_BUDGET, K.SLOW_S, K.SLOW_LOG = 0.08, 0.05, 200
function K.over() return clock ~= nil and K.t0 ~= nil and clock() - K.t0 > K.STEP_BUDGET end
function K.part(name, fn, ...)
  if not clock then return fn(...) end
  local t = clock()
  -- (0.15.557: the 21:45 pause logged nothing: EMF stops the script before the step's end) once the step is slow, the
  -- part about to run is logged BEFORE it runs, and a part over K.SLOW_S right after it
  if K.t0 and t - K.t0 > K.SLOW_S and (K.slow_n or 0) < K.SLOW_LOG then
    K.slow_n = (K.slow_n or 0) + 1
    emf.log(string.format("spawn nodes: slow step: %.0f ms used, now: %s", (t - K.t0) * 1000, name))
  end
  local a, b = fn(...)
  local took = clock() - t
  K.times[#K.times + 1] = string.format("%s %.0f", name, took * 1000)
  if took > K.SLOW_S and (K.slow_n or 0) < K.SLOW_LOG then
    K.slow_n = (K.slow_n or 0) + 1
    emf.log(string.format("spawn nodes: slow step: %s took %.0f ms", name, took * 1000))
  end
  return a, b
end
-- (0.15.488, owner 13:32 "would there be a way to announce a message that a raid has begun, and then announce each
-- wave of monster? and then also announce periodically how many monsters are left to kill? ... say where its near",
-- 13:33 "they should be notice messages put in orange maybe?", 13:36 "yes and when a new wave happens it could say
-- something like "New incoming wave at Melissa's Hideout!"") FlameKit notices (orange, the Notices window and a line in
-- the Messages window), per group switch "announce" (on by default). The start, the end and a Remove go to every player;
-- the waves and the count of monsters left to the players within NOTICE_DIST m of one of the group's nodes. The place:
-- see raid_place (the minimap's place of the player who started or triggered it).
local NOTICE_COLOUR = "#ff9632"  -- (0.15.545: the start notice is red, "#ff4040" in raid_tick; this file is at Lua's 200 locals)
local NOTICE_DIST = 300
local PLACE_WAIT = 180         -- steps (3 s): how long the start notice waits for the asked player's place
local LEFT_EVERY = 30          -- s: the "monsters left" notice is refreshed at least this often while the raid lasts
-- (0.15.544) LEFT_MIN_GAP (5 s) gone: K.LEFT_MIN_STEPS (0.5 s), next to count_notice
local END_GRACE = 10           -- s: (0.15.500) a raid is over when none of its monsters is alive for this long
local START_END_S = 60         -- s: (0.15.494, owner 14:35 "the beginning raid notice and the end raid notice needs to stay up
                               -- longer.. I never even saw the end raid notice") the start and end notices stay this long (was 15)
local MISSES = 3  -- (0.15.483) a monster whose health can't be read is forgotten only after this many checks in a row

-- (0.15.477, owner 11:27 "it would be nice if I could have a monster group for bosses as well so I could have one node
-- spawn a boss") "Bosses": any of the bosses (core/monsters.lua's 26), the only type with bosses in it
local FAMILIES = { "Random", "Ancients", "Beasts", "Drak", "Scavengers", "Shroud", "Undead", "Vukah", "Bosses" }
local FAMILY_LABEL = { Shroud = "Shroud (Fell)", Bosses = "Bosses (any)" }
local TRIGGERS = { "manual", "timer", "wire", "time", "raid" }
-- (0.15.477, owner 11:37 "is there a way I can control which direction the monsters face when they spawn? one of the
-- faced away from the base") which way a spawned monster faces: the nearest player, the node's own direction (the way
-- the admin faced when he added or moved it), or random
local FACES = { "player", "node", "random" }
local FACE_LABEL = { player = "The nearest player", node = "The node's direction", random = "Random" }
local TRIGGER_LABEL = { manual = "Manual (Start now)", timer = "Timer", wire = "Trip wire", time = "Time of day", raid = "Base raid" }
-- the choices of each drop-down (the units in UNIT)
local CHOICES = {
  waves = { 1, 2, 3, 5, 10 }, per_wave = { 1, 2, 3, 5, 8, 10, 15 }, wave_gap = { 0, 5, 10, 20, 30, 60, 120, 300 },  -- (0.15.519, owner 17:18: 0 and 5 added)
 
  max_alive = { 1, 2, 3, 6, 10, 20, 40 },  -- (0.15.503, owner 15:30: 1 and 2 added)
  cooldown = { 1, 2, 5, 10, 15, 30, 60 }, timer_min = { 1, 2, 5, 10, 15, 30, 60, 120 },
  timer_max = { 1, 2, 5, 10, 15, 30, 60, 120 }, wire_r = { 5, 10, 20, 30, 50 }, hour = { 0, 6, 12, 18, 20, 22 },
  raid_r = { 50, 100, 150, 250, 400 },
  near_r = { 20, 30, 50, 75, 100 },  -- (0.15.491)
  duration = { 10, 15, 20, 30, 45, 60, 90, 0 },  -- (0.15.492) min; 0 = no limit
  wave_dead = { 0, 50, 75, 90, 100 },  -- (0.15.542) % of a wave dead before Between waves starts; 0 = when it has spawned
  start_delay = { 0, 5, 10, 15, 20, 30, 60 },  -- (0.15.543) s from the start notice to the first monster
  -- (0.15.547, owner 09:41) the level of its monsters: start_level; level_step: added for each wave after the first
  -- (owner's list; 40 added, taken for a slip: "... 30, 35, 45, 50 ..."); never above K.MAX_LEVEL (100).
  -- (0.15.548, owner 11:38 "get rid of "Game's own" entry and just default it to 1"; 11:27 "I've never seen "the game"
  -- ever spawn anything but a level 1 monster") no "Game's own" (0) any more: a saved 0 is read as 1 (group())
  start_level = { 1, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100 },
  level_step = { 0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 70, 80, 90, 100 },
  -- (0.15.547, owner 09:45 "reward loot (exactly like how test monsters work), normal monster loot, and/or no loot ...
  -- any combination"; 09:45 "if the player chooses no loot, it drops nothing") what its monsters drop: the game's own
  -- loot / Reward loot (runes to the killer's bag, a legendary item to a chest) / both / nothing (K.on_death)
  loot = { "normal", "reward", "both", "none" },
}
local UNIT = { start_delay = "s", wave_gap = "s", cooldown = "min", timer_min = "min", timer_max = "min", wire_r = "m", raid_r = "m", near_r = "m", duration = "min" }
local DEFAULTS = { announce = true, mark = true, on = true, family = "Random", trigger = "manual", face = "player", breaks = false, break_level = "high", protect = false, spare = true, waves = 3, per_wave = 3, wave_gap = 30, max_alive = 6,
  cooldown = 10, wave_dead = 90, start_delay = 20, start_level = 1, level_step = 0, loot = "reward", timer_min = 10, timer_max = 20, wire_r = 20, hour = 20, raid_r = 150, near_r = 50, duration = 30 }
local COLOURS = { 0xff6040ff, 0x40c0ffff, 0xffd040ff, 0x80ff60ff, 0xd070ffff, 0xff80c0ff, 0x60ffe0ff, 0xffa040ff }

-- The monsters of each type (no bosses), from core/monsters.lua: type -> { template GUID, ... }; "Random": all of
-- them; "Bosses": only the bosses.
local POOL = { Random = {}, Bosses = {} }
for _, m in ipairs(monsters) do
  if m[4] then
    table.insert(POOL.Bosses, m[3])
  else
    POOL[m[1]] = POOL[m[1]] or {}
    table.insert(POOL[m[1]], m[3])
    table.insert(POOL.Random, m[3])
  end
end

-- A drop-down value as text ("30 s", "10 min", "20:00").
local function label(key, v)
  if key == "hour" then return string.format("%02d:00", v) end
  if key == "duration" and v == 0 then return "No limit" end  -- (0.15.492)
  if key == "start_level" then return "Level " .. tostring(v) end  -- (0.15.547; 0.15.548 no "Game's own")
  if key == "level_step" then return v == 0 and "No increase" or ("+" .. v .. " each wave") end
  if key == "loot" then return ({ normal = "Normal monster loot", reward = "Reward loot", both = "Reward + normal loot", none = "No loot" })[v] or tostring(v) end
  if key == "wave_dead" then return v == 0 and "It has spawned" or v == 100 and "All of it is dead" or (v .. "% of it is dead") end  -- (0.15.542)
  return tostring(v) .. (UNIT[key] and (" " .. UNIT[key]) or "")
end

-- ---- the server's half ----

local S = { data = nil, steps = 0, runs = {}, queue = {}, last_end = {}, next_timer = {}, last_tod = {},
            notes = {}, session = nil, protect_rule = nil, no_break = nil, broke = {},
            mon = {}, old_bodies = {}, scan = nil, scanned = false, raid = {}, place_answers = {}, place_q = 0, started = {}, track = {}, active_at = {}, respawns = {}, marked = {}, wet = {}, depth_said = {}, sub_said = {}, join_hits = {}, join_seen = nil, orders = {}, bad = {}, join_wait = {}, checks = {}, hunt_pos = {}, halted = {}, threat_seen = {}, hitby = {} }  -- (0.15.547) hitby: monster -> the last player who hit it  -- (0.15.492) started: gid -> os.time() of its start  -- (0.15.483) scan, scanned; (0.15.488) raid; (0.15.526) mon, old_bodies: the roster (below)

-- The saved groups and nodes (spawn_nodes.json), loaded once.
local function data()
  if not S.data then
    local ok, d = pcall(kit.store.load, "spawn_nodes", nil)
    d = (ok and type(d) == "table") and d or {}
    d.groups = type(d.groups) == "table" and d.groups or {}
    d.nodes = type(d.nodes) == "table" and d.nodes or {}
    d.next_g = tonumber(d.next_g) or 1
    d.next_n = tonumber(d.next_n) or 1
    S.data = d
  end
  return S.data
end

local function save()
  local ok, why = pcall(kit.store.save, "spawn_nodes", data())
  if not ok then emf.log("spawn nodes: spawn_nodes.json could not be saved (" .. tostring(why) .. ")") end
end

-- Group `gid` (a number) or nil; its settings filled in with the defaults.
local function group(gid)
  local g = data().groups[tostring(gid)]
  if not g then return nil end
  for k, v in pairs(DEFAULTS) do if g[k] == nil then g[k] = v end end
  if g.start_level == 0 then g.start_level = 1 end  -- (0.15.548) "Game's own" (0) is gone: level 1
  return g
end

-- The groups in their order (by id).
local function groups()
  local list = {}
  for _, g in pairs(data().groups) do list[#list + 1] = g end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

-- The nodes of group `gid`.
local function nodes_of(gid)
  local list = {}
  for _, n in pairs(data().nodes) do if n.g == gid then list[#list + 1] = n end end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

local function node_count()
  local n = 0
  for _ in pairs(data().nodes) do n = n + 1 end
  return n
end

-- The players in the world with their positions: { { id, x, y, z } }.
local function player_spots(world)
  local list = {}
  for _, id in ipairs(players.ids(world)) do
    local oka, acc = pcall(world.account, world, id)
    if oka and acc then
      local ok, x, y, z = pcall(world.position, world, id)
      if ok and x then list[#list + 1] = { id, x, y, z } end
    end
  end
  return list
end

local function dist2(ax, ay, az, bx, by, bz)
  local dx, dy, dz = ax - bx, ay - by, az - bz
  return dx * dx + dy * dy + dz * dz
end

-- The yaw (degrees, 0 north (+z), 90 east (+x)) from x, z toward tx, tz.
local function yaw_to(x, z, tx, tz)
  return math.deg(math.atan(tx - x, tz - z)) % 360
end

-- The way entity `id` faces (its transform's forward), as a yaw; nil when not known.
local function facing(world, id)
  local yaw = nil
  pcall(function()
    local q = world:get("CurrentTransform", id).transform.orientation
    local ax, az = 2 * (q.x * q.z + q.w * q.y), 1 - 2 * (q.x * q.x + q.y * q.y)
    if ax * ax + az * az > 0.0001 then yaw = math.deg(math.atan(ax, az)) % 360 end
  end)
  return yaw
end

-- The nearest player to x, y, z within `r` m: its x, z, or nil.
local function nearest_player(spots, x, y, z, r)
  local best, bx, bz = r * r, nil, nil
  for _, p in ipairs(spots) do
    local d = dist2(p[2], p[3], p[4], x, y, z)
    if d <= best then best, bx, bz = d, p[2], p[4] end
  end
  return bx, bz
end

-- Whether a player is within `r` m of x, y, z.
local function player_near(spots, x, y, z, r)
  for _, p in ipairs(spots) do
    if dist2(p[2], p[3], p[4], x, y, z) <= r * r then return true end
  end
  return false
end

-- The flame altar areas (altar_areas_server.txt, written by FlameKit Native: "x0 y0 z0 x1 y1 z1" per line), read
-- again at most every 10 s.
local altar_cache = { at = -100, boxes = {} }
local function altar_boxes()
  if os.time() - altar_cache.at < 10 then return altar_cache.boxes end
  local boxes = {}
  local f = io.open(emf.dir .. "\\altar_areas_server.txt", "r")
  if f then
    for line in f:lines() do
      local v = {}
      for num in line:gmatch("%-?[%d%.]+") do v[#v + 1] = tonumber(num) end
      if #v >= 6 then boxes[#boxes + 1] = v end
    end
    f:close()
  end
  altar_cache = { at = os.time(), boxes = boxes }
  return boxes
end

-- ---- (0.15.526) THE ROSTER: the one place that knows the raids' monsters ----
-- (owner 2026-11-23 18:59 "yes": rewrite the monster tracking. Until 0.15.525 six things each decided on their own
-- whether a monster was a raid's (S.alive per node, S.dead, S.adopted, the scale tag, the area test, the end check) and
-- they disagreed: at 18:51:24 seven bodies "got up again" with 4-6 health and the count went 1 -> 8 of 60, and for a
-- minute (18:47:43-18:48:43) no node spawned because "Most alive per node" counted bodies that got up and monsters that
-- had joined.) Now every monster of a raid is one entry S.mon[id] = { g = group, n = node, own, dead, born, seen,
-- lost_at, miss }:
--   own   = its node spawned it in this raid: it holds that node's "Most alive per node" place and is in "N of TOTAL";
--   not own = it joined (a summon, a monster of the world that came in), it got up again after it died, or it is left
--           from an earlier raid: it never holds a node's place and never raises N, but the raid ends only when it is
--           dead too ("... summoned monsters still to kill").
-- mon_check (every 0.25 s) is the only thing that reads their health and moves an entry between alive and dead.
-- Bodies of an earlier raid of the group are never looked at again (S.old_bodies: only Remove takes them away).
local RISE_S = 10      -- s: an own monster that has not had health yet (an Undead coming up) counts alive this long
local LOST_S = 10      -- s: a monster whose health can't be read is counted this long, then it is forgotten (logged)
local MISSES = 3       -- checks in a row with neither health nor position: gone, forgotten

-- Adds monster `id` to group `gid`'s raid at node `nid`. `why`: for the log.
local function mon_add(id, gid, nid, own, dead, why)
  if not id or S.mon[id] then return end
  S.mon[id] = { g = gid, n = nid, own = own == true, dead = dead == true, born = os.time(), seen = false, miss = 0 }
  if (S.mon_log or 0) < 300 then
    S.mon_log = (S.mon_log or 0) + 1
    emf.log(string.format("spawn nodes: roster: monster %s in group %d's raid at node %s: %s, %s (%s)", tostring(id), gid,
      tostring(nid), own and "its own" or "counted apart", dead and "dead" or "alive", tostring(why)))
  end
end

-- Forgets monster `id` (and what the off switches kept about it).
local function mon_drop(id)
  S.mon[id] = nil
  S.track[id], S.active_at[id], S.orders[id], S.threat_seen[id], S.hunt_pos[id] = nil, nil, nil, nil, nil
  if S.hitby then S.hitby[id] = nil end  -- (0.15.547)
  K.skip.set(id, false)  -- (0.15.547)
end

-- The ids of the living monsters, in id order: of group `gid` (nil: every group), of node `nid` (nil: every node),
-- only its own ones when `own_only`.
local function mon_alive(gid, nid, own_only)
  local list = {}
  for id, m in pairs(S.mon) do
    if not m.dead and (not gid or m.g == gid) and (not nid or m.n == nid) and (not own_only or m.own) then list[#list + 1] = id end
  end
  table.sort(list)
  return list
end

-- How many of node `nid`'s OWN monsters are alive: what "Most alive per node" counts.
local function alive_count(nid)
  return #mon_alive(nil, nid, true)
end

-- The dead bodies of group `gid` (this raid's and earlier ones'): for Remove and the tab.
local function mon_bodies(gid)
  local list = {}
  for id, m in pairs(S.mon) do if m.dead and m.g == gid then list[#list + 1] = id end end
  for id, g in pairs(S.old_bodies) do if g == gid then list[#list + 1] = id end end
  table.sort(list)
  return list
end

-- Whether monster `id` is known (in a raid, or a body of an earlier one).
local function known(id)
  return S.mon[id] ~= nil or S.old_bodies[id] ~= nil
end

-- (0.15.526) A new raid of group `gid` starts: the bodies of its earlier raids are put aside (never counted, never
-- looked at for getting up again: 18:22:44 eighteen of them "got up" and were counted back in), and any of its monsters
-- still alive from before is counted apart.
local function mon_new_raid(gid)
  local bodies, left = 0, 0
  for id, m in pairs(S.mon) do
    if m.g == gid then
      if m.dead then
        S.old_bodies[id] = gid
        mon_drop(id)
        bodies = bodies + 1
      elseif m.own then
        m.own = false
        left = left + 1
      end
    end
  end
  emf.log(string.format("spawn nodes: roster: group %d's new raid: %d bod(ies) of its earlier raids put aside, %d monster(s) still alive from before counted apart", gid, bodies, left))
end

-- ============================================================================================================
-- (0.15.547, owner 2026-11-24 09:41 "I need to be able to set the starting level of the monsters per group. I also need
-- to add a drop-down option that increases the level of the monsters with each new wave ... the max level of any monster
-- can only be 100 ... I would also like to add in the "reward loot" system like we build for the test monsters and this
-- should be configurable by group as well", 09:45 "reward loot (exactly like how test monsters work), normal monster
-- loot, and/or no loot ... if the player chooses no loot, it drops nothing") LEVEL AND LOOT, per group:
--   Starting level (start_level, 1-100) + Level per wave (level_step) x (wave - 1), at most K.MAX_LEVEL; set on every
--   monster its node spawns (core/spawn.lua set_level, as the test monsters).
--   Loot (loot): "normal" the game's own; "reward" Reward loot by the test monsters' rule, in Spawn Nodes' own code (owner
--   11:06: never connected to the test monsters' code) (core/reward_loot.lua give: runes and
--   legendary runes into the bag of the last player who hit it (S.hitby), a legendary item at its level into a loot
--   chest by the body, twice for Bosses; owner 10:47 "everything should end up in the chest except the runes ... regular
--   monster loot should never end up in these chests ever") and its game loot removed (never into a chest); "both" the reward and its game loot; "none" its game loot removed, nothing
--   given. Only monsters a node spawned (m.sp), once each (m.looted: one that gets up and dies again gives nothing more).
-- ============================================================================================================
K.level_spawned = function(world, id, gid, q)
  local g = gid and group(gid)
  if not g then return end
  local start, step = math.max(1, tonumber(g.start_level) or 1), tonumber(g.level_step) or 0
  local run = S.runs[gid]
  -- the wave it was queued in (the last wave's last monsters spawn after its run is over)
  local wave = (q and tonumber(q.wave)) or ((run and run.wave and run.wave > 0) and run.wave) or 1
  local base = start
  local lvl = math.min(K.MAX_LEVEL, math.max(1, math.floor(base + math.max(0, wave - 1) * step)))
  local ok, set = pcall(K.set_level, world, id, lvl)
  if S.mon[id] then S.mon[id].lvl = lvl end
  S.lvl_said = S.lvl_said or {}
  local key = tostring(gid) .. ":" .. tostring(wave) .. ":" .. tostring(S.started[gid] or 0)
  if not S.lvl_said[key] then
    S.lvl_said[key] = true
    emf.log(string.format("spawn nodes: %s wave %d: its monsters at level %d (starting level %d, %s, at most %d)%s", g.name, wave,
      lvl, start, step > 0 and ("+" .. step .. " each wave") or "no increase", K.MAX_LEVEL,
      (ok and set) and "" or " (FAILED to set: " .. tostring(set) .. ")"))
  elseif not (ok and set) then
    emf.log(string.format("spawn nodes: level: monster %s: setting level %d failed (%s)", tostring(id), lvl, tostring(set)))
  end
end
-- (0.15.547, owner 10:08 "fix that bug") marks monster `id` of group `gid` for Auto Loot (core/loot_skip.lua) when its
-- group's Loot removes the game loot itself (Reward loot, No loot): Auto Loot's first look (0.5 s after the death) came
-- before Spawn Nodes' removal (2 s) and moved the loot to a killer with Auto Loot on. Marked at the spawn, and again
-- for every living one when the group's Loot is changed.
K.mark_loot = function(id, gid)
  local g = gid and group(gid)
  local mode = g and g.loot or "normal"
  K.skip.set(id, mode == "reward" or mode == "none")
end
K.on_death = function(world, id, m)
  if not m.sp or m.looted then return end
  m.looted = true
  local g = group(m.g)
  local mode = g and g.loot or "normal"
  if mode == "normal" then return end
  local okp, x, y, z = pcall(world.position, world, id)
  if not (okp and x) then return end
  local said = {}
  if mode == "reward" or mode == "both" then
    local lvl = m.lvl
    if not lvl then pcall(function() local lv = world:get("Level", id) lvl = lv and lv.dataStorage and lv.dataStorage[1] end) end
    local ok, what = pcall(K.reward.give, world, x, y, z, S.hitby and S.hitby[id], lvl, g.family == "Bosses")
    said[#said + 1] = ok and tostring(what) or ("reward error: " .. tostring(what))
  end
  if mode == "reward" or mode == "none" then
    K.reward.clear_game_loot(world, id, x, z, y)
    said[#said + 1] = "its game loot removed"
  end
  S.loot_log = (S.loot_log or 0) + 1
  if S.loot_log <= 200 then emf.log(string.format("spawn nodes: loot (%s): monster %s: %s", mode, tostring(id), table.concat(said, "; "))) end
end

-- Every 0.25 s: each monster's health, read once. Health > 0: alive (a body that gets up again is counted apart from
-- now on); 0: dead (an own monster that never had health yet counts alive for RISE_S s: still coming up); not readable:
-- counted for LOST_S s, then forgotten; neither health nor position MISSES times in a row: gone.
local function mon_check(world)
  local now = os.time()
  for id, m in pairs(S.mon) do
    local okh, cur = pcall(emf.health, world, id)
    if not okh then cur = nil end
    if cur == nil then
      local okp, px = pcall(world.position, world, id)
      if not (okp and px) then
        m.miss = m.miss + 1
        if m.miss >= MISSES then
          if (S.mon_log or 0) < 300 then S.mon_log = (S.mon_log or 0) + 1 emf.log(string.format("spawn nodes: roster: monster %s gone from the world: forgotten", tostring(id))) end
          mon_drop(id)
        end
      else
        m.miss = 0
        m.lost_at = m.lost_at or now
        if now - m.lost_at >= LOST_S then
          emf.log(string.format("spawn nodes: roster: monster %s: its health could not be read for %d s: forgotten", tostring(id), LOST_S))
          mon_drop(id)
        end
      end
    else
      m.miss, m.lost_at = 0, nil
      if cur > 0 then
        if m.dead then
          m.dead, m.own = false, false
          emf.log(string.format("spawn nodes: roster: monster %s got up again (health %s): alive, counted apart (it does not hold node %s's place)", tostring(id), tostring(cur), tostring(m.n)))
        end
        m.seen = true
      elseif not m.dead then
        if m.own and not m.seen and now - m.born < RISE_S then
          -- still coming up out of the ground: alive
        else
          m.dead = true
          local okd, why = pcall(K.on_death, world, id, m)  -- (0.15.547) its loot, by the group's Loot
          if not okd then emf.log("spawn nodes: loot: " .. tostring(why)) end
          if (S.mon_log or 0) < 300 then
            S.mon_log = (S.mon_log or 0) + 1
            emf.log(string.format("spawn nodes: roster: monster %s died (%s, node %s)%s", tostring(id), m.own and "its own" or "counted apart", tostring(m.n),
              m.seen and "" or string.format(": never had health in %d s", RISE_S)))
          end
        end
      end
    end
  end
end

-- (0.15.483) The tag of group `gid`, and the group a tag names (nil: not one of ours).
local function tag_of(gid) return TAG_BASE - gid * TAG_STEP end
local function group_of_tag(v)
  if type(v) ~= "number" or v > TAG_BASE or v < TAG_BASE - 1000 * TAG_STEP then return nil end
  local gid = math.floor((TAG_BASE - v) / TAG_STEP + 0.5)
  if gid < 1 or math.abs(tag_of(gid) - v) > TAG_STEP * 0.3 then return nil end
  return gid
end

-- (0.15.483) One step of the world scan that finds the nodes' monsters again: each one tagged with a group that still
-- has nodes goes to that group's nearest node: alive into the roster, dead into S.old_bodies. True when the scan is done.
local function scan_tick(world)
  if not S.scan then
    -- the protection stays as it was meanwhile: the raid lock file is kept, and if it names players the rule against
    -- players' hits on placed objects comes back now (EMF dropped it with the old script)
    local f = io.open(emf.dir .. "\\raid_lock_server.txt", "r")
    local text = f and f:read("*a") or ""
    if f then f:close() end
    S.lock_text = text
    -- (0.15.486) the placed objects' protection is FlameKit Native's (raid_protect_server.txt): kept as it is too
    local pf = io.open(emf.dir .. "\\raid_protect_server.txt", "r")
    local pt = pf and pf:read("*a") or ""
    if pf then pf:close() end
    S.protect_on = pt:sub(1, 1) == "1"
    if text ~= "" or S.protect_on then
      emf.log("spawn nodes: loaded during a raid: its protection is kept while the raid's monsters are looked for")
    end
    S.scan = { i = 1, found = 0 }
    return false  -- the list in this step, the walk in the next ones (a big world has tens of thousands)
  end
  local sc = S.scan
  if not sc.list then
    local ok, list = pcall(world.entities, world)
    sc.list = ok and list or {}
    return false
  end
  local t0 = clock and clock() or 0
  local done = 0
  while sc.i <= #sc.list and done < SCAN_MAX and not (clock and clock() - t0 > SCAN_BUDGET) do
    local id = sc.list[sc.i]
    sc.i, done = sc.i + 1, done + 1
    local oks, scl = pcall(world.get, world, "ScaleComponent", id)
    local gid = oks and scl and group_of_tag(scl.uniformScale)
    local nodes = gid and nodes_of(gid)
    if nodes and #nodes > 0 then
      local okp, x, y, z = pcall(world.position, world, id)
      local best, nid = nil, nodes[1].id
      if okp and x then
        for _, n in ipairs(nodes) do
          local d = dist2(n.x, n.y, n.z, x, y, z)
          if not best or d < best then best, nid = d, n.id end
        end
      end
      local okh, cur = pcall(emf.health, world, id)
      if okh and cur and cur > 0 then
        mon_add(id, gid, nid, true, false, "found again after a reload")  -- (0.15.526) the roster
      elseif okh and cur then
        S.old_bodies[id] = gid  -- (0.15.526) a body: only Remove takes it away
      end
      sc.found = sc.found + 1
    end
  end
  if sc.i <= #sc.list then return false end
  emf.log(string.format("spawn nodes: world scan done: %d of the nodes' monsters found again (of %d entities)", sc.found, #sc.list))
  S.scan, S.scanned = nil, true
  -- (0.15.492) a raid found again after a reload: its time limit counts from now (its real start is not known)
  for _, g in ipairs(groups()) do
    if #mon_alive(g.id) > 0 then S.started[g.id] = S.started[g.id] or os.time() end
  end
  return true
end

-- (0.15.487, owner 13:14 "the remove monsters didn't remove them all... it removed some, but some are still flying
-- around") Remove also looks through the whole world for the group's tagged monsters, alive or dead, known or not, and
-- takes them away (a slice per step, as scan_tick). S.purge = { gids = { [gid] = name }, list, i, n }.
local raid_monster  -- (0.15.507) below (join_node, FRIENDLY)
local function purge_tick(world)
  local pg = S.purge
  if not pg.list then
    local ok, list = pcall(world.entities, world)
    pg.list, pg.i, pg.n = ok and list or {}, 1, 0
    return
  end
  local t0 = clock and clock() or 0
  local done = 0
  while pg.i <= #pg.list and done < SCAN_MAX and not (clock and clock() - t0 > SCAN_BUDGET) do
    local id = pg.list[pg.i]
    pg.i, done = pg.i + 1, done + 1
    local oks, scl = pcall(world.get, world, "ScaleComponent", id)
    local gid = oks and scl and group_of_tag(scl.uniformScale)
    if not gid then  -- (0.15.507) a monster of the group's raid area without the tag (a summon, a monster that came in)
      for g2 in pairs(pg.gids) do
        local gd = data().groups[tostring(g2)]
        local first = gd and tonumber(gd.last_first_id) or 0  -- not known (a raid before 0.15.507): every hostile one there
        local nid0 = raid_monster(world, g2, first, id, false)
        if nid0 then gid = g2 break end
      end
    end
    if not gid and (pg.near_n or 0) < 25 then
      -- (0.15.499, owner 14:50 "the remove all monsters doesn't work either": its search found none of the group's
      -- monsters while he still saw some) every living creature near the group's nodes that is NOT one of its
      -- monsters goes into the log: what it is, so the ones Remove leaves can be told apart
      local okp, x, y, z = pcall(world.position, world, id)
      if okp and x then
        for g2 in pairs(pg.gids) do
          for _, n in ipairs(nodes_of(g2)) do
            if dist2(x, y, z, n.x, n.y, n.z) <= 80 * 80 then
              local okh, cur = pcall(emf.health, world, id)
              local okpl, acc = pcall(world.account, world, id)
              if okh and cur and cur > 0 and not (okpl and acc) then
                pg.near_n = (pg.near_n or 0) + 1
                emf.log(string.format("spawn nodes: Remove: not one of its monsters, alive near node %d: entity %s at %.0f %.0f %.0f, health %s, scale %s",
                  n.id, tostring(id), x, y, z, tostring(cur), oks and scl and tostring(scl.uniformScale) or "none"))
              end
              break
            end
          end
        end
      end
    end
    if gid and pg.gids[gid] then
      if pcall(emf.destroy, world, id) then pg.n = pg.n + 1 end
      mon_drop(id)  -- (0.15.526)
      S.old_bodies[id] = nil
    end
  end
  if pg.i <= #pg.list then return end
  local names = {}
  for _, name in pairs(pg.gids) do names[#names + 1] = name end
  emf.log(string.format("spawn nodes: Remove's world search: %d more monster(s) or bod(ies) of %s taken away (%d entities looked at)",
    pg.n, table.concat(names, ", "), #pg.list))
  S.purge = nil
end

-- (0.15.488) The flame altars' names from FlameKit Native: { { x, y, z, name } }, read again at most every 10 s.
local names_cache = { at = -100, list = {} }
local function base_names()
  if os.time() - names_cache.at < 10 then return names_cache.list end
  local list = {}
  local f = io.open(emf.dir .. "\\base_names_server.txt", "r")
  if f then
    for line in f:lines() do
      local x, y, z, name = line:match("^(%-?[%d%.]+) (%-?[%d%.]+) (%-?[%d%.]+)\t?(.*)$")
      if x then list[#list + 1] = { tonumber(x), tonumber(y), tonumber(z), name or "" } end
    end
    f:close()
  end
  names_cache = { at = os.time(), list = list }
  return list
end

-- (0.15.490, owner 13:47 "Just use the nearest map marker for the raid location just like how the mini map uses it to
-- determine the players location", 13:56 "whoever starts the raid OR triggers the raid sends the list to the server",
-- 13:57 "just the one thats closest to the player with the raid is triggered or started") Where group `gid` raids: what
-- the minimap of the player who started or triggered it (else the player nearest its nodes) names as where he is (the
-- named place he is in or nearest to, a flame altar by its given name too; else his region). The dedicated server has no
-- place names of its own (no English texts in its data), so his game sends it when asked (`answer` = { place, region }).
-- No answer (an older FlameKit, or none within PLACE_WAIT): the nearest flame altar's name the server has itself
-- (base_names_server.txt), else nil.
local function raid_place(gid, answer)
  if type(answer) == "table" then
    if type(answer.place) == "string" and answer.place ~= "" then return answer.place:sub(1, 60) end
    if type(answer.region) == "string" and answer.region ~= "" then return answer.region:sub(1, 60) end
  end
  local best, name = nil, nil
  for _, a in ipairs(base_names()) do
    for _, n in ipairs(nodes_of(gid)) do
      local dx, dz = a[1] - n.x, a[3] - n.z
      local d = dx * dx + dz * dz
      if not best or d < best then best, name = d, (a[4] ~= "" and a[4] or "a Flame Altar") end
    end
  end
  return name
end

-- (0.15.488) A notice in player `pid`'s game (Spawn Nodes' own channel; the host's own game: directly). `tag`: a
-- notice with the same tag is changed in place (the count of monsters left), else each its own.
S.notice_n = S.notice_n or 0
-- (0.15.502, owner 15:14 "is there a way the game can play a siren or warning sound when the raid notice comes in?",
-- 15:15 "perfect") Plays sounds/<name>.wav in this game: FlameKit Native plays the file named in play_sound.txt
-- ("<n> <name>", n new each time) through Windows. Only with the player's setting "Raid siren" on.
local function play_sound(name)
  if kit.setting("raid_siren", true) ~= true then return end
  S.sound_n = (S.sound_n or 0) + 1
  local f = io.open(emf.dir .. "\\play_sound.txt", "w")
  if f then f:write(string.format("%d %s.wav\n", os.time() * 100 + S.sound_n % 100, name)) f:close() end
end

local function notice_to(world, pid, text, seconds, tag, sound, colour)
  S.notice_n = S.notice_n + 1
  local msg = { op = "notice", t = text, s = seconds or 10, tag = tag or ("raid_" .. S.notice_n), snd = sound, c = colour }  -- (0.15.545) c: its colour
  if pid == emf.local_player() and kit.is_host() then
    kit.notice("nodes_" .. msg.tag, text, colour or NOTICE_COLOUR, msg.s)
    if sound then play_sound(sound) end
  else
    pcall(emf.net.send_to, world, pid, CHANNEL, emf.json.encode(msg))
  end
end

-- (0.15.488) To every player (near = nil) or to the players within NOTICE_DIST m of group `near`'s nodes.
local function raid_notice(world, gid, text, near, seconds, tag, sound, colour)  -- (0.15.545) colour: "#rrggbb", else orange
  local g = group(gid)
  if not g or g.announce == false then return end
  emf.log("spawn nodes: notice: " .. text)
  for _, p in ipairs(player_spots(world)) do
    local ok = not near
    if near then
      for _, n in ipairs(nodes_of(gid)) do
        if dist2(p[2], p[3], p[4], n.x, n.y, n.z) <= NOTICE_DIST * NOTICE_DIST then ok = true break end
      end
    end
    if ok then notice_to(world, p[1], text, seconds, tag, sound, colour) end
  end
end

-- (0.15.488) How many monsters of group `gid` are alive, its own and those counted apart (0.15.526: the roster).
local function group_alive(gid)
  return #mon_alive(gid)
end
local function group_queued(gid)
  local n = 0
  for _, q in ipairs(S.queue) do
    local qn = data().nodes[tostring(q.node)]
    if qn and qn.g == gid then n = n + 1 end
  end
  for q in pairs(S.checks) do  -- (0.15.508) a spot being checked
    local qn = data().nodes[tostring(q.node)]
    if qn and qn.g == gid then n = n + 1 end
  end
  return n
end

-- (0.15.498, owner 14:49 "it also stopped recording how many monsters I was killing mid fight, not sure if you fucked
-- that up with an update": yes: each reload of FlameKit on the server (the updates at 14:46-14:48) forgot the raid
-- itself: its count, its end notice, its waves still to come) What runs is kept in spawn_nodes_raid.json, written every
-- second when it changed, and taken back after a reload of the same world run (emf.session_token): the raids (place,
-- monsters spawned), their start times and the runs (wave, waves, steps to the next one, who started it).
local function persist()
  local token = nil
  pcall(function() token = emf.session_token() end)
  local out = { token = token, raid = {}, started = {}, runs = {} }
  for gid, r in pairs(S.raid) do out.raid[tostring(gid)] = { place = r.place, spawned = r.spawned, first_id = r.first_id, total = r.total } end
  for gid, at in pairs(S.started) do out.started[tostring(gid)] = at end
  for gid, run in pairs(S.runs) do
    local owed = nil
    if run.owed then owed = {} for nid, v in pairs(run.owed) do owed[tostring(nid)] = v end end
    out.runs[tostring(gid)] = { wave = run.wave, waves = run.waves, next_in = math.max(0, run.next_at - S.steps), by = run.by,
                                in_wave = run.in_wave or nil, owed = owed, wait_dead = run.wait_dead, size = run.size }  -- (0.15.512); (0.15.542) wait_dead, size
  end
  local text = emf.json.encode(out)
  if text ~= S.persisted then
    S.persisted = text
    pcall(kit.store.save, "spawn_nodes_raid", out)
  end
end
local function restore()
  for _, g in ipairs(groups()) do  -- (0.15.547) the cooldowns, kept with the groups (finish)
    if tonumber(g.last_end) and not S.last_end[g.id] then S.last_end[g.id] = tonumber(g.last_end) end
  end
  local ok, saved = pcall(kit.store.load, "spawn_nodes_raid", nil)
  if not ok or type(saved) ~= "table" then saved = {} end
  local token = nil
  pcall(function() token = emf.session_token() end)
  if not token or saved.token ~= token then saved = {} end  -- another world run: its raids are gone
  local n = 0
  for k, r in pairs(saved.raid or {}) do
    local gid = tonumber(k)
    if gid and group(gid) and type(r) == "table" then
      S.raid[gid] = { place = r.place, spawned = tonumber(r.spawned) or 0, first_id = tonumber(r.first_id), total = tonumber(r.total) }
      n = n + 1
    end
  end
  for k, at in pairs(saved.started or {}) do
    local gid = tonumber(k)
    if gid and group(gid) and tonumber(at) then S.started[gid] = tonumber(at) end
  end
  for k, run in pairs(saved.runs or {}) do
    local gid = tonumber(k)
    if gid and group(gid) and type(run) == "table" then
      local owed = nil
      if type(run.owed) == "table" then owed = {} for k2, v in pairs(run.owed) do if tonumber(k2) then owed[tonumber(k2)] = tonumber(v) or 0 end end end
      S.runs[gid] = { wave = tonumber(run.wave) or 0, waves = tonumber(run.waves) or 1, next_at = S.steps + (tonumber(run.next_in) or 0), by = run.by,
                      in_wave = run.in_wave == true and owed ~= nil, owed = owed,  -- (0.15.512)
                      wait_dead = tonumber(run.wait_dead), size = tonumber(run.size) }  -- (0.15.542)
    end
  end
  for _, g in ipairs(groups()) do  -- (0.15.500) its monsters live but its raid was over or not known: a raid again
    if not S.raid[g.id] then
      local alive = #mon_alive(g.id)  -- (0.15.526)
      if alive > 0 then
        S.raid[g.id] = { place = raid_place(g.id, nil), spawned = alive }
        S.started[g.id] = S.started[g.id] or os.time()
        n = n + 1
      end
    end
  end
  for gid, r in pairs(S.raid) do  -- (0.15.501) a raid from before 0.15.501: its first monster = the lowest id it has
    if not r.first_id then
      for _, id in ipairs(mon_alive(gid)) do if not r.first_id or id < r.first_id then r.first_id = id end end  -- (0.15.526)
    end
  end
  emf.log(string.format("spawn nodes: after the reload: %d raid(s) and %d run(s) taken back", n, (function() local c = 0 for _ in pairs(S.runs) do c = c + 1 end return c end)()))
end

-- (0.15.501, owner 15:09 "the game has to accurately count monsters spawned and monsters killed to end the raid fix
-- it": three monsters he killed at 15:07:54-57 were never the nodes' own: the Undead's summons or the world's) Every
-- monster that comes into a raid joins it: counted, marked, watched, and the raid ends only when they are dead too.
-- A monster joins a running raid when its entity id is higher than the raid's first monster's (it was made during the
-- raid: the game numbers entities in order), it is within JOIN_R m of one of the raid's nodes, it is alive, it is not a
-- player and its faction is a hostile one (not Environment 0, Wildlife 5, Player 7, AutomatedPlayer 8, PlayerAlly 11,
-- FarmAnimal 12), or it hit a player or was hit by one (emf.on_hit). Found by a look at the new entities every
-- JOIN_EVERY steps (only the ids above the highest one looked at before) and by every hit.
local JOIN_R = 100
local JOIN_EVERY = 120
local JOIN_FULL = 5            -- (0.15.509) every 5th look (10 s): all ids since the raid's first monster
local FRIENDLY = { [0] = true, [5] = true, [7] = true, [8] = true, [11] = true, [12] = true }
-- Group `gid`'s node nearest x, y, z within JOIN_R m, or nil.
local function join_node(gid, x, y, z)
  local best, nid = nil, nil
  for _, n in ipairs(nodes_of(gid)) do
    local d = dist2(x, y, z, n.x, n.y, n.z)
    if d <= JOIN_R * JOIN_R and (not best or d < best) then best, nid = d, n.id end
  end
  return nid
end
-- (0.15.507) Whether entity `id` is a monster of group `gid`'s raid area: made after `first_id`, within JOIN_R m of its
-- nodes, not a player, hostile (or `engaged`). Returns its node, its health ("dead" for 0), or nil and "wait" when the
-- game has not given it a position, health or faction yet (just made: asked again later).
raid_monster = function(world, gid, first_id, id, engaged)
  if not first_id or id <= first_id then return nil end
  local okp, x, y, z = pcall(world.position, world, id)
  if not (okp and x) then return nil, "wait" end
  local nid = join_node(gid, x, y, z)
  if not nid then return nil end
  local oka, acc = pcall(world.account, world, id)
  if oka and acc then return nil end  -- a player
  -- (0.15.547, found 10:08 cross-checking the features) never FlameKit's own: a test monster spawned near a raid joined
  -- it (hostile faction) and held it open until it died; a loot chest (Reward loot puts one at each body) made during
  -- the raid and hit by a player joined as a "monster" (engaged skips the faction check)
  if K.test_tag.is(world, id) or K.chests.is(id) then return nil end
  local okh, cur = pcall(emf.health, world, id)
  if not (okh and cur) then return nil, "wait" end
  local okf, f = pcall(world.get, world, "Faction", id)
  local faction = okf and f and tonumber(f.faction)
  if not engaged and faction == nil then return nil, "wait" end
  if not engaged and FRIENDLY[faction] then return nil end
  return nid, cur, faction, x, y, z
end

-- Lets entity `id` join a running raid when it is a monster of it (see above); `engaged`: it hit or was hit by a player.
-- (0.15.507) "wait": not ready yet (the summons the Undead make had no health or faction in the step they were made, and
-- the old sweep looked at each new id only once: 50 of them were never counted, census 15:57).
local function try_join(world, id, engaged)
  if not id or id == 0 or known(id) then return false end
  local wait = false
  for gid, r in pairs(S.raid) do
    if r.first_id and id > r.first_id then
      local nid, cur, faction, x, y, z = raid_monster(world, gid, r.first_id, id, engaged)
      if cur == "wait" then wait = true end
      if nid and cur == 0 then wait = true end  -- (0.15.509) 0 health: still coming up out of the ground (the Undead), asked again
      if nid and type(cur) == "number" and cur > 0 then
        do
          mon_add(id, gid, nid, false, false, string.format("joined: faction %s%s, at %.0f %.0f %.0f", tostring(faction),
            engaged and ", in the fight" or "", x, y, z))  -- (0.15.526) counted apart
          r.spawned = r.spawned + 1
          return true
        end
      end
    end
  end
  return false, wait
end
-- (0.15.558, owner 2026-11-24 21:56 "must be something with that node count"; G-Portal 21:54:57/21:55:07 "join took
-- 184/188 ms" with 106 alive, then the pause 21:55:25 with Group 6's 40 nodes) THE LOOK IS SPREAD OVER STEPS: the list of
-- entities is taken once per look (K.jn), then gone through K.JOIN_MS at a time each step, on from where it stopped;
-- when it is through, the waiting ones and the hits are asked. A new look starts only when the last one is through.
K.JOIN_MS = 0.015
local function join_tick(world)
  if next(S.raid) == nil then S.join_seen, K.jn = nil, nil return end
  local jn = K.jn
  if not jn then
    local low = nil
    for _, r in pairs(S.raid) do if r.first_id and (not low or r.first_id < low) then low = r.first_id end end
    if not low then return end
    -- (0.15.509, 16:07-16:10: four Undead of the raid were joined only when a reload looked at every id again) every
    -- JOIN_FULL-th look goes over every id since the raid's first monster again, not only the new ones
    S.join_n = (S.join_n or 0) + 1
    if S.join_n % JOIN_FULL == 0 then S.join_seen = nil end
    local ok, list = pcall(world.entities, world)
    if not ok or type(list) ~= "table" then return end
    jn = { list = list, i = 1, seen = S.join_seen or low, now = os.time() }
    jn.top = jn.seen
    K.jn = jn
  end
  local t0 = clock and clock() or nil
  local list, n = jn.list, #jn.list
  while jn.i <= n do
    local id = list[jn.i]
    jn.i = jn.i + 1
    if id > jn.seen then
      if id > jn.top then jn.top = id end
      local _, wait = try_join(world, id, false)
      if wait then S.join_wait[id] = jn.now end  -- (0.15.507) asked again for up to 20 s
    end
    if t0 and jn.i % 64 == 0 and clock() - t0 > K.JOIN_MS then return true end  -- the rest next step
  end
  K.jn = nil
  S.join_seen = jn.top
  local now = os.time()
  local c = 0
  for id, at in pairs(S.join_wait) do
    c = c + 1
    local joined, wait = try_join(world, id, false)
    if joined or not wait or now - at > 20 or c > 3000 then S.join_wait[id] = nil end
  end
  for id in pairs(S.join_hits) do try_join(world, id, true) end
  S.join_hits = {}
end

-- (0.15.544, owner 2026-11-24 08:25 "a bit of a delay between when I kill the last monster and when the message in the
-- notice disappears about their being 1 monster left to kill", 08:27 "it needs to update when a monster dies,
-- otherwise, it looks like shit to the player") THE COUNTDOWN "Raid on X: N of TOTAL monsters left to kill" is worked
-- out every FAST_STEPS (0.25 s, as deaths are seen: left_tick) and sent when it changed, at most every K.LEFT_MIN_STEPS
-- (0.5 s, so a burst of kills cannot flood the players' channel); at least every LEFT_EVERY s. Until 0.15.543 it was
-- changed at most every 5 s and not at all while nothing was alive (the END_GRACE wait): "1 of 24" stayed ~11 s after the
-- last kill. Now the last kill shows "0 of 24" at once (zero = true while none is alive).
local function count_notice(world, gid, r, g, zero)
  -- (0.15.545, owner 08:36 "The "Raid on base: N of N monsters left to kill" should NOT appear until the first wave of
  -- monsters comes in") nothing before the raid's first monster has spawned
  if (r.spawned or 0) == 0 then return end
  local text
  local total = r.total
  if zero then
    text = string.format("Raid on %s: 0 of %d monsters left to kill.", r.place or "the area", total or 0)
  else
    -- (0.15.513, owner 16:31 "something is fucked with how it counts monsters left to kill": since 0.15.512 the nodes
    -- spawn one by one, so alive + queued went 4, 3, 2, 1, 2, 1, 4) left = alive + queued + what the nodes still owe in
    -- this wave + the waves to come (Monsters per node for every node)
    -- (16:32 "the number keeps going up, you kill more it goes down, it spawns more, number goes up, thats absolutely
    -- useless") so it only goes down: the monsters that joined (summons, the world's) are not in it while the nodes'
    -- own are left; when only joined ones are left, it is their number
    local own = #mon_alive(gid, nil, true)  -- (0.15.526) the roster: its own ones, and the ones counted apart
    local joined = #mon_alive(gid) - own
    local n = own + group_queued(gid)
    local run = S.runs[gid]
    if run then
      for _, owed in pairs(run.owed or {}) do n = n + owed end
      n = n + math.max(0, (run.waves or 0) - (run.wave or 0)) * (g.per_wave or 0) * #nodes_of(gid)
    end
    -- (0.15.514, owner 16:33 "you need to tell the player the TOTAL NUMBER of monsters for the entire raid, and count all
    -- the way down to zero with its over") "N of TOTAL": TOTAL = every node's Monsters per node in every wave, fixed at
    -- the start; N never above it; at 0 with summons still alive, those are named apart
    total = total or n
    if n > total then n = total end
    if n == 0 and joined > 0 then
      text = string.format("Raid on %s: 0 of %d monsters left. %d summoned monster%s still to kill.", r.place or "the area", total, joined, joined == 1 and "" or "s")
    else
      text = string.format("Raid on %s: %d of %d monsters left to kill.", r.place or "the area", n, total)
    end
  end
  local now = os.time()
  if (text ~= r.left_text and S.steps - (r.left_step or -1e9) >= K.LEFT_MIN_STEPS) or now - (r.left_at or 0) >= LEFT_EVERY then
    r.left_text, r.left_at, r.left_step = text, now, S.steps
    raid_notice(world, gid, text, true, LEFT_EVERY + 5, "left_" .. gid)
  end
end

-- (0.15.544) every FAST_STEPS: the countdown of every raid past its start notice, as deaths are seen
local function left_tick(world)
  for gid, r in pairs(S.raid) do
    local g = group(gid)
    if g and not r.ask and r.left_text then
      local alive, queued = group_alive(gid), group_queued(gid)
      count_notice(world, gid, r, g, not S.runs[gid] and alive == 0 and queued == 0)
    end
  end
end

-- (0.15.488) Every second: the count of monsters left, and the end of a raid (no waves to come, none alive, none
-- queued). S.raid[gid] = { place, spawned, left_at, left_n } from its first wave until its end.
local function raid_tick(world)
  for gid, r in pairs(S.raid) do
    if r.ask then  -- (0.15.490) the start notice, once the list came or the wait is over
      local answer = S.place_answers[r.ask.q]
      if answer or S.steps >= r.ask.until_step then
        S.place_answers[r.ask.q] = nil
        r.place = raid_place(gid, answer)
        emf.log(string.format("spawn nodes: place of the raid: %s (%s)", tostring(r.place),
          answer and string.format("player %s's minimap: place '%s', region '%s'", tostring(r.ask.by), tostring(answer.place), tostring(answer.region))
          or "no answer came: the nearest flame altar"))
        r.ask = nil
        -- (0.15.545, owner 2026-11-24 08:36 "The first "Raid forces are pushing into" message should show up in red and the
        -- "N monster are coming." message can be removed from the end of that line ... Also bring back the second siren on
        -- the first notice of the raid forces notice") red, no count, the siren twice again (as 0.15.517-0.15.542)
        raid_notice(world, gid, r.place and string.format("Raid forces are pushing into %s!", r.place) or "A raid has begun!", nil, START_END_S, nil,
          "raid_siren_twice", "#ff4040")
        local run = S.runs[gid]
        local g = group(gid)
        if run and run.hold_until then  -- (0.15.543) the first monsters after the notice
          run.hold_until = S.steps + ((g and g.start_delay) or 0) * 60
          emf.log(string.format("spawn nodes: %s: the start notice went out; its first monsters come in %d s", g and g.name or tostring(gid), (g and g.start_delay) or 0))
        end
      end
    end
  end
  for gid, r in pairs(S.raid) do
    local g = group(gid)
    local alive, queued = group_alive(gid), group_queued(gid)
    if not g then
      S.raid[gid] = nil
    elseif r.ask then
      -- the start notice comes first
    elseif not S.runs[gid] and alive == 0 and queued == 0 and not r.none_since then
      r.none_since = os.time()  -- (0.15.500) none left: over only when it stays so for END_GRACE s (one may get up again)
      count_notice(world, gid, r, g, true)  -- (0.15.544) "0 of N" at once, not the last number until the end notice
    elseif not S.runs[gid] and alive == 0 and queued == 0 and os.time() - r.none_since < END_GRACE then
      -- waiting
    elseif not S.runs[gid] and alive == 0 and queued == 0 and not r.verified then
      -- (0.15.505, owner 15:49 "it just announced the raid was over yet theres still tons of monsters on the map from
      -- the raid?") before the end notice the whole world is searched for the group's monsters (verify_tick); any
      -- still alive is counted again and the raid goes on
      if not S.verify then S.verify = { gid = gid, i = 1, found = 0 } end
    elseif not S.runs[gid] and alive == 0 and queued == 0 then
      S.raid[gid] = nil
      S.started[gid] = nil
      -- (0.15.549, owner 11:38 "add an "all clear" sound effect after the raid is over", 11:46 "yeah go with that one":
      -- sounds/raid_all_clear.wav, a short brass "da-da-da DAAA", 1.2 s) the all-clear with the end notice
      raid_notice(world, gid, string.format("The raid on %s is over: all %d raid monsters defeated!", r.place or "the area", r.total or r.spawned), nil, START_END_S, nil, "raid_all_clear")
      raid_notice(world, gid, "", true, 1, "left_" .. gid)  -- takes the count away soon
    else
      r.none_since, r.verified = nil, nil
      count_notice(world, gid, r, g, false)
    end
  end
end

-- (0.15.491, owner 14:04 "someone should be near it for it to even start... 100 m is kind of far way don't you think?",
-- "yeah build it that way") Whether a player is within the group's "Player within" (near_r) of one of its nodes.
local function group_near(spots, gid)
  local g = group(gid)
  local r = g and g.near_r or 50
  for _, n in ipairs(nodes_of(gid)) do
    if player_near(spots, n.x, n.y, n.z, r) then return true end
  end
  return false
end

-- (0.15.505) A slice of the world search before a raid's end notice: the group's tagged monsters still alive.
local function verify_tick(world)
  local v = S.verify
  local r = S.raid[v.gid]
  if not r then S.verify = nil return end
  if not v.list then
    local ok, list = pcall(world.entities, world)
    v.list = ok and list or {}
    return
  end
  local t0 = clock and clock() or 0
  local done = 0
  while v.i <= #v.list and done < SCAN_MAX and not (clock and clock() - t0 > SCAN_BUDGET) do
    local id = v.list[v.i]
    v.i, done = v.i + 1, done + 1
    local oks, scl = pcall(world.get, world, "ScaleComponent", id)
    local mine = oks and scl and group_of_tag(scl.uniformScale) == v.gid
    if not mine and r.first_id then  -- (0.15.507) or a monster of its raid area without the tag (a summon)
      local nid0, cur0 = raid_monster(world, v.gid, r.first_id, id, false)
      mine = nid0 ~= nil and type(cur0) == "number" and cur0 > 0
    end
    if mine and not known(id) then  -- (0.15.526) one the roster has is mon_check's; a body of an earlier raid is never counted
      local okh, cur = pcall(emf.health, world, id)
      if okh and cur and cur > 0 then
        local okp, x, y, z = pcall(world.position, world, id)
        local nodes = nodes_of(v.gid)
        local best, nid = nil, nodes[1] and nodes[1].id
        for _, n in ipairs(nodes) do
          local d = okp and x and dist2(n.x, n.y, n.z, x, y, z) or 0
          if not best or d < best then best, nid = d, n.id end
        end
        if nid then
          mon_add(id, v.gid, nid, false, false, "found alive by the search before the end notice")  -- (0.15.526) counted apart
          v.found = v.found + 1
        end
      end
    end
  end
  if v.i <= #v.list then return end
  if v.found > 0 then
    emf.log(string.format("spawn nodes: before the end notice: %d of its monsters found alive in the world: the raid goes on", v.found))
    r.none_since, r.verified = nil, nil
  else
    r.verified = true
  end
  S.verify = nil
end

-- ============================================================================================================
-- (0.15.538, owner 2026-11-23 22:28 "before a raid starts it has to stop all the animals", 22:29 "build that into the
-- system and note it heavily") THE ANIMAL HOLD. WHY: the 22:00 path grid probe (0.15.536) showed the base's tamed
-- animals (IsTame + Wildlife, faction Environment, ~22 of the world's 100 near the player) asking the game for short
-- 2-14 m walks that keep failing at the game's 500-step search limit and restart every ~0.5 s; the game's one shared
-- path search then left the raid monsters' requests unsearched for 54-89 s (the "they stand there, then all come at
-- once"). PROOF, 22:17 raid with the animals held by hand (0.15.537 flamekit.tamepath off): all 71 raid requests
-- searched at once, "path came" median 1 s, max 4 s.
-- WHAT: while a raid is active (the same rule as the raid protection: a group running, a raid not yet over, or any
-- of a group's monsters alive), this writes animal_hold_server.txt = "1 <time>" and rewrites it every K.HOLD_BEAT_S;
-- FlameKit Native (build_anywhere.cpp, "animal hold") then refuses every tamed animal's path request (the game's own
-- failure answer), so the animals stand still and the raid monsters have the path search to themselves. Raid over:
-- "0", the animals walk again. SAFETY: FlameKit Native lets go by itself if the file is not rewritten for 30 s (this
-- script stopped, an error), and this side lets go after K.HOLD_MAX_S even if a monster never dies. Nothing is saved;
-- a server restart always starts with the animals free. Logged: "spawn nodes: animal hold: ..." here and
-- "[flamekit build] animal hold: ..." / "tame path test: ..." in FlameKit Native.
-- ============================================================================================================
local function hold_write(on, why)
  local f = io.open(emf.dir .. K.HOLD_FILE .. ".tmp", "w")
  if not f then
    if not S.hold_err then S.hold_err = true emf.log("spawn nodes: animal hold: could not write " .. K.HOLD_FILE) end
    return
  end
  f:write(on and ("1 " .. tostring(os.time()) .. "\n") or "0\n")
  f:close()
  os.remove(emf.dir .. K.HOLD_FILE)
  if not os.rename(emf.dir .. K.HOLD_FILE .. ".tmp", emf.dir .. K.HOLD_FILE) then return end
  if on ~= S.hold_on then
    emf.log(on and ("spawn nodes: animal hold: ON (" .. tostring(why) .. "): tamed animals stand still so the raid monsters get the game's path search")
      or ("spawn nodes: animal hold: off (" .. tostring(why) .. "): the animals walk again"))
    if on then S.hold_since = os.time() end
  end
  S.hold_on = on
  S.hold_at = os.time()
end

-- Starts a run of group `gid` (its waves). `why`: what fired it (for the log). Manual starts ignore the cooldown.
-- (0.15.491) Never without a player within its near_r of one of its nodes: false, the reason, "nobody".
local function fire(world, gid, why, manual, by)  -- (0.15.490) by: the player who started or triggered it
  local g = group(gid)
  if not g or S.runs[gid] then return false, "This group is already running." end
  if not manual then
    if not g.on then return false end
    local since = os.time() - (S.last_end[gid] or 0)
    if since < g.cooldown * 60 then return false end
  end
  if not group_near(player_spots(world), gid) then
    return false, string.format("Nobody is within %d m of its nodes: it does not start.", g.near_r or 50), "nobody"
  end
  S.runs[gid] = { wave = 0, waves = g.waves, next_at = S.steps, by = by }
  S.hold_capped = nil  -- (0.15.538) a new raid: the animal hold's time limit starts again
  pcall(hold_write, true, "raid start: group " .. tostring(gid))  -- (0.15.538) the animal hold, before its first wave
  S.halted[gid] = nil  -- (0.15.514) a new start
  S.started[gid] = os.time()  -- (0.15.492) for its time limit
  for _, n in ipairs(nodes_of(gid)) do S.respawns[n.id] = nil end  -- (0.15.493) a new raid: its own count
  S.order_log, S.stuck_log, S.path_said, S.spawn_said, S.joined_said = nil, nil, nil, nil, nil  -- (0.15.511) each raid logs anew
  S.trickle_log = nil  -- (0.15.512)
  S.ground_log, S.threat_log = nil, nil  -- (0.15.518); (0.15.522)
  S.mon_log = nil  -- (0.15.526)
  mon_new_raid(gid)  -- (0.15.526) the bodies of its earlier raids put aside, monsters left from before counted apart
  if S.raid[gid] then  -- (0.15.526) an earlier raid of it was not over yet (stopped, monsters left): this one has its own count
    emf.log(string.format("spawn nodes: %s: its earlier raid was not over yet: this start begins a new raid (a new count)", g.name))
    S.raid[gid] = nil
  end
  emf.log(string.format("spawn nodes: %s (group %d, %d node(s), %s) started: %s", g.name, gid, #nodes_of(gid), g.family, why))
  return true
end

-- Ends the run of group `gid` (the cooldown starts now).
local function finish(gid)
  S.runs[gid] = nil
  S.last_end[gid] = os.time()
  S.next_timer[gid] = nil  -- the timer picks its next time from now
  -- (0.15.547, found 10:08 cross-checking: a Lua reload or a server restart forgot every cooldown, and a "Base raid"
  -- group fired again at once: the 07:52 raid that started 1 s after a live reload) kept with the group in
  -- spawn_nodes.json; restore() takes it back
  local g = group(gid)
  if g then g.last_end = S.last_end[gid] save() end
end

-- One wave of group `gid`: monsters queued at every node, (0.15.491) while a player is within its near_r of any of
-- them (else the wave is skipped: nobody there).
local function wave(world, gid, spots)
  local g = group(gid)
  local run = S.runs[gid]
  if not g or not run then return end
  run.wave = run.wave + 1
  local pool = POOL[g.family] or POOL.Random
  local queued, skipped = 0, 0
  local anyone = group_near(spots, gid)
  -- (0.15.512, owner 16:19 "I want each monster to spawn once at a time in a node and I want it to spawn 5 monsters
  -- before that wave is over", 16:20 "in some spots you cannot spawn 5 monsters at once in a tiny spot") a wave gives
  -- every node "Monsters per node" monsters to spawn (run.owed); trickle_tick spawns them one by one while fewer than
  -- "Most alive per node" of the node's are alive; the wave is over when every node has spawned all of them, and only
  -- then "Between waves" starts. Nobody near: the wave waits.
  run.owed = {}
  run.size = 0  -- (0.15.542)
  local _ = pool
  for _, n in ipairs(nodes_of(gid)) do
    if anyone then
      run.owed[n.id] = g.per_wave
      queued = queued + g.per_wave
    else
      skipped = skipped + 1
    end
  end
  run.in_wave = queued > 0
  emf.log(string.format("spawn nodes: %s wave %d of %d: %d monster(s)%s", g.name, run.wave, run.waves, queued,
    skipped > 0 and string.format(", skipped: no player within %d m of its nodes", g.near_r or 50) or ""))
  -- (0.15.488) the notices
  local r = S.raid[gid]
  if not r and queued > 0 then
    r = { spawned = 0, total = run.waves * g.per_wave * #nodes_of(gid) }  -- (0.15.514) the raid's whole number
    S.raid[gid] = r
    -- (0.15.543, owner 2026-11-24 08:16 "there needs to be a delay between when the raid notice goes out and when the
    -- monsters actually spawn in.. default to like 10 seconds?") nothing of the first wave spawns before the start
    -- notice has gone out and the group's "First monsters after the notice" time has passed (raid_tick sets the time
    -- when it sends the notice; until then held, at most PLACE_WAIT + that time)
    run.hold_until = S.steps + PLACE_WAIT + (g.start_delay or 0) * 60 + 60
    -- (0.15.490) the start notice waits (at most PLACE_WAIT steps) for the list of places from the player who started or
    -- triggered it, else the player nearest its nodes
    local by = run.by
    if not by then
      local best
      for _, p in ipairs(spots or {}) do
        for _, n in ipairs(nodes_of(gid)) do
          local d = dist2(p[2], p[3], p[4], n.x, n.y, n.z)
          if not best or d < best then best, by = d, p[1] end
        end
      end
    end
    S.place_q = (S.place_q or 0) + 1
    r.ask = { q = S.place_q, until_step = S.steps + PLACE_WAIT, by = by }
    if by then
      local msg = { op = "place_ask", q = r.ask.q }
      if by == emf.local_player() and kit.is_host() then S.host_ask = msg
      else pcall(emf.net.send_to, world, by, CHANNEL, emf.json.encode(msg)) end
      emf.log(string.format("spawn nodes: %s: asked player %s where he is", g.name, tostring(by)))
    end
  elseif r and queued > 0 then
    local last = run.wave >= run.waves
    -- (0.15.495, owner 14:45 "get rid of the (wave 4 of 5, 6 monsters) bullshit no one wants to see that")
    raid_notice(world, gid, string.format("%s at %s!", last and "Final wave incoming" or "New incoming wave", r.place or "the raid"), true, 10, nil, "raid_siren")  -- (0.15.517) once
  end
  if queued == 0 then  -- nobody near: this wave is spent (as before 0.15.512)
    if run.wave >= run.waves then finish(gid) else run.next_at = S.steps + g.wave_gap * 60 end
  end
end

-- (0.15.515) A spot whose check has no answer after CHECK_WAIT steps is used anyway (the check is cancelled).
local CHECK_WAIT = 45  -- 0.75 s
local do_spawn_ref = nil  -- set below (do_spawn)
local function check_timeouts(world)
  for q in pairs(S.checks) do
    if q.asked_at and S.steps - q.asked_at > CHECK_WAIT and not q.cancelled then
      q.cancelled = true
      S.checks[q] = nil
      if q.qid then pcall(emf.path_cancel, q.qid) end
      emf.log(string.format("spawn nodes: node %s: the spot check gave no answer in %.1f s: the spot is used", tostring(q.node), CHECK_WAIT / 60))
      if do_spawn_ref then do_spawn_ref(world, q, q.sx, q.sy, q.sz) end
    end
  end
end

-- (0.15.513) Drops group `gid`'s spots being checked (their answers then spawn nothing): Remove and the time limit.
-- (16:31: a Remove at 16:31:41 called the raid off, and the spots still being checked spawned 3 more monsters.)
local function cancel_checks(gid)
  for q in pairs(S.checks) do
    local qn = data().nodes[tostring(q.node)]
    if qn and qn.g == gid then q.cancelled = true S.checks[q] = nil end
  end
end

-- (0.15.512) The monsters of a node queued or being checked, not spawned yet.
local function node_pending(nid)
  local n = 0
  for _, q in ipairs(S.queue) do if q.node == nid then n = n + 1 end end
  for q in pairs(S.checks) do if q.node == nid then n = n + 1 end end
  return n
end

-- (0.15.512) Every half second: each node of a wave spawns its next monster while fewer than its group's "Most alive per
-- node" are alive (and queued); the wave ends when every node has spawned all of its "Monsters per node".
local function trickle_tick(world)
  local spots = nil
  for gid, run in pairs(S.runs) do
    local g = group(gid)
    if run.hold_until and S.steps >= run.hold_until then run.hold_until = nil end  -- (0.15.543)
    if g and run.in_wave and run.owed and not run.hold_until then
      spots = spots or player_spots(world)
      if not group_near(spots, gid) then
        if not run.held then
          run.held = true
          emf.log(string.format("spawn nodes: %s wave %d: nobody within %d m of its nodes: it waits", g.name, run.wave, g.near_r or 50))
        end
      else
        run.held = nil
        local pool = POOL[g.family] or POOL.Random
        local left = 0
        for nid, owed in pairs(run.owed) do
          local n = data().nodes[tostring(nid)]
          if not n then
            run.owed[nid] = nil
          elseif owed > 0 then
            if alive_count(nid) + node_pending(nid) < g.max_alive then
              local tx, tz = nearest_player(spots, n.x, n.y, n.z, ACTIVE_DIST)  -- (0.15.477) for "face the nearest player"
              S.queue[#S.queue + 1] = { node = nid, x = n.x, y = n.y, z = n.z, guid = pool[math.random(#pool)], face = g.face,
                                        tx = tx, tz = tz, yaw = n.yaw, wave = run.wave }  -- (0.15.547) wave: for its level
              owed = owed - 1
              run.owed[nid] = owed
              run.size = (run.size or 0) + 1  -- (0.15.542) how many this wave spawned
              if (S.trickle_log or 0) < 200 then
                S.trickle_log = (S.trickle_log or 0) + 1
                emf.log(string.format("spawn nodes: %s wave %d: node %d spawns its next monster (%d of %d; %d more to come, %d alive)", g.name,
                  run.wave, nid, g.per_wave - owed, g.per_wave, owed, alive_count(nid)))
              end
            end
            left = left + owed
          end
        end
        if left == 0 then
          run.in_wave, run.owed = false, nil
          emf.log(string.format("spawn nodes: %s wave %d of %d: every node has spawned its monsters (%d)", g.name, run.wave, run.waves, run.size or 0))
          if run.wave >= run.waves then finish(gid)
          elseif (g.wave_dead or 0) > 0 and (run.size or 0) > 0 then  -- (0.15.542) Next wave after: its dead first
            run.wait_dead = run.size
            emf.log(string.format("spawn nodes: %s wave %d: the next wave's %d s start once %d%% of its %d monster(s) are dead (%d or fewer of the group's left alive)",
              g.name, run.wave, g.wave_gap, g.wave_dead, run.size, math.floor(run.size * (100 - g.wave_dead) / 100)))
          else run.next_at = S.steps + g.wave_gap * 60 end
        end
      end
    end
  end
end

-- (0.15.492, owner 14:07 "there needs to be a total raid duration.. so if the raid goes on for 30 mins the raid ends,
-- that should be a configurable setting. so if someone cant finish a raid in a given amount of time it just ends")
-- Every second: a group whose raid has lasted its duration (minutes from its start; 0 = no limit) ends: no more waves,
-- nothing more spawns, its living monsters are taken away (so its protection ends too); the bodies stay.
local function time_tick(world)
  local now = os.time()
  for gid, at in pairs(S.started) do
    local g = group(gid)
    if not g then
      S.started[gid] = nil
    elseif (g.duration or 30) > 0 and now - at >= g.duration * 60 then
      S.started[gid] = nil
      if S.runs[gid] then finish(gid) end
      cancel_checks(gid)  -- (0.15.513)
      S.halted[gid] = true  -- (0.15.514)
      for i = #S.queue, 1, -1 do
        local qn = data().nodes[tostring(S.queue[i].node)]
        if qn and qn.g == gid then table.remove(S.queue, i) end
      end
      local n = 0
      for _, id in ipairs(mon_alive(gid)) do  -- (0.15.526) the roster: its own ones and those counted apart
        if pcall(emf.destroy, world, id) then n = n + 1 end
        mon_drop(id)
      end
      emf.log(string.format("spawn nodes: %s: its time is up (%d min): its raid ends, %d living monster(s) taken away", g.name, g.duration, n))
      local r = S.raid[gid]
      if r then
        raid_notice(world, gid, string.format("Time is up! The raid on %s is over%s.", r.place or "the area",
          n > 0 and string.format(": %d monster%s retreated", n, n == 1 and "" or "s") or ""), nil, START_END_S)  -- (no all-clear here: owner 11:55, only when the monsters are defeated)
        raid_notice(world, gid, "", true, 1, "left_" .. gid)
        S.raid[gid] = nil
      end
    end
  end
end

-- Spawns up to SPAWN_PER_STEP queued monsters.
-- (0.15.485) What is at a point: "building", "terrain", "empty", or nil when not known (an older EMF, not loaded).
local function block_kind(world, x, y, z)
  if not emf.block_at then return nil end
  local ok, b = pcall(emf.block_at, world, x, y, z)
  return ok and type(b) == "table" and b.kind or nil
end

-- (0.15.485) Whether a wall (a building block, or terrain a player placed) stands on the line from `a` to `b`.
local function wall_between(world, a, b)
  if not emf.find_wall then return false end
  local ok, w = pcall(emf.find_wall, world, a, b, { terrain = true })
  if not ok then ok, w = pcall(emf.find_wall, world, a, b) end  -- an older EMF: building blocks only
  return ok and w ~= nil and w ~= false
end

-- (0.15.493) Whether the cell at a point is solid (terrain or a building block); nil when not known.
local function solid_at(world, x, y, z)
  local k = block_kind(world, x, y, z)
  if k == nil then return nil end
  return k == "terrain" or k == "building"
end

-- (0.15.493) The height to stand on at x, z near height y: from 2 m under it up to SURFACE_UP over it, the first place
-- with solid ground just under it and 2 m of air over it. y itself when the cells cannot be read (an older EMF, not
-- loaded); nil when there is no such place.
local function find_surface(world, x, y, z)
  if not emf.block_at or solid_at(world, x, y, z) == nil then return y end
  local h = y - 2
  while h <= y + SURFACE_UP do
    if solid_at(world, x, h - 0.25, z) and not solid_at(world, x, h + 0.25, z) and not solid_at(world, x, h + 1, z)
        and not solid_at(world, x, h + 1.75, z) then
      return h + 0.1
    end
    h = h + 0.5
  end
  return nil
end

-- (0.15.485) A spot for a monster of node `n` (its own spread): x, y, z. See SPOT_TRIES. (0.15.493) y: the ground there.
local function pick_spot(world, q, spread)
  local from = { q.x, q.y + 1, q.z }
  if spread <= 0 then
    return q.x, find_surface(world, q.x, q.y, q.z) or q.y, q.z
  end
  for _ = 1, SPOT_TRIES do
    local a, r = math.random() * 2 * math.pi, math.sqrt(math.random()) * spread
    local x, z = q.x + math.cos(a) * r, q.z + math.sin(a) * r
    local bad = wall_between(world, from, { x, q.y + 1, z })
      or block_kind(world, x, q.y + 1, z) == "building" or block_kind(world, x, q.y + 2, z) == "building"
    if not bad then
      local solid = true
      for _, up in ipairs(SOLID_UP) do
        if block_kind(world, x, q.y + up, z) ~= "terrain" then solid = false break end
      end
      bad = solid
    end
    if not bad then  -- (0.15.497) not where a monster was found in water; (0.15.505) nor where one got stuck
      for _, w in ipairs(S.wet) do
        local dx, dz = w[1] - x, w[2] - z
        if dx * dx + dz * dz <= WET_R * WET_R then bad = true break end
      end
      for _, w in ipairs(S.bad) do
        local dx, dz = w[1] - x, w[2] - z
        if dx * dx + dz * dz <= BAD_R * BAD_R then bad = true break end
      end
    end
    if not bad then
      local y = find_surface(world, x, q.y, z)  -- (0.15.493) its ground, or not this spot
      if y then return x, y, z end
    end
  end
  S.spot_fallbacks = (S.spot_fallbacks or 0) + 1
  if S.spot_fallbacks <= 20 or S.spot_fallbacks % 100 == 0 then
    emf.log(string.format("spawn nodes: node %s: no clear spot within %d m after %d tries: on the node itself (%d times so far)",
      tostring(q.node), spread, SPOT_TRIES, S.spot_fallbacks))
  end
  return q.x, find_surface(world, q.x, q.y, q.z) or q.y, q.z
end

-- (0.15.508) Spawns queue entry `q`'s monster at x, sy, z (the body of spawn_tick before 0.15.508).
local function do_spawn(world, q, x, sy, z)
  -- (0.15.477) the way it faces: given to the spawn (EMF Lua 1.40+) and to the move onto the ground (any EMF)
  local yaw = math.random() * 360
  if q.face == "player" and q.tx then yaw = yaw_to(x, z, q.tx, q.tz)
  elseif q.face == "node" and q.yaw then yaw = q.yaw end
  local qn0 = data().nodes[tostring(q.node)]
  local tag = { ScaleComponent = { uniformScale = tag_of(qn0 and qn0.g or 0) } }  -- (0.15.483) its group, for a reload
  local ok, id = pcall(emf.spawn, world, q.guid, x, sy, z, tag, { yaw = yaw })
  local how = "tagged"
  if not ok or not id or id == 0 then
    local why1 = id
    ok, id = pcall(emf.spawn, world, q.guid, x, sy, z, tag)  -- an older EMF: no yaw
    how = "tagged, no yaw (" .. tostring(why1) .. ")"
  end
  if not ok or not id or id == 0 then
    local why2 = id
    ok, id = pcall(emf.spawn, world, q.guid, x, sy, z)  -- nor the tag
    how = "UNTAGGED (" .. tostring(why2) .. ")"
  end
  if how ~= "tagged" and (S.spawn_said or 0) < 30 then  -- (0.15.506) a monster spawned without its group's tag cannot be found again
    S.spawn_said = (S.spawn_said or 0) + 1
    emf.log(string.format("spawn nodes: node %s: monster %s spawned %s (template %s)", tostring(q.node), tostring(id), how, tostring(q.guid)))
  end
  if ok and id and id ~= 0 then
    local rq = qn0 and S.raid[qn0.g]
    if rq and not q.respawn then rq.spawned = rq.spawned + 1 end  -- (0.15.488); (0.15.493) a replacement is not one more
    if rq and (not rq.first_id or id < rq.first_id) then  -- (0.15.501) its first monster's id
      rq.first_id = id
      local gq = qn0 and data().groups[tostring(qn0.g)]
      if gq then gq.last_first_id = id save() end  -- (0.15.507) kept: Remove and the end check use it
    end
    S.track[id] = { x = x, y = sy, z = z, at = os.time(), born = os.time(), guid = q.guid, q = q }  -- (0.15.493) for stuck_tick
    mon_add(id, qn0 and qn0.g or 0, q.node, true, false, q.respawn and "spawned again for a stuck one" or "spawned by its node")  -- (0.15.526)
    if S.mon[id] then S.mon[id].sp = true end  -- (0.15.547) spawned by a node: its loot follows the group's Loot
    pcall(K.mark_loot, id, qn0 and qn0.g)  -- (0.15.547) Reward loot / No loot: Auto Loot leaves its body alone
    local okl, whyl = pcall(K.level_spawned, world, id, qn0 and qn0.g, q)  -- (0.15.547) the group's level
    if not okl then emf.log("spawn nodes: level: " .. tostring(whyl)) end
    -- (0.15.525) "spare": no EMF hit rule any more (spare_tick, FlameKit Native)
    -- (0.15.531, owner 20:16 "yes" to taking it out, rule 0n) NO teleport onto the ground after the spawn any more: the
    -- spot is already on the ground (find_surface, 0.15.493), and the teleport put back in 0.15.518 (on a misquote) hung
    -- on every node monster ("still has a Teleport 10 s after EMF's push", 48 times on 2026-11-23).
    if (S.ground_log or 0) < 40 then
      S.ground_log = (S.ground_log or 0) + 1
      emf.log(string.format("spawn nodes: node %s: monster %s spawned at %.1f %.1f %.1f (no ground teleport)", tostring(q.node), tostring(id), x, sy, z))
    end
  else
    emf.log("spawn nodes: the game refused a spawn at node " .. tostring(q.node) .. " (" .. tostring(id) .. ")")
  end
end

-- (0.15.508, owner 16:08 "monsters stuck in fence railings again": FlameKit's own spot check sees building blocks and
-- terrain, not placed objects such as fences) Before a monster appears, the game's own path grid (emf.path_find: it
-- knows terrain, buildings, placed objects and doors) is asked for a way from the spot to the nearest player within
-- HUNT_R m (else the node). A spot with no start on the grid (inside a fence or an object, in water) or from which the
-- way gets nowhere (not PATH_GAIN m along it, or half the way) is not used (S.bad) and another is tried, PATH_TRIES in
-- all; then the monster appears near that player (4-8 m, on the ground, nothing built between) or on the node.
-- (0.15.523, owner 18:12 "definitely drop the spot check": from 18:05 on it never answered and every spawn waited its
-- 0.75 s) switched off (kept, as debug tools are): spots are not checked on the path grid
local PATH_CHECK = false
local PATH_TRIES = 6
local PATH_GAIN = 8
local PATH_TARGET_R = 120      -- m: the player the way is asked to (as HUNT_R, below)
local function near_player_spot(world, pl)
  for _ = 1, 12 do
    local a, r = math.random() * 2 * math.pi, 4 + math.random() * 4
    local cx, cz = pl[2] + math.cos(a) * r, pl[4] + math.sin(a) * r
    local cy = find_surface(world, cx, pl[3], cz)
    if cy and not wall_between(world, { pl[2], pl[3] + 1, pl[4] }, { cx, cy + 1, cz }) and block_kind(world, cx, cy + 1, cz) ~= "building" then
      return cx, cy, cz
    end
  end
  return nil
end
do_spawn_ref = do_spawn  -- (0.15.515) for check_timeouts
local function spawn_tick(world)
  local done = 0
  while #S.queue > 0 and done < SPAWN_PER_STEP and (done == 0 or not K.over()) do  -- (0.15.556) and the step's time limit (one always)
    local q = table.remove(S.queue, 1)
    done = done + 1
    local qn1 = data().nodes[tostring(q.node)]
    if qn1 then
      local x, sy, z = pick_spot(world, q, tonumber(qn1.spread) or SPREAD)  -- (0.15.485) the node's spread, a clear spot; (0.15.493) its ground
      local pl, best = nil, nil
      for _, p in ipairs(player_spots(world)) do
        local d = dist2(x, sy, z, p[2], p[3], p[4])
        if d <= PATH_TARGET_R * PATH_TARGET_R and (not best or d < best) then best, pl = d, p end
      end
      local tx, ty, tz = q.x, q.y, q.z
      if pl then tx, ty, tz = pl[2], pl[3], pl[4] end
      local far = math.sqrt(dist2(x, sy, z, tx, ty, tz))
      local asked = false
      if PATH_CHECK and emf.path_find and far > 3 then  -- (0.15.523) switched off
        q.tries = (q.tries or 0) + 1
        q.asked_at, q.sx, q.sy, q.sz = S.steps, x, sy, z  -- (0.15.515) for check_timeouts
        S.checks[q] = true
        local okq, qid = pcall(emf.path_find, world, { x, sy + 0.5, z }, { tx, ty + 0.5, tz },
          { closest = true, jumps = true, width = 0.5, height = 2, nodes = 1500 }, function(w, result)
            S.checks[q] = nil
            if not w or q.cancelled then return end  -- (0.15.513) called off meanwhile
            local status = type(result) == "table" and result.status or "?"
            local len = type(result) == "table" and tonumber(result.length) or 0
            local good = status == "found" and (result.reaches or len >= math.min(PATH_GAIN, far * 0.5))
            -- (0.15.515: answers "other, 0 m" came 10 s late at 16:41:44 for three nodes at once) only a clear no (no start,
            -- no path, or a found way that gets nowhere) refuses a spot; any other answer: the spot is used
            if status ~= "found" and status ~= "no_start" and status ~= "no_path" then good = true end
            if (S.path_said or 0) < 40 then
              S.path_said = (S.path_said or 0) + 1
              emf.log(string.format("spawn nodes: node %s: spot %.0f %.0f %.0f, try %d: path %s, %.0f of %.0f m%s: %s", tostring(q.node), x, sy, z,
                q.tries, status, len, far, result and result.reaches and ", reaches" or "", good and "used" or "not used"))
            end
            if good then
              do_spawn(w, q, x, sy, z)
            else
              S.bad[#S.bad + 1] = { x, z }
              if #S.bad > 200 then table.remove(S.bad, 1) end
              if q.tries < PATH_TRIES then
                table.insert(S.queue, 1, q)
              else
                local mx, my, mz = nil, nil, nil
                if pl then mx, my, mz = near_player_spot(w, pl) end
                emf.log(string.format("spawn nodes: node %s: no spot with a way out after %d tries: %s", tostring(q.node), q.tries,
                  mx and "next to the player" or "on the node"))
                if mx then do_spawn(w, q, mx, my, mz) else do_spawn(w, q, q.x, find_surface(w, q.x, q.y, q.z) or q.y, q.z) end
              end
            end
          end)
        asked = okq and qid ~= nil
        if asked then q.qid = qid end
        if not asked then S.checks[q] = nil end
      end
      if not asked then do_spawn(world, q, x, sy, z) end
    end
  end
end

-- (0.15.493) Every 2 s: monsters in the ground, in water or stuck are taken away and come again at their node (see
-- STUCK_S). S.track[id] = { x, y, z (where it was), at (since when), born, guid, q (its queue entry) }; S.active_at[id]:
-- the last hit it gave or took (emf.on_hit) or wall it broke.
-- (0.15.524, owner 18:14 "and just spawn the monsters and see what happens.. no threat table no spot check none of
-- that") test switches: STUCK_ON (this whole stuck/ground/water/fall handling), HUNT_ON (the enemy orders), THREAT_ON
-- (the threat table writes). All off: monsters are only spawned (with the game's ground move) and counted; the 10 s
-- hunt summary still logs how many moved.
local STUCK_ON, HUNT_ON, THREAT_ON = false, true, true  -- (owner 2026-11-24 13:19: STUCK_ON code is still needed, kept off for now: HANDOFF OPEN #16; do not remove) (0.15.529, owner 19:40 "turn the threat table shit back on still if you must, to see that it does nothing": THREAT_ON back on); (0.15.530, owner 19:55 "turn this back on to see if the log says anything new": HUNT_ON, the enemy orders)
local function stuck_tick(world)
  if not STUCK_ON then return end
  local now = os.time()
  local spots = player_spots(world)
  -- (0.15.526) only the nodes' own monsters (the roster): one counted apart is never taken away as stuck
  for _, id in ipairs(mon_alive(nil, nil, true)) do
    local nid = S.mon[id].n
    do
      local t = S.track[id]
      local okp, x, y, z = pcall(world.position, world, id)
      local node = data().nodes[tostring(nid)]
      if not t and okp and x and node then  -- found again after a reload: watched from now on, a new one of its group's kind
        local g = group(node.g)
        local pool = POOL[g and g.family or "Random"] or POOL.Random
        t = { x = x, y = y, z = z, at = now, born = now,
              q = { node = nid, x = node.x, y = node.y, z = node.z, guid = pool[math.random(#pool)], face = g and g.face, yaw = node.yaw } }
        S.track[id] = t
      end
      if t and okp and x then
        local why = nil
        if now - t.born >= 3 and solid_at(world, x, y + 0.6, z) and solid_at(world, x, y + 1.4, z) then why = "in the ground" end
        if not why then
          -- (0.15.497, owner 14:47 "you're code isn't working. monsters that end up in water need to respawn out of the
          -- water") monsters have no swimming state (DynamicLocomotion is the players'); the game's submerge depth is
          -- read instead: ServerSubmerge (the server's), else NetworkSubmerge. In water: WATER_DEPTH m or deeper.
          local depth = nil
          local oks, sub = pcall(world.get, world, "ServerSubmerge", id)
          if oks and sub then depth = tonumber(sub.submergeDepth) end
          if not depth then
            local okn, nsub = pcall(world.get, world, "NetworkSubmerge", id)
            if okn and nsub then depth = tonumber(nsub.submergeDepth) end
          end
          if not S.sub_said[id] and (S.sub_said_n or 0) < 12 then  -- (0.15.498) which water reading monsters have, for the log
            S.sub_said[id], S.sub_said_n = true, (S.sub_said_n or 0) + 1
            emf.log(string.format("spawn nodes: monster %s at %.0f %.0f %.0f: ServerSubmerge %s, NetworkSubmerge %s, depth %s", tostring(id), x, y, z,
              (oks and sub) and "yes" or "no", select(2, pcall(world.get, world, "NetworkSubmerge", id)) and "yes" or "no", tostring(depth)))
          end
          if depth and depth > 0 and not S.depth_said[id] then  -- the first wet reading of each monster, for the log
            S.depth_said[id] = true
            emf.log(string.format("spawn nodes: monster %s: submerge depth %.2f m at %.0f %.0f %.0f", tostring(id), depth, x, y, z))
          end
          if depth and depth >= WATER_DEPTH then
            why = string.format("in water (%.1f m deep)", depth)
            S.wet[#S.wet + 1] = { x, z }  -- (0.15.497) this place is not used for a spawn again
            if #S.wet > 200 then table.remove(S.wet, 1) end
          end
        end
        if not why and node and y < node.y - FALL_M then  -- (0.15.505) fell: water or a drop under its node
          local down = false
          for _, p in ipairs(spots) do
            if dist2(x, y, z, p[2], p[3], p[4]) <= 30 * 30 and p[3] < node.y - FALL_M + 1 then down = true break end
          end
          if not down then
            why = string.format("fell (%.0f m under its node)", node.y - y)
            S.wet[#S.wet + 1] = { x, z }
            if #S.wet > 200 then table.remove(S.wet, 1) end
          end
        end
        if not why then
          if dist2(x, y, z, t.x, t.y, t.z) >= 1 then
            t.x, t.y, t.z, t.at = x, y, z, now
          elseif not player_near(spots, x, y, z, STUCK_NEAR) then
            t.at = now  -- (0.15.496) nobody near: it only waits; the clock starts again
          elseif now - t.born >= STUCK_BORN and now - t.at >= STUCK_S and now - (S.active_at[id] or t.born) >= STUCK_S then
            why = string.format("stuck (not moved for %d s with a player within %d m)", now - t.at, STUCK_NEAR)
            S.bad[#S.bad + 1] = { x, z }  -- (0.15.505) not a spawn spot again
            if #S.bad > 200 then table.remove(S.bad, 1) end
          end
        end
        if why and (S.stuck_log or 0) < 60 then  -- (0.15.511) what a stuck one was doing, and whether it had a way
          S.stuck_log = (S.stuck_log or 0) + 1
          local o = S.orders[id]
          local okt, tgt = pcall(emf.enemy_target, world, id)
          local pl0, b0 = nil, nil
          for _, p in ipairs(spots) do
            local d = dist2(x, y, z, p[2], p[3], p[4])
            if not b0 or d < b0 then b0, pl0 = d, p end
          end
          local head = string.format("spawn nodes: stuck detail: monster %s (%s) at %.0f %.0f %.0f: order %s at player %s, going for %s, nearest player %s %.0f m",
            tostring(id), why, x, y, z, tostring(o and o.id), tostring(o and o.target), tostring(okt and tgt), tostring(pl0 and pl0[1]), b0 and math.sqrt(b0) or -1)
          if emf.path_find and pl0 then
            local okq = pcall(emf.path_find, world, { x, y + 0.5, z }, { pl0[2], pl0[3] + 0.5, pl0[4] }, { closest = true, jumps = true, width = 0.5, height = 2, nodes = 1500 },
              function(w, result)
                emf.log(string.format("%s; path from it to him: %s, %.0f m along%s", head, tostring(type(result) == "table" and result.status),
                  type(result) == "table" and tonumber(result.length) or 0, type(result) == "table" and result.reaches and ", reaches him" or ", does not reach him"))
              end)
            if not okq then emf.log(head .. "; no path query") end
          else
            emf.log(head)
          end
        end
        if why and (t.moves or 0) < MOVE_MAX then  -- (0.15.505) first: next to the nearest player
          local best, pl = nil, nil
          for _, p in ipairs(spots) do
            local d = dist2(x, y, z, p[2], p[3], p[4])
            if d <= MOVE_NEAR * MOVE_NEAR and (not best or d < best) then best, pl = d, p end
          end
          local mx, my, mz = nil, nil, nil
          if pl then
            for _ = 1, 12 do
              local a, r = math.random() * 2 * math.pi, 4 + math.random() * 4
              local cx, cz = pl[2] + math.cos(a) * r, pl[4] + math.sin(a) * r
              local cy = find_surface(world, cx, pl[3], cz)
              local ok2 = cy ~= nil and not wall_between(world, { pl[2], pl[3] + 1, pl[4] }, { cx, cy + 1, cz })
                and block_kind(world, cx, cy + 1, cz) ~= "building"
              if ok2 then
                for _, list in ipairs({ S.wet, S.bad }) do
                  for _, w in ipairs(list) do
                    local dx, dz = w[1] - cx, w[2] - cz
                    if dx * dx + dz * dz <= BAD_R * BAD_R then ok2 = false break end
                  end
                end
              end
              if ok2 then mx, my, mz = cx, cy, cz break end
            end
          end
          local okt, moved = false, false
          if mx then okt, moved = pcall(emf.teleport, world, id, mx, my, mz, { yaw = yaw_to(mx, mz, pl[2], pl[4]) }) end
          if okt and moved then
            t.moves = (t.moves or 0) + 1
            t.x, t.y, t.z, t.at = mx, my, mz, now
            S.active_at[id] = now
            emf.log(string.format("spawn nodes: node %s: monster %s %s at %.0f %.0f %.0f: moved next to player %s (%.0f %.0f %.0f), move %d of %d",
              tostring(nid), tostring(id), why, x, y, z, tostring(pl[1]), mx, my, mz, t.moves, MOVE_MAX))
            why = nil
          end
        end
        if why then
          local okd, gone = pcall(emf.destroy, world, id)
          if not (okd and gone) then emf.log(string.format("spawn nodes: monster %s: EMF did not take it away (%s)", tostring(id), tostring(gone))) end  -- (0.15.499)
          mon_drop(id)  -- (0.15.526)
          S.respawns[nid] = (S.respawns[nid] or 0) + 1
          local nd0 = data().nodes[tostring(nid)]
          local again = S.respawns[nid] <= RESPAWN_MAX and nd0 ~= nil
            and not S.halted[nd0.g]  -- (0.15.514) nor one of a stopped or removed group
          if again then
            local q = {}
            for k, v in pairs(t.q) do q[k] = v end
            q.respawn = true
            S.queue[#S.queue + 1] = q
          end
          emf.log(string.format("spawn nodes: node %s: monster %s %s at %.0f %.0f %.0f: taken away%s", tostring(nid), tostring(id), why, x, y, z,
            again and ", a new one comes" or string.format(" (%d times at this node in this raid: no new one)", S.respawns[nid])))
        end
      end
    end
  end
  for id in pairs(S.track) do  -- dead or gone: no longer watched
    if not (S.mon[id] and not S.mon[id].dead) then S.track[id], S.active_at[id] = nil, nil end  -- (0.15.526)
  end
end

-- (0.15.503, owner 15:30 "monsters just bunch up at the node ... the just seem to stay there and never run out") Every 2 s
-- each living raid monster without an order (EMF's enemy_order: it walks up to its target and attacks it, at once and
-- after every step) is sent at the player nearest it within HUNT_R m; an order ends when the target dies or leaves
-- (then the next nearest player), when the monster dies, or with a reload (sent again 2 s later). Bosses are refused by
-- EMF: they keep the game's own way.
local HUNT_R = 120
local THREAT_R = 50            -- m: (0.15.521, owner 17:21) every player this near is written into a raid monster's threat table

local function hunt_tick(world)
  local spots = player_spots(world)
  local now0 = os.time()
  local list = mon_alive()  -- (0.15.526) the roster
  local n_all = #list
  local start = ((K.hunt_i or 0) % math.max(1, n_all))  -- (0.15.556) on from where the last one stopped (the time limit)
  for k = 1, n_all do
    local id = list[(start + k - 1) % n_all + 1]
    if k > 1 and K.over() then K.hunt_i = start + k - 1 break end  -- (one always)
    K.hunt_i = start + k
    do
      -- (0.15.522, owner 17:21 "any player near like 50 m gets automatically added to the monsters threat table, one of
      -- their 5 or 6 slots", 17:22 "no hitting for +1 damage. I asked you to put me directly into their threat table.
      -- you've done this before") every player within THREAT_R m of a raid monster is written straight into its threat
      -- table (core/threat.lua: the way PvP players are, experimental.lua since 0.15.69), as Alarmed, every hunt tick
      -- (2 s) while he is that near, and the game's own AddThreatTargetEvent is sent once for him. No hits.
      local okp0, px0, py0, pz0 = pcall(world.position, world, id)
      if THREAT_ON and okp0 and px0 then  -- (0.15.524) off for the test
        local seen = S.threat_seen[id] or {}
        S.threat_seen[id] = seen
        for _, p in ipairs(spots) do
          local d = dist2(px0, py0, pz0, p[2], p[3], p[4])
          if d <= THREAT_R * THREAT_R then
            local oka, res = pcall(threat.alarm, world, id, p[1], math.sqrt(d))
            if not seen[p[1]] then
              seen[p[1]] = true
              local oke, sent = pcall(threat.event, id, p[1])
              if (S.threat_log or 0) < 120 then
                S.threat_log = (S.threat_log or 0) + 1
                local okl, line = pcall(threat.line, world, id)
                emf.log(string.format("spawn nodes: threat: monster %s at %.0f %.0f %.0f: player %s (%.0f m) written into its threat table: %s; event %s; table now [%s]",
                  tostring(id), px0, py0, pz0, tostring(p[1]), math.sqrt(d), oka and tostring(res) or ("error: " .. tostring(res)),
                  (oke and sent) and "sent" or "not sent", okl and line or "?"))
              end
            end
          end
        end
      end
      local o = S.orders[id]
      local okt, tgt = pcall(emf.enemy_target, world, id)
      local still = o and okt and tgt == o.target
      if HUNT_ON and emf.enemy_order and #spots > 0 and not still and (not o or os.time() - o.at >= 4) then  -- (0.15.524) off for the test
        local okp, x, y, z = pcall(world.position, world, id)
        if okp and x then
          local best, pid = nil, nil
          for _, p in ipairs(spots) do
            local d = dist2(x, y, z, p[2], p[3], p[4])
            if d <= HUNT_R * HUNT_R and (not best or d < best) then best, pid = d, p[1] end
          end
          if pid then
            if o and o.id then pcall(emf.enemy_order_cancel, o.id) end
            local ok, oid, why = pcall(emf.enemy_order, world, id, pid)
            S.orders[id] = { id = ok and oid or nil, target = pid, at = os.time(), n = ((o and o.n) or 0) + 1 }
            if ok and oid and (S.order_log or 0) < 80 then  -- (0.15.511, owner 16:17 "of course add the fucking logging")
              S.order_log = (S.order_log or 0) + 1
              emf.log(string.format("spawn nodes: hunt: monster %s at %.0f %.0f %.0f ordered at player %s (%.0f m away), order %s%s", tostring(id),
                x, y, z, tostring(pid), math.sqrt(best), tostring(oid), o and string.format(", again (#%d; it went for %s)", S.orders[id].n, tostring(okt and tgt)) or ""))
            end
            if not (ok and oid) and (S.order_said or 0) < 10 then
              S.order_said = (S.order_said or 0) + 1
              emf.log(string.format("spawn nodes: monster %s: no order to go for player %s (%s)", tostring(id), tostring(pid), tostring(ok and why or oid)))
            end
          end
        end
      end
    end
  end
  -- (0.15.511) every 10 s while monsters live: how many have an order, go for their player, moved
  S.hunt_n = (S.hunt_n or 0) + 1
  if S.hunt_n % 5 == 0 then
    local n, ordered, going, moved = 0, 0, 0, 0
    for _, id in ipairs(mon_alive()) do  -- (0.15.526) the roster
      do
        n = n + 1
        local o = S.orders[id]
        if o and o.id then ordered = ordered + 1 end
        local okt, tgt = pcall(emf.enemy_target, world, id)
        if o and okt and tgt == o.target then going = going + 1 end
        local okp, x, y, z = pcall(world.position, world, id)
        local last = S.hunt_pos[id]
        if okp and x then
          if last and dist2(x, y, z, last[1], last[2], last[3]) >= 1 then moved = moved + 1 end
          S.hunt_pos[id] = { x, y, z }
        end
      end
    end
    if n > 0 then
      emf.log(string.format("spawn nodes: hunt: %d raid monster(s) alive: %d with an order, %d going for their player, %d moved 1 m or more in the last 10 s",
        n, ordered, going, moved))
    end
  end
  for id in pairs(S.orders) do  -- dead or gone: forgotten
    local alive = false
    if S.mon[id] and not S.mon[id].dead then alive = true end  -- (0.15.526)
    if not alive then S.orders[id] = nil end
  end
  for id in pairs(S.threat_seen) do  -- (0.15.522)
    local alive = false
    if S.mon[id] and not S.mon[id].dead then alive = true end  -- (0.15.526)
    if not alive then S.threat_seen[id] = nil end
  end
end

-- (0.15.493, owner 14:33 "all monsters need to get "marked" always") Every living raid monster has an orange marker on
-- every player's game (EMF's send_marker: over the 3D view within NOTICE_DIST m, with an arrow at the screen's edge and
-- its health as a bar, and on the map at any distance). Every 2 s: new ones marked, dead or gone ones unmarked, a bar
-- sent again when the health moved 5 %; all sent again every MARK_RESEND s (players who joined since).
local MARK_COLOUR = 0xff9632ff
local MARK_RESEND = 15
local function mark_spec(id, share)
  return { entity = id, height = 2.6, text = "Raid monster", colour = MARK_COLOUR, shape = "diamond", edge_arrow = true,
           game_map = true, max_distance = NOTICE_DIST, bar = share }
end
-- (0.15.541, owner 2026-11-24 07:48 "the monsters are tagged with "Raid monster" when I stop the raid and remove the
-- monsters, I see a lot of these still on the screen"; 07:55 "yeah" to the fix) MARKERS STAY UNDER EMF's LIMIT AND
-- TAKE-OFFS ARE REPEATED. PROVEN 07:52 with the 0.15.540 marker log: EMF takes only ~39 marker messages in one go;
-- the rest answer 0 ("went to 0 players") and are dropped. 83 take-offs at once: 39 came off, 44 stayed on the
-- owner's screen, and the old code forgot them. Now each check (every 2 s) sends at most K.MARK_BUDGET messages, in this
-- order: take-offs, new markers, health bar updates, the 15 s resends (oldest first). A take-off is kept in S.unmark
-- and tried again every check until EMF answers 1 or more (K.MARK_OFF_TRIES at most: with nobody online it answers 0);
-- a new marker or bar update that answered 0 is tried again too. Logged per check: "spawn nodes: markers: ...".
local function delivered(ok, n) return ok and (type(n) ~= "number" or n >= 1) end
local function mark_tick(world)
  if not emf.send_marker then return end
  local now = os.time()
  S.unmark = S.unmark or {}
  -- (0.15.541, owner 07:58 "I would like to add an option to control whether it puts the raid monster on or not")
  -- only the monsters of groups whose "Mark its monsters" is on; switched off mid-raid: theirs are taken off
  local living, order = {}, {}
  for _, id in ipairs(mon_alive()) do
    local m = S.mon[id]
    local g = m and group(m.g)
    if not (g and g.mark == false) then order[#order + 1] = id living[id] = true end
  end
  for id in pairs(S.marked) do  -- gone from the roster: to be taken off
    if not living[id] then S.unmark[id] = S.unmark[id] or 0 S.marked[id] = nil end
  end
  local budget = K.MARK_BUDGET
  local c = { new = 0, bar = 0, again = 0, off = 0, zero = 0, errs = 0, retry = 0, gave = 0, off_ids = {}, new_ids = {} }
  -- 1. take-offs (also the ones EMF refused before)
  for id, tries in pairs(S.unmark) do
    if living[id] then S.unmark[id] = nil  -- back in the roster (got up): marked again below
    elseif budget > 0 then
      budget = budget - 1
      local ok, ans = pcall(emf.unsend_marker, nil, "m" .. id)
      if delivered(ok, ans) then
        S.unmark[id] = nil
        c.off = c.off + 1
        if #c.off_ids < 6 then c.off_ids[#c.off_ids + 1] = id end
      else
        if not ok then c.errs = c.errs + 1 if c.errs <= 5 then emf.log("spawn nodes: markers: taking off the marker of monster " .. tostring(id) .. " failed: " .. tostring(ans)) end end
        if tries + 1 >= K.MARK_OFF_TRIES then
          S.unmark[id] = nil
          c.gave = c.gave + 1
        else
          S.unmark[id] = tries + 1
          c.retry = c.retry + 1
        end
      end
    end
  end
  -- 2. new markers, 3. bar updates, 4. resends (oldest first)
  local function send(id, share)
    budget = budget - 1
    local ok, n = pcall(emf.send_marker, nil, "m" .. id, mark_spec(id, share))
    if not ok then ok, n = pcall(emf.send_marker, nil, "m" .. id, mark_spec(id, nil)) end  -- an older EMF: no bar
    if not ok then c.errs = c.errs + 1 if c.errs <= 5 then emf.log("spawn nodes: markers: sending the marker of monster " .. tostring(id) .. " failed: " .. tostring(n)) end end
    if ok and not delivered(ok, n) then c.zero = c.zero + 1 end
    return delivered(ok, n)
  end
  local shares = {}
  for _, id in ipairs(order) do
    local okh, cur, max = pcall(emf.health, world, id)
    if okh and cur and max and max > 0 then shares[id] = math.max(0, math.min(1, cur / max)) end
  end
  for _, id in ipairs(order) do
    if budget <= 0 then break end
    if not S.marked[id] and send(id, shares[id]) then
      S.marked[id] = { share = shares[id] or 1, at = now }
      c.new = c.new + 1
      if #c.new_ids < 6 then c.new_ids[#c.new_ids + 1] = id end
    end
  end
  for _, id in ipairs(order) do
    if budget <= 0 then break end
    local m = S.marked[id]
    if m and shares[id] and math.abs(shares[id] - (m.share or 1)) >= 0.05 and send(id, shares[id]) then
      m.share, m.at = shares[id], now
      c.bar = c.bar + 1
    end
  end
  if budget > 0 then
    local old = {}
    for _, id in ipairs(order) do
      local m = S.marked[id]
      if m and now - (m.at or 0) >= MARK_RESEND then old[#old + 1] = id end
    end
    table.sort(old, function(x, y) return (S.marked[x].at or 0) < (S.marked[y].at or 0) end)
    for _, id in ipairs(old) do
      if budget <= 0 then break end
      if send(id, shares[id]) then S.marked[id].at = now c.again = c.again + 1 end
    end
  end
  local waiting_new = 0
  for _, id in ipairs(order) do if not S.marked[id] then waiting_new = waiting_new + 1 end end
  local waiting_off = 0 for _ in pairs(S.unmark) do waiting_off = waiting_off + 1 end
  if c.new + c.bar + c.again + c.off + c.zero + c.errs + c.retry + c.gave > 0 then
    local function ids(t) local o = {} for _, v in ipairs(t) do o[#o + 1] = tostring(v) end return table.concat(o, " ") end
    local marked = 0 for _ in pairs(S.marked) do marked = marked + 1 end
    emf.log(string.format("spawn nodes: markers: %d sent of %d at most: %d new%s, %d bar update(s), %d sent again, %d answered 0 (again next check); "
      .. "%d taken off%s, %d refused (again next check), %d given up after %d tries; %d error(s); marked now %d, waiting: %d to mark, %d to take off",
      K.MARK_BUDGET - budget, K.MARK_BUDGET, c.new, c.new > 0 and (" [" .. ids(c.new_ids) .. (c.new > #c.new_ids and " ..." or "") .. "]") or "",
      c.bar, c.again, c.zero, c.off, c.off > 0 and (" [" .. ids(c.off_ids) .. (c.off > #c.off_ids and " ..." or "") .. "]") or "",
      c.retry, c.gave, K.MARK_OFF_TRIES, c.errs, marked, waiting_new, waiting_off))
  end
end

-- (0.15.526) Was the old tracking's health read (alive -> body, body -> alive again, spare rules); now the roster's
-- mon_check is the only one (above). Kept under its name: F.tick calls it.
local function clean_tick(world)
  mon_check(world)
end

-- (0.15.478) "Monsters damage buildings": each monster of such a group looks along the line to the nearest player within
-- BREAK_LOOK m (emf.find_wall); a player-built block within the level's reach on that line takes one hit (emf.break_blocks,
-- mode damage: cracks and the game's block health; never the ground or the world's own ruins). (0.15.481) How often, how
-- hard, how far and how big: the group's Building damage level (BREAK_LEVEL); with no wall on that line, a building block
-- beside it (four directions, the level's reach). Needs EMF Lua 1.37+ on the server (EMF 0.6.19); an older one:
-- S.no_break, said in the tab.
local function break_tick(world, spots)
  if not (emf.find_wall and emf.break_blocks) then
    for _, g in ipairs(groups()) do if g.breaks then S.no_break = true break end end
    return
  end
  local hits = 0
  for _, g in ipairs(groups()) do
    local lv = BREAK_LEVEL[g.break_level] or BREAK_LEVEL.high
    if g.breaks and S.steps % lv.every == 0 then
      local damage = {}
      for i, d in ipairs(PICKAXE) do damage[i] = math.floor(d * lv.mult) end
      for _, id in ipairs(mon_alive(g.id)) do  -- (0.15.526) the roster
        do
          if hits >= BREAK_MAX then return end
          local ok, x, y, z = pcall(world.position, world, id)
          if ok and x then
            local from = { x = x, y = y + 1, z = z }
            local wall = nil
            -- on its way to the nearest player within BREAK_LOOK m
            local best, px, py, pz = BREAK_LOOK * BREAK_LOOK, nil, nil, nil
            for _, p in ipairs(spots) do
              local d = dist2(p[2], p[3], p[4], x, y, z)
              if d <= best then best, px, py, pz = d, p[2], p[3], p[4] end
            end
            if px then
              local okw, w = pcall(emf.find_wall, world, from, { x = px, y = py + 1, z = pz })
              if okw and type(w) == "table" and w.kind == "building" and w.x and dist2(w.x, w.y, w.z, from.x, from.y, from.z) <= lv.reach * lv.reach then wall = w end
            end
            -- (0.15.481) else any player-built block right beside it
            if not wall then
              for _, dxz in ipairs(NEAR_DIRS) do
                local okw, w = pcall(emf.find_wall, world, from, { x = x + dxz[1] * lv.reach, y = y + 1, z = z + dxz[2] * lv.reach })
                if okw and type(w) == "table" and w.kind == "building" and w.x then wall = w break end
              end
            end
            if wall then
              local okb, bid = pcall(emf.break_blocks, world, wall.x, wall.y, wall.z, { radius = lv.radius, damage = damage }, function(w2, result)
                if type(result) == "table" and (tonumber(result.removed) or 0) > 0 then
                  S.broke[g.id] = (S.broke[g.id] or 0) + result.removed
                end
              end)
              if okb and bid then hits = hits + 1 S.active_at[id] = os.time() end  -- (0.15.493) busy, not stuck
            end
          end
        end
      end
    end
  end
end

-- (0.15.478) "Players cannot damage placed objects during its waves": while such a group runs (0.15.480: or any of its
-- monsters is alive), one EMF hit rule
-- cancels every player's hits on placed objects (chests, stations, doors...: EMF's "objects"), everywhere on the
-- server (EMF's rules have no area). Gone when no such group runs. Walls and floors are not hits: research.
-- (0.15.525, owner 18:32 "at what point did I ever fucking say to make is so monster cannot attack each other", 18:35
-- "fix the fuck up you made") "Monsters spare animals, pets and villagers": until 0.15.524 an EMF hit rule per
-- monster {from = it, to = "creatures", cancel}, and EMF's "creatures" are every creature, so raid monsters could hurt
-- no other monster either. Now FlameKit Native (build_anywhere.cpp, spare_hit) cancels only a listed monster's hits on
-- animals, pets and villagers (faction 5 Wildlife, 6 WildBeast, 11 PlayerAlly, 12 FarmAnimal, or a tame one); its
-- hits on players and on other monsters land. spare_server.txt: the ids of the living monsters of every group with the
-- switch on, one line; written when the list changes (every 2 s at most), and its size logged.
local function spare_tick()
  local ids = {}
  for _, id in ipairs(mon_alive()) do  -- (0.15.526) the roster
    local g = group(S.mon[id].g)
    if g and g.spare then ids[#ids + 1] = math.floor(tonumber(id) or 0) end
  end
  table.sort(ids)
  local text = table.concat(ids, " ")
  if text == S.spare_text then return end
  local f = io.open(emf.dir .. "\\spare_server.txt.tmp", "w")
  if not f then return end
  f:write(text, "\n")
  f:close()
  os.remove(emf.dir .. "\\spare_server.txt")
  if os.rename(emf.dir .. "\\spare_server.txt.tmp", emf.dir .. "\\spare_server.txt") then
    S.spare_text = text
    if (S.spare_log or 0) < 200 then
      S.spare_log = (S.spare_log or 0) + 1
      emf.log(string.format("spawn nodes: spare: %d raid monster(s) now spare animals, pets and villagers (FlameKit Native); their hits on monsters and players land", #ids))
    end
  end
end

local function protect_tick(world, spots)
  local want = false
  local lock = {}
  -- (0.15.480, owner 12:25 "keep the player damage protection up until all the monsters are dead? even if it finished the
  -- raid spawn waves") a protecting group counts while it runs AND while any monster of its nodes is still alive
  local active = {}
  for gid in pairs(S.runs) do active[gid] = true end
  for gid in pairs(S.raid) do active[gid] = true end  -- (0.15.500) until its end notice (no gap while a replacement comes)
  for _, g in ipairs(groups()) do
    if not active[g.id] and #mon_alive(g.id) > 0 then active[g.id] = true end  -- (0.15.526) any of its monsters (the roster)
  end
  for gid in pairs(active) do
    local g = group(gid)
    if g and g.protect then
      want = true
      -- (0.15.479) the players within its base distance (raid_r) of one of its nodes may not change bases while it
      -- runs: FlameKit Native clears their EDIT BASE permission (build_anywhere.cpp, raid lock), so the game itself
      -- refuses their building, dismantling and mining in bases
      for _, p in ipairs(spots or {}) do
        for _, n in ipairs(nodes_of(gid)) do
          if dist2(p[2], p[3], p[4], n.x, n.y, n.z) <= g.raid_r * g.raid_r then lock[#lock + 1] = p[1] break end
        end
      end
    end
  end
  table.sort(lock)
  local text = (#lock > 0 and (table.concat(lock, "\n") .. "\n") or "")
  if text ~= S.lock_text then
    local f = io.open(emf.dir .. "\\raid_lock_server.txt.tmp", "w")
    if f then
      f:write(text)
      f:close()
      os.remove(emf.dir .. "\\raid_lock_server.txt")
      if os.rename(emf.dir .. "\\raid_lock_server.txt.tmp", emf.dir .. "\\raid_lock_server.txt") then
        S.lock_text = text
        emf.log(string.format("spawn nodes: raid lock: %d player(s) may not change bases now", #lock))
      end
    end
  end
  -- (0.15.486, owner 13:05: the Undead could not be killed) players' hits on placed objects are cancelled by FlameKit
  -- Native (build_anywhere.cpp, protect_hit), which spares every creature; no EMF hit rule any more (EMF's "objects"
  -- class takes in monsters the game marks breakable). raid_protect_server.txt: "1" while wanted.
  -- (0.15.551, owner 12:12) the same file also makes FlameKit Native cancel players' hits on pets and animals (a tame
  -- one, or faction 12 FarmAnimal); nothing else changed here.
  if want ~= S.protect_on then
    local f = io.open(emf.dir .. "\\raid_protect_server.txt.tmp", "w")
    if f then
      f:write(want and "1\n" or "0\n")
      f:close()
      os.remove(emf.dir .. "\\raid_protect_server.txt")
      if os.rename(emf.dir .. "\\raid_protect_server.txt.tmp", emf.dir .. "\\raid_protect_server.txt") then
        S.protect_on = want
        emf.log(want and "spawn nodes: a raid runs: players' hits on placed objects are cancelled until its last monster is dead"
          or "spawn nodes: no raid with protection runs: players can hit placed objects again")
      end
    end
  end
end

-- (0.15.538) THE ANIMAL HOLD's every-second check (see hold_write): held while a raid is active, by the raid
-- protection's rule; rewritten every K.HOLD_BEAT_S so FlameKit Native keeps holding; let go when the raid is over or
-- after K.HOLD_MAX_S.
local function hold_tick()
  local active = next(S.runs) ~= nil or next(S.raid) ~= nil
  if not active then
    for _, g in ipairs(groups()) do
      if #mon_alive(g.id) > 0 then active = true break end
    end
  end
  local now = os.time()
  if not active then S.hold_capped = nil end
  if active and S.hold_capped then return end  -- let go at K.HOLD_MAX_S: stays free until this raid is over
  if active and S.hold_on and S.hold_since and now - S.hold_since >= K.HOLD_MAX_S then
    S.hold_capped = true
    hold_write(false, string.format("held %d min, the longest it may", math.floor(K.HOLD_MAX_S / 60)))
    return
  end
  if active then
    if not S.hold_on or now - (S.hold_at or 0) >= K.HOLD_BEAT_S then hold_write(true, "a raid is active") end
  elseif S.hold_on ~= false then
    hold_write(false, S.hold_on == nil and "no raid at the script's start" or "the raid is over (no group running, no raid monster alive)")
  end
end

-- The triggers of every group that is on and not running.
local function trigger_tick(world, spots)
  local tod = nil
  pcall(function() tod = emf.time_of_day(world) end)
  for _, g in ipairs(groups()) do
    local gid = g.id
    group(gid)
    if g.on and not S.runs[gid] and #nodes_of(gid) > 0 then
      if g.trigger == "timer" then
        if not S.next_timer[gid] then
          local lo, hi = math.min(g.timer_min, g.timer_max), math.max(g.timer_min, g.timer_max)
          S.next_timer[gid] = os.time() + math.random(lo * 60, hi * 60)
        elseif os.time() >= S.next_timer[gid] then
          -- (0.15.491) nobody near: it waits (fires when someone comes); any other refusal: a new time
          local ok, _, code = fire(world, gid, "the timer")
          if not ok and code ~= "nobody" then S.next_timer[gid] = nil end
        end
      elseif g.trigger == "wire" and g.wire then
        for _, p in ipairs(spots) do  -- (0.15.490) the one who crossed it
          if dist2(p[2], p[3], p[4], g.wire.x, g.wire.y, g.wire.z) <= g.wire_r * g.wire_r then
            fire(world, gid, "player " .. tostring(p[1]) .. " crossed the trip wire", false, p[1])
            break
          end
        end
      elseif g.trigger == "time" and tod then
        local last = S.last_tod[gid]
        local h = g.hour
        -- the clock passed the hour since the last check (also over midnight)
        if last and ((last < h and tod >= h) or (last > tod and (h > last or h <= tod))) then
          fire(world, gid, string.format("the time of day (%02d:00)", h))
        end
      elseif g.trigger == "raid" then
        local hit, by = false, nil
        for _, b in ipairs(altar_boxes()) do
          for _, p in ipairs(spots) do
            if p[2] >= b[1] and p[2] <= b[4] and p[3] >= b[2] and p[3] <= b[5] and p[4] >= b[3] and p[4] <= b[6] then
              local cx, cz = (b[1] + b[4]) / 2, (b[3] + b[6]) / 2
              for _, n in ipairs(nodes_of(gid)) do
                local dx, dz = n.x - cx, n.z - cz
                if dx * dx + dz * dz <= g.raid_r * g.raid_r then hit, by = true, p[1] break end
              end
            end
            if hit then break end
          end
          if hit then break end
        end
        if hit then fire(world, gid, "player " .. tostring(by) .. " is in a base near its nodes", false, by) end
      end
    end
    if tod then S.last_tod[gid] = tod end
  end
end

-- What group `gid` is doing, as a line for the tab.
local function status(gid)
  local g = group(gid)
  if not g then return "" end
  local run = S.runs[gid]
  local alive = #mon_alive(gid)  -- (0.15.526) the roster: its own ones and those counted apart
  local bodies = #mon_bodies(gid)
  local a = (alive > 0 and string.format(" %d of its monsters alive.", alive) or "")
    .. ((S.broke[gid] or 0) > 0 and string.format(" Blocks they broke: %d.", S.broke[gid]) or "")
    .. (bodies > 0 and string.format(" %d dead bod%s on the ground.", bodies, bodies == 1 and "y" or "ies") or "")
  if run then
    if run.wave == 0 then return "Running: the first wave starts now." .. a end
    if run.hold_until then  -- (0.15.543)
      return string.format("Running: its first monsters come in %d s.", math.max(0, math.floor((run.hold_until - S.steps) / 60))) .. a
    end
    if run.wait_dead then  -- (0.15.542)
      return string.format("Running: wave %d of %d, the next once %d or fewer of its monsters are left alive.", run.wave, run.waves,
        math.floor(run.wait_dead * (100 - (g.wave_dead or 0)) / 100)) .. a
    end
    return string.format("Running: wave %d of %d done, the next in %d s.", run.wave, run.waves,
      math.max(0, math.floor((run.next_at - S.steps) / 60))) .. a
  end
  if not g.on then return "Off." .. a end
  local cd = g.cooldown * 60 - (os.time() - (S.last_end[gid] or 0))
  if cd > 0 and S.last_end[gid] then return string.format("Cooling down: %d min %02d s left.", math.floor(cd / 60), cd % 60) .. a end
  if g.trigger == "timer" and S.next_timer[gid] then
    local t = math.max(0, S.next_timer[gid] - os.time())
    return string.format("Waiting: the timer fires in %d min %02d s.", math.floor(t / 60), t % 60) .. a
  end
  if g.trigger == "wire" and not g.wire then return "No trip wire yet: stand where it should be and press Put trip wire here." .. a end
  return "Waiting for its trigger." .. a
end

-- Whether this player is an admin (core/admins: EMF's admins, the host, npc_admins.json).
-- (0.15.546, owner 2026-11-24 08:43 "lets remove all the admin restrictions on the Spawn Nodes system for now so other
-- players can test it out") EVERY PLAYER COUNTS AS AN ADMIN HERE FOR NOW: they all get the groups and nodes, the tab, the
-- window and every action. To restrict it again: return admins.is(account, from) == true (the line below).
local function is_admin(account, from)
  local _ = admins.is  -- kept for when it is restricted again
  return true
end

-- The state for one player's game: the groups and nodes only for an admin.
local function state(world, account, from)
  local st = { op = "state", admin = is_admin(account, from) or nil, note = S.notes[tostring(account)] }
  S.notes[tostring(account)] = nil
  if not st.admin then return st end
  st.groups, st.nodes, st.status = {}, {}, {}
  for _, g in ipairs(groups()) do
    group(g.id)
    local c = {}
    for k, v in pairs(g) do c[k] = v end
    c.running = S.runs[g.id] and true or nil
    st.groups[#st.groups + 1] = c
    st.status[tostring(g.id)] = status(g.id)
  end
  for _, n in pairs(data().nodes) do
    st.nodes[#st.nodes + 1] = { n.id, n.g, math.floor(n.x * 10 + 0.5) / 10, math.floor(n.y * 10 + 0.5) / 10, math.floor(n.z * 10 + 0.5) / 10, tonumber(n.spread) or SPREAD }  -- (0.15.485) [6] its spread
  end
  table.sort(st.nodes, function(a, b) return a[1] < b[1] end)
  st.max_nodes, st.max_groups = MAX_NODES, MAX_GROUPS
  st.no_break = S.no_break
  return st
end

-- Whether `v` is one of the choices of `key`.
local function allowed(key, v)
  if key == "family" then for _, f in ipairs(FAMILIES) do if f == v then return true end end return false end
  if key == "trigger" then for _, t in ipairs(TRIGGERS) do if t == v then return true end end return false end
  if key == "face" then for _, f in ipairs(FACES) do if f == v then return true end end return false end
  if key == "break_level" then return BREAK_LEVEL[v] ~= nil end
  for _, c in ipairs(CHOICES[key] or {}) do if c == v then return true end end
  return false
end

-- A message from a player's game (or the host's own click): does it, and answers with the state.
local function handle(world, account, entity, msg, from)
  account = tostring(account)
  local function note(text) S.notes[account] = text end
  if msg.op == "get" then return state(world, account, from) end
  if msg.op == "place" then  -- (0.15.490) where the asked player is, at a raid's start: only from the one asked
    local q = tonumber(msg.q)
    for _, r in pairs(S.raid) do
      if r.ask and r.ask.q == q and r.ask.by == entity then
        S.place_answers[q] = { place = type(msg.place) == "string" and msg.place or "", region = type(msg.region) == "string" and msg.region or "" }
      end
    end
    return nil
  end
  if not is_admin(account, from) then
    note("Only FlameKit admins can set up spawn nodes.")
    return state(world, account, from)
  end
  local d = data()
  local gid = tonumber(msg.g)
  local g = gid and group(gid)
  local who = tostring(entity)
  if msg.op == "new_group" then
    if #groups() >= MAX_GROUPS then note("The limit of " .. MAX_GROUPS .. " groups is reached.") return state(world, account, from) end
    local id = d.next_g
    d.next_g = id + 1
    local ng = { id = id, name = "Group " .. id }
    for k, v in pairs(DEFAULTS) do ng[k] = v end
    d.groups[tostring(id)] = ng
    save()
    emf.log(string.format("spawn nodes: player %s made %s", who, ng.name))
    local st = state(world, account, from)
    st.made = id
    return st
  elseif msg.op == "delete_group" and g then
    local n = 0
    for k, node in pairs(d.nodes) do if node.g == gid then d.nodes[k] = nil n = n + 1 end end
    d.groups[tostring(gid)] = nil
    S.runs[gid], S.next_timer[gid] = nil, nil
    save()
    emf.log(string.format("spawn nodes: player %s deleted %s and its %d node(s)", who, g.name, n))
    note(string.format("Deleted %s and its %d node(s).", g.name, n))
  elseif msg.op == "set" and g then
    local key, v = tostring(msg.key), msg.value
    if key == "on" or key == "breaks" or key == "protect" or key == "spare" or key == "announce" or key == "mark" then  -- (0.15.541) mark  -- (0.15.488) announce  -- (0.15.478) the raid switches; (0.15.482) spare
      g[key] = v == true
    elseif allowed(key, v) then
      g[key] = v
      if key == "loot" then for _, mid in ipairs(mon_alive(gid)) do if S.mon[mid] and S.mon[mid].sp then pcall(K.mark_loot, mid, gid) end end end  -- (0.15.547)
      if key == "trigger" or key == "timer_min" or key == "timer_max" then S.next_timer[gid] = nil end
    else
      note("That setting was refused.")
      return state(world, account, from)
    end
    save()
    emf.log(string.format("spawn nodes: player %s set %s %s = %s", who, g.name, key, tostring(v)))
  elseif msg.op == "add_node" and g then
    if node_count() >= MAX_NODES then note("The limit of " .. MAX_NODES .. " nodes is reached.") return state(world, account, from) end
    local ok, x, y, z = pcall(world.position, world, entity)
    if not (ok and x) then note("Your position is not known.") return state(world, account, from) end
    local id = d.next_n
    d.next_n = id + 1
    d.nodes[tostring(id)] = { id = id, g = gid, x = x, y = y, z = z, yaw = facing(world, entity) }
    save()
    emf.log(string.format("spawn nodes: player %s added node %d to %s at %.0f %.0f %.0f", who, id, g.name, x, y, z))
    note(string.format("Node %d added to %s here.", id, g.name))
  elseif msg.op == "move_node" or msg.op == "delete_node" then
    local n = d.nodes[tostring(tonumber(msg.n) or -1)]
    if not n then note("That node is gone.") return state(world, account, from) end
    if msg.op == "delete_node" then
      d.nodes[tostring(n.id)] = nil
      for id, m in pairs(S.mon) do if m.n == n.id then mon_drop(id) end end  -- (0.15.526) as before: its monsters forgotten
      note(string.format("Node %d deleted.", n.id))
      emf.log(string.format("spawn nodes: player %s deleted node %d", who, n.id))
    else
      local ok, x, y, z = pcall(world.position, world, entity)
      if not (ok and x) then note("Your position is not known.") return state(world, account, from) end
      n.x, n.y, n.z = x, y, z
      n.yaw = facing(world, entity)  -- (0.15.477) the node's direction: the way he faces now
      note(string.format("Node %d moved here.", n.id))
      emf.log(string.format("spawn nodes: player %s moved node %d to %.0f %.0f %.0f", who, n.id, x, y, z))
    end
    save()
  elseif msg.op == "node_spread" then  -- (0.15.485) a node's "Spawn within"
    local n = d.nodes[tostring(tonumber(msg.n) or -1)]
    if not n then note("That node is gone.") return state(world, account, from) end
    local v, okv = tonumber(msg.value), false
    for _, c in ipairs(SPREADS) do if c == v then okv = true end end
    if not okv then note("That setting was refused.") return state(world, account, from) end
    n.spread = v
    save()
    emf.log(string.format("spawn nodes: player %s set node %d's spawn distance to %d m", who, n.id, v))
  elseif msg.op == "wire_here" and g then
    local ok, x, y, z = pcall(world.position, world, entity)
    if not (ok and x) then note("Your position is not known.") return state(world, account, from) end
    g.wire = { x = x, y = y, z = z }
    save()
    note(string.format("%s's trip wire is here: a player within %d m of this spot fires it.", g.name, g.wire_r))
    emf.log(string.format("spawn nodes: player %s put %s's trip wire at %.0f %.0f %.0f", who, g.name, x, y, z))
  elseif msg.op == "start" and g then
    local ok, why = fire(world, gid, "Start now by player " .. who, true, entity)
    note(ok and (g.name .. " started.") or (why or "It could not start."))
  elseif msg.op == "stop" and g then
    -- (0.15.514, owner 16:34 "the stop button doesnt stop the raid. its still spawning monsters": Stop ended the waves but
    -- not the spots being checked, the queue, nor the replacing of stuck monsters) Stop: nothing more spawns for the
    -- group; the monsters alive stay (Remove takes them away)
    local was = S.runs[gid] ~= nil
    if was then finish(gid) end
    S.halted[gid] = true
    cancel_checks(gid)
    local dropped = 0
    for i = #S.queue, 1, -1 do
      local qn = d.nodes[tostring(S.queue[i].node)]
      if qn and qn.g == gid then table.remove(S.queue, i) dropped = dropped + 1 end
    end
    emf.log(string.format("spawn nodes: player %s stopped %s (%s; %d queued monster(s) dropped)", who, g.name, was and "its waves ended" or "no waves were running", dropped))
    note(g.name .. " stopped: no more monsters come (its cooldown starts now). Remove its monsters takes away the ones still alive.")
  elseif msg.op == "remove" and g then
    local n, bodies = 0, 0
    -- (0.15.526) the roster: its living monsters (its own and those counted apart), then its bodies of every raid
    for _, id in ipairs(mon_alive(gid)) do
      if pcall(emf.destroy, world, id) then n = n + 1 end
      mon_drop(id)
    end
    for _, id in ipairs(mon_bodies(gid)) do  -- (0.15.482)
      if pcall(emf.destroy, world, id) then bodies = bodies + 1 end
      mon_drop(id)
      S.old_bodies[id] = nil
    end
    for i = #S.queue, 1, -1 do
      local q = S.queue[i]
      local qn = d.nodes[tostring(q.node)]
      if qn and qn.g == gid then table.remove(S.queue, i) end
    end
    emf.log(string.format("spawn nodes: player %s removed %d monster(s) and %d dead bod(ies) of %s", who, n, bodies, g.name))
    note(string.format("Removed %d monster(s) and %d dead bod%s of %s; the rest of the world is being searched for more.", n, bodies, bodies == 1 and "y" or "ies", g.name))
    S.started[gid] = nil  -- (0.15.492)
    cancel_checks(gid)  -- (0.15.513)
    S.halted[gid] = true  -- (0.15.514) nothing more comes
    if S.raid[gid] then  -- (0.15.488)
      if S.runs[gid] then finish(gid) end
      raid_notice(world, gid, string.format("The raid on %s was called off.", S.raid[gid].place or "the area"), nil, START_END_S)
      raid_notice(world, gid, "", true, 1, "left_" .. gid)
      S.raid[gid] = nil
    end
    -- (0.15.487) then the whole world, for the group's tagged ones FlameKit lost track of
    if S.purge and S.purge.list then S.purge.gids[gid] = g.name  -- joins the search under way (it may miss some behind it: Remove again)
    else S.purge = S.purge or { gids = {} } S.purge.gids[gid] = g.name end
  end
  return state(world, account, from)
end

function F.tick(world)
  if not world:is_server() then return end
  S.steps = S.steps + 1
  K.t0, K.times = clock and clock() or nil, {}  -- (0.15.556) the step's time limit starts
  local okb, whyb = pcall(K.step, world)
  if clock and K.t0 then
    local used = clock() - K.t0
    if used > K.SLOW_S and (K.slow_n or 0) < K.SLOW_LOG then
      K.slow_n = (K.slow_n or 0) + 1
      emf.log(string.format("spawn nodes: slow step: %.0f ms (%s); %d queued, %d alive", used * 1000, table.concat(K.times, ", "),
        #S.queue, #mon_alive()))
    end
  end
  if not okb then error(whyb, 0) end
end
function K.step(world)
  local session = emf.session()
  if session ~= S.session then  -- a new world (or this script just loaded): the old ids mean nothing; scan again
    S.session, S.queue, S.runs = session, {}, {}
    S.mon, S.old_bodies = {}, {}  -- (0.15.526) the roster
    S.scan, S.scanned, S.purge, S.raid, S.started = nil, false, nil, {}, {}
    S.track, S.active_at, S.respawns, S.marked = {}, {}, {}, {}  -- (0.15.493)
    S.unmark = {}  -- (0.15.541) take-offs EMF has not taken yet
    S.wet, S.depth_said = {}, {}  -- (0.15.497)
    S.join_hits, S.join_seen, K.jn = {}, nil, nil  -- (0.15.501); (0.15.558) K.jn
    S.orders = {}  -- (0.15.503)
    S.bad, S.verify = {}, nil  -- (0.15.505)
    S.join_wait = {}  -- (0.15.507)
    S.checks = {}  -- (0.15.508)
    S.hunt_pos = {}  -- (0.15.511)
    S.halted = {}  -- (0.15.514)
    S.threat_seen = {}  -- (0.15.522)
    S.hitby, S.lvl_said = {}, {}  -- (0.15.547)
  end
  if not S.scanned then  -- (0.15.483) find the nodes' monsters again first; nothing else until then
    if scan_tick(world) then
      pcall(restore)  -- (0.15.498) and the raids that were running
      -- (0.15.555, owner 2026-11-24 21:01 "yes": G-Portal 20:51/20:56, a 135-a-wave raid paused FlameKit (EMF's 250 ms
      -- rule) and each reload took the raid back and it paused again 2 s later) a raid running at a reload is NOT carried
      -- on: every run taken back is stopped as its Stop button does (cooldown starts, no more waves or spawns) and the
      -- raids' counts are forgotten. Its monsters still alive stay in the world (the protection holds while they live).
      local ended = 0
      S.halted = S.halted or {}
      for gid in pairs(S.runs) do finish(gid) S.halted[gid] = true cancel_checks(gid) ended = ended + 1 end
      S.runs, S.queue, S.raid = {}, {}, {}
      if ended > 0 then emf.log(string.format("spawn nodes: after the reload: %d running raid(s) ended, not carried on", ended)) end
    end
    return
  end
  if S.purge then K.part("purge", purge_tick, world) end  -- (0.15.487)
  K.part("reward", pcall, K.reward.tick, world)  -- (0.15.547) Reward loot's chests and the game loot it removes (once per world step)
  if S.steps % FAST_STEPS == 5 then K.part("timeouts", check_timeouts, world) end  -- (0.15.515)
  if S.steps % FAST_STEPS == 4 then local okt, why = K.part("trickle", pcall, trickle_tick, world) if not okt then emf.log("spawn nodes: trickle_tick: " .. tostring(why)) end end  -- (0.15.512)
  if S.verify then K.part("verify", verify_tick, world) end  -- (0.15.505)
  if K.jn or S.steps % JOIN_EVERY == 7 then local okj, why = K.part("join", pcall, join_tick, world) if not okj then K.jn = nil emf.log("spawn nodes: join_tick: " .. tostring(why)) end end  -- (0.15.501); (0.15.558) a look not through goes on each step
  K.part("spawn", spawn_tick, world)
  -- (0.15.515, owner 16:42 "the nodes are spawning monsters too slowly? if a node spawns a monster and it gets killed it
  -- needs to immediately spawn another one": a death was seen only every 2 s (clean_tick) and the next one queued every
  -- 0.5 s (trickle_tick)) deaths are seen and the next monster queued every 0.25 s
  if S.steps % FAST_STEPS == 3 and S.steps % CLEAN_STEPS ~= 0 then K.part("clean", clean_tick, world) end
  if S.steps % FAST_STEPS == 3 then local okl, why = K.part("left", pcall, left_tick, world) if not okl then emf.log("spawn nodes: left_tick: " .. tostring(why)) end end  -- (0.15.544) the countdown as deaths are seen
  if S.steps % CLEAN_STEPS == 0 then
    K.part("clean", clean_tick, world) K.part("stuck", stuck_tick, world) K.part("mark", pcall, mark_tick, world)  -- (0.15.493) stuck_tick, mark_tick
    local okh, why = K.part("hunt", pcall, hunt_tick, world)  -- (0.15.503); (0.15.556) stops at the time limit, on next time
    if not okh then emf.log("spawn nodes: hunt_tick: " .. tostring(why)) end
  end

  -- (0.15.556) the once-a-second checks wait one step when this step's time is used up (never two in a row)
  local check = S.steps % CHECK_STEPS == 0 or K.check_late
  if check and K.over() and not K.check_late then K.check_late, check = true, false else K.check_late = false end
  local need_spots = check or S.steps % BREAK_STEPS == 0
  for _ in pairs(S.runs) do need_spots = true break end
  if not need_spots then return end
  local spots = player_spots(world)
  for gid, run in pairs(S.runs) do
    -- (0.15.542, owner 2026-11-24 08:08 "the next wave can't start until most of the first wave is dead" (90%), "make
    -- that an option": the group's "Next wave after") Between waves starts only when the group has no more than
    -- (100 - wave_dead)% of the last wave's size alive (monsters of earlier waves still alive count too). A monster
    -- that never dies holds the raid until "Raid lasts at most" ends it.
    if run.wait_dead then
      local g = group(gid)
      local left = math.floor(run.wait_dead * (100 - ((g and g.wave_dead) or 0)) / 100)
      local alive = #mon_alive(gid)
      if alive <= left then
        emf.log(string.format("spawn nodes: %s wave %d: %d of its monsters left alive (%d or fewer wanted): the next wave comes in %d s",
          g and g.name or tostring(gid), run.wave, alive, left, g and g.wave_gap or 0))
        run.wait_dead = nil
        run.next_at = S.steps + ((g and g.wave_gap) or 0) * 60
      end
    end
    if S.steps >= run.next_at and not run.in_wave and not run.wait_dead then K.part("wave", wave, world, gid, spots) end  -- (0.15.512) not while a wave still spawns; (0.15.542) nor while its dead are awaited
  end
  if check then
    K.part("trigger", trigger_tick, world, spots)
    K.part("protect", protect_tick, world, spots)
    local okhd, whyhd = K.part("hold", pcall, hold_tick)  -- (0.15.538) the animal hold
    if not okhd then emf.log("spawn nodes: animal hold: " .. tostring(whyhd)) end
    K.part("spare", pcall, spare_tick)  -- (0.15.525)
    K.part("raid", raid_tick, world)  -- (0.15.488)
    K.part("time", time_tick, world)  -- (0.15.492)
    K.part("persist", pcall, persist)  -- (0.15.498)
  end
  if S.steps % BREAK_STEPS == 0 then K.part("break", break_tick, world, spots) end
end

-- ---- the player's game ----

local C = { shown = nil, since_ask = ASK_STEPS, note = nil, sel = nil, show = nil, marks = {}, marks_key = nil,
            del_asked = nil, last_peer = nil, no_markers = nil }

local function hosting(world)
  return kit.is_host() or world:is_server()
end

local function peer()
  local ok, version = pcall(emf.net.peer, nil, 0, CHANNEL)
  return ok and version or 0
end

-- "Show nodes": this game's own switch (on unless switched off), kept in spawn_nodes_client.json.
local function show_on()
  if C.show == nil then
    local ok, v = pcall(kit.store.load, "spawn_nodes_client", nil)
    C.show = not (ok and type(v) == "table" and v.show == false)
  end
  return C.show
end

local function my_state(world)
  if hosting(world) then
    local me = emf.local_player()
    if not me or me == 0 then return nil end
    local ok, account = pcall(world.account, world, me)
    if not (ok and account) then return nil end
    return state(world, account, { is_local = true })
  end
  return C.shown
end

local function ask(msg)
  local ok, sent = pcall(emf.net.send, CHANNEL, emf.json.encode(msg))
  C.since_ask = 0
  return ok and sent == true
end

local function act(world, msg)
  if hosting(world) then
    local me = emf.local_player()
    local ok, account = pcall(world.account, world, me)
    if ok and account then
      local st = handle(world, account, me, msg, { is_local = true }) or {}
      C.note = st.note
      if st.made then C.sel = st.made end
    end
  elseif C.shown then
    ask(msg)
  end
end

-- The markers of this game: every node and trip wire, while this player is an admin and "Show nodes" is on.
local function markers(world)
  local v = my_state(world)
  local want = {}
  if v and v.admin and show_on() then
    local names, colour = {}, {}
    for i, g in ipairs(v.groups or {}) do
      names[g.id] = g.name
      colour[g.id] = COLOURS[(i - 1) % #COLOURS + 1]
      if g.trigger == "wire" and g.wire then
        want["w" .. g.id] = { x = g.wire.x, y = g.wire.y, z = g.wire.z, height = 0.5, shape = "circle", colour = colour[g.id],
          text = string.format("%s: trip wire (%d m)", g.name, g.wire_r), game_map = true, max_distance = 300 }
      end
    end
    for _, n in ipairs(v.nodes or {}) do
      want["n" .. n[1]] = { x = n[3], y = n[4], z = n[5], height = 1.5, colour = colour[n[2]] or COLOURS[1],
        text = string.format("%s: node %d", names[n[2]] or "?", n[1]), game_map = true, max_distance = 300 }
    end
  end
  local key = emf.json.encode(want)
  if key == C.marks_key then return end
  C.marks_key = key
  if not emf.marker then C.no_markers = next(want) ~= nil return end
  for id in pairs(C.marks) do
    if not want[id] then pcall(emf.remove_marker, id) C.marks[id] = nil end
  end
  for id, spec in pairs(want) do
    local ok, set = pcall(emf.marker, id, spec)
    C.marks[id] = true
    if not (ok and set) then kit.debug("warn", "spawn nodes: marker %s refused (%s)", id, tostring(set)) end
  end
end

-- (0.15.490) What this game's minimap names as where the player is: place, region ("" each when not known), from
-- where_now.txt (FlameKit Native writes it when it changes).
local function where_now()
  local f = io.open(emf.dir .. "\\where_now.txt", "r")
  if not f then return "", "" end
  local line = f:read("*l") or ""
  f:close()
  local place, region = line:match("^([^\t]*)\t?([^\t]*)")
  return place or "", region or ""
end

function F.client_tick(world)
  if S.host_ask then  -- (0.15.490) the host's own game asked: answered here directly
    local place, region = where_now()
    S.place_answers[S.host_ask.q] = { place = place, region = region }
    S.host_ask = nil
  end
  local version = peer()
  if version ~= C.last_peer then C.last_peer, C.shown, C.since_ask = version, nil, ASK_STEPS end
  C.since_ask = C.since_ask + 1
  -- an admin's game asks every ASK_STEPS; a player who is not one only every ASK_STEPS_PLAYER (he gets no list)
  local every = (C.shown and not C.shown.admin) and ASK_STEPS_PLAYER or ASK_STEPS
  if not hosting(world) and version ~= 0 and C.since_ask >= every then ask({ op = "get" }) end
  if C.since_ask % 30 == 0 or hosting(world) then pcall(markers, world) end
end

-- One drop-down row: `key` of group g, its choices as text.
local function choice_row(rows, g, key, title, tip, list, show)
  local opts = {}
  for _, c in ipairs(list or CHOICES[key]) do
    opts[#opts + 1] = { key = "set:" .. key .. ":" .. tostring(c), text = show and show(c) or label(key, c), selected = g[key] == c }
  end
  rows[#rows + 1] = { label = true, text = title }
  rows[#rows + 1] = { options = opts, text = show and show(g[key]) or label(key, g[key]), same_line = true, tooltip = tip }
end

-- ============================================================================================================
-- (0.15.539, owner 2026-11-24 07:13 "cleaning up the UI you made. it looks awful", 07:16 "We need to move a lot of
-- this out to its own window so its easier to create and manage nodes as I'm moving around the map") THE TAB and THE
-- SPAWN NODES WINDOW. The tab keeps the group's setup (Groups / Raid rules / Monsters / When); the window (FlameKit
-- Native's third Experimental-style window, rows in ui_nodes.dat via features/native_ui.lua, clicks "nod ...", shown
-- and hidden by ui_nodes_toggle.request) has what is used out on the map: the group, Start / Stop / Remove, Add node
-- here, Show nodes, Put trip wire here, and the nearest nodes one line each. Both share the chosen group (C.sel) and
-- F.click. Labels followed by a drop-down line up in a column (FlameKit Native's form alignment, 0.15.539).
-- ============================================================================================================

-- The group shown (C.sel, else the first) and the group list.
local function shown_group(v)
  local list = v.groups or {}
  local g = nil
  for _, x in ipairs(list) do if x.id == C.sel then g = x end end
  if not g then g = list[1] C.sel = g and g.id or nil end
  return g, list
end

-- The group drop-down row (label + drop-down).
local function group_row(rows, g, list)
  local opts = {}
  for _, x in ipairs(list) do
    opts[#opts + 1] = { key = "sel:" .. x.id, text = x.name .. (x.on and "" or " (off)") .. (x.running and " (running)" or ""), selected = x.id == g.id }
  end
  rows[#rows + 1] = { label = true, text = "Group" }
  rows[#rows + 1] = { options = opts, text = g.name .. (g.running and " (running)" or ""), same_line = true, tooltip = "The group these settings and nodes belong to." }
end

-- An on/off switch row.
local function switch_row(rows, key, on, text, tip)
  rows[#rows + 1] = { button = key, text = (on and "On    " or "Off   ") .. text, selected = on or nil, tooltip = tip }
end

-- Opens or closes the Spawn Nodes window (FlameKit Native shows or hides it when this file appears).
local function toggle_window()
  local f = emf.dir and io.open(emf.dir .. "\\ui_nodes_toggle.request", "w")
  if f then f:write("toggle\n") f:close() end
end

-- The tab: the group's setup.
function F.panel(world)
  local v = my_state(world)
  if not v then
    return { { dim = true, text = (hosting(world) or peer() ~= 0) and "Asking the server..."
      or "This server does not run FlameKit's Spawn Nodes (or not this version)." } }
  end
  local rows = {}
  local note = C.note or v.note
  if note then rows[#rows + 1] = { color = "#ffb060", text = note } end
  if not v.admin then
    rows[#rows + 1] = { dim = true, text = "Only FlameKit admins can set up spawn nodes." }
    return rows
  end
  local g, list = shown_group(v)
  -- (0.15.554, owner 13:19 "The "Nodes" section on the "Spawn Nodes" tab needs to get moved all the way to the top so
  -- users do not have to scroll all the way to the bottom to find it") the Nodes section first (it was last)
  if g then
    local n_nodes = 0
    for _, n in ipairs(v.nodes or {}) do if n[2] == g.id then n_nodes = n_nodes + 1 end end
    rows[#rows + 1] = { heading = "Nodes" }
    rows[#rows + 1] = { dim = true, text = string.format("%s has %d node%s. Add, move and delete them in the Spawn Nodes window.", g.name, n_nodes, n_nodes == 1 and "" or "s") }
    rows[#rows + 1] = { button = "window", text = "Spawn Nodes window",
      tooltip = "Opens or closes the Spawn Nodes window." }
  end
  rows[#rows + 1] = { heading = "Groups" }
  if g then group_row(rows, g, list)
  else rows[#rows + 1] = { dim = true, text = "No groups yet: make one with New group." } end
  rows[#rows + 1] = { button = "new", text = "New group", disabled = (#list >= (v.max_groups or MAX_GROUPS)) or nil,
    tooltip = "Makes a new group with the default settings: Random monsters, started by hand, 3 waves 30 s apart, 3 monsters per node in each wave." }
  if g then
    local asked = C.del_asked and C.del_asked.g == g.id and os.time() - C.del_asked.at <= 5
    rows[#rows + 1] = { button = "delgroup", same_line = true, selected = asked or nil,
      text = asked and "Click again to delete" or "Delete group",
      tooltip = "Deletes " .. g.name .. " and all its nodes. Click twice within 5 seconds." }
  end
  rows[#rows + 1] = { button = "window", same_line = true, text = "Spawn Nodes window",
    tooltip = "Opens or closes the Spawn Nodes window: the group, Start / Stop, Add node here and its nodes, to use while you move around the map." }
  if not g then return rows end
  local status = (v.status or {})[tostring(g.id)]
  if status and status ~= "" then rows[#rows + 1] = { dim = true, text = status } end

  rows[#rows + 1] = { heading = "Raid rules" }
  switch_row(rows, "on", g.on == true, "Group on", "Off: its trigger never fires (Start now still works).")
  switch_row(rows, "announce", g.announce ~= false, "Announce the raid to players",  -- (0.15.488)
    "Orange FlameKit notices: when it starts (to every player, with the name of the nearest flame altar), each new wave and how "
      .. "many monsters are left (to the players within " .. NOTICE_DIST .. " m of its nodes), and when it is over.")
  switch_row(rows, "mark", g.mark ~= false, "Mark its monsters",  -- (0.15.541, owner 07:58)
    "An orange Raid monster marker over each of its living monsters, with a health bar and an arrow at the screen's edge, and on the map, "
      .. "on every player's game. Off: no markers (switched off during a raid, the ones up come off).")
  switch_row(rows, "spare", g.spare == true, "Monsters spare animals, pets and villagers",  -- (0.15.552, owner 12:26: "Its" taken off the label)
    "Its monsters' hits on anything that is not a player do nothing: farm animals, pets, mounts, villagers and companions are "
      .. "safe from them (other monsters too). Players are not covered: they can still be hit.")
  switch_row(rows, "protect", g.protect == true, "Players cannot damage base structures during raid",  -- (0.15.484, owner 12:50: the label)
    "While its waves run, and until the last of its monsters is dead: players within its Base within distance (" .. g.raid_r .. " m) of one of its nodes lose the game's own "
      .. "base editing permission, so they cannot build, dismantle or mine in bases (they get it back when that is over or they "
      .. "leave that range); and players' hits on placed objects (chests, crafting stations, doors and the like) do nothing, on the whole server; "
      .. "and players' hits on pets and animals (tamed ones and farm animals) do nothing, on the whole server. "
      .. "Admins too, for now.")
  switch_row(rows, "breaks", g.breaks == true, "Monsters damage buildings",
    "Its monsters hit player-built blocks: on their way to the nearest player, or right beside them. How often and how hard: "
      .. "Building damage below. Never the ground or the world's own ruins. Inside a flame altar's area what breaks stays broken. "
      .. "Needs EMF 0.6.19 on the server.")
  if g.breaks then
    choice_row(rows, g, "break_level", "Building damage", "Low: a hit every 3 s like a top pickaxe, blocks within 4 m. Medium: every 1.5 s, "
      .. "twice as hard, 5 m. High: every 1 s, 4 times as hard, 6 m, 1.5 m holes. Extreme: every 0.5 s, 8 times as hard, 6 m, 1.5 m holes. "
      .. "Stone takes about 22 top-pickaxe hits.", BREAK_LEVELS, function(l) return (BREAK_LEVEL[l] or {}).label or l end)
    if v.no_break then rows[#rows + 1] = { color = "#ffb060", text = "This server's EMF cannot break blocks: it needs EMF 0.6.19." } end
  end

  rows[#rows + 1] = { heading = "Monsters" }
  choice_row(rows, g, "family", "Monsters", "Which monsters its nodes spawn: one kind, Random (any kind, no bosses) or Bosses (any boss: set Monsters per node to 1 for one boss).",
    FAMILIES, function(f) return FAMILY_LABEL[f] or f end)
  choice_row(rows, g, "face", "Monsters face", "Which way a monster faces when it appears: the nearest player, the node's direction "
    .. "(the way you faced when you added or last moved the node), or a random way.", FACES, function(f) return FACE_LABEL[f] or f end)
  choice_row(rows, g, "per_wave", "Monsters per node", "How many monsters each node spawns in one wave, one after another (see Most alive per node). "
    .. "The wave is over when every node has spawned all of them; then Between waves starts.")  -- (0.15.512)
  choice_row(rows, g, "max_alive", "Most alive per node", "At most this many of a node's monsters are alive at once: its next one comes when one of them dies. "
    .. "1: one at a time.")
  choice_row(rows, g, "start_level", "Starting level", "The level of the first wave's monsters (1 to " .. K.MAX_LEVEL .. ").")  -- (0.15.547, owner 09:41; 0.15.548 no "Game's own")
  choice_row(rows, g, "level_step", "Level per wave", "Added to the level for each wave after the first. Wave 3 at Starting level 20 "
    .. "and +10 each wave: level 40. Never above " .. K.MAX_LEVEL .. ", whatever is set.")
  choice_row(rows, g, "loot", "Loot", "What its monsters drop. Normal monster loot: what the game gives. Reward loot: like the test "
    .. "monsters: runes and legendary runes into the bag of the last player who hit it, and a legendary item at its level in a "
    .. "loot chest by the body (twice for bosses); nothing of the game's own. Reward + normal loot: both. No loot: nothing at all.")

  rows[#rows + 1] = { heading = "When" }
  choice_row(rows, g, "trigger", "Trigger", "What starts its waves. Start now works with every trigger.", TRIGGERS, function(t) return TRIGGER_LABEL[t] or t end)
  if g.trigger == "timer" then
    choice_row(rows, g, "timer_min", "Timer from", "The timer fires at a random time between these two (after the cooldown).")
    choice_row(rows, g, "timer_max", "Timer to", "The timer fires at a random time between these two (after the cooldown).")
  elseif g.trigger == "wire" then
    choice_row(rows, g, "wire_r", "Trip wire size", "A player this close to the trip wire's spot fires it.")
  elseif g.trigger == "time" then
    choice_row(rows, g, "hour", "At", "Fires when the game's clock passes this hour.")
  elseif g.trigger == "raid" then
    choice_row(rows, g, "raid_r", "Base within", "Fires when a player is inside a flame altar's area whose middle is this close to one of the group's nodes.")
  end
  choice_row(rows, g, "near_r", "Player within", "It starts only when a player is this close to one of its nodes (any trigger, also Start now), "
    .. "and its waves come only while one is. A timer that is due waits for a player; a time of day with nobody near is skipped that day.")  -- (0.15.491)
  choice_row(rows, g, "start_delay", "First monsters after", "The time from the raid's start notice (and its siren) to its first monsters, "
    .. "so players can get ready.")  -- (0.15.543, owner 08:16)
  choice_row(rows, g, "waves", "Waves", "How many waves one start brings.")
  choice_row(rows, g, "wave_dead", "Next wave after", "When the Between waves time starts: once the wave has spawned (the old way), or once "
    .. "this share of its monsters is dead (monsters left from earlier waves count as alive too). A monster that never dies holds the raid "
    .. "until Raid lasts at most ends it.")  -- (0.15.542, owner 08:08)
  choice_row(rows, g, "wave_gap", "Between waves", "The time between two waves (from Next wave after).")
  choice_row(rows, g, "duration", "Raid lasts at most", "From its start: when this time is up its raid ends, whatever is left: no more waves, its "
    .. "living monsters are taken away (and with them its protection), the bodies stay.")  -- (0.15.492)
  choice_row(rows, g, "cooldown", "Cooldown", "After its waves, the trigger cannot fire again for this long.")
  if g.trigger == "wire" and g.wire then
    rows[#rows + 1] = { dim = true, text = string.format("Trip wire at %.0f, %.0f: move it with Put trip wire here in the Spawn Nodes window.", g.wire.x, g.wire.z) }
  end
  return rows
end

-- The Spawn Nodes window: what is used out on the map.
function F.window_rows(world)
  local v = my_state(world)
  if not v then return { { dim = true, text = "Asking the server..." } } end
  local rows = {}
  local note = C.note or v.note
  if note then rows[#rows + 1] = { color = "#ffb060", text = note } end
  if not v.admin then
    rows[#rows + 1] = { dim = true, text = "Only FlameKit admins can set up spawn nodes." }
    return rows
  end
  local g, list = shown_group(v)
  if not g then
    rows[#rows + 1] = { dim = true, text = "No groups yet: make one in the Spawn Nodes tab (F4)." }
    return rows
  end
  group_row(rows, g, list)
  local status = (v.status or {})[tostring(g.id)]
  if status and status ~= "" then rows[#rows + 1] = { dim = true, text = status } end
  rows[#rows + 1] = { button = "start", text = "Start now", disabled = g.running or nil,
    tooltip = "Starts its waves now, whatever its trigger, also during its cooldown, when a player is within its Player within distance of one of its nodes." }
  rows[#rows + 1] = { button = "stop", text = "Stop", same_line = true, disabled = (not g.running) or nil, tooltip = "Ends its waves now; its cooldown starts." }
  rows[#rows + 1] = { button = "remove", text = "Remove its monsters", same_line = true,
    tooltip = "Removes this group's monsters only, alive or dead (their bodies on the ground too); other groups' and the world's "
      .. "own monsters stay. Only the ones spawned since the server last started or reloaded FlameKit." }
  rows[#rows + 1] = { button = "add", text = "Add node here", disabled = (#(v.nodes or {}) >= (v.max_nodes or MAX_NODES)) or nil,
    tooltip = "Adds a node to " .. g.name .. " where you stand, facing the way you face. Its monsters spawn within " .. SPREAD .. " m of it (change it on its line below)." }
  switch_row(rows, "show", show_on(), "Show nodes",
    "Shows every node and trip wire as a marker over the world and on the map, only in your game. Other players never see them.")
  rows[#rows].same_line = true
  if g.trigger == "wire" then
    rows[#rows + 1] = { button = "wire", text = "Put trip wire here", same_line = true,
      tooltip = g.wire and string.format("Moves the trip wire to where you stand (now at %.0f, %.0f).", g.wire.x, g.wire.z)
        or "Puts the trip wire where you stand." }
  end
  if C.no_markers then rows[#rows + 1] = { color = "#ffb060", text = "Your EMF cannot draw markers yet: let FlameKit update EMF (About tab)." } end

  local mine = {}
  for _, n in ipairs(v.nodes or {}) do if n[2] == g.id then mine[#mine + 1] = n end end
  local me = emf.local_player()
  local px, py, pz
  pcall(function() px, py, pz = world:position(me) end)
  for _, n in ipairs(mine) do n.d = px and math.sqrt(dist2(px, py, pz, n[3], n[4], n[5])) or nil end
  table.sort(mine, function(a, b) return (a.d or 1e9) < (b.d or 1e9) end)
  rows[#rows + 1] = { heading = string.format("Nodes of %s (%d), nearest first", g.name, #mine) }
  if #mine == 0 then rows[#rows + 1] = { dim = true, text = "None yet: stand where monsters should come from and click Add node here." } end
  for i = 1, math.min(#mine, NEAR_LIST) do
    local n = mine[i]
    local sp = tonumber(n[6]) or SPREAD
    local opts = {}
    for _, c in ipairs(SPREADS) do
      opts[#opts + 1] = { key = "spread:" .. n[1] .. ":" .. c, text = c == 0 and "On the node" or ("Within " .. c .. " m"), selected = sp == c }
    end
    rows[#rows + 1] = { label = true, text = string.format("Node %d%s", n[1], n.d and string.format(", %d m", math.floor(n.d)) or ""),
      tooltip = string.format("Node %d at %.0f, %.0f.", n[1], n[3], n[5]) }
    rows[#rows + 1] = { options = opts, text = sp == 0 and "On the node" or ("Within " .. sp .. " m"), same_line = true,
      tooltip = "How far from node " .. n[1] .. " its monsters may appear. A spot behind a wall, inside a building or inside rock is not used: "
        .. "FlameKit tries " .. SPOT_TRIES .. " spots, then uses the node itself. Chests and other placed objects are not seen." }
    rows[#rows + 1] = { button = "move:" .. n[1], text = "Move here", same_line = true, tooltip = "Moves node " .. n[1] .. " to where you stand, facing the way you face." }
    rows[#rows + 1] = { button = "del:" .. n[1], text = "Delete", same_line = true, tooltip = "Deletes node " .. n[1] .. "." }
  end
  if #mine > NEAR_LIST then rows[#rows + 1] = { dim = true, text = string.format("(%d more further away)", #mine - NEAR_LIST) } end
  return rows
end

-- A click in the Spawn Nodes window: the same keys as the tab's.
function F.window_click(world, key) return F.click(world, key) end

function F.click(world, key)
  C.note = nil
  local v = my_state(world)
  if not v or not v.admin then return end
  local gid = C.sel
  local sel = key:match("^sel:(%d+)$")
  if sel then C.sel = tonumber(sel) return end
  if key == "new" then act(world, { op = "new_group" }) return end
  if key == "window" then toggle_window() return end  -- (0.15.539) the Spawn Nodes window
  if key == "show" then
    C.show = not show_on()
    pcall(kit.store.save, "spawn_nodes_client", { show = C.show })
    C.marks_key = nil
    return
  end
  if not gid then return end
  local g = nil
  for _, x in ipairs(v.groups or {}) do if x.id == gid then g = x end end
  if not g then return end
  if key == "delgroup" then
    if not (C.del_asked and C.del_asked.g == gid and os.time() - C.del_asked.at <= 5) then C.del_asked = { g = gid, at = os.time() } return end
    C.del_asked = nil
    act(world, { op = "delete_group", g = gid })
  elseif key == "on" then act(world, { op = "set", g = gid, key = "on", value = not g.on })
  elseif key == "breaks" then act(world, { op = "set", g = gid, key = "breaks", value = not g.breaks })
  elseif key == "spare" then act(world, { op = "set", g = gid, key = "spare", value = not g.spare })
  elseif key == "announce" then act(world, { op = "set", g = gid, key = "announce", value = g.announce == false })  -- (0.15.488)
  elseif key == "mark" then act(world, { op = "set", g = gid, key = "mark", value = g.mark == false })  -- (0.15.541)
  elseif key == "protect" then act(world, { op = "set", g = gid, key = "protect", value = not g.protect })
  elseif key == "start" then act(world, { op = "start", g = gid })
  elseif key == "stop" then act(world, { op = "stop", g = gid })
  elseif key == "remove" then act(world, { op = "remove", g = gid })
  elseif key == "add" then act(world, { op = "add_node", g = gid })
  elseif key == "wire" then act(world, { op = "wire_here", g = gid })
  else
    local mv = key:match("^move:(%d+)$")
    local dl = key:match("^del:(%d+)$")
    if mv then act(world, { op = "move_node", n = tonumber(mv) }) return end
    if dl then act(world, { op = "delete_node", n = tonumber(dl) }) return end
    local sn, sv = key:match("^spread:(%d+):(%d+)$")
    if sn then act(world, { op = "node_spread", n = tonumber(sn), value = tonumber(sv) }) return end
    local k, val = key:match("^set:([%w_]+):(.+)$")
    if k then
      local value = tonumber(val) or val
      act(world, { op = "set", g = gid, key = k, value = value })
    end
  end
end

function F.setup(k)
  kit = k
  players.setup(k)
  -- (0.15.493) a monster that gives or takes a hit is busy, not stuck (stuck_tick)
  if emf.on_hit then
    pcall(emf.on_hit, kit.guard(F, function(world, hit)
      if type(hit) ~= "table" then return end
      local now = os.time()
      for _, id in ipairs({ hit.attacker, hit.target }) do
        if id and S.track[id] then S.active_at[id] = now end
      end
      -- (0.15.501) a monster that hits a player or is hit by one may be in a raid: looked at in join_tick
      if next(S.raid) ~= nil and hit.attacker and hit.target and hit.attacker ~= 0 and hit.target ~= 0 then
        local oka = pcall(world.account, world, hit.target)
        local _, at = pcall(world.account, world, hit.target)
        local _, aa = pcall(world.account, world, hit.attacker)
        if oka and at and not aa then S.join_hits[hit.attacker] = true
        elseif aa and not at then S.join_hits[hit.target] = true end
        if aa and S.mon[hit.target] then S.hitby[hit.target] = hit.attacker end  -- (0.15.547) Reward loot's runes go into the bag of the last player who hit it
      end
    end, "a hit (Spawn Nodes)"))
  end
  local ok = emf.net.channel(CHANNEL, {
    version = 1, to = "both", max = 16384, per_10s = 60,
    on_server = kit.guard(F, function(world, from, data_in)
      if type(from) ~= "table" or not from.player or from.player == 0 then return end
      local okd, msg = pcall(emf.json.decode, data_in)
      if not (okd and type(msg) == "table") then return end
      local account = from.account
      if (not account or tostring(account):match("^0x0*$")) then
        local oka, a = pcall(world.account, world, from.player)
        account = oka and a or nil
      end
      if not account then return end
      local st = handle(world, account, from.player, msg, from)
      if st then pcall(emf.net.send_to, world, from.player, CHANNEL, emf.json.encode(st)) end
    end, "a Spawn Nodes message from a player"),
    on_player = kit.guard(F, function(world, from, data_in)
      local okd, msg = pcall(emf.json.decode, data_in)
      if okd and type(msg) == "table" and msg.op == "place_ask" then  -- (0.15.490) where I am, as my minimap says
        local place, region = where_now()
        pcall(emf.net.send, CHANNEL, emf.json.encode({ op = "place", q = msg.q, place = place, region = region }))
        return
      end
      if okd and type(msg) == "table" and msg.op == "notice" and type(msg.t) == "string" and type(msg.tag) == "string" then  -- (0.15.488)
        local tag = "nodes_" .. msg.tag:gsub("[^%w_]", "")
        local colour = type(msg.c) == "string" and msg.c:match("^#%x%x%x%x%x%x$") and msg.c or NOTICE_COLOUR  -- (0.15.545)
        if msg.t == "" then kit.notice(tag) else kit.notice(tag, msg.t:sub(1, 200), colour, math.max(2, math.min(120, tonumber(msg.s) or 10))) end
        if msg.snd == "raid_siren" or msg.snd == "raid_siren_twice" or msg.snd == "raid_all_clear" then play_sound(msg.snd) end  -- (0.15.502); (0.15.517) twice; (0.15.549) the all-clear
        return
      end
      if okd and type(msg) == "table" and msg.op == "state" then
        C.shown = msg
        if msg.note then C.note = msg.note end
        if msg.made then C.sel = msg.made end
      end
    end, "the Spawn Nodes state from the server"),
  })
  if not ok then emf.log("spawn nodes: the channel flamekit/nodes was refused: the Spawn Nodes tab cannot reach the server") end
end

-- (0.15.550) Spawn Nodes switched off (kit.lua calls this once when "sn_enabled" turns off, and at load if it is off).
-- Nothing of it runs while off (kit skips its tick), so what it left active is let go of here:
--   * every running group is stopped as its Stop button does (its waves end, its cooldown starts, its queued monsters
--     are dropped); the raids' counts are forgotten (no "monsters left" notice; the last one shown fades by itself);
--   * the files FlameKit Native reads are set to "nothing": the animal hold "0" (the animals walk again), the raid lock
--     empty (players may change bases), the protection "0" (players can hit placed objects), spare empty. Only files
--     that are there are written (a player's own game has none of them).
-- The raid monsters still alive stay in the world as they are (Remove takes them away once it is on again); while off,
-- their deaths are not seen, so the game's own loot drops for them. Switched on again: everything runs as before; any
-- of its monsters still alive count again for the protection.
function F.switched_off()
  S.halted = S.halted or {}
  for gid in pairs(S.runs or {}) do
    finish(gid)
    S.halted[gid] = true
    cancel_checks(gid)
  end
  S.runs, S.queue, S.raid = {}, {}, {}
  local function put(name, text)
    local f = io.open(emf.dir .. name, "r")
    if not f then return false end
    f:close()
    f = io.open(emf.dir .. name, "w")
    if f then f:write(text) f:close() end
    return true
  end
  local any = false
  if put(K.HOLD_FILE, "0\n") then any = true S.hold_on = false end
  if put("\\raid_lock_server.txt", "") then any = true S.lock_text = "" end
  if put("\\raid_protect_server.txt", "0\n") then any = true S.protect_on = false end
  if put("\\spare_server.txt", "\n") then any = true S.spare_text = "" end
  emf.log("spawn nodes: switched off (sn_enabled): no raid runs" .. (any and "; the animal hold, raid lock, protection and spare files are let go of" or ""))
end

-- tests only
F._handle = function(world, account, entity, msg, from) return handle(world, account, entity, msg, from) end
F._test_set_shown = function(st) C.shown = st end  -- (0.15.504)
F._test_raid_monster = function(...) return raid_monster(...) end  -- (0.15.507)
F._test_S = S  -- (0.15.507)
F._test_spawn_tick = function(w) spawn_tick(w) end  -- (0.15.508)
F._test_trickle = function(w) trickle_tick(w) end  -- (0.15.512)
F._test_hunt = function(w) hunt_tick(w) end  -- (0.15.521)
F._reset = function() S.data, S.runs, S.mon, S.old_bodies, S.queue, S.last_end, S.next_timer, S.last_tod = nil, {}, {}, {}, {}, {}, {}, {} end
F._test_mon_check = function(w) mon_check(w) end  -- (0.15.526)
F._test_raid_tick = function(w) raid_tick(w) end  -- (0.15.526)
F._test_fire = function(w, gid) return fire(w, gid, "test", true, nil) end  -- (0.15.526)
F._test_wave = function(w, gid, spots) wave(w, gid, spots) end  -- (0.15.526)

return F
