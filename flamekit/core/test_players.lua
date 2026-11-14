-- core/test_players.lua: made-up players for testing multiplayer features alone (party window, minimap).
--
-- A player asks for 1 to 6 test players (FlameKit's window, tab Party). Where the world is hosted (your own game, or a
-- server with FlameKit), the hosting half then adds them to the lists it sends to THAT player only, the same way real
-- players are sent: the party list (features/party.lua) and the far players for the minimap (features/minimap.lua).
-- So the whole path is tested: the server half, the network, the player's game, the files and the DLL's drawing.
-- Other players never see someone else's test players. Nothing is saved: a server restart forgets them (the player's
-- game asks again every 10 s while they are on).
--
-- Each test player walks around you in a circle at its own distance (some near, some far beyond what your game sees
-- itself, so they show at the minimap's edge), with health and mana that go up and down; Test Dain is down (0 health)
-- for 4 s every 20 s. They carry buffs and debuffs of the game's own types (since 0.15.49), with timers that run down
-- and start again, so the party window's buff row can be tested too.

local T = {}

T.MAX = 6
local NAMES = { "Test Ayla", "Test Bram", "Test Cora", "Test Dain", "Test Esme", "Test Finn" }
local DIST = { 25, 70, 160, 400, 900, 2000 }  -- metres from you
local LEVEL = { 12, 25, 33, 41, 50, 8 }

-- the game's buff types (ids as EMF gives them; game build 1287369): type, slot (0 food, 1 buff, 2 debuff, 3 rested), time
local BUFFS = {
  { 0xAC13C6C3, 2, 900 },  -- Wet
  { 0xFF24634F, 1, 1800 }, -- Elixir Buff
  { 0xCDBE9C80, 3, 600 },  -- Rested
  { 0x369C3618, 2, 30 },   -- Poisoned
  { 0x44B408C6, 2, 120 },  -- Cold
  { 0xFA042AF9, 1, 300 },  -- a Flame prayer
}

local wanted = {}  -- player entity id -> how many test players

function T.set(id, n)
  n = math.max(0, math.min(T.MAX, math.floor(tonumber(n) or 0)))
  wanted[id] = n > 0 and n or nil
  return n
end

function T.count(id)
  return wanted[id] or 0
end

-- Drops the wishes of players no longer in the world (`present`: entity id -> true).
function T.keep_only(present)
  for id in pairs(wanted) do
    if not present[id] then wanted[id] = nil end
  end
end

-- The test players for player `id`, now: { name, x, z (nil: your place is not known), hp, hp_max, mana, mana_max, level,
-- buffs ("<type hex>:<slot>:<seconds left>,...", as features/party.lua sends them) }.
function T.list(world, id)
  local n = wanted[id]
  if not n then return {} end
  local ok, x, _, z = pcall(world.position, world, id)
  if not ok or type(x) ~= "number" or type(z) ~= "number" then x, z = nil, nil end
  local t = os.time()
  local out = {}
  for i = 1, n do
    local p = { name = NAMES[i], level = LEVEL[i] }
    if x then
      local turn = (i % 2 == 0) and -1 or 1
      local a = i * 1.047 + turn * t * (0.6 / math.sqrt(DIST[i]))
      p.x = math.max(0, math.min(10240, x + math.cos(a) * DIST[i]))
      p.z = math.max(0, math.min(10240, z + math.sin(a) * DIST[i]))
    end
    p.hp_max = 400 + LEVEL[i] * 42
    p.mana_max = 120 + LEVEL[i] * 7
    local wave = 0.5 + 0.5 * math.sin(t * 0.35 + i * 1.3)
    p.hp = math.floor(p.hp_max * (0.25 + 0.75 * wave) + 0.5)
    p.mana = math.floor(p.mana_max * (0.5 + 0.5 * math.cos(t * 0.5 + i)) + 0.5)
    if i == 4 and t % 20 < 4 then p.hp = 0 end
    local list = {}
    for k = 1, (i % 4) + 1 do  -- 2, 3, 4, 1, 2, 3 different buffs
      local b = BUFFS[((i + k - 1) % #BUFFS) + 1]
      list[#list + 1] = string.format("%x:%d:%d", b[1], b[2], b[3] - (t + i * 37) % b[3])
    end
    p.buffs = table.concat(list, ",")
    out[#out + 1] = p
  end
  return out
end

return T
