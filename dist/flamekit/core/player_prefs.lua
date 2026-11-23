-- core/player_prefs.lua (0.15.376, owner 2026-11-21 09:35): the player's own choices the server needs to know (their
-- Settings tab: Auto Loot, later the Messages tab switches). The player's game sends them on channel flamekit/prefs
-- when one changes and every 30 s (a server that restarted or reloaded learns them again); the server keeps them per
-- account for this run. A player whose game sends nothing (no FlameKit, an older one) has none: every feature then uses
-- its own default (Auto Loot: the game's own behaviour).
-- Shared core code (HANDOFF rule 0b):
--   prefs.setup()                          once from a feature's setup (any number of features may call it)
--   prefs.client_tick(world, values, host) the player's game: values = { key = value, ... } (strings, numbers, booleans)
--   prefs.get(account, key, world)         the server: that player's value, or nil

local prefs = {}

local CHANNEL = "prefs"
local SEND_EVERY = 1800  -- steps (30 s)
local by_account = {}    -- the server: account -> { key = value }
local registered = nil
local last_sent, sent_at = nil, -1e9

-- The account a net message came from (from its player entity when the account is missing).
local function who(world, from)
  local acc = from and from.account
  if (not acc or tostring(acc):match("^0x0*$")) and from and from.player then
    local ok, a = pcall(world.account, world, from.player)
    if ok and a then acc = a end
  end
  return acc
end

-- The server: a player's game sent its values ("set"): keeps them for that account, checked (at most 32 short values).
local function on_server(world, from, data)
  local ok, m = pcall(emf.json.decode, data)
  if not (ok and type(m) == "table" and m.op == "set" and type(m.values) == "table") then return end
  local acc = who(world, from)
  if not acc then return end
  local clean, n = {}, 0
  for k, v in pairs(m.values) do
    local tv = type(v)
    if type(k) == "string" and #k <= 32 and (tv == "boolean" or tv == "number" or (tv == "string" and #v <= 64)) and n < 32 then
      clean[k] = v
      n = n + 1
    end
  end
  local had = by_account[acc]
  by_account[acc] = clean
  if not had then emf.log(string.format("prefs: player %s: %d value(s)", tostring(from and from.player), n)) end
end

-- Opens the preferences' net channel to the server (once); true when it is open.
function prefs.setup()
  if registered ~= nil then return registered end
  registered = emf.net.channel(CHANNEL, { version = 1, to = "server", max = 1024, per_10s = 30,
    on_server = function(world, from, data)
      local ok, err = pcall(on_server, world, from, data)
      if not ok then emf.log("prefs: " .. tostring(err)) end
    end }) and true or false
  return registered
end

-- `host`: this game hosts the world (kit.is_host()): its own values are kept here directly, no message
local host_values = nil  -- the hosting player's own values (his game and the server world are one Lua state)
-- The player's game: sends its values to the server when they change, and every SEND_EVERY steps (kept directly in a game that hosts).
function prefs.client_tick(world, values, host)
  if not registered then return end
  if host then
    host_values = values  -- (world:account is for the server world only: prefs.get matches him there)
    return
  end
  local ok, text = pcall(emf.json.encode, { op = "set", values = values })
  if not ok then return end
  local now = world:tick()
  if text ~= last_sent or now - sent_at > SEND_EVERY or now < sent_at then
    local oks, sent = pcall(emf.net.send, CHANNEL, text)
    if oks and sent then last_sent, sent_at = text, now end
  end
end

-- `world` (the server world, optional): lets the hosting player's own values be found
function prefs.get(account, key, world)
  local t = account and by_account[account]
  if t == nil and host_values and world then
    local ok, a = pcall(world.account, world, emf.local_player())
    if ok and a == account then t = host_values end
  end
  if t == nil then return nil end
  return t[key]
end

return prefs
