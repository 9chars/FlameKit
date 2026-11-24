# Spawn Nodes tests (no game needed)

Tests for `flamekit/features/spawn_nodes.lua` and the core modules it uses, run with `texlua` (it is in the Claude
container at `/usr/bin/texlua`). `mock.lua` is a fake EMF world: entities with position, health, faction and scale; time
moves only when a test calls `run()`. These tests check the code's logic. They are not the game: what they pass still
needs the in-game tests in HANDOFF.md's "OPEN" section.

Run all of them from the repository root:

```
for t in tr rl ai hd ui mk wv sd ct op lv jn cd sw; do echo -n "$t "; texlua tools/sntest/$t.lua flamekit/features/spawn_nodes.lua | tail -1; done
texlua tools/sntest/rw.lua
```

Each prints `ok` / `FAIL` lines and ends with `ALL OK` or `N FAILED`.

| Test | What it checks |
|---|---|
| tr.lua | the roster: own monsters, deaths, unreadable health, monsters coming up with 0 health, Remove (old wave timing: `wave_dead = 0`) |
| rl.lua | a reload in the middle of a raid: monsters, bodies and the raid taken back; the raid still ends |
| ai.lua | (0.15.553) the 2026-11-23 test code is gone: no AI log, path census, full recordings or path push; the hunt order still goes out |
| hd.lua | the animal hold file: held from the raid's start, rewritten while it runs, let go at its end and after 30 min |
| ui.lua | the tab and the Spawn Nodes window for every trigger: no errors, every label beside its drop-down, the window button |
| mk.lua | Raid monster markers against a fake EMF that refuses past 39 messages a step (`EMF_LIMIT=20` for a stricter one): never more than 30 a check, all taken off after Remove; the "Mark its monsters" switch |
| wv.lua | "Next wave after": 90 % waits for the dead, "It has spawned" does not; a value off the list is refused |
| sd.lua | "First monsters after" (10 s default, 0); the red start notice without the count, its double siren; no countdown before the first monster |
| ct.lua | the countdown follows every kill within 0.5 s and shows 0 right after the last one |
| op.lua | open to every player (is_admin): a player who is not an admin can make a group and add a node |
| lv.lua | Starting level and Level per wave (60, 85, 100, never 110), each Loot choice, the Auto Loot marks (core/loot_skip.lua) |
| jn.lua | a world monster that comes into a raid joins it; a FlameKit test monster does not |
| cd.lua | a group's cooldown survives a reload |
| sw.lua | the Spawn Nodes switch (`sn_enabled`) turned off mid-raid: the group stops as with Stop, the raid's count is forgotten, the animal hold / raid lock / protection / spare files are set to nothing; kit.lua calls `switched_off` when the switch turns off and at load (not for another key, not when it turns on) |
| rw.lua | core/reward_loot.lua on its own: runes into the killer's bag (the chest when no killer is known), the legendary item into the chest; loose drops near the death removed, far ones, late ones and FlameKit's own marks left (run from the repository root, no argument) |

When a change makes an older test's assumption wrong, set that test's group to the old behaviour (as tr.lua does with
`wave_dead = 0` and several do with `start_delay = 0`) and say so in a comment, so the test keeps checking what it was
written for; the new behaviour gets its own test.
