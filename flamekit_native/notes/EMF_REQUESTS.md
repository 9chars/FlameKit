# Requests for the EMF developer

Things FlameKit cannot do because EMF (0.6.6) does not offer them. Kept by Ninechars; add to it as they come up.

## Asked for (still open, checked against EMF 0.6.6's whole API on 2026-11-13)

4. **Settings that are stored but not shown in the Mods tab (`"hidden": true`).**
   Every value a mod keeps through EMF's settings has to be declared in mod.json, and every declared setting is
   listed on the mod's page in the Mods tab and in EMF.exe. FlameKit has its own panel for most of them (switches,
   size, zoom, marker filters) and keeps internal values there too (the minimap's dragged position, the list of
   hidden marker kinds, "move mode"), so the Mods tab shows the same things a second time, plus values no player
   should edit by hand. Wanted: a per-setting flag that keeps the setting working (`emf.setting`, `set_setting`,
   the ini) but leaves it out of the Mods tab and EMF.exe.

5. **Tell a mod when the EMF console (the overlay) is open.**
   The FlameKit minimap is a window of its own on top of the game, so it also sits on top of the EMF console, which
   is drawn inside the game's picture, and covers part of it. The minimap should hide while the console is open, but
   no call says so (EMF's own HUD lines are hidden then; a mod's overlay cannot find out). Wanted: a call such as
   `overlay_open()` (C API and Lua), or an event when the console opens and closes.

## Workarounds FlameKit uses

(owner 2026-11-22 13:14 "I want to keep track of all changes that we needed to make to work around things EMF could not
do") Every place where FlameKit does something itself, or reaches into the game directly, because EMF (0.6.6) has no
call for it. Each entry: what EMF lacks, what FlameKit does instead, where. Collected from the source on 2026-11-22;
every new workaround gets an entry here. Game addresses are for game build 1287369.

1. **Pictures that stay on screen.** EMF draws text lines and windows only. FlameKit draws all of its UI (minimap,
   tabs, item details, roster, labels) in a layered window of its own over the game's window, which lets clicks through
   and never takes the keyboard. `flamekit_native/src/flamekit_native.cpp` (header).
2. **More than 128 pictures.** EMF keeps at most 128 and never frees one. FlameKit reads item and buff icons straight
   from the game's data files (enshrouded.kfc, kfc_resources, the .dat files; zstd and BC7 decoders) and draws them
   itself. `flamekit_native/src/item_icons.hpp`.
3. **Taking the mouse while a key is held.** FlameKit's pointer mode (Right Alt) uses its own overlay window.
   `flamekit_native/src/flamekit_native.cpp`.
4. **A channel between a native (C++) mod and a Lua mod** (request 8 below). The DLL and the Lua part talk through
   small files in `emf\mods\flamekit`, polled: the UI (`ui_*.dat`, `ui_actions.txt`, `ui_layout.txt`, `*.request`),
   loot news (`loot_news.txt`), Free build (`free_build_server.txt`, `free_build_client.txt`, `free_build_spots.txt`,
   `free_build_spot_half.txt`, `altar_size_server.txt`, `altar_size_client.txt`, `altar_areas_server.txt`), companions (`labels.txt`,
   `pet_drive.txt`, `custom_names.txt`, `companion_debug.txt`, `chest_ground.request`), the updater
   (`update_status.txt`). `features/native_ui.lua`, `flamekit_native.cpp`, `build_anywhere.cpp`,
   `companions_server.cpp`, `loot_news.cpp`. Since a file can be read while the other side is writing it, Free
   build's files are written to a temporary name and then moved over the old one (0.15.453); a reader that finds no
   file keeps what it read before.
5. **4-byte events to Lua.** EMF delivers no 4-byte event to Lua's `emf.on_event` ("the queue layout of 4-byte events
   is not known yet"). New loose items and containers are reported through `loot_news.txt` instead.
   `flamekit_native/src/loot_news.cpp`, `core/loot_news.lua`.
6. **Build zones (where building is allowed).** No EMF call adds, removes or lists build zones. FlameKit hooks the
   game's `BuildZoneSystem_addZone` by byte pattern (Free build, remembered spots, Bigger altar areas, the list of
   altar areas). `flamekit_native/src/build_anywhere.cpp` (its header has what we found). The hook runs inside the
   game's own code on a thread EMF says nothing about, so (0.15.453) no game data is read there: the players'
   positions are read on the world's step (`emf::on_tick`) and kept for the hook.
7. **Air (oxygen).** `emf.attribute` has no name for air. Invincible Mode writes the player's Oxygen component
   directly (`dataStorage[1]` air now, `[2]` maximum, `DynamicOxygenState.accumulatedValue`). `features/experimental.lua`.
8. **Game values with no EMF call** (glider speed, the updraft burst, climbing with the glider, keeping stamina, mana
   and the shroud timer full, the fall height, monster threat tables for PvP). FlameKit writes the game's components
   directly; each is wrapped so that a game update that moves a field only switches that one thing off (logged
   "cannot ... on this game version"). `features/experimental.lua`, `core/leap.lua`, `core/dive.lua`,
   `core/fall_guard.lua`.
9. **Reading the player's input in some game versions.** When the game's own input component cannot be read, the
   player's game sends the S and Space keys to the server for the glider (`input_broken`). `features/experimental.lua`.
10. **Finding entities by component.** EMF has only `world:entities()` (about 37,000 on the production server). The
    flame altars (bases) are found by a background walk, a slice per server step. `core/bases.lua`. Loot no longer
    needs a walk: item 5.
11. **An entity's template (what kind of monster it is).** EMF cannot say. FlameKit fingerprints the template halves
    of a few components (`world:template`) and maps them to names. `core/monster_print.lua`, `core/monster_names.lua`.
12. **Giving an item with its quality and level.** `emf.give` knows only the item type. FlameKit spawns the game's
    pickup template with a PickupItem (item, level, rarity, amount). `core/ground_loot.lua`.
13. **A creature spawned a moment ago.** EMF refuses it (it reads as dead until the game sets its health), so FlameKit
    waits a while before it moves a spawned monster to the ground. `features/experimental.lua` (ground_q).
14. **Text widths.** EMF gives none, so chip widths are estimated from the text's length. `features/loot_filter/client.lua`.
15. **The loading screen of a fast travel.** No event says when it starts or ends; the server watches the player's
    travel request and the game's "ready for gameplay" flag. `features/travel_hide.lua`.
16. **Moving companions and pets.** No EMF call drives an NPC. FlameKit hooks the game's programs (EMF
    `hook_program`: `steering_locomotion`, `interaction_offer`, `interaction_taming`, `interaction_attempt`,
    `locomotion_execution`) and sets the movement itself. `flamekit_native/src/companions_server.cpp`.
17. **Updating a mod.** EMF has no updater. FlameKit updates itself from its GitHub repository, from signed lists
    (ECDSA P-256), and installs at the next game start. `flamekit_native/src/web_update.hpp`.
18. **The game clock in nanoseconds.** Derived from `world:tick() * 1e9 / 60` (candidate below).
19. **Reloading a native mod.** Every C++ change needs a restart of the game and the server (candidate below).

## No longer needed (FlameKit draws its own UI since 0.15.26 and its own icons since 0.15.13)

- 1. A bigger, game-styled pointer for EMF windows: FlameKit's window uses the game's own pointer (look_for_game_cursor).
- 2. Background colours for rows and buttons in EMF windows: FlameKit draws its own buttons.
- 3. Take the mouse while a key is held: FlameKit's pointer mode (Right Alt) does it with its own overlay window.
- 7. The limit of 128 pictures: FlameKit's window makes item icons in memory from the game's files (item_icons.hpp);
  no EMF picture is used any more (0.15.49 removed the last emf.image call).

## Candidates (came up while building FlameKit; not yet confirmed for the list)

- A mod window that can be dragged (EMF's windows are fixed: left, centre or right).
- A way to run code before a hit lands on one player only without a rule per player (the 64 hit rule limit).
- A documented way to read the game clock in nanoseconds (FlameKit derives it from world:tick() * 1e9 / 60).
- (2026-11-18, owner 12:22: "add them to the list, not a big deal right now") Air in `emf.attribute`: `"oxygen"` and
  `"max_oxygen"` (read, and refill through `emf.attribute_add` like health, stamina and mana). FlameKit's Invincible
  Mode (0.15.280) keeps the air full by writing the player's Oxygen component directly (`dataStorage[1]` = air now,
  `[2]` = maximum, plus `DynamicOxygenState.accumulatedValue`), which a game update could break.
- (2026-11-18, same) Reloading a native (C++) mod while the game runs: unload the DLL and load the new one between
  steps, with its hooks, commands and programs taken back and set up again. FlameKit's local test server mod
  (fk_server_probe) needs a server restart (and the game with it) for every C++ change; doing it inside the mod
  (a permanent host DLL plus a swapped plugin DLL) is on FlameKit's own list as the alternative.

6) Controller buttons for mod key settings. A keybind setting takes keyboard keys only, so a player on a controller cannot open a mod panel or use a mod key without the keyboard.

7) (no longer needed: see above) The limit of 128 pictures per game session. EMF loads at most 128 pictures (image_store.h,
   kMaxImages) and never frees one until the game closes. FlameKit shows an icon for every item in the Auto Junk List,
   one picture each, and the game has thousands of items: a player who sees more than 128 different items in one
   session gets no more icons (FlameKit shows the item's name instead). Wanted: a much higher limit, or a call to
   unload a picture a mod no longer shows (or to show one frame of a multi-frame picture by its number, so many icons
   can share one picture). Being watched: whether players really reach it.

8) A message channel between a native mod and a Lua mod in the same game. `emf.bus` connects Lua mods only, and mod
   messages (net channels) connect the same mod on a game and on its server; a native (C++) mod has no way to reach a
   Lua mod. FlameKit's native part (flamekit_native.dll, which draws FlameKit's own UI) and its Lua part (flamekit)
   therefore talk through small files in emf\mods\flamekit (polled). Wanted: `emf.bus` for native mods (publish and
   subscribe in the C API, with the sender's mod id as for Lua), so a native mod and a Lua mod can exchange messages
   in process.
