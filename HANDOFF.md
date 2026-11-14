# FlameKit: handoff note

Read this first when starting a new conversation about FlameKit. Written 2026-11-13, at version 0.15.48.

## What FlameKit is

One mod suite for Enshrouded by Ninechars, one version number for the whole product. Two parts:

- **The Lua part** (`flamekit/`): the panel and the features. Runs in the player's game (the "client") and on the dedicated server.
- **The native part** (`flamekit_native/src/`, built into `flamekit_native.dll`, mod "FlameKit Native"): all of FlameKit's UI (F6 window, pinned windows, minimap, lower left lines), item details, item icons and the updater. Client only, never on a server.

It runs on EMF 0.6.6 (the Enshrouded Modding Framework) with EMF's Lua host. Features: Auto Junk List, Minimap, Party window, Experimental options (per player), Settings, What's New, self-update (signed).

## How the owner wants the work done (follow these exactly)

**KEY DIRECTIVE: protect personal, sensitive and confidential information.** If anything the owner asks for, or anything about to be done, could leak personal, sensitive or confidential information (into the public GitHub repository, into logs players send, into files shared with anyone), STOP before doing it and warn the owner clearly and forcefully: say exactly what could leak and where, and wait for the owner's decision. This comes before every other rule.

1. **Confirm before changing anything.** Say in a line or two what you are about to change and wait for a yes. Reading logs and files to answer a question needs no confirmation.
2. **A question is a question.** Asking for information is not a request to change something.
3. **Take instructions literally.** Do what was named, nothing wider. No assumptions, no extra options, no "while I'm here".
4. **Be specific.** When asking the owner to check something, say exactly where to look and what the expected result is, the first time.
5. **One version per round of work.** Every time anything changes, the version goes up; one version can hold many changes. Never leave changed code under an old number.
6. **The change log lists everything.** `flamekit/changes.txt` gets a line for every change in every version. Nothing is trimmed, merged or hidden. Format: a line `0.15.8 Nov 13, 2026`, then `- ` lines, then an empty line; newest first.
7. **Test the way production works.** Nothing is copied onto the owner's client by hand. New versions reach the client only through the updater.
8. **No release package until told.** Do not build zips or touch `dist` (the players' channel) until the owner says to roll to production.
9. **Do not modify game data.** Read only. Prefer few frameworks. When a game update breaks something, fall back to a generic label or icon; disable a feature only if needed to prevent a crash.
10. **Short labels, short chat lines, no explanatory text in the panel.** Always say "client" or "server" explicitly.
11. **Keep replies short** and lead with the result.
12. **No EMF for any UI.** Nothing FlameKit shows on screen is drawn by EMF, whatever exists today or was used before. Done in 0.15.26: `emf.hud`, `emf.notify`, `emf.window` and the F4 panel (`core/hub.lua`) are gone; FlameKit's window (F6), its pinned windows and the lower left lines are drawn by `flamekit_native.dll`. Never add EMF UI back. Keep it simple; FlameKit's UI must not interfere with other mods or the game's own functions. Later: an output box for status messages.
13. **The DLL never reads the game for the UI.** The Lua part (fields looked up by name at runtime, so it survives game updates) owns all game data and all changes; the DLL only draws and takes clicks. Stable and reliable over clever; no hacky code.
14. **When something needs to be run on the owner's PC** (the build watcher, a program, a restart of the local server), do not hand it to the owner as a chore: ask for permission to run it yourself (computer use or the shell), and on a yes, do it.
15. **Name things explicitly.** In every message to the owner, name exactly what is meant: the file, the program, the tool, the window, the setting, the version. No "it", "this", "that" or "things" where the owner would have to guess; write the name instead (e.g. "the tool that copies files onto your PC", not "it").
16. **The same report after every change** (owner, 0.15.22), always in this form:
    - **Recap:** one or two sentences: what was done and why.
    - **What changed:** the version and a short list of what is different in the game.
    - **Restart needed:** exactly which of these: the game client, the local dedicated server, both, or none (and why, in a few words).
    - Then ask: "Shall I restart <the game client / the local server / both> now?" On a yes, do the whole restart yourself with the **restart helper** (never computer use: the owner does not want his mouse and keyboard taken over): write the one word `client`, `server` or `both` into `<work folder>\restart_helper\restart.request` (copy from a fresh folder each time), wait for `restart.done` (`ok ...` / `failed ...`) and read `restart.log`, then check in FlameKit's log that the new version runs. The helper (`tools/restart_helper/` in this repository; `restart_paths.txt` with the server folder is on the PC only) runs in its own window, `restart_watch.cmd`, which the owner starts: the client is closed like Alt+F4 and started through Steam (app 1203620), a server restart always closes the client first (no player connected), then writes a number into the server's `emf\mods\flamekit\save_now.request`; `features/server_save.lua` on the server calls `emf.request_save()` and answers in `save_now.done`; once a save file newer than the request exists the helper ends the server process (Ctrl+C from another program did not work: tried twice on 2026-11-13, the server ignored it), starts it again minimized, waits for "world loaded" in `emf\emf_core.log`, then starts the client. No new save within 90 s: nothing is stopped. The client is never ended by force. The helper restarts itself when `restart_helper.ps1` changes (exit code 10, `restart_watch.cmd` loops). Joining the server stays a click for the owner. Before asking for a server restart, check whether EMF already reloaded the Lua files on the running server (it does on file change). Never restart anything without that yes.
17. **A chime when waiting for the owner** (owner: ADHD, multitasking): at the end of every turn that waits for the owner's answer or test, copy a file `chime.request` (any content) into `<work folder>\restart_helper\`; the restart helper plays a chime on the PC and deletes the file. Always, every such turn: the owner asked for it.
18. **Be specific and clear** (owner, 0.15.36). The owner wants to understand how FlameKit works inside and points out flawed designs: never hold technical details back or talk down. Technical terms are fine; vague ones are not. When describing a change, say concretely what it does: which file, which function, which data goes where, what the owner will see in the game, and a concrete example when an idea is new (e.g. the actual row a feature would write). A sentence the owner cannot picture is a failure: rewrite it until it names the real thing.

## Where everything is

Folder names on the owner's PC are not in this repository (it is public). `<work folder>`, `<game folder>` and `<server folder>` below are listed in `LOCAL_PATHS.md` next to HANDOFF.md on the owner's PC (never pushed).

- **GitHub:** `9chars/FlameKit` (public). Source, notes, tools, and the update channels. The Claude GitHub App is installed on it; pushing works.
  - `dist-test/`: development versions. The owner's PC downloads from here (it has `emf\mods\flamekit\update_channel.txt` containing `test`).
  - `dist/`: players' versions. Does not exist yet; create it only on release.
- **Owner's PC working copies:** `<work folder>\flamekit` (Lua), `<work folder>\flamekit_native` (C++: `src\`, `build.cmd`, `notes\`).
- **Client install:** `<game folder>\emf\mods\{lua, flamekit, flamekit_native}`.
- **Local dedicated server:** `<server folder>\emf\mods\{lua, flamekit}`.
- **Production server:** G-Portal, last given 0.14.1/0.14.2 by the owner. Upload only when asked.
- **Logs:** `emf\emf_core.log` in the client and in the server folder.

Runtime files that are never deployed, diffed or overwritten: `junk_list.json`, `seen_version.json`, `far_players.dat`, `experimental.json` (server), `item_details.dat`, `icon_requests.txt`, `icons\`, `update_status.txt`, `update_channel.txt`, `ui_list.dat`, `ui_tabs.dat`, `ui_actions.txt`, `ui_hud.dat`, `ui_messages.dat`, `ui_party.dat`, `ui_open.dat`, `ui_layout.txt`, `save_now.request`/`save_now.done` (server), `debug.txt`, `logs\`.

## How to build and publish a version

1. Change the source. Bump `version` in `flamekit/mod.json` and `flamekit_native/mod.json` to the same number. Add the lines to `flamekit/changes.txt`.
2. Lua tests: `texlua flamekit_native/notes/tests/run.lua flamekit /tmp/fkj host` and `... joined`; both must print `ALL PASSED`. Before each run: `rm -rf /tmp/fkj /tmp/fkj\\*` (run.lua's backslash paths land next to the folder; a stale `ui_actions.txt` breaks the tab test).
3. Native build (only when `src\` or `flamekit_native/mod.json` changed): copy the changed files into `<work folder>\flamekit_native\` (fresh staged folder, check md5 on the PC), then restart helper request `build`. Result: `restart.done` `ok build`, `build.log` ends `BUILD OK`, the DLL in `out\flamekit_native\`. The build never copies into the client. Every build gives a different DLL (timestamps), so an unchanged source still makes a new update.
4. Lua part for the local server: copy the changed files into `<server folder>\emf\mods\flamekit`, `mod.json` last (EMF reloads Lua live on the server; check `reloaded` in `emf\emf_core.log`). Same files into `<work folder>\flamekit`.
5. Make the list: `python3 flamekit_native/notes/make_dist.py . dist-test <built dll> flamekit_native/mod.json`.
6. Sign it (since 0.15.45; an unsigned list is refused by every client): copy `dist-test/update.txt` to `<work folder>\restart_helper\signing\update.txt`, restart helper request `sign`, read `signing\update.sig` (128 hex digits) into `dist-test/update.sig`, run `python3 tools/check_sig.py dist-test` (must say `update.sig is good`).
7. Commit `dist-test/` (list and signature together) and push. The client's log (`emf\mods\flamekit\logs\`, newest file) shows `update: vX is ready` within about a minute; `update_status.txt` says `ready|...`. Nothing changes in a running game: everything switches at the next game start.

## How the updater works

`flamekit_native/src/web_update.hpp`: the DLL reads the newest commit of main, then fetches `https://raw.githubusercontent.com/9chars/FlameKit/<commit>/<channel>/update.txt` (version, then `<size> <hash> <path>` per file), downloads what differs, checks size and FNV-1a hash, then installs: the DLL by renaming the loaded one to `.old` (used from the next start); the Lua part is held in `emf\flamekit_update\` and put in place at the next start, `mod.json` last (since 0.15.17). It never downgrades. Status goes to `update_status.txt`, which the label at the bottom left shows.

Since 0.15.20 it reads the newest commit from `github.com/9chars/FlameKit.git/info/refs` (not cached) and downloads from `raw.githubusercontent.com/9chars/FlameKit/<commit>/...` (immutable); falls back to main. Test channel every 60 s, players every 10 min, plus the "Check for updates" button in What's New. Since 0.15.39 it keeps checking while an update waits: a newer one replaces the waiting one (`held_version`, `clear_pending`; the DLL: if `flamekit_native.dll.old` cannot be deleted it is the running DLL, so the waiting `flamekit_native.dll` is overwritten). Since 0.15.45 the list must be signed: `update.sig` next to `update.txt`, ECDSA P-256 over SHA-256, checked with Windows bcrypt against `kReleaseKey` (`signed_by_release_key`); missing or wrong: log `update: REFUSED: ...`, status `failed|An update was refused: it is not signed by FlameKit`, nothing downloaded. Since 0.15.47 a failed/refused status clears once a later check is fine.

**Signing key:** "FlameKit release signing", ECDSA P-256, in the owner's Windows user key store, not exportable (restart helper `keygen`, 2026-11-13). Only the public key is in the repository (`web_update.hpp` `kReleaseKey`, `tools/check_sig.py`). If the owner's PC or Windows account is lost, no update can be signed again: a new key needs a new DLL, which players must install by hand.

**Proven in the owner's game:** download and install from `dist-test` (0.15.10); holding the Lua part to the next start; replacing a waiting Lua part (0.15.40 → 0.15.41) and a waiting DLL while the old one runs (0.15.45 → 0.15.46: `v0.15.46 replaces v0.15.45`); a signed list accepted (0.15.46, 0.15.47); a tampered list refused (`update.txt` changed to 0.15.47 with the 0.15.46 signature: `REFUSED ... the signature does not match`, nothing changed). The old updater through the game server is gone since 0.15.9.
**Not yet tested:** a clean PC installing from scratch, and the `dist` channel (owner: next session).

## State right now

- **Versions:** local server 0.15.48 (Lua). Client: runs 0.15.46; 0.15.48 is downloaded and waits for the next game start. Production server (G-Portal): 0.14.x, not touched. `dist` (players) does not exist yet.
- Every version's detail is in `flamekit/changes.txt` and the git log. Below: how things are built, so new work fits.

## Design (how FlameKit is built)

**Bridge between Lua and the DLL** (rule 13; one writer per file, all in `emf\mods\flamekit\`):
- Lua → DLL: `ui_list.dat` (Auto Junk List: `O` options line; `P <clickkey> <lit> <label>\t<tooltip>` option buttons; `B`/`J` item tiles, tab-separated `B\t<id hex>\t<count>\t<debug>\t<rarity>\t<level>\t<type>\t<name>`), `ui_tabs.dat` (other tabs: rows of kind h heading, t text, b button, s separator, i item tile with 6 more fields), `ui_hud.dat` (label; `notice <text>` drawn orange under it), `ui_messages.dat` (`m <n> <rrggbb> <text>`, last 20; from `kit.note`), `ui_party.dat` (`p <you> <hp> <hpmax> <mana> <manamax> <level> <x> <z> <name>`), `ui_open.dat` (open the window on this tab; the DLL deletes it).
- DLL → Lua: `ui_actions.txt`, numbered lines, never replayed: `junk`, `keep`, `dump`, `auto`, `action`, `view <id>`, `tab <id>/<generation>/<button>`, `key <name>` (a key pressed in the window, to the shown tab's `key(world, name)`), `opt <clickkey>`.
- DLL only: `ui_layout.txt` (place and size of each window, 7 fields incl. height).

**DLL UI** (`flamekit_native.cpp`, `ui_thread`): one overlay window, plain BGRA surface (keep the Vulkan presenter path open), layers in this order: hud, backdrop, minimap, party, messages, window. Watchdog keeps it on top of the game 4×/s.
- `WindowLayer` (F6, `window_key`): title bar, frame, move, resize (min 560×440); tabs wrap; sizes are members set by `lay_out()`. Tab order from `main.lua`, What's New first; it opens by itself on What's New after an update (or every game with `open_on_start`). Auto Junk List has its own icon view (pages); every other tab is rows from `ui_tabs.dat` with a scroll bar. Another program in front does not close it (`lost_front`).
- `PinnedLayer` (party, messages): stay on screen while playing, collapse/hide, move, resize (height = maximum, content scrolls), `content_click`, `hide_in_menus` (party: on; messages: off). They take the mouse only in pointer mode.
- Pointer mode (`g_pointer_mode`): F6 window open, or the pointer key held (`pointer_key`: Right Alt default, Right Ctrl, Caps Lock; `g_pointer_hold`). The pointer returns to where it was last time. The game's own pointer is copied from Windows (`look_for_game_cursor`: only a colour pointer with its hot spot in the top left quarter; the real one is 64×64, hot spot 3,3). `Frame::in_menu`: the game shows its own pointer outside pointer mode.
- Item tiles are a standard element: Lua `kit.items.tip(id, debug_name)`; a panel row `{ item = <id>, count, text, tooltip, button, selected }`; DLL `ItemTip` + `draw_item_tip()`. Use them for any item UI.
- Tooltips: every button whose use is not obvious gets one; a paragraph starting with `WindowLayer::kRedLine` (`L'\x01'`) is red. UI text stays short; tooltips may explain.
- Messages window always shown in a world: last 5, 10 in pointer mode.

**Features (Lua):** settings live only in their own feature's tab; the Settings tab (`features/settings.lua`, from mod.json) shows only the FlameKit groups and each feature's `enabled_setting`. Debug things go in Experimental → Debug (log level buttons, test players `dbg:test:N`). Party: the hosting side reads each player every 30 steps and sends the list on channel `party`; DOWN at 0 health; clicking a player in pointer mode follows them on the minimap. Test players: `core/test_players.lua`, via channel `party_test`. Server version: `features/server_version.lua`, channel `ver` (client asks at step 120, then every 3600; `kit.server_note`). Server save: `features/server_save.lua` (for the restart helper). Who is in the server world: `core/players.lua` (0.15.48), kept from `emf.on_player_joined` / `emf.on_player_left` (EMF Lua 1.20; the installed one is 1.24). Measured on the owner's server: after a FlameKit reload EMF reports every player already there again (`joined: entity id 1` in the same moment), so the list has no gap; the owner's player was id 1, no player id in 65-1023. EMF's docs: player entity ids are 1..0x3FF and a leaving player's id goes to the next who joins. Never scan entity ids for players again; the 1-64 scan stays only as the fallback for an EMF without the events. The Auto Junk List never junks trophies, runes, Legendary Runes, eternal arrows/spells (unless `lf_show_all`).

**Logging** (owner: for everything, long term, switchable): `fk_log.hpp`, logs in `emf\mods\flamekit\logs\` (10 sessions, 50 MB); `debug.txt` off/normal/full, Ctrl+Shift+F12 cycles; the monitor thread copies emf_core.log lines in. Privacy: other programs only by file name and class, never titles; the Windows user name becomes `<user>`.

**Known risk:** the minimap reads position and item data through layouts compiled into the DLL (EMF SDK from game build 1283531); a game update can break them until a rebuild. EMF allows 128 pictures per session (`item icons: N in use` in the log).

## To do (owner's list)

1. **#2 Clean PC / `dist` test** (owner: next session): install FlameKit from nothing the way a player would, and the first `dist` (players') channel. Not before the owner says so (rule 8).
2. **#7 Controller support for the pointer key:** a controller cannot move the mouse pointer; needs pointer emulation first. Later.
3. **#8 What the Messages window is for:** decide what goes there (now: `kit.note` lines). Later.

## Things learned the hard way

- Copying files onto the owner's PC (device_commit_files): sending the same container path twice can deliver the OLD content. Use a fresh folder name per version (e.g. `outputs/v0_15_15/...`) and check the result by hash on the PC before building.
- A Large Backpack is its own container with four rows; the player's inventory links only the first. `core/bag.lua` follows the backpack's own `InventorySetup`, and items in its rows are taken with the backpack as owner.
- Item definitions (2088 bytes, game build 1287369): rarity at `+0x17`, category `+0xcc`, sub-category `+0xcd`, level range `+0x674/+0x678`. Icons: `UiTextureResource` under the item's GUID, in zstd-compressed chunks; pixels are BC7, 256 or 512 px.
- EMF limits met so far: 128 pictures per session and no unloading; windows are a flat list of rows (no scroll area, no fixed height, no row spacing); icons only on `slot` and `row` rows; no controller buttons for mod keys; `emf.take` only accepts slots linked directly to the named entity. See `flamekit_native/notes/EMF_REQUESTS.md`.
- Never hide eternal arrows or spells from protection: they are high-end items and stay un-junkable. Runes and Legendary Runes are never junkable (those two items only).
- Windows macros `far` and `small` cannot be used as C++ names.
- The restart helper: Ctrl+C to the server does not work (save-then-kill instead); the client window is found by skipping FlameKit's own `FlameKitOverlay` class; `Start-Process -Wait` hangs on the build (mspdbsrv), so it uses `WaitForExit`.
- `git revert` takes no `-q`: check that the push really happened (`git log --oneline -1`) before waiting on the client.

More detail: `flamekit_native/notes/STATUS.md` (to-do list), `memory_layouts.md`, `EMF_REQUESTS.md`.
