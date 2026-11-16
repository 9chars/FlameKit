-- core/dive.lua (0.15.218..0.15.226): Fast Dive. Used by features/experimental.lua (the "Fast Dive" option); kept
-- apart because experimental.lua is at Lua's limit of 200 top-level locals. Server world only.
--
-- Owner, 2026-11-16: in the air (falling, after a jump or a Super B Jump, or gliding), a quick double tap of forward
-- (W, or the stick pushed forward twice) sends the player straight down, much faster than gravity; no fall damage; on
-- landing a blast from the game's own explosions (a boom and a crater). The tap uses the player's tap speed (the same
-- setting as Super B Jump, steps of 1/60 s). Each player's own speed, landing blast and minimum height (opts).
--
-- Found in the 0.15.218..0.15.225 tests (local server, owner):
-- - The push: one Impulse slot pointing down. Its keepAliveMask must name only states the player is in (the game
--   ended a push naming Jumping, Falling and HangGliding at once within 1/4 s): Falling (32), or HangGliding (37) when
--   gliding. One push for SECONDS, ending at the landing; renewing it every 5 s restarted its speed curve ("janky").
--   80 down: about 60 m/s (the game's own top fall speed is 20 m/s).
-- - From the glider the dive keeps the glider open: a nose dive (owner: "looks pretty good"). Writing the movement
--   state to Falling does not close the glider. Out of the glider the pose stays the game's fall: the pose is chosen
--   in the player's own game; the HeadDive input and the HeadDiving state set from the server did not change it, and
--   the state left the player rolling on the ground (owner: "drop worrying about the pose thing").
-- - Landing: Explosion_Player_Tool_TNT_T1 (a boom and a crater, owner: "the crater blast definitely worked");
--   Explosion_Player_WeaponGem_MeteoricDescent: a boom, no crater; Explosion_Player_Skill_Shockwave: nothing heard.
-- - MovementCollider.results.groundDistance reads the distance only near the ground (3.4e38 high up): the minimum
--   height only stops a dive just above the ground.

local fall_guard = require("core.fall_guard")

local M = {
  WINDOW = 11,           -- steps: the default tap speed (the player's own comes in opts.window)
  STICK = 0.5,           -- forward on the stick at least this far counts as a press of W
  SPEED = 80,            -- the push down at 1x (the impulse's y, negative)
  SECONDS = 120,         -- one push; from the 2480 m ceiling down at about 60 m/s is about 40 s; it ends at the landing
  MIN_HEIGHT = 10,       -- metres to the ground at 1x default (opts.min); 0 = anywhere
  LANDING_SHIELD = 1.5,  -- seconds the diver takes no hits after the landing (their own blast)
  -- the landing blasts a player can choose (opts.landing): the game's own explosion templates
  LANDINGS = {
    [0] = { name = "Off" },
    [1] = { name = "Small crater", guid = "3ed869e3-c65b-4751-98da-4ce3c6242bac" },   -- Explosion_Player_Tool_TNT_T1
    [2] = { name = "Medium crater", guid = "93ee028c-2fa7-4d31-bfc6-1e7b5ef4ac70" },  -- Explosion_Player_Tool_TNT_T3
    [3] = { name = "Big crater", guid = "9a216c97-1d52-4163-aee4-cb3eff129a50" },     -- Explosion_Player_Tool_TNT_T4
    [4] = { name = "Boom only (no crater)", guid = "896758dd-f2d5-4e26-89f0-a4856f489e77" },  -- ..._MeteoricDescent
  },
  -- (0.15.227, owner: "would land better if the player hit the ground in a crouched position", TEST) in a free-fall
  -- dive within CROUCH_AT metres of the ground, the server adds the game's Sneak input (PlayerInputType 55) to what the
  -- player's game sent, until the landing. Input only (no saved state): the player's next input message overwrites it.
  -- (0.15.228) the server's copy did nothing (the ground distance is known only about 1 m above the ground, and the pose
  -- is the player's own game's): off. Done in the player's own game instead (M.client_tick).
  CROUCH = false,
  CROUCH_AT = 15,
  SNEAK = 1 << 55,
  -- (0.15.229, TEST) land crouched: at the landing of a free-fall dive the server sets the game's InSneakMode state
  -- (keen::actor::StateFlag 21) once. Input probe (2026-11-16): crouch is a toggle that sets that state, only on the
  -- ground; a jump or another crouch press clears it, so it cannot stay stuck. A state set by the server does reach the
  -- player's animation (0.15.224: HeadDiving made the character roll on the ground).
  LAND_CROUCHED = false,  -- (0.15.230) the server's write was gone one step later; done in the player's own game
  SNEAK_STATE = 1 << 21,
  KEEP_FALLING = 1 << 32,
  KEEP_GLIDING = 1 << 37,
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

-- metres to the ground below, as the game's own movement code keeps it (nil when it cannot be read; huge far up)
function M.ground_distance(world, entity)
  local ok, d = pcall(function()
    local mc = world:get("MovementCollider", entity)
    return mc and mc.results and mc.results.m_value and tonumber(mc.results.m_value.groundDistance)
  end)
  return ok and d or nil
end

local function push_down(world, entity, gliding, factor)
  local imp = world:get("Impulse", entity)
  if not imp then return false end
  local now = world:tick() * 50000000 // 3
  for k = 1, 4 do  -- end every push still running (a leap's): straight down, nothing else
    if imp.impulses[k].endTime > now then imp.impulses[k].endTime = now end
  end
  local slot = imp.impulses[1]
  slot.impulse.x, slot.impulse.y, slot.impulse.z = 0, -M.SPEED * factor, 0
  slot.type, slot.startTime, slot.endTime, slot.keepAliveMask = 0, now, now + math.floor(M.SECONDS * 1e9),
    gliding and M.KEEP_GLIDING or M.KEEP_FALLING
  return true
end

-- one of the game's explosion templates at a place: the landing blast, and the console test
function M.boom(world, x, y, z, guid)
  if not guid or guid == "" or guid == "off" then return nil end
  local ok, id = pcall(emf.spawn, world, guid, x, y + 0.2, z)
  if not ok then emf.log("fast dive: the landing blast cannot be spawned (" .. tostring(id) .. ")") end
  return ok and id or nil
end

local function landing(world, entity, kind)
  local x, y, z = world:position(entity)
  if not x then return end
  local l = M.LANDINGS[kind or 1]
  if not (l and l.guid) then return end
  if M.LANDING_SHIELD > 0 then
    local ok, rule = pcall(emf.hit_rule, { to = entity, cancel = true })
    if ok and rule then
      M.shields = M.shields or {}
      M.shields[#M.shields + 1] = { rule = rule, until_tick = world:tick() + math.floor(M.LANDING_SHIELD * 60) }
    end
  end
  M.boom(world, x, y, z, l.guid)
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

-- Every server step for each player with Fast Dive on. `s` is that player's own table, `opts` the player's own
-- settings: window (steps), speed (factor), landing (a LANDINGS key), min (metres).
-- Returns "dive", "low" (asked for below the minimum height), "landed" or nil.
function M.step(world, entity, s, opts)
  if M.broken then return nil end
  opts = opts or {}
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
        landing(world, entity, s.landing)
        if M.LAND_CROUCHED and not s.from_glider then
          local a = world:get("Actor", entity)
          if a then a.currentState = (math.tointeger(a.currentState) or 0) | M.SNEAK_STATE end
        end
        result = "landed"
      end
      s.first = nil
      return
    end
    if st ~= IN_AIR and st ~= GLIDING then s.first = nil return end
    if s.diving then
      fall_guard.step(world, entity)
      if M.CROUCH and st == IN_AIR then
        local gd = M.ground_distance(world, entity)
        if gd and gd > 0 and gd < M.CROUCH_AT then
          local inp = world:get("PlayerInput", entity)
          if inp then inp.fromClient.digitalInput = (math.tointeger(inp.fromClient.digitalInput) or 0) | M.SNEAK end
          if not s.crouched then
            s.crouched = true
            emf.log(string.format("fast dive: player %s crouches %.1f m above the ground (test)", tostring(entity), gd))
          end
        end
      end
      return
    end
    if not pressed then return end
    local window = opts.window or M.WINDOW
    if not (s.first and t - s.first >= 2 and t - s.first <= window) then
      s.first = t
      return
    end
    s.first = nil
    local gd = M.ground_distance(world, entity)
    s.ground = gd
    local min = opts.min or M.MIN_HEIGHT
    if min > 0 and gd and gd > 0 and gd < min then
      result = "low"
      return
    end
    if push_down(world, entity, st == GLIDING, opts.speed or 1) then
      s.diving, s.from_glider, s.landing, s.crouched = true, st == GLIDING, opts.landing or 1, nil
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

-- ---- the player's own game (0.15.228..0.15.230, owner: "the pose action would be great when falling, but the crouching
-- would be good when the player hits the ground") ----
-- Found: pressing buttons for the player does nothing (0.15.228: HeadDive and Sneak written into the game's own
-- ClientPlayerInput; 0.15.227: the server's copy). Sneak is bit 55 and a toggle that only works on the ground; it
-- turns on the actor state InSneakMode (21), which stays until the next crouch press or a jump (input probe). Set by
-- the server, that state was gone one step later (0.15.229): the player's own game keeps its movement states. So
-- (0.15.230, TEST) the player's own game sets them in its own world: HeadDiving (33) while a free-fall dive falls,
-- cleared at the landing (from the server, HeadDiving left the player rolling on the ground: 0.15.224), and
-- InSneakMode (21) once at the landing. The server says when a free-fall dive starts and when it lands (channel
-- flamekit/exp, op "dive").
M.HEAD_STATE = 1 << 33
local me = { on = false, head = false, crouch = false, said = {} }

local function say_once(what, text)
  if me.said[what] then return end
  me.said[what] = true
  emf.log("fast dive (game): " .. text)
end

function M.client_msg(msg)
  if type(msg) ~= "table" then return end
  if msg.on == true and msg.free == true then
    me.on, me.crouch = true, false
    say_once("on", "a free-fall dive started: HeadDiving state while falling")
  elseif msg.on == false and me.on then
    me.on, me.crouch = false, true
    say_once("off", "the dive landed: InSneakMode state")
  end
end

function M.client_tick(world)
  if not (me.on or me.head or me.crouch) then return end
  local id = emf.local_player and emf.local_player()
  if not id or id == 0 then return end
  local ok, err = pcall(function()
    local a = world:get("Actor", id)
    if not a then return end
    local cs = math.tointeger(a.currentState) or 0
    local move = world:get("DynamicLocomotion", id)
    local st = move and n(move.state)
    if me.on and st == ON_GROUND then me.on, me.crouch = false, true end  -- landed before the server's word came
    if me.on and st == IN_AIR then
      a.currentState = cs | M.HEAD_STATE
      me.head = true
      return
    end
    if me.head then  -- never left on: off at once when the dive is over (landed, or the glider opened)
      cs = cs & ~M.HEAD_STATE
      a.currentState = cs
      me.head = false
    end
    if me.crouch and st == ON_GROUND then
      a.currentState = cs | M.SNEAK_STATE
      me.crouch = false
    end
  end)
  if not ok then
    me.on, me.head, me.crouch = false, false, false
    say_once("err", "the game's states cannot be written here (" .. tostring(err) .. ")")
  end
end

return M
