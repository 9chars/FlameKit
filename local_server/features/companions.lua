-- features/companions.lua (0.15.362, owner 2026-11-20 18:11 "go ahead" with the cleanup): the companion system, server
-- side (it was features/npc_probe.lua, 4,000 lines at Lua's limit of 200 top-level locals). Its parts are in
-- features/companions/, in this order. They run in ONE shared environment: what was a top-level local is a name in it,
-- seen by every part (a part may use a name another part defines, as long as it is defined by the time it is used).
-- The game side is features/npc_wheel_probe.lua (the wheel, the Companion Roster window).
local PARTS = {
  "01_base",          -- F, the log (and the companion debug log switch), notices
  "02_fullrec",       -- the full recorder (a debug tool: every field of an entity into a file)
  "03_follow",        -- the drive: following, the trail, water, jumps, stuck, places around the player
  "04_roster",        -- staying, the roster (FlameKit's list of companions), spawning, names
  "05_inventory",     -- the companion's chest
  "06_wheel",         -- E and the wheel
  "07_fight",         -- threats, the monster scan, picking targets
  "08_heal_attack",   -- healing, the attack sequence
  "09_setup",         -- the console commands (with the test tools), events, channels
  "10_tick",          -- put away and back, F.tick
  "11_roster_window", -- the Companion Roster window, pets, the Companions wheel
}
local env = {}
for k, v in pairs(_G) do env[k] = v end  -- the standard names, looked up directly (no __index on every call)
setmetatable(env, { __index = _G })
local F
for _, name in ipairs(PARTS) do
  local path = emf.dir .. "\\features\\companions\\" .. name .. ".lua"
  local chunk, err
  if load then
    local f = assert(io.open(path, "r"), "companions: cannot open " .. path)
    local text = f:read("a")
    f:close()
    chunk, err = load(text, "@features/companions/" .. name .. ".lua", "t", env)
  else  -- (EMF's Lua documents loadfile; load is the standard one)
    chunk, err = loadfile(path, "t", env)
  end
  if not chunk then error("companions: " .. name .. ": " .. tostring(err)) end
  F = chunk() or F
end
return F
