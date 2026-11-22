-- features/water_debug.lua (0.15.450, owner 2026-11-22 16:03 "I don't see a water source piece so I'm concerned its still
-- there?", 16:04 "go ahead"): a debug command that lists the water entities near a player, to find water pieces the game
-- still simulates (the server log's "[Water] BlockWater Entity not found: Outside of Simulation area", and two crashes
-- in the game's water flow code: crash_reports\2026-11-22_*). Nothing in the world changes.
--
--   /flamekit.water [radius]   (chat or console; admins only; radius in m, default 100, at most 1000)
-- Every entity within `radius` of the player that has one of the game's water components (BlockWater, WaterDispenser,
-- WaterDrain, WaterEffector) goes into the server's log (emf_core.log) as "water debug: ..." with its id, position,
-- distance and components; at most LINES_MAX lines, then the counts. The world's entities (some 37,000) are walked a
-- slice per server step (SLICE entities), so no step takes long; the player is told in chat when it starts and the
-- counts when it is done.
-- Uses only core modules (HANDOFF rule 0b).

local admins = require("core.admins")

local F = { id = "water_debug", title = "Water Debug" }  -- no panel: not a tab
local kit

local COMPONENTS = { "BlockWater", "WaterDispenser", "WaterDrain", "WaterEffector" }
local SLICE, LINES_MAX, RADIUS_DEFAULT, RADIUS_MAX = 2000, 80, 100, 1000

local scan = nil  -- the scan under way: { ids, i, x, y, z, r, found, lines, by = player, account }

-- Whether entity `id` has component `c` (false when it cannot be read).
local function has(world, c, id)
  local ok, v = pcall(world.get, world, c, id)
  return ok and v ~= nil
end

-- Logs one line of the scan, up to LINES_MAX.
local function line(text)
  if scan.lines < LINES_MAX then emf.log("water debug: " .. text) end
  scan.lines = scan.lines + 1
end

-- One slice of the scan: SLICE entities looked at; at the end the counts (log and the player's chat line).
local function scan_tick(world)
  local ids, last = scan.ids, math.min(#scan.ids, scan.i + SLICE - 1)
  local r2 = scan.r * scan.r
  for k = scan.i, last do
    local id = ids[k]
    local okp, x, y, z = pcall(world.position, world, id)
    if okp and x then
      local d2 = (x - scan.x) ^ 2 + (y - scan.y) ^ 2 + (z - scan.z) ^ 2
      if d2 <= r2 then
        local comps = {}
        for _, c in ipairs(COMPONENTS) do
          if has(world, c, id) then
            comps[#comps + 1] = c
            scan.found[c] = (scan.found[c] or 0) + 1
          end
        end
        if #comps > 0 then
          line(string.format("entity %d at %.1f %.1f %.1f (%.0f m): %s", id, x, y, z, math.sqrt(d2), table.concat(comps, " ")))
        end
      end
    end
  end
  scan.i = last + 1
  if scan.i <= #ids then return end
  local parts = {}
  for _, c in ipairs(COMPONENTS) do parts[#parts + 1] = string.format("%s %d", c, scan.found[c] or 0) end
  local summary = string.format("within %d m of %.0f %.0f %.0f: %s (%d entities looked at%s)", scan.r, scan.x, scan.y, scan.z,
    table.concat(parts, ", "), #ids, scan.lines > LINES_MAX and string.format("; %d lines, the first %d logged", scan.lines, LINES_MAX) or "")
  emf.log("water debug: done: " .. summary)
  pcall(emf.net.send_to, world, scan.by, "chat", emf.json.encode({ t = "Water debug: " .. summary, c = "n", nc = "#8cd2ff", ns = 30 }))
  scan = nil
end

-- The command: checks the admin, then starts a scan around the player who typed it.
local function command(world, args)
  local who = emf.sender()
  local player, account = nil, nil
  if who and who.chat then player, account = who.entity, who.account
  else
    player = emf.local_player()
    local ok, a = pcall(world.account, world, player)
    account = ok and a or nil
  end
  if not admins.is(account, who) then emf.reply("Only FlameKit admins can use flamekit.water.") return end
  if not player or player == 0 then emf.reply("flamekit.water: no player to look around.") return end
  if scan then emf.reply("flamekit.water: a scan is still under way.") return end
  local x, y, z = world:position(player)
  if not x then emf.reply("flamekit.water: your position cannot be read.") return end
  local r = math.max(1, math.min(RADIUS_MAX, math.floor(tonumber(args[1]) or RADIUS_DEFAULT)))
  local okl, ids = pcall(world.entities, world)
  if not okl or type(ids) ~= "table" then emf.reply("flamekit.water: the world's entities cannot be read.") return end
  scan = { ids = ids, i = 1, x = x, y = y, z = z, r = r, found = {}, lines = 0, by = player, account = account }
  emf.log(string.format("water debug: started by player %s within %d m of %.1f %.1f %.1f (%d entities)", tostring(player), r, x, y, z, #ids))
  emf.reply(string.format("flamekit.water: looking at %d entities within %d m of you; the result comes in a few seconds.", #ids, r))
end

-- Every server step: the scan under way, one slice.
function F.tick(world)
  if not scan or not world:is_server() then return end
  local ok, err = pcall(scan_tick, world)
  if not ok then
    emf.log("water debug: the scan failed: " .. tostring(err))
    scan = nil
  end
end

-- Registers the command (chat and console).
function F.setup(k)
  kit = k
  pcall(emf.command, "water", "[radius]: lists the water entities near you into the server's log (admins; debug)",
    kit.guard(F, command, "the water command"), { players = true })
end

return F
