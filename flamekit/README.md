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
  gliding, and the updraft burst can be used again and again), and two travel buttons (Nearest Flame Altar, Nearest
  Ancient Spire).

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
- **A dedicated server**: EMF with its `lua` mod and `flamekit`. Not `flamekit_native`.
