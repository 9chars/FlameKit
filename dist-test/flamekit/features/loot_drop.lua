-- features/loot_drop.lua (0.15.142, owner): "Monsters drop their loot on the ground", a server setting (the Server
-- tab). Where the world is hosted, when it is on: every monster that dies (the game's own and FlameKit's test
-- monsters) gets its loot taken out of its body and put on the ground beside it, as the same items with the same
-- quality and level (core/ground_loot.lua), so nobody has to press E. Its body is removed 8 s after the death, a
-- boss's (Boss component) after 45 s. Players and their bodies are never touched.
-- What a loose item cannot carry (core/ground_loot.lua): a gem socketed into a weapon. A piece that has one stays in
-- the body (pressing E still gets it) and the body is then left to the game.
-- Uses only core modules (HANDOFF rule 0b). The death event (EntityDiedEvent) needs one server restart after the
-- update that brought it (EMF delivers an event only to scripts that asked for it when the server started).

local bag = require("core.bag")
local ground = require("core.ground_loot")
local server = require("core.server_settings")

local F = { id = "loot_drop", title = "Loot Drop" }
local kit

local LOOT_WAIT_STEPS = 30     -- the game fills a body just after the death: look 0.5 s later
local BODY_S, BOSS_BODY_S = 8, 45
local PER_STEP = 20            -- bodies handled per step (a big fight stays within EMF's time per step)

local queue, head = {}, 1      -- deaths waiting: { id, at }
local bodies = {}              -- body id -> step to remove it at
local steps = 0
local tally = { bodies = 0, items = 0, kept = 0 }  -- summed, logged once a minute (no line per monster)

local function get(world, c, id)
  local ok, v = pcall(world.get, world, c, id)
  if ok then return v end
  return nil
end

local function died(world, e)
  if not server.get("loot_to_ground") then return end
  local id = e and e.deadEntityId
  if type(id) == "table" then id = id.id end
  id = tonumber(id)
  if not id or id == 0 then return end
  queue[#queue + 1] = { id = id, at = steps + LOOT_WAIT_STEPS }
end

local function handle(world, id)
  if get(world, "PlayerState", id) or not get(world, "Faction", id) then return end  -- players, and things that are no creature
  local x, y, z = world:position(id)
  if not x then return end
  local keep = false
  for _, st in ipairs(bag.entity_stacks(world, id)) do
    if st.gem then
      keep = true  -- a socketed gem would be lost on the ground: this piece stays in the body
      tally.kept = tally.kept + 1
    else
      local level, rarity = st.level or 0, st.rarity or 0
      emf.take(world, st.owner, st.item, st.count, function(w, taken)
        if taken and taken > 0 then
          if ground.drop(w, st.item, taken, x, y, z, level, rarity, 2.5) > 0 then
            tally.items = tally.items + 1
          else
            emf.put(w, id, st.item, taken, nil, { level = level, rarity = rarity })  -- not dropped: back, nothing is lost
          end
        end
      end, { slot = st.slot, exact = true })
    end
  end
  tally.bodies = tally.bodies + 1
  if not keep then bodies[id] = steps + 60 * (get(world, "Boss", id) and BOSS_BODY_S or BODY_S) end
end

function F.tick(world)
  steps = steps + 1
  local n = 0
  while head <= #queue and n < PER_STEP do
    local d = queue[head]
    if d.at > steps then break end
    head, n = head + 1, n + 1
    local ok, err = pcall(handle, world, d.id)
    if not ok then kit.debug("warn", "loot drop: body %s: %s", tostring(d.id), tostring(err)) end
  end
  if head > #queue then queue, head = {}, 1 end
  if steps % 30 == 0 then
    for id, at in pairs(bodies) do
      if steps >= at then
        bodies[id] = nil
        pcall(emf.destroy, world, id)
      end
    end
  end
  if steps % 3600 == 0 and tally.bodies > 0 then
    emf.log(string.format("loot drop: last minute: %d bodies, %d stacks on the ground, %d kept in a body (socketed gem)",
      tally.bodies, tally.items, tally.kept))
    tally = { bodies = 0, items = 0, kept = 0 }
  end
end

function F.setup(k)
  kit = k
  local ok = pcall(emf.on_event, "EntityDiedEvent", kit.guard(F, died, "a death"), "server")
  if not ok then emf.log("loot drop: no death events: monsters keep their loot in their bodies") end
end

return F
