-- core/companion_net.lua (0.15.368): the companion system's two message channels, registered once (HANDOFF rule 0b).
-- Both ends of the companion system live in FlameKit now: features/companions (the server end: the wheel's picks, the
-- Companion Roster window's asks) and features/npc_wheel_probe (the player's end: the wheel, the roster window). In a
-- game someone hosts both run in one Lua state, and a second emf.net.channel of the same name would replace the
-- first one's handlers, so each side only sets its handler here; neither knows the other.
--   net.handle("npcwheel", "server", fn)   fn(world, from, data) on the server world
--   net.handle("roster", "player", fn)     ... on the player's game

local M = {}

local DEFS = {
  npcwheel = { max = 1024 },   -- the wheel: picks, calls, prefs; the server's answers (wheel, admin, notices)
  roster = { max = 16384 },    -- the Companion Roster window: its asks, the server's state
}
local handlers = { npcwheel = {}, roster = {} }
local registered = {}  -- name -> what emf.net.channel said (a reload starts over: the new functions are bound)

-- Sets this side's handler (side "server" or "player") and registers the channel the first time; true when the
-- channel is there.
function M.handle(name, side, fn)
  local h = assert(handlers[name], "companion_net: unknown channel " .. tostring(name))
  assert(side == "server" or side == "player", "companion_net: side is server or player")
  h[side] = fn
  if registered[name] == nil then
    registered[name] = emf.net.channel(name, { version = 1, to = "both", max = DEFS[name].max, per_10s = 60,
      on_server = function(world, from, data) if h.server then h.server(world, from, data) end end,
      on_player = function(world, from, data) if h.player then h.player(world, from, data) end end }) and true or false
  end
  return registered[name]
end

return M
