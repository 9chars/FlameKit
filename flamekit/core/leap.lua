-- core/leap.lua (0.15.209): Super B Jump, the leap (owner: named after SuperB, the player who asked for it). Used by
-- features/experimental.lua (the "Super B Jump" option);
-- kept apart because experimental.lua is at Lua's limit of 200 top-level locals. Server world only.
--
-- A quick double tap of jump sends the player straight up, high (about 50 m at 1x height; a double jump is 3.8 m). Measured on the local server (2026-11-16, jump probe):
-- a jump sets DynamicLocomotion.state 2 (in the air; 0 = on the ground) and jumpCount 1, upward 9.58 m/s; the game's own
-- double jump (jumpCount 2) comes only for a second press while the player is no longer rising fast; a second press
-- 6-9 steps (0.1-0.15 s) after the first was ignored by the game in 9 of 9 tries. So a second press within WINDOW steps
-- of the jump, while jumpCount is still 1, is free: FlameKit gives it the leap. A slow double tap stays the game's
-- double jump. One leap per jump; it resets on landing. Only for players with the Double Jump skill (core/skills.lua).
-- The push: one of the player's four Impulse slots (the same kind of push as the glider's updraft burst, which the
-- game moves the player with). While the leap's player is in the air, core/fall_guard.lua keeps the fall short, until
-- they land or open the glider (the glider has no fall damage).

local skills = require("core.skills")
local fall_guard = require("core.fall_guard")

local M = {
  -- steps: the second press must come this soon after the jump. (0.15.216, owner: accidental leaps when jumping) the
  -- owner's quick double taps came 8-9 steps apart (probe, 2026-11-16); the game's own double jump only from 13 steps
  -- on (earlier presses it ignores). 20 took slightly early double jumps as leaps; 11 keeps them apart.
  WINDOW = 11,
  STRENGTH = 60,     -- the push upward (the impulse's y); tuned in game with flamekit.superbjump
  SECONDS = 0.9,     -- how long the push lasts (60 for 0.9 s: about 50 m up; a double jump is 3.8 m)
  -- (owner, 2026-11-16: "a nice arc up and over", only while the player pushes forward, the way the character faces)
  FORWARD = 25,      -- the forward push at full forward input (tuned in game with flamekit.superbjump)
  FORWARD_SECONDS = 3,  -- how long the forward push lasts (it ends at the landing anyway: KEEP)
  -- (owner, 08:52: "too much forward momentum" near the landing) the forward push fades out over its time: ImpulseType
  -- FadeOut (1) instead of S_Curve (0); the push up stays S_Curve
  FORWARD_TYPE = 1,
  STICK_FORWARD = 0.3,  -- the movement stick pushed forward at least this far (keyboard W: 1)
  -- (owner, 2026-11-16: "a little more left and right movement while in the air") while a leap is in the air, the
  -- stick left/right (A/D) pushes sideways: one short push, renewed every SIDE_EVERY steps while held
  SIDE = 1,  -- (owner: 15 and 7 too strong, 4 still; 1 "pretty good", 2026-11-16 08:58)
  SIDE_SECONDS = 0.3,
  SIDE_EVERY = 10,
  STICK_SIDE = 0.3,
  SIDE_SIGN = 1,  -- -1 if right and left come out swapped in the game
  JUMP_BIT = 137438953472,
  -- keepAliveMask: the actor states (keen::actor::StateFlag bits, game's types.json) the push lives in: Jumping (1)
  -- and Falling (32). The glider's burst uses HangGliding (37): with that the game dropped the leap at once (0.15.209 test).
  KEEP = (1 << 1) | (1 << 32),
  -- (owner, 2026-11-16) like the game's double jump, which needs 10 stamina but takes none: a leap needs this much
  STAMINA_NEEDED = 50,
  -- (0.15.215, owner: the full range for everyone, never "you strayed too far") the game sends a player above about
  -- 2560 m back to safety (a 20x leap from 2220 m reached 3295 m and was sent back; 30x from 618 m reached 2233 m, no
  -- warning). A leap is measured at 53.8 m per 1x (10x 535-538 m, 20x 1075-1079 m, 30x 1615 m), so at the leap its
  -- height factor is cut to what reaches CEILING from where the player stands; and in the air its push up ends at once
  -- once the player passes CEILING (lag, a leap from a slope). The same ceiling as the glider's climb (experimental.lua).
  CEILING = 2480,
  PER_X = 53.8,
  broken = false,
}

local IN_AIR, ON_GROUND, GLIDING = 2, 0, 4
-- A number from any game value (the game's 64-bit numbers come as userdata).
local function n(v) return tonumber(tostring(v)) end

-- the jump button: the input the player's game sends (dedicated server and joined players); the host's own player
-- (single player or hosting) by the key
local function jump_down(world, entity)
  if emf.local_player and emf.local_player() == entity and emf.key_down then
    return emf.key_down("Space") == true
  end
  local inp = world:get("PlayerInput", entity)
  return inp ~= nil and (math.tointeger(inp.fromClient.digitalInput) or 0) & M.JUMP_BIT ~= 0
end

-- how far the player pushes forward (0..1): the movement stick's y (keyboard W = 1); the host's own player by the key
local function forward_input(world, entity)
  if emf.local_player and emf.local_player() == entity and emf.key_down then
    return emf.key_down("W") == true and 1 or 0
  end
  local inp = world:get("PlayerInput", entity)
  local y = inp and tonumber(inp.fromClient.movementStick.y) or 0
  return y >= M.STICK_FORWARD and math.min(1, y) or 0
end

-- how far the player pushes sideways (-1 left .. 1 right): the stick's x (keyboard A/D); the host's own player by keys
local function side_input(world, entity)
  if emf.local_player and emf.local_player() == entity and emf.key_down then
    return (emf.key_down("D") == true and 1 or 0) - (emf.key_down("A") == true and 1 or 0)
  end
  local inp = world:get("PlayerInput", entity)
  local x = inp and tonumber(inp.fromClient.movementStick.x) or 0
  if math.abs(x) < M.STICK_SIDE then return 0 end
  return math.max(-1, math.min(1, x))
end

-- the way the character faces, flat (x, z), from its orientation (identity = +z), as the glider's climb does
local function facing(world, entity)
  local q = world:get("CurrentTransform", entity).transform.orientation
  local fx, fz = 2 * (q.x * q.z + q.w * q.y), 1 - 2 * (q.x * q.x + q.y * q.y)
  local len = math.sqrt(fx * fx + fz * fz)
  if len < 0.01 then return nil end
  return fx / len, fz / len
end

-- A free slot (1-4) of the Impulse component at time `now`, not `used`; slot 4 (or 3) when none is free.
local function free_slot(imp, now, used)
  for k = 1, 4 do
    if k ~= used and imp.impulses[k].endTime <= now then return k end
  end
  return used == 4 and 3 or 4
end

-- Fills an Impulse slot: push x, y, z from `now` for `seconds`.
local function put(slot, x, y, z, now, seconds, kind)
  slot.impulse.x, slot.impulse.y, slot.impulse.z = x, y, z
  slot.type, slot.startTime, slot.endTime, slot.keepAliveMask = kind or 0, now, now + math.floor(seconds * 1e9), M.KEEP
end

-- the leap: one push up; and, while the player pushes forward, a longer push the way the character faces (the arc).
-- The facing at the leap is kept in `s` (s.fx, s.fz): air steering is sideways to it, so the character turning toward
-- the push does not turn the push with it (owner, 08:52).
local function push(world, entity, s)
  local imp = world:get("Impulse", entity)
  if not imp then return false end
  local now = world:tick() * 50000000 // 3  -- the game's clock in nanoseconds: 60 steps a second
  local up = free_slot(imp, now, nil)
  local o = s.opts or {}
  local want = o.height or 1
  local _, y = world:position(entity)
  local height = want
  if y then height = math.min(want, (M.CEILING - y) / M.PER_X) end
  if height < 0.05 then  -- at the ceiling already: no leap, the normal jump stays
    M.last_cap = { want = want, got = 0, from = y }
    return false
  end
  M.last_cap = height < want and { want = want, got = height, from = y } or nil
  s.up_slot = up
  put(imp.impulses[up], 0, M.STRENGTH * height, 0, now, M.SECONDS)
  s.fx, s.fz = facing(world, entity)
  local f = forward_input(world, entity)
  M.last_forward = 0
  local fw = M.FORWARD * (o.forward or 1)
  if f > 0 and fw > 0 and s.fx then
    local k = free_slot(imp, now, up)
    put(imp.impulses[k], s.fx * fw * f, 0, s.fz * fw * f, now, M.FORWARD_SECONDS, M.FORWARD_TYPE)
    M.last_forward = f
  end
  return true
end

-- Every server step for each player with Super B Jump on. `s` is that player's own table (kept by the caller); `opts`
-- the player's own factors from the Experimental tab: height, forward, steer (1 = the tuned values above).
-- Returns "leap" in the step a leap starts (for the log), "tired" when a leap was asked for without enough stamina.
function M.step(world, entity, s, opts)
  s.opts = opts or {}
  if M.broken then return nil end
  local result
  local ok, err = pcall(function()
    local move = world:get("DynamicLocomotion", entity)
    if not move then return end
    local t = world:tick()
    local st, count = n(move.state), n(move.jumpCount)
    local down = jump_down(world, entity)
    local pressed = down and not s.down
    s.down = down
    if s.leapt and s.base then  -- (0.15.212) the highest point of the leap, for the log
      local _, y = world:position(entity)
      if y and y > (s.top or -1e9) then s.top = y end
    end
    if st == ON_GROUND then
      if s.leapt and s.base and s.top then
        s.rise = s.top - s.base
        result = "landed"
      end
      s.jumped_at, s.leapt = nil, nil  -- base and top stay for the log until the next leap
    elseif st == IN_AIR and count == 1 and not s.jumped_at then
      s.jumped_at = t  -- the jump (a fall from a ledge has jumpCount 0: no leap from a fall)
    end
    if pressed and st == IN_AIR and count == 1 and s.jumped_at and not s.leapt
        and t - s.jumped_at >= 2 and t - s.jumped_at <= (s.opts.window or M.WINDOW) then  -- (0.15.217) the player's own
      if skills.has(world, entity, skills.DOUBLE_JUMP) == true then
        local okst, stamina = pcall(emf.attribute, world, entity, "stamina")
        stamina = okst and tonumber(stamina) or nil
        if stamina and stamina < M.STAMINA_NEEDED then
          s.leapt = true  -- one try per jump: no second notice in the same jump
          result = "tired"
        elseif push(world, entity, s) then
          s.leapt = true
          M.last_gap = t - s.jumped_at
          local _, y = world:position(entity)
          s.base, s.top = y, y
          result = "leap"
        end
      end
    end
    -- (0.15.215) the safety net: a rising leap above CEILING loses its push up at once
    if s.leapt and s.up_slot and st == IN_AIR then
      local _, y = world:position(entity)
      if y and y > M.CEILING then
        local imp = world:get("Impulse", entity)
        local slot = imp and imp.impulses[s.up_slot]
        local now = t * 50000000 // 3
        if slot and slot.endTime > now and slot.impulse.y > 0 then
          slot.endTime = now
          result = result or "ceiling"
        end
        s.up_slot = nil
      end
    end
    -- air steering: sideways pushes while the leap is in the air (right = the facing AT THE LEAP turned a quarter
    -- clockwise)
    local side = M.SIDE * (s.opts.steer or 1)
    if s.leapt and s.fx and st == IN_AIR and side > 0 and t >= (s.side_next or 0) then
      local x = side_input(world, entity)
      if x ~= 0 then
        local fx, fz = s.fx, s.fz
        local imp = world:get("Impulse", entity)
        if fx and imp then
          local now = t * 50000000 // 3
          s.side_slot = s.side_slot or free_slot(imp, now, nil)
          put(imp.impulses[s.side_slot], fz * side * x * M.SIDE_SIGN, 0, -fx * side * x * M.SIDE_SIGN, now, M.SIDE_SECONDS)
          s.side_next = t + M.SIDE_EVERY
        end
      end
    end
    if st == ON_GROUND then s.side_slot, s.side_next = nil, nil end
    -- fall protection from the leap until the landing; the glider has none of its own to fear
    -- (0.15.249, owner: a Fast Dive impact kills) not during a deadly Fast Dive (opts.no_guard): the leap's protection
    -- stays for everything else
    if s.leapt and st ~= GLIDING and not s.opts.no_guard then fall_guard.step(world, entity) end
  end)
  if not ok then
    M.broken = true
    emf.log("super b jump: does not work on this game version (" .. tostring(err) .. ")")
  end
  return result
end

return M
