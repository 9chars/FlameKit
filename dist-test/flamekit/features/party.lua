-- features/party.lua: the players in the game, for FlameKit's party window (drawn by FlameKit's DLL).
--
-- Where the world is hosted (your own game, or a server with FlameKit) this half reads every player's name, health,
-- mana and level twice a second and sends the list to each player's game on the channel "flamekit/party" (mana and
-- level can only be read there). A player's game writes the list to emf\mods\flamekit\ui_party.dat:
--   source server|local
--   p <you 0|1> <health> <max health> <mana> <max mana> <level> <x> <z> <name>   (fields separated by tabs; -1: not
--     known; x east and z north in metres: the DLL shows the region and how far away and where from you)
--   b <buff type id hex> <slot 0-4> <seconds left, -1: none> <name>   (since 0.15.49: that player's buffs and debuffs,
--     after their p line; slot 0 food, 1 buff, 2 debuff, 3 rested, 4 terrain; the DLL draws the game's own icon)
--   end
-- Buffs travel from the server half as one line per player, "b <type hex>:<slot>:<seconds>,...", and each player's
-- game adds the names in its own language (emf.buff_type; a dedicated server has no names). Types the game hides are
-- left out, as the game's own HUD does.
-- On a server without FlameKit the game writes what it knows itself ("source local"): only you, with your health.
-- ui_party.dat is a runtime file: never deployed or diffed.

local F = { id = "party", title = "Party" }

local test_players = require("core.test_players")
local players = require("core.players")

local kit
local CHANNEL = "party"
local ASK = "party_test"   -- a player's game -> the server half: "<how many test players>" (core/test_players.lua)
local test_wanted = 0      -- in this game: the test players asked for
local test_sent_at = -1000 -- the client step it was last sent
local steps = 0
local last_heard = -1000  -- the client step of the last list from the server half
local client_steps = 0
local written = nil

local SLOT = { food = 0, buff = 1, debuff = 2, rested = 3, terrain = 4 }
local hidden_type = {}  -- buff type id -> true when the game does not show it (read once per type)
local buff_name = {}    -- buff type id -> its name in this game's language

-- Where the world is hosted: a player's buffs as "<type hex>:<slot>:<seconds left>,...", or "" (none, or no EMF buffs).
local function buffs_of(world, id)
  local ok, list = pcall(emf.buffs, world, id)
  if not ok or type(list) ~= "table" then return "" end
  local out = {}
  for _, b in ipairs(list) do
    if type(b) == "table" and type(b.type) == "number" and not b.cleansed then
      local hide = hidden_type[b.type]
      if hide == nil then
        local okt, t = pcall(emf.buff_type, world, b.type)
        hide = okt and type(t) == "table" and t.hidden == true
        hidden_type[b.type] = hide
      end
      if not hide then
        local left = tonumber(b.seconds_left)
        out[#out + 1] = string.format("%x:%d:%d", b.type, SLOT[b.slot] or 1, left and math.max(0, math.floor(left + 0.5)) or -1)
      end
    end
    if #out >= 24 then break end
  end
  return table.concat(out, ",")
end

-- In a player's game: "b <list>" from the server half -> one "b" line per buff, with its name in this game's language.
local function buff_lines(world, list)
  local out = {}
  for hex, slot, left in (list or ""):gmatch("(%x+):(%d):(%-?%d+)") do
    local id = tonumber(hex, 16)
    local name = buff_name[id]
    if name == nil then
      local ok, t = pcall(emf.buff_type, world, id)
      name = ok and type(t) == "table" and type(t.name) == "string" and t.name ~= "" and t.name or false
      buff_name[id] = name
    end
    out[#out + 1] = table.concat({ "b", hex, slot, left, name and (name:gsub("[%c]", " ")) or "" }, "\t")
  end
  return out
end

local function num(v)
  v = tonumber(v)
  if not v or v ~= v then return -1 end
  return math.floor(v + 0.5)
end

local function clean(text)
  return (tostring(text or ""):gsub("[%c]", " "))
end

local function write(text)
  if text == written then return end
  local f = io.open(emf.dir .. "\\ui_party.dat", "w")
  if not f then
    kit.debug("warn", "party: ui_party.dat could not be written")
    return
  end
  f:write(text)
  f:close()
  written = text
  kit.debug("debug", "party: ui_party.dat written (%d bytes)", #text)
end

-- In a player's game: the list as the server half sent it ("you" marked per player).
local function receive(world, text)
  if type(text) ~= "string" or #text > 8000 then return end
  last_heard = client_steps
  local lines = {}
  for line in text:gmatch("[^\n]+") do
    local list = line:match("^b\t(.*)$")
    if list then
      for _, l in ipairs(buff_lines(world, list)) do lines[#lines + 1] = l end
    else
      lines[#lines + 1] = line
    end
  end
  lines[#lines + 1] = "end"
  write("source server\n" .. table.concat(lines, "\n") .. "\n")
end

local function player_name(world, id)
  for _, how in ipairs({ "name", "character_name" }) do  -- the order the minimap uses: the same name, the same colour
    local ok, name = pcall(world[how], world, id)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  return "Player"
end

-- Where the world is hosted: everyone's numbers, sent to everyone.
function F.tick(world)
  steps = steps + 1
  if steps % 30 ~= 0 then return end
  local here = {}
  local present = {}
  local me = emf.local_player()  -- the host's own player gets the list right here (receive)
  for _, id in ipairs(players.ids(world)) do  -- core/players.lua: from EMF's join and leave events
    local ok, account = pcall(world.account, world, id)
    if ok and account then
      local okh, hp, hp_max = pcall(emf.health, world, id)
      local function attr(name)
        local oka, v = pcall(emf.attribute, world, id, name)
        return oka and v or nil
      end
      present[id] = true
      local okp, x, _, z = pcall(world.position, world, id)
      here[#here + 1] = { id = id, name = player_name(world, id), hp = okh and hp or nil, hp_max = okh and hp_max or nil,
        mana = attr("mana"), mana_max = attr("max_mana"), level = attr("level"), x = okp and x or nil, z = okp and z or nil,
        buffs = buffs_of(world, id) }
    end
  end
  test_players.keep_only(present)
  for _, to in ipairs(here) do
    local lines = {}
    for _, p in ipairs(here) do
      lines[#lines + 1] = table.concat({ "p", p.id == to.id and "1" or "0", num(p.hp), num(p.hp_max), num(p.mana), num(p.mana_max),
        num(p.level), num(p.x), num(p.z), clean(p.name) }, "\t")
      if p.buffs ~= "" then lines[#lines + 1] = "b\t" .. p.buffs end  -- everyone sees everyone's buffs
    end
    for _, p in ipairs(test_players.list(world, to.id)) do  -- this player's own test players, sent like real ones
      lines[#lines + 1] = table.concat({ "p", "0", num(p.hp), num(p.hp_max), num(p.mana), num(p.mana_max), num(p.level), num(p.x), num(p.z),
        clean(p.name) }, "\t")
      if p.buffs and p.buffs ~= "" then lines[#lines + 1] = "b\t" .. p.buffs end
    end
    local text = table.concat(lines, "\n")
    if to.id == me then
      receive(world, text)  -- the host's own game is right here
    else
      pcall(emf.net.send_to, world, to.id, CHANNEL, text)
    end
  end
end

-- A step of your own screen's world: without lists from a server half (a server without FlameKit), what this game
-- knows itself.
local function hosting(world)
  return kit.is_host() or world:is_server()
end

-- Asks the server half for `n` test players (0: none). In your own game (you host) it is set directly.
local function ask_test(world, n)
  test_wanted = n
  test_sent_at = client_steps
  if hosting(world) then
    local me = emf.local_player()
    if me and me ~= 0 then test_players.set(me, n) end
    return
  end
  local ok = pcall(emf.net.send, ASK, tostring(n))
  kit.debug("info", "party: asked the server for %d test player(s)%s", n, ok and "" or " (could not be sent)")
end

local function server_has_it()
  local ok, version = pcall(emf.net.peer, nil, 0, ASK)
  return ok and (version or 0) ~= 0
end

-- The test players' rows, for the Debug section of the Experimental tab (features/experimental.lua): keys "N" (0 off).
function F.test_rows(world)
  local rows = {
    { text = "Test players: made-up players for testing the party window and the minimap alone. The server sends them "
      .. "to you the same way as real players (only you see them). They walk around you; some are far away, at the "
      .. "minimap's edge." },
  }
  if not (hosting(world) or server_has_it()) then
    rows[#rows + 1] = { dim = true, text = "This server does not run FlameKit (or not this version): test players need it." }
    return rows
  end
  for _, n in ipairs({ 0, 1, 3, 6 }) do
    rows[#rows + 1] = { button = tostring(n), text = n == 0 and "Off" or tostring(n), selected = test_wanted == n, same_line = n ~= 0,
      tooltip = n == 0 and "No test players" or ("Ask for " .. n .. " test player" .. (n == 1 and "" or "s")) }
  end
  return rows
end

-- A click on one of those rows.
function F.set_test(world, n)
  n = tonumber(n)
  if n then ask_test(world, n) end
end

function F.client_tick(world)
  client_steps = client_steps + 1
  if test_wanted > 0 and client_steps - test_sent_at >= 600 and not hosting(world) then ask_test(world, test_wanted) end  -- the server may have restarted
  if client_steps % 30 ~= 15 or client_steps - last_heard < 240 then return end
  local me = emf.local_player()
  if not me or me == 0 then return end
  local ok, hp, hp_max = pcall(emf.health, world, me)
  local okp, x, _, z = pcall(world.position, world, me)
  local line = table.concat({ "p", "1", num(ok and hp or nil), num(ok and hp_max or nil), "-1", "-1", "-1", num(okp and x or nil),
    num(okp and z or nil), clean(player_name(world, me)) }, "\t")
  local mine = buff_lines(world, buffs_of(world, me))  -- buffs are replicated: your own are known here too
  write("source local\n" .. line .. "\n" .. (#mine > 0 and (table.concat(mine, "\n") .. "\n") or "") .. "end\n")
end

function F.setup(k)
  kit = k
  local ok = emf.net.channel(CHANNEL, {
    version = 1, to = "players", max = 8192, per_10s = 60,
    on_player = kit.guard(F, function(world, from, data) receive(world, data) end, "the party list from the server"),
  })
  if not ok then kit.debug("warn", "party: the channel flamekit/party was refused: only your own health is shown") end
  local ok2 = emf.net.channel(ASK, {
    version = 1, to = "server", max = 16, per_10s = 20,
    on_server = kit.guard(F, function(world, from, data)
      if type(from) ~= "table" or not from.player or from.player == 0 then return end
      local n = test_players.set(from.player, data)
      kit.debug("info", "party: player %s asked for %d test player(s)", tostring(from.player), n)
    end, "a request for test players"),
  })
  if not ok2 then kit.debug("warn", "party: the channel flamekit/party_test was refused: no test players") end
  players.setup(kit)
end

return F
