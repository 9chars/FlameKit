-- core/dive.lua (0.15.218..0.15.231): Fast Dive. Used by features/experimental.lua (the "Fast Dive" option); kept
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
--   state to Falling does not close the glider. Out of the glider the pose stays the game's fall, and the landing is
--   the game's own: a head-first pose and a crouched landing were tried every way FlameKit's Lua can (0.15.223..
--   0.15.230) and dropped (owner, 2026-11-16 13:59). See flamekit_native/notes/MOVEMENT.md before trying again.
-- - Landing: Explosion_Player_Tool_TNT_T1 (a boom and a crater, owner: "the crater blast definitely worked");
--   Explosion_Player_WeaponGem_MeteoricDescent: a boom, no crater; Explosion_Player_Skill_Shockwave: nothing heard.
-- - MovementCollider.results.groundDistance reads the distance only near the ground (3.4e38 high up): the minimum
--   height only stops a dive just above the ground.

local fall_guard = require("core.fall_guard")
local bases = require("core.bases")

local M = {
  WINDOW = 11,           -- steps: the default tap speed (the player's own comes in opts.window)
  STICK = 0.5,           -- forward on the stick at least this far counts as a press of W
  SPEED = 80,            -- the push down at 1x (the impulse's y, negative)
  SECONDS = 120,         -- one push; from the 2480 m ceiling down at about 60 m/s is about 40 s; it ends at the landing
  CRATER_GUARD = 5,      -- (0.15.266) seconds after a glider dive's landing without fall damage (the drop into the crater)
  MIN_HEIGHT = 0,        -- (0.15.263: 10 m above where the player last stood; 0.15.264, owner: "there should just be no minimum for the glider") 0 = the glider dive and its tip at any height
  LANDING_SHIELD = 1.5,
  DEFAULT_LANDING = 1,  -- (0.15.260, owner: "lets make Fast Dive landing set to Small crater")
  RISING = 2,            -- m/s upward (Velocity.y) during a dive: the player pulls up (0.15.247)
  AUTO_ABOVE = 1000,     -- (0.15.248) the game's altitude (metres above sea level): a free fall above it dives by itself (opts.auto; 0 = never)
  AUTO_FALL = 20,        -- metres fallen from the highest point first (not after closing the glider)   -- (0.15.240, owner: "default it to big crater")  -- seconds the diver takes no hits after the landing (their own blast)
  -- the landing blasts a player can choose (opts.landing): the game's own explosion templates
  LANDINGS = {
    [0] = { name = "Off" },
    [1] = { name = "Small crater", guid = "3ed869e3-c65b-4751-98da-4ce3c6242bac" },   -- Explosion_Player_Tool_TNT_T1
    [2] = { name = "Medium crater", guid = "93ee028c-2fa7-4d31-bfc6-1e7b5ef4ac70" },  -- Explosion_Player_Tool_TNT_T3
    [3] = { name = "Big crater", guid = "9a216c97-1d52-4163-aee4-cb3eff129a50", down = 1 },  -- ..._TNT_T4 (0.15.240: 1 m down)
    [4] = { name = "Boom only (no crater)", guid = "896758dd-f2d5-4e26-89f0-a4856f489e77" },  -- ..._MeteoricDescent
    -- (0.15.237, owner: "that one was good ... call it huge crater") the big TNT in the middle and 4 more 1.5 m around
    -- it (a ScaleComponent does not make a blast bigger: 1x, 3x and 6x looked the same, 0.15.235 test; the game's boss
    -- blasts did nothing when spawned alone, 0.15.236 test)
    -- (0.15.239, owner, ring tests 14:46-15:00) going off below the ground digs a deeper, rounder crater: Huge 2 m down;
    -- Massive ("Massive crater is good"): 21 big TNTs, 8 at 1.5 m and 12 at 4 m (turned half a step), 3 m down
    [5] = { name = "Huge crater", guid = "9a216c97-1d52-4163-aee4-cb3eff129a50", rings = { { 4, 1.5 } }, down = 2 },
    [6] = { name = "Massive crater", guid = "9a216c97-1d52-4163-aee4-cb3eff129a50",
            rings = { { 8, 1.5 }, { 12, 4, math.pi / 12 } }, down = 3 },
    -- (0.15.246, owner: "thats good lmao, put it into the game") the same rings plus two more (16 at 6.5 m, 20 at 9 m),
    -- in 4 layers 3 m apart from 12 m down up to 3 m down: 228 big TNTs. Layers closer than one blast's reach (about
    -- 3 m) join into one solid pit (owner: not "lumpy"); each layer below adds about 3 m of depth
    [7] = { name = "Gigantic crater", guid = "9a216c97-1d52-4163-aee4-cb3eff129a50",
            rings = { { 8, 1.5 }, { 12, 4, math.pi / 12 }, { 16, 6.5 }, { 20, 9, math.pi / 20 } },
            down = 12, layers = 4, layer_step = 3 },
  },
  -- (0.15.232, owner: "an option not to blow up stuff inside someones base", per player) a landing inside a base (the
  -- game's InSaveZone actor state, keen::actor::StateFlag 14: a flame altar's area) uses BOOM_ONLY unless the player
  -- chose craters there too (opts.base == 1)
  SAVE_ZONE = 1 << 14,
  BOOM_ONLY = 4,
  -- (0.15.233, owner: a crater just outside a base still damaged it near the border) also boom only within this many
  -- metres around a base's build zone (core/bases.lua), by the size of the blast; tuned with flamekit.fastdive margin
  -- (0.15.242, owner: "too aggressive ... pull it in by 20 m") was 10, 15, 25, 30, 40; never below 0 (the base itself)
  MARGIN = { [1] = 2, [2] = 2, [3] = 5, [5] = 10, [6] = 20, [7] = 30 },  -- (0.15.244, owner: small and medium 2 m; 1 m in 0.15.243)
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

-- (0.15.262) how high the player is above the last place they stood or swam (s.ground_y), or nil when not known
function M.above_ground(s, y)
  return y and s.ground_y and y - s.ground_y or nil
end

-- (0.15.267, owner: "the S key doesn't barely put enough pull back to stop the dive... the dive never slows down when
-- I pull back") a cancelled dive also ends its push (slot 1, when it is still the dive's own), so the player is not
-- pulled down at dive speed any more: before, only the blast and the notice were cancelled
local function end_push(world, entity, factor)
  pcall(function()
    local imp = world:get("Impulse", entity)
    local slot = imp and imp.impulses[1]
    local now = world:tick() * 50000000 // 3
    if slot and slot.endTime > now and math.abs((tonumber(slot.impulse.y) or 0) + M.SPEED * (factor or 1)) < 0.01 then
      slot.endTime = now
    end
  end)
end

local function push_down(world, entity, gliding, factor, keep_others)
  local imp = world:get("Impulse", entity)
  if not imp then return false end
  local now = world:tick() * 50000000 // 3
  if not keep_others then
    for k = 1, 4 do  -- end every push still running (a leap's): straight down, nothing else
      if imp.impulses[k].endTime > now then imp.impulses[k].endTime = now end
    end
  end
  local slot = imp.impulses[1]
  slot.impulse.x, slot.impulse.y, slot.impulse.z = 0, -M.SPEED * factor, 0
  slot.type, slot.startTime, slot.endTime, slot.keepAliveMask = 0, now, now + math.floor(M.SECONDS * 1e9),
    gliding and M.KEEP_GLIDING or M.KEEP_FALLING
  return true
end

-- one of the game's explosion templates at a place: the landing blast, and the console test
-- `scale` (0.15.235, owner: "is there any way to make the blast even bigger", TEST): the game's ScaleComponent
-- (uniformScale), as FlameKit's test monsters are spawned with; whether it makes a blast bigger is what the test shows
-- (0.15.273, test; owner: the blast does not hurt monsters, 0.15.272 measured no health change at all) the explosion is
-- spawned with the player faction (M.BLAST_FACTION), so the game's enemy check lets its damage through to monsters as it
-- does for a player's own TNT; when the game refuses the component it is spawned as before. The first few spawns log
-- the explosion's Faction and OwnerRelationship as the game has them.
M.BLAST_FACTION = 7
M.boom_said = 0
function M.boom(world, x, y, z, guid, scale)
  if not guid or guid == "" or guid == "off" then return nil end
  local comps = {}
  if scale and scale ~= 1 then comps.ScaleComponent = { uniformScale = scale } end
  if M.BLAST_FACTION then comps.Faction = { faction = M.BLAST_FACTION } end
  local ok, id = pcall(emf.spawn, world, guid, x, y + 0.2, z, next(comps) and comps or nil)
  if not ok and comps.Faction then
    emf.log("fast dive: the blast cannot have a faction (" .. tostring(id) .. "): spawned without")
    comps.Faction = nil
    ok, id = pcall(emf.spawn, world, guid, x, y + 0.2, z, next(comps) and comps or nil)
  end
  if not ok then emf.log("fast dive: the landing blast cannot be spawned (" .. tostring(id) .. ")") end
  if ok and id and M.boom_said < 3 then
    M.boom_said = M.boom_said + 1
    pcall(function()
      local okf, f = pcall(world.get, world, "Faction", id)
      local oko, o = pcall(world.get, world, "OwnerRelationship", id)
      local owner = "none"
      if oko and o then
        local oke, txt = pcall(emf.json.encode, o)
        owner = oke and txt or tostring(o)
      end
      emf.log(string.format("fast dive: blast entity %s: faction %s, owner %s", tostring(id),
        okf and f and tostring(f.faction) or "none", owner))
    end)
  end
  return ok and id or nil
end

-- true when the player stands inside a base (a flame altar's area), nil when it cannot be read
function M.in_base(world, entity)
  local ok, inside = pcall(function()
    local a = world:get("Actor", entity)
    return a ~= nil and (math.tointeger(a.currentState) or 0) & M.SAVE_ZONE ~= 0
  end)
  return ok and inside or nil
end

local function landing(world, entity, kind, s)
  local x, y, z = world:position(entity)
  if not x then return end
  s.in_base = M.in_base(world, entity)
  s.near_base = nil
  if not s.in_base and s.base ~= 1 and M.MARGIN[kind or M.DEFAULT_LANDING] then
    s.near_base = bases.near(x, z, M.MARGIN[kind or M.DEFAULT_LANDING])
  end
  if (s.in_base or s.near_base) and (kind or M.DEFAULT_LANDING) ~= 0 and s.base ~= 1 then kind = M.BOOM_ONLY end
  s.landed_with = kind
  local l = M.LANDINGS[kind or M.DEFAULT_LANDING]
  if not (l and l.guid) then return end
  if M.LANDING_SHIELD > 0 then
    local ok, rule = pcall(emf.hit_rule, { to = entity, cancel = true })
    if ok and rule then
      M.shields = M.shields or {}
      M.shields[#M.shields + 1] = { rule = rule, until_tick = world:tick() + math.floor(M.LANDING_SHIELD * 60) }
    end
  end
  for layer = 0, (l.layers or 1) - 1 do
    M.blast(world, x, y - (l.down or 0) + layer * (l.layer_step or 0), z, l.guid, l.rings)
  end
end

-- (0.15.237) one blast in the middle and rings around it: rings = { {count, radius}, ... }; returns how many spawned
function M.blast(world, x, y, z, guid, rings)
  local made = M.boom(world, x, y, z, guid) and 1 or 0
  for _, r in ipairs(rings or {}) do
    for k = 1, r[1] do
      local a = 2 * math.pi * k / r[1] + (r[3] or 0)
      if M.boom(world, x + math.cos(a) * r[2], y, z + math.sin(a) * r[2], guid) then made = made + 1 end
    end
  end
  return made
end

-- the shields of earlier landings run out (every step, any player)
function M.tick(world)
  if world:is_server() then pcall(bases.tick, world) end  -- (0.15.233) the list of bases, made in the background
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
-- settings: window (steps), speed (factor), landing (a LANDINGS key), min (metres), base (1: craters inside bases too).
-- Returns "dive", "low" (asked for below the minimum height), "landed", "cancel" (pulled up) or nil.
function M.step(world, entity, s, opts)
  if M.broken then return nil end
  opts = opts or {}
  local result
  local ok, err = pcall(function()
    local move = world:get("DynamicLocomotion", entity)
    if not move then return end
    local t = world:tick()
    local st = n(move.state)
    s.st = st  -- (0.15.254) for the glider tip (features/experimental.lua)
    local down = forward_down(world, entity)
    local pressed = down and not s.down
    s.down = down
    local _, y = world:position(entity)
    -- (0.15.254, glider tip) the last height the player stood or swam at: the game knows the ground below only about
    -- 1 m before a landing, so the tip counts the height above this
    if y and (st == ON_GROUND or st == 9 or st == 10) then s.ground_y = y end
    -- (0.15.266, owner: "I feel like im getting hurt a lot from the glider"; the log: a glider dive landed unhurt, then
    -- the crater opened under the player and the ~14 m drop into it hit 2515 -> 531) after a glider dive's landing the
    -- fall stays short for CRATER_GUARD seconds, so the drop into the player's own crater does not hurt
    if s.after_guard then
      if t < s.after_guard then fall_guard.step(world, entity) else s.after_guard = nil end
    end
    if st == ON_GROUND then
      if s.diving then
        s.diving = nil
        landing(world, entity, s.landing, s)
        result = "landed"
        if s.from_glider then s.after_guard = t + math.floor(M.CRATER_GUARD * 60) end
      end
      s.first, s.top, s.glider_closed, s.was_gliding = nil, nil, nil, nil
      return
    end
    if st ~= IN_AIR and st ~= GLIDING then
      -- (0.15.252, owner: a dive into water kept the notice up and blew up on the next landing, out of the water)
      -- water (swimming 9, under water 10) ends a dive at once: no blast, the notice goes. Other states (sliding on a
      -- slope) keep it: the landing on the ground comes next.
      if s.diving and (st == 9 or st == 10) then
        s.diving = nil
        result = "cancel"
        end_push(world, entity, s.factor)
        s.cancel_why = "landed in water"
      end
      s.first, s.top = nil, nil
      return
    end
    -- (0.15.248) the highest point of this time in the air, and whether the glider was just closed
    if st == GLIDING then
      if not s.was_gliding and not s.diving then s.glider_opened = true end  -- (0.15.254) the glider tip
      s.was_gliding, s.top = true, nil
    elseif s.was_gliding then
      s.was_gliding, s.glider_closed, s.top = nil, true, y
    end
    if y and (not s.top or y > s.top) then s.top = y end
    if s.diving then
      -- (0.15.249, owner: "the impact should kill you", "let the natural fall kill the player", "let the glider dive
      -- bomb survive") only a dive started in the glider keeps the fall short; a free-fall dive lands as the game's own
      -- fall (No Fall Damage and Invincible Mode still protect: features/experimental.lua)
      if s.from_glider then fall_guard.step(world, entity) end
      -- (0.15.251, fall probe: the game takes a fall's start height once, when the fall begins; a Super B Jump leap is a
      -- fall from the takeoff on, so the start stayed at the ground and a 516 m dive landed as a 3 m fall) a free-fall
      -- dive holds the game's fall start at the highest point of this time in the air, so the game's own fall damage
      -- sees the whole drop. Not for a player whose fall is protected (opts.protected: No Fall Damage, Invincible Mode).
      if not s.from_glider and not opts.protected and s.top then
        local fd = world:get("DynamicFallDamage", entity)
        local start = fd and tonumber(fd.fallStartAltitude)
        if start and start < s.top then fd.fallStartAltitude = s.top end
      end
      -- (0.15.248, owner) an automatic dive (free fall) is cancelled only by opening the glider
      if s.auto and st == GLIDING then
        s.diving = nil
        result = "cancel"
        end_push(world, entity, s.factor)
        s.cancel_why = "the glider was opened"
        return
      end
      -- (0.15.247, owner: pulling up while gliding "drops the fast descent" but the blast still came) the dive watches its
      -- own push: when the glider's updraft burst replaced it, or the player climbs (rising), the dive is cancelled:
      -- no blast, the notice goes, and a new dive can start. Closing the glider during a dive is not a pull-up: the push
      -- is put back with the keep-alive of the new state (its old one ended it).
      local glide_now = st == GLIDING
      if glide_now ~= s.dive_gliding then
        s.dive_gliding = glide_now
        push_down(world, entity, glide_now, s.factor, true)
        return
      end
      local imp = world:get("Impulse", entity)
      local slot = imp and imp.impulses[1]
      local now = t * 50000000 // 3
      local mine = slot and slot.endTime > now and math.abs((tonumber(slot.impulse.y) or 0) + M.SPEED * s.factor) < 0.01
      local v = world:get("Velocity", entity)
      local rising = v and (tonumber(v.velocity.y) or 0) > M.RISING
      if not mine or rising then
        s.diving = nil
        result = "cancel"
        end_push(world, entity, s.factor)
        s.cancel_why = not mine and "its push was replaced (the updraft burst)" or "the player rose (climbing)"
      end
      return
    end
    local start, auto = false, false
    if st == GLIDING then
      -- (0.15.248, owner: "the W double tap would really only work while you're gliding") the nose dive
      if not pressed then return end
      local window = opts.window or M.WINDOW
      if not (s.first and t - s.first >= 2 and t - s.first <= window) then
        s.first = t
        return
      end
      s.first = nil
      -- (0.15.263, owner, after 0.15.262 tied it to the free-fall height: back to "at any height") only not within
      -- MIN_HEIGHT m above where the player last stood (M.above_ground; the game's ground distance is known only ~1 m
      -- before a landing, so the old minimum height setting hardly ever worked and is gone)
      local above = M.above_ground(s, y)
      s.ground = above
      if M.MIN_HEIGHT > 0 and above and above < M.MIN_HEIGHT then
        result = "low"
        return
      end
      start = true
    else
      -- (0.15.248, owner: "if you're free falling above a certain height you're going to leave a crater") automatic:
      -- falling above the player's height (the game's altitude, metres above sea level), after a fall of AUTO_FALL m
      -- from the highest point (so jumps and small drops on high ground never start one), or at once when the glider
      -- was just closed (owner: "if you close the glider and you start falling, it should be enough")
      -- (0.15.262 counted it above where the player last stood: a 1000 m tower then needed another 1000 m; 0.15.263,
      -- owner: back to the game's altitude, explained better in the setting's name and tooltip. The ground far below
      -- cannot be measured: the game knows it only ~1 m before a landing, and its ground search looks ~10 m around.)
      local above = opts.auto or M.AUTO_ABOVE
      if not (above and above > 0 and y and y > above) then return end
      local v = world:get("Velocity", entity)
      local falling = v and (tonumber(v.velocity.y) or 0) < -1
      if not falling then return end
      if not (s.glider_closed or (s.top and s.top - y >= M.AUTO_FALL)) then return end
      start, auto = true, true
    end
    if start and push_down(world, entity, st == GLIDING, opts.speed or 1) then
      s.diving, s.from_glider, s.landing, s.base = true, st == GLIDING, opts.landing or M.DEFAULT_LANDING, opts.base or 0
      s.factor, s.dive_gliding, s.cancel_why, s.auto, s.glider_closed = opts.speed or 1, st == GLIDING, nil, auto, nil
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
