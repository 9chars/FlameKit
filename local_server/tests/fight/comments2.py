import sys
p_in, p_out = sys.argv[1], sys.argv[2]
s = open(p_in, encoding='utf-8').read()
R = []
def r(old, new): R.append((old, new))

r('''-- npc_probe.lua (2026-11-17): FlameKit's companion NPCs, a TEST feature on the owner's local server only (never
-- published). Rebuilt at 17:00 (owner: "under no circumstances do I want any of the old code. no fall back code or
-- anything to do with any of the old AI follow me systems that didnt work"): only what works is left.
--   - the roster: FlameKit's own list of NPCs in the world's data (survives restarts), a main companion per player,
--     controllers and admins;
--   - following = the drive (his AI off, FlameKit's breadcrumb trail, the C++ hook writes his movement input);
--   - water: swims with the player (drive + height and tilt);
--   - staying = no game AI: his AI off, no target, he stands still (owner 17:06);
--   - E opens the wheel (Follow me / Stay here / Put away) in the player's game; "Call my companion" (Experimental
--     panel) respawns his main companion on him;
--   - the full recorder (fullrec) and read-only tools.
-- Console (or emf\\commands.txt on the server): flamekit.npc roster ... | drive <npc> <player> | drive <npc> stop |
--   fullrec <entity> [s] | look <entity> | near <x> <y> <z> [r] | remove <entity>
-- Logs "npc probe: ..." in emf\\emf_core.log.''',
'''-- npc_probe.lua: FlameKit's companions, on the owner's local test server only (never published; the repository keeps
-- the live copy in local_server/). No game AI anywhere: the companion's own AI and route planner are always off.
--   - the roster: FlameKit's own list of companions in the world's data (survives restarts), a main companion per
--     player, controllers and admins;
--   - following = the drive (FlameKit's breadcrumb trail of the player; the C++ server probe writes his movement input),
--     with swimming and diving, jump follow, drops, stuck notices, and put away / back beside the player (glider, fast
--     travel, can't follow);
--   - staying: no target, he stands still;
--   - E opens the wheel (Follow me / Stay here / Put away) in the player's game; "Call my companion" (P, Experimental
--     panel) respawns his main companion beside him;
--   - the minimap's companion dots, the full recorder (fullrec), and console tools for tests.
-- Console (or emf\\commands.txt on the server): flamekit.npc roster ... | drive <npc> <player> | drive <npc> stop |
--   fullrec <entity> [s] | look <entity> | near <x> <y> <z> [r] | remove <entity> | and the test commands in F.setup
-- Logs "npc probe: ..." in emf\\emf_core.log.''')
r('''-- (owner 2026-11-18 07:30: stuck and death notices "stay on the screen until the condition is cleared") a notice in
-- the player's Notices window with no time limit, taken back with clear = true (client npc_wheel_probe.lua)''',
'''-- a notice in the player's Notices window that stays until it is taken back (clear = true): the stuck and death
-- notices stay on the screen until the condition is over (client: npc_wheel_probe.lua)''')
r('''-- ===== The full recorder (owner 13:57/13:58: "logging all meta data ... and any other thing that needs to be logged") ==''',
'''-- ===== The full recorder (logging all of an entity's data) ===========================================================''')
r('''"w")  -- (14:10) one file per recording, kept''', '''"w")  -- one file per recording''')
r('''-- ===== Staying (owner 17:06: "I DO NOT WANT TO USE ANYTHING FROM THE GAME THAT USES THIER CRAPPY AI") ==============''',
'''-- ===== Staying =========================================================================================================''')
r('''-- ===== The roster (B4, owner 11:56/11:58): FlameKit's own list of NPCs, kept in the world's data =====================
-- Each NPC has a name (N1, N2 ...) and keeps it whether its body is out in the world or put away. A record: body
-- (template GUID), spot, mode (stay/follow), owner (account), out (true: has a body in the world). The game
-- deletes our bodies on a restart (seen 11:52): out ones come back, stayers at their spot when the world loads,
-- followers next to their owner when he joins. A probe reload finds its bodies again (by entity, faction 11 (7 before 19:31) and the
-- calm switches) instead of spawning a second one.
-- (owner 19:31) companions are PlayerAlly (11), the game's own "on the players' side": friends of players, enemies of
-- monsters. Faction 7 (Player) made every monster attack of theirs do 0 damage (bite test 19:23: 11 = 239 pierce).''',
'''-- ===== The roster: FlameKit's own list of companions, kept in the world's data =========================================
-- Each companion has a name (N1, N2 ...) and keeps it whether its body is out in the world or put away. A record: body
-- (template GUID), spot, mode (stay/follow), owner (account), out (true: has a body in the world). The game deletes
-- our bodies on a restart: out ones come back, stayers at their spot when the world loads, followers next to their
-- owner when he joins. A script reload finds its bodies again (by entity, faction and the calm switches) instead of
-- spawning a second one.
-- Companions are PlayerAlly (faction 11), the game's own "on the players' side": friends of players, enemies of
-- monsters (with faction 7, Player, their attacks on monsters did no damage).''')
r('''main = {} }  -- main: account -> name (owner 13:06: one main companion each)''', '''main = {} }  -- main: account -> name (one main companion per player)''')
r('''-- (owner 12:36-12:40) who may command an NPC: its controllers''', '''-- who may command a companion: its controllers''')
r('''-- (owner 19:47 "make him match my stats") a companion's level is its owner's level, set the way the game's own scaling
-- does it (Level.dataStorage[1], then DynamicEnemyScaling.nextUpdateTime = 0: the game rescales health and hits; seen
-- 18:36: level 30 = 1164 HP, bite 239). Checked at setup and every 10 s (the owner joins later, or levels up).''',
'''-- a companion's level is its owner's level, set the way the game's own scaling does it (Level.dataStorage[1], then
-- DynamicEnemyScaling.nextUpdateTime = 0: the game rescales health and hits). Checked at setup and every 10 s (the
-- owner joins later, or levels up).''')
r('''  -- (07:31) a living body again: the death and stuck notices go''', '''  -- a living body again: the death and stuck notices go''')
r('''if r.face_yaw then  -- (07:09) a Call: he faces the way the player faced''', '''if r.face_yaw then  -- a Call: he faces the way the player faced''')
r('''    drives[id] = { player = player, trail = {}, logcrumbs = true }  -- logcrumbs: (20:34 test) every crumb into the log''',
  '''    drives[id] = { player = player, trail = {} }''')
r('''.enabled = false end)  -- (owner 17:06) no game AI, ever''', '''.enabled = false end)  -- no game AI, ever''')
r('''      -- (12:40) records from before the controller lists: their owner is the only controller''',
  '''      -- a record without a controller list: its owner is the only controller''')
r('''    -- (12:48) "0x..." is an account, not a player entity (tonumber read 0x...02 as player 2, whose name is "Player")
''', '''    -- "0x..." is an account, not a player entity (tonumber would read 0x...02 as player 2)
''')
r('''roster.main[acc] = r.name  -- (13:06) a companion given to a player is his main one''', '''roster.main[acc] = r.name  -- a companion given to a player is his main one''')
r('''-- here <name> <player>: (13:09, stuck in a fence post) moved onto the player's spot''', '''-- here <name> <player>: moved onto the player's spot''')
r('''-- (owner 12:49, step 2) E opens a wheel on the presser's own screen (FlameKit's game side, channel flamekit/npcwheel);
-- a game without it gets the old follow/stay switch. The server checks who may command the NPC, again at the pick.

''', '')
r('''-- ===== E: the wheel (owner 12:49) ====================================================================================
-- E opens a wheel on the presser's own screen (FlameKit's game side, channel flamekit/npcwheel). The server checks who
-- may command the NPC, again at the pick. No other path (owner 17:00: no fallback).''',
'''-- ===== E: the wheel ====================================================================================================
-- E opens a wheel on the presser's own screen (FlameKit's game side, channel flamekit/npcwheel). The server checks who
-- may command the companion, again at the pick. There is no other way (a game without FlameKit gets a notice).''')
r('''-- "Call my companion" (Experimental panel; owner 13:03/13:06/16:54): the main companion's old body, if any (alive, dead
-- or stuck anywhere), is removed and a fresh one is spawned on the player's spot, following him''',
'''-- "Call my companion" (P, the Experimental panel, and every return after a put-away): the main companion's old body,
-- if any (alive, dead or stuck anywhere), is removed and a fresh one is spawned beside the player, following him''')
r('''  -- (owner 2026-11-18 07:07/07:08: "spawn like .5 to the ... right of me") 0.5 m to the player's right (his facing:
  -- forward = (sin yaw, cos yaw) as the dog's facing code uses, right = (cos yaw, -sin yaw); if it comes out on the
  -- left, the axes are the other way round)''',
'''  -- 0.3 m to the player's right (his facing: forward = (sin yaw, cos yaw), right = (cos yaw, -sin yaw))''')
r('''z - math.sin(yaw) * 0.3  -- (owner 07:10: 0.3 m, was 0.5)''', '''z - math.sin(yaw) * 0.3''')
r('''  -- (owner 07:09: "make it point the same way I am") his body turned like the player's, now and again when he is
  -- set up half a second later (bring_to_life)''',
'''  -- his body turned the way the player faces, now and again when he is set up half a second later (bring_to_life)''')
r('''  -- (owner 13:46 "ANY time he spawns by you, there should be a notice that says 'Companion has spawned near you!'")''',
  '''  -- every time he spawns beside the player: "Companion has spawned near you!"''')
r('''local hit_watch = {}  -- entity -> true: (18:54) its hits go into the HIT log too (npc spawnwild adds the body)''',
  '''local hit_watch = {}  -- entity -> true: its hits go into the HIT log too (npc spawnwild adds the body)''')
r('''  -- (18:48, recorder) every hit a companion gives or takes''', '''  -- every hit a companion gives or takes''')
r('''-- spawnwild <guid> <player> [metres]: (owner 17:41, observation) a wild body, its own AI''', '''-- spawnwild <guid> <player> [metres]: a wild body with its own AI, to watch''')
r('''-- face <npc> <target> [metres]: (owner 18:32, bite test) the npc put m metres in front of''', '''-- face <npc> <target> [metres]: the npc put m metres in front of''')
r('''-- level <entity> <level>: (owner 18:35 "give that dog stronger stats") the way''', '''-- level <entity> <level>: the way''')
r('''-- combat <npc> <target> [attack]: (owner 19:22, damage test) the combat numbers a wild
        -- hound has while it bites (fullrec_25792 18:55:03), copied as plain values, AI stays off''',
'''-- combat <npc> <target> [attack]: the combat numbers a wild
        -- hound has while it bites (taken from a full recording), copied as plain values, AI stays off''')
r('''-- faction <entity> <n>: (19:24 damage test) EMF combat.md: 7 Player, 11 PlayerAlly,''', '''-- faction <entity> <n>: EMF combat.md: 7 Player, 11 PlayerAlly,''')
r('''-- attr <entity> <Strength|Dexterity|Intelligence> <value>: (owner 19:59 "test what we
        -- have and see if it works") dataStorage[1] and [2] (a player has total, base, bonus: Strength 26 11 15)''',
'''-- attr <entity> <Strength|Dexterity|Intelligence> <value>:
        -- dataStorage[1] and [2] (a player has total, base, bonus: Strength 26 11 15)''')
r('''-- tpground <entity> <x> <y> <z>: (owner 22:04, test) EMF's teleport with the game's''', '''-- tpground <entity> <x> <y> <z>: EMF's teleport with the game's''')
r('''        -- (22:07 fix) the callback must not touch `world` (EMF paused the whole script at 22:06:03 for world:tick())''',
  '''        -- the callback must not touch `world` (EMF pauses the whole script for that)''')
r('''-- lure <npc> <x> <y> <z> [seconds]: (owner 22:46) edge-check test, see drive_step''', '''-- lure <npc> <x> <y> <z> [seconds]: edge stop test, see drive_lure''')
r('''-- still <entity>: (19:01 bite test) a test target's monster AI off, so it stands''', '''-- still <entity>: a test target's monster AI off, so it stands''')
r('''-- hold <npc> <target> [seconds]: (owner 19:00) stays put and faces the target''', '''-- hold <npc> <target> [seconds]: stays put and faces the target (drive_hold)''')
r('''-- atk <entity> <index>: (18:45 damage test) combatData.selectedAttackIndex, the number''', '''-- atk <entity> <index>: combatData.selectedAttackIndex, the number''')
r('''local dead_told = {}  -- entity -> true: (owner 07:23) "Companion has died!" sent once per body''', '''local dead_told = {}  -- entity -> true: "Companion has died!" sent once per body''')
r('''-- (owner 13:40/13:46) put away by the glider, a fast travel or can't follow: name -> { player, account, why, ground }''',
  '''-- put away by the glider, a fast travel or can't follow: name -> { player, account, why, ground }''')
r('''local load_seen  -- player -> "ready/teleport count" last logged (13:57)''', '''local load_seen  -- player -> "ready/teleport count" last logged''')
r('''local load_err   -- (14:08) the travel request read failed once (logged)''', '''local load_err   -- the travel request read failed once (logged)''')
r('''require("core.companions")  -- (0.15.278) the minimap's companion dots''', '''require("core.companions")  -- the minimap's companion dots''')
r('''if t % 30 == 0 then  -- (owner 08:56/09:00) where every companion is, with its owner's character name (the dot's colour)''',
  '''if t % 30 == 0 then  -- where every companion is, with its owner's character name (the dot's colour)''')
r('''name = name }  -- (0.15.279) the dot shows the companion's name''', '''name = name }  -- the dot shows the companion's name''')
r('''  -- (owner 13:57 "I got the 'Companion spawns near you message.' before the load was done") logging: the game's own
  -- "ready for gameplay" flag the player's client sends (PlayerInput.fromClientIsReadyForGameplay) and his
  -- TeleportCount, for every player, whenever either changes: does the flag go off during a fast travel's loading screen?''',
'''  -- logging: the game's own "ready for gameplay" flag the player's client sends (PlayerInput.fromClientIsReadyForGameplay)
  -- and his TeleportCount, for every player, whenever either changes''')
r('''    -- (14:08) and the player's own fast travel request (PlayerInput.fromClient.teleportAction): does it come before
    -- the teleport (an earlier signal for hiding FlameKit's UI)?''',
'''    -- and the player's own fast travel request (PlayerInput.fromClient.teleportAction)''')
r('''      -- (owner 13:57 "is there anyway to wait UNTIL the load is done?", 14:10 "ok") and his game reports it has loaded
      -- (PlayerInput.fromClientIsReadyForGameplay: false from the teleport until the loading screen is over, 14:07)''',
'''      -- and his game reports it has loaded (PlayerInput.fromClientIsReadyForGameplay is false from the teleport until
      -- the loading screen is over)''')
MULTI = {R[i][0] for i in range(len(R)) if '0x...02' in R[i][0]}
for old, new in R:
    if old in MULTI:
        assert s.count(old) == 2; s = s.replace(old, new); continue
    assert s.count(old) == 1, ('not found once', s.count(old), old[:80])
    s = s.replace(old, new)
open(p_out, 'w', encoding='utf-8').write(s)
print('replaced', len(R))
