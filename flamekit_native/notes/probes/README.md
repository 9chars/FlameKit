# Probes

Small read-only Lua features for measuring the game on a server. FlameKit never loads them by itself and they are never
published: they are copied onto the **local server only** for a test, and taken off again afterwards.

To use one:
1. Copy the probe into `<server folder>\emf\mods\flamekit\features\`.
2. Add its line to the server's `main.lua` (only there, never in the repository's), before `-- "features.my_next_feature",`:
   `"features.input_probe",      -- TEMPORARY probe (local server only)`
3. EMF reloads FlameKit by itself. The probe's lines are in `<server folder>\emf\emf_core.log` (`input probe:`, `jump probe:`).
4. Afterwards: put the server's `main.lua` back to the repository's and remove the probe file (or move it to `_to_delete\`).

| Probe | What it logs (on every change) | Made for |
|---|---|---|
| `jump_probe.lua` | each player's jump button, `DynamicLocomotion.state`, `previousState`, `jumpCount`, height, upward speed, stamina; the height every 0.1 s for 3 s after a press; once per player their unlocked skill nodes and whether Double Jump (`ffd5f940`) is among them | Super B Jump (0.15.209) |
| `npc_probe.lua` | not read-only, a test: console `flamekit.npc spawn/offer/look/remove`; spawns one of the game's unused test villagers, puts FlameKit's "E Talk" on it, logs its parts | an NPC with FlameKit's own prompts (2026-11-17) |
| `input_probe.lua` | each player's buttons (`PlayerInput.fromClient.digitalInput` as bit numbers), the actor state bits (`Actor.currentState`), `DynamicLocomotion.state`, `ActorInput.locomotionSpeed`, `PlayerState.playerStateMask` | Fast Dive's crouch (0.15.229) |

What they found is in `../MOVEMENT.md`.
