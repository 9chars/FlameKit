# FlameKit: handoff note

Read this first when starting a new conversation about FlameKit. Updated 2026-11-17 07:25 (versions: "Where things stand" below). First written 2026-11-13.

## Start here (next conversation, written 2026-11-17 07:25)

1. Read Rules 0r, 0p, 0g, 0n, 0w, 0h, 0a, 0d, 0c, 0b below before anything else, then "Companions". The two that went wrong most on 2026-11-16:
   **0p** (the owner picks every next step; no change, test or "cleanup" he did not ask for) and reading his words
   right (on 2026-11-16 21:19 Claude read "THE last changes you made to make the monsters take damage" backwards and
   removed the feature he wanted kept). When unsure what he means: ask ONE short, plain question. He gets lost in
   long option lists ("I have no idea what you're asking me", "this is getting to be too complicated").
2. Versions: **0.15.284 on Development and the local server** (2026-11-18 15:21: travel UI hides at 5.3 s, cancel rule
   removed; not yet restarted into), 0.15.283 (14:42: the minimap's old TeleportCount rule removed entirely, Rule 0n), 0.15.282 (14:35: the minimap comes back with the rest
   of the UI after fast travel), 0.15.281 (14:18: fast travel hides all of FlameKit's
   UI; includes 0.15.280 Invincible air), earlier today **0.15.279** (2026-11-18: companion map dots with the companion's name (0.15.279), notices also go to
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

## Rule 0g: CORE DIRECTIVE, Stable and G-Portal only on the owner's direct word (owner, 2026-11-18 14:16)

"do not touch g-portal or stable release ever unless I say so. you do not need to keep asking me about it. I will
directly tell you when I want stable and g-portal updated. otherwise assume I do not want it!" Never update, propose or
ask about Stable or G-Portal; do it only when he says so himself. Releases go to the Development channel (dist-test)
and the local server as usual.

## Rule 0n: CORE DIRECTIVE, a new feature REPLACES the old one (owner, 2026-11-18 14:31)

"yes of course the old signal needs to get cleaned up, why is this such a difficult concept to understand? this isn't
the first time new feature replaces an old feature and you leave the old feature in place? why are you doing that?"
(0.15.281: the new server travel signal showed the UI again, but the minimap's old TeleportCount rule still kept it
hidden until the player moved.) When something new takes over a job, the old code must stop doing that job wherever the
new one runs: no two mechanisms for one job side by side. **No fallbacks either** (owner 14:39, verbatim): "I don't want
old features left in "when the new one can't run". if the new one can't run then there is a problem with the new
feature." So the old code is REMOVED, not kept as a fallback; if the new one can't run, fix the new one. Check this
explicitly for every replacement before releasing.
("Never remove anything we added" is about the owner's features, not about superseded mechanisms.)

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
- **A one-off is never a fix, for ANY code, not only movement** (owner 2026-11-18 14:54, verbatim: "one rare one off
  glitch != do a fix, always violating your directives, what's the point of them ?"). After the 14:27 slow-load travel
  Claude proposed a fix (0.15.284) from one occurrence. A single odd event gets evaluated (Rule 10:00) and written down
  as "watch", with the log evidence; no fix and no fix proposal until it repeats or the owner asks for one.
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
- Server Lua: `<server>\emf\mods\flamekit\features\npc_probe.lua` (local server only, never published). **In git
  since 2026-11-18 15:45: `local_server/` (npc_probe.lua, npc_fields.lua, the local server's main.lua, README.md,
  tests/drive_harness.lua).** Whenever the server copy changes, copy it into `local_server/` and commit (owner 15:39
  "#1 get it into get"). The local server's `main.lua` loads `features.npc_probe`, NOT `features.npc_wheel_probe`
  (npc_probe owns channel `npcwheel` there). The old `claude_scratch/npc_probe.before_*.lua` backups named below were
  deleted 2026-11-18 16:10 (owner #6); the full pre-split version with all its history comments is git commit 5f661f1
  (the claude_scratch copy was deleted 19:17, owner: "lets get rid of it, i cant imagine going back to it").
- C++ server mod: `<work folder>\flamekit_server_probe\src\server_probe.cpp`, in git (`flamekit_server_probe/`)
  since 2026-11-18 15:45 (restart helper `buildprobe`).
- Client (in the release since 0.15.278): `features/npc_wheel_probe.lua` (status notices, wheel, P key, panel button),
  `core/companions.lua` + `features/minimap.lua` (map dot, 0.15.278/279).
- Commands (console or `emf\commands.txt` on the server; write via `cp /tmp/c.txt commands.txt`): `flamekit.npc`
  roster | drive | lure | hold | still | attr | level | faction | combat | atk | face | tpground | fullrec | look |
  spawnwild | remove ... Logs "npc probe: ..." in `emf\emf_core.log`.

### Cleanup round (owner 2026-11-18 15:29-15:39)
Owner 15:29: "before we move ahead is there any clean up we need to do? I want to keep the logging we added ... but
maybe old tests, old code? old systems and functions that didn't work right still in there, code that isn't factored
properly so code can be appropriately reused, etc?" Owner 15:39 on Claude's list, verbatim: "#1 get it into get.. #2
are you saying we don't need this anymore or??? #3 go ahead and do this one, we'll retest everything, make sure we have
a complete backup of the function in case we need to revert back to it. #4 keep them for now #5 get rid of dead code
#6 once the code is in git go ahead and clean this up if we don't need it. #7 go ahead and clean that up #8 you're
talking about companion stuff or????? comments: we'll reassess after this is done. proceed in the order that makes the
most sense"
- #1 done: live companion code and server_probe.cpp in git (commit 5f661f1).
- #5 done: try_offer, v3, gy, the unused `logcrumbs` field, DROP_GAP removed.
- #3 done (16:09, live on the local server by EMF's reload, no restart needed): drive_step is now drive_read,
  drive_waterlog, drive_water, drive_track_player, drive_put_away, drive_lay_crumb, drive_upkeep, drive_jump_follow,
  drive_lure, drive_hold, drive_pick_target, drive_stuck, drive_steer (a part returning true ends the tick), plus
  helpers face, hold_at, health, edge_off, launch_speeds, launch, report_blockers. Checked with
  `local_server/tests/drive_harness.lua` (old vs new in a fake world, every write, log line and notice compared per
  tick): 0 differences in 66 scenarios; every line of the old drive reached except one fallback line. **Owner: retest
  everything in game** (walking, trap door, water in/out, piers, islands, diving, climb-out hop, jumps and double jumps,
  drops, stuck notices, glider, fast travel, Call). Revert = git 5f661f1 (the claude_scratch copy
  was deleted 19:17 by the owner's word).
- #7 done: npc_probe.lua comments say what the code does now (history: this file and git 5f661f1).
- #6 done: deleted the claude_scratch backups (npc_probe.before_*, client/server .before_*, rel278-rel284,
  server_before_278, dist_md5_*), notes/probes/npc_probe.lua and npc_wheel_probe.lua (superseded copies), the server's
  `_to_delete/input_probe.lua` and `fk_server_probe.dll.old_1115`. Kept: the data and tools in claude_scratch (bt, tpl,
  skills, items/inspect dumps, nightly_log_fetch, buffs.png), `server_probe.flattop_setaside.cpp` (set aside by the
  owner), notes/probes input/jump probes (measuring tools), `restart_helper/_to_delete` (FTP setup files: not touched),
  the server's 79 fullrec_*.txt recordings (43 MB, logging output: owner's call).
- #4 kept for now (test console commands). #2 and #8 were questions, answered 16:1x: not done.
- Restart 16:23-16:24 into 0.15.284 (owner 16:23 "yes"). Retest 16:24-16:45, owner 16:45: "initial testing looks good".
  Log: no errors; glides (put away and back), a fast travel, a double jump follow (2.1 m up, landed 0.5 m from the
  player's landing), water in/out, leaps, dives. Three "gave up" (16:43:57, 16:44:06, 16:45:35) with his crumb only
  0.4-0.7 m away on the same level and nobody in his way, each followed by the 2 s respawn. WATCH only (Rule: a
  one-off is never a fix); asked the owner whether they were on purpose.
- WATCH (owner 17:06, could not reproduce): "in one dungeon, it was having problems going down stairs and was jumping
  straight up and out when the stairs went below the ground and their was an over hang above him from the ceiling, it
  seems to have confused him". Likely cause (server_probe.cpp maybe_step_jump): the step-jump rays start 5 m ABOVE him
  (raised 2026-11-17 07:47 to catch steps up to 3.6 m) and look down; under a ceiling or overhang lower than that, the
  first hit 1.5 m ahead can be the overhang, read as a step 0.6-3.6 m up: he jumps. Log since 16:24: three step jumps
  that landed no higher (16:44:59, 16:45:45, 17:01:21). 16:45:45 fits: he "jumped a 0.72 m step up" at 6227.3 920.6
  5287.2, the spot where the player had just jumped DOWN (came down 5 m lower), and landed 1.92 m lower. Owner 17:07:
  "I was able to reproduce it at the time" -> not a one-off. Fix proposed 17:08 (server_probe.cpp only): before the
  downward step ray, one ray straight UP from just above his feet 1.5 m ahead; if it hits a ceiling, the downward ray
  starts just under it instead of 5 m up; nothing overhead = as now; both hits logged per jump. Needs buildprobe + a
  server restart. Owner 17:10: "no, but you maybe right, I would like to find more situations first so we can test
  the fix. currently I don't have a situation where the problem and fix can be tested" -> PARKED until the owner has
  a spot where it happens (then: build, restart, test there). **2026-11-18 19:10: probably fixed by the simplified
  following** (the ray step jump that misread the overhang is removed; steps up come from the trail). WATCH on
  stairs under overhangs.
- BOARDWALK (owner 17:20): "im on a boardwalk suspended above the air partly that connects to land, when I walk out to
  it, he treats it like its not there, like its a cliff face going downward ... gives me the cant follow then
  teleports". Log 17:17-17:20: five "gave up" with the crumb 0.4-1.1 m away on his level; the native edge stop:
  "ground 1.5 m ahead: none within 12 m" (the ray goes through the planks, like the trap door; the floor proof only
  raised the drop limit to 7.5 m), and the proof itself flipped off whenever the player stood within about 5.6 m (trail
  ahead shorter than FLOOR_REACH). Owner 17:29: "go ahead, but the fix for #2 isn't clear to me". **Done 17:31 (Lua,
  live by EMF's reload, git):** (1) the floor proof also counts when the whole trail is one unbroken level piece that
  ends where the player stands on the ground (log "..., to the player"); (2) with a floor proof the native edge stop
  (and its step jump) is off for that tick (edge_off), not only the drop limit. Log line now "floor proven by the
  trail, native edge stop off". Watch: corner cutting on a narrow walkway (up to about 0.3 m).
  Test 17:31-17:34, owner 17:34: "looks fixed now". Log: proven several times ("to the player" too), but two more
  give-ups on the boardwalk (17:33:24, 17:33:38, each teleported back): "no floor proof (... 0.0 m ahead)", the chain
  broke at the FIRST link: the nearest crumb was 0.9-1.1 m from him (over FLOOR_LINK 0.7), e.g. after he stood beside
  the player's path while the player walked past. 17:35 logging (live): the "no floor proof" line now says where and
  why the trail ends ("ends at crumb i of n: x m from him / from the crumb before / above/below him / a break", or "the
  trail ends there, the player is not on it"). Owner 17:46 "sure": **done 17:46 (Lua, live):** FLOOR_FIRST 1.5 m, the
  first link from him to the nearest crumb; the links after it stay FLOOR_LINK 0.7.
- DROP WAIT GAP (owner 17:52): "I jumped down a long drop and the dog isn't complaining about not following me and not
  teleporting to me...". Log 17:51:15: the player jumped 21.7 m down (crumb 2 a break); no notice, no put-away.
  Cause (code, not new today): at a drop he first walks to the last safe crumb and only counts as waiting within
  0.6 m of it; the C++ edge stop (ray 1.5 m ahead) held him about 0.7 m short (crumb ~0.74 m away), so every tick
  "walks there first" cleared h.waiting, and while walking there neither the stuck count nor the wait count runs: no
  notice, no TP_AFTER. 17:54 logging (live): "drop wait <id>: walks to the last safe crumb first / waits at the last
  safe crumb / over ..." with the distances. Owner 17:59 "yes": **done 18:0x (Lua, live):** DROP_AT 1.5 m, he counts
  as at the last safe crumb within 1.5 m (the edge ray's reach) instead of 0.6 m.
- **SIMPLIFY THE FOLLOWING (owner 18:04/18:06), plan in `local_server/FOLLOW_PLAN.md`, NOT BUILT.** Owner 18:04: "I feel
  like this shell game of numbers tic tac toe is proving this approach might not be working. every time you change the
  numbers to fix one thing, something else becomes off... if we keep playing this numbers game you're going to have to
  come up with a simplified solution". 18:06: "write it up, maybe rely more one the new meta data from the bread
  crumbs... he can't teleport easily now so not ever situation needs to be perfectly handled..." (read as: he CAN be
  respawned easily now). The plan: the trail is the only truth; no edge stop and no ray step jump on the trail; ups and
  downs from the crumbs' meta data; one stuck rule = respawn. Owner 18:08: "I mispoke. I meant to say he CAN teleport
  easily now". **Owner 18:35, GO:** "lets do it. if rather have a simplified system that might need some edge cases
  handled rather than constantly tweaking numbers that dont get us anywhere long term". **Built 18:35-18:42 (git),
  waiting for the restart:**
  - Lua (`local_server/features/npc_probe.lua`, md5 86928d7d, installed on the server at the restart): drive_copy (new:
    a break = can't follow; a landing of a real jump (jump count 1+ or second push) or a crumb STEP_UP 0.6+ above him =
    he jumps to it, once per crumb; everything else he walks), drive_jump_follow = only the flight and the settle
    (settle only after a jump up), drive_pick_target (no drop wait; arrived = within 2 m across AND in height),
    drive_stuck = the one rule (no progress STUCK_TICKS -> cant_follow; he stands; the player coming to him ends it;
    TP_AFTER -> respawn), drive_steer (on the trail edge_off; off the trail the native edge stop, drops to 7.5 m only
    toward a swimming player). h.cant is the one state (land, water, to the water). Removed: floor proof, edge
    permission, drop wait, the stuck-and-wait state, DJ_AT/DJ_RISE/DJ_WAIT/DJ_REACH, FLOOR_*, DROP_AT, DROP_RESUME,
    STUCK_MOVED. Log lines: "jump follow ...", "can't follow: <id> <why>: ...", "can't follow: <id> over: ...",
    "edge <id>: on the trail: edge stop off / ...".
  - C++ (`server_probe.cpp`, built 18:41, installed as `mods\fk_server_probe\fk_server_probe.dll` md5 269a667e, the
    loaded one renamed `.old_1841`): the ray step jump and its boost removed; arrived = within kFollowStop across AND
    in height.
  - Fake-world check (drive_harness, dump): no errors; jump follows, can't-follow + respawn at the 10 m cliff, the
    wall at the shore. Behaviour changed on purpose, so only an in-game retest says whether it is right.
  - Restart 18:52-18:53 (owner 18:52 "yes"); both loaded clean. Test 18:53-18:58, owner 18:58: "its pretty good, he
    fell in the trap door and just jumped out on his own" (the step-up rule: next crumb up, he jumps). Log: two big
    drops (11.5 m, 24.5 m) -> "can't follow: drop" -> respawn after 2 s; a glide put-away and return; jump follows
    landing within 0.6 m. WATCH: 18:58:18 a jump follow for a landing with jump count 0 but "second push" (the
    double-jump guess fired during a fall); he hopped 3.4 m down, landed fine.
  - Owner 19:00: "i'm pretty satisfied so far". Owner 19:10 "lets do the clean up now": the old C++ DLL
    (`fk_server_probe.dll.old_1841`) deleted; the overhang item marked probably fixed. The pre-change versions are in
    git (server_probe.cpp before f3229be; npc_probe.lua before f3229be).

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
Owner 13:35: the companion inventory idea "on the back burner for now, lets continue with the main tasks".
**Glider design (owner 13:40):** "it will look way to strange if the dog flies in the air with the glider. since we
have new meta data now, the dog sees I took off on the glider. it should briefly wait to make sure im just just popping
it out quick and landing near by. when it realises I'm not coming back, distance too far, etc, it automatically
'despawns' it waits until I arrive back on ground and magically spawns back in next to me. this could use the same
teleport function as when I move across the map from a fast travel or what not..."
Pieces already there: "Put away" (wheel/do_away: body removed, kept in the roster) and Call / P (on_call: respawn 0.3 m
to the player's right, facing his way). 13:40 logging: "air <id>: player state N after s in the air (...)" each time a
new locomotion state shows up mid-flight, to find the glider's number.
Glide test (13:42, owner: "2 long glides and 1 short one"): **the glider is locomotion state 4** (state 2 = in the air
after a jump; 4 shows ~1.1-1.2 s after takeoff, after the double jump that opens it). Long glides: 79.7 m in 9.9 s
(top 997.2, 43 m above takeoff), 74.5 m in 9.2 s (came down 14.2 m lower); short: 18.4 m in 2.33 s, 1.4 m lower. All
three left a break (flight > 2 s) in the trail: the hound waits at the last crumb before it (and at 13:42:23, 38 m from
the player, "gave up" as can't follow).
Claude's proposal 13:44 (numbers): glider seen -> wait; still in the air after 4 s or 30 m away -> put away; back
beside him after 1 s on the ground; a short glide landing close is no break, he walks; can't reach the player for 5 s
(stuck or afraid) -> the same respawn (the general teleport fallback); fast travel (> 50 m in a moment) -> the same.
Owner 13:46 (taken as the yes, with the notices): "there should be a notice saying 'Companion put away, waiting for
your landing.'. When he appears (or maybe ANY time he spawns by you, there should be a notice that says 'Companion has
spawned near you!'".
**Built 13:48 (npc_probe, live):** GLIDE_STATE 4, GLIDE_WAIT 240 ticks, GLIDE_FAR 30 m, LAND_TICKS 60, TP_AFTER 300,
FAR_JUMP 50 m. drive_step sets h.go_away ("glide" / "fast travel" / "can't follow": h.stuck, h.waiting, h.sstuck or
h.wstuck for TP_AFTER); F.tick put_away_for() removes the body (roster out = false, like "Put away"), the glide one
shows the persistent status "Companion put away, waiting for your landing." (tag companion_away, #8cd2ff), and keeps
`returning[name]`; once the player has been on the ground (not in the air, not swimming) LAND_TICKS, on_call() brings
him back beside the player. on_call (P, Call, these returns) now clears companion_away / companion_stuck and shows
"Companion has spawned near you!" (5 s, #8cd2ff) instead of "<name>: Coming!". A glide that lands before the put-away
sets no drop break. Logs "away: <name> (<id>) put away (<why>) ..." and "away: <name> back beside player ...".
Backup `claude_scratch/npc_probe.before_glider_1348.lua`.
Test (13:53-13:54), owner 13:54: "it works pretty well". Log: three glides, each "put away (glide)" then "back beside
player 1 (glide over)" and respawned (7.0 s, 1.6 s, 2.4 s later). Not yet seen in a test: fast travel, the 5 s can't
follow fallback.
**Fast travel + loading screens (owner 13:57):** "when I warp to a new location. I got the 'Companion spawns near you
message.' before the load was done. is there anyway to wait UNTIL the load is done? Also a lot of the UI elements don't
disappear during zoning to a different area. This has been a problem for a while and just mentioning it to you now. I
will note the mini map does attempt to disappear, but it disappears a little too late. is there anyway to dial this in
a bit better. It just looks goofy to the player". Log: 13:56:00.7 "put away (fast travel)", 13:56:01.7 back (1 s on
the ground at the destination on the SERVER, while the client still loaded). Client today: flamekit_native.cpp hides
only the minimap during a fast travel (g_travelling: the local player's TeleportCount went up; back when he moves
after 2 s, at most 20 s); the other layers (HUD lines, notices, party window ...) do not look at it. 13:58 logging
(local server): "load: player <id> ready for gameplay <PlayerInput.fromClientIsReadyForGameplay>, teleport count <n>,
at x y z" whenever either changes: if the flag drops during the loading screen it is the signal for both (the respawn
waits for it; the client could hide all of FlameKit's layers on it, a Development release).
Can't-follow fallback test (14:02-14:03, owner jumped off without the glider): 14:02:56.970 "stuck: gave up ... player
16.0 m", 14:03:02.004 "put away (can't follow)", 14:03:03.002 back beside the player: works. Owner 14:03: "the respawn
works so well, I wouldn't even wait 5 seconds... wait like 2 seconds maybe. the only case where I would want to change
this is if we were testing it more and trying to figure out situations why he couldn't get to me when he should".
14:04 (live): TP_AFTER 120 ticks (2 s after he gives up; giving up itself takes STUCK_TICKS 3 s of no progress).
Owner 14:05: "the 2 seconds was a quicker response and good just enough total time to see the error from the dog".
**Fast travel data (owner 14:07 "I did a couple fast travels"):** the server's "ready for gameplay" flag
(PlayerInput.fromClientIsReadyForGameplay) goes FALSE 0.04-0.06 s after the teleport count rises and TRUE again when
the client has loaded: 14:06:51.32 -> 14:06:59.60 (8.3 s), 14:07:44.45 -> 14:07:50.32 (5.9 s). The return came at
14:07:00.8 (after ready, by luck) and at 14:07:46.9 (3.4 s BEFORE ready: the early notice). The client's minimap hid at
the teleport count (14:06:51.297, same moment) and came back when the player moved (10.1 s, 11.2 s: later than ready).
14:08 logging: the player's fast travel request (PlayerInput.fromClient.teleportAction: target / teleporterType /
versionData, e.g. "18766/1/607074"); one more fast travel shows whether it arrives before the teleport (an earlier
"hide" signal than the count).
Owner 14:10 "ok" (yes to #1 and one more fast travel). Built 14:10 (live): a return also waits while the player's
fromClientIsReadyForGameplay is false (then LAND_TICKS on the ground). Backup `claude_scratch/npc_probe.before_ready_1410.lua`.
#2 (hide ALL of FlameKit's layers while travelling, back on the ready signal: a client DLL change, Development) waits
for the travel-request timing.
Travel request timing (14:10-14:12): it reaches the server ~4.2-4.3 s BEFORE the teleport (14:11:11.2 -> 14:11:15.6);
owner 14:13: "there's a short animation, maybe about 3.5 seconds before the screen goes dark". Owner 14:16: "build it
and restart" (#2: the server drives hiding ALL of FlameKit's UI: hide 3.3 s after the request or at the teleport, show
when the client reports ready; Development 0.15.281).
**0.15.281 to Development (built 14:18):** `features/travel_hide.lua` (new, listed in main.lua; the local server's own
main.lua got the line too, next to npc_probe): the server watches each player's travel request version, TeleportCount
and ready flag; hides HIDE_AFTER 198 ticks after the request or at the teleport, shows again once ready went false and
then true after the teleport; cancelled travel (no teleport 7 s after the request) or 60 s: shown again. Channel
flamekit/travel ("1"/"0") to the player's game (the host's own game directly); kit.travelling -> ui_hud.dat "travel 1"
(core/kit.lua) -> DLL g_travel_hide: Layer::shown() false for EVERY layer (FlameKit's window too), not gated by
in_world. Logs: server "travel: player N travels: FlameKit's UI hidden (...)" / "... shown again (loaded, after x s)";
client log "fast travel: all of FlameKit's UI hidden / shown again (the server's signal)". The minimap's own
TeleportCount rule stays for servers without it. Also in this release: 0.15.280's Invincible Mode air refill.
Restart 14:19-14:20 (owner 14:16 "build it and restart"); the owner's game on 0.15.281. Test 14:27-14:29, owner 14:29:
"it looks a lot better now". Log: 5 travels: hidden 3.3 s after the request (4x) or at the teleport (1x, 14:28:11: the
teleport came first), shown again "loaded" after 5.7-8.9 s; once (14:27:46) "no teleport came, after 3.7 s" (shown 7 s
after the request without a teleport: a cancelled travel? not asked yet).
Owner 14:30: "when the UI reappears after the zone, the mini map doesn't appear until I move.... ?" Cause: the minimap's
own old rule (TeleportCount up -> hidden until the player moves, 2-20 s) still ran beside the new server signal. Owner
14:31: "yes of course the old signal needs to get cleaned up ..." -> Rule 0n. **0.15.282 to Development (built 14:35):**
`g_travel_signal` (set on the first "travel 1" from the server): the old rule no longer starts once the signal was seen,
and the signal's end also ends it (log "fast travel: the minimap's own rule ended by the server's signal"). The old rule
stays only for a server without travel_hide.lua. To test: fast travel, the minimap must come back with everything else.
Owner 14:39: no fallbacks (Rule 0n). Proposed 0.15.283: remove the old TeleportCount rule and g_travelling entirely
(the minimap is a Layer, so g_travel_hide already hides it).
Owner 14:41 on 0.15.282: "it looks like it worked, go ahead and update dev" -> **0.15.283 to Development (built
14:42)**: g_travelling, g_travel_signal and the TeleportCount block are gone from the DLL; travel_hide.lua is the only
fast travel hide. Owner 14:41 on the 14:27:46 travel: "no something glitched out on the game and it took wayyy longer
to zoned/load". Client log: request ~14:27:42.9 (map closed), hidden 14:27:46.2, shown 14:27:49.9 by the 7 s
CANCEL_AFTER timer, teleport only at 14:28:11.2 (28 s after the request): the UI showed for 21 s of that loading screen.
Proposed fix (not done): drop the 7 s cancel timer, keep hidden until loaded (60 s LONGEST cap), unless a fast travel
can be cancelled in game (asked the owner 14:43).
Owner 14:50: "ok restart it now, but this isn't worth losing your shit over right now" -> the 7 s cancel timer fix is
PARKED: a WATCH item only, no fix unless it repeats (owner 14:54: "one rare one off glitch != do a fix"). Restart into 0.15.283 at 14:50.
Owner 15:20 on 0.15.283: "the UI seems to act correctly with the zoning, you could probably wait 2 seconds longer
before taking the UI off" and "at that point you cant cancel it and theres no need to wait or listen for a cancelled
teleport". **0.15.284 to Development (15:21, server Lua only, travel_hide.lua):** HIDE_AFTER 3.3 -> 5.3 s; the teleport
(about 4.2 s after the request) no longer hides by itself when the request was seen; the 7 s CANCEL_AFTER rule and its
"no teleport came" path are removed (the 14:27 slow load is covered by this now, by the owner's direction); LONGEST 60 s
stays only as a cap. Log line now gives the hide and the teleport times after the request.
**Fast travel UI item DONE** (owner 15:25: "thats good we can cross that one off the list"). 0.15.284 loads at the
next restart (no yes for a restart yet).
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
1. Combat behavior (next after follow/safety). **Owner's design, 2026-11-18 20:09, verbatim:** "You press 'E' on the
   campanion, there should be an "Attack" menu you can select. In the attack menu, you have 4 options. Passive,
   Defensive, Aggressive, and Healing. Each mode determines how the campanion acts and responds in battle situations.
   Passive: the campanion doesn't attack at all. Defensive: the campanion does not seek after monsters, but if
   attacked or if the player is attacked, the campanion will respond by attacking the monster. If he's hurt and the
   player is a good distance away, he should come running back, if the player is near by, he should just keep
   fighting. Aggressive: campanion seeks out targets that are in range and automatically attacks them. He will jump
   to the next nearest target in range until there is nothing left to kill. Only stops when he dies or is moved back
   to passive mode. Healing: Healing is like passive mode, campanion never attacks, but has the added responsibility
   of watching their player, keeping him healed up and tries to stay out of the combat. Monsters don't tend to run
   away so I don't think chasing monster will be an issue, but there should be a maximum distance the campanion
   should be at before running back. How close he gets to monster before attacking I'm not sure -- we'll have to pick
   a distance and adjust it based on game play -- 10 m or 15 m? The bite plus lunge enough for now for damage -- we
   can expand that later if it makes sense. Campanion stays in whatever mode you set it in until you change it."
   Known from 2026-11-17 tests: bite (attack 0, 0x63FE3237, 2 m) and lunge (attack 1, 0xC34733A8, 4 m) start through
   the C++ trigger (fkprobe.bite) with real damage (faction 11; level 50 bite 420); facing via fkprobe.face; the HIT
   log has attacker/target/amount for every hit on or by a companion. Claude's restatement 20:10, owner 20:11 "yes that
   all lays out right": Defensive = only a monster that hits him or the player; badly hurt (under 30% health) and the
   player more than 15 m away -> runs back, player near -> keeps fighting. Aggressive = any monster within 15 m of the
   PLAYER, then the next nearest. Every mode: more than 30 m from the player -> runs back. Lunge from 4 m, bite from
   2 m, paced by his own animations. Healing: how it heals is decided later. Build order: 1 the menu (no fighting),
   2 target logging only, 3 Defensive + Aggressive fighting, 4 Healing.
   **Step 1 done 20:12 (server Lua only, live, no restart; git):** the wheel is Follow me / Stay here / Attack / Put
   away; Attack opens a second wheel Passive / Defensive / Aggressive / Healing (title shows the current mode); the
   pick is matched by its label (the game side sends the label back, so no game update); kept in the roster as
   `fight` (none = Passive, Claude's default); notice "<name>: <mode>."; log "fight: <name> (<id>) <was> -> <mode>".
   Owner 20:22: "looks good for now seems to work" (log: Healing -> Passive -> Defensive).
   **Step 2 (watching only) live 20:24-20:26 (server Lua, git):** threats from the hit handler (a monster's hit on a
   following companion or his player); a monster scan for Aggressive companions (world:entities() once a second, walked
   over steps within 30 ms / 6000 entities; "fight scan: ..." once a minute); once a second per following companion
   "fight <name>: <mode>: would attack <id> (<why>; faction, health; m from him)" / "nothing to attack" / "never
   attacks", "; would run back: ..." (more than 30 m from the player; Defensive: hurt under 30% and the player more
   than 15 m away), logged when it changes. Monster = DynamicEnemy01BehaviorState, not ours, faction not 7/8/11; alive
   = NetworkHealth.health > 0. His health: Health.dataStorage [1]=3680 [2]=0 [3]=3680 [8]=3680 at full health: max
   taken as [3], NOT confirmed (the slots are logged again the first time he is hurt).
   Test 20:26-20:39 (owner 20:39 "we did lots of in and out around monsters"). Log: threats noted for hits on him and on
   the player; Defensive and Aggressive picks right (faction 4 monsters, health 1788-2168); Aggressive moved on to the
   next nearest after a kill (20:35:37); the scan: 41,277 entities in 7 steps, 5 monsters within 15 m. Max health
   CONFIRMED: hurt [1]=3226, [3]=3680, [8]=3680 -> [3]. He died once at 20:35:17 (Defensive, monsters hitting him).
   Seen for step 3: "nearest to him" flips between monsters as he moves (36361/36362/36363 alternating 20:35:41-56):
   in the real fight he must keep his target until it dies or is out of reach. 20:40: the log line now only when the
   mode, the monster or the run-back changes (it was every second: the distances in it changed).
   **Owner 20:47 GO for step 3:** "go ahead, he just needs to lock on a target that he picks until its dead, then make a
   new choice". (Claude keeps the owner's 20:09 run-back rules as the only interruptions: 30 m from the player, and
   Defensive hurt + player far; after that he picks again.)
   **Step 3 built 20:47-21:00 (git), waiting for the restart:**
   - C++ (`server_probe.cpp`, DLL md5 2f4bc191 installed, the loaded one renamed `.old_2100`): start_sequence (the bite
     test's trigger code, shared); per driven companion every step: combatData.selectedAttackIndex 0 = bite
     0x63FE3237, 1 = lunge 0xC34733A8 -> the move starts, the field goes back to 255 ("fight bite/lunge: sequence ...
     written" in the log); combatData.lastTargetId != 0 -> he faces that entity (like fkprobe.face).
   - Lua (`npc_probe.lua` md5 dfca9963, installed at the restart): drive_fight (a part after drive_jump_follow; true
     while he fights): Defensive/Aggressive only; picks the nearest candidate every 0.5 s when he has none
     (fight_pick: threats; Aggressive also monsters within 15 m of the player) and keeps it until it is dead; ends
     sooner only by the run-back rules (he is > 30 m from the player; Defensive: under 30% health and the player
     > 15 m away) or the monster > 30 m from the player; runs at it (homeZone/movementTarget = the monster: the native
     hook stops him 2 m off; edge stop on), faces it, lunge from 4 m, bite from 2.5 m; the next attack waits until
     his Actor.currentServerAction.animationStateId is back to 0 (at most 3 s, logged as TIMED OUT). The step 2
     "would attack" lines are gone (Rule 0n); fight_watch only clears old threats and logs his health slots.
     Logs: "fight <name>: attacks <id> (...)", "lunge/bite at <id> (x m)", "<move> over after x s (started after n
     ticks; animation ...)", "stops fighting <id>: it is dead / runs back: ...".
   - Fake-world test (local_server/tests via /tmp fighttest): lock-on, lunge then bites, waits for each move, next
     target after the kill; following unchanged (drive_harness: no errors).
   - Restart 20:59-21:00 (owner 20:58 "yes"). Owner 21:07 "where are all the monsters lol" (scans: 0 within 15 m up at
     y 1126). Fight at 21:11:22-21:11:43: locked on, bites 280/350/450 (one 900), killed several (33739, 31741,
     31618); he died at 21:11:43 and 21:14:25 (25 hits on him in about 20 s). Owner 21:15: "he's attacking things
     that are not there": 21:14:50 he locked on 31809 (it had hit the player), stayed exactly 4.0 m off and lunged
     every ~3.5 s; his hits landed on entity 3055812669 for 0. Owner 21:17: "he was attacking mushrooms and things
     that were not monsters I think". C++ bug seen: each attack start written ~7 times in the same tick (the hook runs
     several times per step; the 255 reset is not seen in time): guard per entity per tick at the next rebuild.
     Proposed (not done): out of reach = no progress toward his target for 3 s and no hit on it -> drop it, skip it 20 s.
     21:18 logging (live): every threat and every target described: faction, the template's model
     (world:template("ModelResource", id).model), and which of DynamicLocomotion / DynamicPathWalker / NetworkHealth /
     Animal / MovementCollider it has (to tell fixed plants from creatures by data).
   - Owner 21:20 "does the dog have any armor or defensive numbers, he seemed to die pretty quick"; 21:21 "lets just do
     more logging first". Known: no Armor/ArmorPoints component; his hits taken at 21:11: pierce 238, cut 206 (melee),
     shroud magic 48-170; ~7 monsters, 25 hits, ~3,700 in about 20 s. 21:22 logging (live): his defence once per body:
     DamageSusceptibility [0 1 0.8 0.6 1.5 0 0 0 0 1 1 1 1 0 1 1.2 0.6 0.8 1] (19 multipliers, which slot is which
     damage type NOT known), DamageMod [0.5 0.5 1 0], Armor none, ArmorPoints none, Level [50 105], max 3680; every hit
     on his player by a monster ("the player took ..."), and every 10 s with hits "last 10 s: took n hit(s) from m
     monster(s) [type amount ...]; dealt x in y hit(s); his health". Options for later (owner to pick): more health
     per level, lower susceptibility per type, or both.
   - Fight data 21:22-21:30 (owner 21:30 "have a lot at the data"): the same monster's hit on the player vs on him:
     46515 cut/pierce 41-82 on the player, 166-256 on him; 46555 fire melee 82 on the player, 545 on him. Burning ("fire,
     other") 102-112 a tick, many ticks: 2,755 in one 10 s at 21:27 (killed him). His bites 420 (600 some). All targets
     real creatures (faction 4, DynamicLocomotion+DynamicPathWalker+NetworkHealth+MovementCollider). Owner 21:34 "I saw
     him attacking a door": 21:29:20-33 locked on 46554 behind it, 3.1-3.9 m, 8 lunges, hits on object 2969043268 for 0
     (its health 160 -> 140); same as 21:14 (4.0 m, object 3055812669). Owner 21:35: "I'd drop that to like 2 seconds
     and he definitely needs "Armor"". **Done 21:36 (Lua, live, git):** out of reach = not within bite reach (2.5 m),
     no 0.3 m closer and no hit of his on it for REACH_TICKS 120 (2 s) -> let go ("stops fighting ...: out of reach"),
     not picked again for SKIP_TICKS 1200 (20 s). Owner 21:37 "build it" (armor = one third of every damage type).
     **Armor done 21:38-21:40 (Lua, live, git):** match_armor (setup + every second): DamageSusceptibility[i] = base[i]
     x ARMOR (1/3); the base is read once from a body and kept in the roster as `sus_base` (saved), so a reload never
     scales twice (world:template("DamageSusceptibility") gave nothing). HOUND_SUS = the hound's own values (logged
     21:22) recovers bodies the first 21:38 version had already scaled. Live: N1 and N2 at [0 .33 .27 .2 .5 0 0 0 0
     .33 .33 .33 .33 0 .33 .4 .2 .27 .33]. Logs "armor: ...". Expected: physical melee ~55-85 instead of 166-256, fire
     melee ~180 instead of 545, burning ~35 a tick instead of 102-112 (to be checked in the next fight).
   - 2026-11-19 07:28 the owner rejoined (server up since 20:59); armor applied to each respawned body from the saved
     base (07:28, 07:29, 07:33). 07:29 and 07:33 (following, not fighting): a 2.7 m step up; he jumped (13 m/s up,
     0.6 m out), came back down at the bottom, collider "touching" true; one try per crumb -> can't follow -> respawn.
   - **Owner 2026-11-19 07:50, verbatim:** "I do think we'll need a new specific "pathing" system to handle obstacles
     and better navigation on the battle field... we need to dial in to make sure he's attacking monsters, etc
     hopefully you have all the logging in place for this. I saw him getting stuck on fences and other things. he has
     a good jump ability so we'll need to think about having him jump over that stuff, maybe use some of the older
     techniques we used in the old pathing system to avoid objects. just some ideas. we'll test things one at a time
     and improve it one bit by one bit". 07:51 logging (live): "fight <name>: stalled on the way to <id>: x m away, y
     m above/below him, no closer for 0.5 s; his state, speed; collider: touching, a player, last slide side; ground
     (distance, walkable, normal y), standing on" + "fight stall: ... in his way: ..." (once per stall). Material from
     before: the C++ probe has a ground ray and the game's walkable search (fkprobe.gr..., "ground program",
     PathGridSystem) from the 2026-11-17 experiments.
   - Owner 08:33: "he's trying to go after bats, the bats move around a lot so he's not tracking them very well. he
     makes some attacks, but a lot of times he's not facing them. I also notice he keeps keeps coming back to me
     instead of staying locked on a monster." Log 08:31-08:33: bats faction 6, 1.4-2.4 m above him; 28 attacks, one
     hit the bat 63138 for 350 (killed it), the rest hit objects for 0; the 21:36 out-of-reach rule dropped a bat every
     2-3 s (~15 times) -> nothing left -> back to following. C++ faces the target only when he stands.
   - **Owner 09:03, THE ATTACK SEQUENCE SPEC, verbatim:** "we need to keep this simple. let me restate what
     specifically needs to happen and spell out what I think you need to do exactly: once he detects and goes into
     "attack mode" the code that makes him follow and return to me needs to stop until he gives up on his attack
     sequence. attack sequence: he picks the nearest target. he shoots a ray at the target to make sure there's
     nothing blocking him. he shoots the ray to try and avoid fences, walls, trees, and objects that could block his
     path to the monster. if the rays gets blocked, he picks the next nearest target until he finds one that isn't
     blocked. this ray stays up the whole time (or is shoot out repeatedly during the fight) to make sure nothing new
     blocks him and the monster he is fighting. he locks on to that target, always facing the target no matter how it
     moves. of the target moves, he moves to face it. he runs to the target attacks as frequently as he can. he does
     not leave it and attacks it until its dead unless the ray becomes blocked and he can no longer deliver attacks.
     monsters move around a lot during the fight so he will need to frequently check for a block with his ray. if he
     gets blocked he can try to jump and move around to reposition himself in an attempt to get around the block. if
     he cannot, he stops attempting to fight that target and repeats the attack sequence to find another target and
     continue fighting. the attack sequence ends when he cannot find another target to attack after several tries OR
     until all the monsters are dead."
     Claude's reading 09:1x: attack mode stops following/returning; nearest first, a C++ ray from his shoulder to the
     monster's middle, blocked -> next nearest; the ray every tick; faces it every tick; attacks as often as his moves
     allow until dead; blocked mid-fight -> a hop toward it, then 2 m left, then 2 m right (~1 s each), still blocked
     -> drop it (not again for 20 s) and pick again; end = nothing reachable on 3 tries 1 s apart, or all dead.
     **Owner 09:17, verbatim:** "3 tries before giving up on the attack sequence might be too few, but we'll start
     there. you can keep the 30 m leash for now, but he's not likely to exceed that as the player will typically be
     close by. I want to get rid of the requirement for the "running back when badly hurt with you far away."
     mechanic for right now. Defense mode mainly means he attacks only if something attacks us." -> the hurt rule is
     REMOVED; the 30 m leash stays; Defensive = only what attacked him or the player.
     **Built 2026-11-19 09:22 (commit 191329c), NOT yet tested in game:** C++ `fight_step` (server DLL md5 6990b645,
     installed; the one before renamed `fk_server_probe.dll.old_0922`; `.old_2100` still there): every step a ray from
     his shoulder (+0.7 m) to the target's middle (+0.5 m) for `combatData.lastTargetId`, clear = no hit or a hit within
     1 m of the target -> `combatData.isTargetReachable` / `distanceToTarget`; log "fight ray: ... clear/BLOCKED" on a
     change; the attack start once per step (the guard; it was written ~7 times per tick). Lua `drive_fight` = the
     sequence: pick (each candidate nearest first: lastTargetId = it, 2 ticks, read the ray; he stands still), fight
     (locked on; hold_at the target; attacks paced as before), blocked -> hop toward it, 1 s left 2 m, 1 s right 2 m,
     then dropped for 20 s and pick again; nothing reachable -> try again 1 s later, after 3 tries the sequence ends
     and the monsters that were blocked are skipped for 20 s too (else it starts again at once on them and he never
     follows the player; seen in the fake-world test). Following stops while the sequence runs. Logs: "fight N1: the
     attack sequence starts/ends ...", "attacks", "is blocked", "repositioning", "hops", "moves 2 m", "gives up",
     "clear again", "is dead", "picks again", "try n", stall lines. The Lua (md5 fdedea51) is staged in
     claude_scratch/seq_npc_probe.lua and goes on the server with the restart (the old DLL never writes the ray).
     **Owner 10:25, verbatim:** "the only one thing that needs to get added, if the player sets the companion back to
     "passive" during the fight, the companion should completely stop the attack sequence and return to following the
     companion. one other small detail, when the companion is in defensive mode and responds to an attack, it should
     automatically switch to aggressive mode to keep fighting all monsters in the near area as any monsters around
     won't stop fighting". Built 10:3x (Lua only, md5 in the commit after 6e710d3): Passive (or Put away) ends the
     sequence the same tick (it already did: the mode check at the top of drive_fight every tick; fake-world test:
     ends at once, his target cleared, sent back to the player) -> he follows the player ("following the companion"
     read as the player). Defensive: the sequence starts only on a threat (him or the player hit), then he fights
     every monster within 15 m of the player like Aggressive until the sequence ends (the monster scan runs for him
     while it lasts); the menu's mode stays Defensive, so the next sequence again waits for an attack. Log: "the
     attack sequence starts (Defensive, something attacked: he fights like Aggressive until it ends)".
     **First test 2026-11-19 10:31 restart (DLL 6990b645 + Lua bf32a0d8).** Owner 10:38 "its not facing the target";
     "he killed the first target quickly"; "it looks like he hasn't picked a second target and locked on to it"; 10:39
     "the dog is just standing idle now". Log: 26929 (faction 6) one lunge, 500, dead (10:37:49). 26930 (faction 6, not
     moving, 0.1 m below him): ray clear, he got from 7 m to exactly 4.0 m and lunged 12 times ~3.3 s apart
     (10:37:50-10:38:48), no hit on it; at 10:38:48 the lunge hit three objects (2578711003/13/08, health 20/100, for 0:
     plants or props); then he stood (not closer, no lunge, the stall line once only) until the 10:40:12 reload, which
     reset the sequence: picked 26930 at 6.1 m, one lunge from 4.0 m, 500, dead. Same as 2026-11-18 21:14 and 21:29
     (4.0 m, hits on objects for 0): the THIRD time -> a pattern, not a one-off. The ray (0.7 m up to 0.5 m up) misses
     low things in his way. Logging 10:41 (live): every lunge/bite "he faces x deg off it; it at ..., moving v m/s, n m
     above/below him; him at ..." and at its end "he moved x m, now d m from it (was d0)".
     **Owner 10:40, verbatim:** "the dog should stay centered on me within my radius and kill anything in it".
     Claude 10:42 proposed (a) the radius: a 15 m circle around the player that moves with him; only monsters inside
     it; a target that leaves it is dropped; he ends the sequence outside it; it replaces the 30 m leash; (b) "can't
     deliver attacks" = his attack lands on an object, or no closer for a while -> the reposition steps. **Owner
     10:43, verbatim:** "yes. he definitely wasn't "stuck" though. he was idle and didn't come back to me, it looked
     like he wasn't searching for the next target." Cause found in the log: 10:38:49 the C++ edge stop "27129 stops
     at ... (ground 1.5 m ahead: a drop the player did not take, 0.88 m down)" (the edge stop is ON in fights,
     targetOfMyTarget = false) -> he stood; the ray was clear and the target alive, so the sequence kept him "fighting"
     and nothing moved him. **Built 10:5x (Lua, live by reload, NO restart):** FIGHT_LEASH removed; candidates (threats
     too) within FIGHT_RANGE 15 m of the player; a target past 15 m from the player is dropped ("left your 15 m
     radius"); the sequence ends when he is more than 15 + 2.5 m from the player. Can't deliver attacks = the ray
     blocked, OR his attack hit an object and not it (his hits noted by note_my_hit; another monster is no block), OR
     no hit on it and no 0.3 m closer for NO_HIT 2 s -> a reposition step (hop / 2 m left / 2 m right), 1 s, then he
     tries again from there; after the three -> gives up on it (20 s) and picks again; a hit on it starts the steps
     over. Logs "can't deliver attacks on X (why; d m away): hops/moves", "tries X again from here", "gives up on X:
     why after the hop, left and right". ~~Not done (to propose): the edge stop off in fights.~~ -> **WATCH, not a
     to-do** (2026-11-20, see below).
     **Owner 11:11, verbatim:** "the radius change definitely kept him more focused at least the last 2 fights. he still
     struggles to face the targets however. he attacks, lunges and then takes too long to turn around. now there are 2
     monsters attacking me and he took like 10 seconds to even respond to that, still better than before". Data
     11:10:09-11:10:59 (facing logging): degrees off the monster when an attack starts: -5, -23, -156, -121, -42, -119,
     -136, +93, +101, -23, -89, -79; the monsters mostly standing (0.0 m/s) -> not a moving target: the C++ look
     direction does not turn him in time while he stands; lunges carried him 4-5 m the wrong way ("moved 4.2 m, now
     7.0 m from it"), hits on plant 2579759654 for 0 -> he gave up on 36988 (11:10:15) and 36978 (11:10:28), skipped 20 s;
     the sequence ended 11:10:31 with both skipped although they were hitting the player; it started again at 11:10:48
     when the skip ran out (the owner's ~10 s wait). Then bites from 2.4 and 1.1 m killed both (420 each).
     Claude 11:1x proposed (1) facing: he turns himself toward it fast between attacks and attacks only when facing it;
     (2) a skipped monster comes off the skip list when it hits again. **Owner 11:17, verbatim:** "yes get the facing
     fix in asap. this is a big problem, keeping at the maximum distance he needs to be at to add the attack will be
     helpful as well because his lunge attack moves him so much. the closer he is to the target, the further he'll
     travel past the monster. this should be the default for any companion. the companion should only get just as
     close as they need to be to land the attack and no closer.... I don't know what that value is, but I'm sure you
     could tell from the data or I could try to search it, or we could test that range ourselves". **Built 11:2x (Lua,
     live by reload):** turn_toward: between attacks (not during one) his body turns toward it, at most 30 deg a tick
     (TURN; 180 deg in 0.1 s; `face` = the instant turn the following uses), and an attack starts only when he is
     within FACE_OK 15 deg; he runs at it only while farther than FIGHT_LUNGE (4 m, the lunge that hit at 10:40:13 started
     at 4.0 m), then stands where he is (bite only when it is within 2.5 m anyway); every attack's end logs "HIT it" /
     "MISSED it" with where it started (to find the real maximum reach from data); a skipped monster that hits him or
     the player again is a candidate at once ("is no longer skipped: it hit him or the player again"). "Default for any
     companion": all companions use this one drive_fight. Lunge reach: still to be measured (owner offered to search
     or test it).
     Power cut 11:38 (no fights after the 11:19 install); files checked intact; restart 12:47 via the helper (its watcher
     had to be started by the owner first: restart_watch.cmd). **Test 12:56-12:58:** switching works (12:57:13-37 five
     kills in a row, nearest first); facing FIXED (17 attacks, 0 deg off at the start, worst 12; before up to 156);
     9 lunges MISSED from 2.7-4.0 m: the monsters (faction 6) often moving up to 6 m/s, the lunge carries him ~5 m and
     ends past it, the monster behind him (the overshoot the owner predicted); a kill reset the attack, so killing
     attacks had no "HIT/MISSED" line. Weak spots told: all candidates blocked -> he stands 3 s and ends (as the spec
     says); he gave up on 26963 after lunges into a plant. **Owner 13:57, verbatim:** "yes log it, maybe increase his
     attack range by 20 m around me which will help". Logging built 13:58 (live): each hit as it lands ("his lunge's
     hit landed x s after the start on it/object/monster: he is d m from it, moved m"), his lunge at 0.4 s ("he is d
     m from it (d0 at the start), moved m; it moved m"), the killing attack ("his lunge from d m killed it x s after
     it started"). The radius: asked the owner whether "by 20 m" means a 20 m radius (from 15) or 35 m; not built.
     **Owner 13:58, verbatim:** "you're reading it right: 20 m". Built 14:0x (live): FIGHT_RANGE 20 (the radius he
     fights in, the monster scan, a target leaving it, the end at 20 + 2.5 m from the player).
     **Owner 14:02:** "theres a bat right in front of me, it hasn't attacked me yet and its a little higher position than
     were at. the dog doesn't see it?" Log (14:03 logging: positions on a blocked candidate): 26906 at 3005.4 845.0
     2846.3, 3.7 m above him, 7.9 m away; the ray hits at 2.7 m, ~2 m above his feet (the slope/ledge up to it); he
     picks it every 20 s, blocked 3 times, the sequence ends. **Owner 14:03:** "it probably looks blocked to him".
     **Owner 14:05, verbatim:** "if he hopped up he could see it for sure and jump to reach it. lets add that as a step
     to check on later. we'll make sure he can get targets right around him correctly first" -> **LATER LIST:** when
     every candidate is blocked in the pick phase, he hops (up) / repositions toward the nearest to see it, and jumps
     to reach one that is higher. Not now: first the targets right around him.
     Power cuts 14:10 and ~14:28; restarts 14:19 and 14:37 (the watcher came back by itself at 14:28). **Data 14:06-14:08:**
     lunges from 3.9-4.0 m: 6 kills at 0.38 s; one miss (the monster moved 1.5 m; at 0.4 s he was 1.7 m from it, moved
     3.1 m); bites from 0.7-2.4 m: 4 kills at ~1 s. **Data 14:21 (bats, faction 6, 1-2 m above him, up to 6 m/s):**
     facing 0 deg every time; in the 0.4 s to the hit the bat moved 2.0-2.4 m -> 5 lunges missed, 2 hit plants -> the
     reposition steps and giving up (26919 twice; it came back by biting him); 26918 killed by one lunge (1.5 m above,
     so height is not the problem). Also 14:22:04 picked 26920 at 19.5 m, dropped 0.4 s later at the radius edge.
     Claude proposed (1) aim ahead or (2) wait for it to slow. **Owner 14:52, verbatim:** "yes, bats are a good
     challenge because they are a hard target. is there a faster attack he can do against bats instead of the
     lunge?" Answer: only the bite (hit ~1 s) and the lunge (hit 0.38 s) are known; others in the hound's game data
     were never searched (a later item if the owner wants). **Built 14:5x (option 2, live by reload):** a target faster
     than FAST 3 m/s and out of bite reach: he stands at lunge reach facing it and lunges when it slows; waiting does
     not count as "can't deliver attacks" (ok_t reset); logs "waits: X moves v m/s ...", "X slowed to v m/s".
     **Owner 15:28:** "so far he's doing very well" (14:53-15:28: 42 kills, 114 attacks, 23 missed, 0 give-ups, 41 waits
     all ended with the target slowing). **Owner 15:29:** "going to play this dungon all the way through and then lets
     check the data for improvements". **Owner 16:31:** "he struggling with getting monsters that float in the air
     right now". Log: 68778 (faction 10) hovering 0.7-0.8 m above him, mostly 0.0 m/s: lunges from 3.5/4.0 m went
     under it (0.8-0.9 m from it at 0.4 s, ended with it behind him), bites from 0.9-2.4 m all missed; 68618 (0.7 m
     up) died to a lunge from 4.0 m. Claude proposed (1) jump into the attack, (2) lunge from farther. **Owner 16:32,
     verbatim:** "yeah lets see how that goes, he's done well otherwise I think". **Built 16:4x (option 1, live by
     reload, an experiment):** a target HIGH 0.5 m or more above him: when the attack has started he is lifted 0.3 m
     and gets upward speed launch_speeds(0, rise) (rise 0.8 -> ~8.7 m/s), rewritten for up to 6 ticks until he is in
     the air; the attack's forward move is not touched; h.djump NOT used (the follow jump code stays out). Logs
     "jumps into his bite/lunge (up v m/s)", and the 0.4 s line "he is h m higher than at the start, it is x m above him".
     **Owner 16:35:** "he lags behind me a bit more than I'd like for a dungon run.. anyway to keep him closer to me while
     running?" Cause: the C++ picked his speed by straight distance only (walk < 6 m, run 6-12, sprint > 12). Claude
     proposed (1) lower steps, (2) his pace from the crumb meta data (list #8) + sprint when behind. **Owner 16:37:** "I
     agree #2". The player's crumb speeds (6700 crumbs in the log): ~2-3 m/s walking, ~4-5 running, ~8-9 sprinting.
     **Built 16:40:** Lua: every tick PACE_WALK into combatData.prowlAngle (his AI is off, nothing else writes it);
     drive_steer: the crumb he heads for: spd >= 7 sprint, >= 3.5 run, else walk; log "pace <id>: walk/run/sprint (the
     player at that crumb: v m/s; player d m away)" on a change. C++ (DLL 30da7118, installed for the next start; the one
     before renamed fk_server_probe.dll.old_1640; .old_0922 and .old_2100 still there): speed = sprint if more than
     kCatchUp 6 m from where he is headed (the player; in a fight the monster), else the Lua pace; the old 6/12 m steps
     are gone. drive_harness: identical to the commit before on 9 seeds apart from the pace field. Lua live 16:40 (the
     old DLL ignores the pace until the restart).
     Restart 17:22 (owner 17:21 "ready to restart"). **Owner 18:39:** "you should have a lot of data to analyze now".
     **Data 17:22-18:39 (no errors):** 49 sequences, 252 attacks; ground bites at level monsters 26/31 hit or kill,
     ground lunges 15/18; 67 waits, 66 slowed; 14 give-ups. Jump attacks (floating monsters 0.5-3.3 m above): he rises
     2-3 m by 0.4 s; jump LUNGES 20/25 hit or kill, jump BITES 5/22. 30 of 47 sequence ends = everything left blocked:
     97 of 129 blocked checks were monsters >= 1.5 m BELOW him (another floor; the ray hits his own floor's edge), 20
     monsters; each such sequence held him still ~3 s, again every 20 s. Pace (at each change, player away median):
     walk 2.5 m, run 3.1, sprint 5.1. Can't follow 18x -> 15 respawns (7 drops too high, 11 blocked/up), the same kinds
     as before. Claude proposed (1) a target HIGH or more above him: lunge only; (2) he keeps following while he checks
     the candidates. **Owner 18:47, verbatim:** "yes, overall he did well for a pet". **Built 18:5x (Lua, live by
     reload):** (1) ix = bite only when within FIGHT_BITE AND less than HIGH above him, else lunge; (2) the pick phase
     returns false (the following goes on) while it checks (lastTargetId set, RAY_WAIT, the ray read); he stops only
     once a target is locked on.
     **Owner 19:17:** "any reason why he's not attacking the current monster?" Log: 19:16:09 locked on 171975 (faction 15,
     DynamicLocomotion+DynamicPathWalker+MovementCollider, NO NetworkHealth: a part of a monster), its Velocity a
     constant 20 m/s while it did not move (0.0 m in 0.4 s) -> the bat wait forever (waiting resets the no-hit rule);
     171973 beside it (with health; one jump lunge hit it for 400) hit him 8 times, 3680 -> 2751. Claude proposed (1)
     only entities with NetworkHealth are monsters; (2) a target's speed from how far it really moved (~0.25 s), not
     its Velocity. **Owner 19:18, verbatim:** "yeah #1 for sure for ahead". **Built 19:2x (Lua, live by reload):**
     is_monster needs NetworkHealth; monster_alive: no health = not alive. #2 not built: asked whether "go ahead"
     covered it.
     Live 19:19; at once he attacked 171973 (the real monster). **Owner 19:20, verbatim:** "put it on the list, but it
     probably won't come up again" -> **LATER LIST:** a target's speed for the bat wait measured from how far it really
     moved (~0.25 s) instead of its Velocity (only matters if a real monster reports a wrong speed; not seen since #1).
     **Owner 19:21:** "does that dog have any mana? can he do heals?" Logging 19:21 (live): the hound has NO Mana,
     ManaRegeneration, HealthRecharge or HealingMod (only Health 3680 and Stamina 335; he never heals himself); the
     player: Mana 483, ManaRegeneration, HealthRecharge, HealingMod x1.15. FlameKit can heal: emf.attribute_add(...,
     "health", n) (the game's attribute code, stops at max). **Owner 19:25, verbatim:** "yeah write it up, as for how
     much mana and how much heals... im not sure. I only have 483 mana at level 50, but im not spec'd as a mage. I would
     give him 800 mana and see how that works? how would a heal animation work with him? nothing for him I would
     imagine?" -> Claude's take (was written as local_server/HEAL_PLAN.md; **owner 20:27:** "yeah delete that, I don't
     actually need a write up, I just meant give what you think" -> deleted, in git history): his mana is ours (the
     game gives him none), 800, refills 10/s; in Healing mode he heals the player below 60 % for 25 % of max health
     (200 mana, 4 s apart, within 20 m), then himself the same way; otherwise as Passive; no heal animation known (only
     bite and lunge): he turns to the player, a notice, the health bar rises. Open: the numbers; healing himself
     outside Healing mode too; a notice per heal or not. Nothing built.
     **Owner 20:27:** "will he be able to heal himself in defense and attack modes too?" Claude's take: one mana pool and
     one heal for every mode; Defensive/Aggressive: he heals only himself, at ~40 % (mana lasts the fight), no
     animation so it never stops an attack; Healing: the player first, then himself; Passive: a slow recovery between
     fights. **Owner 20:35, verbatim:** "yes that would be good, did you find a howl animation he could do" -> the
     healing design above is agreed (not built). Howl: never searched; his moves start by sequence id (FNV-1a of the
     sequence GUID) through `fkprobe.bite <entity> <hex>`; the hound's other sequences would come from the game data
     (claude_scratch/tpl has kfc.py and the template lists). Asked the owner whether to search.
     **Owner 20:39:** "yes" (search). **Found (device scripts $HOME/hs/seqs*.py on the kfc.py reader; all 2157 action
     sequences = resource type 0x9fd4a561; id = FNV-1a 32 of the GUID's 16 bytes as stored (bytes_le)):** the hound's
     bite/lunge are the WOLF's: 0x63FE3237 Enemy_Wildlife_Wolf_Attack_Bite, 0xC34733A8 ..._Lunge; jump 0xE80706FC
     Enemy_Jump_Move. Other wolf/dog sequences: 0x89A1BC53 Wolf_Shout, 0x0BA28FDE Wolf_Ability_LickWounds,
     0xEE2A75E2 Wolf_Heavy_Opportunity_Howl, 0x60BD6595 Wolf_Heavy_Attack_Bite, 0xE5DAC59D Wolf_Heavy_Attack_Dash,
     0x538A6913 Wolf_Heavy_Attack_Stomp, 0x04F7403E Wolf_Sleep, 0x405E2057 Wolf_Spawn, 0x59DF6580
     Wolf_Reaction_Stun_Long, 0x45A6AA69 Enemy_Skeleton_Hound_Death, Pet_Dog_*: 0x194F5236 greeting_bark, 0xD76BB71B
     Idle_01_bark, 0xF59B6263 Sit, 0xACD28521 Idle_02_sniff, 0x88F25807 Sleep, 0x4DA2D783 Idle_Sad, 0x66D08E3F eating,
     0x0D240B10 being_petted_01; Interaction_Pet_DogCat_Buff 0xB1EB4A70. The full list: $HOME/hs/seqnames.tsv (device
     scratch, not kept). **Played on N1 (254966) 20:40:28-20:41:16, 8 s apart** (fkprobe.bite via commands.txt): 1
     Shout, 2 LickWounds, 3 Heavy howl, 4 dog greeting bark, 5 dog idle bark, 6 dog sit, 7 wolf sleep; all written
     into his trigger; what played: asked the owner.
     **Owner 20:48:** "I missed them all I had no idea you did it... can you output the text as you do them for each
     one" -> played again 20:48:48-20:49:49, a SendUserMessage right as each starts (do it that way for any visual
     test). **Owner 20:51:** "I wanna see 1 2 and 3 again" (played 20:51:11/22/34). **Owner 20:55:** "I didnt see any
     heals go out I like 1 and 2 not sure which one yet" (he was at full health since a 20:37 respawn, so the move's own
     heal, if any, could not show). Claude suggested Lick Wounds for healing himself, Shout for healing the player.
     **Owner 20:58, verbatim:** "Lick Wounds lets go with" -> the heal move: Lick Wounds 0x0BA28FDE (asked: for every
     heal, his and the player's?).
     **Owner 20:59, verbatim:** "I changed my mind, I want Wolf Shout" -> the heal move is **Wolf Shout 0x89A1BC53**
     (replaces Lick Wounds; asked again: for every heal?).
     **Owner 21:01, verbatim:** "every heal would be a good queue that its happening" -> Wolf Shout plays on EVERY heal
     (his own and the player's), as the cue that a heal happens.
     **Owner 21:01, verbatim:** "yeah lets build it now". **Built 21:1x (needs the restart for the shout):** Lua
     `drive_heal` (called every tick after drive_upkeep, never takes over the movement): mana_of[name] (FlameKit's own,
     MANA_MAX 800, refill MANA_REFILL 10/s in every mode, full again after a Lua reload); a heal = emf.attribute_add
     "health" 25 % (HEAL_PART) of the target's max, 200 mana (HEAL_COST), HEAL_GAP 4 s apart, plays Wolf Shout
     (combatData.selectedAttackIndex 2); Healing: the player below 60 % (HEAL_BELOW) within 20 m first, else himself
     below 60 %; Defensive/Aggressive: himself below 40 % (HEAL_BELOW_FIGHT); Passive: no heals, recovers 2 % of his max
     a second (RECOVER_PART) after 10 s without a hit (RECOVER_AFTER; h.hit_t set in note_threat), no mana, no shout.
     Not while one of his attacks plays; the fight starts no attack while a move is asked or within SHOUT_TICKS 1.5 s of
     a heal; the heal waits for the fight's first step (it clears selectedAttackIndex). His health from
     Health.dataStorage [1]/[3]; the player's from emf.attribute "health"/"max_health". Logs "heal <name>: heals the
     player/himself +n (... before; mode); mana a -> b of 800; Wolf Shout", "would heal ... but has n mana",
     "recovers ...", "recovered". C++: selectedAttackIndex 2 -> start_sequence 0x89A1BC53 "heal shout". Fake world:
     Healing/Aggressive/Passive as above; drive_harness identical on 5 seeds. Not proven in game: emf.attribute_add
     "health" on the hound's body.
     Restart 21:14 (owner "yes"). **In game 21:20-21:29:** heals himself +920 (Aggressive 21:20:35 at 1085/3680; Healing
     21:28:16, 21:29:03), heals the player +629 (25 % of 2515) three times; every heal played the shout (C++ "heal
     shout: sequence 89a1bc53 written"); no "could not add health". **Owner 21:29, verbatim:** "can you add a notice
     message that says Companion heals you for <number>!" -> built (live by reload): on a heal of the player, say()
     "Companion heals you for <n>!" (the 5 s chat notice, features.chat notice_to).
     **Owner 21:31:** "maybe make the text green colored?" -> say() takes a colour; the heal notice is #5ad25a (live).
     **Owner 21:48:** "seems to be working, what do you see?" 21:31-21:48 (Healing mode): 4 heals of the player (+629, 2
     pairs 4 s apart, mana right, every shout played), no errors; but both pairs line up with a "can't follow: blocked"
     0.5-0.6 m from his crumb on flat ground (21:33:30, 21:38:46) -> respawn: the Wolf Shout holds him in place, two
     4 s apart = the stuck rule. Other respawns: 3 glide, 1 fast travel, 3 can't follow (steps, long jumps). **Owner
     21:54:** "yes" -> built (live): drive_stuck restarts its progress timer for SHOUT_HOLD 2 s after a heal (h.heal_t).
     **Owner 22:00:** "when were not in combat, or combat finishes, he should heal me up full regardless of my %".
     Claude asked (Healing only? the reading). **Owner 22:04, verbatim:** "when he's in heal mode, he should just always
     heal me to full, when he's in attack or defense I meant more like when all the attack sequences are all done, he
     should do full heals on himself and me, but can wait until all attack sequences are done". **Built 22:0x (live):**
     Healing: the player within 20 m up to full, always (HEAL_FULL 0.99: a heal when 1 % or more is missing), else
     himself below 60 %; Defensive/Aggressive: during an attack sequence (h.atk) only himself below 40 %; with none
     going on, the player and then himself up to full. Passive unchanged. The heal itself unchanged (25 %, 200 mana,
     4 s apart, Wolf Shout, the green notice for the player).
     **Owner 22:09:** "is there way to add an healing spakle animations?" The game's heal VFX templates (claude_scratch/
     tpl/templates.csv) spawn with emf.spawn (as the loot mark, ground_loot.lua MARK_FX). Built (live 22:12): console
     `flamekit.npc healfx <n>` spawns HEAL_FX[n] on the nearest player for 10 s (emf.destroy in F.tick): 1
     VFX_Resource_Increase_Health 2c411630-8a38-41a3-b3d2-a263609a1bdb, 2 ..._NoSound b8e9aca9-..., 3
     VFX_Enemy_Skeleton_Melee_Elite_Heal_Ally_Player_Companion 35183e7f-..., 4 ..._Heal_Ally 100772b0-..., 5
     VFX_Skill_Martyr_Heal 21443035-..., 6 VFX_Ability_Casting_Heal_Channel af4436da-..., 7
     VFX_Spell_ChainHeal_SourceTarget_player fc4f8028-..., 8 ..._NoTarget c15e5bc4-... Shown on the owner 22:12:29-
     22:14:31 (all 8 spawned, a message as each started); which looked good: asked the owner.
     **Owner 22:15-22:16:** "show me #1 again"; "#1 is the only one I saw do anything, can you run that one again?";
     22:17 "run the effect on the dog now so I can see it there" (healfx got an optional target: healfx <n> [entity];
     shown on N1 127633 22:17:47; the effect stays where it was spawned). **Owner 22:18, verbatim:** "yeah thats good, so
     when the dog heals himself he can do the effect, when he heals the player he can do the effect on himself and me to
     highly the heal" -> built (live): after a heal HEAL_FX[1] VFX_Resource_Increase_Health on him, and on the player too
     when it was the player's heal; removed after 10 s (heal_fx_shown).
     **Owner 22:21:** "seems good, we may have to adjust some numbers" (healing accepted; the numbers stay open: MANA_MAX
     800, MANA_REFILL 10/s, HEAL_PART 25 %, HEAL_COST 200, HEAL_GAP 4 s, HEAL_BELOW 60 % (himself in Healing),
     HEAL_BELOW_FIGHT 40 %, HEAL_FULL 99 %, RECOVER_AFTER 10 s, RECOVER_PART 2 %/s).
     **Owner 22:21:** "is there still a 2 second delay before he teleports when he has to spawn and respawn?" (yes:
     STUCK_TICKS 3 s -> the notice, TP_AFTER 2 s -> put away, back 1 s after the player stands, LAND_TICKS). **Owner
     22:22, verbatim:** "get rid of the 2 seconds, show the error, but teleport him immediately" -> built (live): TP_AFTER
     0 (put away the tick he cannot follow; drive_harness seed 1003: tick 632 instead of 753); put_away_for shows the
     same words (STUCK_TEXT[h.cant]) as a 5 s notice in #ff9050 (the stuck status is cleared at the put-away, so it would
     have shown for one tick). The 3 s of no progress before "can't follow" is unchanged.
     **Owner 22:26:** "it works well".
     Claude offered a Development build, then withdrew it (Rule 0d: all of it runs only on the server). **Owner
     2026-11-20 06:17, verbatim:** "update the changes.txt and make sure everything is checked into git for dev" ->
     **0.15.285 (server only, like 0.15.280):** flamekit/mod.json 0.15.285 (flamekit_native stays 0.15.284: no client
     change, no dist-test), changes.txt: one entry for all companion work since 0.15.279 (rebuilt following, pace,
     Attack menu modes, the attack sequence, bats/floaters, armour, healing, instant respawn). Copied to the server and
     the work folder. Git: every server file (npc_probe.lua, npc_fields.lua, main.lua) and server_probe.cpp matched the
     repo (md5) before the commit.
     **Owner 06:19, verbatim:** "I just want to make sure all the new source is checked into git.. thats all". Full
     compare of the work folder (69 files) with git: all game source identical (flamekit/, flamekit_native/src,
     server_probe.cpp, local_server/); 4 notes files newer in git (the work copies are 2026-11-13..16). Never in git
     until now, added (fe2689d): `tools/gamedata/` (kfc.py reader, template tools, arsenal*.py, tplcomp.py, the action
     sequence search seqs*.py + seqnames.tsv, templates.csv, monsters.tsv; README), `local_server/tests/fight/` (the
     fake-world fight/heal tests seqtest*/healtest*/fighttest/doortest/armortest/watchtest, harness.lua, syn.lua,
     helper .py; README), `flamekit_native/notes/map_marker_registry.json`. Left out on purpose: the work folder's
     old `notes/probes/npc_probe.lua` / `npc_wheel_probe.lua` (2026-11-17 copies, superseded; their history is in git)
     and `npc_fields.lua` (identical to local_server's).
     **Owner 06:32-06:37:** "what was the edge check in fights about?", "so he runs off cliffs without my trail to
     follow?" (no: off the trail the C++ edge stop holds him at no ground within 12 m, more than 7.5 m down, or steeper
     than 30 deg unless the player took it), "there was data to back this change up?" -> No: ONE case (2026-11-19 10:38,
     a 0.88 m step), which Claude put on the list as "to propose" by itself, against the one-off rule; since the 21:14
     restart 6 edge stops, all in fights, each ONE tick ("goes on" right after), none left him stuck. **Owner 06:37:**
     "keep it as a watch item, how did it get on the list?" -> **WATCH: the edge stop in fights** (look again only if it
     actually keeps him from a monster again).
     **Owner 06:42:** "I think I as more concerned with the times he killed himself ... can you check every time he
     died yesterday ... see if there is a pattern to why? nothing might need to be changed". 8 deaths on 2026-11-19 (the
     client logs, every session; the server log only from 21:15): (1) killed right after a respawn, 0.2-0.3 s
     (15:57, 18:56, 21:38): 21:38 a 725 hit on the new body before FlameKit set level 50 and the armour (0.2-0.5 s after
     the spawn); (2) falls after a copied jump: 21:47 (the player stepped 4.4 m down onto a narrow ledge 0.9 m out; his
     jump went 9.7 m forward, fell 20.7 m), 21:57 (the player double-jumped and glided 2.5 s / 17 m, 4.7 m lower: not a
     break because glides are excluded from the 2 s flight rule and 4.7 < 7.5 m; his jump fell short, 22.5 m), 18:30 and
     19:06 likely the same (just after "afraid to follow (drop too high)"); 18:33 unknown. **Owner 06:44:** "he didn't
     detect that the jump would kill him? why didn't he just teleport?" (no check of his own jump; nothing watches him
     in the air). **Owner 06:52:** "its common to jump before popping out the glider". **Owner 06:53, verbatim:** "I think
     safety net is a good idea" -> built (live): drive_put_away: in the air (his DynamicLocomotion.state 2) h.fall_y0 =
     the height he left the ground at; more than FALL_SAFE 7.5 m below it -> put away ("falling"), back beside the
     player once the player stands (LAND_TICKS). Log "fall net <id>: x m below where he left the ground ...".
     drive_harness: identical on 9 seeds apart from the new field (seed 7: the net fired at 7.7 m down, correct). Not
     built (offered, not chosen): the glider rule (a jump where the player opened the glider = a break), level/armour set
     on the spawn tick.
     -> **0.15.286 (server only):** flamekit/mod.json + changes.txt line for the fall safety net.
     **Owner 07:54, verbatim (the next step, companion inventory):** "the next step will be adding an inventory option.
     I'd like you to start working on that while I test out the changes. we already learned A LOT about inventory items
     so some of the questions you have about it, I already have answers to. so I'd like the "E" menu to have
     "Inventory" menu. In this menu, it has "Open Chest", "Close Chest". "Open Chest" will spawn a large chest on the
     ground. all of their inventory items the companion has on them will appear. I guess EMF has some system for this
     already, so you'll need to explain that to me. When the player is done they can choose "Close Chest" and it will
     move their inventory out to a space spot (EMF has something?) and the chest despawns... there probably should be a
     backup option where if the user forgets to close it, it despawns within a specified time (but items cannot be lost
     when that despawn happens)". **Research (nothing built):** (1) spawned entities are NOT saved by the game (EMF
     re_villages.md; core/loot_chest.lua): a hidden chest as storage loses everything on a server restart -> the
     companion's items must live in FlameKit's own file (the roster). (2) emf.put/take/move = take + put: plain stacks
     exact; GEAR has a per-item data entity (pide: level, perks, durability, gem) that a take destroys: put back = same
     item, level and rarity (passable), [WRONG, see the owner 07:59 correction below:] perks re-rolled, the socketed gem
     gone (EMF guide.md/cookbook.md). The engine's
     moveStack (op 4, 0x14040da50) keeps the pide between two containers (re_take_items.md 4b) but EMF does not offer it
     and both containers must exist (no saved one to move into). (3) core/bag.lua reads every stack: item, count, gear,
     rarity, level, gem id (not the perks). (4) The chest: core/loot_chest.lua's Prop_Decoration_T5_Storage_40_Chest
     (40 slots), PUT_WAIT 0.5 s before the first put, a hit rule so it takes no damage. Questions asked: gear handling,
     the auto-close time, where the chest appears.
     **Owner 07:59, verbatim:** ""game destroys a gear piece's hidden data when it's taken out." I think you're wrong on
     this and you just forget we tested that. why do you say thats a problem?" -> right: tested 2026-11-15 (core/
     ground_loot.lua): a sword re-made with rarity 4 and level 10 came out legendary level 10, the same item (rarity =
     the number of the item's perks unlocked, so level + rarity give the same piece). EMF's "perks re-rolled" warning
     does not apply. The ONE thing that does not carry over: a gem socketed into a weapon (loot_drop keeps such pieces in
     the body). **Rule for Claude: check HANDOFF and the code comments for our own tests before quoting EMF docs.**
     Asked: a weapon with a socketed gem (store the gem as a separate item / refuse the piece), auto-close 10 min?,
     the chest beside the companion?
     **Owner 07:59:** "the EMF docs are frequently wrong, as we've learned" (our own tests beat the docs). **Owner 08:02,
     verbatim:** "1. how is the gem thing an issue? 2. maybe go with 5 minutes for now? 3. yes make it spawn next to the
     companion, maybe also make it so the companion can't move or do anything until the chest is closed? when the chest
     is open, make the "E" menu just say "close chest" so we can get rid of the whole inventory menu and just have one
     "Inventory" option on the main wheel. clicking that spawns the chest with items" (gem: EMF's put cannot socket a gem,
     so it is kept as a separate item next to the weapon). **Built 0.15.287 (Lua, live by reload; tested in a fake world:
     local_server/tests/fight/invtest.lua with the real core/bag.lua):** wheel {Follow me, Stay here, Attack, Inventory,
     Put away}; while his chest is open {Close Chest} only (an old wheel's other picks are ignored). `inv` table (the
     file is at Lua's 200 top-level locals): inv.open[name] = {chest, player, t0, state filling/open, queue, rest, rule};
     r.inv = [{item, count, level, rarity}] and r.chest = {id, session, state} in the roster (world data). Open: chest
     inv.CHEST (Prop_Decoration_T5_Storage_40_Chest) 1.5 m to his right, a hit rule (no damage), puts one by one
     (PUT_WAIT 0.5 s, RETRIES 3 on a fresh chest, what does not fit kept in c.rest/the record); r.inv untouched until
     every put answered; then every SAVE_EVERY 1 s r.inv = chest (bag.entity_stacks; a socketed gem as its own entry) +
     rest, saved when changed; only a chest that exists and has InventorySetup is read. Close / OPEN_MAX 5 min: final
     save, hit rule off, emf.destroy; a vanished chest closes keeping the last save. Script reload: inv.adopt takes an
     "open" chest of the same session up again, removes a "filling" one; another session: gone, r.inv = last save. Frozen:
     drive_step holds him (hold_at), no fight/heal/follow (inv.frozen; name_of is declared below drive_step: a first
     version read it there and the drive_harness caught the error). Notices "<name>: Inventory open." / "Inventory closed.".
     **Owner 08:11:** "what about despawning him when the chest is open? thats disabled too right?" (blocked: wheel Put
     away, every automatic put-away; not: P call, death, console commands; the chest and items untouched in all).
     **Owner 08:13, verbatim:** "can the that call my companion feature be disabled when the chest is open? if he gets
     killed does the chest despawn automatically too?" -> 0.15.288: on_call refuses while inv.open[r.name] ("<name>:
     Close the chest first."). Death: the chest stays (asked whether it should close itself when he dies).
     **Owner 08:15, verbatim:** "yes if the companion dies with the chest open, the chest needs to despawn" -> 0.15.289:
     F.tick's death check (dead_told) calls inv.close(world, r, "he died") (saves first). invtest.lua: closed, record kept.
     **Owner 08:17:** "so what stats specifically were you worried about not transferring back on items?" Listed: level and
     rarity tested (yes); socketed gem (no: kept separately); UNKNOWN: unlocked perks (PerkContainerNew {availablePerks,
     unlockedPerks}; rarity = availablePerks - 1, unlockedPerks may reset on a fresh copy), durability/broken, fuel,
     custom colour/name. **Owner 08:19, verbatim:** "we'll have to test the unlocked parts, I don't think we tested that
     yet" -> **TO TEST** (owner): a perked weapon through his chest (close, reopen, compare). 0.15.290 logging (live):
     inv.log_gear at "filled" and "closing": "inventory <name> gear (<when>): item, level, rarity, perks a/u unlocked,
     gem, base damage, item state" per gear piece.
     08:20:52 in game: a reload took his OPEN chest up again (inv.adopt) and it kept saving: reload safety confirmed live.
     **Owner 08:20, verbatim:** "I noticed the companion can still be pushed around while the chest is open, anyway to
     stop that?" -> 0.15.291: inv.pin (drive_step's frozen branch): the CurrentTransform position when frozen (c.pin, per
     body) is written back every tick he is moved, his Velocity zeroed; log "pushed while the chest is open: put back"
     once. Harness: a 2 m push undone the next tick.
     **Owner 08:22, verbatim:** "also I wanted the "E" button to just say "Close" chest. it doesn't have to bring up the
     whole wheel when the chest is open..." -> 0.15.292: on_talk while inv.open: inv.close at once (no wheel); his offer
     (inv.prompt, used by bring_to_life too) while open: verb inv.CLOSE_VERB 0x3959A87F, back to "Talk" on close. EMF's
     verb list (emf_api.h EMF_VERB_*) has no Close; own words need an EML content mod (a data patch on every game). The id
     = FNV-1a of Base_Door's InteractionToggle.onToOffVerb GUID da5990c2-f8f0-413c-bb4d-fe057f4b4ca1 (tplcomp.py, comp
     ad7e2be5); UNPROVEN: FNV-1a of its offToOnVerb (0af70198-...) = 0x4E82E309, not EMF_VERB_OPEN 0x0C2E4515, so the
     door's words may be other entries or the hash another; TEST: the prompt shows "E Close" or just "E". Language data:
     not in enshrouded.kfc's 60 biggest resources (the .dat files hold the rest).
     **In game 08:23-08:24 (the owner's round trip):** a weapon level 46, rarity 3, perks 4/0 unlocked, base damage 51
     went out and came back the same (08:23:14 closing, 08:24:22 closing). It had 0 unlocked, so the unlocked-perks
     question is still OPEN (needs a piece with unlocked > 0). BUG found there: at 08:24:10.555 (the filling's own tick)
     the fresh copy read level 0 / rarity 0 / damage 0, item state 64, and the snapshot SAVED that (correct again 0.5 s
     later): a crash in that window would have made it common. 0.15.293: after the filling c.ready_t = t + SAVE_EVERY;
     the first snapshot and the "filled" gear log wait for it; a close before it keeps the record from before the
     opening. The "Close" prompt (0.15.292) not seen yet: the chest was closed before that install.
     **0.15.294 (owner 08:32 "the companion doesn't have an E button at all now"):** inv.prompt took the old offer off
     and made the new one in the same step; EMF refuses that ("an earlier offer is still being taken off it: try again
     in a moment"), so he had no prompt at all. Now the new offer is made 2 ticks later and retried every 6 ticks (up
     to 50) until EMF takes it (inv.want / inv.want_tick from F.tick; log "prompt: E on <id> offered ... after N
     try(s)"). Seen 08:35:18 after the reload: offered at the 1st try (Close verb on 182193, Talk on 13020).
     **Idea (owner 08:33): "the chest that spawns, can it be "named" with the companions name?"** Not built. What we
     know: the game has its own floating name labels (component CustomPlayerString, 8 bytes, saved with the world;
     client programs ui_custom_name / ui_custom_name_visibility draw it with a line-of-sight check, from the
     CustomPlayerStringsSystem); never touched by us, how a string gets into that system is unknown (research). The
     chest's own E prompt words would need a content mod (a game update, not server only).
2. Companions in the party list.
3. ~~Teleport fallback~~ DONE (glider put-away/return, fast travel return, 2 s can't-follow respawn; owner 13:54,
   14:05). ~~Fast travel UI hide~~ DONE (0.15.281-0.15.284; owner 15:25 "we can cross that one off the list").
4. ~~Ground under a glide path~~ DROPPED (owner 15:26: "whats the glide path? I dont think we need that one"). It was
   a way for the hound to walk after a glide (find ground he could cross under the flight, or follow the trail in the
   air); the glider put-away and respawn beside the player (13:48, owner 13:54 "it works pretty well") does that job.
8. **Use more of the crumb meta data (owner 2026-11-18 19:07: "keep it of course. always assume more information is
   better"):** each crumb stores the player's speed, movement state, up/down speed, facing, water depth; not used in
   decisions yet. Ideas: his pace from the player's speed at that crumb (walk where the player walked, sprint where he
   sprinted; now the C++ picks it by distance), react to movement states (climbing, crouching) once their numbers are
   known. Standing rule from the same message: ideas and information are always kept/added to the list, never
   dropped by default.
7. **Companion inventory (owner 2026-11-18 13:06):** "also add to your list: companions can carry extra items for you
   (they have their own inventory like a storage check basically)". (a storage chest the companion carries; later)
   Owner 13:29: "a quick initial assessment of that idea... is it doable with what you know so far?" Assessment
   (from EMF 0.6.6 lua.md, nothing built): EMF has emf.put / emf.take / emf.move (moves between two inventories "without
   losing any", opts slot/exact/level/rarity) and emf.spawn (any template); emf.add_component only allows
   ScaleComponent and InteractionPause, so the hound cannot be given an Inventory. Likely way: a real storage chest
   template spawned out of sight as the companion's bag (kept in the world save, owned by the roster record), and
   FlameKit's own window (like the Auto Junk List tiles) showing its items, clicks moving items with emf.move. The
   game's own chest screen cannot be opened on the dog. Unknown: whether gear keeps perks/durability through
   emf.move, and where a hidden chest may safely stand.
   Owner 13:33: "I'd want all interaction to be in game, I'm trying to get rid of panels windows and buttons users need
   to mess with. I'm sure we could 'spawn' a chest to the ground and populate it with the companions 'simulated bang'
   ? when the user is done interacting with the chest, the game updates the new inventory list for the companion and
   the chest disappears? just spit balling here". (Design direction: NO FlameKit window; the game's own chest screen.)
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
