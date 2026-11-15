-- core/loot_chest.lua (0.15.154, owner: "all other loot that drops needs to go into a large chest that you spawn and
-- store there"; "if a chest becomes full, you spawn another chest"): loot stored in storage chests FlameKit spawns.
-- (0.15.155, owner: players run around, "put it into the next nearest chest. even chests spawned from other player
-- kills could be used") loot goes into the nearest of FlameKit's chests that is not full, anyone's, within NEAR_M of
-- where the loot comes from; none there: a new chest at that spot. A chest a put did not fit into counts as full from
-- then on, and the rest goes into the next one. A chest is removed only once it was used and is empty again (owner: "the
-- chest cant despawn until the users get a chance to empty it"). Spawned entities are not saved by the game (EMF
-- re_villages.md): a server restart loses the chests.
-- (0.15.160) No tag on the chest any more: a chest spawned with a ScaleComponent (0.15.157-0.15.159) refused every put
-- ("put_items: the game refused a request (error 0x15)"). FlameKit remembers its chests in loot_chests.dat instead (with
-- the server session, so a restart's new entities are never taken for old chests), and a new chest gets PUT_WAIT steps
-- before the first put, with RETRIES tries, instead of being taken as full at once (that made a second chest).
-- Shared core code (HANDOFF rule 0b): any feature may use it; it uses no feature.

local M = {}

-- 0.15.154's Prop_Decoration_T4_Storage_56 looked like "a magical chest designed to be used inside a base" (owner);
-- 0.15.157's treasure chest (Base_LootChest_Animgraph2_Random) refused every put.
M.CHEST = "0c667e7e-0fbd-4cb9-b58d-c3a20df7eaec"  -- Prop_Decoration_T5_Storage_40_Chest (40 slots)
M.NEAR_M = 50
M.MAX_CHESTS = 100  -- all owners together
local PUT_WAIT = 30  -- steps (0.5 s) between a chest's spawn and the first put into it
local RETRIES = 3    -- a refused put into a chest under 5 s old is tried again this often before the chest counts as full
local FILE = "loot_chests.dat"

local chests = {}   -- chest id -> { x, y, z, born = os.time(), step, filled = true once items were in it, full = true }
local count = 0
local steps = 0
local pending = {}  -- puts waiting for a new chest: { at, chest, item, n, got, opts, x, y, z, done, again, tries }
local loaded = false

local function path() return emf.dir .. "\\" .. FILE end

local function save()
  local f = io.open(path(), "w")
  if not f then return end
  f:write("session ", tostring(emf.session()), "\n")
  for id, c in pairs(chests) do
    f:write(string.format("%d %.2f %.2f %.2f %d %d\n", id, c.x, c.y, c.z, c.filled and 1 or 0, c.born or 0))
  end
  f:close()
end

local function load(world)
  loaded = true
  local f = io.open(path(), "r")
  if not f then return end
  local first = f:read("*l")
  if first ~= "session " .. tostring(emf.session()) then f:close() return end  -- another server run: those are gone
  local n = 0
  for line in f:lines() do
    local id, x, y, z, filled, born = line:match("^(%d+) (%S+) (%S+) (%S+) (%d) (%d+)")
    id = tonumber(id)
    if id and not chests[id] then
      local okp, px = pcall(world.position, world, id)
      if okp and px then
        chests[id] = { x = tonumber(x), y = tonumber(y), z = tonumber(z), filled = filled == "1", born = tonumber(born) }
        count, n = count + 1, n + 1
      end
    end
  end
  f:close()
  if n > 0 then emf.log(string.format("loot chest: %d chest(s) known again after a reload", n)) end
end

local function item_id(item)
  if type(item) == "string" then
    local ok, id = pcall(emf.item, item)
    return ok and id or nil
  end
  return item
end

local function spawn_chest(world, x, y, z)
  if count >= M.MAX_CHESTS then return nil end
  local ok, id = pcall(emf.spawn, world, M.CHEST, x, y, z)
  if not ok or not id or id == 0 then
    emf.log("loot chest: the game refused a chest (" .. tostring(id) .. ")")
    return nil
  end
  chests[id], count = { x = x, y = y, z = z, born = os.time(), step = steps }, count + 1
  save()
  return id
end

local function chest_for(world, x, y, z)
  local best, bd = nil, M.NEAR_M * M.NEAR_M
  for id, c in pairs(chests) do
    local d = (c.x - x) ^ 2 + (c.z - z) ^ 2
    if not c.full and d <= bd then best, bd = id, d end
  end
  return best or spawn_chest(world, x + 1.5, y, z)
end

local into  -- below

-- one put into p.chest; what does not fit goes on to the next chest (once); a fresh chest is given RETRIES tries first
into = function(world, p)
  local chest = p.chest
  if not chest then
    emf.log("loot chest: no chest for the loot (" .. tostring(p.n) .. " of item " .. tostring(p.item) .. " lost)")
    if p.done then p.done(p.got) end
    return
  end
  local c = chests[chest]
  if c and c.step and steps - c.step < PUT_WAIT then  -- a new chest: its inventory is set up a moment later
    p.at = c.step + PUT_WAIT
    pending[#pending + 1] = p
    return
  end
  local ok = pcall(emf.put, world, chest, p.item, p.n, function(w, added)
    added = tonumber(added) or 0
    local cc = chests[chest]
    if added > 0 and cc and not cc.filled then cc.filled = true save() end
    if added >= p.n then
      if p.done then p.done(p.got + added) end
      return
    end
    p.got, p.n = p.got + added, p.n - added
    if added == 0 and cc and os.time() - (cc.born or 0) < 5 and p.tries < RETRIES then
      p.tries, p.at = p.tries + 1, steps + PUT_WAIT  -- a fresh chest refused: try again in a moment
      pending[#pending + 1] = p
    elseif p.again then
      if cc then cc.full = true end
      p.again, p.tries, p.chest = false, 0, chest_for(w, p.x, p.y, p.z)  -- full: the next nearest one, or a new one
      into(w, p)
    else
      emf.log(string.format("loot chest: %d of item %s did not fit anywhere (lost)", p.n, tostring(p.item)))
      if p.done then p.done(p.got) end
    end
  end, p.opts)
  if not ok then
    emf.log("loot chest: emf.put refused")
    if p.done then p.done(p.got) end
  end
end

-- Puts `n` of `item` (id or name) into the nearest chest near x, y, z (`key` is no longer used), with `level` and
-- `rarity` for gear. `done(added)` (optional) after the game answered.
function M.put(world, key, x, y, z, item, n, level, rarity, done)
  if not loaded then load(world) end
  item = item_id(item)
  if not item or not x or (n or 0) <= 0 then if done then done(0) end return end
  into(world, { chest = chest_for(world, x, y, z), item = item, n = n, got = 0, opts = { level = level, rarity = rarity },
                x = x, y = y, z = z, done = done, again = true, tries = 0 })
end

-- Waiting puts, and removal: a chest that was used and is empty again goes (looked at every 2 s; "used" = the game
-- took items into it, or items were seen in it); one that never got items 30 s after it was put there goes too.
-- Whether a removed chest is really gone is checked 2 s later and logged. Call from a feature's server tick.
local removed = {}  -- chest id -> os.time() it was destroyed
function M.tick(world, bag)
  steps = steps + 1
  if not loaded then pcall(load, world) end
  if #pending > 0 then
    local due, keep = {}, {}
    for _, p in ipairs(pending) do if p.at <= steps then due[#due + 1] = p else keep[#keep + 1] = p end end
    pending = keep
    for _, p in ipairs(due) do pcall(into, world, p) end
  end
  if steps % 120 ~= 0 then return end
  local now, changed = os.time(), false
  for id, at in pairs(removed) do
    if now - at >= 2 then
      removed[id] = nil
      local okp, x = pcall(world.position, world, id)
      emf.log(string.format("loot chest: chest %s %s", tostring(id), (okp and x) and "is STILL THERE after emf.destroy" or "is gone"))
    end
  end
  for id, c in pairs(chests) do
    local okp, px = pcall(world.position, world, id)
    local gone = not okp or px == nil
    local n = gone and 0 or #bag.entity_stacks(world, id)
    if n > 0 and not c.filled then c.filled, changed = true, true end
    local never = not c.filled and now - (c.born or now) >= 30
    if gone or (c.filled and n == 0) or never then
      chests[id], count, changed = nil, count - 1, true
      if not gone then
        local okd, r = pcall(emf.destroy, world, id)
        removed[id] = now
        emf.log(string.format("loot chest: chest %s %s: destroy %s", tostring(id), never and "never got items" or "empty",
          okd and tostring(r) or ("error " .. tostring(r))))
      else
        emf.log(string.format("loot chest: chest %s gone (removed by the game or a player)", tostring(id)))
      end
    end
  end
  if changed then save() end
end

return M
