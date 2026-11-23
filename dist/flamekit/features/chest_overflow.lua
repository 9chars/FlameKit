-- features/chest_overflow.lua (0.15.410, owner 2026-11-21 16:06 "I'm trying to loot something from a chest and its
-- saying my back pack is full instead of pulling it into one of my companions chests... anyway to hook into that and
-- move it over?"; 17:02 "can we go back to the original objective"): what a player takes out of a loot chest while his
-- bag is full goes into his companions' bags instead (the main one first, 72 stacks each: core/loot_route.lua's
-- companion hook), with a Loot tab line. What fits nowhere stays in the chest; nothing goes on the ground.
--
-- How (learned on the local server 2026-11-21): a refused take never reaches the server (16:15: no event there). The
-- player's own game sends TransferItemToInventoryEvent for every take (17:16: "take all" = type 2, the chest in
-- sourceInventoryId or sourceSlotId.entityId, the same entity number as on the server: 17:25 PickupEvent from
-- 3380350191 for the chest the game named 3380350191). So the player's game tells the server about each take from a
-- container (channel flamekit/overflow); the server looks LATER_STEPS later: what is still in that chest (that slot for
-- a single take the game answered with no PickupEvent, everything for "take all") the bag refused: it goes to the
-- companions.
-- Only world loot containers (RandomLoot or DestroyOnLoot: chests, urns, loot piles), within REACH m of the player, and
-- only for a player whose Auto Loot is "bag" or "companion"; never a player's own storage, never a companion's chest.
-- (A game that hosts its own world is not handled: its takes do not come over the channel.)
-- Uses only core modules (HANDOFF rule 0b).

local route = require("core.loot_route")
local prefs = require("core.player_prefs")
local bag = require("core.bag")
local events = require("core.game_events")

local F = { id = "chest_overflow", title = "Chest Overflow" }
local kit

local CHANNEL = "overflow"
local LATER_STEPS = 30       -- half a second: the game has done the take (or refused it) by then
local REACH = 8              -- m between the player and the chest
local TYPES = { [0] = "one", [1] = "half", [2] = "all", [3] = "amount" }  -- InventoryActionType (4 = Destroy: not a take)
local LOG, LOG_MAX = true, 40  -- debug: the requests and what was moved (kept, can be switched off)

local steps = 0
local said = 0
local waiting = {}           -- server: { player, src, slot (0-based or nil), all, at }
local sent = {}              -- client: src -> step of the last "take all" (one a second per chest)
local registered = nil

-- A component of an entity, or nil when it has none or the read fails.
local function get(world, c, id)
  local ok, v = pcall(world.get, world, c, id)
  return ok and v or nil
end

-- A log line (at most LOG_MAX a minute).
local function note(fmt, ...)
  if LOG and said < LOG_MAX then said = said + 1 emf.log(string.format("chest overflow: " .. fmt, ...)) end
end

-- Field `k` of a game value, or nil when it cannot be read.
local function field(v, k)
  local ok, x = pcall(function() return v[k] end)
  return ok and x or nil
end

-- the player's game: a take from a container -> the server
local function on_transfer(world, e)
  if not registered then return end
  local t = tonumber(field(e, "type"))
  if not (t and TYPES[t]) then return end
  local ss = field(e, "sourceSlotId")
  local src = tonumber(field(e, "sourceInventoryId")) or 0
  if src == 0 and ss ~= nil then src = tonumber(field(ss, "entityId")) or 0 end
  if src == 0 then return end
  local me = emf.local_player()
  if src == me or tonumber(field(e, "targetInventoryId")) ~= me then return end  -- only from a container into his bag
  local slot = ss ~= nil and tonumber(field(ss, "slotIndex")) or nil
  local now = world:tick()
  if t == 2 then  -- "take all" clicked again and again: once a second per chest
    if sent[src] and now - sent[src] < 60 then return end
    sent[src] = now
  end
  local ok, text = pcall(emf.json.encode, { op = "take", src = src, slot = slot, all = (t == 2) })
  if ok then pcall(emf.net.send, CHANNEL, text) end
end

-- the server: a player's take; looked at LATER_STEPS later
local function on_server(world, from, data)
  local ok, m = pcall(emf.json.decode, data)
  if not (ok and type(m) == "table" and m.op == "take" and tonumber(m.src)) then return end
  local player = from and tonumber(from.player)
  if not player then return end
  if #waiting >= 64 then return end
  waiting[#waiting + 1] = { player = player, src = tonumber(m.src), slot = tonumber(m.slot), all = m.all == true, at = steps + LATER_STEPS }
end

-- Whether entity `id` is a loot container (random loot or destroyed when looted, with an inventory; not a player).
local function is_loot_container(world, id)
  return (get(world, "RandomLoot", id) or get(world, "DestroyOnLoot", id)) and get(world, "Inventory", id)
    and not get(world, "PlayerState", id)
end

-- (a take that worked: the game's PickupEvent from that chest to that player; a single take that got anything is not
-- touched: what is left in that slot is what the player chose to leave, only "take all" leftovers are the bag's refusal)
local picked = {}  -- "<player>:<chest>" -> step of the last pickup
-- A PickupEvent from a container: notes that this player's take from it worked.
local function on_pickup(world, e)
  local by, from = tonumber(field(e, "pickedUpByEntityId")) or 0, tonumber(field(e, "pickedUpFromEntityId")) or 0
  if by ~= 0 and from ~= 0 then picked[by .. ":" .. from] = steps end
end

-- A take that left items behind (the bag was full), for a player whose Auto Loot is bag or companion: takes what is left out of the chest and gives it to his companions (what none takes goes back in).
local function look(world, w)
  local p = picked[w.player .. ":" .. w.src]
  if not w.all and p and steps - p <= LATER_STEPS + 60 then return end  -- the single take worked
  local oka, acc = pcall(world.account, world, w.player)
  acc = oka and acc or nil
  local choice = acc and prefs.get(acc, "auto_loot", world) or route.DEFAULT
  if choice ~= "bag" and choice ~= "companion" then return end
  if not is_loot_container(world, w.src) then note("player %d: %d is not a loot container: left alone", w.player, w.src) return end
  local px, py, pz = world:position(w.player)
  local cx, cy, cz = world:position(w.src)
  if not (px and cx) or (px - cx) ^ 2 + (pz - cz) ^ 2 > REACH * REACH then
    note("player %d: chest %d out of reach: left alone", w.player, w.src) return
  end
  local stacks = {}
  for _, st in ipairs(bag.entity_stacks(world, w.src)) do
    if not st.gem and (w.all or w.slot == nil or (st.slot >> 32) == w.slot) then stacks[#stacks + 1] = st end
  end
  note("player %d: chest %d, %s: %d stack(s) still in it", w.player, w.src, w.all and "take all" or ("slot " .. tostring(w.slot)), #stacks)
  for _, st in ipairs(stacks) do
    emf.take(world, st.owner, st.item, st.count, function(w2, taken)
      if not (taken and taken > 0) then return end
      route.deliver(w2, w.player, acc, "companion", st.item, taken, st.level or 0, st.rarity or 0, cx, cy, cz, st.gear,
        function(w3, n) emf.put(w3, w.src, st.item, n, nil, { level = st.level or 0, rarity = st.rarity or 0 }) end,
        "chest", { no_ground = true, no_junk = true })
    end, { slot = st.slot, exact = true })
  end
end

-- Every server step: looks at the takes whose wait is over.
function F.tick(world)
  steps = steps + 1
  if steps % 3600 == 0 then said = 0 end
  if #waiting == 0 then return end
  local keep = {}
  for _, w in ipairs(waiting) do
    if steps < w.at then keep[#keep + 1] = w
    else
      local ok, err = pcall(look, world, w)
      if not ok then emf.log("chest overflow: " .. tostring(err)) end
    end
  end
  waiting = keep
end

-- Opens the net channel (the player's game tells the server about each take) and listens for pickups and takes.
function F.setup(k)
  kit = k
  prefs.setup()
  registered = emf.net.channel(CHANNEL, { version = 1, to = "server", max = 256, per_10s = 60,
    on_server = function(world, from, data)
      local ok, err = pcall(on_server, world, from, data)
      if not ok then emf.log("chest overflow: " .. tostring(err)) end
    end }) and true or false
  events.on("PickupEvent", kit.guard(F, on_pickup, "a pickup"))
  local ok = events.on("TransferItemToInventoryEvent", kit.guard(F, on_transfer, "a take"), "client")
  if not ok then emf.log("chest overflow: the player's takes cannot be heard (TransferItemToInventoryEvent): no overflow") end
end

return F
