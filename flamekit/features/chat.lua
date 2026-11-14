-- features/chat.lua: chat and FlameKit's announcements in the Messages window (0.15.76, owner).
--
-- 1. Player chat, copied: the game's chat lines fade from the screen, so every line a player types also goes into the
--    Messages window of every player with FlameKit, as "<name>: <text>". The server sees each line (emf.on_chat, read
--    only: the game still shows it in its own chat) and sends it over the channel flamekit/chat. A player's own game
--    is told by EMF's mod messages; the host's own game gets it directly. Each line has the player's colour, the same as
--    in the Party window (0.15.82).
-- 2. FlameKit's own announcements (for example "PvP for Ninechars ENABLED."): no longer chat lines, only the Messages
--    window of every player with FlameKit (F.announce). Players without FlameKit do not see them.
-- The Notices window is not touched here.

local players = require("core.players")

local F = { id = "chat", title = "Chat" }
local CHANNEL = "chat"
local CHAT_COLOUR, ANNOUNCE_COLOUR = "#c8d2ec", "#ffd27a"
local kit

-- A player's colour, the same as their symbol's in the Party window and on the minimap (0.15.82, owner): the DLL's
-- player_style, FNV-1a over the name's bytes, colour number (hash // 6) % 8 of these eight.
local PLAYER_COLOURS = { "ffaa3c", "ffe65a", "ff78be", "64dcff", "be8cff", "aaf064", "ff6e5a", "f0f0f0" }
local function player_colour(name)
  local h = 2166136261
  for i = 1, #name do h = ((h ~ name:byte(i)) * 16777619) & 0xffffffff end
  return "#" .. PLAYER_COLOURS[(h // 6) % 8 + 1]
end
F.player_colour = player_colour

local function show(msg)
  if type(msg) ~= "table" or type(msg.t) ~= "string" or msg.t == "" then return end
  local colour = msg.c == "a" and ANNOUNCE_COLOUR or CHAT_COLOUR
  if msg.c ~= "a" and type(msg.n) == "string" and msg.n ~= "" then colour = player_colour(msg.n) end
  kit.note(msg.t:sub(1, 400), colour, true)
end

-- To every player's game with FlameKit (the host's own: directly). Server world only.
local function to_all(world, msg)
  local text = emf.json.encode(msg)
  local me = emf.local_player()
  local done_me = false
  for _, id in ipairs(players.ids(world)) do
    local ok, account = pcall(world.account, world, id)
    if ok and account then
      if id == me and kit.is_host() then
        show(msg)
        done_me = true
      else
        pcall(emf.net.send_to, world, id, CHANNEL, text)
      end
    end
  end
  if kit.is_host() and not done_me then show(msg) end  -- the host before EMF reported their player
end

local function name_of(world, entity)
  local ok, name = pcall(world.character_name, world, entity)  -- the character name first (0.15.108)
  if not ok or type(name) ~= "string" or name == "" then ok, name = pcall(world.name, world, entity) end
  if not ok or type(name) ~= "string" or name == "" then name = "A player" end
  return (name:gsub("[%c]", " "))
end

-- An announcement from FlameKit to everyone with FlameKit (server world): see the top.
function F.announce(world, text)
  emf.log("announcement: " .. tostring(text))
  to_all(world, { t = tostring(text), c = "a" })
end

function F.setup(k)
  kit = k
  players.setup(k)
  local ok = emf.net.channel(CHANNEL, {
    version = 1, to = "players", max = 1024, per_10s = 100,
    on_player = kit.guard(F, function(world, from, data) show(emf.json.decode(data)) end, "a chat line from the server"),
  })
  if not ok then emf.log("the channel flamekit/chat was refused: chat is not copied to the Messages window") end
  local okc = pcall(emf.on_chat, kit.guard(F, function(world, account, entity, text)
    if type(text) ~= "string" or text == "" then return end
    local name = name_of(world, entity)
    to_all(world, { t = name .. ": " .. text:gsub("[%c]", " "), c = "c", n = name })
  end, "a chat line"))
  if not okc then emf.log("chat: emf.on_chat is not there: chat is not copied to the Messages window") end
end

return F
