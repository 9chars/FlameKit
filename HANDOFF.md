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
   Messages, the companion test hooks: P key, wheel, panel button). **0.15.368 on Stable and G-Portal (2026-11-20 19:20-19:23)**,
   with the companion system. (Before 0.15.368 the local server's main.lua listed `features.npc_probe` instead of `features.npc_wheel_probe`.) Its companions feed
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

### Companions: where things stand (2026-11-20 18:25; the full log: HANDOFF_companions_history.md, verbatim)
**Read HANDOFF_companions_history.md before changing a companion behaviour**: every owner decision is there with his
words. Standing decisions from 2026-11-20 (owner words):
- 18:11 "I'm afraid some of the clean up will make it harder to debug and fix future errors in the companion/pet system
  we still have other templates to fix and I don't want to limit myself on that": debug tools are never removed, only
  switched off (companion debug log: console `flamekit.npc debug on|off`, off by default).
- 16:20: the "can't follow / can't get up there / afraid" notices only with the Experimental tab's Debug option
  "Companion follow notices" (off by default).
- 16:18 "that doesn't require a fix": far-away companions after a zone-in come back through can't follow (no 80 m rule).
- 17:42/17:46: the Companion Roster is for admins only (greyed out for others, the server refuses); admin list =
  store "npc_admins", default the owner's account (must change before other servers get it).
- 15:10 Pet stays "pick Pet, then press E" (an auto E press was offered, not wanted).
- 16:00 spacing for pets AND monster companions; 15:36 the dive pull change is pets only; 16:33 pets faster when behind
  (boost done; the catch-up jump not needed: 17:22 "they're keeping up fine").
**Code (local test server only):**
- Server Lua: `local_server/features/companions.lua` loads `features/companions/01_base .. 11_roster_window.lua` in ONE
  shared environment (former top-level locals are names in it: no 200-locals limit). Tests:
  `python3 local_server/tests/bundle.py` -> /tmp/companions_bundle.lua for `local_server/tests/drive_harness.lua`
  (old new seed ticks; set F.debug = true in both to compare logs) and `local_server/tests/fight/*.lua`
  (invtest needs `../../../flamekit/core/bag.lua` as 2nd arg). Check every Lua file with
  `texluac -l -p <file> | grep -o '_ENV "[a-zA-Z_0-9]*"'`: only real globals may show (16:28 lesson).
- Game side: `flamekit/features/npc_wheel_probe.lua` (wheel, Companion Roster window, prefs/admin on channel npcwheel),
  `flamekit/core/companion_notices.lua`, `flamekit/core/pets.lua` (no babies since 0.15.345).
- Server C++: `flamekit_server_probe` (fk_server_probe.dll, side server): the drive after steering_locomotion (pets via
  pet_drive.txt: "<id> <target> <player> <code> <mode>"), pets' offers (hooks on interaction_offer pre/post,
  after interaction_taming, before interaction_attempt: touch/Talk, mode 1 Pet, mode 2 Close, offerId 1), the pet boost
  (after locomotion_execution: ONCE per pet per step, x1.6 past 8 m, max 10 m/s: a hook_program post runs ~20 times a
  step, 17:05 lesson), chest names (setString; a name the world load dropped is registered again), the ground ray
  (chest_ground.request), DLOG behind companion_debug.txt. Next step agreed (owner 17:39): fold it into
  flamekit_native (one DLL, side both).
**Open (owner's order decides):** one DLL; then test with a second player (owning, sharing, giving; Give/Share list =
players seen joining); a more forgiving fight line check for monsters below (offered 17:32, not answered); per-kind
tuning (humanoids, their own attacks); shared inventory per player (on hold); admin system for other servers; the
older items in HANDOFF_companions_history.md ("Open list": glider, crumb meta data, inventory, blocked-by notices,
hot reload, companions in the party list, ...). Versions: Stable 0.15.277, Development 0.15.360, server 0.15.362.
Owner 18:26 "once its folded into the DLL we can still make changes and update it correct?" (yes: Lua reloads; the
DLL goes to the server by copy and to players by the updater; a server-only C++ fix: server copy only, Rule 0d) /
**18:27 "k well everyone will be updating"** (the version gap between server and players' DLL is no concern).
**Owner 18:28 "one last little feature request, anyway to float the companion/pets name above them? or add it into the
"E" label some place?" / 18:29 "lets do #1 like how the chests show it"**: 0.15.363 spawn_body spawns the body with
{CustomPlayerString = {stringId = inv.name_key(name)}} (inv.write_names first; refused -> plain spawn), logs "roster:
<n>: name label key on his body ...". Untested whether creatures show it. (#2, the name in the E word, needs a content
mod's text table.) New check: python3 local_server/tests/globals_check.py (names read but never set in the bundle).
**Owner 18:32 "yup it works perfect"** (the name label shows over companions and pets).
**Owner 18:33 "yes" (fold the probe into the main DLL).** 0.15.364: flamekit_native/src/companions_server.cpp = the
probe's code (anonymous namespace; kMod "flamekit companions"; commands fkcomp.*; program fk_companion_ground);
flamekit_native's emf_mod_load: dedicated_server_process() (exe enshrouded_server.exe) -> emf::init +
fk_companions_load() only (no updater: it would replace the server's files with a player's version; no window, no
settings, no install_pending); in a player's game fk_companions_load() after the rest (acts only on a hosted world).
mod.json side "both". flamekit_server_probe removed from the repo (git history keeps it); on the server
mods\fk_server_probe moved to emf\_to_delete\fk_server_probe_1836 and mods\flamekit_native added.
Restart 18:36 (owner "yes"): "[flamekit_native] on a dedicated server: only the companion part runs (loaded)", all
hooks installed; 18:37:55 N2 dropped and "registered again" (0.15.358 works). Owner 18:48 "I renamed my dog ... it
didn't update on my dogs label when I respawned him" / "I guess I had to press enter...?": the name box only sends
on Enter (closed by a click elsewhere 3x = dropped); a fix offered (save on a click elsewhere + relabel the body that
is out): not answered. **Owner 18:49 "now the label isn't showing at all after I renamed it" / "its coming out
empty"**: 18:49:02 "Butt Sniffer: the spawn with his name label was refused (stringId: out of range (0 to 2^64 - 1))":
its FNV key 0xEF44E9F7E41EABBF >= 2^63 is negative as a Lua integer (EMF writes uint64 >= 2^63 only as floats).
0.15.365: inv.label_text(name) = name + trailing spaces until the key is below 2^63 ("Butt Sniffer" + 2 spaces);
inv.label_key; custom_names.txt holds the label texts; body and chest spawns use label_key.
18:52:21 the label showed (key 0x7CAE4A3812554317). **Owner 18:53 "ummm make the C++ dll do it.. that sounds cleaner
and better than spaces and what not" / 18:54 "the spaces is a hacky fix"**. 0.15.366: label_text/label_key removed;
bodies and chests spawn with CustomPlayerString.stringId 0; inv.write_labels (F.tick every 30 ticks, when changed)
writes labels.txt "<entity>\t<name>" for ent_of bodies and open chests; companions_server.cpp labels_tick (every 30
steps): registers a missing name (into g_names_done, so the drop watch covers it) and writes stringId = fnv1a64(name)
when it differs (log "labels: <id> gets the label ..."); a rename relabels the body that is out.
Restart 18:56 (owner "yes"; DLL 9a69d355, old fdff3726 .old_1857): 18:59:12 "labels: 28657 gets the label 'Butt
Sniffer' (0xEF44E9F7E41EABBF ...)"; 18:59:14 renamed to Poop Eater -> the same body relabelled. **Owner 18:59 "tested the
rename fix"**. Seen 18:59:12: the name dropped from the table when a labelled body went away (the game takes back one
claim per labelled entity; the watch re-registered it). 0.15.367 (built, installed with the next restart): labels_tick
calls setString (one claim) for every label it writes.
DLL 21452746 put in (old 9a69d355 .old_1900; loads at the next restart). **Owner 18:59 "appears to work".**
**Owner 19:01: "yes push it to both development AND stable and update g-portal"**. Development 0.15.367 pushed (sig
good). Stable and G-Portal: held for one question first (the release has no companion server code: features/companions
is local_server only, so G-Portal and hosting players would get the buttons without companions).
**Owner 19:05: "the companion system and pets needs to get fully committed to both dev and stable"** (= put the
companion server code into the release first). 0.15.368: local_server/features/companions.lua + companions/ +
npc_fields.lua moved to flamekit/features/ (main.lua lists features.companions after npc_wheel_probe; the local
server's own main.lua is gone: the server runs the release's flamekit folder as it is). core/companion_net.lua
registers npcwheel and roster once (a second emf.net.channel of the same name replaces the first one's handlers; in a
hosted game both ends share one Lua state); each end sets its handler (net.handle(name, "server"|"player", fn)).
The server end's who(): the host's own messages come with the all-zero account -> world:account(from.player).
is_admin(account, from): npc_admins (default OWNER_ACCOUNT) or EMF's admin (from.admin) or the host (from.is_local,
F.hosts from on_player_joined p.host). The loader opens its parts with "/" (Windows takes it; the tests run on Linux).
**FlameKit Native's mod.json "side": "both" (0.15.364) removed**: EMF compares side-both mods by exact version on
join (a note for every player with another version; a server with mods_check=refuse kicks them); EMF_API.md says
FlameKit leaves side unset on purpose. Unset = EMF loads it everywhere (reference.md). Tests: drive_harness 14 seeds
identical, fight/heal/inv tests identical to 0.15.367, globals_check none, run.lua host + joined ALL PASSED (run.lua:
travel/npcwheel/roster channels allowed, the companion parts copied into its data folder, a double registration
fails). Local server 19:14:39: 16 features loaded, both ends' channels true, roster found again, no errors.
Development 0.15.368 signed (sig good). G-Portal needs mods\flamekit_native too (the companion C++: drive, E offers,
labels) and the FTP tool only writes into the FlameKit folder.
**Owner 19:20 "yes"** (Stable 0.15.368 + G-Portal + the FTP tool also uploading FlameKit Native). Stable: dist =
dist-test 0.15.368 (sig good), pushed. FTP tool upload.ps1 (repo tools/ftp_tool + the PC's release\FlameKit FTP tool,
old copy claude_scratch\upload_ps1_old_368.ps1): the outbox's `_flamekit_native\` goes to mod_dir's sibling
flamekit_native/ (uploaded first; root mod.json still last). G-Portal 19:23: 29 files (27 Lua changed since 0.15.277
+ flamekit_native.dll 21452746 + its mod.json); 19:22:58 reload: 16 features, companions' channels true, roster 0
NPCs. **G-Portal needs a restart**: "restart the game to receive InteractionAcceptedEvent" (the pets' E) and the DLL
loads only at a start. After it: fetch the logs (upload with an empty outbox) and look for "[flamekit_native] on a
dedicated server: only the companion part runs (loaded)".
G-Portal restarted by the owner 19:25: 19:25:13 "[flamekit_native] on a dedicated server: only the companion part runs
(loaded)", all hooks installed, 16 features, no errors; world loaded 19:25:40; the owner joined 19:26:59.
**Owner 19:37 "go ahead and to that fix quick on both local / dev and stable -- g-portal"**: 0.15.369 drive_put_away:
the player's TeleportCount going up puts the companion away ("fast travel"), replacing the FAR_JUMP 50 m rule (Rule
0n; G-Portal 19:32:45 a ~25 m travel was missed: back 15-19 s later via can't follow). drive_harness: the fake world
raises TeleportCount on every >50 m move (identical to 0.15.368 in 22 seeds, ignoring tp_count/last_px); with a 25 m
travel step the new rule puts away, the old did not. Local 19:47:06, Development + Stable (sig good), G-Portal 19:47:34
(4 files), all 16 features. **Owner 19:47 "why am I being prompted for an update? you said it was server side only?"**:
a Development/Stable publish always makes an update in every game (the release carries the companion Lua for hosted
games); this one changes only Lua files (the DLL is the same). Say so up front next time a server-only fix is also
asked for on dev/stable.
**Test monsters, owner 20:07-20:12 (collecting changes before building):** "spawn multiple groups of monsters so they
can both fight each other ... setting factions?" Proposed: a Team row (Free-for-all = HitAll as now, Team 1-4 =
factions Vukah 3, Scavenger 4, Ancients 15, Drak 14: no friendly pairs among them; teams still fight players), each
Spawn adds a group instead of replacing. Not yet answered: "a couple more changes first". 20:12 "can we space out the
monsters a bit more?" (now SPOT_MIN 2 m hex grid; 3 m / 4 m offered, not picked yet). 20:12 "were going to remove the
button option for 1000, so that can go away" (DUEL_COUNTS without 1000).
20:13 "don't limit it": the server's cap MAX_DUELISTS stays 1000 (only the button goes).
20:14 "bump it out to 3 m for 500" / 20:15 "put them all to 3 m I think": SPOT_MIN 3 for every quantity.
**Owner 20:16 "yes #3 is good"**: 0.15.370 built: F.TEAMS {3,4,15,14}, Team row (dbg:team:0-4, msg.team, b.faction kept
every body check), Spawn Monsters adds (no drop_bodies_of; the queue is cleared only by Remove), Spawn Dummy replaces
only the dummy, SPOT_MIN 3, DUEL_COUNTS without 1000 (MAX_DUELISTS 1000). run.lua: Team test (factions, both stay,
faction restored, Remove both). Local server 20:19:57, Development 0.15.370 signed. Not on Stable/G-Portal.
**Owner 20:19: reward loot "legendary gems were only spawning two types" - check for missed legendary gear.** Found
(item dumps of 2026-11-15 joined with item_details.dat, build 1287369): the game has only 5 legendary gems (T4
FocusedLight, T5 ColdComposure, T6 Lycanthropy, T7 Armoring + HyperSpecialization) and 5 legendary rings (T1 ministory_05,
T3 Light, T4 The_Ancients, T5 Frost, T6 Shock; none at T7); db.pick takes the monster's tier, so level 100 gives only
the two T7 gems and always Ring of Shock. Not in item_db at all: every shield (45, 2 of them legendary lore shields),
Armor_T5-TX_*_Loot (15), Weapon_T7-TX_2H_GreatSwordEpic_Vorgoth (legendary). Enemy weapons, _Craft, T0, NPC/WIP
cosmetics are left out on purpose. Some dump queries were capped at 50 names: a fresh finer dump would confirm.
**Owner 20:24 "add the shields"**: 0.15.371 (server only, local server 20:26:07): 38 shields in db.GEAR.armor by tier
(T1-T7 DPS/Rogue/Tank and _Loot, the two Lore shields; shields are category 1 = armour). Owner 20:24 on gems: "we've
only seen two gem types ... look at it closer or explain how we can get those to drop". Explained: TIER_MAX_LEVEL puts
level 50/75/100 in T7 (Armoring, HyperSpecialization), 1 and 25 give T4 FocusedLight; T5 ColdComposure (levels 30-36)
and T6 Lycanthropy (37-42) are not reachable with the level buttons. Unfinished outfits = Vanity_TX_PartyHat_02/04_Tint_WIP.
**Owner 20:28 "yes, make those changes, and also make sure the way its randomizing, picking, and dropping the loots is
also doing it right"**: 0.15.372 (server only): db.pick for rings/gems = every legendary one of tier <= the monster's
(uniform), else the nearest above. Checked: Lua 5.4.9 (math.random seeds itself); the logged single kills
(production 2026-11-16..20: armor 13, cosmetic 16, gem 17, ring 13, weapon 20) are even across the five kinds; no
"came out rarity ... not legendary" line in any log; the gem picks matched the tier rule exactly (no bug, the rule
itself). Note: legendary rings have fixed levels (5, 15, 20, 30, 40), so a lower-tier ring from a level 100 kill is
low level; gems are level 1-105.
**Owner 20:30 "we want the NPC outfits in there as well. all cosmetics from the game data"**: new debug command
flamekit.itemnames (experimental.lua, 0.15.372; cosmetics 0.15.373): item_ids.txt (a copy of item_details.dat) -> item_names.txt via emf.item_info
(4213 items, 0 unnamed); kept as tools/gamedata/item_names_1287369.txt (id, name, rarity, levels, category). db.COSMETICS
= all 199 Vanity items (was 105: the old item lists were capped at 50 names a query, so my 20:19 "9 left out" was wrong:
94 were missing). Still not in item_db, found with the full list: TX dungeon weapons (FogNest, HollowHall: 19, many
legendary), Vorgoth's greatsword, MultiClass armour (FogPowered T2, SkeletonArmor T4/T6: 15), Armor_T5-TX loot set (15),
Wards T1-T7 (+_Loot, 14), Craft_ copies of the Lore weapons/shields (left out: crafted).
**Owner 20:36 "yes, add them"**: 0.15.374 (server only): weapon T7 + the 19 Weapon_TX_ (FogNest, HollowHall; levels 1-55)
and Weapon_T7-TX_2H_GreatSwordEpic_Vorgoth; armour: MultiClass T2/T4/T6, Armor_T5-TX_*_Loot in T5, Ward_T1..T7 (+_Loot)
in their tiers (64 names, all checked against the full list, no duplicates).
**Owner 20:40 "lets get everything update. push it to dev and stable and g-portal"**: 0.15.374 on Development and
Stable (sig good, commit 79874ba) and G-Portal 20:41 (5 files changed since 0.15.369: changes.txt, core/item_db.lua,
features/experimental.lua, mod.json, flamekit_native/mod.json; reload 20:41:16, 16 features, no "restart the game").
WATCH (seen, not fixed): G-Portal pet Biggs (75332) "found again" then "drive 75332: gone, stopped" at every reload
(also 20:00:39); player 3 (0x05891a85470cffe2, not an admin) gets "roster window: get refused" every 5 s.
2026-11-21 07:42 Biggs explained (no bug): MisShady's pet (owner 0x3c7d90b3165e75f8); she fast travelled home (Biggs back
beside her 19:59:53 at her base 6298 949 5188) and left 20:00:40.001; her position went 0.17 s earlier, so the drive
stopped ("gone"). The body stayed there; the 20:41 reloads found it again and stopped again (owner away); the 04:11
restart: "Biggs waits for its owner", spawned beside her when she joins (roster_joined / waiting).
**Owner 07:52 "why is "the game" asking for that?" / 07:54 "lets do the fix but, if the game client isn't admin, why does
it even try?"**: native_ui's write_ros builds the roster window's rows every 10 steps for every player (open or not);
F.roster_rows asked {op="get"} every 5 s while it had no list, and a non-admin never gets one. 0.15.375: roster_rows
returns only the refusal text unless the server said admin ({op="admin"}); the first ask comes once it says yes. Server:
the refusal is logged once per account (F.denied_said). Test local_server/tests/rostui.lua (from /tmp, now in git):
not an admin asks 0, an admin asks 1. Local server + Development; not Stable/G-Portal.
**Loot Drop rework, owner 2026-11-21 08:21-08:37 (designing, not built):** "trying to pick up loot from the ground is a bit
cumbersome"; 08:27 "could the loot go directly into one of the players companions"; 08:29 "ideally the loot would go into
the bag of whoever killed it"; 08:37 "i agree with the cap 72 stack limit.. thats per companion". Plan: killer (emf.on_hit
killed=true, attacker; a companion's kill counts for its owner) -> killer's bag -> killer's main companion's r.inv (cap
72 stacks per companion; stackables merge first) -> ground; no killer known -> ground. Through a core module (Rule 0b).
Roster save is one JSON text (1 MiB): the cap keeps it far below.
**Owner 2026-11-21 09:35, the full spec (verbatim, replaces the 08:21-08:37 plan):**
"The loot should go to the player (or their companion) who landed the final blow and killed the monster. The loot should
go either into their main player bag, the bag of one of their companions, directly to the ground, or the original game
behavior. There should be players setting to determine this looting behavior. Here are the player specific options to
add: 1. Auto loot to main bag, or 2. Auto loot to companion bag, or 3. Let loot drop to ground, or 4. Follow original
loot drop behavior. These settings can go into a "Auto Loot" section on the "Settings" tab ABOVE the "Features" section
for now. We'll remove of the "Monsters drop their loot on the ground" setting on the "Server" tab and we'll remove the
"Server" settings tab. If the player opts to have the loot go into one of their bags (main or companions) and the bag is
full, it should default to one or the other, for instance: player opts for loot to go to companion, companions bags are
full, try to put it in their main bag. If their main bag is full, try to put it into one of their companions bags. the
player MUST have the companion spawned and following them for that companions bag to be considered for loot storage. If
all the inventory bag destinations are full, it should simply be dropped to the ground. The loot MUST be evaluated by the
auto junk list first before going to the player (or companions) to ensure the loot is processed in the way the player
prefers (drop it, delete it, and other future possible behaviors built into that system).
As a separate process of major changes, I would like to augment some major changes to the "Messages" window: I would like
to replace the existing text box behavior with a tabbed control to this window. We'll add 3 tabs: Chat, Battle, Loot. All
existing current messages will go to the new "Chat" tab. The "Battle" tab will display attack damage from both the
monster to the player (or companion) and the damage from the player (or companion) to the monster. It should show this
data for all players in the near vicinity of the player (or companion) -- 50 m radius? We should also move heal messages
from the original messages text to the "Battle" tab. The "Companion heals you for..." messages should say which companion
is healing you by name. There should be an option in the settings to filter out other players battle data messages. This
setting should go under a new section in the "Settings" tab called "Messages". The "Loot" tab will output the loot dropped
by monsters and the player (or companion) who received the loot. It should show this data for all players in the near
vicinity of the player (or companion) -- 50 m radius? Messages from the auto loot system that were originally going to
the messages text can be moved to this "Loot" tab. There should be an option in the settings to filter out other players
loot data messages. This setting should go under a new section in the "Settings" tab called "Messages"."
Facts found: Messages window = C++ MessagesLayer (flamekit_native.cpp ~3378) reading ui_messages.dat from kit.note; tabs
need a DLL build. Only server setting = loot_to_ground (core/server_settings + features/server_tab go). Junk list:
loot_filter/server.lua per account {names, opts.action drop|delete}: needs a core hook for loot_drop (Rule 0b). Heal
line: companions 08_heal_attack say() -> features.chat.notice_to (a notice + Messages). Kill credit: emf.on_hit
(killed, attacker). Questions asked 09:35 (defaults, transport volume for Battle, heal pop-up).
**Owner 09:44 answers:** "#1 default it back to game's own behavior -- #2 correct -- #3 default it back to game's own
behavior -- #4 main companion first #5 the purpose of the battle chat is to analyze the attack and damage data. if the
messages are filtered or truncated, it would defeat the purpose of this feature. batch the messages out to the player in
a way you feel is most optimal. I would argue, maybe we need an option to turn those messages off completely all
together. #6 -- I have no idea, this was just a guess, is that too small or too big? some players may run ahead to do an
attack and I would still want to record that data.. I'm not sure what the sweet spot would be for this.. suggestions?
#7 notice messages should stay for heals for now. #8 not sure I understand the question. To my knowledge the message
window is always on the screen -- you mean if the user has the window hidden? #9 -- on by default."
So: default = game's own (4) for players and for kills without a player; others (no FlameKit) = 4; main companion first;
Battle: every hit, no truncation (net channel max 16384 bytes, compact batches); heal notice stays; filters on by default.
Asked 09:45: Battle on/off switch, the radius (#6), what a new line does to an unselected tab (#8).
**Owner 09:48:** "#5 battle messages can be turned off by default to mitigate server load, users who want to analyze this
data can turn it on -- #6 ok I agree with you. #8 I like the new message count, go ahead and add it, but don't mess with
changing the current tab focus when a new message comes in." So: "Battle messages" switch, OFF by default (the server
sends nothing then); radius = your own and your companions' at any distance, party members at any distance, everyone
else within 100 m (Battle and Loot); unselected tabs show a new-line count, the selected tab never changes by itself.
**0.15.376, Part 1 Auto Loot built:** core/loot_route.lua (deliver: junk hook first -> by choice bag/companion/ground
with the fallbacks; hooks set_junk (loot_filter/server.lua: state/resolve/removable, opts.auto), set_owner +
set_companion (companions 05_inventory inv.loot_owner / inv.loot_into: following the killer, main first, 72 stacks,
open chest skipped, roster saved every 300 steps while dirty), set_report (for the Loot tab)); core/player_prefs.lua
(channel flamekit/prefs to=server, the client sends {op=set,values} on change + every 30 s; the host's own values kept
directly, prefs.get(account, key, world) matches him; no value = default "game"); features/settings.lua (groups Auto
Loot and Messages are the tab's own, above Features; client_tick sends auto_loot); mod.json setting auto_loot (select
bag/companion/ground/game, default game); loot_drop.lua: emf.on_hit killed -> kills[target] = route.player_of(attacker),
read at the body's first look (killer_of), no killer or "game" = skip (the body keeps its loot), else every take goes
to deliver (back into the body when even the ground refuses). Server tab + core/server_settings.lua removed (Rule 0n).
Test monsters keep their own reward loot (experimental.lua). Tests: run.lua host + joined (Settings section, the game's
own leaves the body alone, ground choice as before), flamekit_native/notes/tests/loot_route_test.lua (order, junk),
local_server/tests/fight/autoloot_test.lua (companions), drive harness identical to 0.15.375.
**0.15.377, Part 2 Messages tabs built:** DLL MessagesLayer: tabs Chat/Battle/Loot in the title bar
(PinnedLayer::draw_title_extra / title_click, new), each tab its own file (ui_messages.dat, ui_battle.dat, ui_loot.dat),
unread counts on tabs not shown (lines that came this game run), the shown tab never changes by itself; known lines
matched by number (unordered_map). Lua: kit.note_tab(tab, text, colour) (battle 1000 lines, loot 300, files written 4x a
second); core/msg_feed.lua (channel flamekit/feed to=players 16384 B, 100/10 s; per player queues, a batch every 30
steps of up to 4 messages of at most 15 KB, the rest waits: nothing dropped; recipients: own lines always (hits by/on
him or his companions, his loot), others' with others_battle/others_loot (default on) within feed.RADIUS = 150 m
(PENDING the owner's A/B answer: A everyone at any distance, B 150 m; there are no party groups in Enshrouded, the Party
window lists everyone); Battle only for players with battle_msgs on (default off; nothing worked out while nobody has
it); games without the channel get nothing; the host's own lines go straight in); features/msg_tabs.lua (emf.on_hit
-> feed.hit, route report -> feed.loot, player left -> forget). Heals: "<companion> heals you for N!" notice stays
(chat.notice_to opts.quiet: no Chat line), its line in Battle (feed.heal). Monster names: faction kind + level
("Vukah (lvl 25)"); EMF has no template name per entity. Settings: Messages section (battle_msgs default false,
others_battle, others_loot default true). Tests: msg_feed_test.lua (recipients, filters, 3000 hits all arrive, <= 15 KB,
loot text), run.lua host + joined. DLL b09e1d4b (built 10:05). Open question: should Auto Junk's "Junk discarded..."
lines move to the Loot tab too ("Messages from the auto loot system ... can be moved to this Loot tab").
**Owner 10:24:** "#1 I think the 100 m radius is fine for now. I can bump it up or down depending on what I find. -- #2 It
should go to the loot tab." 0.15.378: feed.RADIUS = 100 (core/msg_feed.lua, one constant); loot_filter/client.lua's
"done" summary (Junk discarded/dropped) -> kit.note_tab("loot") (the info lines stay in Chat). run.lua reads ui_loot.dat.
**Owner 11:53 "where are my pets? they didn't respawn and they're not following me?" / 11:54 "it took way too long for
them to teleport to me, fix it" / 11:55 "yes"**: joined 11:51:51, both "follow again" 57 m away and 34 m lower, no trail
(he had not moved) until 11:53:50. 0.15.379 (server only, local server): roster_joined marks the drive joined=true;
drive_put_away at its first step with both positions: farther than JOIN_FAR = 20 m (3D) -> go_away "joined" (back
beside him once on the ground, like a fast travel). Test local_server/tests/fight/joinfar_test.lua; drive harness same.
**Owner 11:58-12:00 "I just took a bunch of loot and none of it showed up in my loot tab?" / "I took the loot from the loot
container after I turned the option on" / "#2... come on, if I pick up loot, it needs to be logged into the loot window
according to my settings."** (Facts: 3 kills 11:57:02-23 judged with "game" before he set bag at 11:57:29; no kill after.)
0.15.380 (server only): feed.pickup on the game's PickupEvent (pickedUpByEntityId a player, pickedUpFromEntityId not 0:
crafting is 0), a Loot line "<name>: <item> xN > picked up" by the same recipients; core/game_events.lua registers each
engine event once and fans out (loot_filter's PickupEvent moved there). The first 20 PickupEvents of a run are logged
whole ("feed: pickup ...") to see what a container take sends (WATCH: if from = 0 there, the filter drops them).
**Owner 12:03 "what does "Fogger (lvl 45) > Midevil: 85" even mean?" / 12:05 "you can just say Fogger(45) not "Fogger(lvl
45)""**: 0.15.381 (server only): "<a> hit <b> for N damage (flags)", monsters "Kind(level)".
**Owner 12:07 "what does "Midevil > Monster 1" mean" / 12:08 "only log damage to and from actual monsters or other players
(PvP)"**: 0.15.382 (server only): feed.hit needs both sides creatures (a player, a companion, or a Faction other than 0);
no attacker (0) is left out; an unnamed faction is "Creature".
**Owner 12:15 "all the monster names in the battle tab say "Fogger(45)" ??? ... it need to say the actual monster's name"
/ 12:18 "do 1 now and see how it looks then 2 if 1 is awful"** (1 = fingerprint templates and map them to FlameKit's
core/monsters.lua names; 2 = research the game's own names in C++: ENGINE_MAP says `ecs::TemplateResource` +0 is the
template's name string, not exposed to Lua). 0.15.383 (server only): debug command `flamekit.monprints` (features/msg_tabs.lua;
from the console it uses the first player online) spawns every kind 300 m below, reads after 2 s, removes, writes
`monster_prints.txt` beside FlameKit; `flamekit.monprints discover` (one kind per group) lists every component name of
`monprint_comps.txt` (made from the SDK's components.hpp) that has a template half (`monster_prints_raw.txt`). Learned:
world:template returns read-only component data (userdata, fields by name), not a table. 0.15.384 (server only):
core/monster_print.lua reads EnemyArsenalReference.arsenal (108 distinct over 189 kinds: the kind) and
AnimationGraphResourceComponent2.animationGraph (77: the species); core/monster_names.lua is generated by
`python3 tools/gamedata/make_monster_names.py tools/gamedata/monster_prints.txt flamekit/core/monster_names.lua`
(group prefix: Scavenger/Shroud/Vukah/Undead/Ancient, none for Beasts/Drak; variant numbers dropped, tiers kept; kinds
sharing an arsenal get their shared words, e.g. Melee01..09 -> "Scavenger Melee"). msg_feed name_of: that name, else the
faction's, then "(level)". **Owner 12:39 "its good enough for now. not worth the work of #2"**: option 1 stays; option 2
(the game's own names through the DLL) is on the ideas list, not planned.
**Owner 12:44 "loot that drops from chopping things down should also be automatically handled based on loot settings
as well"**: 0.15.385 (server only) logging first (features/loot_drop.lua chop_hit/chop_tick, CHOP_LOG): a player's hit
on an object (no Faction) is logged ("loot drop: chop: hit by ..."), and 1 s and 3 s after one breaks every new
PickupItem within 20 m ("loot drop: chop: pickup ..."). Waiting: the owner's yes on the restated scope, and a chop.
**Owner 12:46 "loot you take from chests should also show up in the loot log...."**: cause found: the game's PickupEvent
has only hideInUi, itemCount, itemId, pickedUpByEntityId, pickedUpFromEntityId, position, targetSlotId, timeStamp;
feed.pickup read e.itemLevel, and EMF's strict event table made that an error, so the first pickup with a "from"
(12:40:06, 12:47:29) stopped msg_tabs (Battle and Loot tabs dead until a reload). FlameKit's own puts into a bag (Auto
Loot) come with from 0 (12:33:46-55), so the from = 0 filter stays (no double lines). 0.15.386 (server only): no
level/quality on pickup lines; the logging keeps 20 lines with a from and 20 without; msg_feed_test uses a strict
event. 12:48:04 a pickup with from 3380087472 went through without error.
**Owner 12:50 "lots of different items fall depending on what tree I chop down.. you'll never catch every item by just
watching me take a few trees down..?"**: answered: the plan does not list items; it takes whatever loose pickup appears
where the object broke, so one tree that falls shows the mechanism. Learned 12:49: hits on trees come (targets ~3.38e9,
Health, no Destructible); the breaking hit (killed true) has no position any more; while chopping, pickups of one item
(1853942795 x1) came with from 0 every ~5 s (ground pickups by hand? FlameKit's bag puts are from 0 too). 0.15.387
(server only): the scan uses the object's last hit place (else the player's), 30 m.
**Owner 12:53 "items you pick axe go straight to the bag for some reason when other things don't, I'd still like those
logged in the loot messages also"**: learned 12:54: picking up a loose item from the ground by hand is a PickupEvent
from 0 too (3509012331 picked 12:54:34-38), a chest take has a from. 0.15.388 (server only): every PickupEvent of a
player is a Loot line ("> picked up" with a from, "> into bag" from 0) except hideInUi and FlameKit's own puts:
core/own_puts.lua (note before emf.put in loot_route bag_then, claim in feed.pickup, 10 s). Test monster runes put
into the bag (experimental) are not claimed: they show as "into bag" (wanted: loot the player got).
Chop scan 12:54:23 (tree 95968): 26 pickups within 30 m, nearly all old world pickups (ids ~3.38e9 lying around,
and others 18-44 m up); only 99403 (3.1 m, item 3509012331) looked new. A real chop loot needs "new since the break"
(SpawnTime or a snapshot before), not distance alone.
**Owner 13:00 "what? ask better questions. I only want to auto loot stuff that I mine or chop down with a pickaxe. if
other items are on the ground already, just leave those alone. I'm not sure how much more clear I can be?" / 13:00 "a
pickaxe or axe rather.."** (decision: only drops of objects broken with an axe or pickaxe; never items already lying
there; my earlier yes/no restated what he had said: ask only what is really open). 0.15.389 (server only):
features/chop_loot.lua: a hit with attack "tool" (EMF hit field) on an object (no Faction, no PlayerState) by a player:
at the first hit every PickupItem within 30 m (and 30 m up/down) is noted (a walk, 3000 entities a step); after the
breaking hit (killed) pickups not noted, not FlameKit's own (ground.is_own, new in core/ground_loot.lua: ids made by
ground.drop, 5 minutes) and not taken before go through route.deliver (from "chopped") at 1, 3, 6, 10 s, by the
player's Auto Loot ("bag"/"companion"; "ground"/"game": untouched). An object broken by its first hit: its at-once
drops count as old (left). The chop logging moved there (LOG, "chop loot: ..."; debug, kept). Test:
flamekit_native/notes/tests/chop_loot_test.lua. The Settings label of auto_loot ("Where a monster's loot goes when you
kill it") is client text: changing it needs a client release (not done).
**Owner 13:05 "you mean fix the wording of the setting? you don't actually say what you're asking"** (lesson: say what
the question is about) / **13:07 "change it now, but theres also situations where you kill a monster and it dumps junk
to the ground... when you kill a Shroud Fog Nest drone it just dumps the archiac essence directly to the ground...
those types of loots also need to be auto looted....."**: 0.15.390 (Development release, client update: the label is
client text): auto_loot label "Where loot goes: monsters you kill, things you chop or mine", help rewritten;
features/chop_loot.lua renamed features/loose_loot.lua: also monsters (Faction, not a companion: route.player_of on the
target) killed by the player or his companion, loose pickups within 8 m of the death (objects 30 m), Loot line with the
monster's name. The snapshot is now every pickup in the world at the note (a walk that started after the first hit),
so a monster moving between first hit and death cannot make old items look new. Nothing is noted for a player whose
Auto Loot is ground/game. Old features/chop_loot.lua is still in the local server's mods folder (not loaded).
Dev 0.15.390 with DLL b09e1d4b (0.15.377 build); the owner's game: "Update v0.15.390 is ready" 13:11.
**Owner 13:15 "nothing is picking up the loot"**: his auto_loot was "game" (set 12:42). **13:19 "Critter carapace not auto
looting" / 13:24 "killed more... more drops" / "not auto looted"**: 0.15.391 (server only) logs what lies near each kill.
Found: every item left on the ground near the kills was FlameKit's own (ground.is_own) = his Auto Junk List "drop"
entries (Corrosive Blood, Torn Cloth, Golden Steel Arrow, Aerated Banshee Gel: Loot tab "> junk drop"); Critter Carapace
was "picked up" by hand once (from a container); the tree at 13:23 gave 2 drops (chop loot works, both junk-dropped).
Asked the owner whether junk-list "drop" items should still go to the ground under Auto Loot.
**Owner 13:29 "you're wrong once again. I know what items are on my junk list. Critter carapace is not on my junk list.
the item dropped, nothing picked it up"** (my junk-drop answer was wrong for the carapace: I answered before finding
where it came from; question withdrawn). Found: he took the carapace by hand from loot spot 106943 at 13:29:07; it was
body 100463's (killed 13:23:42): EntityDiedEvent came twice (.808, .976); the first run found the body gone at look 1
and no loot spot yet ("no loot spot found", the spot came later); the second had no killer any more (kills[] used up)
-> the game's own. 0.15.392 (server only, features/loot_drop.lua): a second death event of one body within 10 s is
left out (dead[]); no spot found -> looked for again 1 s apart, 4 times (SPOT_TRIES).
**Owner 13:42 "sure the AI is so sure its right, when it's not.. super annoying"** (lesson: say what the log shows and
what is my reading; no claim of a cause or a fix before it is seen working). **13:43 "auto loot collects the drops from
items I chop down with an axe, but it doesn't log it in the loot window"**: ui_loot.dat has "Pink Mushroom Meat from
chopped > bag" (13:41-42) and the DLL read it (newest 346); the 13:33 tree's 6 drops (Mycelium x5 = junk, Metal Scraps)
have no line found: asked which chop (open). **13:45 "dropped a ton of Critter Carapace and nothing picked it up"**:
0.15.393 debug command `flamekit.lootnear [player] [m]` (features/loot_drop.lua): the critters' piles near him were
Inventory InventorySetup DefaultInventory DestroyOnLoot Faction SpawnTime StaticCollider (no DoNotSave, empty until
opened); core/loot_spots.lua wanted DoNotSave. 0.15.394 (server only): DoNotSave or Faction (a world chest or urn, e.g.
80693, has no Faction). Not yet seen working.
**Owner 13:51 "looks like its picking them up now.. the logging of the items is a bit slow?"**: measured: a Loot line is
on screen <1 s after the take; death -> take is 1.5-5 s (body looks 0.5/1.5/3 s, then the spot, opened, +0.5 s).
Offered: look for the spot from the first look (owner 13:53 "not sure what you're saying honestly": asked again
plainly, open). **13:53 "the battle logging is wrong also Midevil heals Midevil for 18?"**: 149 such lines, ~1 a
second in fights (healing hit, attacker = target = the player); source unknown. 0.15.395 (server only): the first 10
self heals of a run logged whole ("feed: self heal ..."). Waiting for a fight.
**Owner 13:59 "your code probably checks the body 3 times on purpose? so why would you change that? if theres nothing
you can do to speed it up, so be it"**: decision: the 3 body looks stay as they are (no speed-up). (They are on
purpose: 0.15.143 a body was still empty 0.5 s after the death and filled later.) Owner 13:57 on the self heal: "it
could be a self heal I guess idk" (still waiting for the log).
**Owner 14:07 "did you fuck up something on stable because users are reporting none of their UI's are working on the
mod"**: nothing of mine had touched dist (0.15.374 since 11-20 20:40) or G-Portal (07:42 only a log fetch). Screenshot
(14:14): FlameKit v0.15.374 window, tabs there, "..." in the tab = the DLL waits for the Lua part's rows (it never
answers). G-Portal log (fetched 14:19, owner's yes): SuperB (0x05891a85470cffe2) joined with 13 mod channels on 11-20
20:42/20:44, with 1 channel at every join today from 10:30 (owner 14 channels): his FlameKit Lua part mostly not
loading since his first start after the 0.15.374 release (the held Lua part is put in place at that start: reading,
not proven). Owner 14:15 "they tried rebooting their PC and the game.. same result.. I tested it with my computer and
I'm not having that happen"; 14:17 "they're not capable of" sending logs; 14:19 "they were playing just fine last night
with that version". The updater (DLL) re-downloads every listed file that differs on disk when a newer version comes.
**Owner 14:22 "no committ all todays changes to development, and then push it to release" + "update G-portal" + "if his
stuff is still broke I'll update him manually"**: 0.15.396 = Development and Stable (DLL b09e1d4b, the 0.15.377 build),
G-Portal: 28 Lua files changed since 0.15.374 + flamekit_native/mod.json (no DLL); G-Portal reloaded 14:24:51, 17
feature(s) loaded, no error (it reloaded every second while the files came in: loose_loot/msg_tabs missing in between).
Old core/server_settings.lua and features/server_tab.lua are still on G-Portal (not loaded). The owner's game: "Update
v0.15.396 is ready" 14:25. Not yet seen in a game: 0.15.390+ client part (owner's game had not restarted on it).
**Owner 14:27 "looks like the update fixed his issue"**: SuperB's UI works again on 0.15.396 (the re-download of the
files that differed repaired his install, as far as known).
**Owner 14:32 "it was logging it, it was just delayed so I did not see it right away"**: the chop Loot lines (13:43
question, the 13:33 tree) are there: closed. (Chop drops are looked for 1, 3, 6 and 10 s after the break.)
**Owner 14:43 "there isn't a trigger when the items drop? you have to just scan the ground for drop items orr???"**:
answered: no event for a dropped item or a new entity (SDK event list: PickupEvent only on pick up;
TransformedToLootEvent, OnDestroyNotifyEvent carry no pickup); offered scanning every second for 10 s (open, not
answered). **14:44 "the self heal is valid.. can you just make the log say "Midevil heals themselves for 18" whenever
you see a character healing themselves?"**: 0.15.397 (server only, local server): heal_target() -> "themselves" when
healer = target (feed.hit and feed.heal: companions too); the self heal logging switched off (SELF_LOG 0). G-Portal not
updated (asked).
**Owner 14:57 "it seems fine to me"** (taken as: the chop scan timing stays 1/3/6/10 s, no change; G-Portal stays on
0.15.396 until he says so).
**Owner 14:58 "I just want to optimize how things work... scanning for stuff over and over doesn't seem efficient"**:
0.15.398 (server only, local): loose_loot and loot_spots log their walks' cost once a minute ("... last minute: N
walk(s), entities, ms in steps"). Known: EMF has no search by component or place, only world:entities(); a full
synchronous walk with 4 checks per entity (flamekit.lootnear) took ~50 ms on the local server. Options told: merge the
two walks into one shared core walk; or a C++ spawn hook in the DLL (no scanning; game update + server restart).

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
