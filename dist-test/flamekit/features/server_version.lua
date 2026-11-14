-- features/server_version.lua: which FlameKit version the server runs, so the player sees when it is older.
--
-- A player's game asks the server half on the channel "ver" (to = both) once a minute and gets its version back
-- (kit.version, from the server's mod.json). kit.server_note() then gives the lower left notice (kit.lua hud_tick):
--   the server runs an older FlameKit: "This server runs FlameKit v0.15.30 (you: v0.15.45): some features are off"
--   the server's FlameKit has no "ver" channel at all (older than 0.15.45) but other FlameKit channels: "This server
--   runs an older FlameKit: some features are off"
-- (No FlameKit on the server at all: kit.connected is false and kit.lua says so.) Nothing in a world you host.

local F = { id = "server_version", title = "Server version" }

local kit
local CHANNEL = "ver"
local steps = 0
local server_version = nil  -- what the server half answered (this session), nil: no answer yet

function F.client_tick(world)
  steps = steps + 1
  if kit.is_host() or steps % 3600 ~= 120 then return end  -- 2 s after the world is there, then once a minute
  pcall(emf.net.send, CHANNEL, "?")
end

-- The notice for the lower left corner, or nil when the server's FlameKit is as new as this one (or unknown yet).
local function server_note(world)
  if kit.is_host() then return nil end
  if server_version then
    if kit.newer(kit.version, server_version) then
      return string.format("This server runs FlameKit v%s (you: v%s): some features are off", server_version, kit.version)
    end
    return nil
  end
  local ok, has = pcall(emf.net.peer, nil, 0, CHANNEL)
  if ok and (has or 0) == 0 and kit.connected(world) and steps > 600 then
    return "This server runs an older FlameKit: some features are off"
  end
  return nil
end

function F.setup(k)
  kit = k
  kit.server_note = server_note
  local ok = emf.net.channel(CHANNEL, {
    version = 1, to = "both", max = 32, per_10s = 10,
    on_server = kit.guard(F, function(world, from, data)
      if type(from) == "table" and from.player and from.player ~= 0 then pcall(emf.net.send_to, world, from.player, CHANNEL, kit.version) end
    end, "a version question"),
    on_player = kit.guard(F, function(world, from, data)
      if type(data) == "string" and data:match("^%d+%.%d+[%.%d]*$") then
        if data ~= server_version then kit.debug("info", "server version: the server runs FlameKit v%s (here v%s)", data, kit.version) end
        server_version = data
      end
    end, "the server's version"),
  })
  if not ok then kit.debug("warn", "server version: the channel flamekit/ver was refused") end
end

return F
