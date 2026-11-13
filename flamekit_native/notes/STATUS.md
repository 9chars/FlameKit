# FlameKit: where things stand (written 2026-11-12, about 02:15)

## Installed
- FlameKit 0.8.4, author Ninechars, one version number for the whole kit.
- Client (<game folder>\emf\mods): `flamekit` (Lua) and `flamekit_native` (native DLL).
- Local server (<server folder>\emf\mods): `flamekit` (Lua) only.
- G-Portal server: still only the old `flamekit_test`. Upload of `flamekit` deferred until asked.
- Working copies: `<work folder>\flamekit` (Lua) and `<work folder>\flamekit_native` (C++; src\flamekit_native.cpp,
  build.cmd, build_watch.cmd must be running for remote builds; notes\ has the reverse-engineering notes).
- `junk_list.json` lives only in the client's flamekit folder: never overwrite it.

## What the kit does
- Auto Junk List (F4 panel tab; server half removes junk). Settings prefix lf_.
- Minimap (native overlay window): terrain and contours from the game's data files, the game's own marker icons and place
  names, custom map markers, player-given names (altars, graves), waypoint, pings, other players, clock, region (nearest
  Ancient Spire) and nearest place (within the dial's reach, at least 150 m), zoom, size presets, drag to move, hide in
  menus, optional undiscovered places. Settings prefix map_ (in the flamekit mod's mod.json).

## Rules agreed with the user
- Say "client" and "server" explicitly. Keep things simple. Read game data, never modify it.
- Every read of game data is checked; a failure switches off only that feature (generic fallback where possible).
- Rely on other frameworks as little as possible. The minimap stays an overlay window (no renderer hook).
- The native DLL can only be replaced while the client is closed; Lua files reload live.

## To do, in order
1. Experimental (priority): survive the red shroud. Server side, emf.hit_rule with kinds = "shroud" (lua host 1.24 is
   installed), off by default, in an "Experimental" tab. Decide: everyone or admin-controlled.
2. Experimental: build anywhere. First try enlarging a flame altar's build zone (BaseIdComponent.buildZoneSize on the
   server; check the client agrees); else one zone over the whole world (BuildZoneSystem_addZone).
3. Experimental: workshop tab that crafts any craftable item (NPC-only ones too), charging the recipe's materials; no
   game data changes. Open: reading the recipe list; progress locks; crafting time.
4. Experimental: raise the animal limit above 128. Lead: BalancingTable.maximumAnimalsInWorld (EMF docs,
   engine_parts/re_villages.md); change the in-memory number on the server (and maybe the client: its cursor shows
   "MaxTameAnimalCountReached"), never the game's files. First confirm the value reads 128; raise in steps.
4b. The odd farm marker with a generic icon (needs a minimap screenshot).
5. Colours for the player's own map markers (colour number at node +0x18 not decoded).
6. Names in other languages (place names are English only).
7. Enemies on the minimap (optional, probably off by default).
8. Item icons in the Auto Junk List (BC7 decoder, PNG files in the mod folder, item-to-icon table).
9. Upload the flamekit folder to the G-Portal server.
Shelved: weather status. Not possible: dragging the F4 window, button background colours (EMF draws them).
Untested by the user so far: undiscovered-places switches (0.8.3), focus behaviour option A (0.8.0), "Back to its corner".

## 0.9.0 (Experimental tab)
- New Lua feature features/experimental.lua: host/server switches kept in experimental.json in the host's mod folder
  (never overwrite it on deploy): shroud (hit rule kinds=shroud,to=players,cancel), fall, immortal (kinds=all,min_health=1),
  open (every player may change them; otherwise host or [chat] admins only). Net channel flamekit/exp.
- 0.9.1: switches are per player (experimental.json: account -> switches; one hit rule per player and switch, to = the player entity; rules dropped 20 s after the last word from that game). No admin or open flag any more.
- Not yet confirmed in game: whether cancel stops the deadly (instant) shroud kill; if not, try min_health=1 for shroud.

## To-do added 2026-11-12
- Minimap: draw the grave (death) marker on top of all other markers, so it is never hidden under another icon.
- Experimental: when you die, offer an option to revive yourself on the spot (instead of respawning).
- 0.9.2/0.9.3: shroud switch also keeps FogResistance.dataStorage[1] (seconds left) at dataStorage[5] (full, 900) every server
  step: cancelling damage alone still gave "The Shroud has consumed you". "immortal" is now kinds=all cancel=true (no damage
  at all; min_health=1 left the player at 1 hp with the red low-health flash). After a reload the server finds players by
  world:account(1..64), so no unprotected gap. Confirmed by the user: fall, shroud timer, lava (held alive).
  Server copy of experimental.lua still carries DIAG logging (fog/hp each second, landed hits): remove when testing ends.
- DROPPED by the user (2026-11-12): walk on lava without sinking. With the stamina switch on the player still sinks but can move and jump out, which is enough.
- 0.9.4: switch "stamina" (emf.attribute_add to max each step). 0.9.5: button "Take me to the nearest flame altar" (op home: nearest PlayerSpawnPoint with target == 2, emf.teleport spawn_point). Neither confirmed in game yet.
- To-do (experimental): allow the map fast travel from inside the shroud (vanilla ban: fogType >= 2 and not InSaveZone; see EMF re_teleport.md).
- 0.9.6: button "Take me to the nearest Ancient Spire": the CLIENT finds the nearest MapMarker whose type number (FNV-1a of the markerType GUID) is tower 2708501182 or tower_locked 2561857117 and sends op go {x,y,z}; the server lands the player on the nearest PlayerSpawnPoint target==1 within 200 m (else ground). The server world has no MapMarker entities. Do not loop 8 pcall gets over all 38k entities in one step: the 250 ms script limit pauses the mod.
- To-do (experimental): flying upward while gliding. First choice: steer up as freely as down; fallback: unlimited updraft bursts (the game allows one per flight and the glider otherwise only loses height).
- To-do (experimental): walk on water (stand and walk on the surface instead of swimming).
- 0.9.7: switch "fly": while gliding (DynamicLocomotion.state == 4, server world) and the player holds S, the server writes Velocity.velocity.y = 8 every step. Client sends op lift on/off (and every second while held); host mode reads the key in F.tick. Tested by probe: gliderUpstreamFactor/UpwardsFactor = 1 gives NO lift (only slows); velocity.y = 6 gave about +2.8 m/s. Normal glide sinks 4.5 m/s, dive 20 m/s.
- Tests: on Linux the mock writes files named "tmp\\x.json" beside run.lua; delete them before a run (rm tmp\\*).
- 0.9.9 glider findings: a glider rises at most ~2.5 m/s whatever Velocity.y is written; extra upward speed turns the horizontal speed backwards. gliderUpstreamFactor/UpwardsFactor = 3 plus vel.y 12 gave ~6 m/s climb (factor 1: ~5) but still reversed the heading, so 0.9.9 also writes vel.x/z along the facing (yaw from CurrentTransform.orientation; identity = +z) at the speed the climb began with. StaticGravityModifier writes did nothing (Gravity stayed 25). CurrentTransform position fields are integers (fixed point), not metres: a direct position write was not tried. Updraft burst: DynamicLocomotion.flags bit 64 looks like "burst used"; 0.9.9 clears it while gliding (unconfirmed).
- 0.9.10 updraft burst: the game sets DynamicLocomotion.flags bit 64 (used; cleared again ~16 s later or at landing) and writes Impulse.impulses[1] = {0,3,0} S_Curve for 1.0 s and impulses[2] = {0,9.78,0} S_Curve for 2.25 s, keepAliveMask 2^37, start = game time in ns = world:tick() * 1e9/60 (+15 m in 2 s; Velocity does not show it). Clearing bit 64 alone makes the UI show a burst but the game still refuses one, so FlameKit writes the same two impulses on a Space press (client op burst; host reads the key) once the flight own burst is spent.
- 2026-11-12 11:30: user confirmed in game (local server, 0.9.10): S climb good, unlimited updraft bursts "worked perfectly". Glider to-do is DONE. Server copy still has DIAG logging (run diag_server.py after each deploy; remove at the end by copying the clean experimental.lua).
- 0.9.11: glider ceiling. Above about 2560 m the game shows "you strayed too far, returning to safety", counts 3 s and sends the player to the nearest flame altar (seen at 2558-2579 m). The S climb and the extra bursts stop above 2480 m. Removing the game limit itself: not looked into (mechanism unknown).
- To-do (experimental, later): remove the game height limit ("you strayed too far, returning to safety" near 2560 m). Mechanism unknown: not in the EMF docs; needs reverse engineering. Until then the glider ceiling at 2480 m stays.
- 0.10.2 (clock line never drops the time left; shorter wording, then smaller letters via a second TextPainter): minimap altitude at the END OF THE CLOCK LINE ("Alt N m"; setting map_altitude, default on; switch in the Minimap tab). The line shortens itself to fit the dial width (3 wordings). Installed in the client 2026-11-12.
- Windows headers define `small` (like `far`): do not use either as a C++ name.
- 0.10.4 (plus a small yellow "?" on a dark disc at the lower right of each): undiscovered places on the minimap are drawn in LIGHT GREY (brightness only, 150..252) at 0.8 strength instead of the coloured icon at half strength; same size (the user does not want them smaller).
- 0.10.5: clock line back to the usual letters; the overlay picture is wider than the dial by size/4 on each side (Canvas.dial, Canvas.ox; the window starts `pad` left of the dial) so the line can reach past the dial. Undiscovered grey darker (105..194), "?" smaller (7/20 of the icon).
- 0.11.0: minimap marker filters. Setting map_hide (text): short filter names with commas, "-" = none; kFilter[] in flamekit_map.cpp (one name per style) and FILTERS in features/minimap.lua must stay in step. 34 filters, two per row in the Minimap tab, plus Show all / Hide all. map_water and map_custom still work as before.
- 0.11.1: the marker filters are grouped chips (FLAME, SHROUD AND DUNGEONS, PLACES, YOURS, THE MARKERS YOU PLACED), lit = shown. 0.11.2: size preset "Extra extra large" = 480 px (the setting and the DLL already allowed it).
- 0.11.4: a dial bigger than Large (300) shows MORE OF THE WORLD at the Large scale (range x size/300) with letters (21 px), symbols and icons as on Large; map_big_text on (default off) = the old magnifying behaviour. letter_px(), sym_n and `more` in flamekit_map.cpp.
- 2026-11-12 12:38: user confirmed 0.11.4 in game ("perfect"): bigger dials show more of the world, text/icons capped at Large, altitude on the clock line. Marker filters installed with it (not separately commented on yet).
- 0.11.5: the game well_plant marker (4293256260) IS the Elixir Well (user, in game), not a Shroud Root: kStyles label fixed, chip "Elixir Wells" = filter name "sr" (kept for saved settings). The plain "dungeon" marker (3089427013, filter "ew", chip "Other dungeons") has not been identified in game; fognest (660000613) is labelled "Shroud Nest" (unverified: may be what the game calls a Shroud Root). Source edited, NOT yet built (waiting for the user to finish checking the other filters).
- 0.11.6: user-confirmed names: Elixir Wells and Shroud Nests filters work; "Shroud Forge" is called GEM FORGE; the custom marker "Goal" is called FLAG. "Bases" (marker_home_base) and "Travel Points" (mapmarker_fastTravel) are named from the game files only: the user does not recognise them.
- notes/EMF_REQUESTS.md: the list of things to ask the EMF developer for (started 2026-11-12).
- 0.11.7: north mark narrower (0.62), shorter (1.5), redder (238,24,24) and sized by sym_n; the "?" badge is drawn by TextPainter::draw_fine (regular weight, 3x supersampled, no shadow, centred on its ink).
- 0.11.8: the player arrow and the E/S/W marks use sym_n too (no bigger than on Large); "?" badge: dark grey dot (62,66,74), 1 px smaller, moved further onto the icon (0.28, 0.26).
- 0.12.0: chip heading "YOUR CUSTOM MARKERS"; setting map_undiscovered_names REMOVED (undiscovered names follow map_labels); marker and player names drawn by their own painter at 70% of the line letters (14 px at Large) and shown while mpp < 2.5 (was 1.3: now zoom steps 0-4 of 0-6).
- To-do (later, blocked on EMF): click on the minimap to set a waypoint or ping. The user wants a HOLD-A-KEY pointer during play, not "open the bag first". EMF has no call for a native mod to take the mouse (request 3 in EMF_REQUESTS.md). Unverified ideas: server half sets PlayerWaypoint; FlameKit-only pings over the exp channel.
- 0.12.1: "?" badge moved to (0.15, 0.14) of the icon size from its middle (the user asked three times for it to sit further onto the icon: icon pictures have empty edges). 0.12.0 names confirmed "reads well".
- 0.13.0: other players at any distance. Server half (features/minimap.lua F.tick, every 30 steps) sends each FlameKit game the other players as "x z name" lines on channel flamekit/map (to players only); the client Lua writes emf\\mods\\flamekit\\far_players.dat (line 1 = a counter); FarPlayers in flamekit_map.cpp reads it every 300 ms and adds players the game does not know itself (same name or within 30 m = known); a list older than 4 s is dropped. far_players.dat is a runtime file: do not deploy or diff it. NOT tested with two players.
- 0.13.1: settings map_markers, map_water and map_custom REMOVED (the marker filters decide; the DLL treats them as on); labels switch reads "Display map marker labels while zoomed in"; undiscovered switch reads "Show undiscovered map locations"; Zoom section in the Minimap tab (Zoom in / Zoom out, "Zoom level N of 7" where 7 = closest, and a line naming the zoom keys). mod.json is now written by json.dumps (indent 2).
- To-do (blocked on EMF request 5): hide the minimap while the EMF console is open. No API tells a mod that the console is open; a window above the game cannot go behind it (the console is drawn inside the game picture). Until then: F10 hides the minimap.
- 0.13.2: show_label moved to the END of the settings (its own group "FlameKit label", default on). Switching ON shroud / fall / immortal / stamina tells the whole server in the chat ("<name> switched on a FlameKit experimental option: ..."); nothing for the glider, the two travel buttons, or switching off.
- 0.13.3: BUG FIX: emf.broadcast is (text [, opts]) with NO world argument (emf.tell is (world, id, text [, opts])); the chat line of 0.13.2 (and of 0.9.0) was never sent. The mock now checks the argument types. System lines ({system = true}) are shown also with text chat off (EMF docs).

- 0.13.4: the glider option ("fly") is ON BY DEFAULT for every player (DEFAULT_ON in experimental.lua; experimental.json keeps "fly": false only for players who switched it off). The burst note (flags bit 64) is only cleared for players whose game runs FlameKit (p.kit), so players without it keep the game own display.

- 0.13.5 made the four options one-visit only; REVERTED in 0.13.17 at the user request: every option is remembered per player again (no "_session", no reset on leaving; on_player_left only drops the rules).
- 0.13.9 option names (user): "No Shroud Damage", "No Fall Damage", "Invincible Mode", "Unlimited Stamina"; the explanatory line under the travel buttons was removed. Chat lines confirmed visible in game; the user finds them too long (to be shortened).
- 0.13.12 (no "FlameKit:" in front): chat lines are "<Option> for <Player> enabled." / "... disabled." for the four one-visit options (on AND off; not for Enhanced Glider Mode, not for the travel buttons, not when the options end because the player left).
- 0.13.14: minimap hidden whenever the game was in front (visible only while alt-tabbed), first seen 15:46 after the EMF console had been used. Suspected cause: GetCursorInfo says CURSOR_SHOWING while the pointer has no picture (hCursor NULL); the hide-in-menus test now needs a picture too. NOT yet confirmed as the cause.
- 2026-11-12 15:53: after installing 0.13.14 and restarting, the minimap stays visible with the game in front ("seems fixed"). Cause NOT proven: the restart alone may have cleared it. If it comes back: note what was done just before (EMF console? alt-tab?) and log GetCursorInfo flags and hCursor.
- 0.13.15: travel buttons renamed "Nearest Flame Altar" / "Nearest Ancient Spire" under a "Fast Travel" heading; tooltips on every button of the Experimental tab (TIPS) and of the Minimap tab (switches, move, size, zoom, show/hide all).
- 2026-11-12 16:00: the user removed the old flamekit_test mod from the G-Portal server himself. G-Portal has NO FlameKit at the moment; upload flamekit (clean copy, no DIAG) only when the user asks.
- To-do (when the user says the settings are final): ONE package for players to install on their PC (EMF + its Lua host if allowed, flamekit, flamekit_native, short install steps), built from the clean working copy. Not yet: the user still wants to add settings.
- 0.13.16 (quest markers): the client has NO MapMarker entities of the quest types (3308163813, 2815089672); entity marker types not drawn by FlameKit: 2542184947 x5, 1162749170 x1, 1768495365 x69 (zero GUID), 2072506214 x12, 3507827154 x8, 286972634 x1, 3517974793 x178, 2949516383 x111. Guess: quest markers sit in the MapMarkerRegistry list like custom markers; the DLL now draws every list node whose type it has a style for (was: custom only) and logs the list type tally ("markers the game keeps in its own list"). UNCONFIRMED.
- Quest markers (checked 16:21-16:34): NOT in MapMarker entities and NOT in the MapMarkerRegistry list (that list held only custom types: ore x15, plants x1, flag x8, fish x1). A quest "!" seen by the user ("Fishing Island" / quest "Nice Day For Fishing") sits where a farm marker is; only the farm is an entity. The quest system must supply them: to be found (to-do). Registry also has mapmarker_investigation (2949516383 x111 entities, 2343026978), attention_marker (3945074471), marker_dungeon (1525751657), mapmarker_playerPing (2202030728): not drawn.
- 0.13.18: the minimap hides during a fast travel: client TeleportCount.counter change -> hidden until the player moves > 1 m at the new place (min 2 s, max 15 s); logs "fast travel: ..." lines. End of the loading screen itself is not detectable from the components tried (RenderTransform, ClientActor, PlayerState... unchanged). UNTESTED.
- QUEST PROBE (16:52): G38UiPlayData (client singleton) holds the list of what the game map draws. Around +0x36ea30 an entry for a spire read: [u32 0xe4040431 ?name hash][0][u32 markerId hash (FNV-1a of MapMarker.markerId)][0][x i64 32.32][y][z][f32 10.0][f32 5.0][u32 marker type id][u32 2]. Next: dump the entry of a quest-highlighted marker (the farm "Fishing Island", quest "A Nice Day For Fishing") and compare. Probe build: create emf\\mods\\flamekit_map\\probe_go.txt to dump the nearest marker entry (PROBE2 lines in the client log).
- 0.13.20: QUEST MARKS. flamekit_map.cpp quest_marks(): reads the quest list in G38UiPlayData (see memory_layouts.md); an entity marker whose markerId number is in it is drawn with the quest style (kQuestStyle 26, mapmarker_quest icon) and keeps its own name; filter "qu". Probe code removed. UNTESTED.
- 2026-11-12 17:02: user confirmed 0.13.20 in game: the quest mark shows on the minimap at Fishing Island ("looks right to me").
- 2026-11-12 17:04: user confirmed the minimap hides during a fast travel and comes back when the new place has loaded.

## RELEASE 0.14.0 (2026-11-12 17:09)
- Player package: <work folder>\release\FlameKit-0.14.0.zip (8.8 MB; folder release\FlameKit-0.14.0). It is the
  EMF 0.6.6 package (install.cmd / install.ps1 / emf_common.ps1 / uninstall.*, game\ with dinput8.dll and emf\, EMF's
  licences) with game\emf\mods = lua 1.24.0 + flamekit 0.14.0 + flamekit_map 0.14.0 only. EMF's installer copies game\
  next to enshrouded.exe. The EMF files are byte-identical to the ones on the user's client (md5 checked).
- Server mod: release\FlameKit-0.14.0-server-mod.zip (the flamekit folder only, clean, no DIAG).
- 0.14.0 changes: fast travel hide limit 20 s (the user found 30 too long), README rewritten, description updated.
- Local state: client and local server Lua at 0.14.0 (the local server's experimental.lua still has DIAG logging);
  the client's flamekit_map.dll is still 0.13.20 until the client is closed (out\flamekit_map has 0.14.0).
- NOT tested: the package on a clean PC; anything with two players.
