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

## tests/drive_harness.lua

A side-by-side check for changes to the drive: it runs `drive_step` from two versions of `npc_probe.lua` through the
same scripted scenarios in a fake world (walking, jumps, double jumps onto a ledge, a cliff drop and waiting, water,
diving, climbing out, a wall at the shore, glider, fast travel, holds, lures, stuck and blocked) and compares every
component write, the companion's record, every log line and every notice, tick by tick.

    texlua local_server/tests/drive_harness.lua <old.lua> <new.lua> <seed> [ticks]   -- seeds 1..n random, 1001-1006 fixed
    texlua local_server/tests/drive_harness.lua <file> <file> 1 4000 lines 12 <first line> <last line>   -- lines never run

Used for the 2026-11-18 split of drive_step into parts (0 differences in 66 scenarios). It only proves "the same as
before", not "right in the game": an in-game retest is still needed.
