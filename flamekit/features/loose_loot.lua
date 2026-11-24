-- features/loose_loot.lua (0.15.389 as chop_loot.lua; 0.15.390 renamed, monsters too; 0.15.399 the DLL's news instead
-- of walks). Loose drops (PickupItem: items the game throws on the ground) of what a player breaks or kills go by that
-- player's Auto Loot setting (Settings tab, core/player_prefs.lua) through core/loot_route.lua (the Auto Junk List
-- first, a Loot tab line): into his bag or his companions' bags. "ground" and "game" (the default): the game's own
-- way, nothing is touched.
--   Objects (owner 2026-11-21 12:44 "loot that drops from chopping things down should also be automatically handled
--   based on loot settings"; 13:00 "I only want to auto loot stuff that I mine or chop down with a pickaxe ... a
--   pickaxe or axe rather.. if other items are on the ground already, just leave those alone"): broken with a tool
--   (the hit's attack "tool"); drops within OBJECT_R m (a falling trunk drops along its length).
--   Monsters (owner 13:07 "when you kill a Shroud Fog Nest drone it just dumps the archiac essence directly to the
--   ground... those types of loots also need to be auto looted"): killed by the player or his companion or pet (the
--   killing blow); drops within MONSTER_R m of where it died.
-- (What a pickaxe mines out of the ground goes straight into the bag already: the Loot tab lists it, core/msg_feed.lua.)
--
-- (0.15.399, owner 15:05 "eliminate any scanning for loot drops ... replace all that scanning with the DLL") no walk of
-- the world: FlameKit's DLL reports each loose item the moment the game makes it (core/loot_news.lua). A new loose item
-- (made at or after the break, within WINDOW_TICKS, within reach) is the drop of the nearest thing a player broke or
-- killed; it is taken at once. The news are read only while a drop is awaited. Items that were there before are never reported, so they are never taken.
-- Learned on the local server (2026-11-21 12:49-12:54): trees are entities with Health and no Faction; the breaking
-- hit (killed) comes when the tree is gone (no position: the hit's own position is used).
-- (0.15.547) A monster marked in core/loot_skip.lua is left alone (Spawn Nodes: a group with "Reward loot" or "No loot"
-- removes what its monsters throw loose itself, core/reward_loot.lua).
-- Uses only core modules (HANDOFF rule 0b).

local route = require("core.loot_route")
local prefs = require("core.player_prefs")
local ground = require("core.ground_loot")
local feed = require("core.msg_feed")  -- the monster's name for the Loot tab
local news = require("core.loot_news")
local bag = require("core.bag")
local events = require("core.game_events")
local skip = require("core.loot_skip")  -- (0.15.547)

local F = { id = "loose_loot", title = "Loose Loot" }
local kit

local OBJECT_R, MONSTER_R, UP = 30, 8, 30  -- m around the target, and up or down
local WINDOW_TICKS = 60 * 15               -- drops counted up to 15 s after the break or death (a trunk lands late)
-- the logging (debug tool: kept, switched off): each break, death and drop taken
local LOG, LOG_MAX = true, 60

-- broken or killed targets: { id, player, x, y, z, r, tick, monster, from }, the newest last
local broken = {}
local said = 0
local steps = 0
local tally = { objects = 0, monsters = 0, stacks = 0 }

-- A component of an entity, or nil when it has none or the read fails.
local function get(world, c, id)
  local ok, v = pcall(world.get, world, c, id)
  return ok and v or nil
end

-- Field `k` of a game value, or nil when it cannot be read.
local function field(v, k)
  local ok, x = pcall(function() return v[k] end)
  return ok and x or nil
end

-- A log line (at most LOG_MAX a minute).
local function note(fmt, ...)
  if LOG and said < LOG_MAX then said = said + 1 emf.log(string.format("loose loot: " .. fmt, ...)) end
end

-- Whether a hit was made with a tool (pickaxe or axe).
local function is_tool(hit)
  if hit.attack == "tool" then return true end
  if type(hit.attacks) == "table" then
    for _, a in ipairs(hit.attacks) do if a == "tool" then return true end end
  end
  return false
end

-- A player's Auto Loot choice (and account).
local function choice_of(world, player)
  local oka, acc = pcall(world.account, world, player)
  acc = oka and acc or nil
  return acc and prefs.get(acc, "auto_loot", world) or route.DEFAULT, acc
end

-- The world's step count (0 when it cannot be read).
local function tick_of(world)
  local ok, t = pcall(world.tick, world)
  return ok and tonumber(t) or 0
end

-- (0.15.409, owner 17:02 "the same problem happens when i'm chopping down a tree and my inv is full") logging first:
-- every tool hit's place for HIT_TICKS, and new loose items near one that no break or kill claims (what a full bag
-- may throw on the ground while chopping). Debug tool: kept, can be switched off.
local HIT_LOG, HIT_TICKS, HIT_R = true, 60 * 3, 10
local tool_hits = {}  -- { player, x, y, z, tick }
-- Debug: keeps where a player hit something with a tool (the last 64, HIT_TICKS).
local function note_tool_hit(world, hit)
  if not (HIT_LOG and hit and is_tool(hit)) then return end
  local player = route.player_of(world, hit.attacker)
  if not player then return end
  local x, y, z = world:position(player)
  if not x then return end
  local t = tick_of(world)
  tool_hits[#tool_hits + 1] = { player = player, x = x, y = y, z = z, tick = t }
  if #tool_hits > 64 then table.remove(tool_hits, 1) end
end

-- the breaking or killing hit: the target is noted (when its player auto loots)
local function on_hit(world, hit)
  pcall(note_tool_hit, world, hit)
  if not (hit and hit.killed) then return end
  local target = tonumber(hit.target) or 0
  if target == 0 or get(world, "PlayerState", target) then return end
  local monster = get(world, "Faction", target) ~= nil
  if monster and route.player_of(world, target) then return end  -- a companion or pet
  if monster and skip.is(target) then return end  -- (0.15.547) its game loot is removed elsewhere (Spawn Nodes: Reward loot, No loot)
  if not monster and not is_tool(hit) then return end            -- an object: only an axe or a pickaxe
  local player = route.player_of(world, hit.attacker)
  if not player then return end
  local choice = choice_of(world, player)
  if choice ~= "bag" and choice ~= "companion" then return end  -- the game's own way
  local x, y, z = world:position(target)
  local pos = hit.position
  if not x and type(pos) == "table" then x, y, z = tonumber(pos.x), tonumber(pos.y), tonumber(pos.z) end
  if not x then x, y, z = world:position(player) end
  if not x then return end
  local from = "chopped"
  if monster then local okn, n = pcall(feed.name, world, target) from = okn and n or nil end
  broken[#broken + 1] = { id = target, player = player, x = x, y = y, z = z, r = monster and MONSTER_R or OBJECT_R,
                          tick = tick_of(world), monster = monster, from = from }
  if monster then tally.monsters = tally.monsters + 1 else tally.objects = tally.objects + 1 end
  note("%s %s %s by %s at %.1f %.1f %.1f", monster and "monster" or "object", tostring(target), monster and "killed" or "broken",
    tostring(player), x, y, z)
end

-- a new loose item (the DLL's news): the drop of the nearest target broken or killed lately within its reach
local function hit_near(x, y, z, now)
  for i = #tool_hits, 1, -1 do
    local h = tool_hits[i]
    if now - h.tick <= HIT_TICKS and (x - h.x) ^ 2 + (z - h.z) ^ 2 <= HIT_R * HIT_R then return h end
  end
  return nil
end

-- A new loose item: when it is the drop of something a player just broke or killed nearby, it goes by his Auto Loot setting (bag or companion) instead of staying on the ground.
local function on_pickup(world, id, x, y, z, now)
  if ground.is_own(id) then return end
  if HIT_LOG and #broken == 0 then
    local h = hit_near(x, y, z, now)
    if h then
      local p = get(world, "PickupItem", id)
      note("a loose item %s (item %s x%s) near player %s's tool hit, no break: %.1f m from him", tostring(id),
        p and tostring(p.itemId) or "?", p and tostring(p.pickupAmount) or "?", tostring(h.player), math.sqrt((x - h.x) ^ 2 + (z - h.z) ^ 2))
    end
  end
  if #broken == 0 then return end
  local best, best_d
  local keep = {}
  for _, b in ipairs(broken) do
    if now - b.tick <= WINDOW_TICKS then
      keep[#keep + 1] = b
      local d = (x - b.x) ^ 2 + (z - b.z) ^ 2
      -- made at or after the break (a step's slack: the hit and the drop can come in one step)
      if now >= b.tick - 1 and d <= b.r * b.r and math.abs(y - b.y) <= UP and (not best_d or d < best_d) then best, best_d = b, d end
    end
  end
  broken = keep
  if not best then return end
  local choice, acc = choice_of(world, best.player)
  if choice ~= "bag" and choice ~= "companion" then return end
  local p = get(world, "PickupItem", id)
  local item, count = p and tonumber(p.itemId) or 0, p and tonumber(p.pickupAmount) or 0
  if item == 0 or count <= 0 then return end
  local level, rarity = tonumber(p.level) or 0, tonumber(p.rarity) or 0
  if not pcall(emf.destroy, world, id) then return end
  tally.stacks = tally.stacks + 1
  note("%s %s: pickup %s (item %d x%d) to player %s's %s", best.monster and "monster" or "object", tostring(best.id),
    tostring(id), item, count, tostring(best.player), choice)
  route.deliver(world, best.player, acc, choice, item, count, level, rarity, x, y, z, false,
    function(w, n) ground.drop(w, item, n, x, y, z, level, rarity) end, best.from)
end

-- (0.15.411, owner 17:44 "i get backpack full when I pickaxe too") debug: the server's InventoryFull event (the game's
-- mining_node_events, loot_pickup_item and immediate_loot_action send it when a bag refuses): who, from what, and
-- what that entity holds then and half a second later (does a refused mined item stay in the node?). Kept, can be
-- switched off.
local FULL_LOG, FULL_MAX = true, 30
local full_said, full_later = 0, {}
local FULL_FLAGS = { "MiningNode", "DynamicMiningNode", "ResourceNodePickupDrops", "Inventory", "InventorySetup",
  "DefaultInventory", "PickupItem", "DestroyOnLoot", "RandomLoot", "Health", "PlayerState" }
-- Debug: logs what entity `from` is and holds when a bag refused an item from it.
local function full_look(world, from, what)
  local flags, items = {}, {}
  for _, c in ipairs(FULL_FLAGS) do if get(world, c, from) then flags[#flags + 1] = c end end
  for i, st in ipairs(bag.entity_stacks(world, from)) do
    if i > 8 then break end
    items[#items + 1] = string.format("%s x%s", tostring(st.item), tostring(st.count))
  end
  emf.log(string.format("loose loot: full bag: %s: entity %s: %s | %s", what, tostring(from), table.concat(flags, " "),
    #items > 0 and table.concat(items, ", ") or "(nothing)"))
end
-- Debug: the server's InventoryFull event: who, from what, how far (and a look half a second later).
local function on_full(world, e)
  if not FULL_LOG or full_said >= FULL_MAX then return end
  full_said = full_said + 1
  local by = tonumber(field(e, "pickedUpById")) or 0
  local from = tonumber(field(e, "pickedUpFromId")) or 0
  local px, _, pz = world:position(by)
  local fx, _, fz = world:position(from)
  emf.log(string.format("loose loot: full bag: InventoryFull by %d from %d mask %s at %.1f m", by, from,
    tostring(field(e, "mask")), (px and fx) and math.sqrt((px - fx) ^ 2 + (pz - fz) ^ 2) or -1))
  if from ~= 0 then
    full_look(world, from, "now")
    if #full_later < 30 then full_later[#full_later + 1] = { from = from, at = steps + 30 } end
  end
end

-- Every server step: the debug looks that are due, forgets old breaks and tool hits, reads the DLL's loot news while a drop is awaited; once a minute the counts.
function F.tick(world)
  steps = steps + 1
  if #full_later > 0 then
    local keep = {}
    for _, l in ipairs(full_later) do
      if steps < l.at then keep[#keep + 1] = l else pcall(full_look, world, l.from, "half a second later") end
    end
    full_later = keep
  end
  if #broken > 0 and tick_of(world) - broken[#broken].tick > WINDOW_TICKS then broken = {} end
  if #tool_hits > 0 and tick_of(world) - tool_hits[#tool_hits].tick > HIT_TICKS then tool_hits = {} end
  news.tick(world, #broken > 0 or #tool_hits > 0)  -- (0.15.399) the DLL's news only while a drop is awaited (0.15.409: or a tool is in use)
  if steps % 3600 == 0 then
    said = 0
    full_said = 0
    ground.forget_old()
    if tally.objects + tally.monsters > 0 then
      emf.log(string.format("loose loot: last minute: %d object(s) broken with a tool, %d monster(s) killed, %d drop(s) taken",
        tally.objects, tally.monsters, tally.stacks))
    end
    tally = { objects = 0, monsters = 0, stacks = 0 }
  end
end

-- Listens for new loose items (loot news), hits (breaks and kills) and full bags.
function F.setup(k)
  kit = k
  prefs.setup()
  news.setup()
  news.on_pickup(kit.guard(F, on_pickup, "a new loose item"))
  local okh, hooked = pcall(emf.on_hit, kit.guard(F, on_hit, "a hit"))
  if not (okh and hooked ~= false) then emf.log("loose loot: emf.on_hit is not there: loose drops stay the game's") end
  if FULL_LOG and not events.on("InventoryFull", kit.guard(F, on_full, "a full bag")) then
    emf.log("loose loot: InventoryFull cannot be heard")
  end
end

return F
