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
}

-- The options that are on until a player switches them off (the others are off until switched on).
local DEFAULT_ON = { fly = true }

-- What each option does, shown when the pointer rests on its button.
local TIPS = {
  shroud = "Your shroud timer stays full and the red shroud cannot kill you. Stays on until you switch it off. Everyone on the server is told when you switch it.",
  fall = "Falling never hurts you, from any height. Stays on until you switch it off. Everyone on the server is told when you switch it.",
  immortal = "Nothing can hurt or kill you: enemies, lava, the shroud, falling. Stays on until you switch it off. Everyone on the server is told when you switch it.",
  stamina = "Your stamina never runs out. Stays on until you switch it off. Everyone on the server is told when you switch it.",
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

local function view(account)
  local v = { op = "state", keys = input_broken or nil }
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
  if msg.op == "home" or msg.op == "go" then
    local ok, why
    if msg.op == "home" then ok, why = pcall(go_home, world, entity) else ok, why = pcall(go_near, world, entity, msg) end
    local v = view(account)
    v.note = not ok and "The move failed on this game version." or why
    if not ok then emf.log("experimental: go_home failed: " .. tostring(why)) end
    return v
  end
  if msg.op == "set" and type(msg.key) == "string" then
    for _, s in ipairs(SWITCHES) do
      if s[1] == msg.key then
        local set = saved[account] or {}
        if DEFAULT_ON[s[1]] then
          if msg.on == true then set[s[1]] = nil else set[s[1]] = false end  -- only "off" is worth keeping
        else
          set[s[1]] = msg.on == true or nil            -- only "on" is worth keeping
        end
        saved[account] = next(set) and set or nil
        refused[s[1]] = nil
        emf.log(string.format("experimental: %s switched '%s' %s", account, s[1], msg.on == true and "on" or "off"))
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

function F.panel(world)
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
    return rows
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
  if note then rows[#rows + 1] = { color = "#ff8060", text = note } end
  return rows
end

function F.click(world, key)
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
  -- a player who joins has their rules from the first second, not from their game's first hello
  -- a player who leaves: their rules go at once (their switches stay saved for the next visit)
  pcall(emf.on_player_left, kit.guard(F, function(world, p)
    if not (p and p.account) then return end
    local account = tostring(p.account)
    if online[account] then
      drop_rules(online[account])
      online[account] = nil
    end
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
