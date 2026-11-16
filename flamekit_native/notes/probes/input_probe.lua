-- input_probe.lua (2026-11-16, Fast Dive's crouch): a read-only probe. Not loaded by FlameKit: see README.md here.
-- Reads only: for each player, every server step, the buttons the player's game sends (PlayerInput.fromClient
-- .digitalInput, as bit numbers) and the actor's state bits (Actor.currentState: InSneakMode 21, HeadDiving 33,
-- Falling 32, Jumping 1, Grounded 0). Logs a line whenever either changes. Changes nothing.

local F = { id = "input_probe", title = "Input Probe" }

local players
local last = {}
local lines, minute = 0, 0

function F.setup(k)
  players = require("core.players")
  emf.log("[flamekit] input probe: loaded (reads buttons, logs only)")
end

local function bits_of(v)
  local out = {}
  for b = 0, 63 do
    if v & (1 << b) ~= 0 then out[#out + 1] = tostring(b) end
  end
  return #out > 0 and table.concat(out, ",") or "-"
end

function F.tick(world)
  if not world:is_server() then return end
  local t = world:tick()
  if t // 3600 ~= minute then minute, lines = t // 3600, 0 end
  for _, id in ipairs(players.ids(world)) do
    pcall(function()
      local inp = world:get("PlayerInput", id)
      local a = world:get("Actor", id)
      if not inp then return end
      local d = math.tointeger(inp.fromClient.digitalInput) or 0
      local cs = a and math.tointeger(a.currentState) or 0
      local ai = world:get("ActorInput", id)
      local ps = world:get("PlayerState", id)
      local speed = ai and tostring(ai.locomotionSpeed) or "?"
      local lastspeed = ai and tostring(ai.lastLocomotionSpeed) or "?"
      local mask = ps and math.tointeger(ps.playerStateMask) or -1
      local o = last[id] or {}
      if (d ~= o.d or cs ~= o.cs or speed ~= o.speed or mask ~= o.mask) and lines < 600 then
        lines = lines + 1
        local move = world:get("DynamicLocomotion", id)
        emf.log(string.format("[flamekit] input probe: entity %d tick %d buttons [%s] state bits [%s] movement %s speed %s (last %s) playerStateMask [%s]",
          id, t, bits_of(d), bits_of(cs), move and tostring(move.state) or "?", speed, lastspeed, bits_of(mask)))
      end
      o.d, o.cs, o.speed, o.mask = d, cs, speed, mask
      last[id] = o
    end)
  end
end

return F
