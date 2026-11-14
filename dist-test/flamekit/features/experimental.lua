-- features/experimental: switches that bend the game's rules, each player for themselves. All off until switched on.
--
-- Every player has their own switches, and anyone may change their own. They are kept by the world's host (your own
-- game when you host, or the dedicated server) in experimental.json in the mod's folder there, by account, so they
-- are still set the next time you join.
--
-- How they work: EMF's hit rules, which the server applies before damage lands, one rule per player and switch.
-- Nothing in the game's files changes, and a rule is gone the moment its switch is off, the player leaves, the mod
-- is removed or the game stops.

local F = { id = "experimental", title = "Experimental" }

local kit
local note = nil        -- why a rescue button could not do its work, until the next click
local go_request = nil  -- in a world you host: the place for the server half's next step
local CHANNEL = "exp"
local CLIMB_KEY = "S"      -- keyboard fallback only: the server reads the game's own move and jump input first,
local BURST_KEY = "Space"  -- which is the same for keyboard and controller and follows the game's own bindings
local JUMP_BIT = 137438953472  -- the jump button in the input a player's game sends the server
local STICK_BACK = -0.5    -- the movement stick pulled back this far (keyboard: -1) asks for the climb
local BURST_KEEP = 137438953472  -- what the game writes with its own burst impulses (they end when the glide does)
local CLIMB_SPEED = 12    -- metres a second written upward; with the updraft values below some 6 m/s of real climb
local CLIMB_RAMP = 0.5    -- how much of it is added per server step: full climb after about half a second
local UPDRAFT = 3         -- the game's own updraft strength, set while climbing: without it a glider rises 2.5 m/s at most
local MIN_FORWARD = 10    -- metres a second: the least forward speed kept while climbing
local CEILING = 2480       -- metres: near 2560 the game says "you strayed too far" and sends the player to a flame altar
local HANG_GLIDING = 4    -- the game's LocomotionState for an open glider
local LIFT_STEPS = 180    -- a "held" word from a player's game counts for this many server steps (3 seconds)

-- key, what the tab says, the hit rule (its `to` becomes the player), and its name in the chat line everyone gets when a
-- player switches it on or off (none: nobody is told)
local SWITCHES = {
  { "shroud", "No Shroud Damage", { kinds = "shroud", cancel = true }, "No Shroud Damage" },
  { "fall", "No Fall Damage", { kinds = "fall", cancel = true }, "No Fall Damage" },
  { "immortal", "Invincible Mode", { kinds = "all", cancel = true }, "Invincible Mode" },
  { "stamina", "Unlimited Stamina", nil, "Unlimited Stamina" },  -- no hit rule: topped up every server step
  { "fly", "Enhanced Glider Mode" },  -- on by default; see lift()
  { "pvp", "PvP (free-for-all)", nil, "PvP" },  -- no hit rule of its own: see pvp() (0.15.65)
}

-- Options that last only while the player is here: off again when they leave, or the server or the mod restarts.
local SESSION_ONLY = { pvp = true }

-- The options that are on until a player switches them off (the others are off until switched on).
local DEFAULT_ON = { fly = true }

-- What each option does, shown when the pointer rests on its button.
local TIPS = {
  shroud = "Your shroud timer stays full and the red shroud cannot kill you. Stays on until you switch it off. Everyone on the server is told when you switch it.",
  fall = "Falling never hurts you, from any height. Stays on until you switch it off. Everyone on the server is told when you switch it.",
  immortal = "Nothing can hurt or kill you: enemies, lava, the shroud, falling. Stays on until you switch it off. Everyone on the server is told when you switch it.",
  stamina = "Your stamina never runs out. Stays on until you switch it off. Everyone on the server is told when you switch it.",
  pvp = "Free-for-all PvP: you can hurt other players who have PvP on, and they can hurt you, with your normal weapons "
    .. "and spells (25% of the damage). Players without PvP cannot hurt you and you cannot hurt them. Careful: your hits "
    .. "can also hurt your own summons, pets and villagers while it is on. Off again when you leave the server. Everyone "
    .. "on the server is told when you switch it.",
  fly = "While gliding: hold S (back) to climb, and the updraft burst (Space) can be used again and again. On unless you switch it off.",
}

-- ---- the host's half ----

local saved = nil    -- account -> { shroud = true, ... }: what each player switched on
local online = {}    -- account -> { entity, seen = os.time(), rules = { key -> rule id } }
local refused = {}   -- key -> true once EMF refused its rule (said once in the log)
local GONE_AFTER = 20  -- seconds without a word from a player's game: their rules are taken away

-- Has the player with this account got `key` switched on? (saved: forward, see below)
local is_on

-- Every option is remembered for each player (experimental.json, by account): what was on when they left is on
-- again when they come back.
local function save_all()
  kit.store.save("experimental", saved)
end

local function load_saved()
  if saved then return end
  saved = {}
  for account, set in pairs(kit.store.load("experimental", {})) do
    if type(set) == "table" then saved[account] = set end
  end
end

is_on = function(account, key)
  if SESSION_ONLY[key] then return online[account] ~= nil and online[account][key] == true end
  local value = (saved[account] or {})[key]
  if value == nil then return DEFAULT_ON[key] == true end
  return value == true
end

local function drop_rules(p)
  for key, id in pairs(p.rules) do pcall(emf.hit_rule_remove, id) end
  p.rules = {}
end

-- Makes the rules match the switches of the players who are here. Cheap: called every server step, so a reload puts
-- them straight back.
local function apply()
  local now = os.time()
  for account, p in pairs(online) do
    if now - p.seen > GONE_AFTER then
      drop_rules(p)
      online[account] = nil
    else
      for _, s in ipairs(SWITCHES) do
        local key = s[1]
        local wanted = is_on(account, key)
        if not s[3] then
          -- nothing to set up for this one
        elseif wanted and not p.rules[key] and not refused[key] then
          local rule = { to = p.entity }
          for k, v in pairs(s[3]) do rule[k] = v end
          local ok, id = pcall(emf.hit_rule, rule)
          if ok and id then
            p.rules[key] = id
          else
            refused[key] = true
            emf.log("experimental: the rule for '" .. key .. "' was refused (" .. tostring(id) .. "): that switch does nothing here")
          end
        elseif not wanted and p.rules[key] then
          pcall(emf.hit_rule_remove, p.rules[key])
          p.rules[key] = nil
        end
      end
    end
  end
end

-- A player's game said something (or, in a world you host, you are simply here): they are online as `entity`.
local function seen(account, entity)
  local p = online[account]
  if not p then
    p = { entity = entity, rules = {} }
    online[account] = p
  elseif p.entity ~= entity then  -- the same player in a new body: the rules follow
    drop_rules(p)
    p.entity = entity
  end
  p.seen = os.time()
end

-- What a player's tab shows.
local input_broken = false  -- the game's own input cannot be read: players' games send the S and Space keys instead

local body_of  -- forward: the PvP test bodies, below
local function view(account)
  local v = { op = "state", keys = input_broken or nil, body = body_of and body_of(account) or nil }
  for _, s in ipairs(SWITCHES) do
    v[s[1]] = is_on(account, s[1])
    if refused[s[1]] then v[s[1] .. "_dead"] = true end
  end
  return v
end

local function where(world, id)
  local x, y, z = world:position(id)
  if x then return x, y, z end
  local t = world:get("CurrentTransform", id)
  if t then return t.transform.position.x, t.transform.position.y, t.transform.position.z end
end

-- The rescue button: moves the player to the nearest flame altar, the way a respawn lands there. The game's own
-- fast travel is refused inside the shroud; this is not. Returns nil, or why it could not be done.
local function go_home(world, player)
  local px, py, pz = where(world, player)
  local best, best_d = nil, nil
  for _, id in ipairs(world:entities()) do
    local point = world:get("PlayerSpawnPoint", id)
    if point and point.target == 2 then  -- 2: a base's flame altar (1: the world's own travel points)
      local x, y, z = where(world, id)
      local d = (px and x) and ((x - px) ^ 2 + (z - pz) ^ 2) or 0
      if not best or d < best_d then best, best_d = id, d end
    end
  end
  if not best then return "There is no flame altar in this world to go to." end
  if not emf.teleport(world, player, nil, nil, nil, { spawn_point = best }) then
    return "The game refused the move (see the server's emf_core.log)."
  end
  emf.log(string.format("experimental: player %s sent to the flame altar %s", tostring(player), tostring(best)))
end

-- Moves the player to a place their own game named (the nearest Ancient Spire: only a player's game knows the map
-- markers). They land on the game's own travel pad there when one is within 200 m, else on the ground at the place.
local function go_near(world, player, msg)
  local x, y, z = tonumber(msg.x), tonumber(msg.y), tonumber(msg.z)
  if not (x and y and z) or x ~= x or z ~= z or math.abs(x) > 20000 or math.abs(z) > 20000 or math.abs(y) > 20000 then
    return "That place is not on the map."
  end
  local best, best_d = nil, 200 * 200
  for _, id in ipairs(world:entities()) do
    local point = world:get("PlayerSpawnPoint", id)
    if point and point.target == 1 then
      local sx, sy, sz = where(world, id)
      local d = sx and ((sx - x) ^ 2 + (sz - z) ^ 2)
      if d and d < best_d then best, best_d = id, d end
    end
  end
  local queued
  if best then
    queued = emf.teleport(world, player, nil, nil, nil, { spawn_point = best })
  else
    queued = emf.teleport(world, player, x, y, z, { ground = true })
  end
  if not queued then return "The game refused the move (see the server's emf_core.log)." end
  emf.log(string.format("experimental: player %s sent to %.0f %.0f %.0f (pad %s)", tostring(player), x, y, z, tostring(best)))
end

-- Fast travel to the waypoint on the player's map (0.15.60). Their own game sends the waypoint's place (PlayerWaypoint
-- of their player, in their game's world). The game's ground search lands them on the nearest walkable spot within
-- about 10 m (EMF reference "v20"); where there is none they stand exactly there: in the air they fall, inside the
-- terrain the game sends them to their spawn point. So fall damage is off for that player for 30 s after the move
-- (an EMF hit rule, removed again by F.tick). Every move is logged with the waypoint's height and where they landed.
local fall_guard = {}  -- player entity -> { rule = hit rule id, till = os.time() when it goes }
local function go_waypoint(world, player, msg)
  local x, y, z = tonumber(msg.x), tonumber(msg.y), tonumber(msg.z)
  if not (x and y and z) or x ~= x or z ~= z or x < 0 or z < 0 or x > 10240 or z > 10240 or y < -1000 or y > 5000 then
    return "That waypoint is not on the map."
  end
  local _, py = where(world, player)
  local ty = y ~= 0 and y or (py or 300)  -- a waypoint without a height: start from yours
  local okr, rule = pcall(emf.hit_rule, { kinds = "fall", to = player, cancel = true })
  if okr and rule then
    if fall_guard[player] then pcall(emf.hit_rule_remove, fall_guard[player].rule) end
    fall_guard[player] = { rule = rule, till = os.time() + 30 }
  end
  local queued = emf.teleport(world, player, x, ty, z, { ground = true }, function(moved, mx, my, mz, info)
    emf.log(string.format("experimental: waypoint travel of player %s: %s at %.0f %.0f %.0f (waypoint height %.0f, %s)",
      tostring(player), tostring(info and info.status), mx or -1, my or -1, mz or -1, y,
      info and info.raw_target and "no ground found: stood exactly there" or "on the ground"))
  end)
  if not queued then return "The game refused the move (see the server's emf_core.log)." end
  emf.log(string.format("experimental: player %s sent to the waypoint %.0f %.0f %.0f (asked height %.0f)", tostring(player), x, y, z, ty))
end

-- ---- PvP test bodies (Debug section, 0.15.66) ----
-- To try PvP alone, a player can have one test body spawned 3 m in front of them (EMF companion research,
-- engine_parts/re_companions.md):
--   dummy:   FakePlayer_Vukah_Melee, faction 7 (Player) like a player. With PvP on it is your enemy: it swings at you,
--            but its hits do 0 damage (a player-faction body uses the player damage model and has no gear). Your hits
--            on it show whether a PvP player's weapons land on a faction 7 target at all.
--   duelist: Enemy_Vukah_Melee given faction 1 (HitAll): it fights everyone with full monster damage (about 48 a hit
--            at level 1), with PvP on or off. Owner's rule: it may hit and kill everything but pets and animals, and
--            never damage buildings. So it gets an EMF hit rule against placed objects, and every 3 s a rule against
--            each animal or pet within 40 m (Wildlife, Animal or IsTame component, faction 5 Wildlife, 6 WildBeast,
--            12 FarmAnimal, or 11 PlayerAlly unless it is a villager, with NpcState). Villagers are fair game.
--            Voxel walls and terrain never take hits (EMF), and monsters do not break them.
-- Spawned bodies are not saved with the world. One body per player; a new one replaces the old. It goes when its
-- player clicks Remove or leaves, when it dies, or when the world reloads.
local DUMMY_GUID = "9543cfb0-b4d7-408e-905c-ccb79a15136d"  -- FakePlayer_Vukah_Melee
local DUEL_GUID = "d5d05217-52dc-467a-9192-26b4f661d8d9"   -- Enemy_Vukah_Melee
local DUEL_FACTION = 1                                      -- HitAll
local SHIELD_R, SHIELD_MAX, SHIELD_STEPS = 40, 40, 180
local bodies = {}    -- entity id -> { kind, owner = account, session, rules = { key -> id }, guard = { entity -> rule id } }
local body_steps = 0

local function has(world, comp, id)
  local ok, c = pcall(world.get, world, comp, id)
  return ok and c ~= nil
end

local function protected(world, id)
  if has(world, "Wildlife", id) or has(world, "Animal", id) or has(world, "IsTame", id) then return true end
  local ok, f = pcall(world.get, world, "Faction", id)
  local n = ok and f and tonumber(tostring(f.faction))
  if n == 5 or n == 6 or n == 12 then return true end
  return n == 11 and not has(world, "NpcState", id)
end

local function drop_body(world, id, destroy)
  local b = bodies[id]
  if not b then return end
  for _, r in pairs(b.rules) do pcall(emf.hit_rule_remove, r) end
  for _, r in pairs(b.guard) do pcall(emf.hit_rule_remove, r) end
  bodies[id] = nil
  if destroy then pcall(emf.destroy, world, id) end
end

local function drop_bodies_of(world, account, destroy)
  for id, b in pairs(bodies) do
    if b.owner == account then drop_body(world, id, destroy) end
  end
end

-- The duelist's shield: a hit rule against each animal or pet near it, none for anything farther away.
local function shield(world, id, b)
  local x, _, z = world:position(id)
  if not x then return end
  local keep, n = {}, 0
  for _ in pairs(b.guard) do n = n + 1 end
  for _, e in ipairs(world:entities()) do
    if e ~= id and not bodies[e] then
      local okp, ex, _, ez = pcall(world.position, world, e)
      if okp and ex and (ex - x) ^ 2 + (ez - z) ^ 2 < SHIELD_R * SHIELD_R then
        local oka, account = pcall(world.account, world, e)
        if not (oka and account) and protected(world, e) then
          keep[e] = true
          if not b.guard[e] and n < SHIELD_MAX then
            local ok, r = pcall(emf.hit_rule, { from = id, to = e, cancel = true })
            if ok and r then b.guard[e], n = r, n + 1 end
          end
        end
      end
    end
  end
  for e, r in pairs(b.guard) do
    if not keep[e] then
      pcall(emf.hit_rule_remove, r)
      b.guard[e] = nil
    end
  end
  if n >= SHIELD_MAX and not b.full_said then
    b.full_said = true
    emf.log(string.format("experimental: the duelist %s protects only %d animals and pets near it (more are around)", tostring(id), SHIELD_MAX))
  end
end

-- Returns nil, or why there is no body now.
local function spawn_body(world, account, player, kind)
  drop_bodies_of(world, account, true)
  if kind ~= "dummy" and kind ~= "duel" then return nil end
  local x, y, z = where(world, player)
  if not x then return "Your position is not known." end
  local fx, fz = 0, 1
  pcall(function()
    local q = world:get("CurrentTransform", player).transform.orientation
    local ax, az = 2 * (q.x * q.z + q.w * q.y), 1 - 2 * (q.x * q.x + q.y * q.y)
    local len = math.sqrt(ax * ax + az * az)
    if len > 0.01 then fx, fz = ax / len, az / len end
  end)
  local ok, id = pcall(emf.spawn, world, kind == "duel" and DUEL_GUID or DUMMY_GUID, x + fx * 3, y, z + fz * 3)
  if not ok or not id or id == 0 then return "The game refused the spawn (see the server's emf_core.log)." end
  local b = { kind = kind, owner = account, session = emf.session(), rules = {}, guard = {} }
  bodies[id] = b
  if kind == "duel" then
    pcall(function() world:get("Faction", id).faction = DUEL_FACTION end)  -- at once, before its AI picks a target
    local okr, r = pcall(emf.hit_rule, { from = id, to = "objects", cancel = true })
    if okr and r then b.rules.objects = r else emf.log("experimental: the duelist's rule for buildings was refused (" .. tostring(r) .. ")") end
    shield(world, id, b)
  end
  emf.log(string.format("experimental: a PvP test %s (entity %s) for player %s", kind == "duel" and "duelist" or "dummy", tostring(id), tostring(player)))
end

local function bodies_tick(world)
  if next(bodies) == nil then return end
  body_steps = body_steps + 1
  if body_steps % 30 ~= 0 then return end
  local session = emf.session()
  for id, b in pairs(bodies) do
    local alive = false
    if b.session == session then
      pcall(function()
        local hp = world:get("NetworkHealth", id)
        alive = world:position(id) ~= nil and (hp == nil or hp.health > 0)
      end)
    end
    -- (measured: a duelist spawned right after a long move was "gone" half a second later and lived on, untracked; a
    -- far place may not be streamed in yet.) So a body counts as gone only when it was missing three checks in a row.
    if not alive then b.missing = (b.missing or 0) + 1 else b.missing = 0 end
    if not alive and b.missing >= 3 and b.session == session then
      emf.log(string.format("experimental: the PvP test %s (entity %s) is gone", b.kind, tostring(id)))
      drop_body(world, id, false)
    elseif not alive and b.session ~= session then
      drop_body(world, id, false)
    elseif not alive then
      -- not seen this time: asked again in half a second
    else
      -- what its AI does, logged when it changes (for finding out why a body does not fight)
      pcall(function()
        local ai = world:get("DynamicEnemy01BehaviorState", id)
        local st = world:get("SelectedTargets", id)
        local t = st and st.targets[1].targetEntityId
        if type(t) == "table" then t = t.id end
        local line = string.format("AI state %s, target %s", ai and tostring(ai.state) or "-", tostring(t))
        if line ~= b.last then  -- logged when the state or target changes, with the threat table at that moment
          b.last = line
          local okl, al = pcall(F._aggro_line, world, id)
          emf.log(string.format("experimental: the PvP test %s (entity %s): %s, threat table [%s]", b.kind, tostring(id), line,
            okl and al or ("? " .. tostring(al))))
        end
      end)
    end
    if alive and b.kind == "duel" then
      pcall(function()
        local f = world:get("Faction", id)
        if f and tonumber(tostring(f.faction)) ~= DUEL_FACTION then f.faction = DUEL_FACTION end
      end)
      if body_steps % SHIELD_STEPS == 0 then shield(world, id, b) end
    end
  end
end

-- What the Debug section shows about your body.
body_of = function(account)
  for id, b in pairs(bodies) do
    if b.owner == account then return b.kind end
  end
end

-- A word from a player about their own switches. Returns the view to send back.
local function handle(world, account, entity, msg)
  load_saved()
  account = tostring(account)
  seen(account, entity)
  online[account].kit = true  -- this player's game runs FlameKit: only then is the glider's burst note taken away
  if msg.op == "burst" then
    online[account].burst = true
    return nil
  end
  if msg.op == "lift" then
    online[account].lift = msg.on == true and LIFT_STEPS or 0
    return nil
  end
  if msg.op == "home" or msg.op == "go" or msg.op == "wp" then
    local ok, why
    if msg.op == "home" then ok, why = pcall(go_home, world, entity)
    elseif msg.op == "wp" then ok, why = pcall(go_waypoint, world, entity, msg)
    else ok, why = pcall(go_near, world, entity, msg) end
    local v = view(account)
    v.note = not ok and "The move failed on this game version." or why
    if not ok then emf.log("experimental: go_home failed: " .. tostring(why)) end
    return v
  end
  if msg.op == "body" then
    local ok, why = pcall(spawn_body, world, account, entity, msg.kind)
    if not ok then emf.log("experimental: the PvP test body failed: " .. tostring(why)) end
    local v = view(account)
    v.note = not ok and "That did not work on this game version." or why
    return v
  end
  if msg.op == "set" and type(msg.key) == "string" then
    for _, s in ipairs(SWITCHES) do
      if s[1] == msg.key then
        local set = saved[account] or {}
        if SESSION_ONLY[s[1]] then
          online[account][s[1]] = msg.on == true or nil  -- never saved
        elseif DEFAULT_ON[s[1]] then
          if msg.on == true then set[s[1]] = nil else set[s[1]] = false end  -- only "off" is worth keeping
        else
          set[s[1]] = msg.on == true or nil            -- only "on" is worth keeping
        end
        saved[account] = next(set) and set or nil
        refused[s[1]] = nil
        emf.log(string.format("experimental: player %s switched '%s' %s", tostring(entity), s[1], msg.on == true and "on" or "off"))  -- never the account in a log (a log may be shared)
        if s[4] then  -- everyone on the server is told (not for the glider: it changes nothing for others)
          local okn, name = pcall(world.name, world, entity)
          if not okn or type(name) ~= "string" or name == "" then okn, name = pcall(world.character_name, world, entity) end
          if not okn or type(name) ~= "string" or name == "" then name = "a player" end
          local line = string.format("%s for %s %s.", s[4], name, msg.on == true and "ENABLED" or "DISABLED")
          local sent, why = pcall(emf.broadcast, line, { system = true })
          if not sent or why == false then emf.log("experimental: the chat line was not sent (" .. tostring(why) .. ")") end
        end
        save_all()
      end
    end
    apply()
  end
  return view(account)
end

-- You, in a world you host: your account and body, or nil.
local function me(world)
  local player = emf.local_player()
  if not player or player == 0 then return nil end
  local ok, account = pcall(world.account, world, player)
  if not ok or not account then return nil end
  return tostring(account), player
end

-- The shroud timer is the player's FogResistance attribute: its first value is the seconds left, its fifth the full
-- time. Cancelling the damage is not enough (at 0 the game still shows "The Shroud has consumed you"), so with the
-- switch on the timer is simply kept full. A game update that changes the attribute makes this stop, not crash.
local timer_broken = false

local function keep_timer_full(world)
  if timer_broken then return end
  for account, p in pairs(online) do
    if is_on(account, "shroud") then
      local ok, err = pcall(function()
        local fog = world:get("FogResistance", p.entity)
        if not fog then return end
        local full = fog.dataStorage[5]
        if full > 0 and full <= 100000 and fog.dataStorage[1] < full then fog.dataStorage[1] = full end
      end)
      if not ok then
        timer_broken = true
        emf.log("experimental: the shroud timer cannot be kept full on this game version (" .. tostring(err) .. ")")
      end
    end
  end
end

-- After the mod reloads, the players who are already here are found at once (their bodies have the lowest entity
-- ids), so nobody stands unprotected until their game's next hello.
local looked = false

local function find_players(world)
  looked = true
  for id = 1, 64 do
    local ok, account = pcall(world.account, world, id)
    if ok and account then seen(tostring(account), id) end
  end
end

-- Climbing with the glider: while the player's game says the climb key is held and they are gliding, their upward
-- speed is set every server step. (The game's own updraft values were tried first: they only slow the glider.)
local lift_broken = false
local host_burst_down = false
local burst_broken = false

-- What the player's own game sends as movement and buttons: back on the stick climbs, jump bursts.
local function read_input(world, account, p)
  if input_broken or not is_on(account, "fly") then return end
  local ok, err = pcall(function()
    local inp = world:get("PlayerInput", p.entity)
    if not inp then return end
    local c = inp.fromClient
    if c.movementStick.y <= STICK_BACK then p.lift = 2 end
    local jump = (math.tointeger(c.digitalInput) or 0) & JUMP_BIT ~= 0
    if jump and not p.jump then p.burst = true end
    p.jump = jump
  end)
  if not ok then
    input_broken = true
    emf.log("experimental: the game's input cannot be read on this game version, the glider uses the S and Space keys (" .. tostring(err) .. ")")
  end
end

local function lift(world)
  if lift_broken then return end
  for account, p in pairs(online) do
    read_input(world, account, p)
    -- The updraft burst. The game gives one per flight: it notes the used burst in the glider's flags (bit 64) and
    -- lifts the player with two impulses. With the switch on, the note is taken away (so the game's own display
    -- shows a burst ready) and every later press of the burst key gets the same two impulses from here.
    if is_on(account, "fly") and not burst_broken then
      local ok, err = pcall(function()
        local move = world:get("DynamicLocomotion", p.entity)
        if not move or tonumber(tostring(move.state)) ~= HANG_GLIDING then
          p.spent, p.burst = nil, nil
          return
        end
        if move.flags & 64 ~= 0 then
          p.spent = true
          move.flags = move.flags & ~64
        end
        if p.burst then
          p.burst = nil
          local push = world:get("Impulse", p.entity)
          if not (p.spent and push) then return end  -- the first burst of a flight is the game's own
          local _, height = world:position(p.entity)
          if height and height > CEILING then return end
          local now = world:tick() * 50000000 // 3   -- the game's clock in nanoseconds: 60 steps a second
          local one, two = push.impulses[1], push.impulses[2]
          if one.endTime > now or two.endTime > now then return end  -- a burst is still lifting
          one.impulse.x, one.impulse.y, one.impulse.z = 0, 3, 0
          one.type, one.startTime, one.endTime, one.keepAliveMask = 0, now, now + 1000000000, BURST_KEEP
          two.impulse.x, two.impulse.y, two.impulse.z = 0, 9.78, 0
          two.type, two.startTime, two.endTime, two.keepAliveMask = 0, now, now + 2250000000, BURST_KEEP
        end
      end)
      if not ok then
        burst_broken = true
        emf.log("experimental: the updraft burst cannot be renewed on this game version (" .. tostring(err) .. ")")
      end
    end
    if not (p.lift and p.lift > 0) then
      p.climb = nil
    else
      p.lift = p.lift - 1
      if is_on(account, "fly") then
        local ok, err = pcall(function()
          local move = world:get("DynamicLocomotion", p.entity)
          local v = world:get("Velocity", p.entity)
          local _, height = world:position(p.entity)
          if not move or not v or tonumber(tostring(move.state)) ~= HANG_GLIDING or (height and height > CEILING) then
            p.climb = nil
            return
          end
          -- eased in from the speed the glider has now, so the climb starts without a jolt
          local vel = v.velocity
          if not p.climb then p.forward = math.max(MIN_FORWARD, math.sqrt(vel.x * vel.x + vel.z * vel.z)) end
          p.climb = math.min(CLIMB_SPEED, (p.climb or vel.y) + CLIMB_RAMP)
          vel.y = p.climb
          move.gliderUpstreamFactor = UPDRAFT
          move.gliderUpstreamUpwardsFactor = UPDRAFT
          -- the game turns a rising glider's speed backwards, so the forward speed is written too: the speed the
          -- climb began with, along the way the player faces now (steering still works)
          local q = world:get("CurrentTransform", p.entity).transform.orientation
          local fx, fz = 2 * (q.x * q.z + q.w * q.y), 1 - 2 * (q.x * q.x + q.y * q.y)
          local len = math.sqrt(fx * fx + fz * fz)
          if len > 0.01 then
            vel.x = fx / len * p.forward
            vel.z = fz / len * p.forward
          end
        end)
        if not ok then
          lift_broken = true
          emf.log("experimental: climbing with the glider does not work on this game version (" .. tostring(err) .. ")")
        end
      end
    end
  end
end

local stamina_broken = false

local function keep_stamina_full(world)
  if stamina_broken then return end
  for account, p in pairs(online) do
    if is_on(account, "stamina") then
      local ok, err = pcall(function()
        local now, full = emf.attribute(world, p.entity, "stamina"), emf.attribute(world, p.entity, "max_stamina")
        if now and full and now < full then emf.attribute_add(world, p.entity, "stamina", full - now) end
      end)
      if not ok then
        stamina_broken = true
        emf.log("experimental: stamina cannot be kept full on this game version (" .. tostring(err) .. ")")
      end
    end
  end
end

-- Free-for-all PvP (0.15.65). The game decides who can hurt whom by each creature's Faction (one byte; players are 7,
-- Player) in isEnemyFaction, before any damage (EMF docs, engine_parts/combat.md 1.2): two player-side factions are
-- never enemies, but an attacker of faction 1 (HitAll) is the enemy of everything, HitAll included, and anything that
-- is not player side is the players' enemy. So a player with PvP on gets faction 1 (written again every step: the game
-- may set it back, after a death for example), and the game's own weapons, arrows and spells hit them and let them hit.
-- EMF hit rules keep it between PvP players: while anyone has PvP on, each player without it gets two rules (no damage
-- from players, no damage to players), and one rule scales every player-on-player hit to PVP_SCALE. Heals are never
-- matched by a rule (EMF: damage hits only), so a friend's heal still works.
-- The faction is saved with the world, so it is put back to 7 when PvP goes off, and any player without PvP who is
-- found with faction 1 (left over from a crash, a reload or a leave) is put back within a second.
local HIT_ALL, PLAYER_FACTION = 1, 7
local PVP_SCALE = 0.25
local pvp_steps = 0
local pvp_scale_rule = nil

local function faction(world, id)
  local f = world:get("Faction", id)
  return f, f and tonumber(tostring(f.faction))
end

local function pvp_rule(p, key, rule)
  if p.rules[key] then return true end
  local ok, id = pcall(emf.hit_rule, rule)
  if ok and id then p.rules[key] = id return true end
  return false, tostring(id)
end

local function pvp_unrule(p, key)
  if p.rules[key] then pcall(emf.hit_rule_remove, p.rules[key]) end
  p.rules[key] = nil
end

-- Something did not work: PvP goes off for everyone, every player has their own faction again and every PvP rule is
-- taken away. The tab says "(not working on this game version)" until a player switches it on again (one new try).
local function pvp_off_everywhere(world, why)
  refused.pvp = true
  for _, p in pairs(online) do
    p.pvp = nil
    pvp_unrule(p, "pvp_in")
    pvp_unrule(p, "pvp_out")
    pcall(function()
      local f, now = faction(world, p.entity)
      if f and now == HIT_ALL then f.faction = (p.pvp_was and p.pvp_was ~= HIT_ALL) and p.pvp_was or PLAYER_FACTION end
    end)
    p.pvp_was, p.pvp_logged = nil, nil
  end
  if pvp_scale_rule then pcall(emf.hit_rule_remove, pvp_scale_rule) end
  pvp_scale_rule = nil
  emf.log("experimental: PvP is off for everyone: " .. why)
end

-- Monsters ignore a player of faction 1: the game's target picker (enemy_combat_targets) takes only player-side targets
-- (seen in game, 0.15.66: the HitAll duelist noticed a PvP player but never attacked; with PvP off it attacked at
-- once). So PvP would make a player safe from monsters. Fix: every 2 s each monster within AGGRO_R of a PvP player is
-- told, with the game's own AddThreatTargetEvent, that this player threatens it (EMF re_companion_orders.md: it makes
-- an enemy-AI body attack a target it would otherwise ignore). A monster here: an entity with the enemy AI
-- (DynamicEnemy01BehaviorState), alive, of a faction that is not player side (7, 8, 11: players, companions, summons).
local AGGRO_R, AGGRO_STEPS, AGGRO_THREAT = 20, 120, 100
local aggro_broken = false
local aggro_last = 0
-- Measured (0.15.67 diagnostics): AddThreatTargetEvent alone does not do it. The duelist stayed Idle/Roaming with
-- SelectedTargets target 0 while the player had PvP on, and went to Combat with target 1 within 6 s of PvP off. So
-- the monsters near a PvP player also get the player written as their selected target every step (EMF ai.md: "or
-- overwrite SelectedTargets.targets[0] after it runs").
local hunters = {}   -- monster entity -> PvP player entity, rebuilt every AGGRO_STEPS
local target_broken = false

local function set_id(holder, field, value)
  local v = holder[field]
  if type(v) == "table" then
    if v.id ~= value then v.id = value return true end
  elseif v ~= value then
    holder[field] = value
    return true
  end
  return false
end

-- Measured next (02:18): with the target written, the duelist kept target 1 but stayed Idle/Roaming, never Combat.
-- Its threat table (DynamicAggro, 6 slots of AggroTarget) keeps each candidate's faction (+80), state (Alarmed = 3)
-- and aggro; the AI picks a fight from the Alarmed slots. So the PvP player is also put in a slot as Alarmed with
-- faction 7 (Player, as the picker expects) and aggro 100.
local ALARMED, AGGRO_VALUE = 3, 100

local function eid(v)
  if type(v) == "table" then return v.id end
  return v
end

local function alarm(world, monster, player)
  local ag = world:get("DynamicAggro", monster)
  if not ag then return end
  local slot
  for i = 1, 6 do
    if eid(ag.targets[i].entityId) == player then slot = ag.targets[i] break end
  end
  if not slot then
    for i = 1, 6 do
      if tonumber(tostring(ag.targets[i].state)) == 0 then slot = ag.targets[i] break end
    end
  end
  if not slot then return end
  set_id(slot, "entityId", player)
  set_id(slot, "targetId", player)
  if tonumber(tostring(slot.state)) ~= ALARMED then slot.state = ALARMED end
  if tonumber(tostring(slot.faction)) ~= PLAYER_FACTION then slot.faction = PLAYER_FACTION end
  if slot.aggro < AGGRO_VALUE then slot.aggro = AGGRO_VALUE end
end

-- A test body's threat table, for the log: "slot: state entity faction aggro" for the slots in use.
local function aggro_line(world, id)
  local ag = world:get("DynamicAggro", id)
  if not ag then return "no threat table" end
  local parts = {}
  for i = 1, 6 do
    local t = ag.targets[i]
    local st = tonumber(tostring(t.state)) or -1
    if st ~= 0 then parts[#parts + 1] = string.format("%d: %d e%s f%s a%.0f", i, st, tostring(eid(t.entityId)), tostring(t.faction), t.aggro or -1) end
  end
  return #parts > 0 and table.concat(parts, "; ") or "empty"
end
F._aggro_line = aggro_line

local function hunt(world)
  if target_broken or next(hunters) == nil then return end
  local ok, err = pcall(function()
    for monster, player in pairs(hunters) do
      alarm(world, monster, player)
      local st = world:get("SelectedTargets", monster)
      if st then
        local t = st.targets[1]
        local a = set_id(t, "targetEntityId", player)
        local b = set_id(t, "targetRootEntityId", player)
        if a or b then t.changeCounter = (t.changeCounter + 1) & 0xffff end
      end
    end
  end)
  if not ok then
    target_broken = true
    emf.log("experimental: PvP: a monster's target cannot be set on this game version (" .. tostring(err) .. ")")
  end
end

local function pvp_aggro(world, players)
  hunters = {}
  if aggro_broken or #players == 0 then return end
  local sent = 0
  local ok, err = pcall(function()
    for _, e in ipairs(world:entities()) do
      if has(world, "DynamicEnemy01BehaviorState", e) then
        local _, n = faction(world, e)
        if n and n ~= 7 and n ~= 8 and n ~= 11 then
          local hp = world:get("NetworkHealth", e)
          local x, _, z = world:position(e)
          if x and (hp == nil or hp.health > 0) then
            for _, pl in ipairs(players) do
              local px, _, pz = world:position(pl)
              if px and (px - x) ^ 2 + (pz - z) ^ 2 < AGGRO_R * AGGRO_R then
                hunters[e] = pl
                local done = emf.emit("server", "AddThreatTargetEvent", { attackerId = e, targetId = pl, threatValue = AGGRO_THREAT })
                if done == false then error("the game refused AddThreatTargetEvent") end
                sent = sent + 1
              end
            end
          end
        end
      end
    end
  end)
  if not ok then
    aggro_broken = true
    emf.log("experimental: PvP: monsters cannot be pointed at PvP players on this game version (" .. tostring(err) .. "): they ignore them")
  elseif sent ~= aggro_last then
    aggro_last = sent
    emf.log(string.format("experimental: PvP: %d monster(s) near PvP players told they are threatened by them", sent))
  end
end

local function pvp(world)
  pvp_steps = pvp_steps + 1
  local any = false
  for _, p in pairs(online) do if p.pvp then any = true end end
  local ok, err = pcall(function()
    for _, p in pairs(online) do
      if p.pvp then
        pvp_unrule(p, "pvp_in")
        pvp_unrule(p, "pvp_out")
        local f, now = faction(world, p.entity)
        if f and now ~= HIT_ALL then
          if not p.pvp_was then p.pvp_was = now end
          f.faction = HIT_ALL
          if not p.pvp_logged then
            p.pvp_logged = true
            emf.log(string.format("experimental: PvP: player %s now has faction %d (was %s)", tostring(p.entity), HIT_ALL, tostring(now)))
          end
        end
      else
        if p.pvp_was or pvp_steps % 60 == 1 then
          local f, now = faction(world, p.entity)
          if f and now == HIT_ALL then
            local back = (p.pvp_was and p.pvp_was ~= HIT_ALL) and p.pvp_was or PLAYER_FACTION
            f.faction = back
            emf.log(string.format("experimental: PvP: player %s has faction %d again", tostring(p.entity), back))
          end
          p.pvp_was, p.pvp_logged = nil, nil
        end
        if any then
          local a, why = pvp_rule(p, "pvp_in", { from = "players", to = p.entity, cancel = true })
          local b, why2 = pvp_rule(p, "pvp_out", { from = p.entity, to = "players", cancel = true })
          if not (a and b) then error("the protection of players without PvP was refused (" .. tostring(why or why2) .. ")") end
        else
          pvp_unrule(p, "pvp_in")
          pvp_unrule(p, "pvp_out")
        end
      end
    end
    if any and not pvp_scale_rule then
      local okr, id = pcall(emf.hit_rule, { from = "players", to = "players", scale = PVP_SCALE })
      if okr and id then pvp_scale_rule = id end
    elseif not any and pvp_scale_rule then
      pcall(emf.hit_rule_remove, pvp_scale_rule)
      pvp_scale_rule = nil
    end
  end)
  if not ok then pvp_off_everywhere(world, tostring(err)) return end
  if any and pvp_steps % AGGRO_STEPS == 0 then
    local players = {}
    for _, p in pairs(online) do if p.pvp then players[#players + 1] = p.entity end end
    pvp_aggro(world, players)
  elseif not any then
    hunters = {}
  end
  if any then hunt(world) end
end

function F.tick(world)
  load_saved()
  if not looked then find_players(world) end
  local account, player = me(world)
  if account then seen(account, player) end
  apply()
  keep_timer_full(world)
  keep_stamina_full(world)
  if account and online[account] then online[account].kit = true end  -- the host's own game has FlameKit
  if input_broken and account and online[account] and is_on(account, "fly") and emf.key_down(CLIMB_KEY) then
    online[account].lift = 2  -- in a world you host the key is read right here, every step
  end
  if input_broken and account and online[account] and is_on(account, "fly") then
    local down = emf.key_down(BURST_KEY) == true
    if down and not host_burst_down then online[account].burst = true end
    host_burst_down = down
  end
  lift(world)
  pvp(world)
  bodies_tick(world)
  for id, g in pairs(fall_guard) do  -- the waypoint's fall protection ends
    if os.time() >= g.till then
      pcall(emf.hit_rule_remove, g.rule)
      fall_guard[id] = nil
    end
  end
  if go_request and account then
    note = handle(world, account, player, go_request).note
    go_request = nil
  end
end

-- ---- your own game's half ----

local shown = nil       -- the server's switches as last told (a joined server)
local last_peer = 0
local since_ask = 0
local ASK_STEPS = 300   -- say hello every 5 seconds: the server keeps your rules only while it hears from you

local was_held, held_said = false, 0
local burst_down = false
local want_spire = false  -- the spire button was pressed: looked up on the next step of your own screen's world
local want_waypoint = false  -- the waypoint button was pressed: read on the next step of your own screen's world

-- The game's number for a map marker type: FNV-1a over the type's GUID, as the game keeps it in memory or as written.
local function fnv(bytes)
  local h = 0x811c9dc5
  for _, b in ipairs(bytes) do h = ((h ~ b) * 0x01000193) & 0xffffffff end
  return h
end

local function marker_ids(guid)
  local hex = tostring(guid):gsub("[^%x]", "")
  if #hex ~= 32 then return nil end
  local plain = {}
  for i = 1, 31, 2 do plain[#plain + 1] = tonumber(hex:sub(i, i + 1), 16) end
  local mem = { plain[4], plain[3], plain[2], plain[1], plain[6], plain[5], plain[8], plain[7] }
  for i = 9, 16 do mem[i] = plain[i] end
  return fnv(mem), fnv(plain)
end
F._marker_ids = marker_ids

local SPIRES = { [2708501182] = true, [2561857117] = true }  -- an Ancient Spire, and one not yet unlocked
F._spires = SPIRES

-- The nearest Ancient Spire your game knows about: x, y, z, or nil.
local function nearest_spire(world)
  local me_id = emf.local_player()
  local px, py, pz = where(world, me_id)
  local bx, by, bz, best_d
  for _, id in ipairs(world:entities()) do
    local m = world:get("MapMarker", id)
    if m then
      local a, b = marker_ids(m.markerType)
      if a and (SPIRES[a] or SPIRES[b]) then
        local x, y, z = where(world, id)
        if x then
          local d = px and ((x - px) ^ 2 + (z - pz) ^ 2) or 0
          if not best_d or d < best_d then bx, by, bz, best_d = x, y, z, d end
        end
      end
    end
  end
  return bx, by, bz
end

local function peer()
  local ok, version = pcall(emf.net.peer, nil, 0, CHANNEL)
  return ok and version or 0
end

local function ask(msg)
  local ok, sent = pcall(emf.net.send, CHANNEL, emf.json.encode(msg))
  since_ask = 0
  return ok and sent == true
end

function F.client_tick(world)
  if want_waypoint then
    want_waypoint = false
    local ok, wp = pcall(world.get, world, "PlayerWaypoint", emf.local_player())
    if not ok or not wp then
      note = "Your map waypoint cannot be read on this game version."
    elseif not wp.enabled then
      note = "Set a waypoint on your map first."
    else
      local p = wp.waypointPosition
      local x, y, z = p.x / 2 ^ 32, p.y / 2 ^ 32, p.z / 2 ^ 32  -- the game keeps places in 1/2^32 m
      if kit.is_host() then go_request = { op = "wp", x = x, y = y, z = z } else ask({ op = "wp", x = x, y = y, z = z }) end
    end
  end
  if want_spire then
    want_spire = false
    local ok, x, y, z = pcall(nearest_spire, world)
    if not ok then
      emf.log("experimental: the spire lookup failed: " .. tostring(x))
      note = "Ancient Spires cannot be found on this game version."
    elseif not x then
      note = "Your game knows no Ancient Spire yet."
    elseif kit.is_host() then
      go_request = { op = "go", x = x, y = y, z = z }
    else
      ask({ op = "go", x = x, y = y, z = z })
    end
  end
  if kit.is_host() then return end
  -- only when the server cannot read the game's own input (a game update): the climb key, said when it goes down, again once a second while held (whatever the frame rate), and when let go
  if shown and shown.fly and shown.keys then
    local down = emf.key_down(BURST_KEY) == true
    if down and not burst_down then pcall(emf.net.send, CHANNEL, emf.json.encode({ op = "burst" })) end
    burst_down = down
    local held = emf.key_down(CLIMB_KEY) == true
    if held ~= was_held or (held and os.time() ~= held_said) then
      was_held = held
      held_said = os.time()
      pcall(emf.net.send, CHANNEL, emf.json.encode({ op = "lift", on = held }))
    end
  end
  local version = peer()
  if version ~= last_peer then
    last_peer = version
    shown = nil
    since_ask = ASK_STEPS
  end
  since_ask = since_ask + 1
  if version ~= 0 and since_ask >= ASK_STEPS then ask({ op = "get" }) end
end

function F.connected(world)
  return kit.is_host() or peer() ~= 0
end

local function hosting(world)
  return kit.is_host() or world:is_server()
end

-- The Debug section at the bottom of the tab: the test players (features/party.lua) and FlameKit's log level
-- (debug.txt: off, normal, full; the same as Ctrl+Shift+F12 in the game). Keys "dbg:...".
local function debug_rows(world, rows)
  rows[#rows + 1] = { separator = true }
  rows[#rows + 1] = { heading = "Debug" }
  for _, r in ipairs(require("features.party").test_rows(world)) do
    if r.button then r.button = "dbg:test:" .. r.button end
    rows[#rows + 1] = r
  end
  local level = kit.debug_level(true)
  rows[#rows + 1] = { text = "FlameKit's log level (Ctrl+Shift+F12 in the game also switches it):" }
  for i, l in ipairs({ { "off", "Off", "Errors and warnings only" }, { "normal", "Normal", "Also what happens: windows, updates, clicks" },
                       { "full", "Full", "Also every detail: for finding a problem" } }) do
    rows[#rows + 1] = { button = "dbg:log:" .. l[1], text = l[2], selected = level == l[1], same_line = i > 1, tooltip = l[3] }
  end
  rows[#rows + 1] = { dim = true, text = "The logs are in emf\\mods\\flamekit\\logs in the game's folder (the last 10 games)." }
  return rows
end

local function panel_rows(world)
  local v
  if hosting(world) then
    load_saved()
    local account = me(world)
    v = account and view(account)
  else
    v = shown
  end
  local rows = {
    { color = "#ffb060", text = "Experimental: these bend the game's rules for you only. Every player has their own." },
  }
  if not v then
    rows[#rows + 1] = { dim = true, text = (hosting(world) or peer() ~= 0) and "Asking the server..."
      or "This server does not run FlameKit (or not this version), so there is nothing to switch here." }
    return debug_rows(world, rows)
  end
  rows[#rows + 1] = { separator = true }
  for _, s in ipairs(SWITCHES) do
    local on = v[s[1]] == true
    local text = (on and "On    " or "Off   ") .. s[2]
    if v[s[1] .. "_dead"] then text = text .. " (not working on this game version)" end
    rows[#rows + 1] = { button = "sw:" .. s[1], text = text, selected = on, tooltip = TIPS[s[1]] }
  end
  rows[#rows + 1] = { separator = true }
  rows[#rows + 1] = { heading = "Fast Travel" }
  rows[#rows + 1] = { button = "home", text = "Nearest Flame Altar",
    tooltip = "Takes you to the nearest flame altar at once. Works where the map's fast travel does not: inside the shroud, in lava, while stuck." }
  rows[#rows + 1] = { button = "spire", text = "Nearest Ancient Spire", same_line = true,
    tooltip = "Takes you to the nearest Ancient Spire on your map, unlocked or not. Works inside the shroud too." }
  rows[#rows + 1] = { button = "waypoint", text = "Map Waypoint", same_line = true,
    tooltip = "Takes you straight to the waypoint you set on your map, onto the ground there. Fall damage is off for 30 seconds "
      .. "after the move, in case there is no ground right at the waypoint." }
  if note then rows[#rows + 1] = { color = "#ff8060", text = note } end
  debug_rows(world, rows)
  rows[#rows + 1] = { text = "PvP test bodies, 3 m in front of you (one at a time, gone after a reload):" }
  rows[#rows + 1] = { button = "dbg:body:dummy", text = "Spawn PvP dummy", selected = v.body == "dummy",
    tooltip = "A player-like body (faction Player). With PvP on it swings at you but does no damage: hit it to see whether your weapons hurt a player." }
  rows[#rows + 1] = { button = "dbg:body:duel", text = "Spawn PvP duelist", same_line = true, selected = v.body == "duel",
    tooltip = "A Vukah fighter that attacks everyone with full damage, PvP on or off. It never hurts animals, pets or buildings; villagers are fair game. Spawn it away from your base." }
  rows[#rows + 1] = { button = "dbg:body:none", text = "Remove", same_line = true, disabled = v.body == nil,
    tooltip = "Removes your test body." }
  return rows
end

function F.panel(world)
  return panel_rows(world)
end

function F.click(world, key)
  if key:sub(1, 9) == "dbg:test:" then return require("features.party").set_test(world, key:sub(10)) end
  local kind = key:match("^dbg:body:(%a+)$")
  if kind then
    note = nil
    if hosting(world) then
      local account, player = me(world)
      if account then note = handle(world, account, player, { op = "body", kind = kind }).note end
    else
      ask({ op = "body", kind = kind })
    end
    return
  end
  local level = key:match("^dbg:log:(%a+)$")
  if level then
    local f = io.open(emf.dir .. "\\debug.txt", "w")
    if f then
      f:write(level)
      f:close()
    end
    kit.debug("warn", "log: debug level %s (Experimental tab, Debug)", level)
    kit.debug_level(true)
    return
  end
  if key == "home" then
    note = nil
    if hosting(world) then
      local account, player = me(world)
      if account then note = handle(world, account, player, { op = "home" }).note end
    else
      ask({ op = "home" })
    end
    return
  end
  if key == "spire" then
    note = nil
    want_spire = true
    return
  end
  if key == "waypoint" then
    note = nil
    want_waypoint = true
    return
  end
  if key:sub(1, 3) ~= "sw:" then return end
  local name = key:sub(4)
  if hosting(world) then
    local account, player = me(world)
    if not account then return end
    load_saved()
    handle(world, account, player, { op = "set", key = name, on = not view(account)[name] })
  elseif shown then
    shown[name] = not shown[name]  -- at once on screen; the server's answer follows
    ask({ op = "set", key = name, on = shown[name] })
  end
end

function F.setup(k)
  kit = k
  -- the game event that points monsters at PvP players (see pvp_aggro); EMF wants it named in the mod's first run
  local okx, said = pcall(emf.emits, { "AddThreatTargetEvent" }, "server")
  if not okx or said == false then emf.log("experimental: AddThreatTargetEvent cannot be sent (" .. tostring(said) .. "): monsters may ignore PvP players") end
  -- a player who joins has their rules from the first second, not from their game's first hello
  -- a player who leaves: their rules go at once (their switches stay saved for the next visit)
  pcall(emf.on_player_left, kit.guard(F, function(world, p)
    if not (p and p.account) then return end
    local account = tostring(p.account)
    if online[account] then
      if online[account].pvp then
        pcall(function()
          local f, now = faction(world, online[account].entity)
          if f and now == HIT_ALL then f.faction = PLAYER_FACTION end
        end)
      end
      drop_rules(online[account])
      online[account] = nil
    end
    drop_bodies_of(world, account, true)
  end, "a player leaving"))
  pcall(emf.on_player_joined, kit.guard(F, function(world, p)
    if p and p.account and p.player and p.player ~= 0 then
      load_saved()
      seen(tostring(p.account), p.player)
    end
  end, "a player joining"))
  local ok = emf.net.channel(CHANNEL, {
    version = 1, to = "both", max = 1024, per_10s = 30,
    on_server = kit.guard(F, function(world, from, data)
      local msg = emf.json.decode(data)
      if type(msg) ~= "table" or not from or not from.player or from.player == 0 then return end
      local v = handle(world, from.account, from.player, msg)
      if not v then return end
      pcall(emf.net.send_to, world, from.player, CHANNEL, emf.json.encode(v))
    end, "a message from a player"),
    on_player = kit.guard(F, function(world, from, data)
      local msg = emf.json.decode(data)
      if type(msg) == "table" and msg.op == "state" then
        shown = msg
        if msg.note then note = msg.note end
      end
    end, "a message from the server"),
  })
  if not ok then emf.log("the channel flamekit/exp was refused: the experimental switches work only in worlds you host") end
end

return F
