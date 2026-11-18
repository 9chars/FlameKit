# local_server

The companion system as it runs on the owner's local test server (not published, not in any release). These files
are the live copies from `<server folder>\emf\mods\flamekit\`:

- `features/npc_probe.lua`: the companion system (roster, spawning, following drive, water, jumps, glider/teleport
  put-away and return, the wheel's server side, test console commands).
- `features/npc_fields.lua`: generated field list for npc_probe's full recorder (logging).
- `main.lua`: the local server's own main.lua (lists `features.npc_probe` and not `features.npc_wheel_probe`).
  Never overwrite the server's main.lua with the repository's; edit it in place.

The C++ hook that goes with it is `../flamekit_server_probe/` (installed as `<server>\emf\mods\fk_server_probe\`).
Whenever any of these change on the server, copy them here and commit (owner 2026-11-18 15:39: "get it into git").
