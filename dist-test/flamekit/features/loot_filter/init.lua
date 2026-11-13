-- features/loot_filter: your own junk list. Junk is removed from your backpack when you loot it, or with one button.
--
-- Two halves, in one mod that is installed on both sides:
--   server.lua  runs where the world is hosted (your own game, or a dedicated server). Only that side may change an
--               inventory, so it does the removing, for each player by their own list.
--   client.lua  runs in your own game: your list (a file), the panel, the keys. It tells the server half what you want.
-- In a world you host both halves are in the same game and call each other directly. On a server you joined they
-- talk over EMF's mod messages on the channel "flamekit/lf".

local F = { id = "loot_filter", title = "Auto Junk List", enabled_setting = "lf_enabled" }

local server = require("features.loot_filter.server")
local client = require("features.loot_filter.client")

function F.setup(kit)
  server.setup(kit, F)
  client.setup(kit, F, server)
  server.to_local = client.receive

  local ok = emf.net.channel(server.CHANNEL, {
    version = 1, to = "both", max = 16384, per_10s = 60,
    -- a joined player's game -> this server: `from` is the server's own record of who sent it
    on_server = kit.guard(F, function(world, from, data)
      local msg = emf.json.decode(data)
      if msg then server.handle(world, { player = from.player, account = from.account }, msg) end
    end, "a message from a player"),
    -- the server -> this game
    on_player = kit.guard(F, function(world, from, data)
      local msg = emf.json.decode(data)
      if msg then client.receive(world, msg) end
    end, "a message from the server"),
  })
  if not ok then emf.log("the channel flamekit/lf was refused: the Auto Junk List works only in worlds you host") end
end

function F.tick(world)
  server.tick(world)
  client.server_tick(world)  -- in a world you host: your list goes straight to the server half
end

F.client_tick = client.client_tick
F.connected = client.connected
F.setting_changed = client.setting_changed
F.panel = client.panel
F.click = client.click

return F
