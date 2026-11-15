-- features/server_version.lua: which FlameKit version the server runs, so the player sees when it is older.
--
-- A player's game asks the server half on the channel "ver" (to = both) once a minute and gets its version back
-- (kit.version, from the server's mod.json). kit.server_note() then gives an orange line in the Messages window (kit.lua
-- server_messages, since 0.15.117; a short notice in 0.15.114, a line in the lower left corner before):
--   the server runs an older FlameKit: "Server runs older FlameKit v0.15.30!"
--   the server's FlameKit has no "ver" channel at all (older than 0.15.45) but other FlameKit channels: "Server runs
--   an older FlameKit!"
-- (No FlameKit on the server at all: kit.connected is false and kit.lua says "FlameKit not supported by server!".)
-- (0.15.138, owner: compatibility) the server answers with its version and then "min <version>": the oldest game it
-- works with (kit.MIN_GAME). The orange line now appears only when the two do not work together:
--   this game is older than the server's minimum: "This server needs FlameKit vX or newer: restart your game to update."
--   the server is older than this game's minimum (kit.MIN_SERVER): "Server runs FlameKit vX, too old for this game: ..."
-- An older server that still works with this game gets only the white "Server runs FlameKit vX." line.
-- Older games ignore the "min" message (it is not a version), older servers send none.
-- Nothing in a world you host.

local F = { id = "server_version", title = "Server version" }

local kit
local CHANNEL = "ver"
local steps = 0
local server_version = nil  -- what the server half answered (this session), nil: no answer yet
local server_min_game = nil  -- (0.15.138) the oldest game the server works with, nil: not said (an older server)

local session_seen = nil
function F.client_tick(world)
  local okS, session = pcall(emf.session)
  if session ~= session_seen then  -- another game session (maybe another server): its version is asked again
    session_seen = session
    server_version, server_min_game = nil, nil
    steps = 0
  end
  steps = steps + 1
  if kit.is_host() or steps % 3600 ~= 120 then return end  -- 2 s after the world is there, then once a minute
  pcall(emf.net.send, CHANNEL, "?")
end

-- The short orange notice (kit.lua server_notices), or nil when the server's FlameKit is as new as this one (or unknown yet).
local function server_note(world)
  if kit.is_host() then return nil end
  if server_min_game and kit.newer(server_min_game, kit.version) then
    return string.format("This server needs FlameKit v%s or newer: restart your game to update.", server_min_game)
  end
  if server_version then
    if kit.newer(kit.MIN_SERVER, server_version) then
      return string.format("Server runs FlameKit v%s, too old for this game: some features will not work. Ask the server's owner to update it.", server_version)
    end
    return nil
  end
  local ok, has = pcall(emf.net.peer, nil, 0, CHANNEL)
  if ok and (has or 0) == 0 and kit.connected(world) and steps > 600 then
    return "Server runs an older FlameKit!"
  end
  return nil
end

function F.setup(k)
  kit = k
  kit.server_note = server_note
  kit.server_version = function() return server_version end  -- (0.15.117) for the "Server runs FlameKit vX." message
  local ok = emf.net.channel(CHANNEL, {
    version = 1, to = "both", max = 32, per_10s = 10,
    on_server = kit.guard(F, function(world, from, data)
      if type(from) == "table" and from.player and from.player ~= 0 then
        pcall(emf.net.send_to, world, from.player, CHANNEL, kit.version)
        pcall(emf.net.send_to, world, from.player, CHANNEL, "min " .. kit.MIN_GAME)  -- (0.15.138)
      end
    end, "a version question"),
    on_player = kit.guard(F, function(world, from, data)
      local min = type(data) == "string" and data:match("^min (%d+%.%d+[%.%d]*)$")
      if min then server_min_game = min return end
      if type(data) == "string" and data:match("^%d+%.%d+[%.%d]*$") then
        if data ~= server_version then kit.debug("info", "server version: the server runs FlameKit v%s (here v%s)", data, kit.version) end
        server_version = data
      end
    end, "the server's version"),
  })
  if not ok then kit.debug("warn", "server version: the channel flamekit/ver was refused") end
end

return F
