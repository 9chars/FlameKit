-- features/spawn_nodes.lua (0.15.476, owner 2026-11-23 10:53 "I'd like a way to place down "nodes" around the map that
-- could be configured to spawn monsters periodically based on how I set it up", 10:53 admins only, "maybe it would be
-- used as part a larger "raid" type system for spawning monsters against peoples bases", 11:03 "just go to the location
-- I want and click add node", 11:06 "can you group the nodes together also such that when a trigger is activated, all
-- the nodes work together? ... control the monster group type ... (foggers, vukah, scavengers, undead, etc) ... set it
-- to random ... multiple different groups with multiple different nodes", 11:08 "all 5 of those triggers would be good
-- ... lets go ahead and build it"): the Spawn Nodes tab, for FlameKit admins.
--
-- A NODE is only a saved place (x, y, z) that belongs to a GROUP; nothing of it is in the game world, so players cannot
-- see or touch it. Only the monsters it spawns are real (ordinary monsters of the game, not test monsters).
-- A GROUP has: a name ("Group 1"), on/off, a monster type (one of core/monsters.lua's groups, Random, or (0.15.477) Bosses),
-- a trigger, and a run: `waves` waves `wave_gap` seconds apart, each wave `per_wave` monsters at every node of the
-- group, never more than `max_alive` alive from one node; then `cooldown` minutes before the trigger can fire again.
-- TRIGGERS: manual ("Start now" only), timer (every `timer_min` to `timer_max` minutes, a random time in between),
-- trip wire (a player within `wire_r` m of the group's trip wire point, set with "Put trip wire here"), time of day
-- (when the game's clock passes `hour`), base raid (a player inside a flame altar area within `raid_r` m of one of the
-- group's nodes). "Start now" works for every trigger and ignores the cooldown.
-- A node spawns only while a player is within ACTIVE_DIST m of it (the game removes monsters far from every player);
-- the others skip that wave. Monsters spawn within SPREAD m of their node and are put on the ground (core/spawn.lua).
-- Kept on the server in spawn_nodes.json (kit.store): groups and nodes. What runs (waves, monsters alive) is not kept:
-- a restart or reload ends running waves; the game keeps or removes the monsters as it does any monster.
--
-- ADMINS ONLY: every change and the node list go only to FlameKit admins (core/admins.lua). An admin's own game shows
-- the nodes and trip wires as markers (emf.marker: over the 3D view and on the map; only in that game, EMF Lua 1.25+),
-- while "Show nodes" is on (this game's own switch, spawn_nodes_client.json). Other players' games never get the list.
-- The channel "nodes": a player's game asks with {op = "get"}; the server answers {op = "state", admin, groups, nodes,
-- status, note}; an admin's clicks send {op = ...} (below). In a game that hosts the world everything is done right here.
-- (0.15.478) Two raid switches per group: "Monsters damage buildings" (break_tick) and "Players cannot damage placed
-- objects during its waves" (protect_tick); (0.15.482, owner 12:36 "we need an option to protect animals and pets from damage
-- to" and Remove "by node group ... including the dead ones on the ground") "Its monsters spare animals, pets and villagers"
-- (a hit rule per monster: from it to "creatures", cancel) and Remove takes the group's dead bodies too; (0.15.479) renamed "Players cannot change bases during its waves": also the
-- players near its nodes lose the game's base editing permission while it runs (raid_lock_server.txt, FlameKit Native).
-- Uses only core modules (HANDOFF rule 0b).

local admins = require("core.admins")
local players = require("core.players")
local monsters = require("core.monsters")
local spawn = require("core.spawn")

local F = { id = "spawn_nodes", title = "Spawn Nodes" }
local kit

local CHANNEL = "nodes"
local ASK_STEPS = 120          -- the player's game asks for the state every 2 s while the tab may show
local ASK_STEPS_PLAYER = 1800  -- a player who is not an admin: every 30 s (he becomes one: seen within 30 s)
local CHECK_STEPS = 60         -- the triggers are checked every second
local CLEAN_STEPS = 120        -- dead or gone monsters are forgotten every 2 s
local SPAWN_PER_STEP = 4       -- monsters spawned in one server step at most (the rest on the next steps)
local MAX_NODES = 200          -- nodes on the server at most
local MAX_GROUPS = 30          -- groups at most
local SPREAD = 10              -- m: monsters spawn within this of their node (the default; (0.15.485) each node its own)
-- (0.15.485, owner 12:49 "is there a setting to control the spawn radius of the monster near the node and make this a
-- per node setting? ... is it possible to make sure the monster does [not] spawn into an object, terrain or a wall?"):
-- each node's "Spawn within" (node.spread, m), and SPOT_TRIES random spots looked at before one is used: a spot is
-- refused when a building block or terrain a player placed is on the line from the node to it (emf.find_wall, 1 m up),
-- a building block is at it (1 m and 2 m up), or the ground is solid at both SOLID_UP heights over the node's height
-- (a rock or cliff). All refused: the monster appears on the node itself. Not seen: placed objects (chests and the like).
local SPREADS = { 0, 2, 5, 10, 15, 20, 30 }
local SPOT_TRIES = 8
local SOLID_UP = { 1.5, 3.0 }
local ACTIVE_DIST = 100        -- m: a node spawns only while a player is within this
local NEAR_LIST = 8            -- the tab lists this many nodes of the chosen group, nearest first
-- (0.15.478, owner 12:01 "that would be cool if monsters could damage structures, that would be an option for that mode",
-- "prevent players from damaging structures while the raid is active", 12:03 "yes research both we need that setting")
local BREAK_STEPS = 30         -- the building damage is looked at every half second
local BREAK_LOOK = 64          -- m: the nearest player it looks toward (EMF's find_wall: a line of at most 64 m)
local BREAK_MAX = 15           -- hits per half second for all groups together (30 a second; EMF runs 8 breaks a step)
-- (0.15.481, owner 12:26 "anyway to make that more agressive?", 12:27 "yes" to these levels, "high should be the default IMO"):
-- how often each monster hits (server steps), how hard (times the game's top pickaxe: 100, 100, 95, 60, 50 per hardness
-- class), how far (m) and how big a hole (m)
local PICKAXE = { 100, 100, 95, 60, 50 }
local BREAK_LEVELS = { "low", "medium", "high", "extreme" }
local BREAK_LEVEL = {
  low = { every = 180, mult = 1, reach = 4, radius = 1, label = "Low: a hit every 3 s" },
  medium = { every = 90, mult = 2, reach = 5, radius = 1, label = "Medium: every 1.5 s, twice as hard" },
  high = { every = 60, mult = 4, reach = 6, radius = 1.5, label = "High: every 1 s, 4 times as hard" },
  extreme = { every = 30, mult = 8, reach = 6, radius = 1.5, label = "Extreme: every 0.5 s, 8 times as hard" },
}
local NEAR_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }  -- where a monster with no player in reach looks for a wall
-- (0.15.483, owner 12:42 "Players should not be able to damage structures while there are monsters from the raid still
-- alive. If you made a bug that violates this than fix it.": a reload of FlameKit on the server forgot the raid's
-- monsters, so the protection ended at once) Every monster a node spawns carries its group in a ScaleComponent tag:
-- uniformScale = TAG_BASE - group * TAG_STEP (not visible; the test monsters' tag is 0.999, core/test_tag.lua). After a
-- reload (or a new world) FlameKit scans the world for them (SCAN_BUDGET seconds a step at most) and knows them again,
-- alive or dead; until that scan is done the protection stays as it was (the raid lock file is not touched).
local TAG_BASE, TAG_STEP = 0.996, 0.00002
local SCAN_BUDGET, SCAN_MAX = 0.02, 3000   -- s and entities per server step for that scan
local clock_ok, clock = pcall(function() return os.clock end)
if not (clock_ok and type(clock) == "function" and pcall(clock)) then clock = nil end
local MISSES = 3  -- (0.15.483) a monster whose health can't be read is forgotten only after this many checks in a row

-- (0.15.477, owner 11:27 "it would be nice if I could have a monster group for bosses as well so I could have one node
-- spawn a boss") "Bosses": any of the bosses (core/monsters.lua's 26), the only type with bosses in it
local FAMILIES = { "Random", "Ancients", "Beasts", "Drak", "Scavengers", "Shroud", "Undead", "Vukah", "Bosses" }
local FAMILY_LABEL = { Shroud = "Shroud (Fell)", Bosses = "Bosses (any)" }
local TRIGGERS = { "manual", "timer", "wire", "time", "raid" }
-- (0.15.477, owner 11:37 "is there a way I can control which direction the monsters face when they spawn? one of the
-- faced away from the base") which way a spawned monster faces: the nearest player, the node's own direction (the way
-- the admin faced when he added or moved it), or random
local FACES = { "player", "node", "random" }
local FACE_LABEL = { player = "The nearest player", node = "The node's direction", random = "Random" }
local TRIGGER_LABEL = { manual = "Manual (Start now)", timer = "Timer", wire = "Trip wire", time = "Time of day", raid = "Base raid" }
-- the choices of each drop-down (the units in UNIT)
local CHOICES = {
  waves = { 1, 2, 3, 5, 10 }, per_wave = { 1, 2, 3, 5, 8, 10, 15 }, wave_gap = { 10, 20, 30, 60, 120, 300 },
  max_alive = { 3, 6, 10, 20, 40 }, cooldown = { 1, 2, 5, 10, 15, 30, 60 }, timer_min = { 1, 2, 5, 10, 15, 30, 60, 120 },
  timer_max = { 1, 2, 5, 10, 15, 30, 60, 120 }, wire_r = { 5, 10, 20, 30, 50 }, hour = { 0, 6, 12, 18, 20, 22 },
  raid_r = { 50, 100, 150, 250, 400 },
}
local UNIT = { wave_gap = "s", cooldown = "min", timer_min = "min", timer_max = "min", wire_r = "m", raid_r = "m" }
local DEFAULTS = { on = true, family = "Random", trigger = "manual", face = "player", breaks = false, break_level = "high", protect = false, spare = true, waves = 3, per_wave = 3, wave_gap = 30, max_alive = 6,
  cooldown = 10, timer_min = 10, timer_max = 20, wire_r = 20, hour = 20, raid_r = 150 }
local COLOURS = { 0xff6040ff, 0x40c0ffff, 0xffd040ff, 0x80ff60ff, 0xd070ffff, 0xff80c0ff, 0x60ffe0ff, 0xffa040ff }

-- The monsters of each type (no bosses), from core/monsters.lua: type -> { template GUID, ... }; "Random": all of
-- them; "Bosses": only the bosses.
local POOL = { Random = {}, Bosses = {} }
for _, m in ipairs(monsters) do
  if m[4] then
    table.insert(POOL.Bosses, m[3])
  else
    POOL[m[1]] = POOL[m[1]] or {}
    table.insert(POOL[m[1]], m[3])
    table.insert(POOL.Random, m[3])
  end
end

-- A drop-down value as text ("30 s", "10 min", "20:00").
local function label(key, v)
  if key == "hour" then return string.format("%02d:00", v) end
  return tostring(v) .. (UNIT[key] and (" " .. UNIT[key]) or "")
end

-- ---- the server's half ----

local S = { data = nil, steps = 0, runs = {}, alive = {}, queue = {}, last_end = {}, next_timer = {}, last_tod = {},
            notes = {}, session = nil, protect_rule = nil, no_break = nil, broke = {},
            dead = {}, spare_rules = {}, scan = nil, scanned = false, miss = {} }  -- (0.15.483) scan, scanned, miss; (0.15.482) dead: node -> { body id -> true }; spare_rules: monster -> hit rule id
local ground = spawn.ground({ max = 20, keep = function() return true end })  -- with the test monsters' 40: below EMF's 64

-- The saved groups and nodes (spawn_nodes.json), loaded once.
local function data()
  if not S.data then
    local ok, d = pcall(kit.store.load, "spawn_nodes", nil)
    d = (ok and type(d) == "table") and d or {}
    d.groups = type(d.groups) == "table" and d.groups or {}
    d.nodes = type(d.nodes) == "table" and d.nodes or {}
    d.next_g = tonumber(d.next_g) or 1
    d.next_n = tonumber(d.next_n) or 1
    S.data = d
  end
  return S.data
end

local function save()
  local ok, why = pcall(kit.store.save, "spawn_nodes", data())
  if not ok then emf.log("spawn nodes: spawn_nodes.json could not be saved (" .. tostring(why) .. ")") end
end

-- Group `gid` (a number) or nil; its settings filled in with the defaults.
local function group(gid)
  local g = data().groups[tostring(gid)]
  if not g then return nil end
  for k, v in pairs(DEFAULTS) do if g[k] == nil then g[k] = v end end
  return g
end

-- The groups in their order (by id).
local function groups()
  local list = {}
  for _, g in pairs(data().groups) do list[#list + 1] = g end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

-- The nodes of group `gid`.
local function nodes_of(gid)
  local list = {}
  for _, n in pairs(data().nodes) do if n.g == gid then list[#list + 1] = n end end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

local function node_count()
  local n = 0
  for _ in pairs(data().nodes) do n = n + 1 end
  return n
end

-- The players in the world with their positions: { { id, x, y, z } }.
local function player_spots(world)
  local list = {}
  for _, id in ipairs(players.ids(world)) do
    local oka, acc = pcall(world.account, world, id)
    if oka and acc then
      local ok, x, y, z = pcall(world.position, world, id)
      if ok and x then list[#list + 1] = { id, x, y, z } end
    end
  end
  return list
end

local function dist2(ax, ay, az, bx, by, bz)
  local dx, dy, dz = ax - bx, ay - by, az - bz
  return dx * dx + dy * dy + dz * dz
end

-- The yaw (degrees, 0 north (+z), 90 east (+x)) from x, z toward tx, tz.
local function yaw_to(x, z, tx, tz)
  return math.deg(math.atan(tx - x, tz - z)) % 360
end

-- The way entity `id` faces (its transform's forward), as a yaw; nil when not known.
local function facing(world, id)
  local yaw = nil
  pcall(function()
    local q = world:get("CurrentTransform", id).transform.orientation
    local ax, az = 2 * (q.x * q.z + q.w * q.y), 1 - 2 * (q.x * q.x + q.y * q.y)
    if ax * ax + az * az > 0.0001 then yaw = math.deg(math.atan(ax, az)) % 360 end
  end)
  return yaw
end

-- The nearest player to x, y, z within `r` m: its x, z, or nil.
local function nearest_player(spots, x, y, z, r)
  local best, bx, bz = r * r, nil, nil
  for _, p in ipairs(spots) do
    local d = dist2(p[2], p[3], p[4], x, y, z)
    if d <= best then best, bx, bz = d, p[2], p[4] end
  end
  return bx, bz
end

-- Whether a player is within `r` m of x, y, z.
local function player_near(spots, x, y, z, r)
  for _, p in ipairs(spots) do
    if dist2(p[2], p[3], p[4], x, y, z) <= r * r then return true end
  end
  return false
end

-- The flame altar areas (altar_areas_server.txt, written by FlameKit Native: "x0 y0 z0 x1 y1 z1" per line), read
-- again at most every 10 s.
local altar_cache = { at = -100, boxes = {} }
local function altar_boxes()
  if os.time() - altar_cache.at < 10 then return altar_cache.boxes end
  local boxes = {}
  local f = io.open(emf.dir .. "\\altar_areas_server.txt", "r")
  if f then
    for line in f:lines() do
      local v = {}
      for num in line:gmatch("%-?[%d%.]+") do v[#v + 1] = tonumber(num) end
      if #v >= 6 then boxes[#boxes + 1] = v end
    end
    f:close()
  end
  altar_cache = { at = os.time(), boxes = boxes }
  return boxes
end

-- How many monsters of node `nid` are alive.
local function alive_count(nid)
  local n = 0
  for _ in pairs(S.alive[nid] or {}) do n = n + 1 end
  return n
end

-- (0.15.483) The tag of group `gid`, and the group a tag names (nil: not one of ours).
local function tag_of(gid) return TAG_BASE - gid * TAG_STEP end
local function group_of_tag(v)
  if type(v) ~= "number" or v > TAG_BASE or v < TAG_BASE - 1000 * TAG_STEP then return nil end
  local gid = math.floor((TAG_BASE - v) / TAG_STEP + 0.5)
  if gid < 1 or math.abs(tag_of(gid) - v) > TAG_STEP * 0.3 then return nil end
  return gid
end

-- (0.15.483) One step of the world scan that finds the nodes' monsters again: each one tagged with a group that still
-- has nodes goes to that group's nearest node, alive (S.alive) or dead (S.dead). True when the scan is done.
local function scan_tick(world)
  if not S.scan then
    -- the protection stays as it was meanwhile: the raid lock file is kept, and if it names players the rule against
    -- players' hits on placed objects comes back now (EMF dropped it with the old script)
    local f = io.open(emf.dir .. "\\raid_lock_server.txt", "r")
    local text = f and f:read("*a") or ""
    if f then f:close() end
    S.lock_text = text
    -- (0.15.486) the placed objects' protection is FlameKit Native's (raid_protect_server.txt): kept as it is too
    local pf = io.open(emf.dir .. "\\raid_protect_server.txt", "r")
    local pt = pf and pf:read("*a") or ""
    if pf then pf:close() end
    S.protect_on = pt:sub(1, 1) == "1"
    if text ~= "" or S.protect_on then
      emf.log("spawn nodes: loaded during a raid: its protection is kept while the raid's monsters are looked for")
    end
    S.scan = { i = 1, found = 0 }
    return false  -- the list in this step, the walk in the next ones (a big world has tens of thousands)
  end
  local sc = S.scan
  if not sc.list then
    local ok, list = pcall(world.entities, world)
    sc.list = ok and list or {}
    return false
  end
  local t0 = clock and clock() or 0
  local done = 0
  while sc.i <= #sc.list and done < SCAN_MAX and not (clock and clock() - t0 > SCAN_BUDGET) do
    local id = sc.list[sc.i]
    sc.i, done = sc.i + 1, done + 1
    local oks, scl = pcall(world.get, world, "ScaleComponent", id)
    local gid = oks and scl and group_of_tag(scl.uniformScale)
    local nodes = gid and nodes_of(gid)
    if nodes and #nodes > 0 then
      local okp, x, y, z = pcall(world.position, world, id)
      local best, nid = nil, nodes[1].id
      if okp and x then
        for _, n in ipairs(nodes) do
          local d = dist2(n.x, n.y, n.z, x, y, z)
          if not best or d < best then best, nid = d, n.id end
        end
      end
      local okh, cur = pcall(emf.health, world, id)
      if okh and cur and cur > 0 then
        S.alive[nid] = S.alive[nid] or {}
        S.alive[nid][id] = true
      elseif okh and cur then
        S.dead[nid] = S.dead[nid] or {}
        S.dead[nid][id] = true
      end
      sc.found = sc.found + 1
    end
  end
  if sc.i <= #sc.list then return false end
  emf.log(string.format("spawn nodes: world scan done: %d of the nodes' monsters found again (of %d entities)", sc.found, #sc.list))
  S.scan, S.scanned = nil, true
  return true
end

-- Starts a run of group `gid` (its waves). `why`: what fired it (for the log). Manual starts ignore the cooldown.
local function fire(world, gid, why, manual)
  local g = group(gid)
  if not g or S.runs[gid] then return false, "This group is already running." end
  if not manual then
    if not g.on then return false end
    local since = os.time() - (S.last_end[gid] or 0)
    if since < g.cooldown * 60 then return false end
  end
  S.runs[gid] = { wave = 0, waves = g.waves, next_at = S.steps }
  emf.log(string.format("spawn nodes: %s (group %d, %d node(s), %s) started: %s", g.name, gid, #nodes_of(gid), g.family, why))
  return true
end

-- Ends the run of group `gid` (the cooldown starts now).
local function finish(gid)
  S.runs[gid] = nil
  S.last_end[gid] = os.time()
  S.next_timer[gid] = nil  -- the timer picks its next time from now
end

-- One wave of group `gid`: monsters queued at every node with a player near.
local function wave(world, gid, spots)
  local g = group(gid)
  local run = S.runs[gid]
  if not g or not run then return end
  run.wave = run.wave + 1
  local pool = POOL[g.family] or POOL.Random
  local queued, skipped = 0, 0
  for _, n in ipairs(nodes_of(gid)) do
    if player_near(spots, n.x, n.y, n.z, ACTIVE_DIST) then
      local room = math.max(0, g.max_alive - alive_count(n.id))
      local tx, tz = nearest_player(spots, n.x, n.y, n.z, ACTIVE_DIST)  -- (0.15.477) for "face the nearest player"
      for _ = 1, math.min(g.per_wave, room) do
        S.queue[#S.queue + 1] = { node = n.id, x = n.x, y = n.y, z = n.z, guid = pool[math.random(#pool)], face = g.face,
                                  tx = tx, tz = tz, yaw = n.yaw }
        queued = queued + 1
      end
    else
      skipped = skipped + 1
    end
  end
  emf.log(string.format("spawn nodes: %s wave %d of %d: %d monster(s)%s", g.name, run.wave, run.waves, queued,
    skipped > 0 and string.format(", %d node(s) skipped (no player within %d m)", skipped, ACTIVE_DIST) or ""))
  if run.wave >= run.waves then finish(gid) else run.next_at = S.steps + g.wave_gap * 60 end
end

-- Spawns up to SPAWN_PER_STEP queued monsters.
-- (0.15.485) What is at a point: "building", "terrain", "empty", or nil when not known (an older EMF, not loaded).
local function block_kind(world, x, y, z)
  if not emf.block_at then return nil end
  local ok, b = pcall(emf.block_at, world, x, y, z)
  return ok and type(b) == "table" and b.kind or nil
end

-- (0.15.485) Whether a wall (a building block, or terrain a player placed) stands on the line from `a` to `b`.
local function wall_between(world, a, b)
  if not emf.find_wall then return false end
  local ok, w = pcall(emf.find_wall, world, a, b, { terrain = true })
  if not ok then ok, w = pcall(emf.find_wall, world, a, b) end  -- an older EMF: building blocks only
  return ok and w ~= nil and w ~= false
end

-- (0.15.485) A spot for a monster of node `n` (its own spread): x, z. See SPOT_TRIES.
local function pick_spot(world, q, spread)
  if spread <= 0 then return q.x, q.z end
  local from = { q.x, q.y + 1, q.z }
  for _ = 1, SPOT_TRIES do
    local a, r = math.random() * 2 * math.pi, math.sqrt(math.random()) * spread
    local x, z = q.x + math.cos(a) * r, q.z + math.sin(a) * r
    local bad = wall_between(world, from, { x, q.y + 1, z })
      or block_kind(world, x, q.y + 1, z) == "building" or block_kind(world, x, q.y + 2, z) == "building"
    if not bad then
      local solid = true
      for _, up in ipairs(SOLID_UP) do
        if block_kind(world, x, q.y + up, z) ~= "terrain" then solid = false break end
      end
      bad = solid
    end
    if not bad then return x, z end
  end
  S.spot_fallbacks = (S.spot_fallbacks or 0) + 1
  if S.spot_fallbacks <= 20 or S.spot_fallbacks % 100 == 0 then
    emf.log(string.format("spawn nodes: node %s: no clear spot within %d m after %d tries: on the node itself (%d times so far)",
      tostring(q.node), spread, SPOT_TRIES, S.spot_fallbacks))
  end
  return q.x, q.z
end

local function spawn_tick(world)
  local done = 0
  while #S.queue > 0 and done < SPAWN_PER_STEP do
    local q = table.remove(S.queue, 1)
    done = done + 1
    if data().nodes[tostring(q.node)] then
      local qn1 = data().nodes[tostring(q.node)]
      local x, z = pick_spot(world, q, (qn1 and tonumber(qn1.spread)) or SPREAD)  -- (0.15.485) the node's spread, a clear spot
      -- (0.15.477) the way it faces: given to the spawn (EMF Lua 1.40+) and to the move onto the ground (any EMF)
      local yaw = math.random() * 360
      if q.face == "player" and q.tx then yaw = yaw_to(x, z, q.tx, q.tz)
      elseif q.face == "node" and q.yaw then yaw = q.yaw end
      local qn0 = data().nodes[tostring(q.node)]
      local tag = { ScaleComponent = { uniformScale = tag_of(qn0 and qn0.g or 0) } }  -- (0.15.483) its group, for a reload
      local ok, id = pcall(emf.spawn, world, q.guid, x, q.y, z, tag, { yaw = yaw })
      if not ok or not id or id == 0 then ok, id = pcall(emf.spawn, world, q.guid, x, q.y, z, tag) end  -- an older EMF: no yaw
      if not ok or not id or id == 0 then ok, id = pcall(emf.spawn, world, q.guid, x, q.y, z) end  -- nor the tag
      if ok and id and id ~= 0 then
        S.alive[q.node] = S.alive[q.node] or {}
        S.alive[q.node][id] = true
        local qn = data().nodes[tostring(q.node)]
        local qg = qn and group(qn.g)
        if qg and qg.spare then  -- (0.15.482) it never hurts animals, pets or villagers
          local okr, rid = pcall(emf.hit_rule, { from = id, to = "creatures", cancel = true })
          if okr and rid then S.spare_rules[id] = rid end
        end
        ground.add(id, x, q.y, z, yaw)
      else
        emf.log("spawn nodes: the game refused a spawn at node " .. tostring(q.node) .. " (" .. tostring(id) .. ")")
      end
    end
  end
end

-- Forgets monsters that died or are gone.
-- (0.15.482) A monster that died stays known as a body (S.dead) until its group's Remove takes it away; one that is
-- gone from the world is forgotten. Its "spare" hit rule goes when it dies. The rules follow the group's switch.
local function clean_tick(world)
  for nid, ids in pairs(S.alive) do
    local node = data().nodes[tostring(nid)]
    local g = node and group(node.g)
    for id in pairs(ids) do
      local ok, cur = pcall(emf.health, world, id)
      S.miss[id] = (not ok or cur == nil) and ((S.miss[id] or 0) + 1) or nil
      if S.miss[id] and S.miss[id] < MISSES then
        -- (0.15.483) not read this time: still counted alive (and still protecting) until MISSES checks in a row
      elseif not ok or not cur or cur <= 0 then
        ids[id] = nil
        S.miss[id] = nil
        if ok and cur then  -- dead, the body still there
          S.dead[nid] = S.dead[nid] or {}
          S.dead[nid][id] = true
        end
        if S.spare_rules[id] then pcall(emf.hit_rule_remove, S.spare_rules[id]) S.spare_rules[id] = nil end
      elseif g and g.spare and not S.spare_rules[id] then
        local okr, rid = pcall(emf.hit_rule, { from = id, to = "creatures", cancel = true })
        if okr and rid then S.spare_rules[id] = rid end
      elseif g and not g.spare and S.spare_rules[id] then
        pcall(emf.hit_rule_remove, S.spare_rules[id])
        S.spare_rules[id] = nil
      end
    end
    if next(ids) == nil then S.alive[nid] = nil end
  end
  for nid, ids in pairs(S.dead) do  -- bodies the game took away
    for id in pairs(ids) do
      local ok, cur = pcall(emf.health, world, id)
      if not ok or cur == nil then ids[id] = nil end
    end
    if next(ids) == nil then S.dead[nid] = nil end
  end
end

-- (0.15.478) "Monsters damage buildings": each monster of such a group looks along the line to the nearest player within
-- BREAK_LOOK m (emf.find_wall); a player-built block within the level's reach on that line takes one hit (emf.break_blocks,
-- mode damage: cracks and the game's block health; never the ground or the world's own ruins). (0.15.481) How often, how
-- hard, how far and how big: the group's Building damage level (BREAK_LEVEL); with no wall on that line, a building block
-- beside it (four directions, the level's reach). Needs EMF Lua 1.37+ on the server (EMF 0.6.19); an older one:
-- S.no_break, said in the tab.
local function break_tick(world, spots)
  if not (emf.find_wall and emf.break_blocks) then
    for _, g in ipairs(groups()) do if g.breaks then S.no_break = true break end end
    return
  end
  local hits = 0
  for _, g in ipairs(groups()) do
    local lv = BREAK_LEVEL[g.break_level] or BREAK_LEVEL.high
    if g.breaks and S.steps % lv.every == 0 then
      local damage = {}
      for i, d in ipairs(PICKAXE) do damage[i] = math.floor(d * lv.mult) end
      for _, n in ipairs(nodes_of(g.id)) do
        for id in pairs(S.alive[n.id] or {}) do
          if hits >= BREAK_MAX then return end
          local ok, x, y, z = pcall(world.position, world, id)
          if ok and x then
            local from = { x = x, y = y + 1, z = z }
            local wall = nil
            -- on its way to the nearest player within BREAK_LOOK m
            local best, px, py, pz = BREAK_LOOK * BREAK_LOOK, nil, nil, nil
            for _, p in ipairs(spots) do
              local d = dist2(p[2], p[3], p[4], x, y, z)
              if d <= best then best, px, py, pz = d, p[2], p[3], p[4] end
            end
            if px then
              local okw, w = pcall(emf.find_wall, world, from, { x = px, y = py + 1, z = pz })
              if okw and type(w) == "table" and w.kind == "building" and w.x and dist2(w.x, w.y, w.z, from.x, from.y, from.z) <= lv.reach * lv.reach then wall = w end
            end
            -- (0.15.481) else any player-built block right beside it
            if not wall then
              for _, dxz in ipairs(NEAR_DIRS) do
                local okw, w = pcall(emf.find_wall, world, from, { x = x + dxz[1] * lv.reach, y = y + 1, z = z + dxz[2] * lv.reach })
                if okw and type(w) == "table" and w.kind == "building" and w.x then wall = w break end
              end
            end
            if wall then
              local okb, bid = pcall(emf.break_blocks, world, wall.x, wall.y, wall.z, { radius = lv.radius, damage = damage }, function(w2, result)
                if type(result) == "table" and (tonumber(result.removed) or 0) > 0 then
                  S.broke[g.id] = (S.broke[g.id] or 0) + result.removed
                end
              end)
              if okb and bid then hits = hits + 1 end
            end
          end
        end
      end
    end
  end
end

-- (0.15.478) "Players cannot damage placed objects during its waves": while such a group runs (0.15.480: or any of its
-- monsters is alive), one EMF hit rule
-- cancels every player's hits on placed objects (chests, stations, doors...: EMF's "objects"), everywhere on the
-- server (EMF's rules have no area). Gone when no such group runs. Walls and floors are not hits: research.
local function protect_tick(world, spots)
  local want = false
  local lock = {}
  -- (0.15.480, owner 12:25 "keep the player damage protection up until all the monsters are dead? even if it finished the
  -- raid spawn waves") a protecting group counts while it runs AND while any monster of its nodes is still alive
  local active = {}
  for gid in pairs(S.runs) do active[gid] = true end
  for _, g in ipairs(groups()) do
    if not active[g.id] then
      for _, n in ipairs(nodes_of(g.id)) do
        if alive_count(n.id) > 0 then active[g.id] = true break end
      end
    end
  end
  for gid in pairs(active) do
    local g = group(gid)
    if g and g.protect then
      want = true
      -- (0.15.479) the players within its base distance (raid_r) of one of its nodes may not change bases while it
      -- runs: FlameKit Native clears their EDIT BASE permission (build_anywhere.cpp, raid lock), so the game itself
      -- refuses their building, dismantling and mining in bases
      for _, p in ipairs(spots or {}) do
        for _, n in ipairs(nodes_of(gid)) do
          if dist2(p[2], p[3], p[4], n.x, n.y, n.z) <= g.raid_r * g.raid_r then lock[#lock + 1] = p[1] break end
        end
      end
    end
  end
  table.sort(lock)
  local text = (#lock > 0 and (table.concat(lock, "\n") .. "\n") or "")
  if text ~= S.lock_text then
    local f = io.open(emf.dir .. "\\raid_lock_server.txt.tmp", "w")
    if f then
      f:write(text)
      f:close()
      os.remove(emf.dir .. "\\raid_lock_server.txt")
      if os.rename(emf.dir .. "\\raid_lock_server.txt.tmp", emf.dir .. "\\raid_lock_server.txt") then
        S.lock_text = text
        emf.log(string.format("spawn nodes: raid lock: %d player(s) may not change bases now", #lock))
      end
    end
  end
  -- (0.15.486, owner 13:05: the Undead could not be killed) players' hits on placed objects are cancelled by FlameKit
  -- Native (build_anywhere.cpp, protect_hit), which spares every creature; no EMF hit rule any more (EMF's "objects"
  -- class takes in monsters the game marks breakable). raid_protect_server.txt: "1" while wanted.
  if want ~= S.protect_on then
    local f = io.open(emf.dir .. "\\raid_protect_server.txt.tmp", "w")
    if f then
      f:write(want and "1\n" or "0\n")
      f:close()
      os.remove(emf.dir .. "\\raid_protect_server.txt")
      if os.rename(emf.dir .. "\\raid_protect_server.txt.tmp", emf.dir .. "\\raid_protect_server.txt") then
        S.protect_on = want
        emf.log(want and "spawn nodes: a raid runs: players' hits on placed objects are cancelled until its last monster is dead"
          or "spawn nodes: no raid with protection runs: players can hit placed objects again")
      end
    end
  end
end

-- The triggers of every group that is on and not running.
local function trigger_tick(world, spots)
  local tod = nil
  pcall(function() tod = emf.time_of_day(world) end)
  for _, g in ipairs(groups()) do
    local gid = g.id
    group(gid)
    if g.on and not S.runs[gid] and #nodes_of(gid) > 0 then
      if g.trigger == "timer" then
        if not S.next_timer[gid] then
          local lo, hi = math.min(g.timer_min, g.timer_max), math.max(g.timer_min, g.timer_max)
          S.next_timer[gid] = os.time() + math.random(lo * 60, hi * 60)
        elseif os.time() >= S.next_timer[gid] then
          if not fire(world, gid, "the timer") then S.next_timer[gid] = nil end
        end
      elseif g.trigger == "wire" and g.wire then
        if player_near(spots, g.wire.x, g.wire.y, g.wire.z, g.wire_r) then fire(world, gid, "a player crossed the trip wire") end
      elseif g.trigger == "time" and tod then
        local last = S.last_tod[gid]
        local h = g.hour
        -- the clock passed the hour since the last check (also over midnight)
        if last and ((last < h and tod >= h) or (last > tod and (h > last or h <= tod))) then
          fire(world, gid, string.format("the time of day (%02d:00)", h))
        end
      elseif g.trigger == "raid" then
        local hit = false
        for _, b in ipairs(altar_boxes()) do
          for _, p in ipairs(spots) do
            if p[2] >= b[1] and p[2] <= b[4] and p[3] >= b[2] and p[3] <= b[5] and p[4] >= b[3] and p[4] <= b[6] then
              local cx, cz = (b[1] + b[4]) / 2, (b[3] + b[6]) / 2
              for _, n in ipairs(nodes_of(gid)) do
                local dx, dz = n.x - cx, n.z - cz
                if dx * dx + dz * dz <= g.raid_r * g.raid_r then hit = true break end
              end
            end
            if hit then break end
          end
          if hit then break end
        end
        if hit then fire(world, gid, "a player is in a base near its nodes") end
      end
    end
    if tod then S.last_tod[gid] = tod end
  end
end

-- What group `gid` is doing, as a line for the tab.
local function status(gid)
  local g = group(gid)
  if not g then return "" end
  local run = S.runs[gid]
  local alive = 0
  local bodies = 0
  for _, n in ipairs(nodes_of(gid)) do
    alive = alive + alive_count(n.id)
    for _ in pairs(S.dead[n.id] or {}) do bodies = bodies + 1 end
  end
  local a = (alive > 0 and string.format(" %d of its monsters alive.", alive) or "")
    .. ((S.broke[gid] or 0) > 0 and string.format(" Blocks they broke: %d.", S.broke[gid]) or "")
    .. (bodies > 0 and string.format(" %d dead bod%s on the ground.", bodies, bodies == 1 and "y" or "ies") or "")
  if run then
    if run.wave == 0 then return "Running: the first wave starts now." .. a end
    return string.format("Running: wave %d of %d done, the next in %d s.", run.wave, run.waves,
      math.max(0, math.floor((run.next_at - S.steps) / 60))) .. a
  end
  if not g.on then return "Off." .. a end
  local cd = g.cooldown * 60 - (os.time() - (S.last_end[gid] or 0))
  if cd > 0 and S.last_end[gid] then return string.format("Cooling down: %d min %02d s left.", math.floor(cd / 60), cd % 60) .. a end
  if g.trigger == "timer" and S.next_timer[gid] then
    local t = math.max(0, S.next_timer[gid] - os.time())
    return string.format("Waiting: the timer fires in %d min %02d s.", math.floor(t / 60), t % 60) .. a
  end
  if g.trigger == "wire" and not g.wire then return "No trip wire yet: stand where it should be and press Put trip wire here." .. a end
  return "Waiting for its trigger." .. a
end

-- Whether this player is an admin (core/admins: EMF's admins, the host, npc_admins.json).
local function is_admin(account, from)
  return admins.is(account, from) == true
end

-- The state for one player's game: the groups and nodes only for an admin.
local function state(world, account, from)
  local st = { op = "state", admin = is_admin(account, from) or nil, note = S.notes[tostring(account)] }
  S.notes[tostring(account)] = nil
  if not st.admin then return st end
  st.groups, st.nodes, st.status = {}, {}, {}
  for _, g in ipairs(groups()) do
    group(g.id)
    local c = {}
    for k, v in pairs(g) do c[k] = v end
    c.running = S.runs[g.id] and true or nil
    st.groups[#st.groups + 1] = c
    st.status[tostring(g.id)] = status(g.id)
  end
  for _, n in pairs(data().nodes) do
    st.nodes[#st.nodes + 1] = { n.id, n.g, math.floor(n.x * 10 + 0.5) / 10, math.floor(n.y * 10 + 0.5) / 10, math.floor(n.z * 10 + 0.5) / 10, tonumber(n.spread) or SPREAD }  -- (0.15.485) [6] its spread
  end
  table.sort(st.nodes, function(a, b) return a[1] < b[1] end)
  st.max_nodes, st.max_groups = MAX_NODES, MAX_GROUPS
  st.no_break = S.no_break
  return st
end

-- Whether `v` is one of the choices of `key`.
local function allowed(key, v)
  if key == "family" then for _, f in ipairs(FAMILIES) do if f == v then return true end end return false end
  if key == "trigger" then for _, t in ipairs(TRIGGERS) do if t == v then return true end end return false end
  if key == "face" then for _, f in ipairs(FACES) do if f == v then return true end end return false end
  if key == "break_level" then return BREAK_LEVEL[v] ~= nil end
  for _, c in ipairs(CHOICES[key] or {}) do if c == v then return true end end
  return false
end

-- A message from a player's game (or the host's own click): does it, and answers with the state.
local function handle(world, account, entity, msg, from)
  account = tostring(account)
  local function note(text) S.notes[account] = text end
  if msg.op == "get" then return state(world, account, from) end
  if not is_admin(account, from) then
    note("Only FlameKit admins can set up spawn nodes.")
    return state(world, account, from)
  end
  local d = data()
  local gid = tonumber(msg.g)
  local g = gid and group(gid)
  local who = tostring(entity)
  if msg.op == "new_group" then
    if #groups() >= MAX_GROUPS then note("The limit of " .. MAX_GROUPS .. " groups is reached.") return state(world, account, from) end
    local id = d.next_g
    d.next_g = id + 1
    local ng = { id = id, name = "Group " .. id }
    for k, v in pairs(DEFAULTS) do ng[k] = v end
    d.groups[tostring(id)] = ng
    save()
    emf.log(string.format("spawn nodes: player %s made %s", who, ng.name))
    local st = state(world, account, from)
    st.made = id
    return st
  elseif msg.op == "delete_group" and g then
    local n = 0
    for k, node in pairs(d.nodes) do if node.g == gid then d.nodes[k] = nil n = n + 1 end end
    d.groups[tostring(gid)] = nil
    S.runs[gid], S.next_timer[gid] = nil, nil
    save()
    emf.log(string.format("spawn nodes: player %s deleted %s and its %d node(s)", who, g.name, n))
    note(string.format("Deleted %s and its %d node(s).", g.name, n))
  elseif msg.op == "set" and g then
    local key, v = tostring(msg.key), msg.value
    if key == "on" or key == "breaks" or key == "protect" or key == "spare" then  -- (0.15.478) the raid switches; (0.15.482) spare
      g[key] = v == true
    elseif allowed(key, v) then
      g[key] = v
      if key == "trigger" or key == "timer_min" or key == "timer_max" then S.next_timer[gid] = nil end
    else
      note("That setting was refused.")
      return state(world, account, from)
    end
    save()
    emf.log(string.format("spawn nodes: player %s set %s %s = %s", who, g.name, key, tostring(v)))
  elseif msg.op == "add_node" and g then
    if node_count() >= MAX_NODES then note("The limit of " .. MAX_NODES .. " nodes is reached.") return state(world, account, from) end
    local ok, x, y, z = pcall(world.position, world, entity)
    if not (ok and x) then note("Your position is not known.") return state(world, account, from) end
    local id = d.next_n
    d.next_n = id + 1
    d.nodes[tostring(id)] = { id = id, g = gid, x = x, y = y, z = z, yaw = facing(world, entity) }
    save()
    emf.log(string.format("spawn nodes: player %s added node %d to %s at %.0f %.0f %.0f", who, id, g.name, x, y, z))
    note(string.format("Node %d added to %s here.", id, g.name))
  elseif msg.op == "move_node" or msg.op == "delete_node" then
    local n = d.nodes[tostring(tonumber(msg.n) or -1)]
    if not n then note("That node is gone.") return state(world, account, from) end
    if msg.op == "delete_node" then
      d.nodes[tostring(n.id)] = nil
      S.alive[n.id] = nil
      note(string.format("Node %d deleted.", n.id))
      emf.log(string.format("spawn nodes: player %s deleted node %d", who, n.id))
    else
      local ok, x, y, z = pcall(world.position, world, entity)
      if not (ok and x) then note("Your position is not known.") return state(world, account, from) end
      n.x, n.y, n.z = x, y, z
      n.yaw = facing(world, entity)  -- (0.15.477) the node's direction: the way he faces now
      note(string.format("Node %d moved here.", n.id))
      emf.log(string.format("spawn nodes: player %s moved node %d to %.0f %.0f %.0f", who, n.id, x, y, z))
    end
    save()
  elseif msg.op == "node_spread" then  -- (0.15.485) a node's "Spawn within"
    local n = d.nodes[tostring(tonumber(msg.n) or -1)]
    if not n then note("That node is gone.") return state(world, account, from) end
    local v, okv = tonumber(msg.value), false
    for _, c in ipairs(SPREADS) do if c == v then okv = true end end
    if not okv then note("That setting was refused.") return state(world, account, from) end
    n.spread = v
    save()
    emf.log(string.format("spawn nodes: player %s set node %d's spawn distance to %d m", who, n.id, v))
  elseif msg.op == "wire_here" and g then
    local ok, x, y, z = pcall(world.position, world, entity)
    if not (ok and x) then note("Your position is not known.") return state(world, account, from) end
    g.wire = { x = x, y = y, z = z }
    save()
    note(string.format("%s's trip wire is here: a player within %d m of this spot fires it.", g.name, g.wire_r))
    emf.log(string.format("spawn nodes: player %s put %s's trip wire at %.0f %.0f %.0f", who, g.name, x, y, z))
  elseif msg.op == "start" and g then
    local ok, why = fire(world, gid, "Start now by player " .. who, true)
    note(ok and (g.name .. " started.") or (why or "It could not start."))
  elseif msg.op == "stop" and g then
    if S.runs[gid] then finish(gid) note(g.name .. " stopped (its cooldown starts now).") else note(g.name .. " is not running.") end
  elseif msg.op == "remove" and g then
    local n, bodies = 0, 0
    for _, node in ipairs(nodes_of(gid)) do
      for id in pairs(S.alive[node.id] or {}) do
        if pcall(emf.destroy, world, id) then n = n + 1 end
        if S.spare_rules[id] then pcall(emf.hit_rule_remove, S.spare_rules[id]) S.spare_rules[id] = nil end
      end
      S.alive[node.id] = nil
      for id in pairs(S.dead[node.id] or {}) do if pcall(emf.destroy, world, id) then bodies = bodies + 1 end end  -- (0.15.482)
      S.dead[node.id] = nil
    end
    for i = #S.queue, 1, -1 do
      local q = S.queue[i]
      local qn = d.nodes[tostring(q.node)]
      if qn and qn.g == gid then table.remove(S.queue, i) end
    end
    emf.log(string.format("spawn nodes: player %s removed %d monster(s) and %d dead bod(ies) of %s", who, n, bodies, g.name))
    note(string.format("Removed %d monster(s) and %d dead bod%s of %s.", n, bodies, bodies == 1 and "y" or "ies", g.name))
  end
  return state(world, account, from)
end

function F.tick(world)
  if not world:is_server() then return end
  S.steps = S.steps + 1
  local session = emf.session()
  if session ~= S.session then  -- a new world (or this script just loaded): the old ids mean nothing; scan again
    for _, rid in pairs(S.spare_rules) do pcall(emf.hit_rule_remove, rid) end
    S.session, S.alive, S.queue, S.runs, S.dead, S.spare_rules = session, {}, {}, {}, {}, {}
    S.scan, S.scanned, S.miss = nil, false, {}
  end
  if not S.scanned then  -- (0.15.483) find the nodes' monsters again first; nothing else until then
    scan_tick(world)
    return
  end
  ground.tick(world)
  spawn_tick(world)
  if S.steps % CLEAN_STEPS == 0 then clean_tick(world) end
  local need_spots = S.steps % CHECK_STEPS == 0 or S.steps % BREAK_STEPS == 0
  for _ in pairs(S.runs) do need_spots = true break end
  if not need_spots then return end
  local spots = player_spots(world)
  for gid, run in pairs(S.runs) do
    if S.steps >= run.next_at then wave(world, gid, spots) end
  end
  if S.steps % CHECK_STEPS == 0 then
    trigger_tick(world, spots)
    protect_tick(world, spots)
  end
  if S.steps % BREAK_STEPS == 0 then break_tick(world, spots) end
end

-- ---- the player's game ----

local C = { shown = nil, since_ask = ASK_STEPS, note = nil, sel = nil, show = nil, marks = {}, marks_key = nil,
            del_asked = nil, last_peer = nil, no_markers = nil }

local function hosting(world)
  return kit.is_host() or world:is_server()
end

local function peer()
  local ok, version = pcall(emf.net.peer, nil, 0, CHANNEL)
  return ok and version or 0
end

-- "Show nodes": this game's own switch (on unless switched off), kept in spawn_nodes_client.json.
local function show_on()
  if C.show == nil then
    local ok, v = pcall(kit.store.load, "spawn_nodes_client", nil)
    C.show = not (ok and type(v) == "table" and v.show == false)
  end
  return C.show
end

local function my_state(world)
  if hosting(world) then
    local me = emf.local_player()
    if not me or me == 0 then return nil end
    local ok, account = pcall(world.account, world, me)
    if not (ok and account) then return nil end
    return state(world, account, { is_local = true })
  end
  return C.shown
end

local function ask(msg)
  local ok, sent = pcall(emf.net.send, CHANNEL, emf.json.encode(msg))
  C.since_ask = 0
  return ok and sent == true
end

local function act(world, msg)
  if hosting(world) then
    local me = emf.local_player()
    local ok, account = pcall(world.account, world, me)
    if ok and account then
      local st = handle(world, account, me, msg, { is_local = true })
      C.note = st.note
      if st.made then C.sel = st.made end
    end
  elseif C.shown then
    ask(msg)
  end
end

-- The markers of this game: every node and trip wire, while this player is an admin and "Show nodes" is on.
local function markers(world)
  local v = my_state(world)
  local want = {}
  if v and v.admin and show_on() then
    local names, colour = {}, {}
    for i, g in ipairs(v.groups or {}) do
      names[g.id] = g.name
      colour[g.id] = COLOURS[(i - 1) % #COLOURS + 1]
      if g.trigger == "wire" and g.wire then
        want["w" .. g.id] = { x = g.wire.x, y = g.wire.y, z = g.wire.z, height = 0.5, shape = "circle", colour = colour[g.id],
          text = string.format("%s: trip wire (%d m)", g.name, g.wire_r), game_map = true, max_distance = 300 }
      end
    end
    for _, n in ipairs(v.nodes or {}) do
      want["n" .. n[1]] = { x = n[3], y = n[4], z = n[5], height = 1.5, colour = colour[n[2]] or COLOURS[1],
        text = string.format("%s: node %d", names[n[2]] or "?", n[1]), game_map = true, max_distance = 300 }
    end
  end
  local key = emf.json.encode(want)
  if key == C.marks_key then return end
  C.marks_key = key
  if not emf.marker then C.no_markers = next(want) ~= nil return end
  for id in pairs(C.marks) do
    if not want[id] then pcall(emf.remove_marker, id) C.marks[id] = nil end
  end
  for id, spec in pairs(want) do
    local ok, set = pcall(emf.marker, id, spec)
    C.marks[id] = true
    if not (ok and set) then kit.debug("warn", "spawn nodes: marker %s refused (%s)", id, tostring(set)) end
  end
end

function F.client_tick(world)
  local version = peer()
  if version ~= C.last_peer then C.last_peer, C.shown, C.since_ask = version, nil, ASK_STEPS end
  C.since_ask = C.since_ask + 1
  -- an admin's game asks every ASK_STEPS; a player who is not one only every ASK_STEPS_PLAYER (he gets no list)
  local every = (C.shown and not C.shown.admin) and ASK_STEPS_PLAYER or ASK_STEPS
  if not hosting(world) and version ~= 0 and C.since_ask >= every then ask({ op = "get" }) end
  if C.since_ask % 30 == 0 or hosting(world) then pcall(markers, world) end
end

-- One drop-down row: `key` of group g, its choices as text.
local function choice_row(rows, g, key, title, tip, list, show)
  local opts = {}
  for _, c in ipairs(list or CHOICES[key]) do
    opts[#opts + 1] = { key = "set:" .. key .. ":" .. tostring(c), text = show and show(c) or label(key, c), selected = g[key] == c }
  end
  rows[#rows + 1] = { label = true, text = title }
  rows[#rows + 1] = { options = opts, text = show and show(g[key]) or label(key, g[key]), same_line = true, tooltip = tip }
end

function F.panel(world)
  local v = my_state(world)
  if not v then
    return { { dim = true, text = (hosting(world) or peer() ~= 0) and "Asking the server..."
      or "This server does not run FlameKit's Spawn Nodes (or not this version)." } }
  end
  local rows = {}
  local note = C.note or v.note
  if note then rows[#rows + 1] = { color = "#ffb060", text = note } end
  if not v.admin then
    rows[#rows + 1] = { dim = true, text = "Only FlameKit admins can set up spawn nodes." }
    return rows
  end
  local list = v.groups or {}
  local g = nil
  for _, x in ipairs(list) do if x.id == C.sel then g = x end end
  if not g then g = list[1] C.sel = g and g.id or nil end
  rows[#rows + 1] = { heading = "Groups" }
  if g then
    local opts = {}
    for _, x in ipairs(list) do
      opts[#opts + 1] = { key = "sel:" .. x.id, text = x.name .. (x.on and "" or " (off)") .. (x.running and " (running)" or ""), selected = x.id == g.id }
    end
    rows[#rows + 1] = { label = true, text = "Group" }
    rows[#rows + 1] = { options = opts, text = g.name, same_line = true, tooltip = "The group these settings and nodes belong to." }
  else
    rows[#rows + 1] = { dim = true, text = "No groups yet: make one with New group." }
  end
  rows[#rows + 1] = { button = "new", text = "New group", disabled = (#list >= (v.max_groups or MAX_GROUPS)) or nil,
    tooltip = "Makes a new group with the default settings: Random monsters, started by hand, 3 waves 30 s apart, 3 monsters per node in each wave." }
  if not g then return rows end
  local asked = C.del_asked and C.del_asked.g == g.id and os.time() - C.del_asked.at <= 5
  rows[#rows + 1] = { button = "delgroup", same_line = true, selected = asked or nil,
    text = asked and "Click again to delete" or "Delete group",
    tooltip = "Deletes " .. g.name .. " and all its nodes. Click twice within 5 seconds." }
  rows[#rows + 1] = { dim = true, text = (v.status or {})[tostring(g.id)] or "" }

  rows[#rows + 1] = { heading = g.name }
  rows[#rows + 1] = { button = "on", text = (g.on and "On    " or "Off   ") .. "Group on", selected = g.on == true,
    tooltip = "Off: its trigger never fires (Start now still works)." }
  rows[#rows + 1] = { button = "start", text = "Start now", same_line = true, disabled = g.running or nil,
    tooltip = "Starts its waves now, whatever its trigger, also during its cooldown. Nodes without a player within " .. ACTIVE_DIST .. " m skip a wave." }
  rows[#rows + 1] = { button = "stop", text = "Stop", same_line = true, disabled = (not g.running) or nil, tooltip = "Ends its waves now; its cooldown starts." }
  rows[#rows + 1] = { button = "remove", text = "Remove its monsters", same_line = true,
    tooltip = "Removes this group's monsters only, alive or dead (their bodies on the ground too); other groups' and the world's "
      .. "own monsters stay. Only the ones spawned since the server last started or reloaded FlameKit." }
  choice_row(rows, g, "family", "Monsters", "Which monsters its nodes spawn: one kind, Random (any kind, no bosses) or Bosses (any boss: set Monsters per node to 1 for one boss).",
    FAMILIES, function(f) return FAMILY_LABEL[f] or f end)
  choice_row(rows, g, "face", "Monsters face", "Which way a monster faces when it appears: the nearest player, the node's direction "
    .. "(the way you faced when you added or last moved the node), or a random way.", FACES, function(f) return FACE_LABEL[f] or f end)
  rows[#rows + 1] = { button = "spare", text = (g.spare and "On    " or "Off   ") .. "Its monsters spare animals, pets and villagers", selected = g.spare == true,
    tooltip = "Its monsters' hits on anything that is not a player do nothing: farm animals, pets, mounts, villagers and companions are "
      .. "safe from them (other monsters too). Players are not covered: they can still be hit." }
  rows[#rows + 1] = { button = "breaks", text = (g.breaks and "On    " or "Off   ") .. "Monsters damage buildings", selected = g.breaks == true,
    tooltip = "Its monsters hit player-built blocks: on their way to the nearest player, or right beside them. How often and how hard: "
      .. "Building damage below. Never the ground or the world's own ruins. Inside a flame altar's area what breaks stays broken. "
      .. "Needs EMF 0.6.19 on the server." }
  if g.breaks then
    choice_row(rows, g, "break_level", "Building damage", "Low: a hit every 3 s like a top pickaxe, blocks within 4 m. Medium: every 1.5 s, "
      .. "twice as hard, 5 m. High: every 1 s, 4 times as hard, 6 m, 1.5 m holes. Extreme: every 0.5 s, 8 times as hard, 6 m, 1.5 m holes. "
      .. "Stone takes about 22 top-pickaxe hits.", BREAK_LEVELS, function(l) return (BREAK_LEVEL[l] or {}).label or l end)
  end
  if v.no_break and g.breaks then rows[#rows + 1] = { color = "#ffb060", text = "This server's EMF cannot break blocks: it needs EMF 0.6.19." } end
  rows[#rows + 1] = { button = "protect", text = (g.protect and "On    " or "Off   ") .. "Players cannot damage base structures during raid", selected = g.protect == true,  -- (0.15.484, owner 12:50: the label)
    tooltip = "While its waves run, and until the last of its monsters is dead: players within its Base within distance (" .. g.raid_r .. " m) of one of its nodes lose the game's own "
      .. "base editing permission, so they cannot build, dismantle or mine in bases (they get it back when that is over or they "
      .. "leave that range); and players' hits on placed objects (chests, crafting stations, doors and the like) do nothing, on the whole server. "
      .. "Admins too, for now." }
  choice_row(rows, g, "trigger", "Trigger", "What starts its waves. Start now works with every trigger.", TRIGGERS, function(t) return TRIGGER_LABEL[t] or t end)
  if g.trigger == "timer" then
    choice_row(rows, g, "timer_min", "Timer from", "The timer fires at a random time between these two (after the cooldown).")
    choice_row(rows, g, "timer_max", "to", "The timer fires at a random time between these two (after the cooldown).")
  elseif g.trigger == "wire" then
    choice_row(rows, g, "wire_r", "Trip wire size", "A player this close to the trip wire's spot fires it.")
    rows[#rows + 1] = { button = "wire", text = "Put trip wire here",
      tooltip = g.wire and string.format("Moves the trip wire to where you stand (now at %.0f, %.0f).", g.wire.x, g.wire.z)
        or "Puts the trip wire where you stand." }
  elseif g.trigger == "time" then
    choice_row(rows, g, "hour", "At", "Fires when the game's clock passes this hour.")
  elseif g.trigger == "raid" then
    choice_row(rows, g, "raid_r", "Base within", "Fires when a player is inside a flame altar's area whose middle is this close to one of the group's nodes.")
  end
  choice_row(rows, g, "waves", "Waves", "How many waves one start brings.")
  choice_row(rows, g, "wave_gap", "Between waves", "The time between two waves.")
  choice_row(rows, g, "per_wave", "Monsters per node", "How many monsters each node spawns in one wave.")
  choice_row(rows, g, "max_alive", "Most alive per node", "A node spawns no more while this many of its monsters are alive.")
  choice_row(rows, g, "cooldown", "Cooldown", "After its waves, the trigger cannot fire again for this long.")

  local mine = {}
  for _, n in ipairs(v.nodes or {}) do if n[2] == g.id then mine[#mine + 1] = n end end
  local me = emf.local_player()
  local px, py, pz
  pcall(function() px, py, pz = world:position(me) end)
  for _, n in ipairs(mine) do n.d = px and math.sqrt(dist2(px, py, pz, n[3], n[4], n[5])) or nil end
  table.sort(mine, function(a, b) return (a.d or 1e9) < (b.d or 1e9) end)
  rows[#rows + 1] = { heading = string.format("Nodes of %s (%d)", g.name, #mine) }
  rows[#rows + 1] = { button = "add", text = "Add node here", disabled = (#(v.nodes or {}) >= (v.max_nodes or MAX_NODES)) or nil,
    tooltip = "Adds a node to " .. g.name .. " where you stand, facing the way you face. Its monsters spawn within " .. SPREAD .. " m of it (change it with Spawn within)." }
  for i = 1, math.min(#mine, NEAR_LIST) do
    local n = mine[i]
    rows[#rows + 1] = { dim = true, text = string.format("Node %d: %.0f, %.0f%s", n[1], n[3], n[5], n.d and string.format(", %d m away", math.floor(n.d)) or "") }
    rows[#rows + 1] = { button = "move:" .. n[1], text = "Move here", same_line = true, tooltip = "Moves node " .. n[1] .. " to where you stand, facing the way you face." }
    rows[#rows + 1] = { button = "del:" .. n[1], text = "Delete", same_line = true, tooltip = "Deletes node " .. n[1] .. "." }
    -- (0.15.485) its own spawn distance
    local sp = tonumber(n[6]) or SPREAD
    local opts = {}
    for _, c in ipairs(SPREADS) do
      opts[#opts + 1] = { key = "spread:" .. n[1] .. ":" .. c, text = c == 0 and "On the node" or (c .. " m"), selected = sp == c }
    end
    rows[#rows + 1] = { label = true, text = "    Spawn within" }
    rows[#rows + 1] = { options = opts, text = sp == 0 and "On the node" or (sp .. " m"), same_line = true,
      tooltip = "How far from node " .. n[1] .. " its monsters may appear. A spot behind a wall, inside a building or inside rock is not used: "
        .. "FlameKit tries " .. SPOT_TRIES .. " spots, then uses the node itself. Chests and other placed objects are not seen." }
  end
  if #mine > NEAR_LIST then rows[#rows + 1] = { dim = true, text = string.format("(%d more further away)", #mine - NEAR_LIST) } end

  rows[#rows + 1] = { heading = "Markers" }
  rows[#rows + 1] = { button = "show", text = (show_on() and "On    " or "Off   ") .. "Show nodes", selected = show_on(),
    tooltip = "Shows every node and trip wire as a marker over the world and on the map, only in your game. Other players never see them." }
  if C.no_markers then rows[#rows + 1] = { color = "#ffb060", text = "Your EMF cannot draw markers yet: let FlameKit update EMF (About tab)." } end
  return rows
end

function F.click(world, key)
  C.note = nil
  local v = my_state(world)
  if not v or not v.admin then return end
  local gid = C.sel
  local sel = key:match("^sel:(%d+)$")
  if sel then C.sel = tonumber(sel) return end
  if key == "new" then act(world, { op = "new_group" }) return end
  if key == "show" then
    C.show = not show_on()
    pcall(kit.store.save, "spawn_nodes_client", { show = C.show })
    C.marks_key = nil
    return
  end
  if not gid then return end
  local g = nil
  for _, x in ipairs(v.groups or {}) do if x.id == gid then g = x end end
  if not g then return end
  if key == "delgroup" then
    if not (C.del_asked and C.del_asked.g == gid and os.time() - C.del_asked.at <= 5) then C.del_asked = { g = gid, at = os.time() } return end
    C.del_asked = nil
    act(world, { op = "delete_group", g = gid })
  elseif key == "on" then act(world, { op = "set", g = gid, key = "on", value = not g.on })
  elseif key == "breaks" then act(world, { op = "set", g = gid, key = "breaks", value = not g.breaks })
  elseif key == "spare" then act(world, { op = "set", g = gid, key = "spare", value = not g.spare })
  elseif key == "protect" then act(world, { op = "set", g = gid, key = "protect", value = not g.protect })
  elseif key == "start" then act(world, { op = "start", g = gid })
  elseif key == "stop" then act(world, { op = "stop", g = gid })
  elseif key == "remove" then act(world, { op = "remove", g = gid })
  elseif key == "add" then act(world, { op = "add_node", g = gid })
  elseif key == "wire" then act(world, { op = "wire_here", g = gid })
  else
    local mv = key:match("^move:(%d+)$")
    local dl = key:match("^del:(%d+)$")
    if mv then act(world, { op = "move_node", n = tonumber(mv) }) return end
    if dl then act(world, { op = "delete_node", n = tonumber(dl) }) return end
    local sn, sv = key:match("^spread:(%d+):(%d+)$")
    if sn then act(world, { op = "node_spread", n = tonumber(sn), value = tonumber(sv) }) return end
    local k, val = key:match("^set:([%w_]+):(.+)$")
    if k then
      local value = tonumber(val) or val
      act(world, { op = "set", g = gid, key = k, value = value })
    end
  end
end

function F.setup(k)
  kit = k
  players.setup(k)
  local ok = emf.net.channel(CHANNEL, {
    version = 1, to = "both", max = 16384, per_10s = 60,
    on_server = kit.guard(F, function(world, from, data_in)
      if type(from) ~= "table" or not from.player or from.player == 0 then return end
      local okd, msg = pcall(emf.json.decode, data_in)
      if not (okd and type(msg) == "table") then return end
      local account = from.account
      if (not account or tostring(account):match("^0x0*$")) then
        local oka, a = pcall(world.account, world, from.player)
        account = oka and a or nil
      end
      if not account then return end
      local st = handle(world, account, from.player, msg, from)
      pcall(emf.net.send_to, world, from.player, CHANNEL, emf.json.encode(st))
    end, "a Spawn Nodes message from a player"),
    on_player = kit.guard(F, function(world, from, data_in)
      local okd, msg = pcall(emf.json.decode, data_in)
      if okd and type(msg) == "table" and msg.op == "state" then
        C.shown = msg
        if msg.note then C.note = msg.note end
        if msg.made then C.sel = msg.made end
      end
    end, "the Spawn Nodes state from the server"),
  })
  if not ok then emf.log("spawn nodes: the channel flamekit/nodes was refused: the Spawn Nodes tab cannot reach the server") end
end

-- tests only
F._handle = function(world, account, entity, msg, from) return handle(world, account, entity, msg, from) end
F._reset = function() S.data, S.runs, S.alive, S.queue, S.last_end, S.next_timer, S.last_tod = nil, {}, {}, {}, {}, {}, {} end

return F
