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
local spots = require("core.loot_spots")  -- (0.15.170) a creature's separate loot spot
local players = require("core.players")   -- (0.15.179) the nearest player opens a body that fills only when opened

local F = { id = "loot_drop", title = "Loot Drop" }
local kit

-- the game fills a body some time after the death (0.15.143: a bird's body was still empty 0.5 s after it, and was
-- then removed with its loot): look at 0.5, 1.5, 3 and 6 s; a body is removed only once loot came out of it or it
-- was seen empty at every look (a body whose loot FlameKit cannot read is left to the game)
local LOOKS = { 30, 90, 180, 360 }
local BODY_S, BOSS_BODY_S = 8, 45
local PER_STEP = 20            -- bodies handled per step (a big fight stays within EMF's time per step)

local queue, head = {}, 1      -- deaths waiting: { id, at, look, x, y, z, t }
local retry = {}               -- (0.15.170) loot spots to look at again: { d, at }
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

local diag = 0  -- (0.15.169) detail lines this minute (at most DIAG_MAX; was 10 for the whole run)
local DIAG_MAX = 20
local function note(fmt, ...)
  if diag < DIAG_MAX then diag = diag + 1 emf.log(string.format("loot drop: " .. fmt, ...)) end
end

local function died(world, e)
  local id = e and e.deadEntityId
  if type(id) == "table" then id = id.id end
  id = tonumber(id)
  if not id or id == 0 then note("a death without a body id") return end
  if test.armed and not test.id and not get(world, "PlayerState", id) and get(world, "Faction", id) then
    test.armed, test.id, test.step, test.sent = false, id, steps, nil
    return  -- this body is the test's: the normal Loot Drop leaves it alone
  end
  if not server.get("loot_to_ground") then return end
  if test_tag.is(world, id) then return end  -- (0.15.156, owner) FlameKit's test monsters: their loot goes into chests
  local okp, x, y, z = pcall(world.position, world, id)
  local t = spots.death_time(e)
  note("body %s died: queued (time %s)", tostring(id), tostring(t))
  queue[#queue + 1] = { id = id, at = steps + LOOKS[1], look = 1, x = okp and x or nil, y = okp and y or nil,
                        z = okp and z or nil, t = t }
end

local FX_CANDIDATES = {  -- (0.15.180) for flamekit.fx
  { "VFX_Consumable_LightWisp", "ba445d10-0b7b-402e-853b-e49b7ff50876" },
  { "VFX_Altar_FlameEssence", "eb3633fc-6b5b-4cfa-b133-60b2c87ed66e" },
  { "VFX_Player_LootCorpse_Tombstone_OnSpawn", "245f2b14-46ea-4893-bd6b-87b9fb240fdb" },
  { "VFX_SubEntity_Prop_Door_Ancient_Stars_Top", "37350371-70e1-4955-8a33-95b825ad146c" },
  { "VFX_Ability_Casting_Light", "fafcfdff-d2e7-4079-8c55-4c8add039ec6" },
  { "Base_VFX_Light", "decde8fb-896a-4b21-8cce-8a2559c7ec44" },
  { "VFX_Dummy_Light", "ab203251-703f-49aa-8ebf-11199ba135ba" },
  { "VFX_SubEntity_Player_Glider_Light", "d7bb04a2-d06c-43ac-a156-6edc5d95d53e" },
  { "Lootpickup_Scatter_VFX_Bait_T2_Moths_Above", "e1d055ad-d8d0-4d2e-b919-758607e2d4ba" },
  { "VFX_Skill_Aura_SunFire_Trigger_OnPlayer", "4aa64338-ae74-4647-a501-d40cd73af2b6" },
}
local fx_shown = {}  -- { id, at }: preview effects to remove
local fx_said = 0  -- (0.15.173) bodies whose effect components were logged (3 per run)
local function dump(v, depth)
  depth = depth or 0
  if type(v) ~= "table" and type(v) ~= "userdata" then return tostring(v) end
  if depth > 2 then return "{...}" end
  local parts, n = {}, 0
  local ok = pcall(function()
    for k, x in pairs(v) do
      n = n + 1
      if n > 24 then parts[#parts + 1] = "..." break end
      parts[#parts + 1] = tostring(k) .. "=" .. dump(x, depth + 1)
    end
  end)
  if not ok then return tostring(v) end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function handle(world, id, look)
  -- players never; a creature is known by its Faction at the first look only (0.15.147: the body loses it about when
  -- the game fills it with loot, 1.5-3 s after the death, and later looks skipped the body with its loot in it)
  if get(world, "PlayerState", id) then note("body %s: a player, skipped", tostring(id)) return "skip" end
  if look == 1 and not get(world, "Faction", id) then note("body %s, look 1: no Faction (not a creature), skipped", tostring(id)) return "skip" end
  local x, y, z = world:position(id)
  if not x then
    note("body %s, look %d: gone (no position)", tostring(id), look)
    return "gone"
  end
  local keep = false
  local stacks = bag.entity_stacks(world, id)
  note("body %s, look %d: %d stack(s); InventorySetup %s, own Inventory %s", tostring(id), look, #stacks,
    tostring(get(world, "InventorySetup", id) ~= nil), tostring(get(world, "Inventory", id) ~= nil))
  if #stacks > 0 and fx_said < 3 then  -- (0.15.173) the sparkle on a looted body: its effect components, for the log
    fx_said = fx_said + 1
    for _, c in ipairs({ "VfxResourceDynamic", "VfxComponent", "VfxParametersOverwriteComponent", "VfxComponentResource" }) do
      emf.log(string.format("loot drop: body %s %s: %s", tostring(id), c, dump(get(world, c, id))))
      local okt, tv = pcall(world.template, world, c, id)
      if okt and tv then emf.log(string.format("loot drop: body %s %s (template): %s", tostring(id), c, dump(tv))) end
    end
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
            if pid then ground.mark(w, pid) ground.sparkle(w, pid) end  -- (0.15.174) the body's sparkle on it (experiment)
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

-- (0.15.176, owner: "the loot didnt drop out"; 0.15.178) some bodies and loot spots hold only a loot table: the game
-- rolls it when someone opens them (EMF re_villages.md, immediate_loot_action: the loot goes into the GUEST's inventory,
-- all or nothing; 0.15.176 used the body as its own guest and nothing happened). So: a small storage chest is put 3 m
-- under the ground at the body (out of sight; Prop_Decoration_T0_Storage_16, spawned and filled that way in EMF's
-- re_villager_jobs.md), half a second later the game's loot event {guest = chest, host = body} (as pressing E does),
-- half a second after that the chest's items go on the ground at the body and the chest is removed.
local TEMP_CHEST = "669facd1-dc9a-41ab-8fa5-6b9f98c6a382"  -- Prop_Decoration_T0_Storage_16
local pulls = {}  -- { host, chest, x, y, z, at, stage, label }
-- (0.15.179, owner pressed E on such a body: "it gave me some junk") the loot event moves only what is already in a
-- body; the game rolls these bodies' loot on InteractionAcceptedEvent (random_loot_on_interaction, which reads the
-- opener's PlayerInput: the opener must be a player). So first that event, with the nearest player as the opener; the
-- body is then looked at again and its loot goes on the ground as usual. Needs one server restart (emf.emits).
local opened = {}  -- body id -> true once opened this way
local function open_as_player(world, id, label)
  if opened[id] then return false end
  local okp, x, _, z = pcall(world.position, world, id)
  if not okp or not x then return false end
  local best, bd = nil, nil
  local ok, ids = pcall(players.ids, world)
  for _, pid in ipairs(ok and ids or {}) do
    local okq, px, _, pz = pcall(world.position, world, pid)
    if okq and px then
      local d = (px - x) ^ 2 + (pz - z) ^ 2
      if not bd or d < bd then best, bd = pid, d end
    end
  end
  if not best then note("%s: no player to open it", tostring(label)) return false end
  local oke, done = pcall(emf.emit, "server", "InteractionAcceptedEvent", { guestEntityId = best, hostEntityId = id, offerId = 0 })
  opened[id] = true
  note("%s: opened as player %s (%s)", tostring(label), tostring(best), (oke and done ~= false) and "ok" or "refused")
  return oke and done ~= false
end

local function poke(world, id, x, y, z, label)
  if not x then
    local okp, px, py, pz = pcall(world.position, world, id)
    if not okp or not px then note("%s: no position, cannot be opened", tostring(label)) return false end
    x, y, z = px, py, pz
  end
  local ok, chest = pcall(emf.spawn, world, TEMP_CHEST, x, y - 3, z)
  if not ok or not chest or chest == 0 then note("%s: the game refused the receiving chest", tostring(label)) return false end
  pulls[#pulls + 1] = { host = id, chest = chest, x = x, y = y, z = z, at = steps + 30, stage = 1, label = label }
  return true
end

local function pull_tick(world)
  if #pulls == 0 then return end
  local keep = {}
  for _, p in ipairs(pulls) do
    if p.at > steps then keep[#keep + 1] = p
    elseif p.stage == 1 then
      local ok, done = pcall(emf.emit, "server", "LootInteractionEvent",
        { guestId = p.chest, hostId = p.host, offerId = 0, lootAll = true, bypassInteraction = true })
      note("%s: loot event into a receiving chest (%s)", tostring(p.label), (ok and done ~= false) and "ok" or "refused")
      p.stage, p.at = 2, steps + 30
      keep[#keep + 1] = p
    elseif p.stage == 2 then
      local stacks = bag.entity_stacks(world, p.chest)
      for _, st in ipairs(stacks) do
        local level, rarity = st.level or 0, st.rarity or 0
        emf.take(world, st.owner, st.item, st.count, function(w, taken)
          if taken and taken > 0 then
            local made, pid = ground.drop(w, st.item, taken, p.x, p.y, p.z, level, rarity, 2.5)
            if made > 0 then tally.items = tally.items + 1 if pid then ground.mark(w, pid) end
            else emf.put(w, p.host, st.item, taken, nil, { level = level, rarity = rarity }) end
          end
        end, { slot = st.slot, exact = true })
      end
      note("%s: %d stack(s) from the receiving chest to the ground", tostring(p.label), #stacks)
      if #stacks > 0 then tally.bodies = tally.bodies + 1 else tally.empty = tally.empty + 1 end
      p.stage, p.at = 3, steps + 30
      keep[#keep + 1] = p
    else
      pcall(emf.destroy, world, p.chest)  -- the receiving chest goes (its items were taken a step ago)
    end
  end
  pulls = keep
end

local body_again  -- below (it uses handle)
local function from_spot(world, d, again)
  local asked = spots.find(d.id, d.x, d.z, d.t, function(w, ids)
    if #ids == 0 then note("body %s: no loot spot found", tostring(d.id)) tally.empty = tally.empty + 1 return end
    for _, cid in ipairs(ids) do
      local stacks = bag.entity_stacks(w, cid)
      if #stacks == 0 and (again or 0) < 2 then  -- not filled yet: once more, a second later (the 2nd time: poked)
        if again == 1 then  -- (0.15.179) still empty: opened as a player, then looked at once more
          if open_as_player(w, cid, "loot spot " .. tostring(cid)) then
            retry[#retry + 1] = { d = d, at = steps + 30, again = 2 }
          else
            poke(w, cid, nil, nil, nil, "loot spot " .. tostring(cid))  -- (0.15.178) into a receiving chest
          end
          return
        end
        note("body %s: loot spot %s still empty, looking again", tostring(d.id), tostring(cid))
        retry[#retry + 1] = { d = d, at = steps + 60, again = (again or 0) + 1 }
        return
      end
      local okp, x, y, z = pcall(w.position, w, cid)
      if not okp or not x then x, y, z = d.x, d.y, d.z end
      local moved = 0
      for _, st in ipairs(stacks) do
        if not st.gem then
          local level, rarity = st.level or 0, st.rarity or 0
          emf.take(w, st.owner, st.item, st.count, function(w2, taken)
            if taken and taken > 0 then
              local made, pid = ground.drop(w2, st.item, taken, x, y, z, level, rarity, 2.5)
              if made > 0 then tally.items = tally.items + 1 if pid then ground.mark(w2, pid) ground.sparkle(w2, pid) end
              else emf.put(w2, cid, st.item, taken, nil, { level = level, rarity = rarity }) end
            end
          end, { slot = st.slot, exact = true })
          moved = moved + 1
        end
      end
      note("body %s: loot spot %s, %d stack(s) to the ground", tostring(d.id), tostring(cid), moved)
      tally.bodies = tally.bodies + 1
      if moved == #stacks then bodies[cid] = steps + 60 end  -- the emptied spot goes a second later
    end
  end)
  if not asked then note("body %s: gone, and its death has no time or place: its loot spot cannot be told", tostring(d.id)) end
end

body_again = function(world, r)
  local d = r.d
  local okh, res = pcall(handle, world, d.id, #LOOKS)
  if okh and res == "empty" then pcall(from_spot, world, d)
  elseif okh and res == "gone" then pcall(from_spot, world, d) end
end

function F.tick(world)
  steps = steps + 1
  pcall(spots.tick, world)
  pcall(pull_tick, world)  -- (0.15.178) bodies and spots opened into a receiving chest
  if #fx_shown > 0 then  -- (0.15.180) preview effects go after 10 s
    local keep = {}
    for _, f in ipairs(fx_shown) do
      if f.at <= steps then pcall(emf.destroy, world, f.id) else keep[#keep + 1] = f end
    end
    fx_shown = keep
  end
  if steps % 30 == 0 then pcall(ground.fx_tick, world) end  -- (0.15.171) fireflies off picked-up items
  if #retry > 0 then
    local keep = {}
    for _, r in ipairs(retry) do
      if r.at <= steps then
        if r.body then pcall(body_again, world, r) else pcall(from_spot, world, r.d, r.again) end
      else keep[#keep + 1] = r end
    end
    retry = keep
  end
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
        queue[#queue + 1] = { id = d.id, at = steps + LOOKS[d.look + 1] - LOOKS[d.look], look = d.look + 1,
                              x = d.x, y = d.y, z = d.z, t = d.t }
      elseif not d.poked and (get(world, "InventorySetup", d.id) or get(world, "Inventory", d.id)) then
        -- (0.15.176) a body with an inventory that stayed empty: filled only when opened
        d.poked = true
        if open_as_player(world, d.id, "body " .. tostring(d.id)) then
          retry[#retry + 1] = { body = true, d = d, at = steps + 30 }  -- looked at again: its loot to the ground
        elseif not poke(world, d.id, nil, nil, nil, "body " .. tostring(d.id)) then
          pcall(from_spot, world, d)
        end
      else
        pcall(from_spot, world, d)  -- (0.15.170) empty at every look: its loot may be in a separate spot
      end
    elseif r == "gone" then
      pcall(from_spot, world, d)  -- (0.15.170) the body went (it faded): its loot is in a separate spot
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
  if steps % 3600 == 0 then diag = 0 end
  if steps % 3600 == 0 and tally.bodies + tally.empty > 0 then
    emf.log(string.format("loot drop: last minute: %d bodies, %d stacks on the ground, %d kept in a body (socketed gem), %d empty",
      tally.bodies, tally.items, tally.kept, tally.empty))
    tally = { bodies = 0, items = 0, kept = 0, empty = 0 }
  end
end

function F.setup(k)
  kit = k
  local ok = pcall(emf.on_event, "EntityDiedEvent", kit.guard(F, died, "a death"), "server")
  ground.emits()  -- (0.15.174) the sparkle event for dropped items (named here: EMF wants it in the first run)
  if not ok then emf.log("loot drop: no death events: monsters keep their loot in their bodies") end
  local oke, said = pcall(emf.emits, { "LootInteractionEvent", "InteractionAcceptedEvent" }, "server")  -- (0.15.179)
  if not oke or said == false then emf.log("loot drop: LootInteractionEvent cannot be sent (" .. tostring(said) .. ")") end
  -- (0.15.180, owner: "we need to try to find another one that works") console "flamekit.fx <1-10>": candidate effect N
  -- for the ground-loot mark, 3 m in front of the nearest player for 10 s, so effects can be compared one after another
  pcall(emf.command, "fx", "<1-10>: shows candidate effect N for the loot mark 3 m in front of the nearest player for 10 s",
    kit.guard(F, function(world, args)
      if not world:is_server() then emf.reply("Only on the server world.") return end
      local n = tonumber(args[1])
      local c = n and FX_CANDIDATES[n]
      if not c then emf.reply("fx: give a number 1-" .. #FX_CANDIDATES) return end
      local ok, ids = pcall(players.ids, world)
      local pid = ok and ids and ids[1]
      local okp, x, y, z = pcall(world.position, world, pid)
      if not pid or not okp or not x then emf.reply("fx: no player") return end
      local fx, fz = 0, 1
      pcall(function()
        local q = world:get("CurrentTransform", pid).transform.orientation
        local ax, az = 2 * (q.x * q.z + q.w * q.y), 1 - 2 * (q.x * q.x + q.y * q.y)
        local len = math.sqrt(ax * ax + az * az)
        if len > 0.01 then fx, fz = ax / len, az / len end
      end)
      local oks, id = pcall(emf.spawn, world, c[2], x + fx * 3, y, z + fz * 3)
      if oks and id and id ~= 0 then
        fx_shown[#fx_shown + 1] = { id = id, at = steps + 600 }
        emf.log(string.format("loot drop: fx %d (%s) shown as entity %s", n, c[1], tostring(id)))
        emf.reply("fx " .. n .. ": " .. c[1])
      else
        emf.log(string.format("loot drop: fx %d (%s) refused (%s)", n, c[1], tostring(id)))
        emf.reply("fx " .. n .. ": refused")
      end
    end, "the fx command"))
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
