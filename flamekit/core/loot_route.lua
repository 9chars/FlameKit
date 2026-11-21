-- core/loot_route.lua (0.15.376, owner 2026-11-21 09:35): where a killed monster's loot goes, by the killer's own Auto
-- Loot setting (core/player_prefs.lua, key "auto_loot"):
--   "bag"        1. Auto loot to main bag        the killer's bag, then his companions' bags, then the ground
--   "companion"  2. Auto loot to companion bag   his companions' bags, then his bag, then the ground
--   "ground"     3. Let loot drop to ground      the ground beside the body
--   "game"       4. Follow original loot drop behavior (the default: the body keeps its loot, E opens it)
-- A companion's bag counts only while it is out and following him (the main companion first, then the others, each at
-- most 72 stacks: features/companions). Every item is first judged by the killer's Auto Junk List (features/loot_filter):
-- junk he has set to Delete is gone, junk set to Drop goes on the ground at the body. Owner: "The loot MUST be evaluated
-- by the auto junk list first before going to the player (or companions)".
-- Shared core code (HANDOFF rule 0b): the features that know the parts register them here; none of them calls another.
--   route.set_junk(fn)        fn(world, account, item, gear) -> "drop" | "delete" | nil   (features/loot_filter)
--   route.set_owner(fn)       fn(world, entity) -> the player entity whose companion this is, or nil   (features/companions)
--   route.set_companion(fn)   fn(world, player, account, item, count, level, rarity) -> how many it stored, and the
--                             name of the (first) companion that took them (features/companions)
--   route.set_report(fn)      fn(world, report) after each item (the Loot tab, later)

local ground = require("core.ground_loot")

local own_puts = require("core.own_puts")
local route = {}

route.CHOICES = { "bag", "companion", "ground", "game" }
route.DEFAULT = "game"  -- (owner 09:44 "#1 default it back to game's own behavior")

local hooks = {}
function route.set_junk(fn) hooks.junk = fn end
function route.set_owner(fn) hooks.owner = fn end
function route.set_companion(fn) hooks.companion = fn end
function route.set_report(fn) hooks.report = fn end

local function is_player(world, id)
  local ok, v = pcall(world.get, world, "PlayerState", id)
  return ok and v ~= nil
end

-- The player behind a hit's attacker: the player himself, or the owner of the companion or pet that landed it.
function route.player_of(world, attacker)
  attacker = tonumber(attacker)
  if not attacker or attacker == 0 then return nil end
  if is_player(world, attacker) then return attacker end
  if hooks.owner then
    local ok, p = pcall(hooks.owner, world, attacker)
    if ok and p then return p end
  end
  return nil
end

local tally = { items = 0, bag = 0, companion = 0, ground = 0, junk_drop = 0, junk_delete = 0 }
function route.tally() local t = tally tally = { items = 0, bag = 0, companion = 0, ground = 0, junk_drop = 0, junk_delete = 0 } return t end

local function to_ground(world, item, count, level, rarity, x, y, z)
  if count <= 0 then return 0 end
  local made, pid = ground.drop(world, item, count, x, y, z, level, rarity, 2.5)
  if made > 0 and pid then pcall(ground.mark, world, pid) pcall(ground.sparkle, world, pid) end
  return made
end

local function report(world, r)
  if hooks.report then pcall(hooks.report, world, r) end
end

-- Hands `count` of `item` (level, rarity) taken out of a body at x, y, z to `player` (account) by `choice`. `back(world,
-- n)` puts n back into the body when even the ground refused them (nothing is lost). `gear`: a piece with its own level
-- and perks (the junk list keeps those unless the player shows all items). `from`: the monster's name (reports).
-- (0.15.410) `opts` (optional): { no_ground = true } what fits nowhere goes to `back` (never on the ground),
-- { no_junk = true } the Auto Junk List is not asked (an item the player tried to take himself)
function route.deliver(world, player, account, choice, item, count, level, rarity, x, y, z, gear, back, from, opts)
  opts = opts or {}
  count = math.floor(tonumber(count) or 0)
  if count <= 0 then return end
  tally.items = tally.items + 1
  local r = { player = player, account = account, item = item, count = count, level = level, rarity = rarity,
              from = from, bag = 0, companion = 0, ground = 0, junk = nil, x = x, z = z }
  -- the Auto Junk List first
  if hooks.junk and account and not opts.no_junk then
    local okj, act = pcall(hooks.junk, world, account, item, gear)
    if okj and (act == "delete" or act == "drop") then
      r.junk = act
      if act == "drop" then
        r.ground = to_ground(world, item, count, level, rarity, x, y, z) > 0 and count or 0
        if r.ground == 0 and back then back(world, count) end
        tally.junk_drop = tally.junk_drop + 1
      else
        tally.junk_delete = tally.junk_delete + 1
      end
      report(world, r)
      return
    end
  end
  local left = count
  local function companions()
    if left <= 0 or not hooks.companion then return end
    local okc, n, who = pcall(hooks.companion, world, player, account, item, left, level, rarity)
    n = okc and math.floor(tonumber(n) or 0) or 0
    if n > 0 then r.companion = r.companion + n left = left - n tally.companion = tally.companion + 1 r.companion_name = who end
  end
  local function finish(w)
    if left > 0 and opts.no_ground then
      if back then back(w, left) end
      if r.bag + r.companion == 0 then return end  -- nothing went anywhere: no Loot tab line
    elseif left > 0 then
      if to_ground(w, item, left, level, rarity, x, y, z) > 0 then
        r.ground = left
        tally.ground = tally.ground + 1
      elseif back then
        back(w, left)  -- not even the ground took it: back into the body
      end
    end
    report(w, r)
  end
  local function bag_then(after)
    if left <= 0 or not player then after(world) return end
    own_puts.note(player, item, left)  -- (0.15.388) the game reports it as a pickup from 0: the Loot tab has this line already
    local asked = pcall(emf.put, world, player, item, left, function(w, added)
      added = math.floor(tonumber(added) or 0)
      if added > 0 then r.bag = added left = left - added tally.bag = tally.bag + 1 end
      after(w)
    end, { level = level or 0, rarity = rarity or 0 })
    if not asked then after(world) end
  end
  if choice == "companion" then
    companions()
    bag_then(finish)
  elseif choice == "bag" then
    bag_then(function(w) world = w companions() finish(w) end)
  else  -- "ground"
    finish(world)
  end
end

return route
