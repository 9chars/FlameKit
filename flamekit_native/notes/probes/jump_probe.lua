-- jump_probe.lua (2026-11-16, Super B Jump): a read-only probe. Not loaded by FlameKit: see README.md here.
-- Reads only: for each player, every server step, the jump button (PlayerInput), DynamicLocomotion state, previous
-- state and jumpCount, the height and the upward speed. Logs a line when the button, the state or jumpCount change,
-- and the height every 6 steps (0.1 s) for 3 s after a press. Changes nothing in the game.

local F = { id = "jump_probe", title = "Jump Probe" }

local JUMP_BIT = 137438953472  -- the same bit experimental.lua reads for the glider burst
local players
local last = {}   -- entity id -> { jump, state, count, follow }
local lines = 0   -- per minute, at most 400
local minute = 0

function F.setup(k)
  players = require("core.players")
  emf.log("[flamekit] jump probe: loaded (reads jumps, logs only)")
end

local function n(v) return tonumber(tostring(v)) end

local skills_told = {}
local DOUBLE_JUMP = 0xffd5f940  -- skill tree node whose unlock item is Ability_DoubleJump (game files, 2026-11-16)

local function hv(v)
  if type(v) == "table" then v = v.value or v.id or v[1] end
  return math.tointeger(tonumber(tostring(v))) or -1
end

local function tell_skills(world, id)
  if skills_told[id] then return end
  skills_told[id] = true
  local ok, err = pcall(function()
    local u = world:get("UnlockedSkillNodes", id)
    if not u then emf.log("[flamekit] jump probe: entity " .. id .. " has no UnlockedSkillNodes") return end
    local count, has, sample = 0, false, {}
    for k = 1, 256 do
      local h = hv(u.knownSkillNodes[k]) & 0xffffffff
      if h ~= 0 then
        count = count + 1
        if h == DOUBLE_JUMP then has = true end
        if #sample < 12 then sample[#sample + 1] = string.format("%08x", h) end
      end
    end
    emf.log(string.format("[flamekit] jump probe: entity %d skills: %d known, double jump node ffd5f940 %s; first: %s",
      id, count, has and "FOUND" or "not found", table.concat(sample, " ")))
  end)
  if not ok then emf.log("[flamekit] jump probe: skills unreadable: " .. tostring(err)) end
end

function F.tick(world)
  if not world:is_server() then return end
  for _, id in ipairs(players.ids(world)) do tell_skills(world, id) end
  local t = world:tick()
  if t // 3600 ~= minute then minute, lines = t // 3600, 0 end
  for _, id in ipairs(players.ids(world)) do
    pcall(function()
      local inp = world:get("PlayerInput", id)
      local move = world:get("DynamicLocomotion", id)
      if not (inp and move) then return end
      local v = world:get("Velocity", id)
      local _, y = world:position(id)
      local jump = (math.tointeger(inp.fromClient.digitalInput) or 0) & JUMP_BIT ~= 0
      local st, prev, count = n(move.state), n(move.previousState), n(move.jumpCount)
      local vy = v and v.velocity.y or 0
      local okst, stam = pcall(emf.attribute, world, id, "stamina")
      stam = okst and tonumber(stam) or -1
      local o = last[id] or {}
      -- (fixed 2026-11-16: these lines used `o` before it existed, so every step failed silently)
      local stam_changed = o.stam and math.abs(stam - o.stam) >= 0.5 and stam < o.stam
      local changed = jump ~= o.jump or st ~= o.state or count ~= o.count or stam_changed
      if jump and not o.jump then o.follow = t + 180 end
      local follow = o.follow and t <= o.follow and (t % 6 == 0)
      if (changed or follow) and lines < 400 then
        lines = lines + 1
        emf.log(string.format("[flamekit] jump probe: entity %d tick %d jump %s state %s prev %s jumpCount %s y %.2f vy %.2f stamina %.1f%s",
          id, t, jump and "DOWN" or "up", tostring(st), tostring(prev), tostring(count), y or -1, vy, stam,
          changed and "" or " (follow)"))
      end
      o.jump, o.state, o.count, o.stam = jump, st, count, stam
      last[id] = o
    end)
  end
end

return F
