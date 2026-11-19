# Companion following: the simplified plan (draft for the owner, 2026-11-18 18:1x)

Owner 18:04: "I feel like this shell game of numbers tic tac toe is proving this approach might not be working. every
time you change the numbers to fix one thing, something else becomes off... if we keep playing this numbers game you're
going to have to come up with a simplified solution". Owner 18:06: "write it up, maybe rely more one the new meta data
from the bread crumbs... he can't teleport easily now so not ever situation needs to be perfectly handled..." (read
as: he CAN be respawned beside the player easily now, so not every situation needs perfect handling).

NOTHING HERE IS BUILT. Owner review first.

## Why the numbers kept fighting

Two systems decide where he may walk: the C++ edge stop (a ray that guesses the ground 1.5 m ahead; fooled by planks,
trap doors, overhangs, cliff lips) and the player's breadcrumb trail (proof of where the player walked). Every fix this
afternoon was a threshold that settles an argument between the two (FLOOR_LINK 0.7, FLOOR_FIRST 1.5, FLOOR_REACH 3.6,
drop limit 7.5, DROP_AT 1.5, STUCK_MOVED 1.5, DROP_RESUME 6 ...). Moving one moves the border with the others.

## The rule

The trail is the only truth. He goes where the player went, the way the player went (the crumbs' meta data says how).
Whatever he cannot copy, he skips: respawn beside the player (it works well and fast).

## What stays as it is

- The trail: a crumb every 0.25 m the player moves on the ground, with its meta data (state, jump count/type, speed,
  up/down speed, facing, water depth) and the air segments (takeoff, landing, top, time, double jump, glider, water).
- His target: the next crumb ahead (he stays within about 0.3 m of the player's path). He stops within 2 m of the
  player.
- Water: swimming, diving, the climb-out hop, the leap into the water.
- Put away and back beside the player: glider, fast travel, and the respawn itself ("Companion has spawned near you!").
- The jump-follow launch (lift, speeds, steering in the air, the settle after landing).
- All the logging.

## What changes

1. **On the trail, no edge stop and no ray step jump.** Where the player walked, there was ground. The C++ edge stop is
   off while he follows crumbs; it stays only for the one place he leaves the trail on purpose (straight to a swimming
   player). The C++ step jump (the ray from 5 m up, also the overhang bug) is removed.
2. **Ups and downs come from the crumbs' meta data:**
   - The player was in the air between two crumbs and came down higher (an air segment with rise): at the takeoff crumb
     he launches to the landing (the jump follow as now).
   - The next crumb is a step up without a jump (the player stepped or climbed up): he hops to it as soon as he is at
     the crumb before it (no waiting for "no progress" first).
   - Came down lower: up to a safe height he simply follows (he walks off and falls, as the player did); higher than
     that (or a glide, or anything else he cannot copy): respawn beside the player once the player is on the ground.
3. **One stuck rule.** No progress toward his next crumb for a few seconds, for any reason (blocked, wedged, holding
   back, fell off the path): one notice, then the respawn beside the player. The notice names the reason when the trail
   knows it ("too high to follow", "can't get up there"), otherwise "Companion can't follow you!".

## What goes (Rule 0n: removed, no fallback)

- The floor proof and the edge permission (FLOOR_LINK, FLOOR_FIRST, FLOOR_REACH, the "player went down here" check).
- The drop wait (h.waiting, DROP_AT, DROP_RESUME, the walk-there-first state, its per-second notice).
- The stuck state that waits for the player to come back (h.stuck, STUCK_MOVED, "come within 6 m", the per-second
  notice) and the climb launch after DJ_WAIT of no progress (replaced by the step-up hop in 2).
- The separate stuck counts in the water and on the way to the water fold into the one stuck rule.
- C++: the ray step jump (maybe_step_jump) and its boost.

## Numbers left (each one decides one thing, none borders another)

| What | Value |
|---|---|
| a crumb every | 0.25 m |
| a crumb is reached within | 0.3 m |
| he stops this close to the player | 2 m |
| a step up he hops (next crumb this much higher) | 0.5 m |
| a jump he copies (landing this much higher) | 1.0 m |
| the highest drop he follows (his own fall damage starts at 8 m) | 7.5 m |
| no progress before the respawn | 3 s |
| plus the water, glider and fast travel numbers, unchanged | |

## Risks

- Without the edge stop he can step off a narrow path where he cuts a corner (at most about 0.3 m). If he falls, the
  stuck rule respawns him; a fall over 8 m hurts him (lethal from 16 m).
- More respawns than now in odd places. Owner 18:06: not every situation needs perfect handling.

## How it gets built and checked

One rework of the drive parts (drive_jump_follow, drive_pick_target, drive_stuck, drive_steer), the old code removed;
the C++ step jump removed (buildprobe + one server restart). The side-by-side harness can only check for errors here
(the behaviour changes on purpose); then a full retest in game: walking, stairs up and down, the trap door, the
boardwalk, ledges, single and double jumps, drops (small and big), water in and out, diving, glider, fast travel, Call.
