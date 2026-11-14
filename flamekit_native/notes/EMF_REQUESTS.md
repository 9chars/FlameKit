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
