-- core/msg_feed.lua (0.15.377, owner 2026-11-21 09:35/09:44/09:48): the Battle and Loot tabs of the Messages window.
-- Where the world is hosted, every hit a player or a companion lands or takes (emf.on_hit, through features that call
-- feed.hit), every companion heal (feed.heal) and every Auto Loot item (core/loot_route.lua's report) becomes a line for
-- the players who should see it; each player's game puts them into its tab (kit.note_tab: ui_battle.dat, ui_loot.dat,
-- drawn by FlameKit's DLL).
-- Who sees a line: its own player always (his hits, his companions' and pets' hits, the hits on them, his loot); other
-- players' lines only with "Show other players' ... messages" on (the default) and within feed.RADIUS m of the event.
-- Battle lines only for players who switched "Battle messages" on (off by default, owner 09:48: "to mitigate server
-- load"); nothing is worked out while nobody has it on. Owner 09:44: "if the messages are filtered or truncated, it
-- would defeat the purpose": every hit is sent; the server sends each player's lines in batches (at most 15 KB a
-- message, a few messages a second), so in a very big fight lines may come a little late, but none are left out.
-- Shared core code (HANDOFF rule 0b): features call it; it calls none.
--   feed.setup(kit)                       once from a feature's setup (any number may call it)
--   feed.set_namer(fn)                    fn(world, entity) -> a companion's name, or nil (features/companions)
--   feed.hit(world, hit)                  the server: one emf.on_hit hit
--   feed.heal(world, healer, target, amount)   the server: a companion's heal
--   feed.loot(world, report)              the server: core/loot_route.lua's report of one item
--   feed.pickup(world, event)             the server: the game's PickupEvent (loot taken by hand)
--   feed.tick(world)                      the server, every step: sends the batches

local players = require("core.players")
local prefs = require("core.player_prefs")
local route = require("core.loot_route")

local feed = {}

feed.RADIUS = 100          -- m (owner 2026-11-21 10:24 "I think the 100 m radius is fine for now")
local CHANNEL = "feed"
local MAX_BYTES = 15000    -- one message (the channel allows 16384)
local SEND_EVERY = 30      -- steps between two batches to a player
local MOST_PER_BATCH = 4   -- messages to one player per batch (the channel allows 100 in 10 s)

local kit = nil
local registered = nil
local namer = nil
local out = {}             -- player entity -> { battle = {lines}, loot = {lines} }
local steps = 0
local name_cache = {}      -- entity -> { name, at }
local monster_print = require("core.monster_print")

local FACTION_NAME = { [1] = "Monster", [2] = "Fogger", [3] = "Vukah", [4] = "Scavenger", [5] = "Animal", [6] = "Beast",
  [9] = "Monster", [10] = "Skeleton", [12] = "Farm animal", [13] = "Cyclops", [14] = "Drak", [15] = "Ancient" }

function feed.set_namer(fn) namer = fn end
local name_of  -- below

local function get(world, c, id)
  local ok, v = pcall(world.get, world, c, id)
  return ok and v or nil
end

local function is_player(world, id) return id and id ~= 0 and get(world, "PlayerState", id) ~= nil end

-- A short name for anyone in a fight: a player's character name, a companion's own name, else the monster's kind and level.
name_of = function(world, id)
  id = tonumber(id) or 0
  if id == 0 then return "something" end
  local c = name_cache[id]
  if c and steps - c.at < 600 then return c.name end
  local name
  if is_player(world, id) then
    name = players.name(world, id, "A player")
  else
    if namer then local ok, n = pcall(namer, world, id) if ok and n then name = n end end
    if not name then
      local f = get(world, "Faction", id)
      -- (0.15.384, owner 12:15 "it need to say the actual monster's name") the kind's name (core/monster_names.lua),
      -- the faction's only for a monster that table does not know
      local kind = monster_print.name(world, id) or (f and FACTION_NAME[tonumber(f.faction) or -1]) or "Creature"
      local lv = get(world, "Level", id)
      local l = lv and lv.dataStorage and tonumber(lv.dataStorage[1])
      name = l and l > 0 and string.format("%s(%d)", kind, l) or kind  -- (0.15.381, owner 12:05 "just say Fogger(45)")
    end
  end
  name_cache[id] = { name = name, at = steps }
  return name
end

local function account_of(world, player)
  local ok, a = pcall(world.account, world, player)
  return ok and a or nil
end

-- the host's own game is this Lua state: its lines go straight into its tabs
local function is_local_host(player)
  return kit and kit.is_host() and player == emf.local_player()
end

-- Who gets a line about players `owners` (a set: entity -> true) at x, z: owners always, others with their switch on
-- and within feed.RADIUS. `tab` "battle" (only for players with Battle messages on) or "loot".
local function recipients(world, tab, owners, x, z)
  local list = {}
  local ok, ids = pcall(players.ids, world)
  for _, pid in ipairs(ok and ids or {}) do
    local acc = account_of(world, pid)
    local on = tab ~= "battle" or prefs.get(acc, "battle_msgs", world) == true
    -- a game without this channel (no FlameKit, an older one) gets nothing (nothing waits for it)
    if on and not is_local_host(pid) then
      local okp, ver = pcall(emf.net.peer, world, pid, CHANNEL)
      on = okp and (tonumber(ver) or 0) > 0
    end
    if on then
      if owners[pid] then
        list[#list + 1] = pid
      else
        local others = prefs.get(acc, tab == "battle" and "others_battle" or "others_loot", world)
        if others ~= false and x then
          local okp, px, _, pz = pcall(world.position, world, pid)
          if okp and px and (px - x) ^ 2 + (pz - z) ^ 2 <= feed.RADIUS ^ 2 then list[#list + 1] = pid end
        end
      end
    end
  end
  return list
end

local function queue(pid, tab, line)
  local o = out[pid]
  if not o then o = { battle = {}, loot = {} } out[pid] = o end
  local q = o[tab]
  q[#q + 1] = line
end

local any_battle_at, any_battle = -1e9, false
-- true when at least one player has Battle messages on (looked at once a second)
local function battle_wanted(world)
  if steps - any_battle_at < 60 then return any_battle end
  any_battle_at, any_battle = steps, false
  local ok, ids = pcall(players.ids, world)
  for _, pid in ipairs(ok and ids or {}) do
    if prefs.get(account_of(world, pid), "battle_msgs", world) == true then any_battle = true break end
  end
  return any_battle
end

-- a line: "<colour hex> <text>"
local OUT, IN, HEAL = "ffb060", "ff6a5a", "5ad25a"

function feed.hit(world, hit)
  if not (hit and battle_wanted(world)) then return end
  local a, t = tonumber(hit.attacker) or 0, tonumber(hit.target) or 0
  local pa, pt = route.player_of(world, a), route.player_of(world, t)
  if not pa and not pt then return end  -- monsters among themselves
  -- (0.15.382, owner 2026-11-21 12:08 "only log damage to and from actual monsters or other players (PvP)") the other
  -- side has to be a creature too: a player, a companion, or something with a faction other than Environment (0).
  -- Hits on trees, rocks, crates and the like (no faction: "Midevil > Monster 1") are left out, and so is damage with
  -- no attacker.
  local function creature(id, p)
    if p then return true end
    if id == 0 then return false end
    local f = get(world, "Faction", id)
    return f ~= nil and (tonumber(f.faction) or 0) ~= 0
  end
  if not (creature(a, pa) and creature(t, pt)) then return end
  local owners = {}
  if pa then owners[pa] = true end
  if pt then owners[pt] = true end
  local amount = tonumber(hit.amount) or 0
  local flags = {}
  if hit.crit then flags[#flags + 1] = "crit" end
  if hit.backstab then flags[#flags + 1] = "backstab" end
  if hit.weakspot then flags[#flags + 1] = "weak spot" end
  if hit.blocked then flags[#flags + 1] = "blocked" .. ((tonumber(hit.stamina) or 0) > 0 and string.format(" (%d stamina)", hit.stamina) or "") end
  if hit.parried then flags[#flags + 1] = "parried" end
  if hit.killed then flags[#flags + 1] = "KILLED" end
  local text
  if hit.healing or amount < 0 then
    text = string.format("%s %s heals %s for %d", HEAL, name_of(world, a), name_of(world, t), math.abs(amount))
  else
    -- (0.15.381, owner 12:03 "what does "Fogger (lvl 45) > Midevil: 85" even mean?") spelled out
    text = string.format("%s %s hit %s for %d damage%s", pt and not pa and IN or OUT, name_of(world, a), name_of(world, t), math.floor(amount + 0.5),
      #flags > 0 and (" (" .. table.concat(flags, ", ") .. ")") or "")
  end
  local okp, x, _, z = pcall(world.position, world, t)
  for _, pid in ipairs(recipients(world, "battle", owners, okp and x or nil, okp and z or nil)) do queue(pid, "battle", text) end
end

function feed.heal(world, healer, target, amount)
  if not battle_wanted(world) then return end
  local owner = route.player_of(world, healer)
  local pt = route.player_of(world, target)
  local owners = {}
  if owner then owners[owner] = true end
  if pt then owners[pt] = true end
  if not next(owners) then return end
  local text = string.format("%s %s heals %s for %d", HEAL, name_of(world, healer), name_of(world, target), math.floor((tonumber(amount) or 0) + 0.5))
  local okp, x, _, z = pcall(world.position, world, target)
  for _, pid in ipairs(recipients(world, "battle", owners, okp and x or nil, okp and z or nil)) do queue(pid, "battle", text) end
end

-- One Auto Loot item: its numbers go to the players' games, which write the line with the item's name in their language.
-- "L <colour>|<player name>|<item id>|<count>|<level>|<rarity>|<where>" (where: bag, companion name, ground, junk drop/delete)
function feed.loot(world, r)
  if not (r and r.player) then return end
  local where = {}
  if r.junk then where[#where + 1] = "junk " .. r.junk
  else
    if (r.bag or 0) > 0 then where[#where + 1] = "bag" .. ((r.bag ~= r.count) and (" " .. r.bag) or "") end
    if (r.companion or 0) > 0 then where[#where + 1] = (r.companion_name or "companion") .. ((r.companion ~= r.count) and (" " .. r.companion) or "") end
    if (r.ground or 0) > 0 then where[#where + 1] = "ground" .. ((r.ground ~= r.count) and (" " .. r.ground) or "") end
  end
  local line = string.format("L|%s|%s|%d|%d|%d|%d|%s|%s", r.junk and "a0a0a0" or "8cd2ff", (name_of(world, r.player):gsub("|", "/")),
    tonumber(r.item) or 0, tonumber(r.count) or 0, tonumber(r.level) or 0, tonumber(r.rarity) or 0, table.concat(where, ", "),
    ((r.from or ""):gsub("|", "/")))
  local x, z = r.x, r.z
  for _, pid in ipairs(recipients(world, "loot", { [r.player] = true }, x, z)) do queue(pid, "loot", line) end
end

-- (0.15.380, owner 2026-11-21 12:00 "if I pick up loot, it needs to be logged into the loot window according to my
-- settings") a pickup by hand: the game's PickupEvent (from a body, a chest, the ground; anything with a source
-- entity: crafting and FlameKit's own puts come from entity 0 and are left out). The event has the item and how many.
local pickups_logged = {}  -- "from" / "none" -> lines logged
function feed.pickup(world, e)
  if type(e) ~= "table" then return end
  local by, from, item, count = tonumber(e.pickedUpByEntityId) or 0, tonumber(e.pickedUpFromEntityId) or 0,
    tonumber(e.itemId) or 0, tonumber(e.itemCount) or 0
  -- the first ones of a run, to see what the game sends (Logging is live); (0.15.386) 20 with a "from" and 20 without:
  -- FlameKit's own puts into a bag (Auto Loot) come with from 0 and filled the first 20 before any chest take
  local kind = from == 0 and "none" or "from"
  if (pickups_logged[kind] or 0) < 20 then
    pickups_logged[kind] = (pickups_logged[kind] or 0) + 1
    local f = {}
    for k, v in pairs(e) do f[#f + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(f)
    emf.log("feed: pickup " .. table.concat(f, " "))
  end
  if count <= 0 or from == 0 or item == 0 or not is_player(world, by) then return end
  local line = string.format("L|%s|%s|%d|%d|%d|%d|%s|", "c8e6ff", (name_of(world, by):gsub("|", "/")), item, count,
    0, 0, "picked up")  -- (0.15.386) the event has no level or quality (reading e.itemLevel was an error that stopped the feature)
  local okp, x, _, z = pcall(world.position, world, by)
  for _, pid in ipairs(recipients(world, "loot", { [by] = true }, okp and x or nil, okp and z or nil)) do queue(pid, "loot", line) end
end

local RARITY = { [0] = "", [1] = "uncommon ", [2] = "rare ", [3] = "epic ", [4] = "legendary " }
-- A player's game: a loot line as text, with the item's name in this game's language.
local function loot_text(line)
  local colour, who, item, count, level, rarity, where, from = line:match("^L|(%x+)|([^|]*)|(%d+)|(%d+)|(%d+)|(%d+)|([^|]*)|?(.*)$")
  if not colour then return nil end
  local okn, nm = pcall(emf.item_name, tonumber(item))
  if not (okn and type(nm) == "string" and nm ~= "") then
    local oki, info = pcall(emf.item_info, tonumber(item))
    nm = oki and type(info) == "table" and info.name or ("item " .. item)
  end
  local lv = tonumber(level) or 0
  return colour, string.format("%s: %s%s%s%s%s > %s", who, RARITY[tonumber(rarity) or 0] or "", nm,
    (tonumber(count) or 1) > 1 and (" x" .. count) or "", lv > 0 and (" (lvl " .. lv .. ")") or "",
    from ~= "" and (" from " .. from) or "", where)
end

-- A player's game: one batch from the server.
local function receive(m)
  if type(m) ~= "table" or (m.tab ~= "battle" and m.tab ~= "loot") or type(m.lines) ~= "table" then return end
  for _, line in ipairs(m.lines) do
    if type(line) == "string" then
      if m.tab == "loot" then
        local c, t = loot_text(line)
        if c then kit.note_tab("loot", t, "#" .. c) end
      else
        local c, t = line:match("^(%x%x%x%x%x%x) (.*)$")
        if c then kit.note_tab("battle", t, "#" .. c) end
      end
    end
  end
end

function feed.setup(k)
  kit = kit or k
  if registered ~= nil then return registered end
  registered = emf.net.channel(CHANNEL, { version = 1, to = "players", max = 16384, per_10s = 100,
    on_player = function(world, from, data)
      local ok, m = pcall(emf.json.decode, data)
      if ok then pcall(receive, m) end
    end }) and true or false
  return registered
end

-- Sends what is queued: every SEND_EVERY steps, up to MOST_PER_BATCH messages of at most MAX_BYTES to each player
-- (the rest waits for the next batch: nothing is dropped).
function feed.tick(world)
  steps = steps + 1
  if steps % 600 == 0 then name_cache = {} end
  if steps % SEND_EVERY ~= 0 or not next(out) then return end
  for pid, o in pairs(out) do
    for _, tab in ipairs({ "loot", "battle" }) do
      local q = o[tab]
      local sent = 0
      while #q > 0 and sent < MOST_PER_BATCH do
        local lines, bytes, n = {}, 40, 0
        for i = 1, #q do
          local len = #q[i] + 4
          if bytes + len > MAX_BYTES and n > 0 then break end
          lines[#lines + 1], bytes, n = q[i], bytes + len, n + 1
        end
        local msg = { tab = tab, lines = lines }
        if is_local_host(pid) then
          pcall(receive, msg)
        else
          local okj, text = pcall(emf.json.encode, msg)
          local oks, done = pcall(emf.net.send_to, world, pid, CHANNEL, okj and text or "")
          if not (okj and oks and done) then break end  -- refused (over the rate, gone): kept for the next batch
        end
        local rest = {}
        for i = n + 1, #q do rest[#rest + 1] = q[i] end
        q = rest
        o[tab] = q
        sent = sent + 1
      end
      if #q > 20000 and steps % 600 == 0 then emf.log(string.format("feed: player %s: %d %s lines waiting", tostring(pid), #q, tab)) end
    end
    if #o.battle == 0 and #o.loot == 0 then out[pid] = nil end
  end
end

-- A name for anyone (features/loot_drop.lua names the monster a loot line came from).
function feed.name(world, id) return name_of(world, id) end

-- a player left: what waited for him goes
function feed.forget(pid) out[pid] = nil end

return feed
