# FlameKit

One Enshrouded mod with several features, for a server and the players on it. By Ninechars.

It runs on **EMF** (the Enshrouded Modding Framework). The download for players already contains EMF.

## What is in it

Press **F4** in the game for the FlameKit panel. Its tabs:

- **Auto Junk List**: pick the items you never want; they are dropped or deleted when you loot them, or with one button.
- **Minimap**: a round map of the ground around you, drawn from your own game files, with the game's icons, your own
  markers, quest marks, other players, a clock and your altitude. Sizes, zoom, marker filters and what it shows are
  in this tab. F10 hides and shows it; the + and - keys on the number pad zoom.
- **Experimental**: options each player switches for themselves (the server tells everyone when you do):
  No Shroud Damage, No Fall Damage, Invincible Mode, Unlimited Stamina, Enhanced Glider Mode (hold S to climb while
  gliding, and the updraft burst can be used again and again), Fast Travel buttons (Nearest Flame Altar, Nearest
  Ancient Spire), PvP (free-for-all) with its Leaderboard, and test monsters to spawn and fight (their Reward loot
  goes into a loot chest on the ground).
- **Building**: Free build (build outside flame altar areas; what you build there is remembered and saved), bigger
  flame altar areas, and the remembered spots.
- **Spawn Nodes**: raids. Place nodes around the map in groups; a group's trigger (by hand, a timer, a trip wire, a time
  of day, or a player in a base near its nodes) sends waves of monsters from every node, with notices, sirens, a
  countdown of the monsters left and markers over them. Each group sets its monsters, their level (also rising each
  wave, never above 100), their loot (normal, FlameKit's reward chest, both, or none), the waves and the raid's rules
  (protect bases, spare animals and pets). The Spawn Nodes window has what you need while walking the map (add, move
  and delete nodes, start and stop). For now every player can use it (a test).
- **Settings**: Auto Loot (where loot from monsters you kill and what you chop or mine goes: your bag, your companion's
  bag, the ground, or the game's own way) and the switches and keys of FlameKit's windows.
- **Windows** and **About**: which of FlameKit's windows show, their keys, and FlameKit's version and updates.

## Install (players)

1. Extract the zip into a folder (right-click, Extract All). It does not work from inside the zip.
2. Close Enshrouded.
3. Double-click **install.cmd**. It finds the game through Steam and copies everything in.
4. Start the game. Run it in **borderless or windowed mode**: the minimap does not show in exclusive fullscreen.

Everyone on a server needs the same FlameKit version as the server.

## Good to know

- The minimap's place names are in English.
- After a game update some parts can stop working until FlameKit is updated (quest marks, your own markers, names).
  The rest keeps running.
- Windows may ask about the unsigned files the first time.

## Where it has to be installed

- **Your PC**: EMF with its `lua` mod, `flamekit` and `flamekit_native` (minimap, item details, item icons, updates), all in `<game>\emf\mods`.
- **A dedicated server**: EMF with its `lua` mod, `flamekit` and `flamekit_native`. On the server `flamekit_native`
  does the parts the Lua part cannot: Building's Free build areas, and Spawn Nodes' raid lock, base protection, the
  monsters sparing pets and animals, and the hold that keeps tamed animals still during a raid (so the raid monsters
  find their way to the players at once). Without it those parts do nothing.
