-- core/dive.lua (0.15.218): Fast Dive. Used by features/experimental.lua (the "Fast Dive" option); kept apart because
-- experimental.lua is at Lua's limit of 200 top-level locals. Server world only.
--
-- Owner, 2026-11-16: in the air (falling, after a jump or a Super B Jump, or gliding), a quick double tap of forward
-- (W, or the stick pushed forward twice) sends the player straight down, much faster than gravity; out of the glider
-- if gliding; no fall damage; on landing the game's Explosion_Player_Skill_Shockwave (its sound and effect).
-- The tap uses the player's Super B Jump tap speed (the same window, steps of 1/60 s).
-- The push: one Impulse slot pointing down, kept alive while Jumping (1) or Falling (32) (keen::actor::StateFlag), so it
-- ends at the landing. Pushes up still running (a leap) are ended first, so the dive goes straight down.
-- FIRST VERSION, tuned in game with flamekit.fastdive: what the game's MovementCollider.results.groundDistance reads
-- high up (for the minimum height), whether writing the locomotion state takes the player out of the glider, and
-- whether the shockwave hurts anyone near (the diver is shielded by a hit rule for LANDING_SHIELD seconds).

local fall_guard = require("core.fall_guard")

local M = {
  WINDOW = 11,           -- steps: the default tap speed (the player's own comes in opts.window)
  STICK = 0.5,           -- forward on the stick at least this far counts as a press of W
  SPEED = 80,            -- the push down (the impulse's y, negative); the game's own top fall speed is 20 m/s
  SECONDS = 10,          -- each push lasts this long; renewed every RENEW steps until the landing (0.15.221)
  RENEW = 300,           -- steps (5 s)
  MIN_HEIGHT = 10,       -- metres above the ground (groundDistance) before a dive is allowed; 0 = anywhere
  KICK_GLIDER = false,   -- a dive from the glider writes the locomotion state to Falling (2): did nothing (0.15.219)
  -- (0.15.223, owner: "the second one was good and the damage on the ground was good too") the game's Meteoric Descent
  -- landing (Explosion_Player_WeaponGem_MeteoricDescent): its boom and a crater. Before: Explosion_Player_Skill_Shockwave
  -- (3b874eb5-...), which made no sound of its own when spawned
  EFFECT = "896758dd-f2d5-4e26-89f0-a4856f489e77",
  -- (0.15.223, owner: "try the head-first dive pose") TEST: while diving out of the glider, "input" adds the game's
  -- HeadDive input (PlayerInputType 33, bit 33 of digitalInput) to what the player's game sent; "flag" sets the
  -- HeadDiving state (keen::actor::StateFlag 33) in Actor.currentState; "off" neither
  POSE = "input",
  LANDING_SHIELD = 1.5,  -- seconds the diver takes no hits after the landing (their own shockwave)
  -- keepAliveMask: (0.15.220) the game ended a push naming Jumping, Falling and HangGliding at once within 1/4 s
  -- (0.15.219 test): the player must be in every state named. So only the state the player is in: Falling (32), or
  -- HangGliding (37) when the glider stays open
  KEEP_FALLING = 1 << 32,
  KEEP_GLIDING = 1 << 37,
  JUMP_BIT = 137438953472,
  broken = false,
}

local ON_GROUND, IN_AIR, GLIDING = 0, 2, 4
local function n(v) return tonumber(tostring(v)) end

-- forward pressed (W / the stick): the input the player's game sends; the host's own player by the key
local function forward_down(world, entity)
  if emf.local_player and emf.local_player() == entity and emf.key_down then
    return emf.key_down("W") == true
  end
  local inp = world:get("PlayerInput", entity)
  return inp ~= nil and (tonumber(inp.fromClient.movementStick.y) or 0) >= M.STICK
end

-- metres to the ground below, as the game's own movement code keeps it (nil when it cannot be read)
function M.ground_distance(world, entity)
  local ok, d = pcall(function()
    local mc = world:get("MovementCollider", entity)
    return mc and mc.results and mc.results.m_value and tonumber(mc.results.m_value.groundDistance)
  end)
  return ok and d or nil
end

local function push_down(world, entity, gliding, renew)
  local imp = world:get("Impulse", entity)
  if not imp then return false end
  local now = world:tick() * 50000000 // 3
  if not renew then
    for k = 1, 4 do  -- end every push still running: straight down, nothing else
      if imp.impulses[k].endTime > now then imp.impulses[k].endTime = now end
    end
  end
  local slot = imp.impulses[1]
  slot.impulse.x, slot.impulse.y, slot.impulse.z = 0, -M.SPEED * (M.speed_factor or 1), 0
  slot.type, slot.startTime, slot.endTime, slot.keepAliveMask = 0, now, now + math.floor(M.SECONDS * 1e9),
    gliding and M.KEEP_GLIDING or M.KEEP_FALLING
  return true
end

local HEAD_DIVE = 1 << 33  -- the same bit number in the input (PlayerInputType HeadDive) and the state (StateFlag HeadDiving)

local function pose(world, entity)
  if M.POSE == "input" then
    local inp = world:get("PlayerInput", entity)
    if inp then inp.fromClient.digitalInput = (math.tointeger(inp.fromClient.digitalInput) or 0) | HEAD_DIVE end
  elseif M.POSE == "flag" then
    local a = world:get("Actor", entity)
    if a then a.currentState = (math.tointeger(a.currentState) or 0) | HEAD_DIVE end
  end
end

local function landing(world, entity)
  local x, y, z = world:position(entity)
  if not x then return end
  if M.LANDING_SHIELD > 0 then
    local ok, rule = pcall(emf.hit_rule, { to = entity, cancel = true })
    if ok and rule then
      M.shields = M.shields or {}
      M.shields[#M.shields + 1] = { rule = rule, until_tick = world:tick() + math.floor(M.LANDING_SHIELD * 60) }
    end
  end
  M.boom(world, x, y, z, M.EFFECT)
end

-- (0.15.221) one of the game's explosion templates at a place: the landing effect, and the console test
function M.boom(world, x, y, z, guid)
  if not guid or guid == "" or guid == "off" then return nil end
  local ok, id = pcall(emf.spawn, world, guid, x, y + 0.2, z)
  emf.log(string.format("fast dive: effect %s at %.1f %.1f %.1f: %s", tostring(guid), x, y, z,
    ok and ("spawned entity " .. tostring(id)) or ("refused: " .. tostring(id))))
  return ok and id or nil
end

-- the shields of earlier landings run out (every step, any player)
function M.tick(world)
  if not M.shields then return end
  local t = world:tick()
  for i = #M.shields, 1, -1 do
    if t >= M.shields[i].until_tick then
      pcall(emf.hit_rule_remove, M.shields[i].rule)
      table.remove(M.shields, i)
    end
  end
end

-- Every server step for each player with Fast Dive on. `s` is that player's own table, `opts` = { window = steps }.
-- Returns "dive", "low" (asked for below MIN_HEIGHT), "landed" or nil.
function M.step(world, entity, s, opts)
  if M.broken then return nil end
  local result
  local ok, err = pcall(function()
    local move = world:get("DynamicLocomotion", entity)
    if not move then return end
    local t = world:tick()
    local st = n(move.state)
    local down = forward_down(world, entity)
    local pressed = down and not s.down
    s.down = down
    if st == ON_GROUND then
      if s.diving then
        s.diving = nil
        landing(world, entity)
        result = "landed"
      end
      s.first = nil
      return
    end
    if st ~= IN_AIR and st ~= GLIDING then s.first = nil return end
    if s.diving then
      fall_guard.step(world, entity)
      if st == IN_AIR and M.POSE ~= "off" then pcall(pose, world, entity) end
      -- (0.15.219, test) what the dive does: every 15 steps for 3 s, the height, state and the push
      if s.diag and t <= s.diag and (t - s.dive_t) % 15 == 0 then
        local _, y = world:position(entity)
        local imp = world:get("Impulse", entity)
        local sl = imp and imp.impulses[1]
        local now = t * 50000000 // 3
        local a = world:get("Actor", entity)
        local cs = a and math.tointeger(a.currentState) or 0
        emf.log(string.format("fast dive test: +%d steps y %.1f state %s push y %s alive %s; pose %s, HeadDiving %s, Falling %s",
          t - s.dive_t, y or -1, tostring(st), sl and string.format("%.1f", sl.impulse.y) or "?",
          sl and tostring(sl.endTime > now) or "?", M.POSE, tostring(cs & HEAD_DIVE ~= 0), tostring(cs & (1 << 32) ~= 0)))
      end
      -- (0.15.221, owner: the dive slowed down before the ground: its 10 s push ran out about 1000 m down) the push is
      -- renewed every RENEW steps until the landing; its kind follows the glider (open or closed)
      if (t - s.dive_t) % M.RENEW == 0 then push_down(world, entity, st == GLIDING, true) end
      return
    end
    if not pressed then return end
    local window = (opts and opts.window) or M.WINDOW
    if not (s.first and t - s.first >= 2 and t - s.first <= window) then
      s.first = t
      return
    end
    s.first = nil
    local gd = M.ground_distance(world, entity)
    s.ground = gd
    if M.MIN_HEIGHT > 0 and gd and gd > 0 and gd < M.MIN_HEIGHT then
      result = "low"
      return
    end
    -- (0.15.220) writing the state did not close the glider (0.15.219 test: state 4 stayed); kept off by default
    if st == GLIDING and M.KICK_GLIDER then move.state = IN_AIR end
    if push_down(world, entity, st == GLIDING and not M.KICK_GLIDER) then
      s.diving, s.from_glider, s.dive_t, s.diag = true, st == GLIDING, t, t + 180
      local _, y = world:position(entity)
      s.dive_y = y
      result = "dive"
    end
  end)
  if not ok then
    M.broken = true
    emf.log("fast dive: does not work on this game version (" .. tostring(err) .. ")")
  end
  return result
end

return M
