# EMF 0.6.6: what it offers FlameKit (read in full on 2026-11-13)

Check this list, and EMF's own docs, before building a workaround or writing that "EMF cannot do X". The full
reference is in the EMF zip on the owner's PC: `docs/modding/lua.md` (every Lua call, one table), `llms.txt` (the
whole C and Lua API in one file), `reference.md` (rules and limits per API version), `server.md`, `updating.md`,
`cookbook.md`, `docs/engine_parts/*.md` (the game's internals EMF found). Installed: core API v32, Lua host 1.24.0.
FlameKit's `mod.json` asks for Lua `>=1.21`; a call from a later Lua version needs `pcall` or a higher requirement.

## Lua calls, and whether FlameKit uses them

| Call (Lua version) | What | FlameKit |
|---|---|---|
| `emf.on_tick`, `emf.on_event`, `emf.on_key`, `emf.key_down` | steps, engine events, keys | yes (kit, loot_filter PickupEvent, dump key) |
| `emf.setting` / `set_setting` / `on_setting_changed` | mod.json settings | yes |
| `emf.on_world_data` / `save_world_data` / `player_data` / `save_player_data` (1.1, 1.20) | text per world, per player account | yes (junk lists per player on the server, experimental) |
| `emf.item`, `item_info`, `item_name`, `language` (1.21) | item ids, names in the player's language | yes (core/items.lua) |
| `emf.give`, `put`, `take`, `move` (1.6) | items in and out of inventories | yes (take, give; move not used) |
| `emf.health`, `attribute`, `attribute_add`, `damage` (1.5) | health, mana, level, XP | yes (party, experimental) |
| `emf.teleport` (1.7) | fast-travel move, spawn points | yes (experimental: altar, spire) |
| `emf.request_save` (1.6) | save the world now | yes (server_save.lua, restart helper) |
| `emf.tell`, `broadcast` (1.6, 1.22 `{system=true}`) | chat lines | yes (loot_filter fallback, experimental) |
| `emf.command` (1.4 `{players=true}`), `sender`, `reply` | console / chat commands | yes (`/flamekit.junk ...`) |
| `emf.net.channel/send/send_to/send_all/peer` (1.19) | messages between a player's game and the server (max 16384 bytes, rate per 10 s) | yes (lf, exp, party, party_test, map, ver) |
| `emf.on_player_joined/left/died` (1.20) | who is in the server world; told again after a reload | yes (core/players.lua since 0.15.48, experimental, loot_filter); `died` not used |
| `world:account`, `name`, `character_name` (1.22), `position`, `get`, `entities`, `template` | per-entity reads | yes |
| `emf.buff_types`, `buff_type`, `buffs` (1.24) | buff types (id, slot, name, hidden, time) and an entity's active buffs, any world | yes since 0.15.49 (party.lua); needs Lua 1.24, called through pcall |
| `emf.apply_buff`, `remove_buff`, `on_buff` (1.24) | give / cleanse buffs, hear players' buff changes | no |
| `emf.hit_rule`, `hit_rule_remove`, `on_hit` (1.23) | change or watch hits (fall, shroud, cold, drowning with `kinds`) | yes (experimental: no fall damage, shroud) |
| `emf.world_settings.*`, `on_world_setting_changed` (1.10) | the world's settings | no |
| `emf.time_of_day` (1.4), `session`, `session_token` | clock, session ids | yes (session_token) |
| `emf.spawn`, `destroy`, `kill`, `add_component`, `remove_component` | entities | no |
| `emf.offer`, `spawn_offer` (1.14) | the game's "E" prompt on an entity | no |
| `emf.bus.*` (1.17), `emf.json` (1.18) | messages between Lua mods in one game; JSON | json yes; bus no |
| `emf.hud`, `notify`, `window`, `image`, `wheel*` | EMF's own UI | **never** (rule 12: FlameKit draws its own UI) |
| `emf.xp_required`, `level_cap`, `set_level` (1.11) | XP | no |

## C API (the DLL)

FlameKit Native uses: `on_tick`, `local_player`, `get_component` (through `World::get<T>`, which refuses a component whose
size changed), `for_each_item`, `item_data`, `register_program_def` (UiPingEvent, UiCurrentLocationEvent), settings,
`player_name`, `game_build` (since 0.15.49: FlameKit's own raw memory reads only on build 1287369). Also there and not
used: `singleton(world, name)` (named world singletons, e.g. `BuffRegistry`), `buff_text` (a buff's name in the
player's language), `on_player`, `net_*`, `hook_*`, `find_pattern`.

## Facts found while reading (not obvious from the tables)

- **Player events after a reload:** a reloaded Lua script is told about every player already there, as joined, at its
  first step (reference.md "v28"; measured on the owner's server, 0.15.48).
- **Entity ids of players:** 1..0x3FF; a leaving player's id goes to the next player who joins.
- **Buff icons are not in EMF.** They are in the game's data files: the buff registry (resource type `0x1be67cef`)
  lists every buff type with its icon's GUID (item_icons.hpp has the layout). The icons are plain RGBA, white symbols.
- **`emf\commands.txt`:** EMF runs console commands written into that file about once a second while a world runs; the
  output goes to `emf_core.log`. Useful without a mouse: `lua.perf` (time per Lua mod per step), `lua.status`, `mods`,
  `players.mods`, `buffs.of <entity>`, `buffs.list`.
- **Debug bridge** (`[debug] bridge=1`): a named pipe for scripts (`state`, `log`, `wait`, `console`, `screenshot`, `quit`).
  Its screenshot is the game's own picture, so FlameKit's overlay window is not on it. `join` and `load_world` work
  with LOCAL characters only.
- **Mod check on join** (server.md "Players' mods"): mods with `"side": "both"` in mod.json are compared by exact
  version when a player joins; a server can warn or kick. FlameKit leaves `side` unset on purpose: it works across
  versions (server_version.lua says so in the game) and must not get players kicked over a version difference.
  FlameKit Native says `"side": "client"` (EMF.exe then tells server owners it is not needed there).
- **Game updates:** EMF knows builds by the exe's SHA-256 (`emf_core.log`: "known build 1287369"); on an unknown
  build it searches by pattern and turns off what it cannot find. `tools\emf_sigcheck.exe` checks an exe without
  starting the game.
- **Not in EMF 0.6.6** (see EMF_REQUESTS.md): controller buttons for mod keys, hidden settings, whether the EMF
  console is open, the bus for native mods.
