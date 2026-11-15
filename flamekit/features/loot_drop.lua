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
local test_tag = require("core.test_tag")

local F = { id = "loot_drop", title = "Loot Drop" }
local kit

-- the game fills a body some time after the death (0.15.143: a bird's body was still empty 0.5 s after it, and was
-- then removed with its loot): look at 0.5, 1.5, 3 and 6 s; a body is removed only once loot came out of it or it
-- was seen empty at every look (a body whose loot FlameKit cannot read is left to the game)
local LOOKS = { 30, 90, 180, 360 }
local BODY_S, BOSS_BODY_S = 8, 45
local PER_STEP = 20            -- bodies handled per step (a big fight stays within EMF's time per step)

local queue, head = {}, 1      -- deaths waiting: { id, at, look }
local bodies = {}              -- body id -> step to remove it at
local steps = 0
local tally = { bodies = 0, items = 0, kept = 0, empty = 0 }  -- summed, logged once a minute (no line per monster)

-- 0.15.144 test (owner: "why can't the loot go into the dead monster's body and then dumped out to the ground?"):
-- console "flamekit.loottest on" arms it for the next monster death on the server; that body gets the game's own
-- LootInteractionEvent with itself as guest AND host (what pressing E does, the loot moved into the body itself), then
-- its items are only logged at 0.5, 1.5 and 3 s. Nothing is taken, dropped or removed; the normal Loot Drop skips that
-- body. "flamekit.loottest off" disarms it. EMF delivers an event only to scripts that named it in their first run, so
-- this needs one server restart after the update (emf.emits in F.setup).
local test = { armed = false, id = nil, step = 0, sent = nil, looks = { 1, 30, 90, 180 } }

local function get(world, c, id)
  local ok, v = pcall(world.get, world, c, id)
  if ok then return v end
  return nil
end

local function died(world, e)
  local id = e and e.deadEntityId
  if type(id) == "table" then id = id.id end
  id = tonumber(id)
  if not id or id == 0 then return end
  if test.armed and not test.id and not get(world, "PlayerState", id) and get(world, "Faction", id) then
    test.armed, test.id, test.step, test.sent = false, id, steps, nil
    return  -- this body is the test's: the normal Loot Drop leaves it alone
  end
  if not server.get("loot_to_ground") then return end
  if test_tag.is(world, id) then return end  -- (0.15.156, owner) FlameKit's test monsters: their loot goes into chests
  queue[#queue + 1] = { id = id, at = steps + LOOKS[1], look = 1 }
end

local diag = 0  -- the first bodies of a run are described in the log (what FlameKit could read of them)
local function handle(world, id, look)
  -- players never; a creature is known by its Faction at the first look only (0.15.147: the body loses it about when
  -- the game fills it with loot, 1.5-3 s after the death, and later looks skipped the body with its loot in it)
  if get(world, "PlayerState", id) or (look == 1 and not get(world, "Faction", id)) then return "skip" end
  local x, y, z = world:position(id)
  if not x then
    if diag < 10 then diag = diag + 1 emf.log(string.format("loot drop: body %s, look %d: gone", tostring(id), look)) end
    return "gone"
  end
  local keep = false
  local stacks = bag.entity_stacks(world, id)
  if diag < 10 then
    diag = diag + 1
    local setup = get(world, "InventorySetup", id)
    emf.log(string.format("loot drop: body %s, look %d: %d stack(s); InventorySetup %s, own Inventory %s", tostring(id),
      look, #stacks, tostring(setup ~= nil), tostring(get(world, "Inventory", id) ~= nil)))
  end
  if #stacks == 0 then return "empty" end
  for _, st in ipairs(stacks) do
    if st.gem then
      keep = true  -- a socketed gem would be lost on the ground: this piece stays in the body
      tally.kept = tally.kept + 1
    else
      local level, rarity = st.level or 0, st.rarity or 0
      emf.take(world, st.owner, st.item, st.count, function(w, taken)
        if taken and taken > 0 then
          local made, pid = ground.drop(w, st.item, taken, x, y, z, level, rarity, 2.5)
          if made > 0 then
            if pid then ground.mark(w, pid) end  -- (0.15.153, owner) the flame on every dropped item
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
  return "done"
end

local function describe(world, id, what)
  local stacks = bag.entity_stacks(world, id)
  local parts = {}
  for i, st in ipairs(stacks) do
    if i > 12 then parts[#parts + 1] = "..." break end
    parts[#parts + 1] = string.format("%s x%s lvl %s rar %s", tostring(st.item), tostring(st.count), tostring(st.level), tostring(st.rarity))
  end
  emf.log(string.format("loottest: body %s, %s: %d stack(s) [%s]; InventorySetup %s, own Inventory %s", tostring(id), what,
    #stacks, table.concat(parts, "; "), tostring(get(world, "InventorySetup", id) ~= nil), tostring(get(world, "Inventory", id) ~= nil)))
end

-- 0.15.145: lootAll and bypassInteraction are Lua booleans (EMF lua.md: 1 was dropped, "needs true or false"), and the
-- event waits for the body's inventory (0.15.144 measured: none at the death, there between 0.5 and 1.5 s after it)
local WAIT_MAX = 180  -- steps: send at the latest 3 s after the death
local function test_tick(world)
  if not test.id then return end
  local age = steps - test.step
  if test.watch then
    for _, at in ipairs({ 30, 90, 180, 360 }) do
      if age == at then
        local alive = pcall(world.position, world, test.id) and world:position(test.id) ~= nil
        if alive then describe(world, test.id, string.format("%.1f s after the death (watch: no event sent)", at / 60))
        else emf.log(string.format("loottest: body %s, %.1f s after the death (watch): gone", tostring(test.id), at / 60)) end
        if at == 360 then emf.log("loottest: watch done (no event was sent; nothing was taken, dropped or removed)") test.id = nil end
      end
    end
    return
  end
  if not test.sent then
    local has_inv = get(world, "InventorySetup", test.id) ~= nil or get(world, "Inventory", test.id) ~= nil
    if age == 1 then
      emf.log(string.format("loottest: body %s at the death: DefaultInventory %s, InteractionOfferRuntime %s",
        tostring(test.id), tostring(get(world, "DefaultInventory", test.id) ~= nil),
        tostring(get(world, "InteractionOfferRuntime", test.id) ~= nil)))
    end
    if has_inv or age >= WAIT_MAX then
      describe(world, test.id, string.format("%.2f s after the death, before the event", age / 60))
      local ok, done = pcall(emf.emit, "server", "LootInteractionEvent",
        { guestId = test.id, hostId = test.id, offerId = 0, lootAll = true, bypassInteraction = true })
      emf.log(string.format("loottest: body %s: LootInteractionEvent guest = host = body sent (lootAll true, bypassInteraction true): ok %s, answer %s",
        tostring(test.id), tostring(ok), tostring(done)))
      test.sent = steps
    end
    return
  end
  local since = steps - test.sent
  for i = 2, #test.looks do
    if since == test.looks[i] then
      describe(world, test.id, string.format("%.1f s after the event", test.looks[i] / 60))
      if i == #test.looks then emf.log("loottest: done (nothing was taken, dropped or removed)") test.id = nil end
    end
  end
end

function F.tick(world)
  steps = steps + 1
  if steps % 30 == 0 then pcall(ground.fx_tick, world) end  -- (0.15.153) flames off picked-up loot
  local okt, why = pcall(test_tick, world)
  if not okt then emf.log("loottest: error: " .. tostring(why)) test.id = nil end
  local n = 0
  while head <= #queue and n < PER_STEP do
    local d = queue[head]
    if d.at > steps then break end
    head, n = head + 1, n + 1
    local ok, r = pcall(handle, world, d.id, d.look)
    if not ok then
      kit.debug("warn", "loot drop: body %s: %s", tostring(d.id), tostring(r))
    elseif r == "empty" then
      if d.look < #LOOKS then
        queue[#queue + 1] = { id = d.id, at = steps + LOOKS[d.look + 1] - LOOKS[d.look], look = d.look + 1 }
      else
        tally.empty = tally.empty + 1  -- empty at every look: nothing to drop, and the body is left to the game
      end
    end
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
  if steps % 3600 == 0 and tally.bodies + tally.empty > 0 then
    emf.log(string.format("loot drop: last minute: %d bodies, %d stacks on the ground, %d kept in a body (socketed gem), %d empty",
      tally.bodies, tally.items, tally.kept, tally.empty))
    tally = { bodies = 0, items = 0, kept = 0, empty = 0 }
  end
end

function F.setup(k)
  kit = k
  local ok = pcall(emf.on_event, "EntityDiedEvent", kit.guard(F, died, "a death"), "server")
  if not ok then emf.log("loot drop: no death events: monsters keep their loot in their bodies") end
  local oke, said = pcall(emf.emits, { "LootInteractionEvent" }, "server")
  if not oke or said == false then emf.log("loot drop: LootInteractionEvent cannot be sent (" .. tostring(said) .. ")") end
  pcall(emf.command, "loottest", "on|watch|off: (watch: only logs, no event) the next monster that dies gets LootInteractionEvent with itself as guest and host; its items are logged, nothing is moved",
    kit.guard(F, function(world, args)
      if not world:is_server() then emf.reply("Only on the server world.") return end
      test.armed, test.id, test.sent = args[1] ~= "off", nil, nil
      test.watch = args[1] == "watch"
      emf.log("loottest: " .. (test.armed and ("armed" .. (test.watch and " (watch: no event)" or "") .. ": kill one monster") or "off"))
      emf.reply("loottest: " .. (test.armed and "armed" or "off"))
    end, "the loottest command"))
end

return F
