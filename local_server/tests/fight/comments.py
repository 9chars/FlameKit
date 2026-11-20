# New comments for the drive section of npc_probe.lua (owner 2026-11-18 15:39, #7: comments say what the code does
# now; the change history lives in HANDOFF.md and git). Applied to the stripped region by code anchors.
import sys, re
src = open(sys.argv[1], encoding='utf-8').read().split('\n')
A, B = int(sys.argv[2]), int(sys.argv[3])

# anchor (the code line, stripped; "#n" suffix = its n-th occurrence in the region) -> (comment lines above, trailing)
C = {}
def above(anchor, text, trail=None):
    C[anchor] = ([l for l in text.strip('\n').split('\n')], trail)
def trailing(anchor, text):
    old = C.get(anchor, ([], None))
    C[anchor] = (old[0], text)

# ---------------------------------------------------------------------------------------------------------------------
above('local FLOAT_LIFT = 0.45', '''
-- ===== The drive's numbers =============================================================================================
-- Swimming: his body is held FLOAT_LIFT above the player's height while diving, tilted nose up FLOAT_PITCH degrees.''')
trailing('local FLOAT_LIFT = 0.45', '-- metres')
trailing('local FLOAT_PITCH = 28', '-- degrees, nose up')
trailing('local SWIM_OUT_STOP = 0.8', '-- in the water with the player on land, he only stops this close (he has not arrived while he swims)')
above('local DJ_AT, DJ_RISE, DJ_MARGIN, DJ_TICKS, DJ_WAIT, DJ_REACH = 1.5, 1.0, 0.7, 150, 60, 6', '''
-- Jump follow (drive_jump_follow): he launches from within DJ_AT of a takeoff crumb toward a landing DJ_RISE or more
-- higher, aiming DJ_MARGIN over it; a flight lasts at most DJ_TICKS. When he makes no progress for DJ_WAIT toward a
-- crumb that is DJ_RISE or more up and at most DJ_REACH away, he jumps up to it too. The launch speed is written for
-- up to DJ_LIFT ticks until the game counts him in the air; after a landing up top he stands still DJ_SETTLE ticks.''')
trailing('local STUCK_MOVED = 1.5', '-- the player must have moved this far since he gave up before "back near him" counts')
above('local GLIDE_STATE, GLIDE_WAIT, GLIDE_FAR, LAND_TICKS, TP_AFTER, FAR_JUMP = 4, 240, 30, 60, 120, 50', '''
-- Put away and back (drive_put_away, F.tick): the glider is the player's locomotion state GLIDE_STATE; still gliding
-- after GLIDE_WAIT ticks or GLIDE_FAR metres away, he is put away. The player moving more than FAR_JUMP in one tick
-- (a fast travel) puts him away too, and so does TP_AFTER ticks of not being able to follow. He comes back beside the
-- player once the player has stood on the ground LAND_TICKS (and his game has loaded).''')
trailing('local WATER_NEAR = 2', '-- metres above the swimming player\'s water surface that still count as "at the water"')
trailing('local DIVE_PLAYER = 1.8', '-- the player\'s depth from which he dives with him (at the surface the player reads about 1.3)')
trailing('local SWIM_ENTER, SWIM_DEPTH = 0.5, 0.9', '-- he swims while his own depth is over 0.5 m, and is held at about 0.9 m')
trailing('local SWIM_MAX, SWIM_GAIN = 6, 1.2', '-- swimming speed: 1 m/s past the stop distance, +1.2 m/s per metre, at most 6')
trailing('local HOP_TICKS, HOP_HOLD, HOP_EVERY, HOP_MARGIN, HOP_FORWARD = 90, 40, 120, 0.7, 3', '-- the climb-out hop, see drive_water')
above('local drives = {}', '''
-- ===== Following: the drive ============================================================================================
-- No game AI: his AI (DynamicEnemy01BehaviorState.enabled) and his route planner are off. FlameKit keeps the player's
-- breadcrumb trail and writes the next crumb ahead of the hound into his AI data's movementTarget and the player's spot
-- into homeZonePosition. The C++ server probe (fk_server_probe, after the game's steering step) turns that into his
-- movement input (direction, look, walk/run/sprint by distance, nothing within DRIVE_STOP of the player), with an edge
-- stop and a step jump of its own; the game's locomotion moves and animates him. combatData.targetOfMyTarget = true
-- turns the native edge stop and step jump off; combatData.isTargetInsideLeash = true lets him drop down (see
-- drive_steer). No route search and no game follow orders.''', '-- entity -> his record h: { player, trail = {}, ... }')
above('local holds = {}', '''
-- a hold (console "hold", for tests): he stays where he stands and turns toward a target until the time is up''', '-- entity -> { target, untill (tick) }')
trailing('local DRIVE_STOP, DRIVE_STEP = 2, 0.25', '-- he stops within 2 m of the player (the C++ kFollowStop matches); a crumb every 0.25 m')
trailing('local CRUMB_REACH = 0.3', '-- a crumb within this is reached; he aims at the first one further away')
trailing('local FLOOR_LINK, FLOOR_REACH = 0.7, 3.6', '-- the floor proof, see drive_steer')
above('local DROP_HEIGHT, DROP_GAP, DROP_RESUME = 7.5, 6, 6', '''
-- Drops and flights: no crumbs while the player is off the ground. A crumb more than DROP_HEIGHT below the one before
-- (below that his own fall damage starts at 8 m, lethal at 16 m), or the first one after more than DROP_AIR_TICKS in the
-- air (a glide, not a jump), starts a new piece of trail (brk): he walks to the last crumb before it and waits there,
-- and goes on when the player is back within DROP_RESUME on his level.''')
above('local STUCK_TEXT = {', '''
-- the stuck notice says what holds him ("stuck" itself is only for a real clipping problem)''')
trailing('local STUCK_TICKS = 180', '-- 3 s without 0.3 m of progress toward his crumb: he gives up')
trailing('local CRUMB_LOG = true', '-- every crumb of every companion into the server log')
above('local function player_airborne(world, player)', '''
-- the player is off the ground unless he has ground contact, under 0.1 m from it, and locomotion state 0 (the game keeps
-- "ground contact" for the first and last part of a jump)''')
above('local BLOCK_R = 2.5', '''
-- Who stands in his way when he gives up: every body within BLOCK_R of him (not himself, not his player), its kind from
-- its components (Animal; ActiveNpcState = a villager; a player; DynamicEnemy01BehaviorState = a monster or a
-- companion), how far, and whether it is in front of him (toward fx, fz); also his collider's "touching a character"
-- flags. Returns the kind of the nearest one in front ("animal", "npc", "player", "monster") or nil, and a log line.''')

# ---------------------------------------------------------------------------------------------------------------------
above('local function face(world, id, yaw)', '''
-- ===== The drive, in parts =============================================================================================
-- drive_step runs once per tick for each following companion. drive_read puts the tick's facts into one table (s), then
-- the parts run in order; a part that returns true has decided this tick (he swims, is put away, jumps, holds or
-- waits) and the rest is skipped. The parts share only s and his record h (kept between ticks).

-- his body upright and turned toward yaw (radians, 0 = +z)''')
above('local function hold_at(a, x, y, z)', '''
-- the native hook's target and its "player" spot both at x, y, z: he stands there''')
above('local function health(world, id)', '''
-- his health for the logs (-1 when it cannot be read)''')
above('local function edge_off(a)', '''
-- the native edge stop and step jump off for this tick''')
above('local function launch_speeds(d, rise)', '''
-- a jump-follow launch: the speeds that carry him d metres across and rise metres up (gravity 25; up at most 16 m/s
-- for rise + DJ_MARGIN, across at most 10 m/s so that he comes down at the spot)''')
above('local function launch(world, id, ddx, ddz, d, vup, vh)', '''
-- the launch itself: lifted 0.3 m first (a speed written on the ground does not take), then his speed up and across
-- toward ddx, ddz, turned that way. Returns whether the speed could be set, and the speed across (x, z).''')
above('local function report_blockers(s, what, dx, dz)', '''
-- when he gives up: who stands in his way, into the log (h.blocked_by keeps the kind)''')

# drive_read ----------------------------------------------------------------------------------------------------------
above('local function drive_read(world, id, h)', '''
-- the tick's facts: where the player and the hound are, his AI kept off, and the water both read (currentWaterState
-- is the depth below the surface); nil when either body is gone''')
above('local pwater = (okw and tonumber(pw)) or 0', '''
-- the player swims (pwet) when his depth is over 0.5; the hound swims (swim) on his OWN depth''')

# drive_waterlog ------------------------------------------------------------------------------------------------------
above('local function drive_waterlog(s)', '''
-- the water log (measuring only): once a second while the player or the hound reads any water, and 5 s after; both
-- water readings, his submerge depth, heights, ground, locomotion state, speed and its direction, the input the drive
-- gave him, his facing, the way to the player (compass angles, 0 = +z), his air and health, the player's air''')

# drive_water ---------------------------------------------------------------------------------------------------------
above('local function drive_water(s)', '''
-- Water. The leap rule: when the player came down into the water from the air (h.leap, drive_track_player), the edge
-- stop is off until the hound is in the water himself; he follows the trail to its end and then straight to the
-- player. Over when the player leaves the water.
-- While HE swims (returns true): his target is the player; FlameKit sets what the game does not do for a
-- non-swimmer: his height (held at SWIM_DEPTH below the surface, or at the player's height + FLOAT_LIFT while the
-- player dives), his speed (the game keeps an in-air speed frozen, so it is written every tick: toward the player,
-- nothing within the stop distance, SWIM_GAIN per metre, at most SWIM_MAX), and his tilt (nose up FLOAT_PITCH, facing
-- where he swims; the yaw is kept in h.swim_yaw because reading it back from a tilted body goes wrong).
-- Out of the water: upright again and a fresh trail.''')
trailing('pcall(function() a.combatData.targetOfMyTarget = swim or (h.leap ~= nil) end)', '-- edge stop off while he swims or leaps')
above('h.stuck, h.waiting, h.prog = nil, nil, nil#1@drive_water', '''
-- in the water he swims to the player: any stuck or drop wait is over''')
above('local hopping = h.hop_until and t < h.hop_until', '''
-- the height: a quarter of the difference each tick, at most 0.08 m, never pushed down while he touches the bottom
-- (wading), and no hold during a climb-out hop''')
trailing('local fix = math.max(-0.08, math.min(0.08, want * 0.25))', '-- at most 0.08 m a tick')
above('local stop = pwet and DRIVE_STOP or SWIM_OUT_STOP', '''
-- with the player out of the water he keeps going to SWIM_OUT_STOP''')
above('local along = 0#1@drive_water', '''
-- Progress = how far HE has moved along the line to the player since the last mark (keeping pace behind a swimming
-- player counts; sliding sideways along a bank does not). None for HOP_TICKS while the player is higher: a climb-out
-- hop (speed straight up for the player's height + HOP_MARGIN, HOP_FORWARD toward him, HOP_HOLD ticks, at most every
-- HOP_EVERY). None for STUCK_TICKS: the "can't follow" notice, cleared when he moves again.''')
trailing('v.x, v.z = math.sin(yaw) * spd, math.cos(yaw) * spd', '-- up and down left to gravity during the hop')

# drive_track_player --------------------------------------------------------------------------------------------------
above('local function drive_track_player(s)', '''
-- What the player does, every tick: on the ground or in the air, a leap into the water, air segments, and his meta
-- data for the crumbs. While he swims there are no crumbs and swimming is not a flight. Coming down into the water
-- straight from the air (no ground between) is a leap: where he took off and where he went in (h.leap).
-- An air segment (h.aseg) is every time in the air between two crumbs: the takeoff (the crumb before gets .takeoff),
-- the top, how long, the jump count, every locomotion state seen (the glider has its own), a second push up mid-air
-- (a double jump), and the landing (the first crumb after gets .landing; into the water: .water). Logged as "air".''')
trailing('pcall(function()#1@drive_track_player', '-- the player\'s ground data whenever it changes (log)')
trailing('elseif h.air then', '-- landed: a long flight (not a glide that came down close) breaks the trail at the next crumb')
above('local pm = { st = -1, jc = -1, jt = -1, vx = 0, vy = 0, vz = 0, yaw = 0 }', '''
-- his meta data: locomotion state (0 on the ground, 2 in the air, 4 the glider, 9/10 swimming), jump count and type,
-- speed and up/down speed, facing''')
trailing('if not sg.states[pm.st] then', '-- each new locomotion state in the air (log)')
trailing('if t > sg.t0 + 5 and pm.vy > sg.minvy + 3 then sg.double = true end', '-- a second push up: a double jump')

# drive_put_away ------------------------------------------------------------------------------------------------------
above('local function drive_put_away(s)', '''
-- Put away (h.go_away; F.tick removes the body and brings him back beside the player once he stands on the ground):
-- a glide still going after GLIDE_WAIT or GLIDE_FAR away, a fast travel (FAR_JUMP in one tick), or TP_AFTER of not
-- being able to follow (stuck, waiting at a drop, or stuck in or on the way to the water).''')

# drive_lay_crumb -----------------------------------------------------------------------------------------------------
above('local function drive_lay_crumb(s)', '''
-- the breadcrumb trail: a crumb every DRIVE_STEP the player moves on the ground, with his meta data (crumb.m) and the
-- air segment that landed there; a drop or a long flight before it marks a break (brk). At most 800 crumbs.''')

# drive_upkeep --------------------------------------------------------------------------------------------------------
above('local function drive_upkeep(s)', '''
-- every tick: his route planner off (it still runs with the AI off and writes "don't move" into his input), and the
-- slide recorder (his locomotion state and the game's slide flags, into the log when they change)''')

# drive_jump_follow ---------------------------------------------------------------------------------------------------
above('local function drive_jump_follow(s)', '''
-- Jump follow (returns true while a launch flies, he settles, or a new launch starts). Where the player jumped up
-- (double jump: jump count 2+ or a second push mid-air; or any jump when the hound has made no progress there for
-- DJ_WAIT) to a landing DJ_RISE or more higher, the hound launches from that takeoff crumb toward the landing. Also,
-- with no progress for DJ_WAIT toward a crumb DJ_RISE or more up and within DJ_REACH, he jumps up to it. The native
-- edge stop and step jump are off for the flight. Logs "double jump".''')
above('if not h.djump.air and t <= h.djump.t0 + DJ_LIFT then', '''
-- until the game counts him in the air (up to DJ_LIFT ticks) the launch speed is written again''')
above('if h.djump.air and not h.djump.over then', '''
-- in the air the speed across is written every tick toward the landing spot (up/down left to gravity)''')
above('if not h.djump.over and (nx - h.djump.x1) ^ 2 + (nz - h.djump.z1) ^ 2 < 0.6 ^ 2 then', '''
-- over the landing spot (within 0.6 m): no more speed across, he drops onto it''')
trailing('if h.djump.air and ny >= h.djump.y1 - 0.5 then h.djsettle = t + DJ_SETTLE end', '-- landed up top: he settles')
above('if h.djsettle then', '''
-- the settle: he stands still, step jump and edge stop off, so he neither hops nor slides off''')
above('local blocked_here = h.prog and t - h.prog.t > DJ_WAIT', '''
-- the player's jumps up, at the takeoff crumbs among the next 8''')
above('if not pwet and not h.djump and h.prog and t - h.prog.t > DJ_WAIT and h.prog.c then', '''
-- no progress toward a crumb up a ledge (the player got up without a jump the log saw): he jumps up to it''')

# drive_lure / drive_hold ---------------------------------------------------------------------------------------------
above('local function drive_lure(s)', '''
-- a lure (console "lure", for tests of the edge stop): one point he walks to for a while instead of the trail, facing
-- it; only the native edge stop keeps him from walking off a cliff. The trail stays.''')
above('local function drive_hold(s)', '''
-- a hold (console "hold", for tests): he stands where he is and faces the target''')

# drive_pick_target ---------------------------------------------------------------------------------------------------
above('local function drive_pick_target(s)', '''
-- His target (s.c, the crumb he heads for; nil = the player). Crumbs behind him and the ones he reached are dropped (the
-- last one before a break stays: he waits there, h.waiting). Within DRIVE_STOP of the player there is no target.
-- At the water: when the player swims and the hound stands at the water's level (at most WATER_NEAR above the surface
-- the player's depth gives, not more than 1 m below it), or after a leap, and the trail ahead is short (its last crumb
-- within 3 m, or none), he heads straight for the swimming player (h.to_swimmer) and stays on that while the player is
-- in the water; a stuck there is over. On that way his progress along the line to the player counts; none for
-- STUCK_TICKS: the "can't follow" notice.''')
trailing('log(string.format("drive %s: switch: player wet %s (depth %.2f), surface %s, his height %.2f, near water %s, leap %s, player %.1f m, trail %d crumbs, last crumb %s m, tick %d",', '-- every value the switch looked at')

# drive_stuck ---------------------------------------------------------------------------------------------------------
above('local function drive_stuck(s)', '''
-- Stuck and waiting (returns true while he stands). Stuck: he heads for a crumb but has not come 0.3 m closer to it for
-- STUCK_TICKS; he stops, the notice says why (STUCK_TEXT: down, up, a drop the player took within 3 m ahead, or
-- blocked), with how far the player is, once a second. He goes on when the player has moved STUCK_MOVED since he gave
-- up and is back within DROP_RESUME on his level (a fresh trail from where HE stands), or with Call.
-- Waiting at a drop: he stands at the last safe crumb with its own notice; the same way on.''')
trailing('h.stuck_px, h.stuck_pz = px, pz', '-- where the player was when he gave up')

# drive_steer ---------------------------------------------------------------------------------------------------------
above('local function drive_steer(s)', '''
-- The native hook's inputs: the target (the crumb, or the player) and the player's spot. The edge stop's permission
-- (isTargetInsideLeash): it lets him drop more than 2.5 m only where the player went down himself (a crumb within 12 m
-- ahead, before any break, 0.8 to 7.5 m below him) or the way to the swimming player. The floor proof: an unbroken level
-- trail ahead (each crumb within FLOOR_LINK of the one before, none more than 0.8 m above or below him) out to
-- FLOOR_REACH proves a floor the edge ray cannot see (a closed trap door); a jump leaves a gap, so a hole the player
-- jumped over still stops him. While he moves his body faces the target.''')

# drive_step ----------------------------------------------------------------------------------------------------------
above('local function drive_step(world, id, h)', '''
-- one tick of the drive for one companion (F.tick calls it for every entry in drives)''')

# apply ---------------------------------------------------------------------------------------------------------------
count = {}
fcount = {}
used = set()
out = []
fn = None
for idx, ln in enumerate(src, start=1):
    if A <= idx <= B:
        key = ln.strip()
        m = re.match(r'local function (\w+)', ln)
        if m: fn = m.group(1)
        count[key] = count.get(key, 0) + 1
        fk = (fn, key)
        fcount[fk] = fcount.get(fk, 0) + 1
        k = None
        if '%s#%d@%s' % (key, fcount[fk], fn) in C: k = '%s#%d@%s' % (key, fcount[fk], fn)
        elif key in C and count[key] == 1: k = key
        if k:
            used.add(k)
            ab, tr = C[k]
            ind = re.match(r'[ \t]*', ln).group(0)
            for cl in ab: out.append(ind + cl if cl else '')
            if tr: ln = ln + '  ' + tr
    out.append(ln)
missing = [k for k in C if k not in used]
assert not missing, missing
# anchors used without #n must be unique in the region
for k in used:
    if '@' not in k:
        assert count[k.strip()] == 1, ('not unique', k)
open(sys.argv[4], 'w', encoding='utf-8').write('\n'.join(out))
print('comments placed:', len(used))
