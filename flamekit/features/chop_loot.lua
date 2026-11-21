-- features/chop_loot.lua (0.15.389, owner 2026-11-21 12:44 "loot that drops from chopping things down should also be
-- automatically handled based on loot settings as well"; 13:00 "I only want to auto loot stuff that I mine or chop down
-- with a pickaxe or axe ... if other items are on the ground already, just leave those alone"): what falls out of an
-- object a player breaks with a tool (an axe, a pickaxe: the hit's attack "tool") goes by that player's Auto Loot
-- setting (Settings tab, core/player_prefs.lua) through core/loot_route.lua (the Auto Junk List first, a Loot tab line):
-- into his bag or his companions' bags. "ground" and "game" (the default): the game's own way, nothing is touched.
-- (What a pickaxe mines out of the ground goes straight into the bag already: the Loot tab lists it, core/msg_feed.lua.)
--
-- How: the drops are loose pickups (PickupItem) the game spawns around the object. Items already lying there are never
-- taken: at the first tool hit on an object every pickup within RADIUS m is noted (a walk of the world's entities,
-- PER_STEP a step); after the object breaks, a pickup within RADIUS m that was not there then, not FlameKit's own
-- (core/ground_loot.lua) and not taken before is its drop, looked for at 1, 3, 6 and 10 s. An object broken by its
-- first hit is noted only then: what it dropped at once counts as old and is left on the ground (never a wrong take).
-- Learned on the local server (2026-11-21 12:49-12:54): trees are entities with Health and no Faction; the breaking
-- hit (killed) comes when the tree is gone (no position: the hit's own position is used); 26 pickups lay within 30 m
-- of a tree before it fell, one came from it.
-- Uses only core modules (HANDOFF rule 0b).

local route = require("core.loot_route")
local prefs = require("core.player_prefs")
local ground = require("core.ground_loot")

local F = { id = "chop_loot", title = "Chop Loot" }
local kit

local RADIUS, UP = 30, 30        -- m around the object (a falling trunk drops along its length), and up or down
local LOOKS = { 60, 180, 360, 600 }  -- steps after the break (1, 3, 6, 10 s)
local PER_STEP = 3000            -- entities looked at a step (the production server has ~37,000)
local FORGET = 3600 * 2          -- an object hit but not broken is forgotten after 2 minutes
-- the logging of 0.15.385-387 (debug tool: kept, switched off): each tool hit on an object and each drop taken
local LOG, LOG_MAX = true, 40

local steps = 0
local objects = {}   -- object id -> { player, x, y, z, at, known = { pickup ids } or nil (noting), broke = step or nil, looks = 0 }
local walk = nil     -- { list, i, found = { { id, x, y, z } } }
local said = 0
local tally = { objects = 0, stacks = 0 }

local function get(world, c, id)
  local ok, v = pcall(world.get, world, c, id)
  return ok and v or nil
end

local function note(fmt, ...)
  if LOG and said < LOG_MAX then said = said + 1 emf.log(string.format("chop loot: " .. fmt, ...)) end
end

local function is_tool(hit)
  if hit.attack == "tool" then return true end
  if type(hit.attacks) == "table" then
    for _, a in ipairs(hit.attacks) do if a == "tool" then return true end end
  end
  return false
end

local function near(o, x, y, z)
  return (x - o.x) ^ 2 + (z - o.z) ^ 2 <= RADIUS * RADIUS and math.abs(y - o.y) <= UP
end

local function on_hit(world, hit)
  if not (hit and is_tool(hit)) then return end
  local target = tonumber(hit.target) or 0
  if target == 0 or get(world, "Faction", target) or get(world, "PlayerState", target) then return end
  local player = route.player_of(world, hit.attacker)
  if not player then return end
  local o = objects[target]
  if not o then
    local x, y, z = world:position(target)
    local pos = hit.position
    if not x and type(pos) == "table" then x, y, z = tonumber(pos.x), tonumber(pos.y), tonumber(pos.z) end
    if not x then x, y, z = world:position(player) end
    if not x then return end
    o = { player = player, x = x, y = y, z = z, at = steps, known = nil, looks = 0 }
    objects[target] = o
  end
  o.player, o.at = player, steps
  note("tool hit by %s on %s: %s damage, killed %s, at %.1f %.1f %.1f", tostring(player), tostring(target),
    tostring(hit.amount), tostring(hit.killed), o.x, o.y, o.z)
  if hit.killed and not o.broke then o.broke = steps end
end

-- One broken object's new pickups, by its player's choice.
local function take(world, oid, o, found)
  local oka, acc = pcall(world.account, world, o.player)
  acc = oka and acc or nil
  local choice = acc and prefs.get(acc, "auto_loot", world) or route.DEFAULT
  if choice ~= "bag" and choice ~= "companion" then return end
  for _, f in ipairs(found) do
    if not o.known[f.id] and near(o, f.x, f.y, f.z) and not ground.is_own(f.id) then
      o.known[f.id] = true  -- never looked at again, whatever happens below
      local p = get(world, "PickupItem", f.id)
      local item, count = p and tonumber(p.itemId) or 0, p and tonumber(p.pickupAmount) or 0
      if item ~= 0 and count > 0 then
        local level, rarity = tonumber(p.level) or 0, tonumber(p.rarity) or 0
        local okd = pcall(emf.destroy, world, f.id)
        if okd then
          tally.stacks = tally.stacks + 1
          note("object %s: pickup %s (item %d x%d) to player %s's %s", tostring(oid), tostring(f.id), item, count, tostring(o.player), choice)
          route.deliver(world, o.player, acc, choice, item, count, level, rarity, f.x, f.y, f.z, false,
            function(w, n) ground.drop(w, item, n, f.x, f.y, f.z, level, rarity) end, "chopped")
        end
      end
    end
  end
end

-- After a walk: objects waiting for their note get the pickups lying around them; broken ones whose look is due get
-- their new pickups taken.
local function after_walk(world, found, started)
  for oid, o in pairs(objects) do
    if o.known == nil and o.asked and o.asked <= started then
      o.known = {}
      for _, f in ipairs(found) do if near(o, f.x, f.y, f.z) then o.known[f.id] = true end end
    elseif o.known and o.broke and o.due and o.due <= started then
      o.due = nil
      o.looks = o.looks + 1
      if o.looks == 1 then tally.objects = tally.objects + 1 end
      take(world, oid, o, found)
      if o.looks >= #LOOKS then objects[oid] = nil end
    end
  end
end

function F.tick(world)
  steps = steps + 1
  if steps % 3600 == 0 then
    said = 0
    ground.forget_old()
    if tally.objects > 0 then
      emf.log(string.format("chop loot: last minute: %d object(s) broken with a tool, %d drop(s) taken", tally.objects, tally.stacks))
    end
    tally = { objects = 0, stacks = 0 }
  end
  local need = false
  for oid, o in pairs(objects) do
    if not o.broke and steps - o.at > FORGET then objects[oid] = nil
    else
      if o.known == nil and not o.asked then o.asked = steps end
      if o.known and o.broke and not o.due and o.looks < #LOOKS and steps >= o.broke + LOOKS[o.looks + 1] then o.due = steps end
      if (o.known == nil) or o.due then need = true end
    end
  end
  if not walk then
    if need then walk = { list = world:entities(), i = 1, found = {}, started = steps } end
    return
  end
  local last = math.min(#walk.list, walk.i + PER_STEP - 1)
  for i = walk.i, last do
    local id = walk.list[i]
    if get(world, "PickupItem", id) then
      local x, y, z = world:position(id)
      if x then walk.found[#walk.found + 1] = { id = id, x = x, y = y, z = z } end
    end
  end
  walk.i = last + 1
  if walk.i > #walk.list then
    local w = walk
    walk = nil
    after_walk(world, w.found, w.started)
  end
end

function F.setup(k)
  kit = k
  prefs.setup()
  local okh, hooked = pcall(emf.on_hit, kit.guard(F, on_hit, "a hit"))
  if not (okh and hooked ~= false) then emf.log("chop loot: emf.on_hit is not there: what tools break stays the game's") end
end

return F
