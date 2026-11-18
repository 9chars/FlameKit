# FlameKit: handoff note

Read this first when starting a new conversation about FlameKit. Updated 2026-11-17 07:25 (versions: "Where things stand" below). First written 2026-11-13.

## Start here (next conversation, written 2026-11-17 07:25)

1. Read Rules 0r, 0p, 0w, 0h, 0a, 0d, 0c, 0b below before anything else, then "Companions". The two that went wrong most on 2026-11-16:
   **0p** (the owner picks every next step; no change, test or "cleanup" he did not ask for) and reading his words
   right (on 2026-11-16 21:19 Claude read "THE last changes you made to make the monsters take damage" backwards and
   removed the feature he wanted kept). When unsure what he means: ask ONE short, plain question. He gets lost in
   long option lists ("I have no idea what you're asking me", "this is getting to be too complicated").
2. Versions: **local server 0.15.280** (server-only: Invincible Mode keeps air full, 2026-11-18 12:14), **0.15.279 on
   Development and the local server's game part** (2026-11-18: companion map dots with the companion's name (0.15.279), notices also go to
   Messages, the companion test hooks: P key, wheel, panel button). **0.15.277 on Stable and G-Portal.** The local
   server's main.lua keeps `features.npc_probe` instead of `features.npc_wheel_probe`; its npc_probe feeds
   `core.companions.set_places` ({x, z, owner = character name}); minimap sends `c x z owner<TAB>companion name` lines, the DLL draws a
   small dot in the owner's player_style colour with the companion's name over it (owner 09:17: "named by the
   companion's name"; there was never a "no name" request), never merged with players.
   Owner 09:26 on 0.15.279 in his game (named dot, P key, Messages): "yeah looks good so far".
2b. (owner 2026-11-18 09:23) "you need to add a longer delay before trying to load that client for dev test cause it
   loads faster now than before and the server is not up fast enough": restart_helper.ps1 starts the client right at
   the server's "world loaded" (about 22 s after start). Done 09:25 (owner: 30 s "should work"): Wait-ForServer
   sleeps 30 s between Start-Server and Start-Client on a `server`/`both` request. Takes effect once the owner
   restarts the helper window (same as the steam://connect change).
3. Production after the release (nightly log `production_stable_logs\emf_core_2026-11-17.log`, 12,492 lines up to
   03:55): no errors; Super B Jump and the glider tip in use there. Check it again at the start.
4. Ask for folder access first (the four folders in "Where things stand").
5. **Open, not settled:** at 21:17 the owner said "no something is wrong": a Fast Dive landing did not seem to damage
   STRUCTURES any more. The explosions spawned normally (log), nothing in the explosion code changed since the
   afternoon when "it definitely blows everything up"; Claude's guess: the Gigantic crater's bombs sit 3..12 m
   underground and miss what stands on the surface (Small/Big go off at or 1 m under the surface). Not tested: the
   owner stopped the session there. Ask him whether it still happens before touching anything.
6. Next feature ideas: "To do (owner's list)" below (boss challenge/arena first), plus the open items in STATUS.md.

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

## Rule 0r: CORE DIRECTIVE, restart status FIRST (owner, 2026-11-16 08:05)

Every message that reports a change (or a copy to the local server, G-Portal or a channel) STARTS with one bold line,
before anything else: **Restart: client** / **Restart: server** / **Restart: both** / **Restart: none**, with a few
words why (e.g. "Restart: none: EMF reloaded the server's Lua by itself"). Owner: "you never tell me this and it takes a
while to read all your shit to figure out if I need to restart or not ... I have to keep telling and asking you this."
No exceptions, also for small changes, probes and test copies.

## Rule 0p: CORE DIRECTIVE, the owner picks the next action (owner, 2026-11-16 13:14)

Always let the owner pick the next action before rolling out any test or any change to the mod. After each result,
say what was found and offer the possible next steps, then STOP and wait for the owner to choose. Never chain on to
the next step on Claude's own initiative (2026-11-16: after "the crater blast definitely worked" Claude built and
published 0.15.226 with Fast Dive's settings unasked; the owner wanted to test the big TNT first: "you're jumping the
gun here per usual"). Owner: "This simple ask makes the work flow move smoother and prevents unnecessary changes until
the plan has been perfectly dialed in." This sharpens rule 1 (confirm before changing anything), which Claude kept
breaking by treating an earlier general request ("give me all the settings") as a yes for every step after it.

## Rule 0w: CORE DIRECTIVE, the owner's exact words (owner, 2026-11-18 09:22)

Found 2026-11-18: after a context summary cut his message to "I'm not sure we need it to say 'companion' ...", Claude
guessed "no label" and released a nameless map dot; he had asked for the companion's name on it. Two rules:
1. **Check before building.** When a request rests on the owner's wording and Claude has only a shortened or unclear
   version (a summary, a "..."), restate it in ONE line ("dot with the companion's name, in your colour?") and get his
   yes before writing code. A cut-off part is unknown, never a guess.
2. **Write his decisions down at once.** Every decision or requirement he states goes into this file (with his words
   and the time) in the same turn, before the work, so it survives a context summary.

## Rule 0h: CORE DIRECTIVE, HANDOFF is never overwritten (owner, 2026-11-18 09:30)

2026-11-18 09:22 Claude copied the repo's HANDOFF over the work folder's without comparing them and lost the companion
notes (rebuilt in "Companions" below). From now on: never copy HANDOFF.md in either direction without a diff first;
the work folder copy and the repo copy must stay identical (md5), and every HANDOFF change is committed and pushed
in the same turn, so the repo always holds a backup.

## Rule 0a: CORE DIRECTIVE, tests and requests (owner, 2026-11-15 14:46)

Every time Claude needs a new test, it says so. Never ask the owner to do anything without first giving a short, brief
recap: what Claude needs, what Claude will do, what the owner will do. Short: a few lines, no long explanations
(owner: "all you have to say is you need to do another test"). Without that recap the owner refuses.

## Rule 0d: CORE DIRECTIVE, no game client updates for server-only changes (owner, 2026-11-15 15:24)

"Updating game client versions for no reason": a change that only touches what runs on the server (server-side Lua) goes
to the local server only: no DLL build, no dist-test list, no Development channel push, no client update. The server's
`flamekit/mod.json` still gets the next version number and changes.txt its line (rule 5). The Development channel gets a
version only when something the game client runs changed (client Lua, the DLL, or a feature both sides need).

**Development is the default (owner, 2026-11-18 09:05):** "I generally assume if were adding a feature and updating the
code it always goes to development". A feature change the game client runs goes to the Development channel
(dist-test) without asking. Stable and G-Portal only with his explicit word for that version. Never remove anything we
added while releasing.

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

## Where things stand (updated 2026-11-16 21:15, end of the conversation of 2026-11-16)

- Versions (2026-11-16 21:30): **0.15.277 everywhere**: Development, **Stable** (dist) and the local server, and
  **G-Portal** (uploaded 21:29 by the restart helper: 9 files changed since 0.15.208; EMF reloaded, no "restart the
  game" lines). Owner, 21:27: "send it out to all channels including stable and update g-portal". 0.15.276 took the
  monster blast damage out by Claude's misreading; 0.15.277 put it back exactly (owner was angry: read his words
  twice, and never remove or change anything he did not ask for).
- Every Development version today rebuilt the DLL (flamekit_native/mod.json bumped with flamekit/mod.json, restart
  helper `build`, then stage `out\flamekit_native\flamekit_native.dll` and run make_dist.py with it).
- The container's git remote https://github.com/9chars/flamekit answers "This repository moved ... FlameKit.git";
  pushes still go through.
- `C:\enshrouded mod shit\outbox` is empty.
- Fast Dive and Glider Sprint: the owner tested and liked what is in 0.15.275 (21:07: "works for me"). Change them only
  when he reports something.
- Debug code kept ON PURPOSE (owner, 2026-11-16: "keep the loot drop debug code for now since I want more data in
  case I find new problems"): loot_drop.lua `flamekit.loottest`, `flamekit.fx <1-10>`, the effect-component `dump()`,
  DIAG_MAX 60 lines a minute of Loot Drop notes. Also kept: Fast Dive's console tests (`flamekit.fastdive ...`,
  `boom`, `ring`, `rings`), the fall probe (one "fall probe: ... LANDED (fast dive)" line per dive landing and
  "fall probe: FALL HIT" per fall damage hit), MOVEMENT.md and the probes in flamekit_native/notes/probes/.
- Dropped by the owner: Revive on the spot (STATUS.md), the Fast Dive head-first pose and crouched landing (every route
  failed, see MOVEMENT.md), the Dump Key mouse buttons ("not worried about that one for now").
- Folder access in a new conversation: ask for `C:\enshrouded mod shit`, `D:\SteamLibrary\steamapps\common\Enshrouded\emf`,
  `D:\SteamLibrary\steamapps\common\Enshrouded` and `C:\Program Files\Steam\SteamApps\common\EnshroudedServer\emf`.
- Restart helper `server` request restarts the GAME CLIENT too: ask the owner before any server restart.

## Built 2026-11-16 (0.15.209 .. 0.15.257), in short

- **Super B Jump** (core/leap.lua, switch "superbjump", per player, off in PvP; owner named it after SuperB, the
  tooltip ends "Named after SuperB, who requested the feature."): a quick double tap of Space leaps high (an Impulse
  push, keepAliveMask Jumping|Falling), W held gives a forward arc, light air steering. Needs the Double Jump skill
  (core/skills.lua, node 0xffd5f940) and 50 stamina (else a yellow notice). Settings (glide.SBJ): height and forward
  up to 30x, steering, tap speed (window). Capped below the game's ~2560 m limit (CEILING 2480 m). Its own fall
  protection (core/fall_guard.lua) from the leap to the landing, except during a free-fall Fast Dive.
- **Fast Dive** (core/dive.lua, switch "fastdive", per player): a double tap of forward WHILE GLIDING is a nose dive;
  falling without the glider above a per-player altitude (default 1000 m) dives by itself after a 20 m fall from the
  highest point, or at once after closing the glider. Opening the glider cancels an automatic dive; the updraft burst
  or climbing cancels a glider dive; landing in water ends a dive (0.15.252: no blast). Orange notice "Fast Dive in
  progress! Prepare for impact!" until the landing (op "dive"). Landing blasts from TNT templates: Off, Small, Medium,
  Big (default), Huge, Massive, Gigantic, Boom only; per player "Fast Dive inside bases" (Boom only / Crater) with
  margins around bases (core/bases.lua). Speed 1x..5x (0.15.256: the new 1x = the old 10x, setting key `sbj_divespd`,
  `glide.DIVE_PUSH` = 10; owner: nothing slower).
  - **Deadly impact** (0.15.249..251; owner: "let the natural fall kill the player", "let the glider dive bomb
    survive", "no fall damage should let them survive"; no setting: "the player can always just open the glider"):
    a free-fall dive's landing is the game's OWN fall damage; a glider dive is protected; No Fall Damage and
    Invincible Mode protect (opts.protected). The game takes a fall's start height ONCE, when the fall begins, and a
    Super B Jump leap counts as falling from the takeoff (the probe: start stayed at 781 m, a 516 m dive landed as a
    3 m fall). So dive.lua holds DynamicFallDamage.fallStartAltitude at the highest point of the fall during a
    free-fall dive. Checked: 539 m fall, FALL HIT 2515 -> 0. A ~16 m fall already kills (FallDamage lethal distance).
  - **Glider tip** (0.15.253..255): opening the glider with Fast Dive on shows "Quickly double tap forward to initiate
    Fast Dive!" in light blue (#8cd2ff) for 10 s (owner's words). The SERVER sees the glider open (dive.lua
    `s.glider_opened`) and sends op "tip" {on, seconds}; 0.15.253's check in the player's game never fired on the
    joined server. Not shown below the minimum height, counted above the last place the player stood or swam
    (`s.ground_y`: the game knows the ground below only ~1 m before a landing).
- **Grave marker** drawn last on the minimap (flamekit_native.cpp, 3 passes).
- Restart status line first in every report (Rule 0r) and the owner picks every next step (Rule 0p): both from today.

## Built 2026-11-16 evening (0.15.258 .. 0.15.275), in short

- **Glider Sprint** (switch "glidersprint", per player, off in PvP; glide.sprinting/glide.apply): holding the game's
  Sprint input (PlayerInputType **53**, measured with the input probe: sent while running AND while gliding; same
  input on a controller) multiplies the glider speed by "Glider Sprint speed" (sbj_sprint, 1.25x..5x, default 2x)
  on top of Glider speed. No stamina. Also while climbing with back/S (0.15.259: the climb's forward speed times it).
- **Settings order** (0.15.261): switches, then Damage bonus, line, Glider speed + Glider Sprint speed, line, Super B
  Jump's, line, Fast Dive's.
- **Fast Dive changes:** landing default Small crater (0.15.260). "Free-fall Dive Minimum" (0.15.265, owner's name;
  key sbj_diveauto) is ONLY for the automatic free-fall dive and is the game's altitude above sea level (default
  1000 m). The glider double tap works at any height (0.15.264: no minimum at all). The old "minimum height" setting
  is gone (0.15.262/263): groundDistance is only known ~1 m before a landing, so it hardly ever worked.
  - 0.15.262 tried "height above where you last stood" for both dives and was undone at once: jumping off a 1000 m
    tower then needed another 1000 m. **Real height above the ground cannot be read** from Lua: EMF has no terrain or
    raycast call, and the teleport ground search only looks ~10 m around the given point. Owner was confused by the
    many options that evening: give him ONE plain question at a time.
  - After a glider dive lands, no fall damage for 5 s (CRATER_GUARD, 0.15.266): the crater opens under the player
    and the ~14 m drop into it hurt (2515 -> 531). Monsters still take that fall.
  - A cancelled dive (pull up/S, burst, glider opened, water) now also ends its push (end_push, 0.15.267): before,
    only the blast and notice were cancelled and the player kept falling at dive speed.
  - The updraft burst (Space) pulls out of a glider dive every time (0.15.268): FlameKit's renewed burst no longer
    counts the dive's push (impulse.y <= -50) as "a burst still lifting"; it replaces it and the dive cancels.
  - **Blast damage to monsters** (0.15.274, glide.kill_tick): the game's explosion spawned by FlameKit NEVER hurts
    creatures (0.15.272/273 measured monsters 1 m from a Gigantic crater at full health, also with Faction 7 on the
    explosion; on_hit saw no hit at all). A player's TNT damage comes from the item, which a spawned template lacks.
    So after a landing FlameKit walks world:entities() (budgeted over a few steps, ~48,000 entities on the local
    server) and hits every monster within reach with emf.damage FROM THE DIVER: BLAST_DMG Small 500, Medium 1000,
    Big 2000, Huge 4000, Massive 8000, Gigantic 15000 at the centre, down to BLAST_EDGE (a fifth) at BLAST_R (10..32 m).
    Bosses too. Monster = no account, has DynamicEnemy01BehaviorState, Faction not 7/8/11. Some places (camps, ruins)
    let the boom go off but allow no terrain damage: a game rule.
- Debug kept: one fall-probe line per dive landing and every fall damage hit; the blast line per landing; the
  0.15.272 health watch is off (glide.BLAST_WATCH) but kept.

## Built 2026-11-15..16 (0.15.143 .. 0.15.208), in short

- **Loot Drop** (Server tab "Monsters drop their loot on the ground", server-wide, off by default):
  features/loot_drop.lua. Monster loot arrives three ways: the body fills itself 2-3 s after the death; a separate
  loot pile `LootContainer_Enemy_*` appears near the body (core/loot_spots.lua finds it within 4 m in a budgeted world
  walk); or the body fills only when opened (`random_loot_on_interaction`): FlameKit opens it as the nearest player
  (`InteractionAcceptedEvent {guestEntityId = player, hostEntityId = body, offerId = 0}`), fallback a hidden chest
  3 m under ground with `LootInteractionEvent`. The items go to the ground with core/ground_loot.lua (0.25 m up), each
  with a VFX_Altar_FlameEssence mark (`MARK_FX eb3633fc-...`, chosen by the owner) that follows a sliding item
  (0.15.197: a new mark when the item moved 0.6 m). Whether a body is a creature is read at the death (0.15.198: the
  Faction goes when the body fills; the queue no longer waits in order).
- **Test monsters' reward loot** (experimental.lua, Experimental tab "Reward loot" switch, default off): runes and
  legendary runes into the killer's bag (`emf.put`, overflow to the chest), one legendary item (weapon, armour, ring,
  gem, cosmetic; rings and gems from `db.LEGENDARY_BY_TYPE`) into a spawned `Prop_Decoration_T5_Storage_40_Chest`
  (core/loot_chest.lua: nearest non-full chest within 50 m else a new one 2.5 m apart, a hit rule per chest so it takes
  no damage, a grave-flame glow, removed when emptied or 15 min after its last item; `flamekit.chests` lists them).
  No corpse and no other loot: the body is removed at the kill and the game's loot piles 2 s later. Bosses are not
  offered as dummies (0.15.187).
- **Glider speed** (0.15.200..0.15.207): Experimental tab drop-down 0.1x..5x (`glide.STEPS`), per player in
  experimental.json `glide_speed`. Measured on G-Portal: the game pulls a glider to 18.7 m/s horizontal, sinking
  4.5 m/s, so the horizontal speed is SET every step to 18.7 x factor along the game's own direction (not scaled:
  scaling is pulled back). Faster only while not much slower than cruising; slower never above the target.
- **Damage bonus** (0.15.205, 0.15.207): drop-down Off..+1000% (`glide.DAMAGE`), per player `damage_pct`; one EMF hit
  rule `{from = player, to = "creatures", scale = 1 + bonus}`, none while the player is in PvP.
- **Invincible Mode keeps mana full** (0.15.207) and **No Fall Damage / Invincible reset the fall start height**
  every step while falling (0.15.208; DynamicFallDamage.fallStartAltitude), because the cancel rule gives the health
  back only after the game took it (a moment dead + a death message).
- experimental.lua is at Lua's limit of 200 top-level locals: new things go into the `glide` table (or `after`).
- **Join/leave lines** (chat.lua, 0.15.205..206): "<name> joined the server!" / "left the server!" in yellow
  (#ffe14d) in Notices and Messages, told 3 s after the join; joins EMF reports again at a reload are not told.
- **Window (DLL)**: tabs end with Windows and About. About (0.15.192): the update line and "Check for updates" at the
  top, README.md from GitHub below (Readme helper, fetched each time the tab opens), a "Change Log" button (0.15.193)
  that opens ChangeLogDialog with changes.txt (12 versions) and OK. The What's New tab and the About window are gone;
  What's New no longer opens after an update (0.15.188); the first time FlameKit is used the window opens on About
  (changes.lua, seen_version absent). Windows tab: "FlameKit Menu" key at the top of Keys and pointer (window_key,
  0.15.195; while a key is being set the menu key does not close the window), Pointer key behavior Press & Hold /
  Toggle (pointer_toggle, 0.15.194), the pointer key takes any key or mouse button (pointer_key, text setting).
- Settings removed: show_label (the version label always shows), open_on_start, lf_keep_hotbar ("Exclude Action
  Bar"), pointer_auto. Minimap sizes: Small 220, Medium 300 (default), Large 380, Extra Large 480. Messages line at every
  world: "Press <menu key> for FlameKit Main Menu".

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

## Companions (test feature, local server only) — REBUILT 2026-11-18 09:35

The original section (written 2026-11-17/18 in the work folder's HANDOFF only) was overwritten at 09:22 by Claude
(rule 0h). Rebuilt from: [L] comments in the server's `features/npc_probe.lua`, [C] comments in
`flamekit_server_probe/src/server_probe.cpp`, [S] Claude's conversation summary. Owner: anything that does not match
what you remember is the rebuild's fault, not a decision.

### The owner's rules for companion work
- NO GAME AI, ever [L 17:06: "I DO NOT WANT TO USE ANYTHING FROM THE GAME THAT USES THIER CRAPPY AI"]; no old code,
  no fallback [L 17:00: "under no circumstances do I want any of the old code. no fall back code ..."].
- **Logging needs no question (owner 2026-11-18 10:00):** "when it comes to a question of adding more logging to get
  more data, you do not need to ask me that, automatically add the new logging in, explain to me about the new
  logging and then ask to proceed with a new test".
- **Odd edge cases first (owner 10:00):** when a new odd situation comes up mid-test, evaluate it right away ("its
  important to evaluate these odd ball edge cases when they happen"), then go back to the test.
- No movement code changes from a single test: he does several tests first [S 2026-11-18 07:20].
- One fix per test round [S 07:49: "lets make sure we test one fix at a time so we don't add any complexity we dont need"].
- In-game tests only after his "ready" [S 2026-11-17 20:01] (a test once ran while he was in a menu).
- Before guessing a cause: search this file and the notes for the same symptom [S] (the faction 7 miss cost about an hour).
- Log everything that helps [S]. Never use `world` inside callbacks (EMF paused all of FlameKit once) [S].
- Teleport catch-up is the LAST fallback, not yet [S 08:23: "the fix will be he'll just teleport to me in any situation he
  cant really get to me... im not ready to add that yet"].
- The jump overshoot stays [S: "it gives him a bit of character"]. The flat-top check is set aside
  (`claude_scratch/server_probe.flattop_setaside.cpp`) [S 07:15].
- Slope limit 30 degrees [C 23:11/23:12; owner: "these are all guesses"].
- Eventually: different models must work with the same tuning; companions shown like players (party list) [S].

### Where things are
- Server Lua: `<server>\emf\mods\flamekit\features\npc_probe.lua` (local server only, never published; backups
  `claude_scratch/npc_probe.before_*.lua`). The local server's `main.lua` loads `features.npc_probe`, NOT
  `features.npc_wheel_probe` (npc_probe owns channel `npcwheel` there).
- C++ server mod: `<work folder>\flamekit_server_probe\src\server_probe.cpp` (restart helper `buildprobe`; backups
  `server_probe.cpp.before_*`).
- Client (in the release since 0.15.278): `features/npc_wheel_probe.lua` (status notices, wheel, P key, panel button),
  `core/companions.lua` + `features/minimap.lua` (map dot, 0.15.278/279).
- Commands (console or `emf\commands.txt` on the server; write via `cp /tmp/c.txt commands.txt`): `flamekit.npc`
  roster | drive | lure | hold | still | attr | level | faction | combat | atk | face | tpground | fullrec | look |
  spawnwild | remove ... Logs "npc probe: ..." in `emf\emf_core.log`.

### Body, side and stats
- Body: Enemy_Skeleton_Hound `18eefd30-da1d-49f5-a6d8-7da8f2d01f43` (owner's pick) [L].
- Roster [L 11:56/11:58]: names N1, N2 ... kept in the world's data; one main companion per player [L 13:06];
  controllers (accounts) + admins (`npc_admins.json`) may command [L 12:36-12:40]; owner account 0x485890b753e75ad1.
- **Faction 11 (PlayerAlly)** [L 19:31]. Faction 7 (Player) = every attack does 0 damage (bite test 19:23). This was
  already in the notes (0.15.81 dummy) and was missed: rule "search the notes first".
- Level = owner's level [L 19:47]: `Level.dataStorage[1]`, then `DynamicEnemyScaling.nextUpdateTime = 0`; at setup
  and every 10 s. Level 30 = 1164 HP / bite 239; level 50 = 3680 HP / bite 420 [S].
- Attributes: Strength/Dexterity/Intelligence writable (100 each gave a 2520 bite); Constitution/Spirit/Endurance
  not available (emf.add_component limits) [S]. Owner: "just scale his HP up according to his level"; "stop making
  up things" [S].
- Facing a target while attacking [C 18:38]; bite = attack 0 `0x63FE3237` (2 m), lunge = attack 1 `0xC34733A8` (4 m) [C].

### Following: the drive and the breadcrumb trail
- His AI off (`DynamicEnemy01BehaviorState.enabled = false`, route planner off). Lua writes the next crumb into
  movementTarget and the player's spot into homeZonePosition; the C++ hook right after the game's steering step
  writes his movement input (direction, look, Walk/Run/Sprint; nothing within 3 m) [L/C 15:42-16:05].
- Crumb every **0.25 m** [L 08:10 "lets try .25", tight spaces between trees; was 0.5, 2 m before 15:54]; reached
  within **0.3 m** (CRUMB_REACH); reached crumbs are deleted [L 20:43, back-and-forth fix].
- Crumbs only on the ground: contact AND groundDistance < 0.1 AND DynamicLocomotion.state 0 [L 20:36].
- Breaks ("brk"): a drop over **7.5 m** (his fall damage starts at 8 m, lethal 16 m) [L 20:16/20:18], or more than
  **120 ticks (2 s)** in the air (a flight; a jump is about 1 s) [L 20:37]. He waits at the last crumb before a break;
  goes on when the player is within **6 m and 2 m height**; the fresh trail starts where HE stands [L 08:25].
- Faces where he goes [L 17:32]. Swimming: FLOAT_LIFT 0.45 m, FLOAT_PITCH 28 deg [L 13:28-13:31, 16:33].
- Hold (stay put, face a target) while attacking [L 19:00].

### Edge stop (C++ edge_blocked) [C 22:37-23:12]
- Ray 1.5 m ahead (plus 2.5 / 3.5 m running / sprinting), mask 7, from +2 m to -12 m. Blocks on: no ground, more
  than 7.5 m down, or more than 0.87 m down within 1.5 m (30 degrees) unless permitted.
- Permission: Lua sets `combatData.isTargetInsideLeash` when a trail crumb within **12 m** ahead (before any brk) is
  more than 0.8 m and less than 7.5 m below him [L 22:55, 23:02, 23:19, 08:23 (12 m)]. Swimming:
  `combatData.targetOfMyTarget` = skip. Skipped while airborne (state 2) [S].

### Jumps (C++) [C 23:32-23:51, 07:46/07:47]
- The game's jump: `ActorInput.externalTriggerJumpType` (offset 377) = 1, `externalTriggerJumpTime` (384) = now.
  1.76 m high, 4-9 m forward when running.
- Auto step jump: rays 0.5 m (level within 0.4 m) and 1.5 m ahead (a step 0.6-3.6 m up); cooldown 90 ticks.
- Boost sized to the step [owner 07:47: "the dog should just be able to adjust his jump height"]: an Impulse slot at
  takeoff aiming at step + 0.7 m; push = (sqrt(2*25*peak) - 9.4)/0.2 for 0.2 s. Overshoots about 2.2x: kept.
- Double jump: owner, "just make it more complicated" [S]; not done.

### Stuck and status notices
- Stuck = no 0.3 m progress toward his crumb in 3 s (180 ticks) [L 07:23/07:24]: he stands; resumes like a drop wait,
  or with P / Call.
- Notices stay until the condition clears [L 07:30], and (0.15.278) every notice also goes to Messages [S].
  - "Companion is afraid to follow (too steep)!" [L 08:20], "Companion is afraid to follow (drop too high)!" [L 08:41],
    "Companion can't get up there!", "Companion is stuck!" — orange #ff9050.
  - Live line once a second: distance and height to the player, "(come within 6 m, 2 m height)" [L 07:35, 08:18].
  - "Companion has died!" red #ff4040 [L 07:23]; all cleared when he comes back to life.

### Call and the map
- P key (client) / "Call my companion": spawns him 0.3 m to the player's right, facing the player's way
  [L 07:07-07:10].
- Map dot (0.15.278/279): small dot in the owner's player colour with the companion's name over it, never merged with
  players; server line `c x z owner<TAB>name` [owner 08:49-09:17].

### Open list (owner's order decides)
**Owner's plan (2026-11-18 13:00):** "going to take a short break, but I'd like to handle situations with the glider
and get the teleport stuff in there and then we can move on" -> next: glider situations, then the teleport fallback.
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
1. Combat behavior (next after follow/safety).
2. Companions in the party list.
3. Teleport fallback (later, owner's word).
4. Ground under a glide path: parked. Owner idea (2026-11-18 09:27, not decided): "maybe the dog could just follow
   the trail in the air".
7. **Companion inventory (owner 2026-11-18 13:06):** "also add to your list: companions can carry extra items for you
   (they have their own inventory like a storage check basically)". (a storage chest the companion carries; later)
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

## How to build and publish a version

1. Change the source. Bump `version` in `flamekit/mod.json` and `flamekit_native/mod.json` to the same number. Add the lines to `flamekit/changes.txt`.
2. Lua tests: `texlua flamekit_native/notes/tests/run.lua flamekit /tmp/fkj host` and `... joined`; both must print `ALL PASSED`. Before each run: `rm -rf /tmp/fkj /tmp/fkj\\*` (run.lua's backslash paths land next to the folder; a stale `ui_actions.txt` breaks the tab test).
3. Native build (only when `src\` or `flamekit_native/mod.json` changed): copy the changed files into `<work folder>\flamekit_native\` (fresh staged folder, check md5 on the PC), then restart helper request `build`. Result: `restart.done` `ok build`, `build.log` ends `BUILD OK`, the DLL in `out\flamekit_native\`. The build never copies into the client. Every build gives a different DLL (timestamps), so an unchanged source still makes a new update.
4. Lua part for the local server: copy the changed files into `<server folder>\emf\mods\flamekit`, `mod.json` last (EMF reloads Lua live on the server; check `reloaded` in `emf\emf_core.log`). Same files into `<work folder>\flamekit`.
5. Make the list: `python3 flamekit_native/notes/make_dist.py . dist-test <built dll> flamekit_native/mod.json`.
6. Sign it (since 0.15.45; an unsigned list is refused by every client): copy `dist-test/update.txt` to `<work folder>\restart_helper\signing\update.txt`, restart helper request `sign`, read `signing\update.sig` (128 hex digits) into `dist-test/update.sig`, run `python3 tools/check_sig.py dist-test` (must say `update.sig is good`).
8. G-Portal (only with the owner's word for it): put the changed server files in `<work folder>\outbox\` (same layout as `emf\mods\flamekit`, replace what is there), restart helper request `upload`; it uploads, waits for EMF's reload and fetches the logs into `<work folder>\production_stable_logs\` (an `upload` with an empty outbox just fetches the logs). Check `production_stable_logs\emf_core.log` for "reloaded" and for "is new since the game started: restart the game" lines (then the server needs a restart for that event).
9. Stable (only with the owner's yes for that exact version): `rm -rf dist && cp -r dist-test dist`, `check_sig.py dist`, commit, push.
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

## Labels and About (0.15.103, changed 0.15.192..196)
Main screen line: "FlameKit vX" (always; show_label is gone). In-world label (kit.lua hud_tick): "FlameKit vX is
Connected|Not Connected" from kit.connected(). README.md and changes.txt: see the About tab above.

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
- EMF on a running server: a new `emf.on_event` or `emf.emits` name (one the script did not use when the server started) only works after a server restart; the log says so. A Lua upload alone does not fix it.
- Restart helper request `server` restarts the game client too: ask the owner first.
- A drop-down row in a Lua panel: `{ options = { {key, text, selected}, ... }, text = <shown choice>, same_line = true }` after a `{ label = true, text = ... }` row; the click comes back to the feature's `click` as the entry's key (tests: `click("W:<key>")`).
- The game's fall damage takes the fall's start height once, when the fall begins (DynamicFallDamage.fallStartAltitude); a push that keeps the Falling state from the takeoff keeps that start at the ground. Write the start yourself when a fall must count from higher up (core/dive.lua), or every step to keep a fall short (core/fall_guard.lua).
- What the player's own game sees of its movement state on a joined server was not enough to see the glider open (0.15.253): let the server see it and send a message.
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
