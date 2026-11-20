-- Companion inventory (owner 2026-11-20 07:54/08:02) in a fake world: the chest is filled from his record, the
-- player takes and adds items, the chest is closed (or closes itself), and his record holds exactly what was in it.
-- texlua invtest.lua ../../features/npc_probe.lua ../../../flamekit/core/bag.lua
local file, bagfile = arg[1], arg[2]
local f = assert(io.open(file)) local text = f:read("a") f:close()
text = text:gsub("\nreturn F%s*$", "\nF._t = { inv = inv, roster = roster, find = find, drive_step = drive_step, drives = drives, name_of = name_of }\nreturn F\n")
local logs, saved = {}, {}
TICK = 0
local comps, pos = {}, {}
local SESSION = 1
local W = {}
function W:tick() return TICK end
function W:get(c, id) local e = comps[id] return e and e[c] end
function W:position(id) local p = pos[id] if p then return p[1], p[2], p[3] end end
function W:is_server() return true end
function W:account() return "acc" end
local next_id, slots_per_inv = 9000, 8
local next_pide = 50000
local REFUSE_UNTIL = {}  -- chest -> tick before which a put adds nothing (a fresh chest)
local emf = setmetatable({
  log = function(s) logs[#logs + 1] = "[" .. TICK .. "] " .. s end,
  session = function() return SESSION end,
  hit_rule = function() return 77 end, hit_rule_remove = function() end,
  save_world_data = function(t) saved[#saved + 1] = t return true end,
  json = { encode = function(t) return "json" end, decode = function() return {} end },
  net = { send_to = function() end, channel = function() return true end },
  dir = "/tmp",
  spawn = function(w, g, x, y, z)
    next_id = next_id + 10
    local id = next_id
    pos[id] = { x, y, z }
    local links = {}
    for k = 1, 5 do links[k] = id + k comps[id + k] = { Inventory = { slots = {} } } for s = 1, slots_per_inv do comps[id + k].Inventory.slots[s] = { id = 0, data = { count = 0, pide = 0 } } end end
    comps[id] = { InventorySetup = { linksEntities = links } }
    REFUSE_UNTIL[id] = TICK + 20
    return id
  end,
  destroy = function(w, id) pos[id], comps[id] = nil, nil end,
  put = function(w, chest, item, count, fn, opts)
    -- answered a tick later, like the game: a fresh chest adds nothing; gear (level/rarity given) one per slot
    PENDING[#PENDING + 1] = function()
      local added = 0
      if TICK >= REFUSE_UNTIL[chest] and comps[chest] then
        for _, inv in ipairs(comps[chest].InventorySetup.linksEntities) do
          for _, sl in ipairs(comps[inv].Inventory.slots) do
            if added < count then
              if opts then
                if sl.id == 0 then
                  next_pide = next_pide + 1
                  comps[next_pide] = { ItemState = { itemRarityUi = opts.rarity, itemLevelUi = opts.level } }
                  sl.id, sl.data = item, { count = 1, pide = next_pide } added = added + 1
                end
              elseif sl.id == item or sl.id == 0 then
                local n = math.min(count - added, 50 - (sl.id == item and sl.data.count or 0))
                if n > 0 then sl.data.count = (sl.id == item and sl.data.count or 0) + n sl.id = item added = added + n end
              end
            end
          end
        end
      end
      fn(w, added)
    end
    return true
  end,
}, { __index = function(_, k) return function() end end })
PENDING = {}
local bagenv = setmetatable({ emf = emf }, { __index = _G })
local bag = assert(loadfile(bagfile, "t", bagenv))()
local env = setmetatable({ emf = emf, require = function(n) if n == "core.bag" then return bag end
  return setmetatable({}, { __index = function() return function() return {} end end }) end }, { __index = _G })
local F = assert(load(text, "=" .. file, "t", env))()
local T = F._t
local function step() TICK = TICK + 1 local p = PENDING PENDING = {} for _, fn in ipairs(p) do fn() end F.tick(W) end
local function chest_items(c)
  local out = {}
  for _, inv in ipairs(comps[c].InventorySetup.linksEntities) do for _, sl in ipairs(comps[inv].Inventory.slots) do
    if sl.id ~= 0 then out[#out + 1] = sl end end end
  return out
end
local function show(title, r) local parts = {}
  for _, e in ipairs(r.inv or {}) do parts[#parts + 1] = e.item .. "x" .. e.count .. (e.level and ("@L" .. e.level .. "/R" .. e.rarity) or "") end
  print(title .. ": " .. table.concat(parts, " ")) end

-- his record: 30 wood, 5 potions, a legendary sword level 10, a rare axe level 7
T.roster.loaded = true
local r = { name = "N1", controllers = { "acc" }, names = {}, inv = { { item = 100, count = 30 }, { item = 200, count = 5 },
  { item = 300, count = 1, level = 10, rarity = 4 }, { item = 301, count = 1, level = 7, rarity = 2 } } }
T.roster.list = { r }
pos[500] = { 0, 0, 0 } comps[500] = { CurrentTransform = { transform = { orientation = { x = 0, y = 0, z = 0, w = 1 } } } }
T.name_of[500] = "N1"
show("record at the start", r)
T.inv.open_chest(W, 1, 500, r)
for _ = 1, 120 do step() end
local c = T.inv.open.N1
print("state after 2 s:", c and c.state, "chest stacks:", #chest_items(c.chest))
-- the player takes 10 wood out and puts in a gem-socketed weapon (item 400, level 9, rarity 3, gem 900)
for _, sl in ipairs(chest_items(c.chest)) do if sl.id == 100 then sl.data.count = 20 end end
local inv1 = comps[c.chest].InventorySetup.linksEntities[5]
next_pide = next_pide + 1
comps[next_pide] = { ItemState = { itemRarityUi = 3, itemLevelUi = 9 }, WeaponGemSlot = { weaponGem = { id = 900 } } }
comps[inv1].Inventory.slots[8] = { id = 400, data = { count = 1, pide = next_pide } }
for _ = 1, 70 do step() end
show("record while open (saved every second)", r)
T.inv.close_chest(W, 1, 500, r)
print("after close: open?", T.inv.open.N1 ~= nil, "chest still there?", pos[c.chest] ~= nil, "r.chest", r.chest)
show("record after close", r)
-- open again: everything comes back, the gem as its own item
T.inv.open_chest(W, 1, 500, r)
for _ = 1, 120 do step() end
c = T.inv.open.N1
local parts = {}
for _, sl in ipairs(chest_items(c.chest)) do local st = comps[sl.data.pide] and comps[sl.data.pide].ItemState
  parts[#parts + 1] = sl.id .. "x" .. sl.data.count .. (st and ("@L" .. tostring(st.itemLevelUi) .. "/R" .. tostring(st.itemRarityUi)) or "") end
print("chest on the second open: " .. table.concat(parts, " "))
-- frozen: his drive does nothing while it is open
-- forgotten: closes itself after 5 minutes
for _ = 1, 5 * 3600 + 5 do step() end
print("after 5 minutes: open?", T.inv.open.N1 ~= nil)
show("record after the auto-close", r)
-- a chest that vanished: closing keeps the last save
T.inv.open_chest(W, 1, 500, r)
for _ = 1, 120 do step() end
c = T.inv.open.N1
pos[c.chest], comps[c.chest] = nil, nil
T.inv.close_chest(W, 1, 500, r)
print("vanished chest: open?", T.inv.open.N1 ~= nil)
show("record after the vanished chest", r)
-- a script reload while open: the chest is taken up again
T.inv.open_chest(W, 1, 500, r)
for _ = 1, 120 do step() end
local old = T.inv.open.N1.chest
T.inv.open.N1 = nil
T.inv.adopt(W, r)
print("reload while open: taken up again?", T.inv.open.N1 ~= nil and T.inv.open.N1.chest == old)
-- a server restart while open: the chest is gone with the run, the record keeps the last save
T.inv.open.N1 = nil
SESSION = 2
pos[old], comps[old] = nil, nil
T.inv.adopt(W, r)
print("restart while open: r.chest", r.chest, "open?", T.inv.open.N1 ~= nil)
show("record after the restart", r)
for _, l in ipairs(logs) do if l:find("inventory") then print(l) end end
