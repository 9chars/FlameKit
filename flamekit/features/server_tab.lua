-- features/server_tab.lua (0.15.142, owner): the Server tab of FlameKit's window: settings that apply to the whole
-- server, every player and the whole world (core/server_settings.lua keeps them where the world is hosted). For now
-- anyone may change them (owner: protected later); a warning at the top says they affect everyone.
--
-- A player's game shows the values the server sent last (channel flamekit/srv: the server sends {op="state",values}
-- to every player when one changes and to a player who joins or asks); a click sends {op="set",key,value}. Where you
-- host the world yourself the setting is changed directly. On a server without this FlameKit the tab says so.

local players = require("core.players")
local server = require("core.server_settings")

local F = { id = "server_tab", title = "Server" }
local CHANNEL = "srv"
local kit

local shown = nil        -- the values the server sent (a player's game), or nil before any
local asked_at = -1e9
local steps = 0

local function state_text()
  return emf.json.encode({ op = "state", values = server.all() })
end

local function send_all(world)
  local me = emf.local_player()
  local text = state_text()
  for _, id in ipairs(players.ids(world)) do
    if not (id == me and kit.is_host()) then pcall(emf.net.send_to, world, id, CHANNEL, text) end
  end
end

-- a change, wherever it came from (`who`: a name for the log)
local function change(world, key, value, who)
  if server.set(key, value) then
    emf.log(string.format("server tab: %s set %s to %s", tostring(who), key, tostring(value)))
    send_all(world)
  end
end

local function values()
  if kit.is_host() then return server.all() end
  return shown and shown.values or nil
end

function F.panel(world)
  local rows = {
    { color = "#ff9632", text = "These settings are server wide: they apply to every player on this server and the "
      .. "whole world. Change them with care." },
    { separator = true },
  }
  local v = values()
  if not v then
    rows[#rows + 1] = { text = "No settings from the server yet (a server without this FlameKit version shows none)." }
    return rows
  end
  for _, s in ipairs(server.LIST) do
    if type(s.default) == "boolean" then
      local on = v[s.key] == true
      rows[#rows + 1] = { text = s.label, tooltip = s.tooltip }
      rows[#rows + 1] = { button = "on:" .. s.key, text = "On", selected = on, same_line = true, tooltip = s.tooltip }
      rows[#rows + 1] = { button = "off:" .. s.key, text = "Off", selected = not on, same_line = true, tooltip = s.tooltip }
    end
  end
  return rows
end

function F.click(world, key)
  local what, name = key:match("^(%a+):([%w_]+)$")
  if not what then return end
  local value = what == "on"
  if kit.is_host() then
    change(world, name, value, "the host")
  else
    pcall(emf.net.send, CHANNEL, emf.json.encode({ op = "set", key = name, value = value }))
  end
end

function F.client_tick(world)
  steps = steps + 1
  -- a player's game asks once a minute until the server answered (it also answers each join by itself)
  if not kit.is_host() and not shown and steps - asked_at >= 3600 then
    asked_at = steps
    pcall(emf.net.send, CHANNEL, emf.json.encode({ op = "get" }))
  end
end

function F.setup(k)
  kit = k
  players.setup(kit)
  local ok = emf.net.channel(CHANNEL, {
    version = 1, to = "both", max = 2048, per_10s = 20,
    on_server = kit.guard(F, function(world, from, data)
      local msg = emf.json.decode(data)
      if type(msg) ~= "table" or not from or not from.player or from.player == 0 then return end
      if msg.op == "set" and type(msg.key) == "string" then
        change(world, msg.key, msg.value, players.name(world, from.player, "a player"))
      end
      pcall(emf.net.send_to, world, from.player, CHANNEL, state_text())  -- the answer, also to "get"
    end, "a Server tab message from a player"),
    on_player = kit.guard(F, function(world, from, data)
      local msg = emf.json.decode(data)
      if type(msg) == "table" and msg.op == "state" and type(msg.values) == "table" then shown = msg end
    end, "the server settings from the server"),
  })
  if not ok then emf.log("server tab: the channel flamekit/srv was refused: the Server tab works only where you host") end
  pcall(emf.on_player_joined, kit.guard(F, function(world, p)
    if p and p.player and p.player ~= 0 then pcall(emf.net.send_to, world, p.player, CHANNEL, state_text()) end
  end, "a player joining"))
end

return F
