# FlameKit: handoff note

Read this first when starting a new conversation about FlameKit. Written 2026-11-13, at version 0.15.143 on Development and the local server only (owner, 2026-11-15 13:51: "I didn't say anything about touching g-portal or publishing to stable"); production: 0.15.141; Stable: 0.15.140.

## Rule 0: instructions to the owner (read before every message that tells him to do something)

The owner has asked many times for specific instructions and Claude has failed it many times (last: 2026-11-15, "back in
that folder"). Before sending any message that asks the owner to do something, check every step against this list and
rewrite the step if any answer is no:

1. Is it a numbered step that does exactly one thing?
2. Does it give the full path (`C:\enshrouded mod shit\...`) of every folder or file it mentions, even if the step
   before named it? No "that folder", "there", "back in", "the same", "the one above".
3. Does it name the exact file, button or menu item to click, and what Windows will show or ask?
4. Would the step make sense if it were the only step he read?
5. Does the last step say what to tell Claude when done, and what Claude does then?
6. For a test: does the message say, BEFORE the steps, what the test does exactly (what is created, read or changed,
   with which values), what it never touches, and what each possible result means? (owner, 2026-11-15: "left me
   guessing about your test")
7. Did Claude first check everything it can check itself (the file on the PC, what the code will do, a read-only dry
   run in the log) so the owner is not the one finding Claude's mistakes?

## Rule 0a: CORE DIRECTIVE, tests and requests (owner, 2026-11-15 14:46)

Every time Claude needs a new test, it says so. Never ask the owner to do anything without first giving a short, brief
recap: what Claude needs, what Claude will do, what the owner will do. Short: a few lines, no long explanations
(owner: "all you have to say is you need to do another test"). Without that recap the owner refuses.

## Rule 0d: CORE DIRECTIVE, no game client updates for server-only changes (owner, 2026-11-15 15:24)

"Updating game client versions for no reason": a change that only touches what runs on the server (server-side Lua) goes
to the local server only: no DLL build, no dist-test list, no Development channel push, no client update. The server's
`flamekit/mod.json` still gets the next version number and changes.txt its line (rule 5). The Development channel gets a
version only when something the game client runs changed (client Lua, the DLL, or a feature both sides need).

## Rule 0c: copying files to the PC (found 2026-11-15)

device_commit_files can send an OLD copy when the same staged path is committed again after the file changed (seen
twice: upload.ps1 and the lt test mod). Always stage every new version under a new folder in /mnt/user-data/outputs/,
and after every commit check the file on the PC (md5sum through device_bash) before relying on it.

## Rule 0b: code design (owner, 2026-11-15)

Features never build on other features. Code two features both need goes into a shared module in `core/` (as
`core/bag.lua`, `core/items.lua`, the planned `core/spawner.lua` and item database), and each feature uses that module
on its own: no feature calls into or reads another feature's code or data (for example, loot-to-ground uses
`core/bag.lua`'s inventory reading, never the Auto Junk List's `features/loot_filter`). A change to one feature must not
be able to change how another works. Keep the code clean, reusable and well factored, without dependencies between
systems.

## Open: Loot Drop for the game's own monsters (2026-11-15, 0.15.143)

Built as "read the body after the death, move its loot to the ground": does NOT work for normal monsters. The game
fills a body only when it is first opened (ecs program `random_loot_on_interaction`, EMF docs ecs_programs.md and
re_content.md: "fills a container when it is first opened"); FlameKit saw every body empty (some with no inventory).
This was in EMF's docs and should have been checked before building. features/loot_drop.lua stays harmless (it only
removes a body after moving loot out of it). Next route (owner, 2026-11-15 14:14: "can't you just call the same process that pressing 'E' calls"): send
the game's own `LootInteractionEvent {guestId, hostId = body, offerId 0, lootAll 1, bypassInteraction 1}` right after
the death (emf.emits / emf.emit in Lua; EMF's runtime test harvested a plant into a chest with it: the game created
the loot and moved it in the same step, real items). The guest needs an inventory, so the owner must choose first:
(1) guest = the killer: the loot goes straight into their bag as if they pressed E (simplest), or (2) loot into a
hidden temporary container, then drop it on the ground with core/ground_loot.lua (needs a container FlameKit can
spawn: untested). Before building: test that the event works for a monster body; explain the test first (Rule 0).
Feature 1 is NOT dead: only the first way of building it was. Proven parts kept: core/ground_loot.lua (a ground item keeps quality and
level), the test monsters' legendary loot, the Server tab.

## Where things stand (end of the conversation of 2026-11-13..15; the owner starts a new one)

- Versions (2026-11-15 23:40): 0.15.202 on Development, the local server and production (G-Portal); Stable: 0.15.199.
- `C:\enshrouded mod shit\outbox` still holds the 0.15.142 Lua files (from before the owner stopped the G-Portal
  upload): never upload them unless the owner asks for G-Portal; replace them with the right files when he does.
- The Server tab's "Monsters drop their loot on the ground" is ON on the local server (server_settings.json); with
  the current loot_drop.lua it does nothing harmful (bodies are empty when looked at, so none is removed).
- Not yet tried in the game: the test monsters' legendary loot (0.15.142: runes, legendary runes, one legendary
  item). The ground drop itself was proven in game (a legendary sword level 10 came out as given).
- Nightly log fetch (restart helper, 3:55 AM, logs only) first runs on 2026-11-16: check
  `<work folder>\production_stable_logs\emf_core_2026-11-16.log` and a "nightly:" line in restart.log.
- Lessons the owner insisted on (all in the rules above): check the docs and everything checkable before building or
  asking for a test; explain a test before asking for it; full paths in every step; never G-Portal or Stable without
  his word for that version; Development and the local server always together; features never depend on each other;
  stage every file version under a new path and verify md5 on the PC; say plainly what is and is not tested.

## What FlameKit is

One mod suite for Enshrouded by Ninechars, one version number for the whole product. Two parts:

- **The Lua part** (`flamekit/`): the panel and the features. Runs in the player's game (the "client") and on the dedicated server.
- **The native part** (`flamekit_native/src/`, built into `flamekit_native.dll`, mod "FlameKit Native"): all of FlameKit's UI (the F4 FlameKit Menu, the pinned windows, the minimap, the corner lines, the update and About windows), item details, item icons and the updater. Client only, never on a server.

It runs on EMF 0.6.6 (the Enshrouded Modding Framework) with EMF's Lua host. Features: Auto Junk List, Minimap, Party window, Messages and Notices, chat copy, Experimental window (Fast Travel, PvP, test monsters) and options (per player), PvP Leaderboard, Settings, What's New with About, self-update (signed) with the update window.

## How the owner wants the work done (follow these exactly)

**KEY DIRECTIVE: protect personal, sensitive and confidential information.** If anything the owner asks for, or anything about to be done, could leak personal, sensitive or confidential information (into the public GitHub repository, into logs players send, into files shared with anyone), STOP before doing it and warn the owner clearly and forcefully: say exactly what could leak and where, and wait for the owner's decision. This comes before every other rule.

1. **Confirm before changing anything.** Say in a line or two what you are about to change and wait for a yes. Reading logs and files to answer a question needs no confirmation.
2. **A question is a question.** Asking for information is not a request to change something.
3. **Take instructions literally.** Do what was named, nothing wider. No assumptions, no extra options, no "while I'm here".
4. **Be specific.** When asking the owner to check something, say exactly where to look and what the expected result is, the first time.
5. **One version per round of work.** Every time anything changes, the version goes up; one version can hold many changes. Never leave changed code under an old number.
6. **The change log lists everything.** `flamekit/changes.txt` gets a line for every change in every version. Nothing is trimmed, merged or hidden. Format: a line `0.15.8 Nov 13, 2026`, then `- ` lines, then an empty line; newest first.
7. **Test the way production works.** Nothing is copied onto the owner's client by hand. New versions reach the client only through the updater.
8. **NEVER push to Stable without the owner's explicit approval of that exact version** (owner, 2026-11-14, after 0.15.131 was released unasked). Ask, and wait for a clear yes for that version; a complaint, a question or "fix that for stable" is not a yes. `dist` (the players' channel, Stable) gets a new version only then; every other version goes to `dist-test` only. First release: 0.15.124 (2026-11-14, owner).
8a. **Compatibility check before every publish** (owner, 2026-11-14): for each change, ask "does an older server still work with the new game, and an older game with the new server?" and say the answer in the summary to the owner. A change that breaks the older side raises `kit.MIN_SERVER` or `kit.MIN_GAME` (core/kit.lua), gets a line in "Compatibility" below, and is rolled out server first, then games; the owner hears about it before anything is published. Add new message fields so the older side can ignore them; never change an existing channel's format or `version` without that.
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
    - Then ask: "Shall I restart <the game client / the local server / both> now?" On a yes, do the whole restart yourself with the **restart helper** (never computer use: the owner does not want his mouse and keyboard taken over): write the one word `client`, `server` or `both` into `<work folder>\restart_helper\restart.request` (copy from a fresh folder each time), wait for `restart.done` (`ok ...` / `failed ...`) and read `restart.log`, then check in FlameKit's log that the new version runs. The helper (`tools/restart_helper/` in this repository; `restart_paths.txt` with the server folder is on the PC only) runs in its own window, `restart_watch.cmd`, which the owner starts: the client is closed like Alt+F4 and started through Steam (app 1203620), a server restart always closes the client first (no player connected), then writes a number into the server's `emf\mods\flamekit\save_now.request`; `features/server_save.lua` on the server calls `emf.request_save()` and answers in `save_now.done`; once a save file newer than the request exists the helper ends the server process (Ctrl+C from another program did not work: tried twice on 2026-11-13, the server ignored it), starts it again minimized, waits for "world loaded" in `emf\emf_core.log`, then starts the client. No new save within 90 s: nothing is stopped. The client is never ended by force. The helper restarts itself when `restart_helper.ps1` changes (exit code 10, `restart_watch.cmd` loops). Joining the server stays a click for the owner. Before asking for a server restart, check whether EMF already reloaded the Lua files on the running server (it does on file change). Never restart anything without that yes. Production server by FTP (2026-11-14, owner; G-Portal cannot make a limited FTP user): the FTP tool (`tools/ftp_tool/`) lives in `<work folder>\release\FlameKit FTP tool` (owner, 2026-11-15: "direct access to upload to the production FTP folder"), with its own ftp.txt and the password in ftp_password.dat (DPAPI, the owner's Windows user). **Never open, stage or copy ftp.txt or ftp_password.dat.** Claude uploads by writing `upload` into restart.request: the helper runs the tool's upload.ps1 and logs its output in restart.log. **Every publish goes to the Development channel and the local server. They are one step: never copy to the local server alone as a shortcut (owner, 2026-11-15 14:02: "its part of the same workflow"). The production server (G-Portal upload) and the Stable channel only when the owner names them for that version** (owner, 2026-11-15 13:51, replacing 08:38's "always"). Earlier rule, kept for history: **Every publish goes to: the Development channel, the local server and the production server (G-Portal upload), always** (owner, 2026-11-15 08:38: "a lot of testing happens on that server that I cannot do locally"). **The Stable channel (the players' game updates) only when the owner says so for that version.** So production often runs newer Lua than Stable players' games: before every publish check (rule 8a) that the server change works with the Stable game version; if it needs a newer game (raise kit.MIN_GAME), stop and ask the owner first. **Design rule (owner, 2026-11-15: "shit needs to be backwards compatible as much as possible"): a server change must work with the Stable game, always.** New message fields are added so an older game ignores them, a new feature degrades to the old behaviour with an older game, nothing is renamed or removed that an older game still sends or reads. Raising kit.MIN_GAME is a last resort, only with the owner's explicit yes. **Always fill the outbox with every publish, without asking** (owner, 2026-11-15: "always put the files in the outbox"). Only the files that changed since the version the production server runs, mod.json last (owner, 2026-11-15: 25 files for 4 changes was too many). Claude only puts the files for the server's FlameKit folder in `<work folder>\outbox\` (same layout as emf\mods\flamekit, mod.json included) and tells the owner; the owner double-clicks upload.cmd, which uploads them (mod.json last, then removes them from the outbox) and fetches the server's log into `<work folder>\production_stable_logs\emf_core.log` for Claude to check. Since 2026-11-15 the restart helper has the `upload` request (it only starts the FTP tool). `ftplist` also writes the FTP's file list to `<work folder>\production_stable_logs\ftp_list.txt`. Every upload fetches into `<work folder>\production_stable_logs\` (owner, 2026-11-15; before: outbox\server_log): emf_core.log, emf_loader.log, enshrouded_server.log, eml.log (the other loader, EML), `backup\enshrouded_server_<time>.log` (the game server log of the run before the last restart; G-Portal restarts the server every night at about 04:10 server time) and the newest `crash_dumps\...\enshrouded_server.dmp` (none since 2026-10-26, before FlameKit). **emf_core.log has no backup on the server**: after a restart, the EMF log of the run before is gone unless fetched before it. So (owner, 2026-11-15) the restart helper fetches the logs every night at 3:55 PC time (Chicago, the same clock as the server's emf_core.log; the server restarts at about 4:10) with upload.ps1 -LogsOnly (never uploads) and keeps `emf_core_<date>.log`; it needs the PC on and the helper window open. Steam's own logs (stats_log, connection_log*, system*.txt) are not fetched: nothing about the game.
17. **A chime when waiting for the owner** (owner: ADHD, multitasking): at the end of every turn that waits for the owner's answer or test, copy a file `chime.request` (any content) into `<work folder>\restart_helper\`; the restart helper plays a chime on the PC and deletes the file. Always, every such turn: the owner asked for it.
18. **Be specific and clear** (owner, 0.15.36). The owner wants to understand how FlameKit works inside and points out flawed designs: never hold technical details back or talk down. Technical terms are fine; vague ones are not. When describing a change, say concretely what it does: which file, which function, which data goes where, what the owner will see in the game, and a concrete example when an idea is new (e.g. the actual row a feature would write). A sentence the owner cannot picture is a failure: rewrite it until it names the real thing.
19. **Know EMF before building around it** (owner, 0.15.48: "it's critical you understand everything that is available to us"). Before building a workaround, guessing game data, or writing "EMF cannot do X", look it up in `flamekit_native/notes/EMF_API.md` and EMF's own docs (`docs/modding/lua.md`, `llms.txt`, `reference.md` in the EMF zip on the owner's PC), and name the line that says so. Also search FlameKit's own code for the call first: the 1-64 player scan (0.15.21-0.15.47) was written while `experimental.lua` already used EMF's player events.
20. **No account ids in logs** (0.15.49). A player's account (`world:account`, `p.account`: likely their Steam id) never goes into a log line; use the entity id. Logs get shared with bug reports.

## Where everything is

Folder names on the owner's PC are not in this repository (it is public). `<work folder>`, `<game folder>` and `<server folder>` below are listed in `LOCAL_PATHS.md` next to HANDOFF.md on the owner's PC (never pushed).

- **GitHub:** `9chars/FlameKit` (public). Source, notes, tools, and the update channels. The Claude GitHub App is installed on it; pushing works.
  - `dist-test/`: development versions. The owner's PC downloads from here (it has `emf\mods\flamekit\update_channel.txt` containing `test`). Since 0.15.124 any player can pick it: Experimental tab → Debug → Updates: Stable / Development (experimental.lua `dbg:chan:*` writes the file, "test" or "stable", and `ui_update_check.request`, which the DLL's HudLayer turns into an update look at once).
  - `dist/`: players' versions (Stable). Since 0.15.124. A release: `dist` = a copy of a `dist-test` version that was tried (update.txt does not name its channel, so the same update.sig is good for both; `tools/check_sig.py dist`).
  - Release packages (on the owner's PC, `<work folder>\release\`, never in the repository): `FlameKit-<v>.zip` for players (the 0.14.2 package's EMF 0.6.6 + Lua host, with `flamekit` and `flamekit_native`; its `install.ps1` has `Remove-OldFlameKit`: it deletes `emf\mods\flamekit_map`, `emf\mods\flamekit_native`, `emf\flamekit_update` and every file in `emf\mods\flamekit` but the player's `.json` files other than mod.json, `ui_layout.txt`, `update_channel.txt`, `debug.txt` and `logs\`) and `FlameKit-<v>-server-mod.zip` (the `flamekit` folder and SERVER-README.txt with the manual steps for G-Portal). The package's own texts are in `tools/release/` (install.ps1 = EMF 0.6.6's with `Remove-OldFlameKit`, README.txt, SERVER-README.txt; change the version in the READMEs). A new package: the last one, with `game\emf\mods\flamekit` and `flamekit_native` replaced by the release's `dist` folders. Tested 2026-11-14 with the restart helper's `installold`/`installnew` (a fake server folder `restart_helper\installtest\game`): 0.14.2, then 0.15.124 over it with seeded data: flamekit_map, the old files, the .old DLL and a held update gone; junk list, layout, channel and logs kept.
- **Owner's PC working copies:** `<work folder>\flamekit` (Lua), `<work folder>\flamekit_native` (C++: `src\`, `build.cmd`, `notes\`).
- **Client install:** `<game folder>\emf\mods\{lua, flamekit, flamekit_native}`.
- **Local dedicated server:** `<server folder>\emf\mods\{lua, flamekit}`.
- **Production server:** G-Portal, last given 0.14.1/0.14.2 by the owner. Upload only when asked.
- **Logs:** `emf\emf_core.log` in the client and in the server folder.

Runtime files that are never deployed, diffed or overwritten (all in `emf\mods\flamekit\` unless said): `junk_list.json`, `seen_version.json`, `far_players.dat`, `experimental.json` (server), `leaderboard.json` (server), `item_details.dat`, `update_status.txt`, `update_channel.txt`, `debug.txt`, `logs\`; the Lua → DLL files `ui_list.dat`, `ui_tabs.dat`, `ui_exp.dat`, `ui_hud.dat`, `ui_messages.dat`, `ui_notices.dat`, `ui_party.dat`, `ui_board.dat`, `ui_open.dat`; the DLL → Lua file `ui_actions.txt`; the DLL's own `ui_layout.txt`; one-shot requests `ui_board_toggle.request`, `ui_open_logs.request`, `save_now.request`/`save_now.done` (server); the Restart Game script `restart_game.ps1` and its `restart_game.log`.

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

Since 0.15.20 it reads the newest commit from `github.com/9chars/FlameKit.git/info/refs` (not cached) and downloads from `raw.githubusercontent.com/9chars/FlameKit/<commit>/...` (immutable); falls back to main. Every 60 s on both channels (players every 10 min until 0.15.130), plus the "Check for updates" button in What's New. Since 0.15.39 it keeps checking while an update waits: a newer one replaces the waiting one (`held_version`, `clear_pending`; the DLL: if `flamekit_native.dll.old` cannot be deleted it is the running DLL, so the waiting `flamekit_native.dll` is overwritten). Since 0.15.45 the list must be signed: `update.sig` next to `update.txt`, ECDSA P-256 over SHA-256, checked with Windows bcrypt against `kReleaseKey` (`signed_by_release_key`); missing or wrong: log `update: REFUSED: ...`, status `failed|An update was refused: it is not signed by FlameKit`, nothing downloaded. Since 0.15.47 a failed/refused status clears once a later check is fine.

**Signing key:** "FlameKit release signing", ECDSA P-256, in the owner's Windows user key store, not exportable (restart helper `keygen`, 2026-11-13). Only the public key is in the repository (`web_update.hpp` `kReleaseKey`, `tools/check_sig.py`). If the owner's PC or Windows account is lost, no update can be signed again: a new key needs a new DLL, which players must install by hand.

**Proven in the owner's game:** download and install from `dist-test` (0.15.10); holding the Lua part to the next start; replacing a waiting Lua part (0.15.40 → 0.15.41) and a waiting DLL while the old one runs (0.15.45 → 0.15.46: `v0.15.46 replaces v0.15.45`); a signed list accepted (0.15.46, 0.15.47); a tampered list refused (`update.txt` changed to 0.15.47 with the 0.15.46 signature: `REFUSED ... the signature does not match`, nothing changed). The old updater through the game server is gone since 0.15.9.
**Not yet tested:** a clean PC installing from scratch in a real game folder, and a game updating from `dist` (the first release is 0.15.124: the first update from `dist` comes with the next release).

## State right now

- **Versions:** see the line at the top. The owner's client and the local server follow every version through dist-test. Players were on 0.14.2 (no updater) until the 0.15.124 release package; from it on, their games update from `dist`.
- Every version's detail is in `flamekit/changes.txt` and the git log. Below: how things are built, so new work fits.

## Design (how FlameKit is built)

**Bridge between Lua and the DLL** (rule 13; one writer per file, all in `emf\mods\flamekit\`):
- Lua → DLL: `ui_list.dat` (Auto Junk List: `O` options line; `P <clickkey> <lit> <label>\t<tooltip>` option buttons; `B`/`J` item tiles, tab-separated `B\t<id hex>\t<count>\t<debug>\t<rarity>\t<level>\t<type>\t<name>`), `ui_tabs.dat` (other tabs: rows of kind h heading, t text, b button, s separator, i item tile with 6 more fields), `ui_hud.dat` (label; `notice <text>` drawn orange under it), `ui_messages.dat` (`m <n> <rrggbb> <text>`, last 20; from `kit.note`), `ui_notices.dat` (`n <tag> <rrggbb> <text>`; from `kit.notice(tag, text, colour)`, `kit.notice(tag)` takes it back; since 0.15.54), `ui_party.dat` (`p <you> <hp> <hpmax> <mana> <manamax> <level> <x> <z> <name>`), `ui_open.dat` (open the window on this tab; the DLL deletes it).
- DLL → Lua: `ui_actions.txt`, numbered lines, never replayed: `junk`, `keep`, `dump`, `auto`, `action`, `view <id>`, `tab <id>/<generation>/<button>`, `key <name>` (a key pressed in the window, to the shown tab's `key(world, name)`), `opt <clickkey>`.
- Also Lua → DLL: `ui_exp.dat` (the Experimental window's rows), `ui_board.dat` (the PvP Leaderboard), `ui_notices.dat`, `ui_party.dat`, `ui_messages.dat`, `far_players.dat`. And two one-shot request files, each written by a Lua click and deleted by the DLL when it acts: `ui_board_toggle.request` (show or hide the Leaderboard, BoardLayer) and `ui_open_logs.request` (Explorer on the logs, HudLayer). Two styles (owner asked, 0.15.112): a `.dat` file is state the DLL draws, a `.request` file is a one-time action. Both are fine; new work picks the one that fits.
- DLL only: `ui_layout.txt` (place and size of each window, 7 fields incl. height).

**DLL UI** (`flamekit_native.cpp`, `ui_thread`): one overlay window, plain BGRA surface (keep the Vulkan presenter path open), layers in this order: hud, backdrop, minimap, party, messages, notices, experimental, board, window, about, update dialog. The overlay is owned by the game's window (0.15.94: owned windows stay in front of their owner; the topmost setting alone did not hold on the main screen); the watchdog checks 4×/s and logs.
- `WindowLayer` (F4 by default since 0.15.63, owner: players know F4 from the old versions; F6 in 0.15.26-0.15.62; setting `window_key`): title bar, frame, move, resize (min 560×440); tabs wrap; sizes are members set by `lay_out()`. Tab order from `main.lua`, What's New first; it opens by itself on What's New after an update (or every game with `open_on_start`). Auto Junk List has its own icon view (pages); every other tab is rows from `ui_tabs.dat` with a scroll bar. Another program in front does not close it (`lost_front`).
- **Build mode** (0.15.59, owner: declutter while building; setting `ui_hide_build`, group "Windows", switched in the F4 menu → Windows since 0.15.62, default on): kit.lua reads `ClientPlayerInput.data.mask` of the player in the client world: its two low bits (most likely the two building cursors) are set (3) exactly while the building tool is out, 0 or 256 otherwise (measured 0.15.62, two rounds). Not the cursor position: it stays where it was after build mode ends (0.15.61: FlameKit stayed hidden) and writes `build 1` into `ui_hud.dat`; the DLL (`g_build_hide`) hides every layer whose `stays_in_build()` is false. **Owner's rule (0.15.61): ALL FlameKit UI on screen hides in build mode**, the lower left lines too, and every new window does so by default; only `WindowLayer` and `BackdropLayer` (the F4 menu, opened on purpose; the update and About windows too) opt out, and a future feature made for build mode may opt out (`stays_in_build`). The compositor uses `Layer::shown()`, never `visible` alone.
- `NoticeLayer` (0.15.54, owner: the Auto-Collect warning got lost in Messages): warnings that stay until the feature takes them back. A `PinnedLayer` with `headless` (no title bar, `kHead` 0): dragged anywhere and sized at its corner in pointer mode; shown only while there is a notice; hidden in menus. Rule: a warning about a state that lasts (a setting conflict) is a notice, not a message.
- `PinnedLayer` (party, messages, notices, experimental, board): stay on screen while playing, collapse/hide, move, resize (height = maximum, content scrolls; `fixed_height` keeps the given height: messages; `fit_height` always fits the content: notices), `content_click`, `hide_in_menus` (all of them hide in the game's menus since 0.15.107), `default_hidden` (the board: hidden until shown, decided before its layout entry exists, 0.15.112), first places from `def_x_pm`/`def_y_pm`, `def_center` or `def_right_px`. They take the mouse only in pointer mode.
- Pointer mode (`g_pointer_mode`): one of the windows in `g_ui_modal` open (the F4 menu, the update window, the About window: the one list, set in ui_thread_body; the backdrop reads it too), or the pointer key held (`pointer_key`: Right Alt default, Right Ctrl, Caps Lock; `g_pointer_hold`). The pointer returns to where it was last time. The game's own pointer is copied from Windows (`look_for_game_cursor`: only a colour pointer with its hot spot in the top left quarter; the real one is 64×64, hot spot 3,3). `Frame::in_menu`: the game shows its own pointer outside pointer mode.
- Party window buffs (0.15.49): the server half reads `emf.buffs` per player (types the game hides left out) and sends `b <type hex>:<slot>:<seconds>,...` after each `p` line; each player's game adds the names (`emf.buff_type`, its own language) and writes one `b <type hex> <slot> <seconds> <name>` line per buff into `ui_party.dat`. `PartyLayer` draws the buffs on the name line, behind the name (0.15.52, owner: the extra row made the window too long): 30 px badges since 0.15.54 (slot colour, the game's icon from `game_files().buff_icon`, the time left inside on a dark outline; debuffs first; a player with buffs is `kBuffExtra` 10 px taller), as many as fit before the level, the last one "+N" when more; name, kind and exact time in a tooltip on hover (pointer mode, `PinnedLayer::content_hover`, `spots`). Buff icons: `item_icons.hpp` (buff registry layout there). `game_files()` is the one shared reader of the game's data files (UI thread).
- FlameKit's own raw memory reads (`peek`: map markers, names, quest marks; and the item-definition offsets) run only on game build 1287369 (`kLayoutsBuild`, `g_layouts_ok` from `emf::game_build()`); another build logs `FlameKit's own memory reads are OFF`.
- Tests: the Auto Junk List is tested through what FlameKit's window really uses (`junk_view()` in run.lua reads `ui_list.dat`, clicks go through `ui_actions.txt`); the old EMF-panel tests are gone. Other tabs are still driven through their `panel` rows (`toggle_panel`).
- **Updates and new settings** (0.15.61): EMF reads FlameKit's `mod.json` (its settings) before FlameKit Native loads and puts a held Lua part in place, so a setting a new version adds did not exist until the second start (it read as off). After installing, the DLL touches `flamekit\mod.json` 8 s later (`install_pending` returns true); EMF's watcher then reads the settings again and reloads the Lua part. Log: `update: flamekit\mod.json touched`.
- Item tiles are a standard element: Lua `kit.items.tip(id, debug_name)`; a panel row `{ item = <id>, count, text, tooltip, button, selected }`; DLL `ItemTip` + `draw_item_tip()`. Use them for any item UI.
- Tooltips: every button whose use is not obvious gets one; a paragraph starting with `WindowLayer::kRedLine` (`L'\x01'`) is red. UI text stays short; tooltips may explain.
- PvP (0.15.65, Experimental switch `pvp`, session only, never saved): the server gives a player with PvP on `Faction` 1 (HitAll, enemy of everything: EMF `engine_parts/combat.md` 1.2), written again every step; off: back to 7. While anyone has PvP on, each player without it gets two hit rules (`from players, to them, cancel` and `from them, to players, cancel`) (until 0.15.127 one more rule scaled player-on-player hits to 25%; owner, 0.15.128: full damage, the rule is gone). Since 0.15.130 (owner) each PvP player has `pvp_obj` `{from = them, to = "objects", cancel = true}`: their hits never damage buildings or placed objects. Unknown: whether EMF's "objects" also covers trees, ore and loot jars (then a PvP player cannot harvest them while PvP is on). Since 0.15.132 (owner: pets and farm birds took PvP damage) `guard_pets`: every 120 steps while anyone has PvP on, each pet (IsTame), farm animal (faction 12) and non-villager ally (11 without NpcState) within 40 m of a PvP player gets `{from = "players", to = it, cancel = true}`, at most 24 (`PET_MAX`); wild animals stay huntable. A player without PvP found with faction 1 is put back to 7 within 60 steps (leftover from a crash or reload: the faction is saved with the world). Untested with two players; the risk: some attacks may skip players for other reasons, and a HitAll player can hurt their own summons, pets and villagers. Rule budget: 2 per non-PvP player while PvP is in use (EMF allows 64).
- PvP holds the other options off (0.15.118, owner: no cheating): experimental.lua `PVP_KEEPS` (fly, pvp). `wants()` is what the player switched (saved as before), `is_on()` = wants and not `held_by_pvp()`, so the hit rules, the shroud timer and stamina all drop while PvP is on and come back after. The view marks held ones `<key>_pvp`: the Experimental tab greys them out ("(off in PvP)"); a set for a held option is refused (server and client). Fast travel too (0.15.119): `home`/`go`/`wp` are refused while `wants(account, "pvp")`, the window greys the three buttons. Test monsters too: the drop-downs, level buttons and spawn buttons are greyed out (0.15.120: the Experimental window draws a disabled drop-down grey and never opens it), a `body` spawn (dummy or duel) is refused in PvP (Remove still works), and switching PvP on removes the player's duelist; the dummy stays (it never does damage, and it is how players test PvP weapons).
- PvP and monsters (0.15.67): measured with the duelist: a faction-1 player is noticed but never attacked by enemy AI (the target picker `enemy_combat_targets` takes player-side targets only); with PvP off it attacked at once. A PvP player's hit on the faction-7 dummy did kill it (PvP hits land). Fix: `pvp_aggro` every 120 steps sends `AddThreatTargetEvent {attackerId = monster, targetId = PvP player, threatValue = 100}` to each enemy-AI entity (DynamicEnemy01BehaviorState, faction not 7/8/11, alive) within 20 m; `emf.emits` in experimental's setup, so the server needs a restart for it (not a reload).
- PvP and villagers (owner, 2026-11-14, 0.15.70): a player with PvP on could not kill a villager (summoned): villagers take no hits from a HitAll player. Summons and pets with PvP on: not tried yet.
- PvP and monsters, solved (0.15.68, measured with the duelist and FlameKit's AI log lines): AddThreatTargetEvent alone: target stays 0, Idle/Roaming. Writing `SelectedTargets.targets[1]` (target and root id, changeCounter+1): target 1 but still no Combat. Also putting the player in a `DynamicAggro` slot as Alarmed (state 3) with `faction` 7 and aggro 100 (`alarm`, every step for the monsters found within 20 m every 120 steps): Combat (state 6) within 1 s, attacks. The monster's threat slot's faction is what the AI checks. Body log lines: AI state, target and threat table when state or target change.
- PvP threat (0.15.69, owner: several PvP players): every PvP player within 20 m gets their own free slot in the monster's `DynamicAggro` (Alarmed, faction 7, start aggro 100 - 3/m, at least 40; afterwards only a floor of 20), no forced `SelectedTargets` any more. Measured with `flamekit.pvptest 1` (server console via `emf\commands.txt`): the duelist went to Combat with target 1 within 1 s from the slot alone. `flamekit.pvptest off` undoes it.
- Duelist choice (0.15.70): `DUELISTS` in experimental.lua (Vukah d5d05217, brawler 9c8e2008, skeleton b3e66f3b, wolf 478381c5, boar 255fd8d9, sabretooth 50b96064, hound 87575915; from EMF's raids/champion/necromancer/beastmaster mods); level 1-255 via `set_level`; all seven attacked the owner in game (2026-11-14). A full monster list needs template GUIDs: EMF's guid_dump EML mod writes `export/template_guids.csv` (12,266 templates); it is in EMF-0.6.6-source.zip (GitHub releases), not in EMF-0.6.6.zip. The tab's pick is client-side (`duel_what`, `duel_level`), sent with op `body` as `what` and `level`.
- Monster list (0.15.72): `core/monsters.lua`, generated once from `enshrouded.kfc_resources` (build 1287369) with a Python reader of the same layout as item_icons.hpp: `TemplateResource` = type 0x39768775 (12,269 records, part 0), +0 name offset/length, +16 component list offset/count (12 bytes: hash, data offset from the entry's +4, size); kept: Enemy01BehaviorState (0x52487b01) and a Faction (0xa1f30f21) byte of 2-6, 9, 10, 13-15, without Base_/test/sleep/dungeon/patrol/summon-stone copies: 189. Regenerate after a game update with the scripts in `claude_scratch\tpl` (kfc.py, list2.py, curate.py) on the PC. The server spawns only GUIDs on the list.
- Creature levels (measured 2026-11-14 with `flamekit.duelist 1 <level>`, the Vukah duelist): 1 = 119 health, 50 = 6692, 75 = 20760, 100 = 53084; every level from 150 to 100000 came out as level 105 with 62687 health: the game's top is 105, it clamps anything higher, no harm seen. FlameKit's cap is 100 (owner, 0.15.78: a round number).
- Chat colours (0.15.82, owner; 0.15.112): a player's chat line goes into ui_messages.dat as `p <n> <name>\t<text>` and the DLL colours it with `player_style(name)`, the one place player colours are worked out (Party, minimap, chat).
- 0.15.81 (owner): window titles carry their key (`key_label`, PinnedLayer `hotkey()`); `party_window_key` (default F7, `g_party_toggle`); the dummy is any monster from its own drop-down (`dummy_of`, `DUMMY_PLAIN` first), given faction 7 at spawn and every 30 steps (`DUMMY_FACTION`): a player-faction enemy body hits for 0 (EMF re_companions.md).
- 0.15.79 (owner): F4 toggles the window (WindowLayer: `want_toggle`, a second sighting within 400 ms is the same press: the key comes both as the window's own key message and the game thread's key check). `pointer_toggle` setting: the main loop flips `hold` on each press of the pointer key (0.15.80: the press from the raw key state, at least 250 ms apart: the front changing when the pointer goes away looked like a new press), Esc or leaving the world or the front ends it. Dummy at MAX_LEVEL. Hover name: own small painter, above the marker.
- Minimap hover names (0.15.77, owner): MinimapLayer keeps the pointer's place (mouse moves come only in pointer mode) and `draw_hover_name` draws the nearest marker's name (within 14 px, `nearest()`, shared with the click) in a dark box with a gold edge after the dial.
- Chat (0.15.76, owner, features/chat.lua): the server reads players' chat (`emf.on_chat`, read only, the game still shows it) and sends "<name>: <text>" on channel `chat` (to players) to every FlameKit game's Messages window; FlameKit's announcements (`require("features.chat").announce(world, text[, "#rrggbb"])`, 0.15.121: an optional colour; PvP on is "<name> joined PvP!", off "<name> has left PvP." (0.15.122), both orange) go only there now, never `emf.broadcast` (owner: no FlameKit lines in the game's chat). The Notices window is not touched. `emf.tell` stays only as the junk list's fallback for players without FlameKit.
- **EMF's 250 ms rule** (production, 2026-11-14 21:55): one Lua call that runs over 250 ms pauses ALL of FlameKit on that side ("the script ran longer than 250 ms ... paused until one of its files changes"): the Party list and everything else stop until a FlameKit file changes or the server restarts; a reconnect does not help. It happened with 100 duelists: guard_duelists checked every entity against every duelist, and the production world has about 37,500 entities (enshrouded_server.log `[ecss] Stats ... Ent:37,567`; the server logged `Bad Performance ... peak: 275,840 us` at that moment). 0.15.137: test monsters have no protections at all any more (owner: no pet, animal or building rules; only PvP protects pets), so no world scan for them; spawns 20 per step (`spawn_queue`, `spawn_tick`), no per-monster log lines or AI logging with more than 5, and every scan over `world:entities()` (guard_pets, pvp_aggro, remove_all) stops after `SCAN_BUDGET` (60 ms, os.clock) and goes on later (remove_all resumes from where it stopped: `remove_left`). Rule for new code: never loop over all entities in one call without the budget; never nest such a loop.
- **Many monsters, measured on production (2026-11-15, 0.15.139):** 200 random (non-boss) fighting monsters: server steps ~66 ms of 16.7 (peaks 126 ms), the server at ~40% speed (`[ecss] Stats Upd:1,520` a minute instead of 3,600); 200 level-1 Vukahs only ~17 ms. 500 and 1000 random spawned without a FlameKit pause; the server log for them was not fetched yet. 0.15.140 (owner): with more than 5 test monsters no per-monster log lines at all (kills, bodies, out of sight: one summary line per check; Remove: one line).
- **5000 at once (owner, 2026-11-15 02:04, 0.15.140 on production):** "crushed the server, really bad rubberbanding". The logs of that test were not fetched yet. Owner: the cap comes back down, but only after more tests on the morning of 2026-11-15; 2026-11-15 07:19 owner: cap back to 1000, 5000 button removed (0.15.141, with the seen_alive fix). Measured (logs fetched 02:16; emf_core.log time = enshrouded_server.log time - about 1:56:30): 5000 random: server steps ~165 ms (10x the 16.7 budget, peaks 283 ms), 6 steps a second (`Upd:362` a minute), Ent 66k; FlameKit at most 60 ms in a step (no 250 ms pause), Remove took 4149 in one go (01:59:38). 1000 random: steps 50 ms at first, then 28-40 ms for 10 minutes (the server at 30-50% speed). Ground snap under that load: 477 teleports not moved within 10 s (EMF's watchdog took them back). Found: the first 20 of every big spawn counted as "killed" 0.3 s after the spawn and their (living) bodies removed 8 s later: a fresh creature reads as dead until its health is set; fixed in 0.15.141 (`seen_alive`), not published. Old note: next time read the fetched logs of that test first (Bad Performance, [ecss] Stats, any FlameKit "slow:" or 250 ms line, the Remove summary, ground snap), then ask the owner for the new cap.
- **Plan for any future feature that spawns many monsters (owner asked, 2026-11-15: "will I have to request all those things again?" Answer: no):** do not copy the test-monster code. First move the reusable parts out of `features/experimental.lua` into a shared `core/spawner.lua` (spawn queue N per step, tracking what it spawned, dead-body removal after CORPSE_S, the resumable budgeted world scan, summary logging), use it from both the test monsters and the new feature, and keep to the 250 ms rule above. Test-only stays in experimental.lua: the 0.999 scale tag, Remove-all-test-monsters, the calm dummy, Random without bosses. The owner must not have to ask for any of these again.
- 0.15.136 (owner): the kill notice is red and stays 120 s (chat.lua clamps a notice to 300 s). The level stepper (< >) is gone: only the picks 1/25/50/75/100. "Quantity" (was "How many") 1, 15, 50, 100, 200 (`MAX_DUELISTS` 200). Remove: `remove_all` destroys the player's own test monsters wherever they are (a body out of sight is kept, no longer forgotten) and every test monster nobody keeps (`is_test_monster`: spawned with ScaleComponent `TAG_SCALE` 0.999; older: a creature with faction 1, a dead one with 7; never one with an account). Dying with PvP on ends PvP, cool-down or not (`emf.on_player_died` in experimental's setup, free-for-all only: `PVP_MODE` "ffa"); "<name> has left PvP." only when no player killed them (else the kill line says it). EMF: died needs the call in the first run, so this needs a server restart, not a reload. The cool-down counts only damage (amount > 0, or a blocked or parried attack); heals, buffs and regeneration do not.
- 0.15.134 (owner): the kill line is "<killer> brutally murdered <victim> in PvP." in red (`chat.announce(world, text, colour, {colour, seconds})`: the notice part is a short kit.notice "announce_<n>" in everyone's Notices window, orange, 30 s, each its own so several stack). PvP cool-down: `emf.on_hit` (experimental setup) stamps `pvp_hit_at` on a PvP player hit by another PvP player; switching PvP off is refused for `PVP_LOCK_S` (60) s after it; the Party list carries `v\tlock\t<s>` after `v\tpvp` (party.lua, `F.pvp_lock_left`) and the DLL draws "PvP 42s". Leaving the server still ends PvP (owner: fine). The dummy has faction 3 (the monsters') and a rule `{from = it, cancel = true}`: anyone can hit it, it hurts nobody (`OLD_DUMMY_FACTION` 7 only for sweeping old corpses). Duelists: "How many" 1, 5, 10, 20, 50 (0.15.135, `DUEL_COUNTS`, `MAX_DUELISTS` 50, msg `count`), rows of 10, 2 m apart; buttons "Spawn Monsters" and "Spawn Dummy". The shield is shared (`guard_duelists`, `duel_guard`): while any duelist lives one rule `{from = "creatures", to = "objects", cancel}` and one per protected animal within 40 m of any duelist `{from = "creatures", to = it, cancel}`, at most 30: wild monsters near them cannot hurt buildings or animals meanwhile either.
- Dead test monsters (0.15.126, owner, production): a killed duelist's body could not be looted and never went away (inside a flame altar's area), and Remove was greyed out (`bodies` forgot it at the kill, without destroying it). Now a killed body is destroyed `CORPSE_S` (8) s later (`b.dead_at`, the owner is told via `tell_player`); Remove is always enabled and also runs `sweep_corpses`: dead (NetworkHealth 0) entities within `CORPSE_R` (15) m of the player with faction 1 or 7 and no account (the game's monsters never have those factions; players have an account) are destroyed. Untested in game.
- Map Waypoint on a dedicated server (0.15.125, production log 2026-11-14): with `ground = true` the game's ground search never finished for moves of a few hundred metres (EMF: "still has a Teleport 10 s after EMF's push: it is removed"; the player frozen 10 s, a click meanwhile refused: "already under way"). Likely: the destination's path grid is not loaded on a dedicated server far from players. And minimap waypoints carried the player's own height. Now the minimap click sends the marker's height ("wp x,y,z"; entity markers: their transform; the player's own map pins: +0x08 of the MapMarkerRegistry node, **unverified**, used only when -1000..5000 and not 0); the server keeps it (`wp_known`); a move over 64 m (`NEAR_M`) to a known height goes straight there, 1.5 m above, without the ground search; a ground search that gives up is retried that way (`retry`, 30 steps later, after EMF's watchdog took its Teleport); unknown height and given up: the player is told. One move per player (`moving`, 15 s at most). Since 0.15.133 (production log: a game-map waypoint had height 808 with the player at 945) any waypoint with a height other than 0 counts as known, from the game's map too. Player-facing lines from a teleport answer: `tell_player`. Untested in game. (0.15.127, owner) A minimap click on an undiscovered place (state < 2, the "?" ones) sets no waypoint: `wp undiscovered`, a Messages line. A waypoint set in the game's own map is not checked (its discovery is not known there).
- Minimap clicks (0.15.75, owner): with the pointer out, a press and release within 4 px is a click (a move is a drag, as before). The nearest marker within 14 px: `g_act("wp", "x,z")` (or "clear" when the waypoint is within 3 m of it) -> native_ui -> experimental `F.minimap_waypoint` -> op `setwp`/`clearwp` -> the server writes the player's `PlayerWaypoint` (enabled, position in 1/2^32 m; y = the player's height, the marker's is not known). Not yet seen in game: whether the game's `player_waypoint_selection` program overwrites a server-written waypoint. `map_shape` circle/square: draw_dial measures distance as max(|dx|,|dy|) for the square.
- Experimental window (0.15.74, owner): `ExperimentalLayer` (a PinnedLayer, id `experimental`, shown by default, hidden in menus and build mode, key `exp_window_key` default F6 via `g_exp_toggle`) draws the rows of experimental.lua `F.window_rows` from `ui_exp.dat` (`gen <n>`, `r` lines as ui_tabs.dat, `end`; native_ui.lua `write_exp`, every 10 steps and after a click). Clicks: `exp <gen>/<n>` in ui_actions.txt through WindowLayer::act. The drop-down's list opens inside the window, which grows while it is open. Order (owner): Fast Travel, PvP, test monsters. The F4 Experimental tab keeps the other switches and Debug.
- Window controls (0.15.73): a row may be a drop-down (`options = { {heading = true, text}, {key, text, color, selected} }`, its `text` the chosen entry; ui_tabs.dat kind d, entries as extra fields joined by \31) or a label among buttons (`label = true`, kind l). The DLL draws the list under (or over) the drop-down, up to 14 entries, wheel scrolls it, a click on an entry comes back as a row button.
- PvP test bodies (0.15.66, Experimental Debug, op `body` on channel exp): dummy `FakePlayer_Vukah_Melee` (faction 7, 0 damage) and duelist `Enemy_Vukah_Melee` with faction 1 (rewritten every 30 steps), one per player, 3 m in front. Owner: the duelist may hurt everything but pets and animals, never buildings: rule `from duelist, to objects, cancel` plus, every 180 steps, a rule per animal/pet within 40 m (Wildlife/Animal/IsTame, faction 5/6/12, or 11 without NpcState), at most 40. Villagers are fair game (owner). Not saved; gone on Remove, death, reload or the owner leaving. Unknown: whether a spawned Vukah despawns after a while (EMF saw a hostile vanish within a minute).
- Messages window: every message FlameKit sends the player (`kit.note`, always shown since 0.15.106: no setting), except persistent notices, which go to the notices window (`kit.notice`) (owner, 0.15.64). Last 5, 10 in pointer mode, all (up to 100) once the player sized it.

**Features (Lua):** settings live only in their own feature's tab; the Settings tab (`features/settings.lua`, from mod.json) shows only the FlameKit groups and each feature's `enabled_setting` (Auto Junk List `lf_enabled`, Minimap `map_show` since 0.15.112). The "Windows" group (F5-F8 keys, pointer toggle) is shown at the bottom of the DLL's Windows tab (0.15.112), changed through settings.lua (`k:<key>:c`, `b:<key>`). Keys that act in the game (`lf_dump_key`, `map_zoom_in_key`, `map_zoom_out_key`) take only F1-F12 or numpad keys (settings.lua `GAME_KEYS`/`key_allowed`; checked where used too). Debug things go in Experimental → Debug (log level buttons, test players `dbg:test:N`). Party: the hosting side reads each player every 30 steps and sends the list on channel `party`; DOWN at 0 health; clicking a player in pointer mode follows them on the minimap. Test players: `core/test_players.lua`, via channel `party_test`. Server version: `features/server_version.lua`, channel `ver` (client asks at step 120, then every 3600; `kit.server_note`). Server save: `features/server_save.lua` (for the restart helper). Who is in the server world: `core/players.lua` (0.15.48), kept from `emf.on_player_joined` / `emf.on_player_left` (EMF Lua 1.20; the installed one is 1.24). Measured on the owner's server: after a FlameKit reload EMF reports every player already there again (`joined: entity id 1` in the same moment), so the list has no gap; the owner's player was id 1, no player id in 65-1023. EMF's docs: player entity ids are 1..0x3FF and a leaving player's id goes to the next who joins. Never scan entity ids for players again; the 1-64 scan stays only as the fallback for an EMF without the events. The Auto Junk List never junks trophies, runes, Legendary Runes, eternal arrows/spells (unless `lf_show_all`).

**Logging** (owner: for everything, long term, switchable): `fk_log.hpp`, logs in `emf\mods\flamekit\logs\` (10 sessions, 50 MB); `debug.txt` off/normal/full, Ctrl+Shift+F12 cycles; the monitor thread copies emf_core.log lines in. Privacy: other programs only by file name and class, never titles; the Windows user name becomes `<user>`.

**Known risk:** the minimap reads position and item data through layouts compiled into the DLL (EMF SDK from game build 1283531); a game update can break them until a rebuild. EMF allows 128 pictures per session (`item icons: N in use` in the log).

## Shared code, one copy each (0.15.112, owner: no duplicated logic)
- Player names: `core/players.lua` `M.name(world, id, fallback)` (character name first, then the connection/account name). Party, minimap, chat, announcements and the leaderboard all use it.
- Player colours: only the DLL's `player_style`.
- Pointer-out windows: `g_ui_modal`. Menu check: `Frame::in_menu` (minimap included).
- File changed?: `file_stamp()`. Word wrap: `wrap_words()` (Messages, Notices, F4 tooltips, Experimental rows and tooltips, About).
- Before fixing a behaviour, search for every place that makes the same decision (the minimap's own menu check was missed in 0.15.107).

## Menus vs chat (0.15.107, 0.15.110)
Frame::in_menu = the game shows its pointer (game in front). The only menu check: the minimap uses it too since 0.15.111 (with map_hide_in_menus). Kept as menu_was while another program is in front.
Chat: Enter with no menu open sets chat_open (pointer then not a menu) until Enter, Esc, leaving the world, or the
pointer gone 0.5 s after it was seen, or no pointer within 1 s of the Enter (0.15.112: Enter that opened no chat).

## PvP in the party list (0.15.109)
party.lua (server tick) asks experimental.pvp_of(account) and adds a "v\tpvp" line after the player's p and b lines;
PartyLayer reads it into Member.pvp and draws a red "PvP" tag before the level.

## Player names (0.15.108)
Everywhere: `players.name` (character name first, the connection/account name as a fallback). character_name is
server-world only, so the DLL's minimap names nearby players with emf::player_name (the account name) and FarPlayers
puts the character name from far_players.dat (the server's list) in its place, the nearest within 30 m; on a server
without FlameKit the account names stay (0.15.112, owner).

## Messages window sizing (0.15.105)
PinnedLayer::fixed_height: a player-given height (e.h) is kept even when the content is shorter (other windows: at most
that tall). MessagesLayer uses it: with e.h set it shows all kept messages (kit.lua MOST_MESSAGES 100), sticks to the
newest unless scrolled up; max width 1400.

## Default window places (0.15.104, 0.15.123)
Taken from the owner's own ui_layout.txt at 1920x1080 (0.15.123). PinnedLayer: def_x_pt / def_y_pt (1/10000 of the game
window, rounded), or def_center, or def_right_px (px from the right edge), def_bottom_px (px above the bottom);
default_w; default_h (the first height in px at 1080 high, scaled with the game window; `given_h()` = the player's height
or that). Party 29,255 (151, 2361‱) 432 wide, at most 792; Experimental 121 px from the right, 204 (1889‱), 256 wide, at
most 500; Messages 4 px (21‱) from the left, 3 px above the bottom, 548 x 138 (fixed); Notices centred, 104 (963‱), 640
wide; Leaderboard centred, 246 (2278‱), 640 wide, at most 361, hidden at first; F4 window 569,11 (2964, 102‱), 895 wide,
9852‱ of the height. Saved places (ui_layout.txt) always win; Reset place goes back to these.

## Labels and About (0.15.103)
Main screen line: "FlameKit vX". In-world label (kit.lua hud_tick): "FlameKit vX is Connected|Not Connected" from
kit.connected(); the not-connected orange notice is gone (the older-server notice stays). About: WindowLayer kAbout
(What's New tab) sets g_about_request; AboutDialog fetches /9chars/FlameKit/main/README.md from raw.githubusercontent.com
on a thread (web_update::fetch) each time it opens and shows it cleaned (headings gold, ** and ` dropped, bullets, table
rows as cells) in a scroll box; OK / Esc / Enter close; it takes pointer and keys like the update dialog.

## Minimap (0.15.101)
map_corner and map_margin settings removed (owner: never asked for them): corner fixed lower right, margin 24, map_x/map_y
still keep a dragged place. The location is one line "Region / Place" (region gold, place pale, the place shortened
first). Mouse wheel over the minimap (pointer mode) changes map_zoom.

## Experimental window tooltips (0.15.97)
ExperimentalLayer reads each row's tooltip (ui_exp.dat field 10) and draws it under (or above) the hovered button,
drop-down or label in pointer mode. Explanations go into tooltips, not text rows (owner). Drop-down labels are cut to
the box. Dummy "Player-like" (DUMMY_GUID key) spawns a random PLAYER_LIKE template (FakePlayer_Scavenger_Ranger and the
human Scavenger melee fighters) instead of FakePlayer_Vukah_Melee.

## PvP Leaderboard (0.15.95)
features/leaderboard.lua: server side uses emf.on_player_died (p.killer = last hitter within 10 s; counted only when
world:account(killer) is a player and not the victim). leaderboard.json (store, by account; never log accounts) keeps
kills/deaths/name. Board sent on channel flamekit/board (to players) on change, join and every 30 s; the client writes
ui_board.dat ("source server|none", "r rank kills deaths you name", "end"). Ranking: kills desc, deaths asc, name;
equal kills+deaths share a rank. Kills announced via chat.announce. Console: flamekit.board_reset. DLL: BoardLayer
(PinnedLayer "board", key board_window_key F5, hidden until the key is first pressed). Not yet tested with real kills.
0.15.96: Experimental window button "Show/Hide PvP Leaderboard [F5]" (label from ui_layout.txt's board line); a click
writes ui_board_toggle.request, which BoardLayer deletes and toggles on (checked every 100 ms).

## Scroll bars (0.15.115)
PinnedLayer and AboutDialog scroll bars take the mouse (handle drag, page click above/below); PinnedLayer::scrolled()
tells Messages to stop following the newest. The F4 menu's tabs had this already; the Experimental window's drop-down
list scrolls with the wheel only.

## Corner lines, server and update messages (0.15.113, 0.15.117)
In a world nothing in the lower left corner (owner). Since 0.15.117 the server's state and a new update are lines in
the Messages window, not notices (owner). kit.lua server_messages, once per game session in a joined game:
"FlameKit vX connected to server!" (white) when kit.connected, then "Server runs FlameKit vY." (white, from
kit.server_version() in server_version.lua), "Server runs older FlameKit vY!" (orange) when older, and "FlameKit not
supported by server!" (orange) after 20 s without. kit.lua update_message: "FlameKit vX update downloaded!" (green)
once per version, read from update_status.txt. The DLL has no notice of its own any more. kit.notice(tag, text,
colour, seconds) still makes short notices. NoticeLayer: `fit_height` (always as tall as its notices, so a new one is
never cut off), an x per notice in pointer mode (PinnedLayer::press for headless windows), closed ones stay closed
while the same notice is up.
show_label only switches the main screen's version line.

## Main screen line (0.15.88 to 0.15.94)
Outside a world HudLayer shows one line in the lower RIGHT corner, 1 px from the edges, on a dark box: "FlameKit v<running
Lua version>" (owner: the lower left holds the game's copyright lines on the main screen). Nothing if ui_hud.dat's
label is empty (show_label off). Status, notice, updater and debug lines and a stale "build 1" count only in a world.
After Alt+Tab back to the main screen the overlay stayed behind the game (SetWindowPos(HWND_TOPMOST) returned ok but did
not take; never seen in a world). Fixed in 0.15.94: the overlay's owner is the game window (GWLP_HWNDPARENT, in
WindowPresenter::order); the watchdog only counts "below the game's window" as a failure. The 0.15.90 hide-and-show
repair did not help and was removed in 0.15.112.

## Update dialog (0.15.83)
UpdateDialog (flamekit_native.cpp, above BackdropLayer) reads update_status.txt each second (first after 5 s, once the
updater has cleared the last session's line). On "ready|Update vX ..." it opens once per version per session. It takes the
pointer and the keyboard while open (0.15.85 tried not to; the owner found the pointer key too clumsy, reverted in
0.15.86): OK / Enter / Esc close it; Restart Game (0.15.86) writes restart_game.ps1 into flamekit\, runs it in "launch" mode, which has
WMI (Win32_Process.Create) start it again in "wait" mode as a process that is NOT the game's child (0.15.83 used a child:
Steam counted it as the game and refused the restart), then posts WM_CLOSE to the game window (as the restart helper and
Alt+F4 do). The waiter waits up to 120 s for the game's process, then until no enshrouded.exe is left, 5 s, then starts
steam://rungameid/1203620. Log: flamekit\restart_game.log.

0.15.100: the Check for updates button (WindowLayer kCheckUpdates) sets g_update_ask_until = now + 20 s; a ready status
within that time shows the dialog again even for an announced version.

## Restart button (owner, 2026-11-14)

When a restart is due (or might help), offer it as buttons, never ask the owner to type "restart": AskUserQuestion with the options **Restart Server**, **Restart Client**, **Restart Both** and **Not now** (the owner sometimes changes the server's settings file and wants just the server restarted).

## To do (owner's list)

1. **#2 Release roll-out** (0.15.124 built 2026-11-14: `dist`, `release\FlameKit-0.15.124.zip`, `-server-mod.zip`): the owner updates the G-Portal server (SERVER-README.txt) and the two players (install.cmd: it removes 0.14.2's `flamekit_map`, else two overlays and two minimaps). Still to see: a real game installed from the package, and the first update from `dist` (the next release). A 0.14.2 player on a new server keeps the junk list, experimental and far players (same channels lf/exp/map at version 1) and gets nothing on the new channels; FlameKit has no `side: both`, so EMF's mod check never kicks over the version.
2. **Boss challenge / arena mode** (owner, 2026-11-14): turn the duelist into a game mode: a boss challenge (pick a level and a place, a duelist appears for you or the party to beat) or an arena with waves of duelists, each wave stronger than the last. Measured: level 50 duelist = 6692 health, a fair fight for a level 50 player; level 75 = 20760 health, beat the owner (needed Invincible Mode). Starts from `flamekit.duelist <player> [level]` and `set_level` in experimental.lua (Level.dataStorage + DynamicEnemyScaling.nextUpdateTime = 0). Tomorrow.
3. **#7 Controller support for the pointer key:** a controller cannot move the mouse pointer; needs pointer emulation first. Later.

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


## Compatibility
The server and the players' games are updated separately (the server by hand, games through their channel), so they
often run different versions. They work together as long as each is at least the other's minimum: `kit.MIN_SERVER`
(checked in each game) and `kit.MIN_GAME` (sent by the server on channel `ver` as "min <version>", since 0.15.138). A
player whose game is too old sees "This server needs FlameKit vX or newer..."; one whose server is too old sees "Server
runs FlameKit vX, too old for this game...". An older server that is still compatible gives only the white
"Server runs FlameKit vX." line (before 0.15.138: an orange "older" line for any older server).

| Version | Side | Needs the other side? |
|---|---|---|
| 0.15.124 | both | first Stable release: MIN_SERVER = MIN_GAME = 0.15.124 |
| 0.15.125-0.15.136 | mixed | no: every change is optional for the other side (new fields ignored by older ones) |
| 0.15.137 | server | no (production server test only) |
| 0.15.138 | game: min check, "Server updated to" line, tooltips | no |
| 0.15.139 | both: Random, cap 1000, calm dummy, option notices, Windows tab minimap row and Reset All | no: an older server spawns Vukah Melee for Random and caps lower; an older game never sends Random |
- **Instructions to the owner (2026-11-15, owner: "you've failed one of your directives again"):** numbered steps, every folder as its full path (`C:\enshrouded mod shit\...`) in every step, never "that folder", "back in there" or "the one above"; say which button to click and what Windows will ask.
| 0.15.140 | server: scatter, ground snap, cap 5000, budgeted checks, summary logs; game: 5000 button | no: an older server caps the 5000 request at its own cap |
| 0.15.141 | server: cap 1000, hexagonal grid, seen_alive; game: no 5000 button | no: a 0.15.140 game asking for 5000 gets 1000 |
| 0.15.142 | server: Loot Drop (EntityDiedEvent: one server restart), Server tab channel srv, test monster loot; game: the Server tab | no: an older game has no Server tab; an older server: the tab says no settings came |
| 0.15.143 | server: Loot Drop looks again (0.5/1.5/3/6 s), removes a body only after its loot came out | no |
