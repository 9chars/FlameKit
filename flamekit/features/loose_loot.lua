-- features/loose_loot.lua (0.15.389 as chop_loot.lua; 0.15.390 renamed, monsters too). Loose drops (PickupItem: items the
-- game throws on the ground) of what a player breaks or kills go by that player's Auto Loot setting (Settings tab,
-- core/player_prefs.lua) through core/loot_route.lua (the Auto Junk List first, a Loot tab line): into his bag or his
-- companions' bags. "ground" and "game" (the default): the game's own way, nothing is touched.
--   Objects (owner 2026-11-21 12:44 "loot that drops from chopping things down should also be automatically handled
--   based on loot settings"; 13:00 "I only want to auto loot stuff that I mine or chop down with a pickaxe ... a
--   pickaxe or axe rather.. if other items are on the ground already, just leave those alone"): broken with a tool
--   (the hit's attack "tool"); drops within OBJECT_R m (a falling trunk drops along its length).
--   Monsters (owner 13:07 "when you kill a Shroud Fog Nest drone it just dumps the archiac essence directly to the
--   ground... those types of loots also need to be auto looted"): killed by the player or his companion or pet (the
--   killing blow, as features/loot_drop.lua, which keeps the loot in bodies and loot spots); drops within MONSTER_R m
--   of where it died.
-- (What a pickaxe mines out of the ground goes straight into the bag already: the Loot tab lists it, core/msg_feed.lua.)
--
-- Items already lying there are never taken: at the first hit on a target (by a player whose Auto Loot is bag or
-- companion) the world's entities are walked (PER_STEP a step) and every pickup there is then is noted; after the
-- break or the death a pickup near it that was not there then, not FlameKit's own (core/ground_loot.lua) and not
-- taken before is its drop, looked for at 1, 3, 6 and 10 s. A target broken or killed by its first hit is noted right
-- after (the game throws a drop out a moment later: a trunk when it lands, a monster's loot 1-3 s after the death).
-- Learned on the local server (2026-11-21 12:49-12:54): trees are entities with Health and no Faction; the breaking
-- hit (killed) comes when the tree is gone (no position: the hit's own position is used); 26 pickups lay within 30 m
-- of a tree before it fell, one came from it; the world's own pickups (sticks, stones) have StaticCollider.
-- Uses only core modules (HANDOFF rule 0b).

local route = require("core.loot_route")
local prefs = require("core.player_prefs")
local ground = require("core.ground_loot")
local feed = require("core.msg_feed")  -- the monster's name for the Loot tab

local F = { id = "loose_loot", title = "Loose Loot" }
local kit

local OBJECT_R, MONSTER_R, UP = 30, 8, 30  -- m around the target, and up or down
local LOOKS = { 60, 180, 360, 600 }        -- steps after the break or death (1, 3, 6, 10 s)
local PER_STEP = 3000                      -- entities looked at a step (the production server has ~37,000)
local FORGET = 3600 * 2                    -- a target hit but not broken or killed is forgotten after 2 minutes
-- the logging of 0.15.385-389 (debug tool: kept, switched off): each first hit, break and drop taken
local LOG, LOG_MAX = true, 40

local steps = 0
-- target id -> { player, x, y, z, r, at, known = { pickup id = true } (the pickups there at the note) or nil,
--               asked, broke, due, looks, taken = { pickup id = true }, monster }
local targets = {}
local walk = nil     -- { list, i, found = { { id, x, y, z } }, set = { id = true }, started }
local said = 0
local tally = { objects = 0, monsters = 0, stacks = 0 }

local function get(world, c, id)
  local ok, v = pcall(world.get, world, c, id)
  return ok and v or nil
end

local function note(fmt, ...)
  if LOG and said < LOG_MAX then said = said + 1 emf.log(string.format("loose loot: " .. fmt, ...)) end
end

local function is_tool(hit)
  if hit.attack == "tool" then return true end
  if type(hit.attacks) == "table" then
    for _, a in ipairs(hit.attacks) do if a == "tool" then return true end end
  end
  return false
end

local function choice_of(world, player)
  local oka, acc = pcall(world.account, world, player)
  acc = oka and acc or nil
  return acc and prefs.get(acc, "auto_loot", world) or route.DEFAULT, acc
end

local function place(world, target, hit, player)
  local x, y, z = world:position(target)
  local pos = hit.position
  if not x and type(pos) == "table" then x, y, z = tonumber(pos.x), tonumber(pos.y), tonumber(pos.z) end
  if not x then x, y, z = world:position(player) end
  return x, y, z
end

local function on_hit(world, hit)
  if not hit then return end
  local target = tonumber(hit.target) or 0
  if target == 0 or get(world, "PlayerState", target) then return end
  local monster = get(world, "Faction", target) ~= nil
  if monster and route.player_of(world, target) then return end  -- a companion or pet
  if not monster and not is_tool(hit) then return end            -- an object: only an axe or a pickaxe
  local player = route.player_of(world, hit.attacker)
  if not player then return end
  local t = targets[target]
  if not t then
    local choice = choice_of(world, player)
    if choice ~= "bag" and choice ~= "companion" then return end  -- the game's own way: not even noted
    local x, y, z = place(world, target, hit, player)
    if not x then return end
    t = { player = player, x = x, y = y, z = z, r = monster and MONSTER_R or OBJECT_R, at = steps, looks = 0,
          taken = {}, monster = monster }
    targets[target] = t
    note("%s %s first hit by %s at %.1f %.1f %.1f", monster and "monster" or "object", tostring(target), tostring(player), x, y, z)
  end
  t.player, t.at = player, steps
  if monster then  -- a monster moves: its last place is where it dies
    local x, y, z = place(world, target, hit, player)
    if x then t.x, t.y, t.z = x, y, z end
  end
  if hit.killed and not t.broke then
    t.broke = steps
    if monster then local okn, n = pcall(feed.name, world, target) t.from = okn and n or nil end
    note("%s %s %s by %s at %.1f %.1f %.1f", monster and "monster" or "object", tostring(target), monster and "killed" or "broken",
      tostring(player), t.x, t.y, t.z)
  end
end

local function near(t, x, y, z)
  return (x - t.x) ^ 2 + (z - t.z) ^ 2 <= t.r * t.r and math.abs(y - t.y) <= UP
end

-- One broken or killed target's new pickups, by its player's choice.
local function take(world, tid, t, found)
  local choice, acc = choice_of(world, t.player)
  if choice ~= "bag" and choice ~= "companion" then return end
  for _, f in ipairs(found) do
    if not t.known[f.id] and not t.taken[f.id] and near(t, f.x, f.y, f.z) and not ground.is_own(f.id) then
      t.taken[f.id] = true  -- never looked at again, whatever happens below
      local p = get(world, "PickupItem", f.id)
      local item, count = p and tonumber(p.itemId) or 0, p and tonumber(p.pickupAmount) or 0
      if item ~= 0 and count > 0 then
        local level, rarity = tonumber(p.level) or 0, tonumber(p.rarity) or 0
        if pcall(emf.destroy, world, f.id) then
          tally.stacks = tally.stacks + 1
          note("%s %s: pickup %s (item %d x%d) to player %s's %s", t.monster and "monster" or "object", tostring(tid),
            tostring(f.id), item, count, tostring(t.player), choice)
          route.deliver(world, t.player, acc, choice, item, count, level, rarity, f.x, f.y, f.z, false,
            function(w, n) ground.drop(w, item, n, f.x, f.y, f.z, level, rarity) end, t.monster and t.from or "chopped")
        end
      end
    end
  end
end

-- After a walk: targets waiting for their note get the pickups there then; broken or killed ones whose look is due
-- get their new pickups taken.
local function after_walk(world, w)
  for tid, t in pairs(targets) do
    if t.known == nil and t.asked and t.asked <= w.started then
      t.known = w.set
    elseif t.known and t.broke and t.due and t.due <= w.started then
      t.due = nil
      t.looks = t.looks + 1
      if t.looks == 1 then
        if t.monster then tally.monsters = tally.monsters + 1 else tally.objects = tally.objects + 1 end
      end
      take(world, tid, t, w.found)
      if t.looks >= #LOOKS then targets[tid] = nil end
    end
  end
end

function F.tick(world)
  steps = steps + 1
  if steps % 3600 == 0 then
    said = 0
    ground.forget_old()
    if tally.objects + tally.monsters > 0 then
      emf.log(string.format("loose loot: last minute: %d object(s) broken with a tool, %d monster(s) killed, %d drop(s) taken",
        tally.objects, tally.monsters, tally.stacks))
    end
    tally = { objects = 0, monsters = 0, stacks = 0 }
  end
  local need = false
  for tid, t in pairs(targets) do
    if not t.broke and steps - t.at > FORGET then targets[tid] = nil
    else
      if t.known == nil and not t.asked then t.asked = steps end
      if t.known and t.broke and not t.due and t.looks < #LOOKS and steps >= t.broke + LOOKS[t.looks + 1] then t.due = steps end
      if t.known == nil or t.due then need = true end
    end
  end
  if not walk then
    if need then walk = { list = world:entities(), i = 1, found = {}, set = {}, started = steps } end
    return
  end
  local last = math.min(#walk.list, walk.i + PER_STEP - 1)
  for i = walk.i, last do
    local id = walk.list[i]
    if get(world, "PickupItem", id) then
      walk.set[id] = true
      local x, y, z = world:position(id)
      if x then walk.found[#walk.found + 1] = { id = id, x = x, y = y, z = z } end
    end
  end
  walk.i = last + 1
  if walk.i > #walk.list then
    local w = walk
    walk = nil
    after_walk(world, w)
  end
end

function F.setup(k)
  kit = k
  prefs.setup()
  local okh, hooked = pcall(emf.on_hit, kit.guard(F, on_hit, "a hit"))
  if not (okh and hooked ~= false) then emf.log("loose loot: emf.on_hit is not there: loose drops stay the game's") end
end

return F
