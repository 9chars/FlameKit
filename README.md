# FlameKit

A mod suite for Enshrouded by Ninechars. FlameKit adds a minimap, a party window, an auto junk list, PvP with a leaderboard, and a set of handy extras, all in one mod with one version number. FlameKit is under continuous development and you can expect to see new features and improvements.

FlameKit runs in your game and, for the features that change the world (PvP, fast travel, the experimental options), on the server too. On a server without FlameKit you still get the minimap, the junk list and the windows. It keeps itself up to date. It is built on top of the Enshrouded Modding Framework (EMF).

## Keys

All keys can be changed in the FlameKit Menu (F4): F4 and the pointer key in the Settings tab, F5 to F7 in the Windows tab, the minimap's keys in the Minimap tab. Keys that act while you play (Dump Junk, minimap zoom) can only be F1 to F12 or numpad keys, so typing in chat never sets them off.

| Key | What it does |
|---|---|
| F4 | FlameKit Menu |
| F5 | PvP Leaderboard |
| F6 | Experimental window |
| F7 | Party window |
| F10 | Minimap on or off |
| Numpad + / - | Minimap zoom |
| Right Alt | The mouse pointer, to click, move, resize and hide FlameKit's windows (hold it, or press once if you switched that on in the Windows tab) |
| Esc | Closes the FlameKit Menu and the pop-up windows |

## Features

### Minimap
- A round (or square) map in the corner of your screen, made from the game's own map: markers, flame altars, Ancient Spires, quest marks and other players.
- The clock, the time until day or night, your altitude, and where you are ("Blackmire / Flame Altar") under the dial.
- Zoom with the mouse wheel over it, or the Numpad + and - keys. F10 shows and hides it.
- With the pointer out, drag it anywhere, hover a marker to see its name, and click a marker to set your waypoint there (click it again to clear it).
- Hidden while the big map, your bag or any menu is open, and while you build.

### Auto Junk List
- Your own list of items you never want to carry. When you pick one up it is dropped or deleted, as you choose.
- Manage it in the FlameKit Menu (F4): your bag on one side, your junk list on the other. Move items with a click; "Dump Junk" clears what you already carry.

### Party window (F7)
- Every player on the server: health, mana, level, buffs and debuffs with the game's own icons, and where they are (region, distance and direction from you).

### PvP (Experimental window, F6)
- Free-for-all PvP that each player switches on for themselves. Only players who both have PvP on can hurt each other (at 25% of normal damage). It switches off when you leave the server.
- Monsters fight PvP players like any other player.

### PvP Leaderboard (F5)
- Ranks players by how many other players they killed; with equal kills, fewer deaths ranks higher. Shows how often each player was killed by another player.
- Only kills between players count. The server keeps the board across restarts, and every kill is announced in the Messages window.

### Experimental window (F6)
- Fast Travel: to the nearest Flame Altar, the nearest Ancient Spire, or your map waypoint, even from inside the shroud.
- Test monsters: spawn a harmless level 100 dummy to try your PvP weapons on (PvP must be on to hit it), or a duelist, any monster in the game at the level you pick, that fights back.
- Leaderboard button: shows or hides the PvP Leaderboard.

### Experimental options (FlameKit Menu, Experimental tab)
- No shroud damage, no fall damage, invincible mode, unlimited stamina and an enhanced glider (hold S to climb). Each player switches their own; everyone on the server is told when someone switches one.

### Messages and Notices
- Messages: everything FlameKit has to say, and a copy of the players' chat, each player in their own colour (the same as in the Party window and on the minimap).
- Notices: warnings that stay until they no longer apply.

### Updates
- FlameKit updates itself from this repository. When a new version has downloaded, a window says so; "Restart Game" closes the game and starts it again with the new version. "Check for updates" on the What's New tab looks right away.
- Every update is signed with FlameKit's own key; your game refuses anything else.
- The What's New tab lists every change, and the About button shows this page.

## Installing

FlameKit needs EMF (the Enshrouded Modding Framework) 0.6.6 with its Lua host. EMF is not part of this repository; install it first, from https://github.com/matenm/emf-enshrouded/releases

In your game, put the folders `flamekit` and `flamekit_native` into `Enshrouded\emf\mods\`. On a dedicated server, put only `flamekit` into the server's `emf\mods\`. Both need the same FlameKit version for every feature to work; your game updates itself, the server is updated by its owner.

## Your data

Nothing from the game is in this repository: item icons and item details are read on your own PC from your own game files, and FlameKit never changes the game's files. FlameKit's log (`emf\mods\flamekit\logs\`) leaves out account ids, so it is safe to share with a bug report.

## For the curious

| Folder | What it is |
|---|---|
| `flamekit/` | The Lua part: every feature's logic. Runs in your game and on the server, and talks to the server over EMF's mod messages. |
| `flamekit_native/src/` | The native part (a DLL, C++): everything FlameKit draws on screen (its own see-through window over the game), item details and icons, and the updater. Only in your game, never on a server. |
| `flamekit_native/notes/` | Notes, tools and the tests. |
| `dist-test/` | The development update channel. |
| `flamekit/changes.txt` | Every change in every version. |

The updater reads the newest commit of this repository, downloads the channel's file list (`update.txt`), checks its ECDSA signature against the key built into the DLL, and downloads only the files that changed. The new version is put in place at the next game start.

The source, the notes and every version: https://github.com/9chars/FlameKit

## Third-party code

The native part contains zstd's decoder (`zstddeclib.c`, BSD licence) and bcdec (`bcdec.h`). Their licence texts are beside them in `flamekit_native/src/`.

## Thank You Keen

A heartfelt thank you to Keen Games, the studio behind Enshrouded. You built a world that is a joy to explore, to build in and to share with friends, and it is that world that made us want to add our own small touches to it. FlameKit exists because Enshrouded is so much fun to play.

We look forward to your continued support and future content updates.

https://www.keengames.com/about
