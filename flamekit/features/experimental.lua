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
-- The PvP mode: "ffa", free-for-all, the only one so far. Rules that belong to it alone check it (owner, 0.15.136:
-- future modes such as teams may differ). The cool-down and the protections are shared by every mode for now.
local PVP_MODE = "ffa"
local PVP_LOCK_S = 60
-- (0.15.137, production: the server's world has some 37,000 entities, and EMF pauses all of FlameKit when one call
-- runs over 250 ms) the scans over every entity stop once they used SCAN_BUDGET seconds and go on later
local SCAN_BUDGET = 0.06
local SCAN_MAX = 6000  -- and never more than this many entities in one call, in case the clock does not work
local clock_ok, clock = pcall(function() return os.clock end)
if not (clock_ok and type(clock) == "function" and pcall(clock)) then clock = nil end
local function now_s() return clock and clock() or 0 end
-- one scan's limit: time (when os.clock works) and a count, whichever comes first
local function scan_over(t0, done) return done >= SCAN_MAX or (clock ~= nil and clock() - t0 > SCAN_BUDGET) end  -- (0.15.134, owner) PvP cannot be left until this long after the last hit by another PvP player

-- The options that are on until a player switches them off (the others are off until switched on).
local DEFAULT_ON = { fly = true }

-- (0.15.118, owner: no cheating in PvP) while a player has PvP on, all their other options are off, except the
-- glider; what they had switched on stays saved and works again once PvP is off.
local PVP_KEEPS = { fly = true, pvp = true }

-- What each option does, shown when the pointer rests on its button.
local TIPS = {
  shroud = "Your shroud timer stays full and the red shroud cannot kill you. Stays on until you switch it off. Everyone on the server is told when you switch it.",
  fall = "Falling never hurts you, from any height. Stays on until you switch it off. Everyone on the server is told when you switch it.",
  immortal = "Nothing can hurt or kill you: enemies, lava, the shroud, falling. Stays on until you switch it off. Everyone on the server is told when you switch it.",
  stamina = "Your stamina never runs out. Stays on until you switch it off. Everyone on the server is told when you switch it.",
  pvp = "Free-for-all PvP: you can hurt other players who have PvP on, and they can hurt you, with your normal weapons "
    .. "and spells, at full damage. Players without PvP cannot hurt you and you cannot hurt them. Off again when you leave the server. Everyone "
    .. "on the server is told when you switch it. Once another PvP player hits you, you cannot switch PvP off for a minute. While PvP is on, fast travel, spawning test monsters and your other options are off (all but the glider) and come back when you switch PvP off.",
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

-- What the player switched, PvP or not.
local function wants(account, key)
  if SESSION_ONLY[key] then return online[account] ~= nil and online[account][key] == true end
  local value = (saved[account] or {})[key]
  if value == nil then return DEFAULT_ON[key] == true end
  return value == true
end

-- Is this option held off by PvP for this player?
local function held_by_pvp(account, key)
  return not PVP_KEEPS[key] and wants(account, "pvp")
end

is_on = function(account, key)
  return wants(account, key) and not held_by_pvp(account, key)
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
    if held_by_pvp(account, s[1]) then v[s[1] .. "_pvp"] = true end
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
-- EMF refused a move at once (its log says why: most often one still under way for that player)
local REFUSED = "The move could not start: wait a moment and try again."

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
    return REFUSED
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
  if not queued then return REFUSED end
  emf.log(string.format("experimental: player %s sent to %.0f %.0f %.0f (pad %s)", tostring(player), x, y, z, tostring(best)))
end

-- Fast travel to the waypoint on the player's map (0.15.60). Their own game sends the waypoint's place (PlayerWaypoint
-- of their player, in their game's world). So fall damage is off for that player for 30 s after the move (an EMF hit
-- rule, removed again by F.tick). Every move is logged with the waypoint's height and where they landed.
-- (0.15.125, production server log 2026-11-14) The game's ground search (`ground = true`) never finished for moves of
-- some hundred metres on the dedicated server: EMF gave up after 10 s ("still has a Teleport 10 s after EMF's push"),
-- the player stood frozen meanwhile, and a click in that time was refused. The ground search needs the destination's
-- path grid, which a dedicated server has only near players. And a minimap waypoint had the player's own height, not
-- the marker's. Now: a minimap click sends the marker's height too (wp_known); a move farther than NEAR_M to a waypoint
-- whose height is known goes straight there, 1.5 m above it, without the ground search (fall damage is off anyway);
-- a ground search that gives up is tried again once that way when the height is known; otherwise the player is told.
-- One move per player at a time (moving[]): a second click while one is under way is answered, not refused.
local fall_guard = {}  -- player entity -> { rule = hit rule id, till = os.time() when it goes }
local wp_known = {}    -- player entity -> { x, y, z }: the last minimap waypoint, with the marker's own height
local moving = {}      -- player entity -> os.time() when its waypoint move started (cleared by the answer, or after 15 s)
local retry = {}       -- player entity -> { x, y, z, account, steps }: a raw move to try once the given-up one is gone
local NEAR_M = 64      -- closer than this: the ground search (its area is loaded around the player)

local function guard_falls(player)
  local okr, rule = pcall(emf.hit_rule, { kinds = "fall", to = player, cancel = true })
  if okr and rule then
    if fall_guard[player] then pcall(emf.hit_rule_remove, fall_guard[player].rule) end
    fall_guard[player] = { rule = rule, till = os.time() + 30 }
  end
end

-- A line for one player's FlameKit window (the note under the buttons), from a callback: no reply to send it with.
local tell_player  -- set below, once `view` and the channel are known

local function waypoint_move(world, player, account, x, y, z, ground, why)
  guard_falls(player)
  moving[player] = os.time()
  local ty = ground and y or y + 1.5
  local queued = emf.teleport(world, player, x, ty, z, { ground = ground }, function(moved, mx, my, mz, info)
    moving[player] = nil
    emf.log(string.format("experimental: waypoint travel of player %s (%s): %s at %.0f %.0f %.0f (waypoint height %.0f%s)",
      tostring(player), why, tostring(info and info.status), mx or -1, my or -1, mz or -1, y,
      not ground and ", straight there" or info and info.raw_target and ", no ground found: stood exactly there" or ", on the ground"))
    if moved then return end
    if ground and y ~= 0 then
      retry[player] = { x = x, y = y, z = z, account = account, steps = 30 }  -- once EMF's watchdog took its Teleport away
    elseif tell_player then
      tell_player(world, player, account, "The game could not find ground at the waypoint in time. Set the waypoint by "
        .. "clicking a marker on the minimap, then try again.")
    end
  end)
  if not queued then moving[player] = nil end
  return queued
end

local function go_waypoint(world, player, msg, account)
  local x, y, z = tonumber(msg.x), tonumber(msg.y), tonumber(msg.z)
  if not (x and y and z) or x ~= x or z ~= z or x < 0 or z < 0 or x > 10240 or z > 10240 or y < -1000 or y > 5000 then
    return "That waypoint is not on the map."
  end
  if moving[player] and os.time() - moving[player] < 15 then return "Still on the way: one move at a time." end
  local px, py, pz = where(world, player)
  local k = wp_known[player]
  local known = k and math.abs(k.x - x) < 3 and math.abs(k.z - z) < 3
  if known then y = k.y end
  -- (0.15.133, production log: a waypoint set on the game's own map had a real height, 808, the player stood at 945)
  -- a waypoint from the game's map is as good: any real height counts
  if not known and y ~= 0 then known = true end
  local far = not px or (px - x) ^ 2 + (pz - z) ^ 2 > NEAR_M * NEAR_M
  local ty = y ~= 0 and y or (py or 300)  -- a waypoint without a height: start from yours
  local raw = known and far
  if not waypoint_move(world, player, account, x, ty, z, not raw, raw and "far, marker height" or "ground search") then
    return REFUSED
  end
  emf.log(string.format("experimental: player %s sent to the waypoint %.0f %.0f %.0f (%s)", tostring(player), x, ty, z,
    raw and "straight there" or "ground search"))
end

-- once a step (server world): the raw retry of a given-up ground search
local function retry_tick(world)
  for player, r in pairs(retry) do
    r.steps = r.steps - 1
    if r.steps <= 0 then
      retry[player] = nil
      if not waypoint_move(world, player, r.account, r.x, r.y, r.z, false, "again, straight there") and tell_player then
        tell_player(world, player, r.account, "The move to the waypoint did not work: try again.")
      end
    end
  end
  for player, t in pairs(moving) do
    if os.time() - t >= 15 then moving[player] = nil end  -- no answer came (a reload): not stuck for ever
  end
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
-- player clicks Remove or leaves, or when the world reloads. (0.15.126, owner: a killed duelist's body could not be
-- looted and never went away, in a flame altar's area, and Remove was greyed out) When it dies, its body is destroyed
-- CORPSE_S seconds later. Remove is always there: since 0.15.136 it destroys every test monster in the world that is
-- the player's own or nobody's (remove_all, is_test_monster).
local DUMMY_GUID = "9543cfb0-b4d7-408e-905c-ccb79a15136d"  -- FakePlayer_Vukah_Melee
local DUEL_GUID = "d5d05217-52dc-467a-9192-26b4f661d8d9"   -- Enemy_Vukah_Melee
-- What a duelist can be (0.15.72, owner: any monster from a list): every creature in core/monsters.lua, read from
-- the game's own data (189 of them, in groups). The client sends the template GUID; the server spawns only GUIDs on that
-- list. Before 0.15.72 there were seven, taken from EMF's own mods (all seven fought, 2026-11-14).
local MONSTERS = require("core.monsters")
local item_db = require("core.item_db")      -- (0.15.142) the items test monsters drop
local ground = require("core.ground_loot")
local loot_chest = require("core.loot_chest")  -- (0.15.154) test monsters' loot in chests
local bag = require("core.bag")
local MONSTER_BY_GUID, MONSTER_GROUPS = {}, {}
for _, m in ipairs(MONSTERS) do
  MONSTER_BY_GUID[m[3]] = m
  if not MONSTER_GROUPS[#MONSTER_GROUPS] or MONSTER_GROUPS[#MONSTER_GROUPS] ~= m[1] then
    local known = false
    for _, g in ipairs(MONSTER_GROUPS) do if g == m[1] then known = true end end
    if not known then MONSTER_GROUPS[#MONSTER_GROUPS + 1] = m[1] end
  end
end
-- (0.15.139, owner) "Random", the default: each monster of a spawn is a different random one from the list, bosses
-- left out (26 of the 189: a spawn of 1000 would bring about 140 bosses). An older server does not know the key and
-- spawns its default (Vukah Melee).
local RANDOM_KEY = "random"
local RANDOM_PICK = { "Random", "Random", RANDOM_KEY, false }
local RANDOM_POOL = {}
for _, m in ipairs(MONSTERS) do if not m[4] then RANDOM_POOL[#RANDOM_POOL + 1] = m end end
local function duelist(guid)
  if guid == RANDOM_KEY then return RANDOM_PICK end
  return MONSTER_BY_GUID[guid] or MONSTER_BY_GUID[DUEL_GUID] or { "Vukah", "Melee", DUEL_GUID, false }
end
-- (0.15.81, owner) The dummy can be any monster too: it gets faction 7 (Player), whose hits do no damage (EMF
-- re_companions.md: a player-faction enemy body hits for 0), so it never hurts anyone. The first choice is the
-- player-like body of before.
local DUMMY_PLAIN = { "Dummy", "Player-like", DUMMY_GUID, false }
-- (0.15.97, owner: the FakePlayer_Vukah_Melee body does not look like a player) "Player-like" spawns one of these at
-- random: the game's other fake-player body and the human Scavenger fighters (template names from the game's data).
local PLAYER_LIKE = {
  "4227fee0-b8e6-4518-9dc6-358472b3957b",  -- FakePlayer_Scavenger_Ranger
  "53bf33ac-f81a-4874-9f0c-7c23daf4e24e", "bfeb722b-c6b8-4fdd-9141-dfb363ab7ff0", "1ae0f2bf-1201-42ae-aa69-ab9bd516c029",
  "bd8548d8-4c7d-4133-8db8-3f24dc377340", "7782b953-ba12-4254-9eea-042a1c9c65cf", "016c2e66-30a1-494b-9682-35564756f011",
  "342d4470-68f0-4f9c-8454-6875ff72f261", "eb35d1ff-3c0c-47b7-8aec-bc7826525362", "60b09960-d2c7-43ea-875c-2eb4547bed50",  -- Enemy_Scavenger_Melee01-09
  "40bd6a6a-d549-4e9b-b421-741f3b0777d5", "73941b4c-5d7a-4525-85fc-0da71a4fc74e", "78060b4c-8395-4d3b-a814-f350092affb2",
  "19023f07-becf-48c6-88dd-8c2060ed9a6c", "68e89aee-9560-4246-8bd8-3fc9a6a5fbe0", "04e5439f-2fd5-4626-bbf0-deb8f1a39e1f",
  "b5f02f01-513e-4543-a6f1-d82c64d3194b",  -- Enemy_Scavenger_ColdHeights_Melee01-07
}
local function dummy_of(guid)
  if guid == DUMMY_GUID or not MONSTER_BY_GUID[guid] then return DUMMY_PLAIN end
  return MONSTER_BY_GUID[guid]
end
local DUMMY_LEVEL = 50  -- (0.15.129, owner: 100 was too high) about 6700 health
local MAX_LEVEL = 100  -- owner (0.15.78): a round top. The game's own is 105: any higher level is set back to 105 (measured 2026-11-14: 150 to 100000 all became 105, 62687 health)
local DUEL_FACTION = 1                                      -- HitAll
-- (0.15.134, owner: anyone should be able to kill the dummy, not only PvP players) the monsters' own faction (3), so
-- every player can hit it and monsters leave it alone; a hit rule cancels all of its own hits, so it never hurts
-- anyone. Before: faction 7 (Player), which only PvP players could hit (0.15.81 to 0.15.133).
local DUMMY_FACTION = 3
local OLD_DUMMY_FACTION = 7  -- dead dummies left before 0.15.134 (is_test_monster)
local SHIELD_STEPS = 180  -- how often the duelists' building rule is checked
-- (0.15.134, owner: how many to spawn) MAX_DUELISTS: the most one request may ask for (the server refuses more, so a
-- bug or a modified game cannot ask for 100,000); owner, 0.15.139: 1000. Measured on the production server
-- (2026-11-14): 200 level-1 monsters fighting one player put the game server at its limit per step (~17 ms of 16.7).
local MAX_DUELISTS = 1000  -- (0.15.141, owner) back to 1000: 5000 crushed the production server (steps ~165 ms)
local DUEL_COUNTS = { 1, 15, 50, 100, 200, 500, 1000 }
local bodies = {}    -- entity id -> { kind, owner = account, session, rules = { key -> id }, guard = { entity -> rule id } }
local CORPSE_S = 8
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

-- (0.15.136, owner: Remove must clear every test monster in the world, near and far) Every test monster is spawned
-- with a ScaleComponent of TAG_SCALE (0.1% smaller than normal: not visible) so it can be found again, also after a
-- reload of FlameKit (which forgets `bodies`). Older ones: a duelist has faction 1 (no game monster has it); a dead
-- dummy from before 0.15.134 has faction 7. Players are never touched (they have an account).
local TAG_SCALE = require("core.test_tag").SCALE  -- 0.999 (0.15.156: shared, core/test_tag.lua)
local function is_test_monster(world, id)
  local oka, acc = pcall(world.account, world, id)
  if oka and acc then return false end
  local oks, sc = pcall(world.get, world, "ScaleComponent", id)
  if oks and sc and sc.uniformScale and math.abs(sc.uniformScale - TAG_SCALE) < 0.0003 then return true end
  local okf, f = pcall(world.get, world, "Faction", id)
  local fn = okf and f and tonumber(tostring(f.faction))
  if fn == DUEL_FACTION then return has(world, "NetworkHealth", id) end  -- a creature, not something placed
  if fn == OLD_DUMMY_FACTION then
    local okh, hp = pcall(world.get, world, "NetworkHealth", id)
    return okh and hp ~= nil and hp.health <= 0  -- only dead ones (a live faction 7 creature may be a companion)
  end
  return false
end

-- Removes this player's test monsters and every test monster nobody keeps (left behind by a reload, or by a player
-- who is gone), anywhere in the world. Another player's own live test monsters stay. Returns how many.
local remove_left = nil  -- (0.15.137) a world scan of Remove that ran out of time: { account, player, from, n }
local function remove_all(world, account, player, from, n)
  n = n or 0
  local t0 = now_s()
  if not from then  -- (0.15.140: up to 5000) the player's own ones, within the budget too; the rest on the next steps
    local k = 0
    for id, b in pairs(bodies) do
      if b.owner == account then
        if scan_over(t0, k) then
          remove_left = { account = account, player = player, n = n }
          return n, false
        end
        drop_body(world, id, true)
        n, k = n + 1, k + 1
      end
    end
    t0 = now_s()
  end
  local list = world:entities()
  for i = from or 1, #list do
    local id = list[i]
    if scan_over(t0, i - (from or 1)) then
      remove_left = { account = account, player = player, from = i, n = n }  -- the rest on the next steps
      return n, false
    end
    if id ~= player and not bodies[id] and is_test_monster(world, id) then
      if pcall(emf.destroy, world, id) then n = n + 1 end  -- (0.15.140, owner) no line per monster: one at the end
    end
  end
  remove_left = nil
  emf.log(string.format("experimental: Remove by player %s: %d test monster%s removed", tostring(player), n, n == 1 and "" or "s"))
  return n, true
end

-- (0.15.137, owner) test monsters have no protections at all any more: they may hurt pets, animals, villagers,
-- buildings and placed objects ("anyone who spawns 200 monsters inside someone's base..."). Before, a shared building
-- rule and per-animal rules (0.15.66 to 0.15.136); the animal rules were a scan of the whole world for every duelist,
-- which paused FlameKit with 100 of them. guard_duelists only takes away a building rule left from before.
local duel_guard = { objects = nil }
local function guard_duelists(world)
  if duel_guard.objects then pcall(emf.hit_rule_remove, duel_guard.objects) end
  duel_guard = { objects = nil }
end

-- Returns nil, or why there is no body now.
-- A body's level (console only: flamekit.duelist <player> <level>). EMF re_companion_orders.md: writing
-- Level.dataStorage and DynamicEnemyScaling.nextUpdateTime = 0 makes the game's next scaling update use it (level 10:
-- health 119 -> 417, hits 48 -> 156). Levels above the world's range were never tried.
local function set_level(world, id, level)
  local lv = world:get("Level", id)
  if not lv then return false end
  lv.dataStorage[1] = level
  local sc = world:get("DynamicEnemyScaling", id)
  if sc then
    if type(sc.nextUpdateTime) == "table" then sc.nextUpdateTime.value = 0 else sc.nextUpdateTime = 0 end
  end
  return true
end

local SPAWN_PER_STEP = 20
local scatter  -- below
-- (0.15.140, owner: "spawn on top of the terrain so they don't end up inside stuff") emf.spawn puts a monster exactly
-- at the given place: the player's height, which on a slope is inside the hill or in the air. So GROUND_WAIT_STEPS
-- after its spawn each one is moved with emf.teleport and the game's own ground search (fast travel's: the nearest
-- walkable spot within about 10 m up or down; EMF docs: +4..+8 and -3..-10 m snapped, +-16 m not, then it stays
-- where it is). The wait: EMF refuses a creature spawned a moment ago (it reads as dead until the game sets its
-- health). At most GROUND_MAX at once (EMF allows 64 teleports under way for all of FlameKit; the rest for players).
-- Untested in game.
local GROUND_WAIT_STEPS, GROUND_MAX, GROUND_GIVEUP_STEPS = 120, 40, 900
local ground_q, ground_head, ground_busy, ground_step = {}, 1, {}, 0
local ground_n = 0  -- how many in ground_busy
local function to_ground(id, x, y, z)
  ground_q[#ground_q + 1] = { id = id, x = x, y = y, z = z, at = ground_step + GROUND_WAIT_STEPS }
end
local function ground_tick(world)
  ground_step = ground_step + 1
  if ground_n > 0 and ground_step % 60 == 0 then  -- an answer that never came (a reload): not counted any more
    for id, at in pairs(ground_busy) do
      if ground_step - at > GROUND_GIVEUP_STEPS then ground_busy[id], ground_n = nil, ground_n - 1 end
    end
  end
  while ground_head <= #ground_q and ground_n < GROUND_MAX do
    local g = ground_q[ground_head]
    if g.at > ground_step then break end
    ground_head = ground_head + 1  -- (entries stay until the queue is empty: # of a table with holes is not reliable)
    if bodies[g.id] and not ground_busy[g.id] then
      local x, z = g.x, g.z
      pcall(function()  -- where it is now (it may have walked a little), at the height it was given
        local px, _, pz = world:position(g.id)
        if px and pz then x, z = px, pz end
      end)
      local id = g.id
      local okt, queued = pcall(emf.teleport, world, id, x, g.y, z, { ground = true }, function()
        if ground_busy[id] then ground_busy[id], ground_n = nil, ground_n - 1 end
      end)
      if okt and queued then ground_busy[id], ground_n = ground_step, ground_n + 1 end
    end
  end
  if ground_head > #ground_q then ground_q, ground_head = {}, 1 end
end
-- (0.15.139, owner: "I don't want the dummy to attack me back") Since 0.15.134 the dummy has the monsters' faction so
-- anyone can hit it, and so its AI goes for players: it swung but did no damage. Before (faction 7) it stood still.
-- Now its threat table (DynamicAggro) and its target (SelectedTargets) are emptied every server step: with no Alarmed
-- slot the game's AI has nobody to fight (HANDOFF: the AI picks a fight only from the Alarmed slots). One dummy per
-- player, so it costs next to nothing.
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
local calm = {}  -- dummy entity -> true
local function calm_tick(world)
  for id in pairs(calm) do
    local b = bodies[id]
    if not b or b.kind ~= "dummy" then
      calm[id] = nil
    else
      pcall(function()
        local ag = world:get("DynamicAggro", id)
        if ag then
          for i = 1, 6 do
            local t = ag.targets[i]
            if t and tonumber(tostring(t.state)) ~= 0 then t.state = 0; t.aggro = 0 end
          end
        end
      end)
      pcall(function()
        local st = world:get("SelectedTargets", id)
        if st and st.targets and st.targets[1] then set_id(st.targets[1], "targetEntityId", 0) end
      end)
    end
  end
end
local spawn_queue = {}  -- { account, fn }: each spawns one queued test monster (spawn_tick)

-- Where the monsters of a spawn stand, as { side, ahead } in metres from 3 m in front of the player (spawn_body adds
-- the 3 m): one alone right there. More: (0.15.141, owner: "packed as tight as possible", "do a hexagonal grid") a
-- hexagonal grid SPOT_MIN m apart (each monster 2 m from its six neighbours, about 3.5 m2 each: the tightest packing),
-- centred on the player and filled from the inside out, so the spawn is round; no monster within SPOT_MIN m of the
-- player. 15: within about 5 m, 200: about 16 m, 1000: about 34 m. (0.15.140 had a random scatter, 0.15.139 a square
-- grid.) Each monster is then put on the ground (to_ground).
local SPOT_MIN = 2
scatter = function(count)
  if count <= 1 then return { { 0, 0 } } end
  local row = SPOT_MIN * math.sqrt(3) / 2  -- the distance between two rows of a hexagonal grid
  local r = math.sqrt(count * SPOT_MIN * row / math.pi) + 2 * SPOT_MIN  -- a little more than the area they need
  local cells = {}
  for j = -math.ceil(r / row), math.ceil(r / row) do
    local b = j * row
    local shift = (j % 2 == 0) and 0 or SPOT_MIN / 2
    for i = -math.ceil(r / SPOT_MIN) - 1, math.ceil(r / SPOT_MIN) + 1 do
      local a = i * SPOT_MIN + shift
      local d2 = a * a + b * b
      if d2 >= SPOT_MIN * SPOT_MIN - 0.01 and d2 <= r * r then cells[#cells + 1] = { a, b, d2 } end
    end
  end
  table.sort(cells, function(p, q) return p[3] < q[3] end)  -- nearest first: a round spawn
  local spots = {}
  for k = 1, math.min(count, #cells) do spots[k] = { cells[k][1], cells[k][2] - 3 } end
  return spots
end

-- (0.15.142, owner) What a killed test monster (Spawn Monsters, not the dummy) drops on the ground beside its body,
-- all legendary: regular runes (10 or 15) and legendary runes (5 or 10), a boss twice as many; and one more item with
-- equal chances of a cosmetic, a weapon, an armour piece, a ring or a gem, the gear of the tier for the monster's level
-- (core/item_db.lua). Through core/ground_loot.lua (a loose item keeps quality and level).
local LOOT_KINDS = { "cosmetic", "weapon", "armor", "ring", "gem" }  -- (0.15.162, owner: "we want cosmetics too")
local fx_steps = 0    -- server steps (F.tick)
local body_clear = {}  -- (0.15.161) test monster bodies to empty: { id, at }
local function body_clear_tick(world)
  if #body_clear == 0 then return end
  local keep = {}
  for _, d in ipairs(body_clear) do
    if d.at > fx_steps then keep[#keep + 1] = d
    else
      for _, st in ipairs(bag.entity_stacks(world, d.id)) do
        pcall(emf.take, world, st.owner, st.item, st.count, function() end, { slot = st.slot, exact = true })
      end
    end
  end
  body_clear = keep
end

local function drop_test_loot(world, id, b)
  local ok, x, y, z = pcall(world.position, world, id)
  if not ok or not x then return "no position" end
  local twice = b.boss and 2 or 1
  local level = tonumber(b.level) or 1
  local runes, lrunes = (math.random(2) == 1 and 10 or 15) * twice, (math.random(2) == 1 and 5 or 10) * twice
  -- (0.15.154, owner: too much loot on the ground) runes straight into the killer's bag (the last player who hit it;
  -- else whoever spawned it); what does not fit there, and the legendary item, into a chest beside the body
  -- (core/loot_chest.lua: a new chest when one is full)
  local killer = b.last_hitter
  if not killer and online[b.owner] then killer = online[b.owner].entity end
  local key = killer or ("owner:" .. tostring(b.owner))
  local function to_bag(item, n)
    local iid = item
    if type(iid) == "string" then local okn, v = pcall(emf.item, iid) iid = okn and v or nil end
    if not killer or not iid then loot_chest.put(world, key, x, y, z, item, n, 0, 0) return end
    local okp = pcall(emf.put, world, killer, iid, n, function(w, added)
      added = tonumber(added) or 0
      if added < n then loot_chest.put(w, key, x, y, z, iid, n - added, 0, 0) end  -- the bag is full: the rest in the chest
    end)
    if not okp then loot_chest.put(world, key, x, y, z, iid, n, 0, 0) end
  end
  to_bag(item_db.RUNE, runes)
  to_bag(item_db.LEGENDARY_RUNE, lrunes)
  local kind = LOOT_KINDS[math.random(#LOOT_KINDS)]
  local name = kind == "cosmetic" and item_db.pick_cosmetic() or item_db.pick(kind, level)
  if name then loot_chest.put(world, key, x, y, z, name, 1, level, "legendary") end
  -- (0.15.160, owner: "I don't want these spawned monsters dropping anything other than the runes and the gear";
  -- 0.15.161: "it leaves the corpse with junk in it no one wants") the game's own loot in the body (it comes 1.5-3 s
  -- after the death) is taken out and thrown away at 2, 3 and 5 s; the body goes at CORPSE_S (8 s)
  for _, t in ipairs({ 120, 180, 300 }) do body_clear[#body_clear + 1] = { id = id, at = fx_steps + t } end
  -- (0.15.148) one line per kill, so it can be checked in the log (none when there are many: see the caller)
  return string.format("%d runes and %d legendary runes to %s, %s %s level %d legendary to the chest", runes, lrunes,
    killer and ("player entity " .. tostring(killer)) or "a chest (no killer known)", kind, tostring(name), level)
end

local function spawn_body(world, account, player, kind, level, what, count)
  if kind == "dummy" or kind == "duel" then drop_bodies_of(world, account, true) end
  spawn_queue = {}  -- a new spawn or Remove also stops a spawn under way
  if kind ~= "dummy" and kind ~= "duel" then  -- Remove: all of them, anywhere (0.15.136)
    local n, done = remove_all(world, account, player)
    guard_duelists(world)
    if not done then return string.format("Removing test monsters... (%d so far)", n) end
    return n > 0 and string.format("Removed %d test monster%s.", n, n == 1 and "" or "s") or "No test monsters to remove."
  end
  if kind == "dummy" then level = DUMMY_LEVEL end  -- (0.15.79, owner) it never hurts anyone; (0.15.129, owner) level 50
  local x, y, z = where(world, player)
  if not x then return "Your position is not known." end
  local fx, fz = 0, 1
  pcall(function()
    local q = world:get("CurrentTransform", player).transform.orientation
    local ax, az = 2 * (q.x * q.z + q.w * q.y), 1 - 2 * (q.x * q.x + q.y * q.y)
    local len = math.sqrt(ax * ax + az * az)
    if len > 0.01 then fx, fz = ax / len, az / len end
  end)
  local d0 = kind == "duel" and duelist(what) or dummy_of(what)
  -- (0.15.134, owner) several duelists: rows of up to 10, 2 m apart, from 3 m in front of the player
  count = kind == "duel" and math.max(1, math.min(MAX_DUELISTS, math.floor(tonumber(count) or 1))) or 1
  local jobs = {}
  local spots = scatter(count)
  for i = 1, count do
    local side, ahead = spots[i][1], spots[i][2]
    jobs[i] = (function(world)
  local d = d0
  if d[3] == RANDOM_KEY then d = RANDOM_POOL[math.random(#RANDOM_POOL)] end  -- a different one each time
  local guid, boss = d[3], d[4] == true
  if kind ~= "duel" and guid == DUMMY_GUID then guid = PLAYER_LIKE[math.random(#PLAYER_LIKE)] end  -- a random player-like body
  local sx, sz = x + fx * (3 + ahead) - fz * side, z + fz * (3 + ahead) + fx * side
  local ok, id = pcall(emf.spawn, world, guid, sx, y, sz, { ScaleComponent = { uniformScale = TAG_SCALE } })  -- the tag
  if not ok or not id or id == 0 then ok, id = pcall(emf.spawn, world, guid, sx, y, sz) end  -- without it
  d = { d[1], d[1] .. ": " .. d[2] }
  if not ok or not id or id == 0 then return "The game refused the spawn (see the server's emf_core.log)." end
  local b = { kind = kind, owner = account, session = emf.session(), rules = {}, guard = {}, what = d[2],
              level = level, boss = boss }
  bodies[id] = b
  to_ground(id, sx, y, sz)  -- (0.15.140) put on the ground a moment later
  if level then
    local okl, set = pcall(set_level, world, id, level)
    b.level = level
    if count == 1 then  -- (0.15.137) one line per monster only for a single one: logging is slow
      emf.log(string.format("experimental: the PvP test %s (entity %s) set to level %d: %s", kind, tostring(id), level,
        okl and (set and "done" or "it has no Level") or tostring(set)))
    end
  end
  if kind == "dummy" then
    pcall(function() world:get("Faction", id).faction = DUMMY_FACTION end)  -- at once
    local okr, r = pcall(emf.hit_rule, { from = id, cancel = true })  -- its own hits never land (0.15.134)
    calm[id] = true  -- (0.15.139) and it never goes for anyone
    if okr and r then b.rules.harmless = r else emf.log("experimental: the dummy's rule against its own hits was refused (" .. tostring(r) .. ")") end
  end
  if kind == "duel" then
    pcall(function() world:get("Faction", id).faction = DUEL_FACTION end)  -- at once, before its AI picks a target
  end
  if count == 1 then
    emf.log(string.format("experimental: a PvP test %s (entity %s%s%s) for player %s", kind == "duel" and "duelist" or "dummy", tostring(id),
      b.what and (", " .. b.what) or "", level and (", level " .. level) or "", tostring(player)))
  end
    end)
  end
  -- (0.15.137, production: 100 at once paused all of FlameKit, "the script ran longer than 250 ms") at most
  -- SPAWN_PER_STEP now, the rest a few at a time on the next server steps (spawn_tick)
  local first = math.min(count, SPAWN_PER_STEP)
  for i = 1, first do
    local why = jobs[i](world)
    if why then return why end
  end
  for i = first + 1, count do spawn_queue[#spawn_queue + 1] = { account = account, fn = jobs[i] } end
  if count > 1 then
    emf.log(string.format("experimental: %d PvP test %ss (%s%s) for player %s%s", count, kind == "duel" and "duelist" or "dumm",
      d0[3] == RANDOM_KEY and "random monsters" or (d0[1] .. ": " .. d0[2]),
      level and (", level " .. level) or "", tostring(player), count > first and string.format(" (%d now, the rest over the next steps)", first) or ""))
  end
  if kind == "duel" then guard_duelists(world) end  -- buildings and animals near them, at once
  if count > first then return string.format("Spawning %d monsters...", count) end
end

-- the rest of a big spawn, SPAWN_PER_STEP a server step; the shield follows once all are there
local function spawn_tick(world)
  if remove_left then  -- a Remove that ran out of time goes on, then tells its player
    local r = remove_left
    local n, done = remove_all(world, r.account, r.player, r.from, r.n)
    if done and tell_player then
      tell_player(world, r.player, r.account, n > 0 and string.format("Removed %d test monster%s.", n, n == 1 and "" or "s") or "No test monsters to remove.")
    end
  end
  if #spawn_queue == 0 then return end
  for _ = 1, math.min(SPAWN_PER_STEP, #spawn_queue) do
    local job = table.remove(spawn_queue, 1)
    local okj, why = pcall(job.fn, world)
    if not okj or why then emf.log("experimental: a queued test monster was not spawned: " .. tostring(why)) end
  end
  if #spawn_queue == 0 then guard_duelists(world) end
end

local body_pass = nil  -- a check of the test monsters under way (bodies_tick)
local function bodies_tick(world)
  if next(bodies) == nil then
    if duel_guard.objects then guard_duelists(world) end  -- the last one went: the rule goes
    return
  end
  body_steps = body_steps + 1
  if body_steps % SHIELD_STEPS == 0 then guard_duelists(world) end
  -- (0.15.140, owner: up to 5000) a check of all test monsters starts every 30 steps and, with many, goes on over the
  -- next steps within SCAN_BUDGET (a list of their ids, so new ones spawned meanwhile wait for the next check)
  if not body_pass then
    if body_steps % 30 ~= 0 then return end
    local list = {}
    for id in pairs(bodies) do list[#list + 1] = id end
    body_pass = { list = list, i = 1, killed = 0, gone = 0, away = 0, many = #list > 5 }
  end
  local pass, t0 = body_pass, now_s()
  local session = emf.session()
  local many = pass.many  -- (0.15.137) with many test monsters their AI is not logged (slow, and the log would flood)
  -- (0.15.140, owner) nor their deaths, bodies and going out of sight one by one: one summary line per check
  local killed, gone, away = pass.killed, pass.gone, pass.away
  local done = 0
  while pass.i <= #pass.list do
    if scan_over(t0, done) then
      pass.killed, pass.gone, pass.away = killed, gone, away
      return
    end
    local id = pass.list[pass.i]
    pass.i, done = pass.i + 1, done + 1
    local b = bodies[id]
    if b then
    local alive = false
    if b.session == session then
      pcall(function()
        local hp = world:get("NetworkHealth", id)
        local placed = world:position(id) ~= nil
        alive = placed and (hp == nil or hp.health > 0)
        if alive then b.seen_alive = true end
        -- (0.15.141, production log: the first 20 of every big spawn "killed" 0.3 s after the spawn, and their
        -- bodies removed 8 s later) a creature reads as dead until the game sets its health (EMF docs): it counts
        -- as killed only once it was seen alive
        if placed and hp and hp.health <= 0 and not b.seen_alive then alive = true end
        b.why = not placed and "no longer in the world (removed by the game)" or (hp and hp.health <= 0 and b.seen_alive and "killed") or nil
      end)
    end
    -- (measured: a duelist spawned right after a long move was "gone" half a second later and lived on, untracked; a
    -- far place may not be streamed in yet.) So a body counts as gone only when it was missing three checks in a row.
    if not alive then b.missing = (b.missing or 0) + 1 else b.missing = 0 end
    if not alive and b.why == "killed" and b.session == session then
      -- its body goes CORPSE_S seconds after the kill (it cannot be looted and the game never removes it)
      if not b.dead_at then
        b.dead_at = os.time()
        killed = killed + 1
        if b.kind == "duel" then  -- (0.15.142, owner) its loot on the ground
          local okd, what = pcall(drop_test_loot, world, id, b)
          -- (0.15.162, owner: "we dont want the corpse") (0.15.163: at the next check, 2 of 15 bodies stayed: the game
          -- changes a body soon after the death and it no longer read as killed) the body goes at once, in this check
          drop_body(world, id, true)
          gone = gone + 1
          if not many then emf.log(string.format("experimental: test monster %s loot: %s", tostring(id), okd and tostring(what) or ("error: " .. tostring(what)))) end
        end
        local when = b.kind == "duel" and "its body removed" or string.format("its body goes in %d s", CORPSE_S)  -- (0.15.163)
        if not many then emf.log(string.format("experimental: the PvP test %s (entity %s) was killed: %s", b.kind, tostring(id), when)) end
        local o = online[b.owner]
        if o and tell_player and not many then  -- (0.15.137) not a message per monster when there are many
          tell_player(world, o.entity, b.owner, b.kind == "duel" and "Your test monster was killed."
            or string.format("Your test monster was killed: its body goes in %d seconds.", CORPSE_S))
        end
      elseif os.time() - b.dead_at >= CORPSE_S then
        gone = gone + 1
        if not many then emf.log(string.format("experimental: the PvP test %s (entity %s): its body removed", b.kind, tostring(id))) end
        drop_body(world, id, true)
      end
    elseif not alive and b.missing >= 3 and b.session == session then
      -- (0.15.136) out of sight (far from every player, not loaded) is not gone: kept, so Remove still reaches it
      if not b.away_said then
        b.away_said = true
        away = away + 1
        if not many then emf.log(string.format("experimental: the PvP test %s (entity %s) is out of sight: %s (kept for Remove)", b.kind, tostring(id), b.why or "?")) end
      end
    elseif not alive and b.session ~= session then
      drop_body(world, id, false)
    elseif not alive then
      -- not seen this time: asked again in half a second
    elseif not many then
      -- what its AI does, logged when it changes (for finding out why a body does not fight)
      pcall(function()
        local ai = world:get("DynamicEnemy01BehaviorState", id)
        local st = world:get("SelectedTargets", id)
        local t = st and st.targets[1].targetEntityId
        if type(t) == "table" then t = t.id end
        local line = string.format("AI state %s, target %s", ai and tostring(ai.state) or "-", tostring(t))
        if b.level and not b.health_said then
          local hp = world:get("NetworkHealth", id)
          local lv = world:get("NetworkLevel", id)
          if hp and hp.healthMax and hp.healthMax > 0 then
            b.health_said = true
            emf.log(string.format("experimental: the PvP test %s (entity %s): health %s / %s, level %s", b.kind, tostring(id),
              tostring(hp.health), tostring(hp.healthMax), lv and tostring(lv.level or lv.value or "?") or "?"))
          end
        end
        if line ~= b.last then  -- logged when the state or target changes, with the threat table at that moment
          b.last = line
          local okl, al = pcall(F._aggro_line, world, id)
          emf.log(string.format("experimental: the PvP test %s (entity %s): %s, threat table [%s]", b.kind, tostring(id), line,
            okl and al or ("? " .. tostring(al))))
        end
      end)
    end
    if alive and b.kind == "dummy" then  -- the game may set a faction back: a dummy stays harmless
      pcall(function()
        local f = world:get("Faction", id)
        if f and tonumber(tostring(f.faction)) ~= DUMMY_FACTION then f.faction = DUMMY_FACTION end
      end)
    end
    if alive and b.kind == "duel" then
      pcall(function()
        local f = world:get("Faction", id)
        if f and tonumber(tostring(f.faction)) ~= DUEL_FACTION then f.faction = DUEL_FACTION end
      end)
    end
    end  -- if b
  end
  body_pass = nil
  if many and killed + gone + away > 0 then
    emf.log(string.format("experimental: test monsters: %d killed, %d bodies removed, %d out of sight (kept for Remove)", killed, gone, away))
  end
end

-- What the Debug section shows about your body.
body_of = function(account)
  for id, b in pairs(bodies) do
    if b.owner == account and not b.dead_at then return b.kind end  -- a killed one's body is on its way out
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
  if (msg.op == "home" or msg.op == "go" or msg.op == "wp") and wants(account, "pvp") then
    -- (0.15.119, owner) no fast travel out of a fight
    local v = view(account)
    v.note = "Fast travel is off while you are in PvP."
    return v
  end
  if msg.op == "home" or msg.op == "go" or msg.op == "wp" then
    local ok, why
    if msg.op == "home" then ok, why = pcall(go_home, world, entity)
    elseif msg.op == "wp" then ok, why = pcall(go_waypoint, world, entity, msg, account)
    else ok, why = pcall(go_near, world, entity, msg) end
    local v = view(account)
    v.note = not ok and "The move failed on this game version." or why
    if not ok then emf.log("experimental: go_home failed: " .. tostring(why)) end
    return v
  end
  if msg.op == "setwp" or msg.op == "clearwp" then  -- (0.15.75) a click on a minimap marker: the player's own waypoint
    local ok, why = pcall(function()
      local w = world:get("PlayerWaypoint", entity)
      if not w then error("the player has no waypoint component") end
      if msg.op == "clearwp" then
        wp_known[entity] = nil
        w.enabled = false
        emf.log(string.format("experimental: waypoint of player %s cleared from the minimap", tostring(entity)))
        return
      end
      local x, z = tonumber(msg.x), tonumber(msg.z)
      if not x or not z or x ~= x or z ~= z or x < -1000 or z < -1000 or x > 20000 or z > 20000 then error("not a place on the map") end
      local _, py = world:position(entity)
      local my = tonumber(msg.y)  -- (0.15.125) the marker's own height, from the minimap; else the player's
      if my and (my ~= my or my < -1000 or my > 5000) then my = nil end
      wp_known[entity] = my and { x = x, y = my, z = z } or nil
      w.waypointPosition.x = math.floor(x * 2 ^ 32)
      w.waypointPosition.y = math.floor((my or py or 0) * 2 ^ 32)
      w.waypointPosition.z = math.floor(z * 2 ^ 32)
      w.enabled = true
      emf.log(string.format("experimental: waypoint of player %s set from the minimap at %.0f %.0f", tostring(entity), x, z))
    end)
    if not ok then emf.log("experimental: the minimap waypoint failed: " .. tostring(why)) end
    local v = view(account)
    v.note = not ok and "The waypoint could not be set on this game version." or nil
    return v
  end
  if msg.op == "body" and (msg.kind == "dummy" or msg.kind == "duel") and wants(account, "pvp") then
    -- (0.15.119, owner: a monster spawned in a fight could throw it) no test monsters while PvP is on; Remove still works
    local v = view(account)
    v.note = "Test monsters cannot be spawned while you are in PvP."
    return v
  end
  if msg.op == "body" then
    local level = tonumber(msg.level)
    if level then level = math.max(1, math.min(MAX_LEVEL, math.floor(level))) end
    local what = type(msg.what) == "string" and msg.what or nil
    local ok, why = pcall(spawn_body, world, account, entity, msg.kind, level, what, msg.count)
    if not ok then emf.log("experimental: the PvP test body failed: " .. tostring(why)) end
    local v = view(account)
    v.note = not ok and "That did not work on this game version." or why
    return v
  end
  if msg.op == "set" and msg.key == "pvp" and msg.on ~= true and online[account] and online[account].pvp then
    -- (0.15.134, owner: no leaving PvP when close to death) not until PVP_LOCK_S seconds after the last hit by a PvP player
    local at = online[account].pvp_hit_at
    local left = at and PVP_LOCK_S - (os.time() - at) or 0
    if left > 0 then
      local v = view(account)
      v.note = string.format("You were attacked by a PvP player %d s ago: you can leave PvP in %d seconds.", PVP_LOCK_S - left, left)
      return v
    end
  end
  if msg.op == "set" and type(msg.key) == "string" then
    for _, s in ipairs(SWITCHES) do
      if s[1] == msg.key and held_by_pvp(account, s[1]) then
        local v = view(account)
        v.note = "Off while you are in PvP."
        return v
      end
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
        if s[1] == "pvp" and msg.on == true then  -- (0.15.119) a duelist spawned before goes (the harmless dummy stays)
          for id, b in pairs(bodies) do
            if b.owner == account and b.kind == "duel" then drop_body(world, id, true) end
          end
        end
        emf.log(string.format("experimental: player %s switched '%s' %s", tostring(entity), s[1], msg.on == true and "on" or "off"))  -- never the account in a log (a log may be shared)
        if s[4] then  -- everyone on the server is told (not for the glider: it changes nothing for others)
          local name = require("core.players").name(world, entity, "a player")  -- the character name first, as everywhere
          -- (0.15.139, owner) "Ninechars turned ON no shroud damage." / "... turned OFF ..."
          local line = string.format("%s turned %s %s.", name, msg.on == true and "ON" or "OFF", s[4]:lower())
          local colour = nil
          if s[1] == "pvp" then  -- (0.15.121, 0.15.122, owner) both in orange
            line, colour = name .. (msg.on == true and " joined PvP!" or " has left PvP."), "#ff9632"
          end
          -- (0.15.76, owner) to the Messages window of everyone with FlameKit (features/chat.lua), no longer the game's chat
          -- (0.15.139, owner) and in everyone's Notices window, orange, for about 10 seconds (PvP lines too)
          local sent, why = pcall(require("features.chat").announce, world, line, colour, { colour = "#ff9632", seconds = 10 })
          if not sent then emf.log("experimental: the announcement was not sent (" .. tostring(why) .. ")") end
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
-- from players, no damage to players). (0.15.128, owner: too little damage) Player-on-player hits are full damage now:
-- the rule that scaled them to 25% (0.15.65 to 0.15.127) is gone. Heals are never
-- matched by a rule (EMF: damage hits only), so a friend's heal still works.
-- The faction is saved with the world, so it is put back to 7 when PvP goes off, and any player without PvP who is
-- found with faction 1 (left over from a crash, a reload or a leave) is put back within a second.
local HIT_ALL, PLAYER_FACTION = 1, 7
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
local pet_rules = {}  -- (0.15.132) pet or farm animal entity -> its rule (guard_pets, below)
local function pvp_off_everywhere(world, why)
  refused.pvp = true
  for _, p in pairs(online) do
    p.pvp = nil
    pvp_unrule(p, "pvp_in")
    pvp_unrule(p, "pvp_out")
    pvp_unrule(p, "pvp_obj")
    pcall(function()
      local f, now = faction(world, p.entity)
      if f and now == HIT_ALL then f.faction = (p.pvp_was and p.pvp_was ~= HIT_ALL) and p.pvp_was or PLAYER_FACTION end
    end)
    p.pvp_was, p.pvp_logged = nil, nil
  end
  if pvp_scale_rule then pcall(emf.hit_rule_remove, pvp_scale_rule) end
  pvp_scale_rule = nil
  for _, r in pairs(pet_rules) do pcall(emf.hit_rule_remove, r) end
  pet_rules = {}
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
local hunters = {}   -- monster entity -> { PvP player entity -> distance in m }, rebuilt every AGGRO_STEPS
local target_broken = false


-- Measured next (02:18): with the target written, the duelist kept target 1 but stayed Idle/Roaming, never Combat.
-- Its threat table (DynamicAggro, 6 slots of AggroTarget) keeps each candidate's faction (+80), state (Alarmed = 3)
-- and aggro; the AI picks a fight from the Alarmed slots. So the PvP player is also put in a slot as Alarmed with
-- faction 7 (Player, as the picker expects) and aggro 100.
-- (0.15.69, owner: several PvP players near one monster) Every PvP player within AGGRO_R goes into the monster's table,
-- each in their own slot; the game's picker chooses between the Alarmed slots by aggro (hits and damage raise it,
-- time lowers it; it switches at most every 2-2.5 s), as it does for normal players. FlameKit gives a new slot a
-- starting aggro by distance (closest highest) and afterwards only keeps it from falling below AGGRO_FLOOR while the
-- player is in range, so the game's own aggro decides. The target is no longer forced.
local ALARMED, AGGRO_FLOOR = 3, 20
local function start_aggro(dist) return math.max(40, 100 - 3 * dist) end

local function eid(v)
  if type(v) == "table" then return v.id end
  return v
end

local function alarm(world, monster, player, dist)
  local ag = world:get("DynamicAggro", monster)
  if not ag then return end
  local slot, fresh
  for i = 1, 6 do
    if eid(ag.targets[i].entityId) == player and tonumber(tostring(ag.targets[i].state)) ~= 0 then slot = ag.targets[i] break end
  end
  if not slot then  -- a free slot only: the game's own candidates (other monsters, villagers) are never pushed out
    for i = 1, 6 do
      if tonumber(tostring(ag.targets[i].state)) == 0 then slot, fresh = ag.targets[i], true break end
    end
  end
  if not slot then return end
  set_id(slot, "entityId", player)
  set_id(slot, "targetId", player)
  if tonumber(tostring(slot.state)) ~= ALARMED then slot.state = ALARMED end
  if tonumber(tostring(slot.faction)) ~= PLAYER_FACTION then slot.faction = PLAYER_FACTION end
  if fresh then
    slot.aggro = start_aggro(dist or AGGRO_R)
  elseif slot.aggro < AGGRO_FLOOR then
    slot.aggro = AGGRO_FLOOR
  end
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
    for monster, near in pairs(hunters) do
      for player, dist in pairs(near) do alarm(world, monster, player, dist) end
    end
  end)
  if not ok then
    target_broken = true
    emf.log("experimental: PvP: a monster's threat table cannot be written on this game version (" .. tostring(err) .. ")")
  end
end

local aggro_i = 1  -- (0.15.137) where pvp_aggro's pass over the world goes on
local function pvp_aggro(world, players)
  if aggro_i == 1 then hunters = {} end  -- a new pass
  if aggro_broken or #players == 0 then hunters, aggro_i = {}, 1 return end
  local sent = 0
  local ok, err = pcall(function()
    local t0, done, list = now_s(), 0, world:entities()
    local i = aggro_i
    aggro_i = 1
    while i <= #list do
      if scan_over(t0, done) then aggro_i = i break end
      local e = list[i]
      i, done = i + 1, done + 1
      if not bodies[e] and has(world, "DynamicEnemy01BehaviorState", e) then  -- test monsters fight anyway
        local _, n = faction(world, e)
        if n and n ~= 7 and n ~= 8 and n ~= 11 then
          local hp = world:get("NetworkHealth", e)
          local x, _, z = world:position(e)
          if x and (hp == nil or hp.health > 0) then
            for _, pl in ipairs(players) do
              local px, _, pz = world:position(pl)
              if px and (px - x) ^ 2 + (pz - z) ^ 2 < AGGRO_R * AGGRO_R then
                hunters[e] = hunters[e] or {}
                hunters[e][pl] = math.sqrt((px - x) ^ 2 + (pz - z) ^ 2)
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

-- (0.15.132, owner: pets and farm animals such as birds took damage from PvP) A PvP player has faction 1 (HitAll), so
-- their hits land on pets and farm animals too. While anyone has PvP on, every pet (IsTame), farm animal (faction 12)
-- and player ally that is not a villager (faction 11 without NpcState) within PET_R m of a PvP player gets a rule:
-- no damage from players. Looked for every PET_STEPS steps; at most PET_MAX rules (EMF has 64 for all of FlameKit).
-- Wild animals stay huntable. Villagers already took no hits from a HitAll player (0.15.70).
local PET_R, PET_MAX, PET_STEPS = 40, 24, 120
local pets_full_said = false

local function pet_like(world, id)
  if has(world, "IsTame", id) then return true end
  local ok, f = pcall(world.get, world, "Faction", id)
  local n = ok and f and tonumber(tostring(f.faction))
  return n == 12 or (n == 11 and not has(world, "NpcState", id))
end

local pets_scan = { i = 1, keep = {} }  -- where guard_pets' pass over the world is
local function guard_pets(world, any)
  if not any then
    for e, r in pairs(pet_rules) do pcall(emf.hit_rule_remove, r) end
    pet_rules = {}
    pets_scan = { i = 1, keep = {} }
    return
  end
  local centres = {}
  for _, p in pairs(online) do
    if p.pvp then
      local okw, x, _, z = pcall(where, world, p.entity)
      if okw and x then centres[#centres + 1] = { x, z } end
    end
  end
  local n = 0
  for _ in pairs(pet_rules) do n = n + 1 end
  -- (0.15.137) a pass over the world may take several calls: it goes on where the last call stopped, and rules are
  -- taken away only at the end of a whole pass
  local keep = pets_scan.keep
  local list = world:entities()
  local t0, done, partial = now_s(), 0, false
  local i = pets_scan.i
  while i <= #list do
    if scan_over(t0, done) then partial = true break end
    local e = list[i]
    i, done = i + 1, done + 1
    local okp, ex, _, ez = pcall(world.position, world, e)
    if okp and ex then
      local near = false
      for _, c in ipairs(centres) do
        if (ex - c[1]) ^ 2 + (ez - c[2]) ^ 2 < PET_R * PET_R then near = true break end
      end
      if near then
        local oka, account = pcall(world.account, world, e)
        if not (oka and account) and not bodies[e] and pet_like(world, e) then
          keep[e] = true
          if not pet_rules[e] and n < PET_MAX then
            local okr, r = pcall(emf.hit_rule, { from = "players", to = e, cancel = true })
            if okr and r then pet_rules[e], n = r, n + 1 end
          end
        end
      end
    end
  end
  if partial then
    pets_scan.i = i
  else
    for e, r in pairs(pet_rules) do
      if not keep[e] then
        pcall(emf.hit_rule_remove, r)
        pet_rules[e] = nil
      end
    end
    pets_scan = { i = 1, keep = {} }
  end
  if n >= PET_MAX and not pets_full_said then
    pets_full_said = true
    emf.log(string.format("experimental: PvP: only %d pets and farm animals near PvP players are protected (more are around)", PET_MAX))
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
        -- (0.15.130, owner) a PvP player's hits never damage buildings or placed objects (EMF "objects")
        local okb, whyb = pvp_rule(p, "pvp_obj", { from = p.entity, to = "objects", cancel = true })
        if not okb and not p.obj_said then
          p.obj_said = true
          emf.log("experimental: PvP: the rule protecting buildings was refused (" .. tostring(whyb) .. ")")
        end
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
        pvp_unrule(p, "pvp_obj")
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
    if pvp_scale_rule then  -- (0.15.128) full damage: one left from before a reload goes
      pcall(emf.hit_rule_remove, pvp_scale_rule)
      pvp_scale_rule = nil
    end
  end)
  if not ok then pvp_off_everywhere(world, tostring(err)) return end
  if any and (pvp_steps % AGGRO_STEPS == 0 or aggro_i > 1) then  -- (0.15.137) a pass cut short goes on next step
    local players = {}
    for _, p in pairs(online) do if p.pvp then players[#players + 1] = p.entity end end
    pvp_aggro(world, players)
  elseif not any then
    hunters = {}
  end
  if any then hunt(world) end
  if pvp_steps % PET_STEPS == 1 or pets_scan.i > 1 or (not any and next(pet_rules)) then
    local okg, errg = pcall(guard_pets, world, any)
    if not okg then emf.log("experimental: PvP: protecting pets failed: " .. tostring(errg)) end
  end
end

function F.tick(world)
  fx_steps = fx_steps + 1
  if world:is_server() then pcall(body_clear_tick, world) end  -- (0.15.161) test monster bodies emptied
  if world:is_server() then pcall(loot_chest.tick, world, bag) end  -- (0.15.154) empty loot chests go
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
  spawn_tick(world)
  ground_tick(world)
  calm_tick(world)
  bodies_tick(world)
  retry_tick(world)
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
local duel_what, duel_level = RANDOM_KEY, 1  -- (0.15.139) Random is the default  -- the Debug section's duelist choice, this session (0.15.70)
local duel_count = 1  -- (0.15.134, owner) how many duelists one Spawn makes
local dummy_what = DUMMY_GUID               -- and the dummy's (0.15.81)
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

-- (0.15.109, owner) Has the player with this account PvP on right now? (where the world is hosted; for the party list)
-- tests only: the most entities one scan looks at
function F._scan_max(n) SCAN_MAX = n end
function F._ground() return ground_n, #ground_q - ground_head + 1 end

-- tests only: end a player's PvP cool-down
function F._pvp_hit_reset(account)
  if online[tostring(account)] then online[tostring(account)].pvp_hit_at = nil end
end

-- tests only: put another player into (or out of) the online list, with PvP on or off
function F._online_test(entity, account, pvp)
  if not account then
    for acc, p in pairs(online) do if p.entity == entity then drop_rules(p); online[acc] = nil end end
    return
  end
  online[account] = { entity = entity, rules = {}, seen = os.time() + 3600, pvp = pvp or nil }
end

-- (0.15.134, owner) the seconds left of a player's PvP cool-down (0: none), for the Party list
function F.pvp_lock_left(account)
  local p = account and online[tostring(account)]
  if not (p and p.pvp and p.pvp_hit_at) then return 0 end
  return math.max(0, PVP_LOCK_S - (os.time() - p.pvp_hit_at))
end

function F.pvp_of(account)
  return account ~= nil and is_on(tostring(account), "pvp") == true
end

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

-- (0.15.125) a line under the buttons of one player's Experimental window, from a teleport's answer (server world)
tell_player = function(world, player, account, text)
  local mine = kit.is_host() and emf.local_player() == player
  if mine then
    note = text
    return
  end
  local v = view(tostring(account))
  v.note = text
  pcall(emf.net.send_to, world, player, CHANNEL, emf.json.encode(v))
end

-- The Debug section at the bottom of the tab: the test players (features/party.lua) and FlameKit's log level
-- (debug.txt: off, normal, full; the same as Ctrl+Shift+F12 in the game). Keys "dbg:...".
-- (0.15.124, owner) the update channel: update_channel.txt in FlameKit's folder, "test" for the development versions
-- (dist-test), anything else or no file for the released ones (dist). The DLL's updater reads it at every look.
local function dev_channel()
  local f = io.open(emf.dir .. "\\update_channel.txt", "r")
  if not f then return false end
  local t = f:read("a") or ""
  f:close()
  return t:sub(1, 4) == "test"
end

local function debug_rows(world, rows)
  rows[#rows + 1] = { separator = true }
  rows[#rows + 1] = { heading = "Debug" }
  for _, r in ipairs(require("features.party").test_rows(world)) do
    if r.button then r.button = "dbg:test:" .. r.button end
    rows[#rows + 1] = r
  end
  -- (0.15.116, owner) made-up players on the PvP Leaderboard, to see how it looks with data (this game only)
  local fake = require("features.leaderboard").fake_on()
  rows[#rows + 1] = { button = "dbg:fakeboard", text = (fake and "On    " or "Off   ") .. "Test leaderboard data", selected = fake,
    tooltip = "Fills your PvP Leaderboard with made-up players (only in your game; the server's real board is not touched). "
      .. "Switch it off to see the real board again." }
  local level = kit.debug_level(true)
  rows[#rows + 1] = { text = "FlameKit's log level (Ctrl+Shift+F12 in the game also switches it):" }
  for i, l in ipairs({ { "off", "Off", "Errors and warnings only" }, { "normal", "Normal", "Also what happens: windows, updates, clicks" },
                       { "full", "Full", "Also every detail: for finding a problem" } }) do
    rows[#rows + 1] = { button = "dbg:log:" .. l[1], text = l[2], selected = level == l[1], same_line = i > 1, tooltip = l[3] }
  end
  rows[#rows + 1] = { dim = true, text = "The logs are in emf\\mods\\flamekit\\logs in the game's folder (the last 10 games)." }
  rows[#rows + 1] = { button = "dbg:openlogs", text = "Open log folder", tooltip = "Opens FlameKit's log folder in Explorer." }  -- (0.15.106)
  local dev = dev_channel()
  rows[#rows + 1] = { text = "Updates:" }
  rows[#rows + 1] = { button = "dbg:chan:stable", text = "Stable", selected = not dev,
    tooltip = "Released versions only: tested and the same for everyone. Recommended. Switching back from Development keeps the "
      .. "version you have until a newer stable one comes out." }
  rows[#rows + 1] = { button = "dbg:chan:test", text = "Development", selected = dev, same_line = true,
    tooltip = "The very latest development versions, as soon as they are made: new things first, but they may have bugs. "
      .. "FlameKit looks for one every minute, on both channels." }
  return rows
end

local function my_view(world)
  if hosting(world) then
    load_saved()
    local account = me(world)
    return account and view(account)
  end
  return shown
end

-- The F4 tab (0.15.74, owner): the switches but PvP, and the Debug section (test players, log level). Fast Travel, PvP
-- and the test bodies are in FlameKit's Experimental window (F.window_rows below).
local function panel_rows(world)
  local v = my_view(world)
  local rows = {
    { color = "#ffb060", text = "Experimental: these bend the game's rules for you only. Every player has their own." },
    { dim = true, text = "Fast Travel, PvP and the test monsters are in the Experimental window (F4 > Windows shows and hides it; "
      .. "its key is a setting)." },
  }
  if not v then
    rows[#rows + 1] = { dim = true, text = (hosting(world) or peer() ~= 0) and "Asking the server..."
      or "This server does not run FlameKit (or not this version), so there is nothing to switch here." }
    return debug_rows(world, rows)
  end
  rows[#rows + 1] = { separator = true }
  for _, s in ipairs(SWITCHES) do
    if s[1] ~= "pvp" then
      local on = v[s[1]] == true
      local text = (on and "On    " or "Off   ") .. s[2]
      if v[s[1] .. "_pvp"] then
        rows[#rows + 1] = { button = "sw:" .. s[1], text = "Off   " .. s[2] .. " (off in PvP)", disabled = true,
          tooltip = "Off while you are in PvP, so nobody can cheat in a fight. It comes back when you switch PvP off." }
      else
        if v[s[1] .. "_dead"] then text = text .. " (not working on this game version)" end
        rows[#rows + 1] = { button = "sw:" .. s[1], text = text, selected = on, tooltip = TIPS[s[1]] }
      end
    end
  end
  return debug_rows(world, rows)
end

-- FlameKit's Experimental window (0.15.74, owner): a pinned window that stays on screen while playing. Fast Travel at
-- the top, then PvP, then the test bodies (the dummy and the duelist). Drawn by the DLL from ui_exp.dat
-- (features/native_ui.lua); its clicks come back to F.click like the tab's.
-- Is the PvP Leaderboard's window shown? The DLL keeps it in ui_layout.txt: "board <x> <y> <w> <collapsed> <hidden> ...";
-- no line yet: hidden (it starts hidden).
local function board_shown()
  local f = io.open(emf.dir .. "\\ui_layout.txt", "r")
  if not f then return false end
  local text = f:read("a") or ""
  f:close()
  local hidden = text:match("\nboard %-?%d+ %-?%d+ %-?%d+ %d+ (%d+)") or text:match("^board %-?%d+ %-?%d+ %-?%d+ %d+ (%d+)")
  return hidden == "0"
end

function F.window_rows(world)
  local v = my_view(world)
  if not v then
    return { { dim = true, text = (hosting(world) or peer() ~= 0) and "Asking the server..."
      or "This server does not run FlameKit (or not this version)." } }
  end
  local rows = {}
  -- (0.15.119, owner) no fast travel out of a fight: greyed out while PvP is on (the server refuses it too)
  local in_pvp = v.pvp == true
  local function travel_tip(tip)
    return in_pvp and "Off while you are in PvP, so nobody can escape a fight. It comes back when you switch PvP off." or tip
  end
  rows[#rows + 1] = { heading = "Fast Travel" }
  rows[#rows + 1] = { button = "home", text = "Flame Altar", disabled = in_pvp or nil,
    tooltip = travel_tip("Takes you to the nearest flame altar at once. Works where the map's fast travel does not: inside the shroud, in lava, while stuck.") }
  rows[#rows + 1] = { button = "spire", text = "Ancient Spire", same_line = true, disabled = in_pvp or nil,
    tooltip = travel_tip("Takes you to the nearest Ancient Spire on your map, unlocked or not. Works inside the shroud too.") }
  rows[#rows + 1] = { button = "waypoint", text = "Map Waypoint", same_line = true, disabled = in_pvp or nil,
    tooltip = travel_tip("Takes you straight to the waypoint you set on your map, onto the ground there. Fall damage is off for 30 seconds "
      .. "after the move, in case there is no ground right at the waypoint.") }
  rows[#rows + 1] = { heading = "PvP" }
  local on = v.pvp == true
  rows[#rows + 1] = { button = "sw:pvp", text = (on and "On    " or "Off   ") .. "PvP (free-for-all)" .. (v.pvp_dead and " (not working)" or ""),
    selected = on, tooltip = TIPS.pvp }
  -- (0.15.96, owner) the PvP Leaderboard's window (DLL), so players find it
  local board_key = tostring(kit.setting("board_window_key", "F5") or "")
  rows[#rows + 1] = { button = "board", text = "Leaderboard", selected = board_shown(),
    tooltip = "Shows or hides the PvP Leaderboard" .. (board_key ~= "" and (" (" .. board_key .. ")") or "") .. ". It ranks players by their kills of other players and shows how often each one was killed by another player." }
  rows[#rows + 1] = { heading = "Test monsters" }
  -- every monster under its group's heading, bosses in orange (0.15.73); `first` is put on top under its own heading
  local function monster_options(prefix, chosen, first)
    local options = {}
    if first then
      if first[1] ~= first[2] then options[#options + 1] = { heading = true, text = first[1] } end  -- not "Random" twice
      options[#options + 1] = { key = prefix .. first[3], text = first[2], selected = first[3] == chosen }
    end
    for _, g in ipairs(MONSTER_GROUPS) do
      options[#options + 1] = { heading = true, text = g }
      for _, m in ipairs(MONSTERS) do
        if m[1] == g then
          options[#options + 1] = { key = prefix .. m[3], text = m[2] .. (m[4] and "  (boss)" or ""),
            color = m[4] and "#ffb060" or nil, selected = m[3] == chosen }
        end
      end
    end
    return options
  end
  -- the dummy (0.15.81, owner: chosen like the duelist): never hurts anyone, level DUMMY_LEVEL
  local in_pvp = v.pvp == true  -- (0.15.119, owner) no spawning while PvP is on: it could throw a fight
  local no_spawn = "Off while you are in PvP, so nobody can throw a fight with a monster. Spawn the dummy before you switch PvP on."
  local dpick = dummy_of(dummy_what)
  rows[#rows + 1] = { options = monster_options("dbg:dwhat:", dpick[3], DUMMY_PLAIN), text = dpick[1] .. ": " .. dpick[2],
    color = dpick[4] and "#ffb060" or nil, disabled = in_pvp or nil,
    tooltip = in_pvp and no_spawn or "The dummy never hurts anyone and is level " .. DUMMY_LEVEL .. ": beat on it as long as you like. Anyone can hit it, PvP on or off." }
  rows[#rows + 1] = { button = "dbg:body:dummy", text = "Spawn Dummy", selected = v.body == "dummy", disabled = in_pvp or nil,
    tooltip = in_pvp and no_spawn or "Spawns the dummy (" .. dpick[2] .. ") at level " .. DUMMY_LEVEL .. " 3 m in front of you. Anyone can hit it, PvP on or off. It stands "
      .. "still and never fights back. It replaces your test monster." }
  rows[#rows + 1] = { button = "dbg:body:none", text = "Remove", same_line = true,
    tooltip = "Removes all your test monsters, wherever they are in the world, and any test monster nobody keeps any more." }
  rows[#rows + 1] = { separator = true }
  -- the duelist (0.15.73: one drop-down; the level with < > and five quick picks)
  local pick = duelist(duel_what)
  rows[#rows + 1] = { options = monster_options("dbg:what:", pick[3], RANDOM_PICK),
    text = pick[3] == RANDOM_KEY and "Random" or (pick[1] .. ": " .. pick[2]), color = pick[4] and "#ffb060" or nil,
    disabled = in_pvp or nil, tooltip = in_pvp and no_spawn or "The monsters fight everyone and everything with full damage, PvP on or off: players, pets, animals, villagers and buildings. Spawn them away from bases." }
  local lvl_tip = "Its level: the game sets its health and damage from it (level 50: about 6700 health, level 100: about 53000)."
  rows[#rows + 1] = { label = true, text = "Level" }
  -- (0.15.136, owner: clutter) only the five picks; the < > stepper and the number between them are gone
  for _, q in ipairs({ 1, 25, 50, 75, 100 }) do
    rows[#rows + 1] = { button = "dbg:lvlset:" .. q, text = tostring(q), same_line = true, selected = duel_level == q,
      disabled = in_pvp or nil, tooltip = lvl_tip }
  end
  rows[#rows + 1] = { label = true, text = "Quantity" }  -- (0.15.134, owner; 0.15.136: "Quantity", 1-200; 0.15.139: 500, 1000)
  for _, c in ipairs(DUEL_COUNTS) do
    rows[#rows + 1] = { button = "dbg:cnt:" .. c, text = tostring(c), same_line = true, selected = duel_count == c,
      disabled = in_pvp or nil, tooltip = "How many monsters one Spawn makes, in rows of up to 10." }
  end
  rows[#rows + 1] = { button = "dbg:body:duel", text = "Spawn Monsters",
    selected = v.body == "duel", disabled = in_pvp or nil,
    tooltip = in_pvp and no_spawn or "Spawns " .. (duel_count > 1 and (duel_count .. " of ") or "") .. pick[2] .. " at level " .. duel_level .. " 3 m in front of you. It attacks everyone with full damage, PvP on "
      .. "or off, and anything near it, buildings included: spawn it away from bases. It replaces your test body." }
  rows[#rows + 1] = { button = "dbg:body:none", text = "Remove", same_line = true,
    tooltip = "Removes all your test monsters, wherever they are in the world, and any test monster nobody keeps any more." }
  if note then rows[#rows + 1] = { color = "#ff8060", text = note } end
  return rows
end

function F.panel(world)
  return panel_rows(world)
end

-- (0.15.75) The minimap's waypoint click (features/native_ui.lua, "wp x,z" or "wp clear"): sent to the server, which
-- writes the player's PlayerWaypoint (the game's own waypoint: its map and compass show it, Map Waypoint goes there).
function F.minimap_waypoint(world, arg)
  local msg
  if arg == "undiscovered" then  -- (0.15.127, owner) a "?" place on the minimap: no waypoint there
    kit.note("Waypoints can only be set on places you have discovered.", "#ff9632", true)
    return
  end
  if arg == "clear" then
    msg = { op = "clearwp" }
  else
    -- "x,z", or "x,y,z" with the marker's height (0.15.125)
    local x, y, z = tostring(arg):match("^(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+)$")
    if not x then
      x, z = tostring(arg):match("^(%-?[%d%.]+),(%-?[%d%.]+)$")
      if not x then return end
    end
    msg = { op = "setwp", x = tonumber(x), y = y and tonumber(y) or nil, z = tonumber(z) }
  end
  if hosting(world) then
    local account, player = me(world)
    if account then note = handle(world, account, player, msg).note end
  else
    ask(msg)
  end
end

function F.click(world, key)
  if key:sub(1, 9) == "dbg:test:" then return require("features.party").set_test(world, key:sub(10)) end
  if key == "dbg:what:" .. RANDOM_KEY then duel_what = RANDOM_KEY return end
  local what = key:match("^dbg:what:([%x%-]+)$")
  if what then duel_what = duelist(what)[3] return end
  local dwhat = key:match("^dbg:dwhat:([%x%-]+)$")
  if dwhat then dummy_what = dummy_of(dwhat)[3] return end
  local step = key:match("^dbg:lvl:(%-?%d+)$")
  if step then duel_level = math.max(1, math.min(MAX_LEVEL, duel_level + tonumber(step))) return end
  local set = key:match("^dbg:lvlset:(%d+)$")
  if set then duel_level = math.max(1, math.min(MAX_LEVEL, tonumber(set))) return end
  local cset = key:match("^dbg:cnt:(%d+)$")
  if cset then duel_count = math.max(1, math.min(MAX_DUELISTS, tonumber(cset))) return end
  local kind = key:match("^dbg:body:(%a+)$")
  if kind then
    note = nil
    local msg = { op = "body", kind = kind, what = kind == "duel" and duel_what or kind == "dummy" and dummy_what or nil,
      level = kind == "duel" and duel_level or nil, count = kind == "duel" and duel_count or nil }
    if hosting(world) then
      local account, player = me(world)
      if account then note = handle(world, account, player, msg).note end
    else
      ask(msg)
    end
    return
  end
  if key == "dbg:fakeboard" then
    local lb = require("features.leaderboard")
    lb.set_fake(world, not lb.fake_on())
    return
  end
  local chan = key:match("^dbg:chan:(%a+)$")
  if chan == "stable" or chan == "test" then
    local f = io.open(emf.dir .. "\\update_channel.txt", "w")
    if f then
      f:write(chan == "test" and "test\n" or "stable\n")
      f:close()
    end
    local r = io.open(emf.dir .. "\\ui_update_check.request", "w")  -- the DLL looks for updates at once (HudLayer)
    if r then
      r:write("1")
      r:close()
    end
    kit.log("update channel: " .. (chan == "test" and "development (dist-test)" or "stable (dist)"))
    return
  end
  if key == "dbg:openlogs" then  -- FlameKit's DLL opens Explorer on the logs when this file appears (HudLayer)
    local f = io.open(emf.dir .. "\\ui_open_logs.request", "w")
    if f then
      f:write("1")
      f:close()
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
  if key == "board" then  -- the DLL shows or hides the PvP Leaderboard (BoardLayer) when this file appears
    local f = io.open(emf.dir .. "\\ui_board_toggle.request", "w")
    if f then
      f:write("1")
      f:close()
    end
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
    if view(account)[name .. "_pvp"] then return end  -- held off by PvP
    note = handle(world, account, player, { op = "set", key = name, on = not view(account)[name] }).note
  elseif shown then
    if shown[name .. "_pvp"] then return end  -- held off by PvP
    shown[name] = not shown[name]  -- at once on screen; the server's answer follows
    ask({ op = "set", key = name, on = shown[name] })
  end
end

function F.setup(k)
  kit = k
  -- A console test for PvP (server console or emf\commands.txt, output in emf_core.log), so it can be tried without a
  -- second player at the keyboard: "flamekit.pvptest <player entity>" switches PvP on for that player, makes them
  -- unable to die (an EMF hit rule, min_health 1: hits still land and show) and spawns a duelist 3 m in front of them;
  -- "flamekit.pvptest off" takes all of it back. The duelist's AI lines in the log tell whether it fights.
  local test = nil  -- { account, player, rule }
  pcall(emf.command, "duelist", "<player entity> [level|off] [template GUID from core/monsters.lua]: a duelist 3 m in front of that player (PvP on or off, it fights)",
    kit.guard(F, function(world, args)
      if not world:is_server() then emf.reply("Only on the server world.") return end
      local player, level = tonumber(args[1]), tonumber(args[2])
      local ok, account = pcall(world.account, world, player)
      if not player or not ok or not account then emf.reply("duelist: no player with entity " .. tostring(args[1])) return end
      if args[2] == "off" then
        drop_bodies_of(world, tostring(account), true)
        emf.reply("duelist: removed")
        return
      end
      -- at most MAX_LEVEL (the game itself would set anything above 105 back to 105)
      if level then level = math.max(1, math.min(MAX_LEVEL, math.floor(level))) end
      local why = spawn_body(world, tostring(account), player, "duel", level, args[3])
      emf.reply("duelist: " .. (why or "spawned"))
    end, "the duelist command"))
  pcall(emf.command, "pvptest", "<player entity>|off: PvP on for that player (who cannot die meanwhile) and a duelist in front of them",
    kit.guard(F, function(world, args)
      if not world:is_server() then emf.reply("Only on the server world.") return end
      load_saved()
      if args[1] == "off" then
        if test then
          if online[test.account] then online[test.account].pvp = nil end
          drop_bodies_of(world, test.account, true)
          pcall(emf.hit_rule_remove, test.rule)
          emf.log("experimental: pvptest: off for player " .. tostring(test.player))
          test = nil
        end
        emf.reply("pvptest: off")
        return
      end
      local player = tonumber(args[1])
      local ok, account = pcall(world.account, world, player)
      if not player or not ok or not account then emf.reply("pvptest: no player with entity " .. tostring(args[1])) return end
      account = tostring(account)
      seen(account, player)
      online[account].pvp = true
      local okr, rule = pcall(emf.hit_rule, { kinds = "all", to = player, min_health = 1 })
      test = { account = account, player = player, rule = okr and rule or nil }
      pvp(world)
      local why = spawn_body(world, account, player, "duel")
      emf.log(string.format("experimental: pvptest: PvP on for player %s (cannot die: %s), duelist: %s", tostring(player),
        tostring(test.rule ~= nil), why or "spawned"))
      emf.reply("pvptest: on")
    end, "the pvptest command"))
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
    for i = #spawn_queue, 1, -1 do  -- (0.15.137) the rest of their spawn is not made
      if spawn_queue[i].account == account then table.remove(spawn_queue, i) end
    end
  end, "a player leaving"))
  emf.log("experimental: scans over the world stop after " .. SCAN_MAX .. " entities" .. (clock and string.format(" or %d ms", SCAN_BUDGET * 1000) or " (os.clock is not there: no time limit)"))
  -- (0.15.136, owner) a player who dies with PvP on is out of PvP (the cool-down does not apply) until they switch it
  -- on again. A rule of the free-for-all mode only (owner: a future team mode may not want it): PVP_MODE.
  pcall(emf.on_player_died, kit.guard(F, function(world, d)
    if PVP_MODE ~= "ffa" or not d or not d.account then return end
    local account = tostring(d.account)
    local o = online[account]
    if not (o and o.pvp) then return end
    o.pvp, o.pvp_hit_at = nil, nil
    emf.log(string.format("experimental: player %s died with PvP on: PvP off", tostring(d.player)))
    -- killed by another player: the kill line has told everyone already (leaderboard.lua); otherwise say it here
    local by_player = false
    if d.killer and d.killer ~= 0 and d.killer ~= d.player then
      local oka, acc = pcall(world.account, world, d.killer)
      by_player = oka and acc ~= nil
    end
    if not by_player then
      local name = require("core.players").name(world, d.player, "a player")
      pcall(require("features.chat").announce, world, name .. " has left PvP.", "#ff9632")
    end
    if tell_player then tell_player(world, d.player, account, "You died: PvP is off. Switch it on again to fight.") end
  end, "a player's death"))
  -- (0.15.134) hits between PvP players start the PvP cool-down of the one hit (see PVP_LOCK_S)
  pcall(emf.on_hit, kit.guard(F, function(world, hit)
    if not hit or hit.kind ~= "hit" or not hit.attacker or hit.attacker == 0 or hit.attacker == hit.target then return end
    -- (0.15.154) a test monster remembers the last player who hit it: its runes go into that player's bag
    if bodies[hit.target] then
      for _, p in pairs(online) do
        if p.entity == hit.attacker then bodies[hit.target].last_hitter = hit.attacker break end
      end
    end
    -- (0.15.136, owner: heals, buffs and regeneration reset it) only damage counts: a hit that did damage (also over
    -- time, from a debuff), or an attack that was blocked or parried; never a heal or a hit of 0 (a buff)
    local amount = tonumber(hit.amount) or 0
    if hit.healing or amount < 0 then return end
    if amount == 0 and not (hit.blocked or hit.parried) then return end
    local pa, pt
    for _, p in pairs(online) do
      if p.entity == hit.attacker then pa = p elseif p.entity == hit.target then pt = p end
    end
    if pa and pt and pa.pvp and pt.pvp then pt.pvp_hit_at = os.time() end
  end, "a hit"))
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
