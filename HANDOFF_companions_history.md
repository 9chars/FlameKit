# Companions: the full work log (moved out of HANDOFF.md on 2026-11-20 18:25, owner 18:11 "go ahead", cleanup E)

Everything below is verbatim, as it stood in HANDOFF.md (its section "Open list" and all that followed it up to "How to
build and publish a version"): every owner quote, every decision, every test. HANDOFF.md keeps the rules, a short
current state and the open list; this file keeps the history. Never edit the history, only add to HANDOFF.md.

### Open list (owner's order decides)
**Owner's plan (2026-11-18 13:00):** "going to take a short break, but I'd like to handle situations with the glider
and get the teleport stuff in there and then we can move on" -> next: glider situations, then the teleport fallback.
Owner 13:35: the companion inventory idea "on the back burner for now, lets continue with the main tasks".
**Glider design (owner 13:40):** "it will look way to strange if the dog flies in the air with the glider. since we
have new meta data now, the dog sees I took off on the glider. it should briefly wait to make sure im just just popping
it out quick and landing near by. when it realises I'm not coming back, distance too far, etc, it automatically
'despawns' it waits until I arrive back on ground and magically spawns back in next to me. this could use the same
teleport function as when I move across the map from a fast travel or what not..."
Pieces already there: "Put away" (wheel/do_away: body removed, kept in the roster) and Call / P (on_call: respawn 0.3 m
to the player's right, facing his way). 13:40 logging: "air <id>: player state N after s in the air (...)" each time a
new locomotion state shows up mid-flight, to find the glider's number.
Glide test (13:42, owner: "2 long glides and 1 short one"): **the glider is locomotion state 4** (state 2 = in the air
after a jump; 4 shows ~1.1-1.2 s after takeoff, after the double jump that opens it). Long glides: 79.7 m in 9.9 s
(top 997.2, 43 m above takeoff), 74.5 m in 9.2 s (came down 14.2 m lower); short: 18.4 m in 2.33 s, 1.4 m lower. All
three left a break (flight > 2 s) in the trail: the hound waits at the last crumb before it (and at 13:42:23, 38 m from
the player, "gave up" as can't follow).
Claude's proposal 13:44 (numbers): glider seen -> wait; still in the air after 4 s or 30 m away -> put away; back
beside him after 1 s on the ground; a short glide landing close is no break, he walks; can't reach the player for 5 s
(stuck or afraid) -> the same respawn (the general teleport fallback); fast travel (> 50 m in a moment) -> the same.
Owner 13:46 (taken as the yes, with the notices): "there should be a notice saying 'Companion put away, waiting for
your landing.'. When he appears (or maybe ANY time he spawns by you, there should be a notice that says 'Companion has
spawned near you!'".
**Built 13:48 (npc_probe, live):** GLIDE_STATE 4, GLIDE_WAIT 240 ticks, GLIDE_FAR 30 m, LAND_TICKS 60, TP_AFTER 300,
FAR_JUMP 50 m. drive_step sets h.go_away ("glide" / "fast travel" / "can't follow": h.stuck, h.waiting, h.sstuck or
h.wstuck for TP_AFTER); F.tick put_away_for() removes the body (roster out = false, like "Put away"), the glide one
shows the persistent status "Companion put away, waiting for your landing." (tag companion_away, #8cd2ff), and keeps
`returning[name]`; once the player has been on the ground (not in the air, not swimming) LAND_TICKS, on_call() brings
him back beside the player. on_call (P, Call, these returns) now clears companion_away / companion_stuck and shows
"Companion has spawned near you!" (5 s, #8cd2ff) instead of "<name>: Coming!". A glide that lands before the put-away
sets no drop break. Logs "away: <name> (<id>) put away (<why>) ..." and "away: <name> back beside player ...".
Backup `claude_scratch/npc_probe.before_glider_1348.lua`.
Test (13:53-13:54), owner 13:54: "it works pretty well". Log: three glides, each "put away (glide)" then "back beside
player 1 (glide over)" and respawned (7.0 s, 1.6 s, 2.4 s later). Not yet seen in a test: fast travel, the 5 s can't
follow fallback.
**Fast travel + loading screens (owner 13:57):** "when I warp to a new location. I got the 'Companion spawns near you
message.' before the load was done. is there anyway to wait UNTIL the load is done? Also a lot of the UI elements don't
disappear during zoning to a different area. This has been a problem for a while and just mentioning it to you now. I
will note the mini map does attempt to disappear, but it disappears a little too late. is there anyway to dial this in
a bit better. It just looks goofy to the player". Log: 13:56:00.7 "put away (fast travel)", 13:56:01.7 back (1 s on
the ground at the destination on the SERVER, while the client still loaded). Client today: flamekit_native.cpp hides
only the minimap during a fast travel (g_travelling: the local player's TeleportCount went up; back when he moves
after 2 s, at most 20 s); the other layers (HUD lines, notices, party window ...) do not look at it. 13:58 logging
(local server): "load: player <id> ready for gameplay <PlayerInput.fromClientIsReadyForGameplay>, teleport count <n>,
at x y z" whenever either changes: if the flag drops during the loading screen it is the signal for both (the respawn
waits for it; the client could hide all of FlameKit's layers on it, a Development release).
Can't-follow fallback test (14:02-14:03, owner jumped off without the glider): 14:02:56.970 "stuck: gave up ... player
16.0 m", 14:03:02.004 "put away (can't follow)", 14:03:03.002 back beside the player: works. Owner 14:03: "the respawn
works so well, I wouldn't even wait 5 seconds... wait like 2 seconds maybe. the only case where I would want to change
this is if we were testing it more and trying to figure out situations why he couldn't get to me when he should".
14:04 (live): TP_AFTER 120 ticks (2 s after he gives up; giving up itself takes STUCK_TICKS 3 s of no progress).
Owner 14:05: "the 2 seconds was a quicker response and good just enough total time to see the error from the dog".
**Fast travel data (owner 14:07 "I did a couple fast travels"):** the server's "ready for gameplay" flag
(PlayerInput.fromClientIsReadyForGameplay) goes FALSE 0.04-0.06 s after the teleport count rises and TRUE again when
the client has loaded: 14:06:51.32 -> 14:06:59.60 (8.3 s), 14:07:44.45 -> 14:07:50.32 (5.9 s). The return came at
14:07:00.8 (after ready, by luck) and at 14:07:46.9 (3.4 s BEFORE ready: the early notice). The client's minimap hid at
the teleport count (14:06:51.297, same moment) and came back when the player moved (10.1 s, 11.2 s: later than ready).
14:08 logging: the player's fast travel request (PlayerInput.fromClient.teleportAction: target / teleporterType /
versionData, e.g. "18766/1/607074"); one more fast travel shows whether it arrives before the teleport (an earlier
"hide" signal than the count).
Owner 14:10 "ok" (yes to #1 and one more fast travel). Built 14:10 (live): a return also waits while the player's
fromClientIsReadyForGameplay is false (then LAND_TICKS on the ground). Backup `claude_scratch/npc_probe.before_ready_1410.lua`.
#2 (hide ALL of FlameKit's layers while travelling, back on the ready signal: a client DLL change, Development) waits
for the travel-request timing.
Travel request timing (14:10-14:12): it reaches the server ~4.2-4.3 s BEFORE the teleport (14:11:11.2 -> 14:11:15.6);
owner 14:13: "there's a short animation, maybe about 3.5 seconds before the screen goes dark". Owner 14:16: "build it
and restart" (#2: the server drives hiding ALL of FlameKit's UI: hide 3.3 s after the request or at the teleport, show
when the client reports ready; Development 0.15.281).
**0.15.281 to Development (built 14:18):** `features/travel_hide.lua` (new, listed in main.lua; the local server's own
main.lua got the line too, next to npc_probe): the server watches each player's travel request version, TeleportCount
and ready flag; hides HIDE_AFTER 198 ticks after the request or at the teleport, shows again once ready went false and
then true after the teleport; cancelled travel (no teleport 7 s after the request) or 60 s: shown again. Channel
flamekit/travel ("1"/"0") to the player's game (the host's own game directly); kit.travelling -> ui_hud.dat "travel 1"
(core/kit.lua) -> DLL g_travel_hide: Layer::shown() false for EVERY layer (FlameKit's window too), not gated by
in_world. Logs: server "travel: player N travels: FlameKit's UI hidden (...)" / "... shown again (loaded, after x s)";
client log "fast travel: all of FlameKit's UI hidden / shown again (the server's signal)". The minimap's own
TeleportCount rule stays for servers without it. Also in this release: 0.15.280's Invincible Mode air refill.
Restart 14:19-14:20 (owner 14:16 "build it and restart"); the owner's game on 0.15.281. Test 14:27-14:29, owner 14:29:
"it looks a lot better now". Log: 5 travels: hidden 3.3 s after the request (4x) or at the teleport (1x, 14:28:11: the
teleport came first), shown again "loaded" after 5.7-8.9 s; once (14:27:46) "no teleport came, after 3.7 s" (shown 7 s
after the request without a teleport: a cancelled travel? not asked yet).
Owner 14:30: "when the UI reappears after the zone, the mini map doesn't appear until I move.... ?" Cause: the minimap's
own old rule (TeleportCount up -> hidden until the player moves, 2-20 s) still ran beside the new server signal. Owner
14:31: "yes of course the old signal needs to get cleaned up ..." -> Rule 0n. **0.15.282 to Development (built 14:35):**
`g_travel_signal` (set on the first "travel 1" from the server): the old rule no longer starts once the signal was seen,
and the signal's end also ends it (log "fast travel: the minimap's own rule ended by the server's signal"). The old rule
stays only for a server without travel_hide.lua. To test: fast travel, the minimap must come back with everything else.
Owner 14:39: no fallbacks (Rule 0n). Proposed 0.15.283: remove the old TeleportCount rule and g_travelling entirely
(the minimap is a Layer, so g_travel_hide already hides it).
Owner 14:41 on 0.15.282: "it looks like it worked, go ahead and update dev" -> **0.15.283 to Development (built
14:42)**: g_travelling, g_travel_signal and the TeleportCount block are gone from the DLL; travel_hide.lua is the only
fast travel hide. Owner 14:41 on the 14:27:46 travel: "no something glitched out on the game and it took wayyy longer
to zoned/load". Client log: request ~14:27:42.9 (map closed), hidden 14:27:46.2, shown 14:27:49.9 by the 7 s
CANCEL_AFTER timer, teleport only at 14:28:11.2 (28 s after the request): the UI showed for 21 s of that loading screen.
Proposed fix (not done): drop the 7 s cancel timer, keep hidden until loaded (60 s LONGEST cap), unless a fast travel
can be cancelled in game (asked the owner 14:43).
Owner 14:50: "ok restart it now, but this isn't worth losing your shit over right now" -> the 7 s cancel timer fix is
PARKED: a WATCH item only, no fix unless it repeats (owner 14:54: "one rare one off glitch != do a fix"). Restart into 0.15.283 at 14:50.
Owner 15:20 on 0.15.283: "the UI seems to act correctly with the zoning, you could probably wait 2 seconds longer
before taking the UI off" and "at that point you cant cancel it and theres no need to wait or listen for a cancelled
teleport". **0.15.284 to Development (15:21, server Lua only, travel_hide.lua):** HIDE_AFTER 3.3 -> 5.3 s; the teleport
(about 4.2 s after the request) no longer hides by itself when the request was seen; the 7 s CANCEL_AFTER rule and its
"no teleport came" path are removed (the 14:27 slow load is covered by this now, by the owner's direction); LONGEST 60 s
stays only as a cap. Log line now gives the hide and the teleport times after the request.
**Fast travel UI item DONE** (owner 15:25: "thats good we can cross that one off the list"). 0.15.284 loads at the
next restart (no yes for a restart yet).
0. **Pathing retests before combat** (owner 2026-11-18 09:32: "I think we have more pathing issues to test out first like
   water. he was getting stuck or falling through the ground between water and terrain transitions? that was a while
   ago so maybe these are none issues.. but need to get tested again"). Note from the code (not a diagnosis): water
   mode follows the PLAYER's water state (`currentWaterState > 0.5`), and while it lasts the hound's height is set
   every tick to the player's height + 0.45 m, wherever the hound is. Logged now: only "player in water" / "out of
   the water" lines.
   **Owner decision 09:42:** "his state should change based on when he's in the water and not mine" (water mode from
   the HOUND's own water state, not the player's).
   Owner 09:45 on the plan (switch on HIS water depth > 0.5 m, held at the water surface where he is, tilt kept, still
   heading to the player, walks the trail while the player swims and he is on land, logging): "that all sounds right
   to me". Found before building: the full recorder could not read the hound's `currentWaterState.waterDepth` ("?";
   for the player the code reads `currentWaterState` as a plain number); the hound has canSwim = false, canDive =
   false; unknown whether his water value is live and whether it means depth below the surface at his feet or the
   water's whole depth. Also on him: `ServerSubmerge.submergeDepth`.
   Owner 09:47 "ok" to a logging round first. 09:48: npc_probe logs "waterlog <id>: hound water=... submerge=...
   check=... y ... ground ... loco ... | player water=... y ... | m apart [water mode]" once a second while either
   reads water and 5 s after. No behaviour change. Backup `claude_scratch/npc_probe.before_waterlog_0948.lua`.
   **Water test 1 (09:52-09:57, owner):** "on first attempt the dog swam around the water erratically and then got
   stuck or fell into the terrain some place"; "on the second attempt, I jumped right in and the dog took off in the
   complete wrong direction". Log: (1) body 32953: in water mode he drifted 3 -> 28 m from the player; after the
   player left the water he fell 20 m every second with no ground under him (y 944 -> 844): under the terrain.
   (2) body 33570: in water mode the distance grew steadily 8 -> 99 m (about 2.2 m/s, straight). Both: locomotion
   state 2 (in the air) the whole time in water mode, no ground. Hound water value: 0.70-1.08 for a few seconds in
   attempt 1, 0.0 the whole of attempt 2 (even with the player in 4.8 m deep water 10 m away). Not yet logged: his
   velocity, the move direction written, his facing. No change made from this test (rule: several tests first).
- **Behaviour per body type (owner 09:45):** "the water body tilt thing is probably only going to be for the dog
  'template', other ones would not have that feature most likely, so you'd need to store these behaviors by the
  model/template type eventually". Today FLOAT_LIFT / FLOAT_PITCH (and the jump numbers) are single constants, not
  per template: to do when a second body comes.
0b. **Trap door "stuck" (owner 10:00, village):** "the dogs path in front of me is clear and wide open, yet the message
   says the companion is stuck ... he is on a flat boardwalk type surface. there IS a closed trap door in front of
   him". Log 09:56:14 and 09:56:56: `edge: 33767 stops at 6301.5 948.5 5179.9 (ground 1.5 m ahead: a drop the player
   did not take, 5.50 m down)`, then stuck. The player's crumbs there are level (y 948.50), so the player walked
   over it. The edge ray (mask 7) went through the closed trap door and hit the ground 5.5 m below. Permission today
   only covers crumbs going DOWN; a level crumb ahead (laid only on solid ground) is not counted as proof of a floor.
   Owner 10:03: "I could see a situation where the trap door is open and I jumped over it, how would that situation be
   handled?" -> rule tightened: only an UNBROKEN trail counts (a jump leaves a gap). Owner 10:06: "yes do the fix for
   now". Built 10:07 (npc_probe, live reload): FLOOR_LINK 0.7 m between crumbs, FLOOR_REACH 3.6 m (past the 3.5 m
   sprint ray), level = within 0.8 m of his height, no brk; then the permission flag is set (the native 7.5 m limit
   stays). Log: "edge <id>: floor proven by the trail / no floor proof (unbroken level trail X m ahead)". Backup
   `claude_scratch/npc_probe.before_floorproof_1007.lua`. Test 1 (10:09-10:11): log shows him crossing the trap
   door both ways (10:09:10 proof at 6300.4 -> 6304.3 two seconds later; 10:10:34 proof at 6304.1 -> 6291.6 at
   10:10:38), no edge stop, no stuck. Owner 10:10: "he walked over it fine this time".
   Open trap door (owner 10:11 test, 10:13 "he stops at an open trap door"): log 10:12:36 and 10:12:53 edge stops at
   the trap door (5.50 m down), no floor proof, then stuck: correct.
   **Watch (10:13:29, one case):** at 6285.0 947.0 5211.0 (about 30 m from the trap door) the edge ray saw 5.19 m
   down, the floor proof (level trail 3.7 m ahead) let him go on, and he dropped 1.91 m (jumplog "landed -1.91 m"),
   then carried on fine. The proof checks the trail, not that the trail passes the spot the ray tested: if his line
   leaves the trail (a corner), the proof can cover ground the player never walked. Possible tightening: the chain
   must pass within ~0.5 m of the tested point(s). Not changed (one case; owner decides).
   Owner 10:18 (stale crumbs): "theres a button to open that trap door ... only stays open for a few seconds. to
   access the button ... I had to step on the trap door itself. that may have left a bread crumb there. I hit the
   switch and hopped off quick to the other side while it opened. I could see that situation tricking the dog into
   trying to walk over it". Why he stopped in this test: the hop broke the trail (gap), so no proof. Had the owner
   WALKED off the door, crumbs would lie over the open hole and the proof would let him walk in. The edge ray cannot
   tell open from closed (it goes through the closed door too). Bound: the proof never allows a drop of 7.5 m or
   more (native limit), his fall damage starts at 8 m, so the worst case is a harmless fall into the hole.
   **Owner wishes / ideas (10:06, not decided):** "it would be nice if he could just also jump over it"; "its too bad
   he can't use my actions as predictions as to what he should do.. it would be nice if we could add more context to
   the bread crumbs for instance the bread crumb could indicate I jumped next, etc... not sure how possible or stable
   that would be in real practice, just an idea to think about?"
   10:07 (logging, owner rule 10:00): waterlog lines now also give his speed and its compass angle, the drive's move
   input angle, his facing angle and the angle to the player (0 = +z, 90 = +x).
   **Water test 2 (10:24-10:26, body 39619, with the new logging):**
   - In water mode with locomotion state 2 ("in the air", he is held above the ground at the player's height) his
     horizontal speed is FROZEN at whatever it was when he left the ground: "vel 1.2 m/s at 50" for 14 s while the
     drive's input turned 64 -> 202; "vel 3.5 at 320" while the input said 140-147 (the opposite way); "vel 9.3 at 4"
     with input 180-194. Distance grew to 20 m each time. Each brief touch of the ground set a new frozen speed. The
     drive's input was right every time: the body cannot steer in the air. Vertical speed sits at -20 m/s (gravity
     keeps pulling; his height is reset every tick).
   - With locomotion state 0 (10:25:22-10:25:48, the owner dove to 6 m) his speed followed the input exactly and he
     kept 4-6 m from the player.
   - Facing stuck at 128 the whole time in water mode (the tilt code keeps the yaw it reads back; he never turns).
   - Hound water value = depth below the surface (player water 6.4 at y 939.8, hound 5.7 at 940.2: same surface
     ~946). It reads right in locomotion state 0, wrong or 0 in state 2 (0.55 when it should be ~1.2; 0.0 at times).
   - After the player left the water (10:25:48) he sank 1.5 m/s to the bottom (y 939.6, 4.4 m under the surface),
     walked on the bottom, and gave up stuck at 10:25:56 under his crumb 7.2 m above him.
   - Run 1 of this test (body 33767, 10:23:40-10:23:57): frozen at 12.4 m/s in direction 346 while the input said
     170-184 (the opposite way): 125 m in 10 s. When the player left the water he was over land far away and dropped
     19.6 m (jumplog "landed -19.61 m"), more than his 16 m lethal height in the fall-damage data; he was still
     jumping afterwards.
   - Owner 10:27: "I had to reset the dog several times, the first time the dog just ran off completely, the second
     time I eased him in slowly and he made it in the water, but he real struggled to follow me. I took a dive under
     water and he seemed to follow that. He struggled to get out of the water where he is stuck now. this illustrates
     all the known issues pretty well. the data should reflect that. those are the things we need to improve on".
     The data matches every point (ran off = frozen air speed; struggled = frozen speed + no turning; followed the
     dive = locomotion 0; stuck getting out = sank to the bottom under a 7 m wall).
   **Fix round 1 (owner 10:30: "you can adjust his height and angle if you need to, if that is part of the problem. go
   ahead with your proposed fixes"; built 10:31, live reload):** in water mode FlameKit writes his Velocity every
   tick: toward the player, 0 within DRIVE_STOP (3 m), else 1 m/s + 1.2 m/s per metre past it, at most 6 (SWIM_MAX,
   SWIM_GAIN), up/down 0; his yaw kept in h.swim_yaw (not read back from the tilted body), tilt 28 deg kept, height
   still player + 0.45. Not yet changed: switching on his own water value, sinking after the player leaves the water.
   Backup `claude_scratch/npc_probe.before_swimsteer_1031.lua`. Unknown before the test: whether the game takes a
   Velocity write in the air (the waterlog "vel" will show it).
   **Fix round 1 result (body 41655, 10:34:46-10:35:14):** it works: in water mode "vel" = "input" = "faces" every
   second (e.g. 3.4 m/s at 257, input 257, faces 257), 2-5 m from the player, locomotion 0 now. His own water value
   held steady at 0.87-0.98 at that height (player + 0.45). Exit: the player walked out at 10:35:14 ("the spot here
   he's stuck, I walked right out. I didn't need to jump or anything", owner 10:35); water mode ended with the
   PLAYER's state while the hound was 3.7 m behind over deep water: he sank 1.5 m/s to the bottom (y 939.3, 8 m
   under the surface) and gave up stuck at 10:35:18. Cause: the switch follows the player (owner's 09:42 decision
   not built yet).
   **Fix round 2 (owner 10:37 "yes change it"; built 10:38-10:39, live reload):** water mode = the HOUND's own depth
   > SWIM_ENTER 0.5 m; held at SWIM_DEPTH 0.9 m below the surface by his own depth (a quarter of the difference per
   tick, at most 0.08 m a tick, never pushed down while he touches the bottom); edge-stop skip flag from HIS
   swimming; a swimming player lays no crumbs and gets no flight time; when the player swims and the hound is at the
   end of the trail (or it is empty) he heads straight for the player with edge permission (7.5 m limit kept), log
   "trail ends at the water: straight to the swimming player" / "back on the trail"; entering the water ends a stuck
   or drop wait. Logs "in the water himself (depth x)" / "out of the water himself (depth x)". FLOAT_LIFT is no longer
   used (kept). Backup `claude_scratch/npc_probe.before_ownwater_1039.lua`.
   First effect (10:38:52, the first reload): the stuck hound at the bottom (8.04 m deep) rose, swam to the shore
   and walked out by himself in about 1.5 s, 2.9 m from the player.
   **Water test 3 (10:42-10:45, body 44436):** owner 10:44: "he's not throwing an error about being stuck, but I
   walked up over a bank and he can't get out to follow me". Log: he followed into the water ("trail ends at the
   water: straight to the swimming player" 10:42:30 / 10:43:17), swam right ("input" = "faces" = toward the player).
   At the bank: at the surface (depth 1.02, y 946.72), the player 3.6 m away on top at y 948.55 (1.8 m higher); he
   pushes toward him (input 347) but moves 0.4-0.5 m/s sideways along the bank, locomotion 2, for over 40 s. Water
   is deep right up to the bank: he cannot touch bottom and walk out; the step jump only works on the ground. No
   stuck notice: stuck detection is skipped in water mode (the water branch returns before it).
   **Fix round 3 (owner 10:46 "I'm good with those fixes, but will a hop work in water?"; built 10:46-10:47):** in
   water mode, no 0.3 m progress toward the player for HOP_TICKS 90 (1.5 s) and the player more than 0.3 m higher:
   a hop: Velocity up = sqrt(2*25*(player height difference + HOP_MARGIN 0.7)) (max 14) and HOP_FORWARD 3 m/s toward
   the player, no surface hold for HOP_HOLD 40 ticks, at most every HOP_EVERY 120. No progress for STUCK_TICKS (3 s)
   in water: orange "Companion is stuck!", cleared when he gets closer or leaves the water. Logs "hop: ..." and
   "stuck (water): ...". Not the game's jump (that needs ground). Backup `claude_scratch/npc_probe.before_hop_1047.lua`.
   Result 10:46:55: "hop: 44436 hops out of the water toward the player (1.7 m higher, 3.6 m away): 11.0 m/s up",
   jumplog "highest +2.21 m, landed +1.52 m", on the bank 1.5 m from the player 2 s later: an upward Velocity write
   takes in the water. Owner 10:47: "he came up on shore, so it seemed to work, I will test it further".
   **False water stuck (owner 10:49: "I'm getting a stuck message when he isn't stuck (in the water)"):** log
   10:48:53 and 10:48:59 "stuck (water): makes no progress (player 3.7 m / 3.0 m)" while he swam after the swimming
   player at 1-2 m/s, 3-4 m behind (input = faces = toward the player). Cause (Claude's rule): progress = the
   distance to the player shrinking by 0.3 m; following a MOVING player at a steady distance never shrinks it. The
   hop uses the same measure (it only fires with the player higher, so it did not fire here).
   Fix (owner 10:50 "go ahead and do the fix"; built 10:51): water progress = his own movement along the line to the
   player since the last mark (> 0.3 m resets it), no count within DRIVE_STOP. Entering the water now always clears
   the stuck notice (one from the old rule stayed on screen after the reload). Backup
   `claude_scratch/npc_probe.before_wprog_1050.lua`.
   **Island case (owner 10:53: "I found a small island in the water (very small) which he climbed up on correctly
   with me, but I stepped back off into the water and now he says he's stuck"):** 10:52:18 hop onto the island (0.6 m
   higher, 8.1 m/s up), crumbs 1-9 on the island. 10:52:23 the player stepped into the water; the edge stop held him
   0.8 m short of the island's edge crumbs: "a drop the player did not take, 6.29 m down" (the ray goes through the
   water to the lake bottom; water looks like a cliff). The trail-ends-at-the-water switch needs him AT the last
   crumb (within 1 m), which the edge stop never let him reach; 3 s later land stuck (10:52:26), and a stuck hound
   is excluded from that switch. He stands on the island since then, the player 6.8 m away swimming.
   Fix (owner 10:55 "sure, but is it possible for him to know I'm just in the water?"; built 10:55-10:56): the
   player's water surface = his height + his water depth; when the hound stands at most WATER_NEAR 2 m above it (and
   not more than 1 m below) and the trail's last crumb is within 3 m (or there is none), he heads straight for the
   swimming player with drop permission, and a stuck there is cleared. First build (10:55:53) broke the drive for 35 s:
   "npc_probe.lua:471: attempt to perform arithmetic on a emf.proxy value (local 'pw')" ("pw" is reused later in
   drive_step for his DynamicPathWalker); fixed 10:56:28 with `pwater`. Result 10:56:28: "trail ends at the water:
   straight to the swimming player", into the water 10:56:29 (owner 10:59: "yes he's in the water again with me").
   Backup `claude_scratch/npc_probe.before_island_1056.lua`.
   Watch: the native edge stop still blocks "no ground within 12 m" even with permission (a flicker here, 10:56:28.703):
   water deeper than 12 m could hold him at the shore.
   **Island again (owner 11:00: "I tested the island thing again and now he's struggle to get up back on it.. I did
   not see him try to hop or get a message that he was stuck"):** log 10:59:17-11:00:31: he floats at the surface
   3.0 m from the player, who stands on the island 0.74 m higher; "input none", speed 0. Cause: the swim speed is 0
   within DRIVE_STOP (3 m), and the hop and the water stuck notice only count beyond DRIVE_STOP, so a player standing
   on land less than 3 m from the water's edge never pulls him out.
   Owner 11:10: "so I'm good with your fix, but generally I think we should bump is follow range closer to me, which
   might be a better fix. theres a lot of tight spots on this map and him following closer like 2m would possible
   mitigate this situation. having him closer on land would be good too probably". Found: the land stop distance is
   ALSO hard-coded in the C++ drive (`server_probe.cpp` drive_post: `if (dp > 3.0 && dl > 0.05)`; speed Walk/Run/
   Sprint at 6 / 12 m), besides Lua DRIVE_STOP 3: 2 m on land needs a probe rebuild (buildprobe) and a server restart.
   **Owner decision 11:12:** "I think both fixes should be done.. if he's still swimming he hasn't arrived (there could
   be other edge cases where this happens) and the follow distance needs to be 2 m. I think this is a one of situation
   where its safe to do both fixes together" (an exception to the one-fix rule, his call).
   Built 11:12-11:15: C++ `kFollowStop = 2.0` (was the literal 3.0 in drive_post; buildprobe BUILD OK 11:12:56, backup
   `claude_scratch/server_probe.before_stop2_1113.cpp`); the loaded DLL renamed to `mods\fk_server_probe\
   fk_server_probe.dll.old_1115` and the new one copied in (md5 d56a065e...), used from the next server start. Lua
   (live 11:13): DRIVE_STOP 2; in the water with the player NOT swimming the stop is SWIM_OUT_STOP 0.8 m and the hop
   and the water stuck count past it. Backup `claude_scratch/npc_probe.before_stop2_1114.lua`. Until the restart the
   old DLL still stops him at 3 m while Lua expects 2 m: "stuck ... gave up / goes on" every 3 s at 2.4 m (11:13:17).
   Restart (owner 11:18 "yes lets do the restart"): 11:18:58-11:19:55, the helper's new 30 s wait ran ("waiting 30 s
   for it to finish coming up before the client starts"); the new fk_server_probe.dll loaded 11:19:01.
   **Pier case (owner 11:25: "I walked off a pier that a bit above the water, the dog doesn't say he's stuck, but he
   doesn't follow me into the water"):** body 26151 on the pier at y 948.50; the player swims (y 945.2, depth 1.30:
   surface 946.5, so the pier is 1.98 m above it). 11:25:15.951 "trail ends at the water: straight to the swimming
   player", but the native edge stop: "stops at 6327.1 948.5 5187.6 (ground 1.5 m ahead: more than 7.5 m lower,
   8.96 m down)": the ray measures to the lake BOTTOM under the pier, and the 7.5 m limit holds even with permission.
   No notice: heading straight to the swimmer sets no crumb target, and stuck detection only watches a crumb.
   WATER_NEAR 2 m only just covered 1.98 m.
   Owner 11:33 on Claude's proposal (cliff check off within 3 m above the water): "what the 3 m limit? you can legit
   fall into water from the highests points and never die.. if I leap into water he should follow.. 3 m limit is
   too... limiting?"
   Claude proposed instead: follow the player's LEAP (takeoff crumb -> where he went in), no height limit, edge check
   off only for that leap; plus a stuck notice while heading straight to a swimmer. Owner 11:39: "ok, but he's got to
   make sure I'm in water first". **Built 11:40 (live):** the player's first wet tick straight after air time (h.air,
   no ground between) records h.leap {takeoff = his last crumb, entry = his position}; walking in records none. When
   the player is in the water NOW and the hound is within LEAP_AT 2 m of the takeoff (height within 1.5 m): Velocity
   out toward the entry point (speed so he comes down there, LEAP_UP 4 m/s up, gravity 25, at most LEAP_MAX 15 m/s),
   edge stop off for the flight, LEAP_TICKS 300; ends in the water (log "leap ...: in the water (health x, was y)") or
   on the ground (log "ended on the ground, not in the water"). Logs "leap ...: the player leapt into the water from
   ..." and "leaps after the player: ...". Stuck notice while heading straight to the swimmer: his own way toward the
   player, none for 3 s -> orange; log "stuck (to the water)". Backup `claude_scratch/npc_probe.before_leap_1140.lua`.
   Unknown: whether water spares the hound fall damage.
   **Leap test 1 (11:42):** owner 11:43: "two different tests, he did not follow, but he's giving me the 'Companion is
   stuck!' error. So that works, but he's not really stuck, he just can't follow me, so the notice should say
   'Companion can't follow you!'". Log 11:42:33: "the player leapt into the water from 6328.5 948.5 5187.5 (2.6 m
   above where he went in ...)": recorded right. But the edge stop holds him 1.5 m short of the edge ("stops at
   6326.0 948.5 5187.4 ... 8.97 m down"): 2.5 m from the takeoff crumb, outside LEAP_AT 2.0, so no leap; 3 s later
   "stuck (to the water)". Notice text changed 11:44 (live) to "Companion can't follow you!" for that case (the water
   bank stuck still says "Companion is stuck!").
   Owner 11:46: "lets change the other message too. I want 'stuck' to mean he's actually stuck on terrain he can't get
   out of like a clipping problem.... are you sure your approach is right on this? seems like we're tweak a ton of
   numbers that might not work in other situations, the crux of it is, if I jumped in, im in water, I'm safe, dog
   follows....". Done 11:47 (live): the water-bank notice also says "Companion can't follow you!".
   **Owner's meaning of "stuck" (11:46):** only a hound really stuck in terrain he cannot get out of (clipping). Still
   "Companion is stuck!" today: the land "blocked" case (STUCK_TEXT.blocked, no progress toward a level crumb), which
   was the trap-door edge stop, i.e. NOT clipping: to bring to the owner.
   **Owner decisions 11:50:** (1) replace the leap launch with the simple rule: "yes -- he doesn't have to leap in, he
   just needs to follow" (player came down into the water from the air AND is in the water now -> edge check off for
   the hound until he is in the water himself, he heads straight for the player). (2) "if its not a clipping problem
   then yes change it to can't follow you, if he can't follow me because he can't get over or navigate an obstacle,
   then its 'cant follow you'".
   Built 11:50 (live): the 11:40 launch/flight code and LEAP_* removed (owner's yes to replace it); h.leap (recorded
   when the player comes down into the water from the air, with the hound's health) now sets the native edge-stop skip
   flag (combatData.targetOfMyTarget) until the hound is in the water himself or the player leaves the water, and
   allows the straight-to-the-swimmer target from any height (near_water OR h.leap). Logs "the player leapt into the
   water ... edge stop off for the hound (health x)", "followed the player into the water (health x, was y)", "the
   player left the water, edge stop on again". STUCK_TEXT.blocked = "Companion can't follow you!" (land); no text says
   "Companion is stuck!" now except fallbacks (no clipping detection exists yet). Backup
   `claude_scratch/npc_probe.before_simplefollow_1151.lua`.
   **Pier test with the simple rule (11:58:22, body 34877): it works.** "the player leapt into the water from 6328.6
   948.5 5187.9 (2.6 m above ...)", 1 s later "trail ends at the water: straight to the swimming player", 2 s after
   the leap "followed the player into the water (health 3680, was 3680)": no damage. Earlier (11:57:57) a 1.9 m leap
   where the player climbed out again within 4 s ("the player left the water, edge stop on again") before the hound
   got there. Seen: in/out of water mode flickers at a depth right on 0.5 (11:57:56, four switches in 0.2 s): no
   problem reported; a small hysteresis would end it if it ever matters.
   **Village animal (owner 12:00, information only, "I don't want a complicated solution"):** "he climbed on shore
   correctly, but one of the village animals blocked his way and he correctly gave the 'cant follow you message'. is
   there anything he can do to navigate that problem?" (log 11:58:57 "stuck: 34877 gave up at 6307.6 948.5 5202.6
   (crumb 0.9 m away, player 15.3 m)").
   Owner 12:02: "definitely do #2.. he'll get blocked by NPC's too. idk if the hit test can tell the difference between
   animals and NPC's but if it can, the message should reflect that, such as 'Blocked by animals!' or 'Blocked by NPC!'
   Some NPC's won't move ever...". Built 12:03 (live, logging only so far): `blockers()` in npc_probe: when he gives up
   (land, water, to-the-water), every body within BLOCK_R 2.5 m (2 m height) is listed with its kind from components
   (Animal -> animal, ActiveNpcState -> npc, an account -> player, DynamicEnemy01BehaviorState -> monster), distance,
   in front/behind, faction, plus his collider's "touching a character / a player" flags; log "stuck: <id> in his way:
   ...". h.blocked_by = the nearest kind in front. Notice text not changed yet (wording to confirm with the owner).
   Backup `claude_scratch/npc_probe.before_blockers_1203.lua`. Unverified: that village animals carry "Animal" and
   villagers "ActiveNpcState".
   **Diving (owner 12:05):** "I swam back on the little island again and he followed me correctly. I jumped off this
   island and he did correctly follow me, but he did not match my depth in the water. I swam all the way to the bottom
   and he did not follow me down." Log: he stays at the surface (his depth 0.93) above the player: by design since
   fix round 2 (10:38, held at SWIM_DEPTH below the surface where he is). Before round 2 he dove because he was held
   at the player's height. The hound has canDive = false and an Oxygen value (5): drowning not known.
   Owner 12:07: "#2 -- he should dive with me, because there are a lot of underwater areas and it would be cool if he
   could follow me down". Built 12:07 (live): the player in the water deeper than DIVE_PLAYER 1.8 m (at the surface he
   reads ~1.3): the hound is held at the player's height + FLOAT_LIFT 0.45 (same quarter step, at most 0.08 m a tick,
   never pushed down while touching the bottom); back to the surface when the player comes up. Logs "dives with the
   player" / "back to the surface". The bank hop now only fires when the player is OUT of the water. Waterlog lines
   start with "air <now>/<max>, health <hp>". Backup `claude_scratch/npc_probe.before_dive_1208.lua`.
   Dive test (12:08-12:10): "dives with the player" 12:08:51, down to 6.4 m deep (player 6.8 m) 2.0 m from him, back
   to the surface 12:10:00; air stayed 5/5 and health 3680 the whole ~70 s under: no drowning seen. Owner 12:10: "he
   looked fine, followed me well".
   **Shore jump retest (owner 12:23: "I jumped into the water from the shore and he appears stuck or confused"):** body
   41363 on the shore (y 946.15, 0.8 m above the water surface 945.36), the player swimming 10 m out. Log 12:23:36-41:
   "trail ends at the water: straight to the swimming player" / "back on the trail" flipping every 10 ticks (0.17 s),
   he did not move, no notice (each flip resets the to-the-water progress mark). No "leap" line (the player probably
   touched ground in the shallows). Cause NOT found: at 12:24:17 a logging-only reload (new line "drive <id>: switch:
   player wet ..., surface, his height, near water, leap, player m, trail n crumbs, last crumb m, tick") reset his
   trail; he went straight into the water 0.5 s later. The flip is tied to the trail's state; the new line will show
   it next time.
   Retest 12:25:55 (owner 12:26: "he jumped in this time with me"): leap recorded (1.4 m), straight to the swimmer
   ("trail 2 crumbs, last crumb 1.3 m"), at 12:25:57.135 "back on the trail" with "last crumb 3.0 m", 0.07 s later
   in the water. Likely cause of the 12:23 flip-flop: the switch needs the trail's last crumb within 3 m; walking
   straight toward the player carries him past 3 m from it, so it switches back to the trail, he turns toward the
   crumb, gets within 3 m, switches again. Fix idea: once he heads straight for the swimmer, he stays on that until
   he is in the water himself or the player leaves the water.
   Owner 12:26: "it happened again. I jumped, hit the the shore edge and swam in" (log 12:26:30-32: "last crumb 3.0 m"
   every flip, the player 3.9 -> 6.3 m away). Owner 12:27: "yup make it". Built 12:27:43 (live): the switch keeps
   to_swimmer while the player is in the water once it was on (was_to_swimmer). He went into the water 0.6 s after the
   reload. Backup `claude_scratch/npc_probe.before_commit_1228.lua`.
- **Double-jump cliff (owner 12:31: "there is one last thing, not sure we should mess with it since everything is going
  well... I double-jumped up a cliff and made it, but the dog could not"):** log 12:30:04 autojump "a step 2.49 m up
  ... aims 3.19 m high, push 16.2" landed +2.54 m (up), but 12:30:10 he dropped back down 4.04 m (takeoff at 949.23,
  "landed -4.04 m"); then 12:30:19 "stuck: gave up at 6280.7 946.3 5219.1 (crumb 6280.4 949.8 5218.8, 0.4 m away)":
  the next crumb 3.5 m straight above him, 0.4 m out (a wall face). Not changed.
  Found for the blockers log: "his collider: touching a character true" with nobody within 2.5 m, so
  hasSpheroidCollision is not "touching a creature" (a wall counts too): the kind list from components is the
  reliable part.
  **Owner decisions 12:38:** "I think we should try to implement that, we double-jump a lot and he'll need to follow
  during that situation. Also -- in general, I think you should add the player meta data to the bread crumbs, even if
  we are not using the information yet, because in the future were certainly going to run into situations where
  having that information would be useful, even possibly required to solve the problem. Meta data could include
  things like, was I running, jumping, did I take off in the glider, and any other relevant player meta data I did
  not think of). To be clear, I don't really want to change how any of the existing stuff as it is working right now
  (other than adding the ability to follow a double jump to higher heights)."
  Owner 12:40 (while building): "if jumping higher is his only block to following me, he should do it...".
  **Built 12:40 (npc_probe, live):** (1) player metadata: every tick the player's locomotion state, jump count/type,
  speed, up/down speed, facing, water depth; each crumb keeps it in `crumb.m`, the crumb log line shows state, speed,
  facing. Air segments (every time in the air between crumbs): takeoff point/speed/up speed, top, landing, duration,
  jump count max, "second push" (up speed rising 3 m/s over its lowest mid-air: a double jump), every locomotion
  state seen; the takeoff crumb gets `.takeoff`, the first crumb after gets `.landing`, into water `.water`; log
  "air <id>: the player took off at ... came down at ... (x m higher/lower, y m out) after s; jump count n, second
  push b, states ...". (2) jump follow: at a takeoff crumb (within DJ_AT 1.5 m, height within 1 m) whose segment came
  down DJ_RISE 1 m or more higher: a double jump (count 2+ or second push) launches at once; any other such jump after
  DJ_WAIT 60 ticks without progress (his own step jump first). Launch = Velocity up for landing height + DJ_MARGIN 0.7
  (gravity 25, max 16 m/s) and across to land on the player's landing point (max 10 m/s); edge stop and step jump off
  for the flight (DJ_TICKS 150). Logs "double jump <id>: follows the player's ..." and "... down at ..., x m from the
  player's landing". Nothing else changed. Backup `claude_scratch/npc_probe.before_meta_dj_1240.lua`. Unknown before
  the test: whether a Velocity write takes on LAND (in water it did), and what jumpCount counts.
  **Test 1 (12:41-12:45), owner 12:44:** "I'm getting 'Companion can't get up there!' in the messages window, but not
  the notice window... so that should be fixed, also the dog can't get up here. I did see him make an attempt".
  - Metadata works: double jumps log "jump count 2, second push true" (a single jump once also showed "second push
    true": the jump COUNT is the reliable sign).
  - 12:42:54 double jump follow fired (3.6 m up, 4.7 m out) but a Velocity write alone did nothing on the ground (he
    never left it). His own step jump then got him up 3 m (12:42:56). The next ledge (1.6 m up, 4 m out) the player
    reached without an air segment the log saw (a climb/mantle).
  - Notice bug: he gave up with the player 4 m away, "the player is back near him" was true at once, so notice on/off
    every 3 s: a Messages line each time, nothing kept in Notices.
  Fixes 12:45-12:46 (live): resume after a give-up only when the player has MOVED STUCK_MOVED 1.5 m since then (and is
  near); launch = lift 0.3 m + speed, the speed rewritten until the game counts him in the air (DJ_LIFT 40 ticks; it
  took 14 at 12:45:06); over the landing spot (0.6 m) the speed across goes to 0; and a crumb-based jump: no progress
  for DJ_WAIT toward his next crumb that is DJ_RISE..6 m higher and within DJ_REACH 6 m: the same launch at it (log
  "double jump <id>: jumps up to his next crumb ..."). 12:45:06 (before the DJ_LIFT fix) it went up 2.2 m but the
  flight ended after 10 ticks, he flew 7.6 m past the ledge. Backup `claude_scratch/npc_probe.before_djfix_1246.lua`.
  **Test 2 (12:50), owner 12:50: "his double jump looks great".** Log: 12:50:40 the double jump follow launched (body
  47704, 2.6 m up, 4.7 m out, in the air after 5 ticks) but went nearly straight UP (0.95 m forward, highest +3.0 m)
  and came back down 2.7 m below the landing; 0.6 s later his own step jump with the boost ("a step 2.67 m up ...
  push 17.9", landed +2.51 m) got him onto the ledge: that is what the owner saw. So the launch's speed ACROSS does not
  hold once he is in the air (the up speed does). Not changed yet.
  Owner 12:52: "if you think you can tweak it go ahead. one time he cleared the jump, but slid off". Built 12:52 (live):
  in the air the speed across is written every tick toward the landing spot until he is over it (up/down left to
  gravity); after a jump-follow landing up top he stands still DJ_SETTLE 20 ticks (speed across 0, target = himself).
  Backup `claude_scratch/npc_probe.before_djsteer_1253.lua`.
  **Test 3 (12:55, 4 double jumps), owner 12:56:** "the first two times he had to jump twice. the 3rd time he got it in
  one jump, the 4th time I think he jumped twice. this result is good enough for me, but if you think you can tweak it
  further so he can nail it in one jump, go ahead". Log: all 4 follows landed 0.5 m from the player's landing and
  level with it (0.2-0.3 m), "7.0 / 7.3 / 6.6 / 7.3 m forward, highest +3.2..3.7 m". The "second jump" was the native
  step jump hopping him IN PLACE 0.35 s after landing ("a step 0.7 m up ... 0.08 m forward"), as the 20-tick settle
  ended (the 3rd test had no hop). Tweak 12:57 (live): DJ_SETTLE 45 ticks, with the step jump and edge stop off while
  he stands still settling.
  **Test 4 (12:58), owner 12:59: "looks good. he nailed it first try, the other jumps didnt get quite as far, but he
  still made it up".** Log: all 4 follows down 0.4-0.6 m from the player's landing, level (0.2-0.4 m); in 3 of them
  the native step jump then fired 0.78 s after landing ("a step 0.7-0.8 m up 1.5 m ahead", i.e. real ground rising
  toward the player's next crumbs), which is likely the "not quite as far" look. 3 of 4 launches were at the 10 m/s
  across cap (8.5-9.8 m out). Owner content; no further change.
- **Invincible Mode and air (owner 12:11, a player's complaint):** "when invincible mode is on and I go under water,
  it keeps me alive, but the oxygen level depletes and we get the drowning effect on the screen.. anyway to keep my
  oxygen full so I don't get that message when in invincible mode?" Found: Invincible keeps mana full in
  experimental.lua keep_stamina_full (emf.attribute_add "mana"); EMF's emf.attribute has no "oxygen" name and refuses
  heals of other attributes (lua.md), but the player's Oxygen component is plain data: dataStorage reads "30 30 0 0 0
  30" at full (12:12, logged by npc_probe's waterlog, local only), DynamicOxygenState.accumulatedValue 0.00.
  Under water drowning (12:14): "0 30 0 0 0 30 (acc 0.53)": [1] = air now, [2] = max. Owner 12:14 "build it".
  **0.15.280 (server only, rule 0d: no game update, no dist-test):** experimental.lua keep_stamina_full: with
  Invincible Mode on, Oxygen.dataStorage[1] set to [2] when lower, DynamicOxygenState.accumulatedValue 0
  (glide.air_broken if it fails). Local server + work folder 12:14:50; result: "30 30 0 0 0 30" at 2.4 m deep.
  NOT on G-Portal (owner's word needed). Owner 12:16: "it worked, its keeping my air up, no I'm not ready to update
  G-portal".
- **Idea (owner 11:18, not decided):** "can't we write a plugin type system so you can just 'hot reload' the DLL or
  does EMF not like that? same with the client side? if we could 'hot reload' the DLL with a plugin type system, we
  might be able to avoid all this restarting...."
1. Combat behavior (next after follow/safety). **Owner's design, 2026-11-18 20:09, verbatim:** "You press 'E' on the
   campanion, there should be an "Attack" menu you can select. In the attack menu, you have 4 options. Passive,
   Defensive, Aggressive, and Healing. Each mode determines how the campanion acts and responds in battle situations.
   Passive: the campanion doesn't attack at all. Defensive: the campanion does not seek after monsters, but if
   attacked or if the player is attacked, the campanion will respond by attacking the monster. If he's hurt and the
   player is a good distance away, he should come running back, if the player is near by, he should just keep
   fighting. Aggressive: campanion seeks out targets that are in range and automatically attacks them. He will jump
   to the next nearest target in range until there is nothing left to kill. Only stops when he dies or is moved back
   to passive mode. Healing: Healing is like passive mode, campanion never attacks, but has the added responsibility
   of watching their player, keeping him healed up and tries to stay out of the combat. Monsters don't tend to run
   away so I don't think chasing monster will be an issue, but there should be a maximum distance the campanion
   should be at before running back. How close he gets to monster before attacking I'm not sure -- we'll have to pick
   a distance and adjust it based on game play -- 10 m or 15 m? The bite plus lunge enough for now for damage -- we
   can expand that later if it makes sense. Campanion stays in whatever mode you set it in until you change it."
   Known from 2026-11-17 tests: bite (attack 0, 0x63FE3237, 2 m) and lunge (attack 1, 0xC34733A8, 4 m) start through
   the C++ trigger (fkprobe.bite) with real damage (faction 11; level 50 bite 420); facing via fkprobe.face; the HIT
   log has attacker/target/amount for every hit on or by a companion. Claude's restatement 20:10, owner 20:11 "yes that
   all lays out right": Defensive = only a monster that hits him or the player; badly hurt (under 30% health) and the
   player more than 15 m away -> runs back, player near -> keeps fighting. Aggressive = any monster within 15 m of the
   PLAYER, then the next nearest. Every mode: more than 30 m from the player -> runs back. Lunge from 4 m, bite from
   2 m, paced by his own animations. Healing: how it heals is decided later. Build order: 1 the menu (no fighting),
   2 target logging only, 3 Defensive + Aggressive fighting, 4 Healing.
   **Step 1 done 20:12 (server Lua only, live, no restart; git):** the wheel is Follow me / Stay here / Attack / Put
   away; Attack opens a second wheel Passive / Defensive / Aggressive / Healing (title shows the current mode); the
   pick is matched by its label (the game side sends the label back, so no game update); kept in the roster as
   `fight` (none = Passive, Claude's default); notice "<name>: <mode>."; log "fight: <name> (<id>) <was> -> <mode>".
   Owner 20:22: "looks good for now seems to work" (log: Healing -> Passive -> Defensive).
   **Step 2 (watching only) live 20:24-20:26 (server Lua, git):** threats from the hit handler (a monster's hit on a
   following companion or his player); a monster scan for Aggressive companions (world:entities() once a second, walked
   over steps within 30 ms / 6000 entities; "fight scan: ..." once a minute); once a second per following companion
   "fight <name>: <mode>: would attack <id> (<why>; faction, health; m from him)" / "nothing to attack" / "never
   attacks", "; would run back: ..." (more than 30 m from the player; Defensive: hurt under 30% and the player more
   than 15 m away), logged when it changes. Monster = DynamicEnemy01BehaviorState, not ours, faction not 7/8/11; alive
   = NetworkHealth.health > 0. His health: Health.dataStorage [1]=3680 [2]=0 [3]=3680 [8]=3680 at full health: max
   taken as [3], NOT confirmed (the slots are logged again the first time he is hurt).
   Test 20:26-20:39 (owner 20:39 "we did lots of in and out around monsters"). Log: threats noted for hits on him and on
   the player; Defensive and Aggressive picks right (faction 4 monsters, health 1788-2168); Aggressive moved on to the
   next nearest after a kill (20:35:37); the scan: 41,277 entities in 7 steps, 5 monsters within 15 m. Max health
   CONFIRMED: hurt [1]=3226, [3]=3680, [8]=3680 -> [3]. He died once at 20:35:17 (Defensive, monsters hitting him).
   Seen for step 3: "nearest to him" flips between monsters as he moves (36361/36362/36363 alternating 20:35:41-56):
   in the real fight he must keep his target until it dies or is out of reach. 20:40: the log line now only when the
   mode, the monster or the run-back changes (it was every second: the distances in it changed).
   **Owner 20:47 GO for step 3:** "go ahead, he just needs to lock on a target that he picks until its dead, then make a
   new choice". (Claude keeps the owner's 20:09 run-back rules as the only interruptions: 30 m from the player, and
   Defensive hurt + player far; after that he picks again.)
   **Step 3 built 20:47-21:00 (git), waiting for the restart:**
   - C++ (`server_probe.cpp`, DLL md5 2f4bc191 installed, the loaded one renamed `.old_2100`): start_sequence (the bite
     test's trigger code, shared); per driven companion every step: combatData.selectedAttackIndex 0 = bite
     0x63FE3237, 1 = lunge 0xC34733A8 -> the move starts, the field goes back to 255 ("fight bite/lunge: sequence ...
     written" in the log); combatData.lastTargetId != 0 -> he faces that entity (like fkprobe.face).
   - Lua (`npc_probe.lua` md5 dfca9963, installed at the restart): drive_fight (a part after drive_jump_follow; true
     while he fights): Defensive/Aggressive only; picks the nearest candidate every 0.5 s when he has none
     (fight_pick: threats; Aggressive also monsters within 15 m of the player) and keeps it until it is dead; ends
     sooner only by the run-back rules (he is > 30 m from the player; Defensive: under 30% health and the player
     > 15 m away) or the monster > 30 m from the player; runs at it (homeZone/movementTarget = the monster: the native
     hook stops him 2 m off; edge stop on), faces it, lunge from 4 m, bite from 2.5 m; the next attack waits until
     his Actor.currentServerAction.animationStateId is back to 0 (at most 3 s, logged as TIMED OUT). The step 2
     "would attack" lines are gone (Rule 0n); fight_watch only clears old threats and logs his health slots.
     Logs: "fight <name>: attacks <id> (...)", "lunge/bite at <id> (x m)", "<move> over after x s (started after n
     ticks; animation ...)", "stops fighting <id>: it is dead / runs back: ...".
   - Fake-world test (local_server/tests via /tmp fighttest): lock-on, lunge then bites, waits for each move, next
     target after the kill; following unchanged (drive_harness: no errors).
   - Restart 20:59-21:00 (owner 20:58 "yes"). Owner 21:07 "where are all the monsters lol" (scans: 0 within 15 m up at
     y 1126). Fight at 21:11:22-21:11:43: locked on, bites 280/350/450 (one 900), killed several (33739, 31741,
     31618); he died at 21:11:43 and 21:14:25 (25 hits on him in about 20 s). Owner 21:15: "he's attacking things
     that are not there": 21:14:50 he locked on 31809 (it had hit the player), stayed exactly 4.0 m off and lunged
     every ~3.5 s; his hits landed on entity 3055812669 for 0. Owner 21:17: "he was attacking mushrooms and things
     that were not monsters I think". C++ bug seen: each attack start written ~7 times in the same tick (the hook runs
     several times per step; the 255 reset is not seen in time): guard per entity per tick at the next rebuild.
     Proposed (not done): out of reach = no progress toward his target for 3 s and no hit on it -> drop it, skip it 20 s.
     21:18 logging (live): every threat and every target described: faction, the template's model
     (world:template("ModelResource", id).model), and which of DynamicLocomotion / DynamicPathWalker / NetworkHealth /
     Animal / MovementCollider it has (to tell fixed plants from creatures by data).
   - Owner 21:20 "does the dog have any armor or defensive numbers, he seemed to die pretty quick"; 21:21 "lets just do
     more logging first". Known: no Armor/ArmorPoints component; his hits taken at 21:11: pierce 238, cut 206 (melee),
     shroud magic 48-170; ~7 monsters, 25 hits, ~3,700 in about 20 s. 21:22 logging (live): his defence once per body:
     DamageSusceptibility [0 1 0.8 0.6 1.5 0 0 0 0 1 1 1 1 0 1 1.2 0.6 0.8 1] (19 multipliers, which slot is which
     damage type NOT known), DamageMod [0.5 0.5 1 0], Armor none, ArmorPoints none, Level [50 105], max 3680; every hit
     on his player by a monster ("the player took ..."), and every 10 s with hits "last 10 s: took n hit(s) from m
     monster(s) [type amount ...]; dealt x in y hit(s); his health". Options for later (owner to pick): more health
     per level, lower susceptibility per type, or both.
   - Fight data 21:22-21:30 (owner 21:30 "have a lot at the data"): the same monster's hit on the player vs on him:
     46515 cut/pierce 41-82 on the player, 166-256 on him; 46555 fire melee 82 on the player, 545 on him. Burning ("fire,
     other") 102-112 a tick, many ticks: 2,755 in one 10 s at 21:27 (killed him). His bites 420 (600 some). All targets
     real creatures (faction 4, DynamicLocomotion+DynamicPathWalker+NetworkHealth+MovementCollider). Owner 21:34 "I saw
     him attacking a door": 21:29:20-33 locked on 46554 behind it, 3.1-3.9 m, 8 lunges, hits on object 2969043268 for 0
     (its health 160 -> 140); same as 21:14 (4.0 m, object 3055812669). Owner 21:35: "I'd drop that to like 2 seconds
     and he definitely needs "Armor"". **Done 21:36 (Lua, live, git):** out of reach = not within bite reach (2.5 m),
     no 0.3 m closer and no hit of his on it for REACH_TICKS 120 (2 s) -> let go ("stops fighting ...: out of reach"),
     not picked again for SKIP_TICKS 1200 (20 s). Owner 21:37 "build it" (armor = one third of every damage type).
     **Armor done 21:38-21:40 (Lua, live, git):** match_armor (setup + every second): DamageSusceptibility[i] = base[i]
     x ARMOR (1/3); the base is read once from a body and kept in the roster as `sus_base` (saved), so a reload never
     scales twice (world:template("DamageSusceptibility") gave nothing). HOUND_SUS = the hound's own values (logged
     21:22) recovers bodies the first 21:38 version had already scaled. Live: N1 and N2 at [0 .33 .27 .2 .5 0 0 0 0
     .33 .33 .33 .33 0 .33 .4 .2 .27 .33]. Logs "armor: ...". Expected: physical melee ~55-85 instead of 166-256, fire
     melee ~180 instead of 545, burning ~35 a tick instead of 102-112 (to be checked in the next fight).
   - 2026-11-19 07:28 the owner rejoined (server up since 20:59); armor applied to each respawned body from the saved
     base (07:28, 07:29, 07:33). 07:29 and 07:33 (following, not fighting): a 2.7 m step up; he jumped (13 m/s up,
     0.6 m out), came back down at the bottom, collider "touching" true; one try per crumb -> can't follow -> respawn.
   - **Owner 2026-11-19 07:50, verbatim:** "I do think we'll need a new specific "pathing" system to handle obstacles
     and better navigation on the battle field... we need to dial in to make sure he's attacking monsters, etc
     hopefully you have all the logging in place for this. I saw him getting stuck on fences and other things. he has
     a good jump ability so we'll need to think about having him jump over that stuff, maybe use some of the older
     techniques we used in the old pathing system to avoid objects. just some ideas. we'll test things one at a time
     and improve it one bit by one bit". 07:51 logging (live): "fight <name>: stalled on the way to <id>: x m away, y
     m above/below him, no closer for 0.5 s; his state, speed; collider: touching, a player, last slide side; ground
     (distance, walkable, normal y), standing on" + "fight stall: ... in his way: ..." (once per stall). Material from
     before: the C++ probe has a ground ray and the game's walkable search (fkprobe.gr..., "ground program",
     PathGridSystem) from the 2026-11-17 experiments.
   - Owner 08:33: "he's trying to go after bats, the bats move around a lot so he's not tracking them very well. he
     makes some attacks, but a lot of times he's not facing them. I also notice he keeps keeps coming back to me
     instead of staying locked on a monster." Log 08:31-08:33: bats faction 6, 1.4-2.4 m above him; 28 attacks, one
     hit the bat 63138 for 350 (killed it), the rest hit objects for 0; the 21:36 out-of-reach rule dropped a bat every
     2-3 s (~15 times) -> nothing left -> back to following. C++ faces the target only when he stands.
   - **Owner 09:03, THE ATTACK SEQUENCE SPEC, verbatim:** "we need to keep this simple. let me restate what
     specifically needs to happen and spell out what I think you need to do exactly: once he detects and goes into
     "attack mode" the code that makes him follow and return to me needs to stop until he gives up on his attack
     sequence. attack sequence: he picks the nearest target. he shoots a ray at the target to make sure there's
     nothing blocking him. he shoots the ray to try and avoid fences, walls, trees, and objects that could block his
     path to the monster. if the rays gets blocked, he picks the next nearest target until he finds one that isn't
     blocked. this ray stays up the whole time (or is shoot out repeatedly during the fight) to make sure nothing new
     blocks him and the monster he is fighting. he locks on to that target, always facing the target no matter how it
     moves. of the target moves, he moves to face it. he runs to the target attacks as frequently as he can. he does
     not leave it and attacks it until its dead unless the ray becomes blocked and he can no longer deliver attacks.
     monsters move around a lot during the fight so he will need to frequently check for a block with his ray. if he
     gets blocked he can try to jump and move around to reposition himself in an attempt to get around the block. if
     he cannot, he stops attempting to fight that target and repeats the attack sequence to find another target and
     continue fighting. the attack sequence ends when he cannot find another target to attack after several tries OR
     until all the monsters are dead."
     Claude's reading 09:1x: attack mode stops following/returning; nearest first, a C++ ray from his shoulder to the
     monster's middle, blocked -> next nearest; the ray every tick; faces it every tick; attacks as often as his moves
     allow until dead; blocked mid-fight -> a hop toward it, then 2 m left, then 2 m right (~1 s each), still blocked
     -> drop it (not again for 20 s) and pick again; end = nothing reachable on 3 tries 1 s apart, or all dead.
     **Owner 09:17, verbatim:** "3 tries before giving up on the attack sequence might be too few, but we'll start
     there. you can keep the 30 m leash for now, but he's not likely to exceed that as the player will typically be
     close by. I want to get rid of the requirement for the "running back when badly hurt with you far away."
     mechanic for right now. Defense mode mainly means he attacks only if something attacks us." -> the hurt rule is
     REMOVED; the 30 m leash stays; Defensive = only what attacked him or the player.
     **Built 2026-11-19 09:22 (commit 191329c), NOT yet tested in game:** C++ `fight_step` (server DLL md5 6990b645,
     installed; the one before renamed `fk_server_probe.dll.old_0922`; `.old_2100` still there): every step a ray from
     his shoulder (+0.7 m) to the target's middle (+0.5 m) for `combatData.lastTargetId`, clear = no hit or a hit within
     1 m of the target -> `combatData.isTargetReachable` / `distanceToTarget`; log "fight ray: ... clear/BLOCKED" on a
     change; the attack start once per step (the guard; it was written ~7 times per tick). Lua `drive_fight` = the
     sequence: pick (each candidate nearest first: lastTargetId = it, 2 ticks, read the ray; he stands still), fight
     (locked on; hold_at the target; attacks paced as before), blocked -> hop toward it, 1 s left 2 m, 1 s right 2 m,
     then dropped for 20 s and pick again; nothing reachable -> try again 1 s later, after 3 tries the sequence ends
     and the monsters that were blocked are skipped for 20 s too (else it starts again at once on them and he never
     follows the player; seen in the fake-world test). Following stops while the sequence runs. Logs: "fight N1: the
     attack sequence starts/ends ...", "attacks", "is blocked", "repositioning", "hops", "moves 2 m", "gives up",
     "clear again", "is dead", "picks again", "try n", stall lines. The Lua (md5 fdedea51) is staged in
     claude_scratch/seq_npc_probe.lua and goes on the server with the restart (the old DLL never writes the ray).
     **Owner 10:25, verbatim:** "the only one thing that needs to get added, if the player sets the companion back to
     "passive" during the fight, the companion should completely stop the attack sequence and return to following the
     companion. one other small detail, when the companion is in defensive mode and responds to an attack, it should
     automatically switch to aggressive mode to keep fighting all monsters in the near area as any monsters around
     won't stop fighting". Built 10:3x (Lua only, md5 in the commit after 6e710d3): Passive (or Put away) ends the
     sequence the same tick (it already did: the mode check at the top of drive_fight every tick; fake-world test:
     ends at once, his target cleared, sent back to the player) -> he follows the player ("following the companion"
     read as the player). Defensive: the sequence starts only on a threat (him or the player hit), then he fights
     every monster within 15 m of the player like Aggressive until the sequence ends (the monster scan runs for him
     while it lasts); the menu's mode stays Defensive, so the next sequence again waits for an attack. Log: "the
     attack sequence starts (Defensive, something attacked: he fights like Aggressive until it ends)".
     **First test 2026-11-19 10:31 restart (DLL 6990b645 + Lua bf32a0d8).** Owner 10:38 "its not facing the target";
     "he killed the first target quickly"; "it looks like he hasn't picked a second target and locked on to it"; 10:39
     "the dog is just standing idle now". Log: 26929 (faction 6) one lunge, 500, dead (10:37:49). 26930 (faction 6, not
     moving, 0.1 m below him): ray clear, he got from 7 m to exactly 4.0 m and lunged 12 times ~3.3 s apart
     (10:37:50-10:38:48), no hit on it; at 10:38:48 the lunge hit three objects (2578711003/13/08, health 20/100, for 0:
     plants or props); then he stood (not closer, no lunge, the stall line once only) until the 10:40:12 reload, which
     reset the sequence: picked 26930 at 6.1 m, one lunge from 4.0 m, 500, dead. Same as 2026-11-18 21:14 and 21:29
     (4.0 m, hits on objects for 0): the THIRD time -> a pattern, not a one-off. The ray (0.7 m up to 0.5 m up) misses
     low things in his way. Logging 10:41 (live): every lunge/bite "he faces x deg off it; it at ..., moving v m/s, n m
     above/below him; him at ..." and at its end "he moved x m, now d m from it (was d0)".
     **Owner 10:40, verbatim:** "the dog should stay centered on me within my radius and kill anything in it".
     Claude 10:42 proposed (a) the radius: a 15 m circle around the player that moves with him; only monsters inside
     it; a target that leaves it is dropped; he ends the sequence outside it; it replaces the 30 m leash; (b) "can't
     deliver attacks" = his attack lands on an object, or no closer for a while -> the reposition steps. **Owner
     10:43, verbatim:** "yes. he definitely wasn't "stuck" though. he was idle and didn't come back to me, it looked
     like he wasn't searching for the next target." Cause found in the log: 10:38:49 the C++ edge stop "27129 stops
     at ... (ground 1.5 m ahead: a drop the player did not take, 0.88 m down)" (the edge stop is ON in fights,
     targetOfMyTarget = false) -> he stood; the ray was clear and the target alive, so the sequence kept him "fighting"
     and nothing moved him. **Built 10:5x (Lua, live by reload, NO restart):** FIGHT_LEASH removed; candidates (threats
     too) within FIGHT_RANGE 15 m of the player; a target past 15 m from the player is dropped ("left your 15 m
     radius"); the sequence ends when he is more than 15 + 2.5 m from the player. Can't deliver attacks = the ray
     blocked, OR his attack hit an object and not it (his hits noted by note_my_hit; another monster is no block), OR
     no hit on it and no 0.3 m closer for NO_HIT 2 s -> a reposition step (hop / 2 m left / 2 m right), 1 s, then he
     tries again from there; after the three -> gives up on it (20 s) and picks again; a hit on it starts the steps
     over. Logs "can't deliver attacks on X (why; d m away): hops/moves", "tries X again from here", "gives up on X:
     why after the hop, left and right". ~~Not done (to propose): the edge stop off in fights.~~ -> **WATCH, not a
     to-do** (2026-11-20, see below).
     **Owner 11:11, verbatim:** "the radius change definitely kept him more focused at least the last 2 fights. he still
     struggles to face the targets however. he attacks, lunges and then takes too long to turn around. now there are 2
     monsters attacking me and he took like 10 seconds to even respond to that, still better than before". Data
     11:10:09-11:10:59 (facing logging): degrees off the monster when an attack starts: -5, -23, -156, -121, -42, -119,
     -136, +93, +101, -23, -89, -79; the monsters mostly standing (0.0 m/s) -> not a moving target: the C++ look
     direction does not turn him in time while he stands; lunges carried him 4-5 m the wrong way ("moved 4.2 m, now
     7.0 m from it"), hits on plant 2579759654 for 0 -> he gave up on 36988 (11:10:15) and 36978 (11:10:28), skipped 20 s;
     the sequence ended 11:10:31 with both skipped although they were hitting the player; it started again at 11:10:48
     when the skip ran out (the owner's ~10 s wait). Then bites from 2.4 and 1.1 m killed both (420 each).
     Claude 11:1x proposed (1) facing: he turns himself toward it fast between attacks and attacks only when facing it;
     (2) a skipped monster comes off the skip list when it hits again. **Owner 11:17, verbatim:** "yes get the facing
     fix in asap. this is a big problem, keeping at the maximum distance he needs to be at to add the attack will be
     helpful as well because his lunge attack moves him so much. the closer he is to the target, the further he'll
     travel past the monster. this should be the default for any companion. the companion should only get just as
     close as they need to be to land the attack and no closer.... I don't know what that value is, but I'm sure you
     could tell from the data or I could try to search it, or we could test that range ourselves". **Built 11:2x (Lua,
     live by reload):** turn_toward: between attacks (not during one) his body turns toward it, at most 30 deg a tick
     (TURN; 180 deg in 0.1 s; `face` = the instant turn the following uses), and an attack starts only when he is
     within FACE_OK 15 deg; he runs at it only while farther than FIGHT_LUNGE (4 m, the lunge that hit at 10:40:13 started
     at 4.0 m), then stands where he is (bite only when it is within 2.5 m anyway); every attack's end logs "HIT it" /
     "MISSED it" with where it started (to find the real maximum reach from data); a skipped monster that hits him or
     the player again is a candidate at once ("is no longer skipped: it hit him or the player again"). "Default for any
     companion": all companions use this one drive_fight. Lunge reach: still to be measured (owner offered to search
     or test it).
     Power cut 11:38 (no fights after the 11:19 install); files checked intact; restart 12:47 via the helper (its watcher
     had to be started by the owner first: restart_watch.cmd). **Test 12:56-12:58:** switching works (12:57:13-37 five
     kills in a row, nearest first); facing FIXED (17 attacks, 0 deg off at the start, worst 12; before up to 156);
     9 lunges MISSED from 2.7-4.0 m: the monsters (faction 6) often moving up to 6 m/s, the lunge carries him ~5 m and
     ends past it, the monster behind him (the overshoot the owner predicted); a kill reset the attack, so killing
     attacks had no "HIT/MISSED" line. Weak spots told: all candidates blocked -> he stands 3 s and ends (as the spec
     says); he gave up on 26963 after lunges into a plant. **Owner 13:57, verbatim:** "yes log it, maybe increase his
     attack range by 20 m around me which will help". Logging built 13:58 (live): each hit as it lands ("his lunge's
     hit landed x s after the start on it/object/monster: he is d m from it, moved m"), his lunge at 0.4 s ("he is d
     m from it (d0 at the start), moved m; it moved m"), the killing attack ("his lunge from d m killed it x s after
     it started"). The radius: asked the owner whether "by 20 m" means a 20 m radius (from 15) or 35 m; not built.
     **Owner 13:58, verbatim:** "you're reading it right: 20 m". Built 14:0x (live): FIGHT_RANGE 20 (the radius he
     fights in, the monster scan, a target leaving it, the end at 20 + 2.5 m from the player).
     **Owner 14:02:** "theres a bat right in front of me, it hasn't attacked me yet and its a little higher position than
     were at. the dog doesn't see it?" Log (14:03 logging: positions on a blocked candidate): 26906 at 3005.4 845.0
     2846.3, 3.7 m above him, 7.9 m away; the ray hits at 2.7 m, ~2 m above his feet (the slope/ledge up to it); he
     picks it every 20 s, blocked 3 times, the sequence ends. **Owner 14:03:** "it probably looks blocked to him".
     **Owner 14:05, verbatim:** "if he hopped up he could see it for sure and jump to reach it. lets add that as a step
     to check on later. we'll make sure he can get targets right around him correctly first" -> **LATER LIST:** when
     every candidate is blocked in the pick phase, he hops (up) / repositions toward the nearest to see it, and jumps
     to reach one that is higher. Not now: first the targets right around him.
     Power cuts 14:10 and ~14:28; restarts 14:19 and 14:37 (the watcher came back by itself at 14:28). **Data 14:06-14:08:**
     lunges from 3.9-4.0 m: 6 kills at 0.38 s; one miss (the monster moved 1.5 m; at 0.4 s he was 1.7 m from it, moved
     3.1 m); bites from 0.7-2.4 m: 4 kills at ~1 s. **Data 14:21 (bats, faction 6, 1-2 m above him, up to 6 m/s):**
     facing 0 deg every time; in the 0.4 s to the hit the bat moved 2.0-2.4 m -> 5 lunges missed, 2 hit plants -> the
     reposition steps and giving up (26919 twice; it came back by biting him); 26918 killed by one lunge (1.5 m above,
     so height is not the problem). Also 14:22:04 picked 26920 at 19.5 m, dropped 0.4 s later at the radius edge.
     Claude proposed (1) aim ahead or (2) wait for it to slow. **Owner 14:52, verbatim:** "yes, bats are a good
     challenge because they are a hard target. is there a faster attack he can do against bats instead of the
     lunge?" Answer: only the bite (hit ~1 s) and the lunge (hit 0.38 s) are known; others in the hound's game data
     were never searched (a later item if the owner wants). **Built 14:5x (option 2, live by reload):** a target faster
     than FAST 3 m/s and out of bite reach: he stands at lunge reach facing it and lunges when it slows; waiting does
     not count as "can't deliver attacks" (ok_t reset); logs "waits: X moves v m/s ...", "X slowed to v m/s".
     **Owner 15:28:** "so far he's doing very well" (14:53-15:28: 42 kills, 114 attacks, 23 missed, 0 give-ups, 41 waits
     all ended with the target slowing). **Owner 15:29:** "going to play this dungon all the way through and then lets
     check the data for improvements". **Owner 16:31:** "he struggling with getting monsters that float in the air
     right now". Log: 68778 (faction 10) hovering 0.7-0.8 m above him, mostly 0.0 m/s: lunges from 3.5/4.0 m went
     under it (0.8-0.9 m from it at 0.4 s, ended with it behind him), bites from 0.9-2.4 m all missed; 68618 (0.7 m
     up) died to a lunge from 4.0 m. Claude proposed (1) jump into the attack, (2) lunge from farther. **Owner 16:32,
     verbatim:** "yeah lets see how that goes, he's done well otherwise I think". **Built 16:4x (option 1, live by
     reload, an experiment):** a target HIGH 0.5 m or more above him: when the attack has started he is lifted 0.3 m
     and gets upward speed launch_speeds(0, rise) (rise 0.8 -> ~8.7 m/s), rewritten for up to 6 ticks until he is in
     the air; the attack's forward move is not touched; h.djump NOT used (the follow jump code stays out). Logs
     "jumps into his bite/lunge (up v m/s)", and the 0.4 s line "he is h m higher than at the start, it is x m above him".
     **Owner 16:35:** "he lags behind me a bit more than I'd like for a dungon run.. anyway to keep him closer to me while
     running?" Cause: the C++ picked his speed by straight distance only (walk < 6 m, run 6-12, sprint > 12). Claude
     proposed (1) lower steps, (2) his pace from the crumb meta data (list #8) + sprint when behind. **Owner 16:37:** "I
     agree #2". The player's crumb speeds (6700 crumbs in the log): ~2-3 m/s walking, ~4-5 running, ~8-9 sprinting.
     **Built 16:40:** Lua: every tick PACE_WALK into combatData.prowlAngle (his AI is off, nothing else writes it);
     drive_steer: the crumb he heads for: spd >= 7 sprint, >= 3.5 run, else walk; log "pace <id>: walk/run/sprint (the
     player at that crumb: v m/s; player d m away)" on a change. C++ (DLL 30da7118, installed for the next start; the one
     before renamed fk_server_probe.dll.old_1640; .old_0922 and .old_2100 still there): speed = sprint if more than
     kCatchUp 6 m from where he is headed (the player; in a fight the monster), else the Lua pace; the old 6/12 m steps
     are gone. drive_harness: identical to the commit before on 9 seeds apart from the pace field. Lua live 16:40 (the
     old DLL ignores the pace until the restart).
     Restart 17:22 (owner 17:21 "ready to restart"). **Owner 18:39:** "you should have a lot of data to analyze now".
     **Data 17:22-18:39 (no errors):** 49 sequences, 252 attacks; ground bites at level monsters 26/31 hit or kill,
     ground lunges 15/18; 67 waits, 66 slowed; 14 give-ups. Jump attacks (floating monsters 0.5-3.3 m above): he rises
     2-3 m by 0.4 s; jump LUNGES 20/25 hit or kill, jump BITES 5/22. 30 of 47 sequence ends = everything left blocked:
     97 of 129 blocked checks were monsters >= 1.5 m BELOW him (another floor; the ray hits his own floor's edge), 20
     monsters; each such sequence held him still ~3 s, again every 20 s. Pace (at each change, player away median):
     walk 2.5 m, run 3.1, sprint 5.1. Can't follow 18x -> 15 respawns (7 drops too high, 11 blocked/up), the same kinds
     as before. Claude proposed (1) a target HIGH or more above him: lunge only; (2) he keeps following while he checks
     the candidates. **Owner 18:47, verbatim:** "yes, overall he did well for a pet". **Built 18:5x (Lua, live by
     reload):** (1) ix = bite only when within FIGHT_BITE AND less than HIGH above him, else lunge; (2) the pick phase
     returns false (the following goes on) while it checks (lastTargetId set, RAY_WAIT, the ray read); he stops only
     once a target is locked on.
     **Owner 19:17:** "any reason why he's not attacking the current monster?" Log: 19:16:09 locked on 171975 (faction 15,
     DynamicLocomotion+DynamicPathWalker+MovementCollider, NO NetworkHealth: a part of a monster), its Velocity a
     constant 20 m/s while it did not move (0.0 m in 0.4 s) -> the bat wait forever (waiting resets the no-hit rule);
     171973 beside it (with health; one jump lunge hit it for 400) hit him 8 times, 3680 -> 2751. Claude proposed (1)
     only entities with NetworkHealth are monsters; (2) a target's speed from how far it really moved (~0.25 s), not
     its Velocity. **Owner 19:18, verbatim:** "yeah #1 for sure for ahead". **Built 19:2x (Lua, live by reload):**
     is_monster needs NetworkHealth; monster_alive: no health = not alive. #2 not built: asked whether "go ahead"
     covered it.
     Live 19:19; at once he attacked 171973 (the real monster). **Owner 19:20, verbatim:** "put it on the list, but it
     probably won't come up again" -> **LATER LIST:** a target's speed for the bat wait measured from how far it really
     moved (~0.25 s) instead of its Velocity (only matters if a real monster reports a wrong speed; not seen since #1).
     **Owner 19:21:** "does that dog have any mana? can he do heals?" Logging 19:21 (live): the hound has NO Mana,
     ManaRegeneration, HealthRecharge or HealingMod (only Health 3680 and Stamina 335; he never heals himself); the
     player: Mana 483, ManaRegeneration, HealthRecharge, HealingMod x1.15. FlameKit can heal: emf.attribute_add(...,
     "health", n) (the game's attribute code, stops at max). **Owner 19:25, verbatim:** "yeah write it up, as for how
     much mana and how much heals... im not sure. I only have 483 mana at level 50, but im not spec'd as a mage. I would
     give him 800 mana and see how that works? how would a heal animation work with him? nothing for him I would
     imagine?" -> Claude's take (was written as local_server/HEAL_PLAN.md; **owner 20:27:** "yeah delete that, I don't
     actually need a write up, I just meant give what you think" -> deleted, in git history): his mana is ours (the
     game gives him none), 800, refills 10/s; in Healing mode he heals the player below 60 % for 25 % of max health
     (200 mana, 4 s apart, within 20 m), then himself the same way; otherwise as Passive; no heal animation known (only
     bite and lunge): he turns to the player, a notice, the health bar rises. Open: the numbers; healing himself
     outside Healing mode too; a notice per heal or not. Nothing built.
     **Owner 20:27:** "will he be able to heal himself in defense and attack modes too?" Claude's take: one mana pool and
     one heal for every mode; Defensive/Aggressive: he heals only himself, at ~40 % (mana lasts the fight), no
     animation so it never stops an attack; Healing: the player first, then himself; Passive: a slow recovery between
     fights. **Owner 20:35, verbatim:** "yes that would be good, did you find a howl animation he could do" -> the
     healing design above is agreed (not built). Howl: never searched; his moves start by sequence id (FNV-1a of the
     sequence GUID) through `fkprobe.bite <entity> <hex>`; the hound's other sequences would come from the game data
     (claude_scratch/tpl has kfc.py and the template lists). Asked the owner whether to search.
     **Owner 20:39:** "yes" (search). **Found (device scripts $HOME/hs/seqs*.py on the kfc.py reader; all 2157 action
     sequences = resource type 0x9fd4a561; id = FNV-1a 32 of the GUID's 16 bytes as stored (bytes_le)):** the hound's
     bite/lunge are the WOLF's: 0x63FE3237 Enemy_Wildlife_Wolf_Attack_Bite, 0xC34733A8 ..._Lunge; jump 0xE80706FC
     Enemy_Jump_Move. Other wolf/dog sequences: 0x89A1BC53 Wolf_Shout, 0x0BA28FDE Wolf_Ability_LickWounds,
     0xEE2A75E2 Wolf_Heavy_Opportunity_Howl, 0x60BD6595 Wolf_Heavy_Attack_Bite, 0xE5DAC59D Wolf_Heavy_Attack_Dash,
     0x538A6913 Wolf_Heavy_Attack_Stomp, 0x04F7403E Wolf_Sleep, 0x405E2057 Wolf_Spawn, 0x59DF6580
     Wolf_Reaction_Stun_Long, 0x45A6AA69 Enemy_Skeleton_Hound_Death, Pet_Dog_*: 0x194F5236 greeting_bark, 0xD76BB71B
     Idle_01_bark, 0xF59B6263 Sit, 0xACD28521 Idle_02_sniff, 0x88F25807 Sleep, 0x4DA2D783 Idle_Sad, 0x66D08E3F eating,
     0x0D240B10 being_petted_01; Interaction_Pet_DogCat_Buff 0xB1EB4A70. The full list: $HOME/hs/seqnames.tsv (device
     scratch, not kept). **Played on N1 (254966) 20:40:28-20:41:16, 8 s apart** (fkprobe.bite via commands.txt): 1
     Shout, 2 LickWounds, 3 Heavy howl, 4 dog greeting bark, 5 dog idle bark, 6 dog sit, 7 wolf sleep; all written
     into his trigger; what played: asked the owner.
     **Owner 20:48:** "I missed them all I had no idea you did it... can you output the text as you do them for each
     one" -> played again 20:48:48-20:49:49, a SendUserMessage right as each starts (do it that way for any visual
     test). **Owner 20:51:** "I wanna see 1 2 and 3 again" (played 20:51:11/22/34). **Owner 20:55:** "I didnt see any
     heals go out I like 1 and 2 not sure which one yet" (he was at full health since a 20:37 respawn, so the move's own
     heal, if any, could not show). Claude suggested Lick Wounds for healing himself, Shout for healing the player.
     **Owner 20:58, verbatim:** "Lick Wounds lets go with" -> the heal move: Lick Wounds 0x0BA28FDE (asked: for every
     heal, his and the player's?).
     **Owner 20:59, verbatim:** "I changed my mind, I want Wolf Shout" -> the heal move is **Wolf Shout 0x89A1BC53**
     (replaces Lick Wounds; asked again: for every heal?).
     **Owner 21:01, verbatim:** "every heal would be a good queue that its happening" -> Wolf Shout plays on EVERY heal
     (his own and the player's), as the cue that a heal happens.
     **Owner 21:01, verbatim:** "yeah lets build it now". **Built 21:1x (needs the restart for the shout):** Lua
     `drive_heal` (called every tick after drive_upkeep, never takes over the movement): mana_of[name] (FlameKit's own,
     MANA_MAX 800, refill MANA_REFILL 10/s in every mode, full again after a Lua reload); a heal = emf.attribute_add
     "health" 25 % (HEAL_PART) of the target's max, 200 mana (HEAL_COST), HEAL_GAP 4 s apart, plays Wolf Shout
     (combatData.selectedAttackIndex 2); Healing: the player below 60 % (HEAL_BELOW) within 20 m first, else himself
     below 60 %; Defensive/Aggressive: himself below 40 % (HEAL_BELOW_FIGHT); Passive: no heals, recovers 2 % of his max
     a second (RECOVER_PART) after 10 s without a hit (RECOVER_AFTER; h.hit_t set in note_threat), no mana, no shout.
     Not while one of his attacks plays; the fight starts no attack while a move is asked or within SHOUT_TICKS 1.5 s of
     a heal; the heal waits for the fight's first step (it clears selectedAttackIndex). His health from
     Health.dataStorage [1]/[3]; the player's from emf.attribute "health"/"max_health". Logs "heal <name>: heals the
     player/himself +n (... before; mode); mana a -> b of 800; Wolf Shout", "would heal ... but has n mana",
     "recovers ...", "recovered". C++: selectedAttackIndex 2 -> start_sequence 0x89A1BC53 "heal shout". Fake world:
     Healing/Aggressive/Passive as above; drive_harness identical on 5 seeds. Not proven in game: emf.attribute_add
     "health" on the hound's body.
     Restart 21:14 (owner "yes"). **In game 21:20-21:29:** heals himself +920 (Aggressive 21:20:35 at 1085/3680; Healing
     21:28:16, 21:29:03), heals the player +629 (25 % of 2515) three times; every heal played the shout (C++ "heal
     shout: sequence 89a1bc53 written"); no "could not add health". **Owner 21:29, verbatim:** "can you add a notice
     message that says Companion heals you for <number>!" -> built (live by reload): on a heal of the player, say()
     "Companion heals you for <n>!" (the 5 s chat notice, features.chat notice_to).
     **Owner 21:31:** "maybe make the text green colored?" -> say() takes a colour; the heal notice is #5ad25a (live).
     **Owner 21:48:** "seems to be working, what do you see?" 21:31-21:48 (Healing mode): 4 heals of the player (+629, 2
     pairs 4 s apart, mana right, every shout played), no errors; but both pairs line up with a "can't follow: blocked"
     0.5-0.6 m from his crumb on flat ground (21:33:30, 21:38:46) -> respawn: the Wolf Shout holds him in place, two
     4 s apart = the stuck rule. Other respawns: 3 glide, 1 fast travel, 3 can't follow (steps, long jumps). **Owner
     21:54:** "yes" -> built (live): drive_stuck restarts its progress timer for SHOUT_HOLD 2 s after a heal (h.heal_t).
     **Owner 22:00:** "when were not in combat, or combat finishes, he should heal me up full regardless of my %".
     Claude asked (Healing only? the reading). **Owner 22:04, verbatim:** "when he's in heal mode, he should just always
     heal me to full, when he's in attack or defense I meant more like when all the attack sequences are all done, he
     should do full heals on himself and me, but can wait until all attack sequences are done". **Built 22:0x (live):**
     Healing: the player within 20 m up to full, always (HEAL_FULL 0.99: a heal when 1 % or more is missing), else
     himself below 60 %; Defensive/Aggressive: during an attack sequence (h.atk) only himself below 40 %; with none
     going on, the player and then himself up to full. Passive unchanged. The heal itself unchanged (25 %, 200 mana,
     4 s apart, Wolf Shout, the green notice for the player).
     **Owner 22:09:** "is there way to add an healing spakle animations?" The game's heal VFX templates (claude_scratch/
     tpl/templates.csv) spawn with emf.spawn (as the loot mark, ground_loot.lua MARK_FX). Built (live 22:12): console
     `flamekit.npc healfx <n>` spawns HEAL_FX[n] on the nearest player for 10 s (emf.destroy in F.tick): 1
     VFX_Resource_Increase_Health 2c411630-8a38-41a3-b3d2-a263609a1bdb, 2 ..._NoSound b8e9aca9-..., 3
     VFX_Enemy_Skeleton_Melee_Elite_Heal_Ally_Player_Companion 35183e7f-..., 4 ..._Heal_Ally 100772b0-..., 5
     VFX_Skill_Martyr_Heal 21443035-..., 6 VFX_Ability_Casting_Heal_Channel af4436da-..., 7
     VFX_Spell_ChainHeal_SourceTarget_player fc4f8028-..., 8 ..._NoTarget c15e5bc4-... Shown on the owner 22:12:29-
     22:14:31 (all 8 spawned, a message as each started); which looked good: asked the owner.
     **Owner 22:15-22:16:** "show me #1 again"; "#1 is the only one I saw do anything, can you run that one again?";
     22:17 "run the effect on the dog now so I can see it there" (healfx got an optional target: healfx <n> [entity];
     shown on N1 127633 22:17:47; the effect stays where it was spawned). **Owner 22:18, verbatim:** "yeah thats good, so
     when the dog heals himself he can do the effect, when he heals the player he can do the effect on himself and me to
     highly the heal" -> built (live): after a heal HEAL_FX[1] VFX_Resource_Increase_Health on him, and on the player too
     when it was the player's heal; removed after 10 s (heal_fx_shown).
     **Owner 22:21:** "seems good, we may have to adjust some numbers" (healing accepted; the numbers stay open: MANA_MAX
     800, MANA_REFILL 10/s, HEAL_PART 25 %, HEAL_COST 200, HEAL_GAP 4 s, HEAL_BELOW 60 % (himself in Healing),
     HEAL_BELOW_FIGHT 40 %, HEAL_FULL 99 %, RECOVER_AFTER 10 s, RECOVER_PART 2 %/s).
     **Owner 22:21:** "is there still a 2 second delay before he teleports when he has to spawn and respawn?" (yes:
     STUCK_TICKS 3 s -> the notice, TP_AFTER 2 s -> put away, back 1 s after the player stands, LAND_TICKS). **Owner
     22:22, verbatim:** "get rid of the 2 seconds, show the error, but teleport him immediately" -> built (live): TP_AFTER
     0 (put away the tick he cannot follow; drive_harness seed 1003: tick 632 instead of 753); put_away_for shows the
     same words (STUCK_TEXT[h.cant]) as a 5 s notice in #ff9050 (the stuck status is cleared at the put-away, so it would
     have shown for one tick). The 3 s of no progress before "can't follow" is unchanged.
     **Owner 22:26:** "it works well".
     Claude offered a Development build, then withdrew it (Rule 0d: all of it runs only on the server). **Owner
     2026-11-20 06:17, verbatim:** "update the changes.txt and make sure everything is checked into git for dev" ->
     **0.15.285 (server only, like 0.15.280):** flamekit/mod.json 0.15.285 (flamekit_native stays 0.15.284: no client
     change, no dist-test), changes.txt: one entry for all companion work since 0.15.279 (rebuilt following, pace,
     Attack menu modes, the attack sequence, bats/floaters, armour, healing, instant respawn). Copied to the server and
     the work folder. Git: every server file (npc_probe.lua, npc_fields.lua, main.lua) and server_probe.cpp matched the
     repo (md5) before the commit.
     **Owner 06:19, verbatim:** "I just want to make sure all the new source is checked into git.. thats all". Full
     compare of the work folder (69 files) with git: all game source identical (flamekit/, flamekit_native/src,
     server_probe.cpp, local_server/); 4 notes files newer in git (the work copies are 2026-11-13..16). Never in git
     until now, added (fe2689d): `tools/gamedata/` (kfc.py reader, template tools, arsenal*.py, tplcomp.py, the action
     sequence search seqs*.py + seqnames.tsv, templates.csv, monsters.tsv; README), `local_server/tests/fight/` (the
     fake-world fight/heal tests seqtest*/healtest*/fighttest/doortest/armortest/watchtest, harness.lua, syn.lua,
     helper .py; README), `flamekit_native/notes/map_marker_registry.json`. Left out on purpose: the work folder's
     old `notes/probes/npc_probe.lua` / `npc_wheel_probe.lua` (2026-11-17 copies, superseded; their history is in git)
     and `npc_fields.lua` (identical to local_server's).
     **Owner 06:32-06:37:** "what was the edge check in fights about?", "so he runs off cliffs without my trail to
     follow?" (no: off the trail the C++ edge stop holds him at no ground within 12 m, more than 7.5 m down, or steeper
     than 30 deg unless the player took it), "there was data to back this change up?" -> No: ONE case (2026-11-19 10:38,
     a 0.88 m step), which Claude put on the list as "to propose" by itself, against the one-off rule; since the 21:14
     restart 6 edge stops, all in fights, each ONE tick ("goes on" right after), none left him stuck. **Owner 06:37:**
     "keep it as a watch item, how did it get on the list?" -> **WATCH: the edge stop in fights** (look again only if it
     actually keeps him from a monster again).
     **Owner 06:42:** "I think I as more concerned with the times he killed himself ... can you check every time he
     died yesterday ... see if there is a pattern to why? nothing might need to be changed". 8 deaths on 2026-11-19 (the
     client logs, every session; the server log only from 21:15): (1) killed right after a respawn, 0.2-0.3 s
     (15:57, 18:56, 21:38): 21:38 a 725 hit on the new body before FlameKit set level 50 and the armour (0.2-0.5 s after
     the spawn); (2) falls after a copied jump: 21:47 (the player stepped 4.4 m down onto a narrow ledge 0.9 m out; his
     jump went 9.7 m forward, fell 20.7 m), 21:57 (the player double-jumped and glided 2.5 s / 17 m, 4.7 m lower: not a
     break because glides are excluded from the 2 s flight rule and 4.7 < 7.5 m; his jump fell short, 22.5 m), 18:30 and
     19:06 likely the same (just after "afraid to follow (drop too high)"); 18:33 unknown. **Owner 06:44:** "he didn't
     detect that the jump would kill him? why didn't he just teleport?" (no check of his own jump; nothing watches him
     in the air). **Owner 06:52:** "its common to jump before popping out the glider". **Owner 06:53, verbatim:** "I think
     safety net is a good idea" -> built (live): drive_put_away: in the air (his DynamicLocomotion.state 2) h.fall_y0 =
     the height he left the ground at; more than FALL_SAFE 7.5 m below it -> put away ("falling"), back beside the
     player once the player stands (LAND_TICKS). Log "fall net <id>: x m below where he left the ground ...".
     drive_harness: identical on 9 seeds apart from the new field (seed 7: the net fired at 7.7 m down, correct). Not
     built (offered, not chosen): the glider rule (a jump where the player opened the glider = a break), level/armour set
     on the spawn tick.
     -> **0.15.286 (server only):** flamekit/mod.json + changes.txt line for the fall safety net.
     **Owner 07:54, verbatim (the next step, companion inventory):** "the next step will be adding an inventory option.
     I'd like you to start working on that while I test out the changes. we already learned A LOT about inventory items
     so some of the questions you have about it, I already have answers to. so I'd like the "E" menu to have
     "Inventory" menu. In this menu, it has "Open Chest", "Close Chest". "Open Chest" will spawn a large chest on the
     ground. all of their inventory items the companion has on them will appear. I guess EMF has some system for this
     already, so you'll need to explain that to me. When the player is done they can choose "Close Chest" and it will
     move their inventory out to a space spot (EMF has something?) and the chest despawns... there probably should be a
     backup option where if the user forgets to close it, it despawns within a specified time (but items cannot be lost
     when that despawn happens)". **Research (nothing built):** (1) spawned entities are NOT saved by the game (EMF
     re_villages.md; core/loot_chest.lua): a hidden chest as storage loses everything on a server restart -> the
     companion's items must live in FlameKit's own file (the roster). (2) emf.put/take/move = take + put: plain stacks
     exact; GEAR has a per-item data entity (pide: level, perks, durability, gem) that a take destroys: put back = same
     item, level and rarity (passable), [WRONG, see the owner 07:59 correction below:] perks re-rolled, the socketed gem
     gone (EMF guide.md/cookbook.md). The engine's
     moveStack (op 4, 0x14040da50) keeps the pide between two containers (re_take_items.md 4b) but EMF does not offer it
     and both containers must exist (no saved one to move into). (3) core/bag.lua reads every stack: item, count, gear,
     rarity, level, gem id (not the perks). (4) The chest: core/loot_chest.lua's Prop_Decoration_T5_Storage_40_Chest
     (40 slots), PUT_WAIT 0.5 s before the first put, a hit rule so it takes no damage. Questions asked: gear handling,
     the auto-close time, where the chest appears.
     **Owner 07:59, verbatim:** ""game destroys a gear piece's hidden data when it's taken out." I think you're wrong on
     this and you just forget we tested that. why do you say thats a problem?" -> right: tested 2026-11-15 (core/
     ground_loot.lua): a sword re-made with rarity 4 and level 10 came out legendary level 10, the same item (rarity =
     the number of the item's perks unlocked, so level + rarity give the same piece). EMF's "perks re-rolled" warning
     does not apply. The ONE thing that does not carry over: a gem socketed into a weapon (loot_drop keeps such pieces in
     the body). **Rule for Claude: check HANDOFF and the code comments for our own tests before quoting EMF docs.**
     Asked: a weapon with a socketed gem (store the gem as a separate item / refuse the piece), auto-close 10 min?,
     the chest beside the companion?
     **Owner 07:59:** "the EMF docs are frequently wrong, as we've learned" (our own tests beat the docs). **Owner 08:02,
     verbatim:** "1. how is the gem thing an issue? 2. maybe go with 5 minutes for now? 3. yes make it spawn next to the
     companion, maybe also make it so the companion can't move or do anything until the chest is closed? when the chest
     is open, make the "E" menu just say "close chest" so we can get rid of the whole inventory menu and just have one
     "Inventory" option on the main wheel. clicking that spawns the chest with items" (gem: EMF's put cannot socket a gem,
     so it is kept as a separate item next to the weapon). **Built 0.15.287 (Lua, live by reload; tested in a fake world:
     local_server/tests/fight/invtest.lua with the real core/bag.lua):** wheel {Follow me, Stay here, Attack, Inventory,
     Put away}; while his chest is open {Close Chest} only (an old wheel's other picks are ignored). `inv` table (the
     file is at Lua's 200 top-level locals): inv.open[name] = {chest, player, t0, state filling/open, queue, rest, rule};
     r.inv = [{item, count, level, rarity}] and r.chest = {id, session, state} in the roster (world data). Open: chest
     inv.CHEST (Prop_Decoration_T5_Storage_40_Chest) 1.5 m to his right, a hit rule (no damage), puts one by one
     (PUT_WAIT 0.5 s, RETRIES 3 on a fresh chest, what does not fit kept in c.rest/the record); r.inv untouched until
     every put answered; then every SAVE_EVERY 1 s r.inv = chest (bag.entity_stacks; a socketed gem as its own entry) +
     rest, saved when changed; only a chest that exists and has InventorySetup is read. Close / OPEN_MAX 5 min: final
     save, hit rule off, emf.destroy; a vanished chest closes keeping the last save. Script reload: inv.adopt takes an
     "open" chest of the same session up again, removes a "filling" one; another session: gone, r.inv = last save. Frozen:
     drive_step holds him (hold_at), no fight/heal/follow (inv.frozen; name_of is declared below drive_step: a first
     version read it there and the drive_harness caught the error). Notices "<name>: Inventory open." / "Inventory closed.".
     **Owner 08:11:** "what about despawning him when the chest is open? thats disabled too right?" (blocked: wheel Put
     away, every automatic put-away; not: P call, death, console commands; the chest and items untouched in all).
     **Owner 08:13, verbatim:** "can the that call my companion feature be disabled when the chest is open? if he gets
     killed does the chest despawn automatically too?" -> 0.15.288: on_call refuses while inv.open[r.name] ("<name>:
     Close the chest first."). Death: the chest stays (asked whether it should close itself when he dies).
     **Owner 08:15, verbatim:** "yes if the companion dies with the chest open, the chest needs to despawn" -> 0.15.289:
     F.tick's death check (dead_told) calls inv.close(world, r, "he died") (saves first). invtest.lua: closed, record kept.
     **Owner 08:17:** "so what stats specifically were you worried about not transferring back on items?" Listed: level and
     rarity tested (yes); socketed gem (no: kept separately); UNKNOWN: unlocked perks (PerkContainerNew {availablePerks,
     unlockedPerks}; rarity = availablePerks - 1, unlockedPerks may reset on a fresh copy), durability/broken, fuel,
     custom colour/name. **Owner 08:19, verbatim:** "we'll have to test the unlocked parts, I don't think we tested that
     yet" -> **TO TEST** (owner): a perked weapon through his chest (close, reopen, compare). 0.15.290 logging (live):
     inv.log_gear at "filled" and "closing": "inventory <name> gear (<when>): item, level, rarity, perks a/u unlocked,
     gem, base damage, item state" per gear piece.
     08:20:52 in game: a reload took his OPEN chest up again (inv.adopt) and it kept saving: reload safety confirmed live.
     **Owner 08:20, verbatim:** "I noticed the companion can still be pushed around while the chest is open, anyway to
     stop that?" -> 0.15.291: inv.pin (drive_step's frozen branch): the CurrentTransform position when frozen (c.pin, per
     body) is written back every tick he is moved, his Velocity zeroed; log "pushed while the chest is open: put back"
     once. Harness: a 2 m push undone the next tick.
     **Owner 08:22, verbatim:** "also I wanted the "E" button to just say "Close" chest. it doesn't have to bring up the
     whole wheel when the chest is open..." -> 0.15.292: on_talk while inv.open: inv.close at once (no wheel); his offer
     (inv.prompt, used by bring_to_life too) while open: verb inv.CLOSE_VERB 0x3959A87F, back to "Talk" on close. EMF's
     verb list (emf_api.h EMF_VERB_*) has no Close; own words need an EML content mod (a data patch on every game). The id
     = FNV-1a of Base_Door's InteractionToggle.onToOffVerb GUID da5990c2-f8f0-413c-bb4d-fe057f4b4ca1 (tplcomp.py, comp
     ad7e2be5); UNPROVEN: FNV-1a of its offToOnVerb (0af70198-...) = 0x4E82E309, not EMF_VERB_OPEN 0x0C2E4515, so the
     door's words may be other entries or the hash another; TEST: the prompt shows "E Close" or just "E". Language data:
     not in enshrouded.kfc's 60 biggest resources (the .dat files hold the rest).
     **In game 08:23-08:24 (the owner's round trip):** a weapon level 46, rarity 3, perks 4/0 unlocked, base damage 51
     went out and came back the same (08:23:14 closing, 08:24:22 closing). It had 0 unlocked, so the unlocked-perks
     question is still OPEN (needs a piece with unlocked > 0). BUG found there: at 08:24:10.555 (the filling's own tick)
     the fresh copy read level 0 / rarity 0 / damage 0, item state 64, and the snapshot SAVED that (correct again 0.5 s
     later): a crash in that window would have made it common. 0.15.293: after the filling c.ready_t = t + SAVE_EVERY;
     the first snapshot and the "filled" gear log wait for it; a close before it keeps the record from before the
     opening. The "Close" prompt (0.15.292) not seen yet: the chest was closed before that install.
     **0.15.294 (owner 08:32 "the companion doesn't have an E button at all now"):** inv.prompt took the old offer off
     and made the new one in the same step; EMF refuses that ("an earlier offer is still being taken off it: try again
     in a moment"), so he had no prompt at all. Now the new offer is made 2 ticks later and retried every 6 ticks (up
     to 50) until EMF takes it (inv.want / inv.want_tick from F.tick; log "prompt: E on <id> offered ... after N
     try(s)"). Seen 08:35:18 after the reload: offered at the 1st try (Close verb on 182193, Talk on 13020).
     **Idea (owner 08:33): "the chest that spawns, can it be "named" with the companions name?"** Not built. What we
     know: the game has its own floating name labels (component CustomPlayerString, 8 bytes, saved with the world;
     client programs ui_custom_name / ui_custom_name_visibility draw it with a line-of-sight check, from the
     CustomPlayerStringsSystem); never touched by us, how a string gets into that system is unknown (research). The
     chest's own E prompt words would need a content mod (a game update, not server only).
     Owner 08:41 "research the first point and see what it looks like?". Found: our own client notes already have it
     (flamekit_native/notes/memory_layouts.md, read_custom_names in flamekit_native.cpp, used by the minimap): the
     names players give flame altars and chests; CustomPlayerStringsSystem pool of 0x140-byte entries {key +0x10 =
     the entity's CustomPlayerString.stringId, text at +0x38, length +0x20}; the client only has the names of things
     near the player. Only program that sys-writes it: custom_player_string_init. 0.15.295: console command
     `flamekit.npc names` (list) / `names copy <from> <to>` / `names set <entity> <n>`. 08:43:53 on the local server:
     135 entities have the component, 125 with a key (keys look random 64-bit; those >= 2^63 read as floats in Lua and
     cannot be copied exactly). 2112, 11 m from the player, is a chest (Inventory, ToggleAnimation, UiOffsets) with key
     0x2E2B803BEE877B55 (copyable). Next test: copy 2112's key onto the companion's open chest and see if 2112's name
     floats over it; then making our own text needs a new entry in the server's string pool (C++).
     08:47: the companion's spawned chest (186765) has NO CustomPlayerString (player-placed chests do);
     emf.add_component (Lua 1.12) only takes ScaleComponent/InteractionPause, but emf.spawn's `components` takes any:
     0.15.296 `names spawn <from>` spawns a test chest (60 s) with {CustomPlayerString = {stringId = key}}. 08:48:49
     test chest 187029 with 2112's key: **owner 08:49 "it says "Private Stash" so the label test worked"**: the game's
     floating name shows on a chest the mod spawns, by key alone. Left: our own text ("N1") needs an entry in the
     server's CustomPlayerStringsSystem (layout only known on the client; it is saved with the world).
     **Owner 08:51: "when the chest spawns and opens I just want it to have the companions name on it.. you're just
     asking me too many questions for a simple task"** (fewer questions: build it). Static RE of enshrouded_server.exe
     (sha256 f0d824be7fcd48eb; objdump + numpy xref scripts in the device's $HOME/re, not kept): the key IS FNV-1a 64 of
     the text ("Private Stash" = 0x2E2B803BEE877B55, "N1" = 0x09207B07B5B5A6A0); setString 0x140915b80(out, sys, oldKey,
     {p, n}) = the CustomPlayerStringClientMessage handler's call (0x1407bde90): refcounted entries (+0x138), takes a ref
     on the new text, drops one on oldKey's; hash map sys+0x198 bits / +0x1a0 slots / +0x1b8 keys / +0x1d0 entries /
     +0x1e4 count; lookup 0x140953040 ALSO adds a ref (custom_player_string_init calls it per entity and ZEROES a key
     that is not in the map: the name must exist before the chest spawns). 0.15.297: Lua writes roster names to
     mods\flamekit\custom_names.txt and spawns the chest with {CustomPlayerString = {stringId = FNV-1a 64(name)}}
     (logs "name label key on the chest ..." at the filling: 0 = the server did not know the name); the server probe
     (on_tick, server world, every 30 ticks when the file changes) calls setString(oldKey 0) once per name per run
     (our ref, never dropped), logs "names: 'N1' registered ...". DLL md5 27d76044 copied in at 09:03 (03a0df63 renamed
     .old_0903): loads at the next server start (not restarted yet).
     **Upgrades (owner 08:57 "upgraded items don't appear to be preserved :( it definitely stripped the upgrades off
     it...... if there anything you can do to put them back on it?"):** 08:56:41 out "perks 4/1", 08:56:47 back "4/0":
     emf.put does not keep PerkContainerNew.unlockedPerks (the unlocked-perks question is answered: NOT kept).
     0.15.298: inv.gear_list reads it, his record keeps `unlocked`, the put records a fix, inv.apply_unlocked writes it
     on the new piece at ready_t (before the first snapshot). 0.15.299: `flamekit.npc unlock <companion> <item> <n>`;
     09:02:16 N1's record item 3412482507 level 47 set to 1 unlocked (the owner's weapon). NOT yet seen in game.
     **Server restart 09:05 (owner 09:05 "yeah bounce it"):** probe DLL 27d76044 loaded; 09:05:40 'N1'/'N2' registered
     BEFORE the world loaded (table count 1, 2) and they survived the load: 09:11:57 chest 28184 kept key
     0x09207B07B5B5A6A0 (not zeroed); 09:11:58 "upgrades put back on item 3412482507 (level 47): unlocked 0 -> 1",
     gear log 4/1; the owner took the weapon out at 09:12:03. **Owner 09:14 "seems to all work".**
     **Owner 09:14: "I've decided to take the despawn time limit off the chest completely since the companion can't move
     so it should be safe just to leave it there."** 0.15.300: inv.OPEN_MAX and the auto-close removed (rule 0n);
     invtest checks it is still open after 5 minutes. Safety (his question "items will be safe on a server restart or
     crash right?"): his record is written to emf\config\flamekit\<slot>.txt within 1 s of any change (the world data
     file, written at once), the chest itself is never saved by the game, a new run starts with the record; the gap:
     the PLAYER's inventory is only saved with the world (every 30 s), so a crash right after moving items can lose (took
     out) or double (put in) what moved since the last world save; a restart through the helper saves first.
     **Owner 09:17 "if I open my companions chest and log off and come back. is everything in the same spot.. orrrr
     now does that work?"** From the code: the server keeps the chest (only a server restart loses it); his drive stops
     when the player is gone (drive_read: player position nil), the game AI stays off so he stands; roster_joined drives
     him again and inv.frozen pins him back to c.pin; E still closes it. 0.15.301: inv.close(world, r, why, by): the
     closed notice goes to the player who pressed E (c.player is an old entity id after a rejoin). Not tested in game.
     **Owner 09:19 "so while im offline someone can move him around?" / 09:21 "yeah it needs to be pinned for all players
     so if I log off no one can mess with it.. is there a way to make a check so ONLY the player who owns the companion
     can open the chest?"** 0.15.302: inv.tick pins ent_of[name] every tick (drive_step's frozen branch no longer pins);
     EMF has no per-player interaction lock (InteractionLock is template: required item / requiredPermission), so
     emf.on_event("InteractionAcceptedEvent") (guestEntityId = player, hostEntityId = chest): a guest whose account is
     not r.owner closes the chest at once (inv.close "someone else opened it", record saved) and gets a notice; the
     owner is not affected; r.owner nil = anyone. invtest covers both. Not tested in game (needs a second player).
     Owner 09:24 "still works" (his own opening). 0.15.303: log "chest X opened by its owner" (proof the event fires).
     **Owner 09:25 "anyway to make this chest a gigantic chest instead of this small one?"** 0.15.304: inv.CHEST =
     Prop_Decoration_T6_Storage_72_Magic bc834cbd-58f1-494a-97fb-0dc0248eb738 (72 slots, the biggest storage template;
     others: T4_Storage_56 fae7a62e..., T3_Storage_40 bdebd6a9...). Not seen in game yet. A bigger LOOK would be
     ScaleComponent in emf.spawn's components (untested on a prop).
     Owner 09:27 "I meant bigger slots so you got it right". **Owner 09:28 "can you make the chest not spawn right on the
     player? it spawned it right where I was standing which was super werid"** (09:27:21 chest 31493; the 72-slot chest
     is bigger, 1.5 m to his right reached the player). 0.15.305: inv.SPOT 2.5 m from him on the far side from the player
     (his right only when the player stands on him); the opened log gives the distance from the player. NOTE: no "opened
     by its owner" line at 09:27 (he closed it via E at 09:27:34; maybe never opened it): the event is still unproven.
     Owner 09:29 "2.5 away from him seems a bit too far don't you think? 1m should be fine": 0.15.306 inv.SPOT = 1.
     Owner 09:31 "make the chest just spawn to the left of him by 1.5 m, sorry its a process to test it out right":
     0.15.307 1.5 m to his left by his facing (the far-side-from-the-player rule removed).
     Owner 09:31 "left of the way he is facing.. so if he is facing forward, its on his left side" (= what was built; the
     left/right sign is UNPROVEN in game: if it lands on his right, flip it). Owner 09:33/09:34: frozen = follow,
     attack, heal off (confirmed from drive_step: the frozen branch returns before all of it); items belong to the
     world's data file, not the character. **Owner 09:35 "yes delete should refuse it"** (after I found: roster delete
     dropped r.inv, and an open chest stayed behind ownerless): 0.15.308 delete refuses while inv.open[name] or
     inv.count(r.inv) > 0; `away` closes an open chest first (without his body nothing could close it). invtest covers it.
     Owner 09:38 opened chest 32632: NO "opened by its owner" line: EMF says on every reload since 09:22 "on_event
     (InteractionAcceptedEvent) is new since the game started: restart the game to receive it" (an event asked for
     after the server started needs a server restart; I missed the log line). The owner-only rule is NOT live until the
     next server restart (asked 09:39, not answered yet). **Owner 09:40/09:41 on running commands: chat commands need
     [chat] admins in the server's emf\emf_core.ini (the local server has none); "nah its probably best no one can use
     the commands like that"**: no emf_core.ini, commands only through emf\commands.txt (me) / the server log.
2. Companions in the party list.
9. **Companion roster tab (owner 2026-11-20 09:43-09:45):** "the companion roster management probably best done with a new
   window on the client side mod right?" / "why can't I just make it part of the FlameKit ui like all the other windows?"
   / "yeah because were not using EMF ui to draw anything..." (rule 12: I wrongly mentioned EMF windows). Plan: a
   "Companions" tab in FlameKit's window (F6), built like the Server tab (server sends the list on a channel, rows and
   buttons, clicks go back and the server checks may_command/admin): every companion with owner (name), mode, out/away,
   items, chest open; give/share/unshare/main/away/back/delete; players picked by name (names remembered per account at
   join, for offline players). A game-side change: Development build. Not started.
10. **Pets (owner 2026-11-20 09:47-09:49, idea only, nothing to build yet):** "can the template guid be like an "animal"
   in the game or it must be a monster?" / "wouldn't steering it be 100% the same?" / "i'm thinking anything that an
   "animal" we'd call "pets" and they'd work and function differently from a full on companion". Facts found:
   templates.csv: 102 animal/tame templates, peaceful ones (dogs AG2, cats, goats, yak, capybara, bunnies, birds, fish)
   have NO monster AI (no DynamicEnemy01BehaviorState); animal_behavior writes ActorInput/DynamicLocomotion/PathWalker
   and they run steering_locomotion like the hound, so the probe's ActorInput write after steering_locomotion should
   steer them the same; different: their brain-off switch (unknown), the Lua -> C++ target hand-over (now through
   DynamicEnemy01BehaviorState fields, also drive_scan's filter), no attack moves. Untested in game.
   **Owner 09:51: "yes pets are a weaker companion, they don't die, but they don't fight, maybe they can heal and hold
   small inventory".** So far: no death, no fighting; maybe heals and a small inventory (smaller chest). Not built.
   **Owner 09:52: "ok lets make sure we can resuse all that code. before we add pets, I want to finish building out the
   roster management system"**: order = roster management (item 9) first, pets after, and the companion code (healing,
   chest, follow) kept reusable for pets. Waiting for the owner's spec of the roster tab.
   **Owner 10:00 (the spec):** ""Companion Roster" needs to be its own complete window. for now you can just add a
   button under the "Experimental" tab in the settings window next to the "Call my companion" button. I'll let you
   implement as you described and will see if that's good enough or if it needs to be reworked. I'll want to be able to
   change any players "main" companion to any of the available monster templates that are not bosses. The companion
   system has to be able to handle small tweaks to how they function between the templates.. for instance the how the
   dog is position in water will NOT work for a humanoid template... We don't need and "admin" checks or restrictions
   at this time, but probably in the future, we'll be adding a lot of admin restrictions throughout the mod, but that is
   another task for another day". So: its own window (opened by a button next to "Call my companion" in the
   Experimental tab), the list + actions as sketched 09:52, change a player's main companion's template to any non-boss
   monster template, per-template behaviour tweaks (water position etc.), NO admin checks for now.
   **Owner 10:01: "I should be able to name the companion as well".** Plan asked 10:0x (window, rows, Rename text box,
   Kind drop-down of non-boss monsters, Give/Share/Unshare by player name, Set main, Put away/Bring back, Delete,
   per-kind profiles; Development build + server restart): **owner: "sounds good, not sure what "(2) one row per
   companion: name, owner, kind (template)," is actually going to look like on the screen...but go ahead and make it"**.
   Untuned kinds: **"I would go with #2.. once the roster system is done we'll test and develop some "tuned" behaviors
   that work with the humanoid templates and see how it goes...."** = an untuned kind plays its own attack moves looked
   up in the game data (its first melee attack), may look wrong until tuned.
   **0.15.309 (Development + local server, 10:14; DLL c810aefb built 10:12):** server npc_probe.lua: channel
   flamekit/roster (max 16384): {op=get} -> {op=roster, list={n,k guid,o owner,m,f,out,it items,ch chest,main,c
   controllers}, players={a,n,on}}; {op=do, what=rename|kind|give|share|unshare|main|away|back|delete, name, arg} ->
   {op=result,text,ok} + a push to every viewer (10 min after their last ask; F.tick every 60 ticks pushes changes);
   roster.known (account -> name, saved in the roster) for offline players; rename re-keys ent_of/returning/mana_of/
   waiting/name_of/roster.main (refused with the chest open; 1-20 of letters digits space - _ ' .); kind = any
   non-boss core/monsters.lua entry, replaces an out body at its spot (r.sus_base reset); the rest reuses roster_cmd
   (emf.reply captured). All in the `roster` table (Lua local limit). Client npc_wheel_probe.lua: "Companion Roster"
   button same line as Call (writes ui_roster_toggle.request + asks), F.roster_rows / F.roster_click (two-click
   Delete); native_ui.lua: ui_roster.dat + "ros" clicks (text box: gen/num/hex). DLL: ExperimentalLayer has a second
   constructor (id companion_roster, ui_roster.dat, verb ros, toggled by the request file, hidden at first, centred,
   above FlameKit's window in the layer order) and row kind e (text box: click = keyboard to the overlay, WM_CHAR typed,
   Enter sends, Esc/click elsewhere drops); Layer::chr + WM_CHAR in the overlay's window proc. Tests: invtest (server
   actions), a client rows check, run.lua ALL PASSED. Needs a server restart (new channel + the open event) and a game
   restart (update ready 10:14:38). Per-kind profiles / attacks (task 2 of the plan): NOT built yet.
   Restart both 10:31 (owner "yes"): 0.15.309 runs on both. **Owner 10:47 "okay I see the screen... but.. how do I add
   a new entry?"** / 10:48 "theres no buttons at the top" / 11:12 "sure, but there's a new hitch in the design.....
   some players wants pet as their main companions too.. so with that complicate how the companion roster works?"
   0.15.310 (Development 11:15, DLL edfa2ee4; server reloaded 11:13): "New companion" button at the top (op do what=new
   -> roster_cmd new <asking player>: a hound of his, next to him, following); fix: label rows need {label = true,
   text = ...} (they were blank). Pets as mains: proposed a type per roster entry (companion/pet), Kind list by type,
   New companion / New pet, main stays one per player; ASKED: one main total or one main companion + one main pet.
   **Owner 11:16: "no just one main one, but it can be a pet or a companion, but pets will still have limited
   capabilities"** = one main per player, a companion OR a pet; pets keep their limited set (no death, no fighting,
   maybe heals, small inventory).
   **Owner 11:20: "could the pets just have their own "Pets" section in the drop-down list with the other companions
   to keep the UI cleaner?"** -> yes: no separate type field or New pet button; the Kind drop-down gets a "Pets" group
   (the peaceful animals); picking one makes him a pet (his type follows from his kind). Built with the pets.
   **Owner 11:26: "can you make "Bring back" spawn the companion next to the player? I just put N2 away and brought
   back and its not near me"** (N2 is a stayer: it came back at its spot). 0.15.311: roster.ui_back: next to the
   clicking player, 0.3 m right, his facing (as Call); follower follows the clicker, a stayer's spot becomes there.
   **Owner 11:31: "I restarted the client and something is broke.. "Companion Roster" is stuck saying "asking the server
   for the roster""**: the window was still shown from before the restart and "get" was only sent by the button.
   0.15.312: roster_rows asks when there is no list (every 5 s) and again every 9 minutes.
   **Owner 11:40: "can you add the Pets section and add all the available pets into?"** 0.15.313: core/pets.lua (26:
   Animal_Wildlife_* dogs/cats/goat/mountain goat/bunny x2/cat-deer/turkey/desert bird/yak/capybara + Animal_Baby_*;
   no fish, flying birds, tests, deprecated), "Pets" first in the Kind drop-down; server ui_kind accepts them (reply
   says pets do not follow yet); still_ours accepts a companion-faction body with DynamicAnimal (no monster AI) so a
   reload does not spawn a second animal. A pet body runs its own animal AI: drive_read errors once per body (logged).
   Owner 11:53 "why did you leave out flying birds?" (my own call, unasked) / 11:55 "yes add them.. everything is
   untested so we won't know until we figure it out --- the cats and dogs, do you label what each type is or...?":
   0.15.314 adds Animal_Wildlife_Flying_Bird 0eaf60f1-... as "Bird (flying)" (the only flying one). Fish still out.
   Cats/dogs are labelled by the colour in their template names (Dog bright/dotted/dark/black/white, Cat
   black/striped/bright).
   **Owner 12:12: "N1's chest spawned in the air... can you make that stay on the ground..?" / "it spawned too close
   to the other chest I guess"** (12:11 chest 65256 at y 1019.6 = N1's height; N2 at 1018.6, so N1 likely stood on
   another chest). Also seen: 12:11:22 "chest 65256 opened by its owner": the InteractionAcceptedEvent check works.
   0.15.315 (server only): inv.open_chest writes chest_ground.request ("<name>#<i> x y z", 4 places: left, right,
   behind, front at inv.SPOT), the server probe's ground program (do_chest_ground, the game ray from y+1.5 to y-8,
   mask 0x9) answers chest_ground.answer; inv.ground_tick picks the first place with ground in feet-1.2..feet+0.4,
   else the lowest within feet-3..feet+1, else (no answer in 1 s / none) his left at his height; inv.open_at spawns.
   Logged "chest place N of 4 (...)" and "chest ground: ..." (C++).
   **Owner 12:14: "would it be easiler for all companions of a player should just share one inventory? I dont think
   each companion needs to have its own chest?" / "not sure"**: my opinion (one inventory per player: items belong
   to the player, fits one main, no stranded items, pets a smaller chest) -> **owner 12:16 "hold off on #2 for now"**
   (kept on the list, not built). Owner 12:16 "yeah it was standing on the chest" (the cause). Server probe DLL
   35370f20 copied in 12:15 (27d76044 renamed .old_1215): loaded at the server restart 12:18 (owner "sure").
   **Owner 12:22: "N2 didn't spawn with me and it was set to follow when I logged off"**: it had (12:22:17 at the
   join), at N1's exact spot, and both followed to the same point (12:22:55 both at 6358.2 986.5 5378.2). 0.15.316:
   spawn_body moves a spawn 1.2 m along x per other companion within 1 m; drive_steer: with several followers of one
   player, going to the player (no crumb), the 2nd.. (by entity id) aim at SLOTS around him (right/forward metres of
   his facing: -1.6/-0.8, 1.6/-0.8, 0/-2.2, -2.4/-2.2, 2.4/-2.2). While walking the trail they still share the crumbs.
   Owner 12:23 "yeah we can't have that". 12:24:36 after the reload both still at 6360.4 986.0 5376.7: the C++ stops
   him within kFollowStop 2 m of homeZonePosition (the player), not of his target. 0.15.317: a slotted follower's
   homeZonePosition = his slot point + 1.5 m on his way there (stops ~0.5 m from his place).
   12:26 still together: a reload starts each trail with a crumb at the player's feet, so c was never nil near him.
   0.15.318: the slot also applies within SLOT_NEAR 4 m of the player, crumb or not.
   0.15.319: log "slot <id>: follower k of n ..."; 12:28:12 N1's place was 0.4 m from where both stood (the player's
   facing put left-behind right there). 0.15.320: the place = the first of SLOTS (starting at his own) at least
   SLOT_GAP 1.5 m from every follower before him (their current positions), kept while free (h.slot_i).
   12:29:50 apart (N2 next to the player, N1 ~3 m away). **Owner 12:35 "yeah thats good, ideally you'd have different
   ones" / 12:36 "first one. we dont need different paths"** = ideally a player's companions are different kinds (set
   with Kind); no separate follow paths wanted.
   **Owner 12:37: "when I teleported I only see N1 again"**: 12:37:14 both returning entries called on_call (the
   player's MAIN companion): N1 spawned twice (34173, 34174), N2 never. 0.15.321: the return calls roster.ui_back for
   that companion (beside the player, 0.3 m right; spawn_body keeps them 1.2 m apart); the "Companion has spawned near
   you!" notice only for the main one. Cleanup: the extra N1 body removed, N2 brought back by console.
   (Correction: the extra N1 body was already gone: on_call destroys the old one; N2 brought back 12:38:59 by console.)
   **Pets (owner 12:43):** "next I'd like to try getting pets working as those should be pretty easy. it might make
   sense to have "arch types" for behavior so dog like templates all share the same stuff. humanoids, flying stuff,
   etc... not sure how practical that is tho as each one has different animations? pets should be mostly the same";
   12:48 "n2 is a dog now" (N2 = 36028, Dog (bright)); **12:49 "yeah dont use anything for the built in AI, it should
   just use what we made already"**. 0.15.322: `flamekit.npc petlog <entity> [s]`. 12:49:31-51 petlog of the dog: its
   AI is program "wildlife" (DynamicWildlife: state 3 idle, 6 walking to a roaming target currentTargetPosition via the
   DynamicPathWalker, which writes ActorInput move ~0.3 at speed 2). The dog has Animal + Wildlife + FleeSensor, no
   DynamicEnemy01BehaviorState. 0.15.323: Lua drive_read uses a shim table (h.shim, same fields as the monster AI's)
   for a pet; roster.pet_flush writes AnimalSaved.spawnPosition = target, DynamicWildlife.spawnPosition = player spot,
   DynamicWildlife.runAwayDistance = pace + 10 edge off + 20 drops ok (0 = not driven); roster.pets_quiet keeps
   wildlife state 3, its roaming target at the pet, the path walker off; pets skip drive_fight / drive_heal; an
   emf.hit_rule cancel makes pet bodies take no damage. C++ drive_scan takes faction-11 DynamicWildlife bodies with
   runAwayDistance >= 1.5; drive_post reads those carriers (same steering, edge stop, pace; no fight_step). Untested.
   Restart 12:54 (owner "sure"); **owner 13:02 "the dog jerks around a lot but does follow me" / 13:05 "its very
   erratic"**: petlog 13:04:45-49: 20 m jumps every half second (1767 -> 1779 -> 1757 -> 1774) = the game moves the
   animal by AnimalSaved/DynamicWildlife spawn positions (my carriers). Also: the wildlife program keeps state 6 and
   zeroes currentTargetPosition whatever we write. 0.15.324: carriers gone; Lua writes pet_drive.txt beside the mod
   ("<id> <target xyz> <player xyz> <code>", only when it changes, tmp + rename); the probe's read_pets reloads it on a
   new write time; drive_scan/drive_post take pets from it. pets_quiet only: wildlife state 3 + path walker off.
   **E prompt on pets (owner 12:54 "I noticed this pet doesn't have an 'E' button, will that change?"):** emf.offer is
   refused ("it has its own offer from the game"); ideas: spawn the pet tame so the game's "E Pet" shows and open our
   wheel on its InteractionAcceptedEvent. Not built.
   Restart 13:07 (owner "yes"); **owner 13:22 "it still glitches out a bit"**: petlog 13:23:25-60 (wildlife state 13):
   10-33 m in 0.5 s whenever the drive gave speed 4 (sprint), normal at 2/3; jumplog "takes off ... lands 33.6 m
   forward". Animal locomotion has no sprint. 0.15.325: C++ caps pets at speed 3 (run).
   Restart 13:26 (owner "yep"). **Owner 13:48 "he seems good, does he jump"**: yes, drive_jump_follow copies the
   player's jumps for pets too (13:48:37-41: 4 copies, down 0.6-0.8 m from the crumb). **Owner 13:56 "I saw one"**:
   likely the flat-ground copies are low hops (5.9 m/s up) with no jump animation on an animal (it is lifted by speed;
   the hound plays Enemy_Jump_Move). Open: look for a dog jump-like move in the game data if wanted.
   **Owner 13:57 "yeah do the E menu next"** (pets' E). 0.15.326: spawn_body spawns a pet (core/pets guid) with
   {IsTame = {}} (fallback: wild); inv.prompt skips pets; F.setup's InteractionAcceptedEvent handler: host = one of
   ours without monster AI -> on_talk(world, guest, host) (his wheel). Untested: whether the game shows "E Pet" on a
   tame spawn and fires the event.
   **WORKS (owner 14:07):** "the e press does the pet and brings up the wheel" (log 14:07:17: pet N2 80367, game's E
   -> wheel sent). The game's pet animation plays too.
   **Owner 14:07 "it let me pick up the pet to..." / 14:08 "it doesnt let me put it down either "needs building
   area""**: the game's tame pick-up removed N2's body (14:07:42 "drive 80367: gone, stopped"; the roster still had him
   out). **Owner 14:09 decision: "yeah we need to remove the pick up and pet option, the pet option could be put in
   the wheel"** = our pets get no game pick-up and no game "Pet" option; petting moves into his wheel. In progress.
   Docs: program interaction_animal_tame_default (tpl Animal, needs IsTame) and interaction_taming (Wildlife, no IsTame)
   write InteractionOfferRuntime (fields defaultSequence, overrideSequence, defaultVerbId, overrideVerbLocaId, offerId,
   isOffered, isDisabled); animal_upgrade_interaction (a player program: SelectedTargets, other-read IsTame) may be the
   pick-up. 14:07:42 pick-up came with no InteractionAcceptedEvent. 0.15.327: petlog also logs the offer runtime.
   petlog 14:11:55 (N2 87125, tame): default seq 0 verb 0, override seq 0xB1EB4A70 verb 0x6D5B6297 (= EMF_VERB_PET),
   offerId 1, offered. 0.15.328: roster.pet_offer (from pets_quiet, every tick) writes override seq EMF_SEQUENCE_TOUCH
   0x3E5189BF + verb EMF_VERB_TALK 0xD9861C4B; logs the first fix and every 100th (shows whether the game rewrites it).
   Untested: whether the pick-up goes with the sequence. Next (owner's idea): "Pet" in his wheel.
   Log 14:13: the game writes its Pet offer back every tick (our fix counted 60 a second). **Owner 14:19: "the 'E' pet
   option just opens the wheel"** (the word still reads Pet; our touch sequence wins at E). Pick-up: not checked yet.
   **Found 14:11-14:19 (not from 0.15.328):** standing still, N2 (tame) stops 2.0 m from the player and his crumb;
   "can't follow: blocked: no progress toward his crumb (2.0 m away)" puts him away and back every 10-20 s.
   **Owner 14:20: "the 'pick up' option is still there"** = the pick-up is not in the offer (it needs IsTame: likely
   the player program animal_upgrade_interaction). 0.15.329: pets spawned wild again (the IsTame spawn removed);
   roster.pet_offer also forces isOffered true / isDisabled false on the wild animal's taming offer. Untested.
   Log 14:21: wild offer every step seq 0 verb 0 offered false (game rewrites). **Owner 14:22: "pick up is gone, but
   so is the E menu"**. 0.15.330: Lua pet_offer removed; server probe hooks program interaction_offer (it copies the
   runtime offer into ClientInteractionOffer): pre = each g_pets id's runtime offer set to touch seq 0x3E5189BF + verb
   Talk 0xD9861C4B, isOffered 1, isDisabled 0; post = logs runtime + client copy every 10 s ("pet offer ..."). Needs the
   probe DLL (server restart).
   Probe DLL 0dd8a1f0 installed (old 781c4e64 kept as .old_1425); restart 14:25 (owner "yes"); "pets: hook on
   interaction_offer installed". Log 14:28: N2 22654 runtime override 3e5189bf/d9861c4b offered 1, client verb
   d9861c4b offered 1. **Owner 14:28: "I see just the 'Talk' option"** (no Pet, no Pick up). E -> wheel: not yet pressed.
   **Owner 14:32: "no wheel, do I need to respawn him?"**: no InteractionAcceptedEvent in the log at all (14:30-14:32)
   = the press is checked (interaction_attempt) after the game put its own offer back. 0.15.331: the same set also
   after interaction_taming and before interaction_attempt; "pet offer ... before interaction_attempt: the game's
   again" logged (every 10 s at most) when it had been reset. Needs the probe DLL (restart). Respawn not needed.
   DLL 6dbd7f92 (old .old_1433); restart 14:34 (owner "yes"). **Owner 14:37 "I pressed E"**: still no event; log every
   10 s "before interaction_attempt: the game's again (seq 0 verb 0 offered 1)" = the override is cleared between
   interaction_offer and the press check (likely program interaction_override_reset), and the wild default is 0.
   0.15.332: defaultSequence / defaultVerbId set to touch / Talk as well (all three hooks).
   DLL 11c28b80 (old .old_1440); restart 14:39 (owner "yes"). **Owner 14:42 "still nothing"**: default now stays ours
   (log: seq 3e5189bf/0 before the press check), still no InteractionAcceptedEvent. 0.15.333: petlog logs the animal's
   InteractionLock / InteractionKnowledgeLock / InteractionOffer / ClientInteractionOffer / InteractionPause.
   petlog 14:43 (N2 22667): no locks, no InteractionOffer component, runtime ours but **offerId 0** (the tame one at
   14:11 had offerId 1, and its E worked). 0.15.334: the probe also sets offerId 1 when it is 0.
   DLL 16767076 (old .old_1445); restart 14:44 (owner "yes"). **WORKS: owner 14:46 "I get a wheel this time"** (log
   14:46:28 / 14:46:38: E on N2 22666 -> wheel sent). Pets: only "Talk", no Pet, no Pick up; E opens his wheel.
   Open: "Pet" as a wheel entry (owner's 14:09 idea); the 10 s probe log lines can be thinned later.
   **Owner 14:47: "looks like everything seems to be working like it was"** (the rest of the pet still works).
   **Owner 14:49: "yes and the wheel for pets would need to be different than the wheel for the monster companions I
   think. I also noticed it wasn't labeling the inventory chest with the pets name on it"** = yes to "Pet" in the wheel;
   pets get their own wheel (wording being confirmed). Chest label: log 14:47:04 N2's chest key 0x0 (his name
   0x09207E07B5B5ABB9 registered 14:44:57 "now there"); N1's chest at 14:47:11 had its key. Not pet-specific so far.
   The game offers no call to play its petting animation; idea: wheel "Pet" switches his E to the game's pet sequence
   0xB1EB4A70 / verb Pet for a few seconds (that E plays the animation), then back to Talk.
   **Owner 14:58 "awww no way to call it directly?" / 14:59 "lets try it"** (the server sends the accept itself; falls
   back to the press-E plan if the animation does not play). 0.15.335: PET_WHEEL {Follow me, Stay here, Pet, Inventory,
   Put away} for DynamicWildlife bodies without monster AI; roster.do_pet sets roster.pet_mode[npc] -> pet_drive.txt
   9th field 1 -> the probe's pet_offers writes seq 0xB1EB4A70 / verb Pet; after PET_SEND 6 ticks Lua emf.emit
   AcceptOfferedInteractionEvent {guest = player, host = pet, offerId 1} (emf.emits in F.setup: needs a restart);
   InteractionAcceptedEvent while pet_mode: logged "petting accepted", no wheel; after PET_HOLD 240 ticks back to Talk.
   Chest name: Lua logs the key right after the chest spawn; the probe logs when a registered name leaves the
   server's table ("names: 'N2' ... is NO LONGER in the server's table").
   DLL 010b78f7 (old .old_1503); restart 15:02 (owner "yes"). Log 15:05-15:06: the server-sent accept was never
   accepted (the 2 accepted ones, offer 4 and 7, came ~2 s later = his own E). **Owner 15:06: "when I press the 'Pet'
   option from the wheel, it lets me press E again for the pet"**. 0.15.336 (the press-E plan): the emit removed;
   Pet says "Press E to pet <name>"; back to Talk PET_AFTER 30 ticks after that accept, or PET_HOLD 600 without it.
   Offered (15:08 "anyway for the 'Pet' action on the wheel to make the petting happen?"): the client mod presses E
   itself after Pet (native SendInput; facing him, E only). **Owner 15:10: "its probably fine how it is now I think, at
   least the player can still do it"** = not built; Pet stays as in 0.15.336 (idea kept on the list).
   Chest name: 15:10:46 N2's chest had his key right after the spawn and at the filling; **owner 15:11 "that looks
   good"**. WATCH: the 14:47 miss (key 0) is unexplained; the probe's "NO LONGER in the server's table" log stays on.
   **Owner 15:11 "do pets have there own mana?"**: no (drive_heal skipped for pets; the dog body has no Mana).
   **Owner 15:16 "is 200 per heal normal ? that seems high honestly" / 15:17 "yeah I would"** (100): 0.15.337 HEAL_COST
   100 (was 200; MANA_MAX 800, refill 10/s unchanged).
   **Owner 15:22: "lets give the pets the same heal ability, same sparkle and that mode is just always active"**.
   0.15.338: drive_heal runs for pets too, mode always Healing (heals the player within FIGHT_RANGE up to full, 25 %
   for HEAL_COST 100 mana, HEAL_GAP 4 s, sparkle HEAL_FX 1 on both, green notice); for pets no fight_init wait, no
   Wolf Shout (selectedAttackIndex untouched), no self heal, own health not required. Log "heal N2: ... (Healing
   mode, pet)".
   **Owner 15:27 "looks like it works"** (15:27:08 heal N2: the player +635, mana 333 -> 233). Owner 15:27 asked about
   following / stuck / respawns: same drive and safety nets; pets: run at most (fall behind on long sprints), water
   untested for animals, no "can't follow" since 15:02 (the 14:11-14:19 loop was with the tame spawn). **Owner 15:33
   "seems good"** (log: jump follow copies, step-ups 3.5 m, no can't-follow).
   **Owner 15:35: "the pet dog swims but doesn't really follow me all the way down into the water"**: 15:34:19-42
   "dives with the player", the dog ~2.3 m deep (y 944.3) while the player was 4-5.5 m (y 941.1): the game lifts an
   animal more than the 0.08 m a tick drive_water moves him. **Owner 15:36: "yep as long it as that change is only valid
   for pets"**. 0.15.339: in drive_water, for s.pet only: fix = half the difference, at most PET_DIVE_STEP 0.4 m a tick;
   log "dive <id> (pet): ..." every second while diving. Monsters unchanged (0.25, at most 0.08).
   **Owner 15:38: "yep looks good"** (pets dive with the player).
   **Owner 15:38 "so here comes the last part" / 15:39: "in the wheel menu, id like a new section called "Companions"
   this option would apply to both Pets and the Monster Companions"** (what it holds: being asked).
   **Owner 15:39: "this wheel should should all the assigned pets and companions to that user and let them spawn them
   to them"**; restated (every companion/pet he controls, name + kind; a pick spawns it beside him following; one out
   is put away first; main unchanged), **owner "yup"**. 0.15.340: "Companions" last in WHEEL_LABELS and PET_WHEEL;
   roster.wheel_list sends a second wheel (title Companions, labels "N1 (Hound) - out"), roster.cw[player] maps
   labels to names (an hour); on_pick checks it first -> roster.wheel_summon (controls() check, roster away if out,
   mode follow, roster.ui_back, green notice, roster window pushed).
   **Owner 15:44: "I'm getting the Companion can't follow you error, but it hasn't respawned to me"**: 15:43:38 pet
   82256 swimming at a bank (player 2 m higher, 12-15 m away; climb-out hops every 2 s fail): "can't follow (water)"
   but drive_step returns after drive_water, so drive_put_away's TP_AFTER rule never ran in the water (old, every
   companion). 0.15.341: the same rule after drive_water (h.go_away = "can't follow"; log "can't follow: <id> in the
   water: put away").
   **Owner 15:52 "I noticed the give to list box is grayed out, is that because theres no players on the server"**: yes
   (roster.known has only Midevil; Give lists known players minus the owner).
   **Owner 15:55: "I'm noticing with multiple companions open they're seem to all be fighting to get to me and I'm
   getting lots of "Companion can't follow you!" messages"**: 15:54-15:55 N3 (follower 3 of 3, place 4) stood 0.4 m
   from his place, 2.8 m from the player: drive_stuck saw no progress toward the crumb at the player's feet -> can't
   follow -> respawn, every 8 s (18 times since 15:40; likely also the 14:11-14:19 loop). 0.15.342: drive_steer keeps
   h.slot_at {x, z, t}; drive_stuck counts a follower within SLOT_AT 1.5 m of his place (slot set in the last 30
   ticks) as progress.
   **Owner 15:59: "anyway to space out the pets a little bit more from each other, when they run or I stop they all
   just bunch right up on me"**; offered (places x1.5, 2.5 m apart; a 2.5 m queue on the trail); **owner 16:00 "pets
   and companion monsters too"**. 0.15.343: SLOTS x1.5, SLOT_GAP 2.5, SLOT_NEAR 6 (was 4); drive_steer, on the trail
   beyond SLOT_NEAR: a follower holds (hold_at, h.gap_t) while another of the player's followers is within TRAIL_GAP
   2.5 m and closer to the player (log "gap <id>: waits for ..." / "goes on"); drive_stuck counts that wait as progress.
   16:02:22-23: "waits" / "goes on" several times a second at the border. 0.15.344: a waiting one goes on past
   TRAIL_GAP_GO 3.5 m.
   **Owner 16:03 "yep looks good, I noticed I set a baby bunny and I dont see it"**: N5 = Baby bunny (91110) has no
   DynamicWildlife (petlog: tame true from its template, the game's Pet offer, animal state 4), so not a pet to the
   drive: left at 6298 948 5199 by the 16:02:40 fast travel. Babies: tame from birth (pick-up), no wildlife AI, grow up.
   **Owner 16:08: "yeah that the babies out... also the spacing changes made it hard for me to go up to one of the
   pets, the run around a lot when I try to move, making it hard for me to get to them. maybe theres a small radius we
   can add so as long as they're in that radius around me, they don't move around so much?"** 0.15.345: core/pets.lua
   without the 9 babies (kept as comments; client list too: Development release); ui_kind's "Pets do not follow yet"
   text removed; drive_steer: settle (SETTLE_R 6, SETTLE_ARRIVE 2.7): once arrived (the first within 2.7 m of the
   player, the others within SLOT_AT of their place) h.settled: hold_at where he stands while the player is within
   6 m ("settle <id>: arrived ..." / "follows again"); drive_stuck counts h.settle_t as progress. Applies to every
   companion (owner 16:00 "pets and companion monsters too" for the spacing). N5 needs another kind (roster window).
   0.15.345 server part installed 16:09:54 (settle lines logged at once). **Owner 16:10: "I also noticed, when their
   inventory crate is open, the pet still says "E" Talk instead of "E" Close"**. 0.15.346: pet_drive.txt 9th field
   2 while his chest is open; the probe's pet_offers: mode 2 = touch sequence + verb 0x3959A87F (inv.CLOSE_VERB).
   Needs the probe DLL (restart). Client Development release for core/pets.lua (no babies in the Kind list).
   Development release 0.15.346 pushed (dist-test, sig checked); the client runs v0.15.346 since 16:13. Probe DLL
   e7000094 installed (old .old_1611), restart pending.
   **Owner 16:15: "I'm getting a lot of "Companion cant get up there" errors on zoning in... related to having a bunch of
   companions and pets out"**: 16:14:00-08 the player joined 4700 m from where the 5 bodies stood; each in turn:
   "can't follow: up: no progress toward his crumb (4739 m away)" + notice, then back beside him. 0.15.347:
   drive_put_away first: farther than FAR_AWAY 80 m -> h.go_away = "far away" (no notice; log "far <id>: ...").
   **Owner 16:18: "did that really need a fix then if it was just from the teleport?"** (not strictly: they came back
   within 1-8 s; it only removed the notices; made without asking first) / **16:18 "dont make any changes for that
   then.."** (whether to take 0.15.347 out: being confirmed).
   **Owner 16:18: "that doesn't require a fix"** = 0.15.347 out. 0.15.348: FAR_AWAY and its check removed (as 0.15.346).
   **Owner 16:19: "zoning in shows the notices again"** (confirmed: out). 0.15.348 installed 16:19:33.
   **Owner 16:20: "were going to add an option that turns all those "cant follow" "can't reach", "afraid to jump", etc
   messages and default it off... players don't need to see that, its mostly for me and for debugging, so put that
   option under the debug section"**. 0.15.349: core/companion_notices.lua (on() / set(), companion_notices.json, off by
   default); Experimental tab Debug row "Companion follow notices" (dbg:fnotices); npc_wheel_probe.client_tick sends
   {op = "prefs", notices} on npcwheel at once on a change and every 1800 ticks; server F.notice_pref[account],
   F.follow_notices(world, player): cant_follow's status "companion_stuck" and put_away_for's can't-follow notice
   only when on. Not gated: the glide notice and "Companion has spawned near you!".
   **Owner 16:20: "I'm still getting a ton of errors with them saying they can't follow and then they respawn back...
   I'm just standing here.. so theres definitely a problem still with that"**: 16:20-16:21 N1 (follower 5 of 5, place
   4) stood 1.6 m from his place (SLOT_AT 1.5), 3.3 m from the player, never closer: can't follow -> respawn at the
   same spot every 5 s. 0.15.349: drive_stuck: within SLOT_NEAR 6 m of the player and NEAR_LEVEL 1.5 m level with him
   = progress (never can't follow there); settle counts a place within SETTLE_PLACE 2.5 m as reached.
   0.15.349 server Lua 16:22:41 (the loop stopped); Development release 0.15.349 (sig good); restart 16:24 (owner
   "yes"), client v0.15.349. **Owner 16:28: "I ran from my pets and none of the mare following me or teleporting to
   me....?"**: 16:26:42 "drive <id>: npc_probe.lua:980: attempt to compare number with nil" = drive_stuck read
   SLOT_NEAR, declared further down (a global nil). 0.15.350: SLOT_NEAR / SLOT_GAP declared above drive_stuck. Check
   from now on: texluac -l -p <file> | grep '_ENV "' must list only real globals.
   16:29 reload: all 5 back (2 put away from 70-80 m, the rest caught up). Owner 16:30 "drop the baby bunny one": asked
   whether to delete N5 or just drop it from the list: not answered (nothing done).
   **Owner 16:31 "no way to make the pets move faster eh" / 16:33 "for the pets, try 1 first then 2, because they just
   lag behind too much. the monster companions work differently right?"** = pets only: 1) find the animal's own run
   speed and raise it; then 2) a catch-up put-away/bring-back when a pet falls too far behind. Monsters: walk/run/
   sprint (the C++ sprints past 6 m), pets capped at run (sprint = 10-33 m jumps, 13:23).
   Found (fullrec 16:34, dog 32527 / hound 26319): ClientLocomotion.runSpeed dog 4.3 / hound 5.8, sprintSpeed 0 for
   both; no speed field in Locomotion; buff type names are not on the dedicated server (buffs.list needs a hosted
   world). 0.15.351 (option 1): the probe hooks after locomotion_execution (writes Velocity): a driven pet (g_pets code
   >= 1.5) more than kBoostFrom 8 m from the player's spot, moving over 1 m/s: horizontal velocity x kBoost 1.6 (log
   "pet boost <id>: ..." every 5 s at most). Needs the probe DLL (restart). Option 2 (catch-up) after the test.
   DLL 29afa6fa installed (old e7000094 .old_1637). **Owner 16:41 "power went down"**; files intact, world saved
   16:38:06; **owner 16:45 "start it all up"**: up 16:46:38 (hooks installed). **Owner 16:48 "mod crashed?"**:
   emf_core.log ends 16:48:23.031 on the FIRST "pet boost 25645: 8.1 m from the player: 7.3 -> 11.6 m/s"; the game
   server process still runs (its session log goes on, player connected) = the server's world step hung right after
   the boost (cause not known: the hook after locomotion_execution, its Velocity write, or its log from a worker
   thread). The DLL put back: e7000094 (29afa6fa kept as .bad_1650). 0.15.352: server_probe.cpp back to 0.15.346's
   (8e22ed7a). Needs a restart. Option 1 needs another way (or option 2).
   Restart 16:52 (owner "restart it"): the helper FAILED (no save within 90 s: the hung server could not save; it
   never force-stops); the owner ended the server (16:56 "done"); up 16:57:05 on e7000094. Owner 17:00 "was it a bug
   orrr?" (yes: ours; the freeze came at the first real boost) / **17:00 "can we find out? dont care if we crash it
   again?"**. 0.15.353 test A: 0.15.351's boost without the EMF_LOG inside the hook (counters only; boost_report on the
   server's on_tick logs "pet boost: N boosts so far ..." every 5 s). Freeze again = the Velocity write itself.
   DLL f534635f (old e7000094 .old_1703); restart 17:02 (owner "test again go ahead"), up 17:04:01. **Owner 17:05
   "crashed again, I'll kill it"**. The counters said why: "6534 boosts so far (hook ran 152551 times) ... inf -> inf
   m/s" at 17:04:58, 15066 at 17:05:03: hook_program's post runs ~20 times per step (once per job, on several
   threads), so the same Velocity was multiplied by 1.6 ~20 times a step -> infinity (then the step hung). 0.15.354 test
   B: once per pet per step (g_boosted entity -> w.tick(), under g_boost_mx), never above kBoostMax 10 m/s, skipped
   when the speed is not finite. Lesson: a hook_program post runs many times per step.
   Build fix ((std::min) against windows.h' min); DLL 305065ab (test A's kept as .bad_1706); restart 17:12 (owner
   "yes"), up 17:13:47. **Owner 17:15 "not crashing so thats good"**: log 17:15:24-39 "pet boost: 17 -> 488 boosts ...
   8.0-9.5 m from the player, 8.2-9.5 -> 10.0 m/s" (at the cap), no can't-follow. Whether they keep up: asked.
   Owner 17:17 "I dont think I see the cat anyplace": N3 (Cat (black)) was the inf-speed pet put away at 17:05:07
   just before the freeze, saved as away (17:13 "roster: loaded" listed N1 N2 N4 N5). **Owner 17:22 "they're keeping
   up fine, is the black cat swimming with me? I cant see it"** (boost = option 1 done; option 2 not needed): 17:21:47
   N3 29397 at depth 0.40 (< SWIM_ENTER 0.5) = walking: "can't follow (to the water): no progress toward the swimming
   player" -> put away; back once the player stands on the ground. **Owner 17:24 "go ahead and make the adjustment,
   but why didnt the cat just spawn to me then instead of being put away?"**. 0.15.355: F.SMALL_PETS (3 cats, 2
   bunnies, turkey, desert bird, flying bird), F.is_small(id); drive_read: a small pet swims over F.SWIM_ENTER_SMALL
   0.25 m; drive_water holds it F.SWIM_DEPTH_SMALL 0.3 m below the surface (was 0.9). npc_probe.lua is AT the 200
   top-level locals: new values go into F or tables.
   Asked: bring a can't-follow companion back beside a swimming player at once? **Owner 17:27 "yes"**. 0.15.356: the
   returning loop: after rt.why "can't follow" a swimming player (depth > 0.5) counts as ready (LAND_TICKS as before);
   glide / fast travel / falling still wait for the ground.
   0.15.356 installed 17:27:57. **Owner 17:29 "it took the companion dog a bit to respond to that crab that just
   attacked"**: 17:28:21-24 N1 (Aggressive): crab 29669 at 20.6 m, 4.8 m below, ray blocked x3 -> skipped 20 s; attacked
   at 17:28:44 (3.9 m), dead 17:28:53. (17:28:31: the Companions wheel brought N3 back: works.) **Owner 17:31 "yeah make
   that change, also 20 second skip might be too long a wait also? drop it down to like 10 seconds?"**. 0.15.357:
   SKIP_TICKS 600 (10 s, was 1200); fight_candidates: a skipped monster within F.SKIP_NEAR 6 m of the player is a
   candidate again ("... is no longer skipped: it is within 6 m of the player"); a hit already did that.
   Owner 17:31 "nothing was blocking the companion that I could see" (the straight ray, 4.8 m down, likely hit the
   slope at 3.8 m; offered a more forgiving ray: not answered). **Owner 17:32 "maybe you reverted a previous change, but
   chests aren't labeled by he pets name now"**: not a revert: 17:12:54 N1-N5 registered (5 names), 17:13:45 "N2..N5 is
   NO LONGER in the server's table (133 names)" = once the world's own player strings had loaded, ours were gone
   (N1 stayed: in the save); 17:31:30 N4's chest key 0. Same as the 14:47 miss (WATCH solved). 0.15.358: names_tick
   registers a name again when it is no longer there (log "names: '<n>' registered again"; the file read once more).
   Needs the probe DLL (restart).
   Restart 17:34 (owner "yes"): 17:34:53 N1-N5 registered; no drop after the join this time.
   **Owner 17:39: "lets get everything folded into one DLL, do some clean up on the code and evaluate what outstanding
   stuff needs to get addressed before we push a big update"**: plan given (1 one DLL: fk_server_probe into
   flamekit_native, side both; 2 cleanup: one companion feature, test tools out, server folder, HANDOFF; 3 open list:
   second-player tests, today's untested fixes, line check, admin, per-kind tuning, shared inventory, versions).
   **Owner 17:42: "E close on chests worked, small pets swim. I think the Companion Roster needs to be protected by
   admin rights"** (wording being confirmed).
   Restated (admins only; greyed out for others, the server refuses; admin = the owner for now; wheels and Companions
   stay for everyone). **Owner 17:46: "yes. also you need to tell me how to add companions to other plays because all
   those drop down were grayed out/disabled"**. 0.15.359: roster.ui_do refuses non-admins ({op = "denied"}, no
   subscription); the prefs reply on npcwheel sends {op = "admin", admin}; the client's Roster button is disabled
   unless admin (tooltip says why), its click is ignored, the window shows the refusal. Admin = is_admin (store
   "npc_admins", default OWNER_ACCOUNT: must change for other servers before a release). invtest: non-admin case.
   Give/Share lists = roster.known (players the server has seen join): the other player must join once.
   Development release 0.15.359 (sig good). **Owner 17:58: "Rename "Call my companion" to just "Call Companion" and get
   rid of one of the extra divider lines below it, theres two in a row..."**. 0.15.360: the button text; npc_wheel_
   probe.panel_rows no longer ends with a separator (experimental.lua adds its own).
   Development release 0.15.360 (sig good). **Owner 18:07 "lets review for clean up then"**: review A-E given.
   **Owner 18:11: "I'm afraid some of the clean up will make it harder to debug and fix future errors in the
   companion/pet system we still have other templates to fix and I don't want to limit myself on that"** -> revised:
   A detailed logs behind one server "companion debug log" switch (off by default, console toggle), nothing deleted;
   B every test tool stays (own file); C split npc_probe.lua into modules + rename probe -> companions; D delete only
   the 20 old probe DLL copies and 43 MB of fullrec dumps; E shorten HANDOFF keeping rules/decisions. **Owner 18:11 "go
   ahead"**. Standing rule from this: debug tools are never removed, only switched off.
   D done 18:13: delete permission granted for the server's emf folder; 20 .old_/.bad_ probe DLLs and 81 fullrec_*.txt
   removed (fk_server_probe.dll fdef5e67 kept). A, 0.15.361: npc_probe's log() skips F.DEBUG_ONLY patterns unless
   F.debug (console "flamekit.npc debug on|off", store "companion_debug", file companion_debug.txt beside FlameKit);
   the probe: DLOG() for jumps, edge, sequence writes, pet offer, boost, fight ray, drive count, names "is in"; reads
   companion_debug.txt every 120 ticks ("companion debug log on/off"). drive_harness identical with F.debug true.
   0.15.361 installed 18:15 (Lua live; probe DLL a9f92ac0, old fdef5e67 .old_1820: loads at the next restart).
   C, 0.15.362: features/npc_probe.lua -> features/companions.lua (loader) + features/companions/01_base .. 11_roster_
   window.lua (split at the section headers by a script: top-level locals became names in ONE shared environment, so
   no 200-locals limit and no declared-too-late nils). F.id "companions", log prefix "companions: ". local_server/main.lua
   loads features.companions. Tests: python3 local_server/tests/bundle.py makes /tmp/companions_bundle.lua (the parts in
   order) for the harnesses; drive_harness (debug on) identical over 1500 ticks for 3 seeds; invtest, fighttest,
   doortest, heal/seq/armor/watch tests identical; the fight tests' strict-globals checks removed (shared values are
   environment names now). Still there: features/npc_fields.lua (the recorder's field list).
3. ~~Teleport fallback~~ DONE (glider put-away/return, fast travel return, 2 s can't-follow respawn; owner 13:54,
   14:05). ~~Fast travel UI hide~~ DONE (0.15.281-0.15.284; owner 15:25 "we can cross that one off the list").
4. ~~Ground under a glide path~~ DROPPED (owner 15:26: "whats the glide path? I dont think we need that one"). It was
   a way for the hound to walk after a glide (find ground he could cross under the flight, or follow the trail in the
   air); the glider put-away and respawn beside the player (13:48, owner 13:54 "it works pretty well") does that job.
8. **Use more of the crumb meta data (owner 2026-11-18 19:07: "keep it of course. always assume more information is
   better"):** each crumb stores the player's speed, movement state, up/down speed, facing, water depth; not used in
   decisions yet. Ideas: his pace from the player's speed at that crumb (walk where the player walked, sprint where he
   sprinted; now the C++ picks it by distance), react to movement states (climbing, crouching) once their numbers are
   known. Standing rule from the same message: ideas and information are always kept/added to the list, never
   dropped by default.
7. **Companion inventory (owner 2026-11-18 13:06):** "also add to your list: companions can carry extra items for you
   (they have their own inventory like a storage check basically)". (a storage chest the companion carries; later)
   Owner 13:29: "a quick initial assessment of that idea... is it doable with what you know so far?" Assessment
   (from EMF 0.6.6 lua.md, nothing built): EMF has emf.put / emf.take / emf.move (moves between two inventories "without
   losing any", opts slot/exact/level/rarity) and emf.spawn (any template); emf.add_component only allows
   ScaleComponent and InteractionPause, so the hound cannot be given an Inventory. Likely way: a real storage chest
   template spawned out of sight as the companion's bag (kept in the world save, owned by the roster record), and
   FlameKit's own window (like the Auto Junk List tiles) showing its items, clicks moving items with emf.move. The
   game's own chest screen cannot be opened on the dog. Unknown: whether gear keeps perks/durability through
   emf.move, and where a hidden chest may safely stand.
   Owner 13:33: "I'd want all interaction to be in game, I'm trying to get rid of panels windows and buttons users need
   to mess with. I'm sure we could 'spawn' a chest to the ground and populate it with the companions 'simulated bang'
   ? when the user is done interacting with the chest, the game updates the new inventory list for the companion and
   the chest disappears? just spit balling here". (Design direction: NO FlameKit window; the game's own chest screen.)
6. **Blocked by animal / NPC notice (owner 12:18, follow up later):** "that edge case was so rare, I could not
   reproduce it. it only happened when the dog let himself back up on the shore... when I'm on land he follows me so
   well he doesn't get stuck... so we might have to just add that to the list for a follow up later to see if its been
   encountered again". The blockers() log stays on ("stuck: <id> in his way: ..."): when it happens again, check
   that animals and NPCs come out as different kinds, then ask the owner's wording ("Blocked by animals!" / "Blocked
   by NPC!" alone, or after "Companion can't follow you!").
5. **Hot reload for the C++ server probe (owner 11:22: "add the hot reload to the list for us to look at later, I'm not
   sure I want to risk introducing stability issues right now"):** a small permanent host DLL (hook, commands,
   registered programs, all state) + the logic as a plugin DLL loaded from a fresh copy; reload = preload the new copy,
   swap one function pointer, free the old one once no worker thread is inside it (a use count). Client side later,
   riskier (overlay, render hooks; the updater already swaps the DLL at the next start). Local server only first.
   (12:22) Also added to `flamekit_native/notes/EMF_REQUESTS.md` "Candidates" (owner: "add them to the list, not a big
   deal right now"): native mod reload in EMF, and "oxygen"/"max_oxygen" in emf.attribute. Controller buttons for mod
   keys stay candidate #6 (not moved up).
- Watch: the client lag at first launch through steam://connect.

