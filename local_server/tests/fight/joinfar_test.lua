-- (0.15.379, owner 2026-11-21 11:54 "it took way too long for them to teleport to me, fix it") a follower farther than
-- JOIN_FAR from his player when the player joins is put away at once (back beside him once he stands on the ground).
-- texlua joinfar_test.lua /tmp/companions_bundle.lua ../../../flamekit/core/bag.lua
local file, bagfile = arg[1], arg[2]
local f = assert(io.open(file)) local text = f:read("a") f:close()
text = text:gsub("\nreturn F%s*$", "\nF._t = { drive_put_away = drive_put_away, inv = inv, roster = roster, find = find, ent_of = ent_of, drive_step = drive_step, drives = drives, name_of = name_of, roster_cmd = roster_cmd, admins = admins }\nreturn F\n")
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
  if n == "core.items" then return { max_stack = function(id) return id == 100 and 50 or 1 end } end
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

local function check(c, what) if not c then error("FAILED: " .. what, 2) end print("ok   " .. what) end
local Wf = { get = function(self, c, id) if c == "TeleportCount" then return { counter = 3 } end return nil end }
local function s_for(h, px, py, pz, nx, ny, nz)
  return { world = Wf, id = 501, h = h, t = 100, px = px, py = py, pz = pz, nx = nx, ny = ny, nz = nz }
end
local h = { player = 7, trail = {}, joined = true }
check(T.drive_put_away(s_for(h, 0, 34, 0, 57, 0, 0)) == true and h.go_away == "joined", "joined 57 m away and 34 m lower: put away at once")
h = { player = 7, trail = {}, joined = true }
check(not T.drive_put_away(s_for(h, 0, 0, 0, 8, 0, 0)) and h.go_away == nil and h.joined == nil, "joined 8 m away: keeps walking (looked at once)")
h = { player = 7, trail = {} }
check(not T.drive_put_away(s_for(h, 0, 0, 0, 57, 0, 0)) and h.go_away == nil, "no join: 57 m away is not put away by this rule")
print("ALL PASSED (joinfar)")
