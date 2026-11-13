# FlameKit

A mod suite for Enshrouded, by Ninechars. One mod with a server part and a client part, one version number.

- **Auto Junk List**: your own list of items that are dropped or destroyed as you pick them up.
- **Minimap**: an overlay with the game's own map, markers, players, quest marks, clock and altitude.
- **Experimental**: per-player options such as no fall damage, unlimited stamina and an enhanced glider.
- **Updates itself** from the server a player joins, and tells the player what changed.

FlameKit runs on EMF (the Enshrouded Modding Framework), which is not part of this repository.

## Layout

| Folder | What it is |
|---|---|
| `flamekit/` | The Lua part: the panel and the features. Runs in the game and on the dedicated server. |
| `flamekit_native/src/` | The native part (a DLL): the minimap, item details and item icons. Only in the game, never on a server. |
| `flamekit_native/notes/` | Notes, tools and tests. |

`flamekit/changes.txt` lists every change in every version.

## Third-party code

The native part contains zstd's decoder (`zstddeclib.c`, BSD licence) and bcdec (`bcdec.h`). Their licence texts are beside them in `flamekit_native/src/`.

Nothing from the game is in this repository: icons and item details are read on each player's PC from their own game files.
