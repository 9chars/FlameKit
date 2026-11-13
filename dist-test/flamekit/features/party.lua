-- features/party.lua: the players in the game, for FlameKit's party window (drawn by FlameKit's DLL).
--
-- Where the world is hosted (your own game, or a server with FlameKit) this half reads every player's name, health,
-- mana and level twice a second and sends the list to each player's game on the channel "flamekit/party" (mana and
-- level can only be read there). A player's game writes the list to emf\mods\flamekit\ui_party.dat:
--   source server|local
--   p <you 0|1> <health> <max health> <mana> <max mana> <level> <name>   (fields separated by tabs; -1: not known)
--   end
-- On a server without FlameKit the game writes what it knows itself ("source local"): only you, with your health.
-- ui_party.dat is a runtime file: never deployed or diffed.

local F = { id = "party", title = "Party" }

local kit
local CHANNEL = "party"
local steps = 0
local last_heard = -1000  -- the client step of the last list from the server half
local client_steps = 0
local written = nil

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
local function receive(text)
  if type(text) ~= "string" or #text > 8000 then return end
  last_heard = client_steps
  write("source server\n" .. text .. (text ~= "" and "\n" or "") .. "end\n")
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
  local ids = {}
  for id = 1, 64 do ids[#ids + 1] = id end  -- players' bodies have the lowest entity ids
  local me = emf.local_player()
  if me and me > 64 then ids[#ids + 1] = me end  -- and the host's own player, wherever it is
  for _, id in ipairs(ids) do
    local ok, account = pcall(world.account, world, id)
    if ok and account then
      local okh, hp, hp_max = pcall(emf.health, world, id)
      local function attr(name)
        local oka, v = pcall(emf.attribute, world, id, name)
        return oka and v or nil
      end
      here[#here + 1] = { id = id, name = player_name(world, id), hp = okh and hp or nil, hp_max = okh and hp_max or nil,
        mana = attr("mana"), mana_max = attr("max_mana"), level = attr("level") }
    end
  end
  for _, to in ipairs(here) do
    local lines = {}
    for _, p in ipairs(here) do
      lines[#lines + 1] = table.concat({ "p", p.id == to.id and "1" or "0", num(p.hp), num(p.hp_max), num(p.mana), num(p.mana_max),
        num(p.level), clean(p.name) }, "\t")
    end
    local text = table.concat(lines, "\n")
    if to.id == me then
      receive(text)  -- the host's own game is right here
    else
      pcall(emf.net.send_to, world, to.id, CHANNEL, text)
    end
  end
end

-- A step of your own screen's world: without lists from a server half (a server without FlameKit), what this game
-- knows itself.
function F.client_tick(world)
  client_steps = client_steps + 1
  if client_steps % 30 ~= 15 or client_steps - last_heard < 240 then return end
  local me = emf.local_player()
  if not me or me == 0 then return end
  local ok, hp, hp_max = pcall(emf.health, world, me)
  local line = table.concat({ "p", "1", num(ok and hp or nil), num(ok and hp_max or nil), "-1", "-1", "-1", clean(player_name(world, me)) }, "\t")
  write("source local\n" .. line .. "\nend\n")
end

function F.setup(k)
  kit = k
  local ok = emf.net.channel(CHANNEL, {
    version = 1, to = "players", max = 8192, per_10s = 60,
    on_player = kit.guard(F, function(world, from, data) receive(data) end, "the party list from the server"),
  })
  if not ok then kit.debug("warn", "party: the channel flamekit/party was refused: only your own health is shown") end
end

return F
