# local_server

Since 0.15.368 (owner 2026-11-20 19:05: "the companion system and pets needs to get fully committed to both dev and
stable") the companion system is part of the release: `flamekit/features/companions.lua` + `flamekit/features/companions/`
(the server end), `flamekit/features/npc_fields.lua` (the full recorder's field list), `flamekit/features/npc_wheel_probe.lua`
(the player's end), `flamekit/core/companion_net.lua` (their two channels, registered once) and the C++ part in
`flamekit_native/src/companions_server.cpp`. The local test server runs the release's `flamekit` folder as it is
(its own main.lua is gone). This folder only keeps the companion tests:
`python3 local_server/tests/bundle.py` (the parts as one file), `globals_check.py`, `drive_harness.lua`, `fight/`.

## tests/drive_harness.lua

A side-by-side check for changes to the drive: it runs `drive_step` from two versions of `npc_probe.lua` through the
same scripted scenarios in a fake world (walking, jumps, double jumps onto a ledge, a cliff drop and waiting, water,
diving, climbing out, a wall at the shore, glider, fast travel, holds, lures, stuck and blocked) and compares every
component write, the companion's record, every log line and every notice, tick by tick.

    texlua local_server/tests/drive_harness.lua <old.lua> <new.lua> <seed> [ticks]   -- seeds 1..n random, 1001-1006 fixed
    texlua local_server/tests/drive_harness.lua <file> <file> 1 4000 lines 12 <first line> <last line>   -- lines never run

Used for the 2026-11-18 split of drive_step into parts (0 differences in 66 scenarios). It only proves "the same as
before", not "right in the game": an in-game retest is still needed.
