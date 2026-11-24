-- core/reward_loot.lua (0.15.547, owner 2026-11-24 09:41 "add in the "reward loot" system like we build for the test
-- monsters and this should be configurable by group as well", 09:45 "make it configurable. so I can do reward loot
-- (exactly like how test monsters work), normal monster loot, and/or no loot ... if the player chooses no loot, it drops
-- nothing"): the test monsters' Reward loot (features/experimental.lua drop_test_loot, 0.15.142-0.15.186) as shared core
-- code, so Spawn Nodes can use it without reaching into another feature (HANDOFF rule 0b). Experimental keeps its own
-- copy for now; the two do the same.
--
--   reward.give(world, x, y, z, killer, level, boss)  a kill's reward: 10 or 15 runes and 5 or 10 legendary runes (twice
--        for a boss) straight into the killer's bag (player entity; what does not fit, and everything when no killer is
--        known, into a loot chest at x, y, z), and one legendary item (cosmetic, weapon, armor, ring or gem; gear at
--        `level`) into that chest. Returns one line for the log.
--   reward.clear_game_loot(world, id, x, z)  the monster's own game loot goes: what is in its body is taken out and
--        thrown away 2, 3 and 5 s after the death (the game puts it in 1.5-3 s after), and a separate loot pile the game
--        leaves where it died (core/loot_spots.lua) is removed 2 s after.
--   reward.tick(world)  every server step (does its work once per world step, whoever calls it).

local M = {}
local item_db = require("core.item_db")
local loot_chest = require("core.loot_chest")
local bag = require("core.bag")
local spots = require("core.loot_spots")

M.KINDS = { "cosmetic", "weapon", "armor", "ring", "gem" }  -- (0.15.162, owner: "we want cosmetics too")
local PICK_TRIES = 5
local not_legendary = {}  -- debug names that came out of the chest below legendary (0.15.168)
local steps, last_tick = 0, nil
local clears, piles = {}, {}  -- { id, at } bodies to empty; { id, x, z, at } loot piles to remove

-- Puts legendary item `name` into the loot chest at x, y, z; one that comes out below legendary is noted, taken back and
-- another one tried (PICK_TRIES times at most). (0.15.168, owner: "it also dropped uncommon gems and rings")
local function give_legendary(world, key, x, y, z, name, level, tries)
  loot_chest.put(world, key, x, y, z, name, 1, level, "legendary", function(added, chest)
    if not added or added < 1 or not chest then return end
    local okn, iid = pcall(emf.item, name)
    for _, st in ipairs(bag.entity_stacks(world, chest)) do
      if okn and st.item == iid and st.rarity ~= nil and st.rarity < 4 then
        not_legendary[name] = true
        emf.log(string.format("reward loot: %s came out rarity %s, not legendary: taken back, another one picked", name, tostring(st.rarity)))
        pcall(emf.take, world, st.owner, st.item, 1, function() end, { slot = st.slot, exact = true })
        if tries > 1 then
          local nxt
          for _ = 1, 20 do
            local k = M.KINDS[math.random(#M.KINDS)]
            nxt = k == "cosmetic" and item_db.pick_cosmetic() or item_db.pick(k, level)
            if nxt and not not_legendary[nxt] then break end
          end
          if nxt then give_legendary(world, key, x, y, z, nxt, level, tries - 1) end
        end
        return
      end
    end
  end)
end

function M.give(world, x, y, z, killer, level, boss)
  if not x then return "no position" end
  local twice = boss and 2 or 1
  level = math.max(1, math.floor(tonumber(level) or 1))
  local runes, lrunes = (math.random(2) == 1 and 10 or 15) * twice, (math.random(2) == 1 and 5 or 10) * twice
  local key = killer or "nobody"
  local function to_bag(item, n)
    local iid = item
    if type(iid) == "string" then local okn, v = pcall(emf.item, iid) iid = okn and v or nil end
    if not killer or not iid then loot_chest.put(world, key, x, y, z, item, n, 0, 0) return end
    local okp = pcall(emf.put, world, killer, iid, n, function(w, added)
      added = tonumber(added) or 0
      if added < n then loot_chest.put(w, key, x, y, z, iid, n - added, 0, 0) end  -- the bag is full: the rest in the chest
    end)
    if not okp then loot_chest.put(world, key, x, y, z, iid, n, 0, 0) end
  end
  to_bag(item_db.RUNE, runes)
  to_bag(item_db.LEGENDARY_RUNE, lrunes)
  local kind, name
  for _ = 1, 20 do
    kind = M.KINDS[math.random(#M.KINDS)]
    name = kind == "cosmetic" and item_db.pick_cosmetic() or item_db.pick(kind, level)
    if name and not not_legendary[name] then break end
  end
  if name then give_legendary(world, key, x, y, z, name, level, PICK_TRIES) end
  return string.format("%d runes and %d legendary runes to %s, %s %s level %d legendary to the chest", runes, lrunes,
    killer and ("player entity " .. tostring(killer)) or "a chest (no killer known)", tostring(kind), tostring(name), level)
end

function M.clear_game_loot(world, id, x, z)
  for _, t in ipairs({ 120, 180, 300 }) do clears[#clears + 1] = { id = id, at = steps + t } end
  if x and z then piles[#piles + 1] = { id = id, x = x, z = z, at = steps + 120 } end
end

-- Whether anything is waiting (a caller may skip the tick).
function M.busy() return #clears > 0 or #piles > 0 end

function M.tick(world)
  local okt, t = pcall(world.tick, world)
  if okt and t ~= nil then
    if t == last_tick then return end  -- already done this world step (more than one feature may call it)
    last_tick = t
  end
  steps = steps + 1
  pcall(loot_chest.tick, world, bag)  -- (once per world step: see core/loot_chest.lua) waiting puts, empty chests go
  if #clears > 0 then
    local keep = {}
    for _, d in ipairs(clears) do
      if d.at > steps then keep[#keep + 1] = d
      else
        for _, st in ipairs(bag.entity_stacks(world, d.id)) do
          pcall(emf.take, world, st.owner, st.item, st.count, function() end, { slot = st.slot, exact = true })
        end
      end
    end
    clears = keep
  end
  if #piles > 0 then
    local keep = {}
    for _, p in ipairs(piles) do
      if p.at > steps then keep[#keep + 1] = p
      else
        spots.find(p.id, p.x, p.z, nil, function(w, ids)
          for _, cid in ipairs(ids) do pcall(emf.destroy, w, cid) end
          if #ids > 0 then emf.log(string.format("reward loot: monster %s: its game loot pile removed (%d)", tostring(p.id), #ids)) end
        end)
      end
    end
    piles = keep
  end
  pcall(spots.tick, world)  -- answers the questions asked above (at the next step); nothing to do when none waits
end

return M
