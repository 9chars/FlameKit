# Player movement: what FlameKit measured (2026-11-16, Super B Jump and Fast Dive)

Game build 1287369, EMF 0.6.6, local dedicated server. Code: `flamekit/core/leap.lua` (Super B Jump),
`flamekit/core/dive.lua` (Fast Dive), `flamekit/core/fall_guard.lua`, `flamekit/core/skills.lua`. Probes: `probes/`.

## Input (server: `PlayerInput.fromClient`)
- `digitalInput` bit N is the game's `keen::ecs::PlayerInputType` N. Measured: Space sends **32 (Jump) and 37 (Glider)**
  together (the JumpAndGlider double binding); crouch sends **55 (Sneak)**; other bits seen while moving: 46-49, 53.
  HeadDive (33) is never sent by a key, not even crouch in the air.
- `movementStick` (x, y): keyboard W = y 1, S = y -1; a controller's stick gives the same values. Reading the game's own
  input means controller bindings work without extra code.
- Server steps: 60 a second. The owner's quick double taps reached the server 8-9 steps apart; the game's own double
  jump only takes a second press from about 13 steps after the jump (earlier presses it ignores).

## Movement state (`DynamicLocomotion`)
- `state` (`LocomotionState`): 0 Walking (on the ground), 1 Sliding, 2 Falling (in the air), 3 Flying, 4 HangGliding,
  9 Swimming, 10 Diving (water).
- `jumpCount`: 1 after a jump, 2 after the double jump, 0 on the ground (and in a fall from a ledge).
- A jump leaves the ground at 9.58 m/s and rises about 1.9 m; a double jump about 3.8 m in all. Gravity takes 25 m/s
  every second; the top fall speed is 20 m/s.
- `MovementCollider.results.m_value.groundDistance` is only known close to the ground (0.5-1.3 m before a landing);
  higher up it reads 3.4e38 (no ground in range). There is no EMF call for the ground height below a player.

## Actor state bits (`Actor.currentState`, `keen::actor::StateFlag`)
0 Grounded, 1 Jumping, 21 InSneakMode, 23 HasAggro, 24 InCombat, 30 InSnappingLerp, 32 Falling, 33 HeadDiving,
37 HangGliding, 50 IsReadyForGameplay, 52 WantsToMove. Crouch is a toggle: one Sneak press on the ground turns 21 on
until the next press or a jump; a press in the air does nothing. **The game rebuilds these bits every step** in the
player's own game: written by the server (0.15.229) or by FlameKit in the player's game (0.15.230) they are gone a
step later. Exception seen once: HeadDiving set by the server every step (0.15.224) stayed after the landing and kept
the player rolling forward until cleared.

## Pushing a player: `Impulse`
- Four slots (`impulses[1..4]`), each `{impulse (x, y, z), type, startTime, endTime, keepAliveMask}`; times in ns,
  game clock = `world:tick() * 1e9 / 60`. The game moves the player with them (also the player's own game).
- `impulse` is a speed in m/s while the slot lasts (`type` 0 S_Curve eases it in; 1 FadeOut fades it out over its
  time). Super B Jump: 60 up for 0.9 s rises about 54 m; the rise grows evenly with the strength (10x 535 m, 20x
  1075 m, 30x 1615 m).
- `keepAliveMask`: actor state bits the slot needs; the player must be in **every** state named, else the game ends the
  slot at once. Measured: HangGliding (37) alone for gliding (the game's own updraft burst), Jumping|Falling for a leap
  that starts on a jump, Falling (32) alone for a dive in free fall. Naming Jumping, Falling and HangGliding together
  ended a push within 1/4 s.
- Renewing a slot restarts its curve from zero (visible slowdowns every renewal): give one long `endTime` instead.

## Height limit
- Above about 2560 m the game says "you strayed too far, returning to safety" and sends the player back (a leap from
  2220 m reached 3295 m and was sent back; 2233 m and 2481 m gave no warning). FlameKit's ceiling for leaps and the
  glider's climb: 2480 m.

## Falling damage
- `DynamicFallDamage.fallStartAltitude` (metres, the same unit as the position): setting it to the current height
  every step while `wasFalling` makes any landing a short fall (`core/fall_guard.lua`).

## Skills
- `UnlockedSkillNodes.knownSkillNodes[1..256]`: the player's unlocked skill tree nodes (HashKey32). The skill tree is
  resource type `0xe4b6994f` (`SkillTreeResource`, 243 `SkillTreeNode`s of 140 bytes: `id` +0, `name` LocaTagId +12,
  `activeSkillUnlockRef` +24, `impactReference` +76, `type` +134, `maxLevel` +136). Double Jump = node `ffd5f940`
  (unlock item `Ability_DoubleJump`). The list and the scripts that read it: `<work folder>\claude_scratch\skills\`.

## Explosions (landing blasts), spawned with `emf.spawn` at the player's feet
- `Explosion_Player_Tool_TNT_T1` (3ed869e3-...): a boom and a crater. `_T4` (9a216c97-...): a big one. `_T3`
  (93ee028c-...): not tried alone.
- `Explosion_Player_WeaponGem_MeteoricDescent` (896758dd-...): a boom, no crater.
- `Explosion_Player_Skill_Shockwave` (3b874eb5-...): nothing heard when spawned alone.
- Not yet checked: whether these hurt monsters, other players, pets or buildings nearby (Fast Dive shields the diver
  for 1.5 s with a hit rule).

## Tried and dropped: a player's pose (2026-11-16, owner: "lets completely drop that idea")
A head-first pose while falling and a crouched landing (Fast Dive, 0.15.223..0.15.230). The pose is chosen by the
player's own game from its own input and its own state, before anything FlameKit writes:
| Route | Head-first | Crouch at the landing |
|---|---|---|
| Server adds the button to `PlayerInput` (0.15.223, 0.15.227) | nothing | nothing |
| Server sets the state bit (0.15.224, 0.15.229) | nothing in the air; stuck rolling on the ground | gone one step later |
| The player's game adds the button to `ClientPlayerInput` (0.15.228) | nothing | nothing |
| The player's game sets its own state bit (0.15.230) | gone at once | gone at once |
Left: patching the game's movement code from the DLL, or the DLL sending real key presses (keyboard only, breaks with
rebinding). Both against FlameKit's rules; not done.

Also tried: writing `DynamicLocomotion.state` to Falling while gliding does not close the glider (0.15.219).
