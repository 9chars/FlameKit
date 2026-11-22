-- features/companions/05_inventory.lua: part 5 of the companion code (the server side), split from npc_probe.lua in 0.15.362
-- (owner 2026-11-20 18:11). The parts run in order in ONE shared environment (features/companions.lua): what was a
-- top-level local is a name in that environment, seen by every part.
-- ===== Inventory (owner 2026-11-20 07:54/08:02) ===========================================================================
-- "Inventory" on his wheel spawns a large chest next to him with everything he carries; while it is open he is frozen
-- and his wheel offers only "Close Chest", which saves what is in it and removes the chest. It stays open until closed
-- (owner 2026-11-20 09:14: the 5-minute limit is gone, "the companion can't move so it should be safe"). Spawned entities are not saved by the game (a server restart loses them), so his
-- items live in his roster record (r.inv: {item, count, level, rarity}, in the world's data): the chest is only a view.
-- Filling: the items are put into the new chest one after another (inv.PUT_WAIT after the spawn, inv.RETRIES tries on a
-- fresh chest); r.inv is not touched until every put has answered. Open: every inv.SAVE_EVERY his record becomes the
-- chest's contents (core/bag.lua) plus what did not fit, saved when it changed, so a server restart loses at most that
-- much. Gear keeps its level and rarity (tested 2026-11-15, core/ground_loot.lua); a gem socketed into a weapon cannot be
-- put back into the socket (EMF's put knows only level and rarity), so it is kept as a separate item next to the weapon.
-- r.chest = {id, session, state} survives a script reload: the same server run takes the chest up again (an "open" one)
-- or removes it ("filling": r.inv still holds everything); a new server run has lost it (r.inv is the last save).
-- (owner 2026-11-20 09:25 "anyway to make this chest a gigantic chest instead of this small one?") the game's biggest
-- storage chest; before: Prop_Decoration_T5_Storage_40_Chest 0c667e7e-0fbd-4cb9-b58d-c3a20df7eaec (40 slots)
inv.CHEST = "bc834cbd-58f1-494a-97fb-0dc0248eb738"  -- Prop_Decoration_T6_Storage_72_Magic (72 slots)
inv.PUT_WAIT, inv.RETRIES, inv.SAVE_EVERY = 30, 3, 60
inv.SPOT = 1.5  -- m to his left (owner 09:31)

-- (owner 2026-11-20 08:19 "we'll have to test the unlocked parts") every gear piece in the chest: its level, rarity,
-- perks (PerkContainerNew: available/unlocked), durability-broken and gem, logged when the chest is filled and when it
-- closes, so one round trip shows what came back changed. `when`: "filled" or "closing".
function inv.log_gear(world, name, chest, when)
  local okset, setup = pcall(world.get, world, "InventorySetup", chest)
  if not (okset and setup) then return end
  local n = 0
  for i = 1, #(setup.linksEntities or {}) do
    local okv, invc = pcall(world.get, world, "Inventory", setup.linksEntities[i])
    for k = 1, #((okv and invc and invc.slots) or {}) do
      local sl = invc.slots[k]
      local pide = sl.data and sl.data.pide or 0
      if sl.id ~= 0 and pide ~= 0 then
        local st, pc, gs
        pcall(function() st = world:get("ItemState", pide) end)
        pcall(function() pc = world:get("PerkContainerNew", pide) end)
        pcall(function() gs = world:get("WeaponGemSlot", pide) end)
        n = n + 1
        log(string.format("inventory %s gear (%s): item %s level %s rarity %s perks %s/%s unlocked, gem %s, base damage %s, item state %s", name, when,
          tostring(sl.id), tostring(st and st.itemLevelUi), tostring(st and st.itemRarityUi), tostring(pc and pc.availablePerks),
          tostring(pc and pc.unlockedPerks), tostring(gs and gs.weaponGem and gs.weaponGem.id), tostring(st and st.baseDamageUi), tostring(st and st.itemState)))
      end
    end
  end
  if n == 0 then log(string.format("inventory %s gear (%s): none", name, when)) end
end

-- (owner 2026-11-20 08:20 "the companion can still be pushed around while the chest is open, anyway to stop that?")
-- pinned: the spot he stood on when the chest opened (or was taken up after a reload) is kept; anything that moves him
-- (a push) is undone the same tick, and his speed is set to nothing
function inv.pin(world, id)
  local c = inv.open[name_of[id] or ""]
  if not c then return end
  local p = world:get("CurrentTransform", id).transform.position
  if not c.pin or c.pin_id ~= id then c.pin, c.pin_id = { p.x, p.y, p.z }, id return end
  if p.x ~= c.pin[1] or p.y ~= c.pin[2] or p.z ~= c.pin[3] then
    p.x, p.y, p.z = c.pin[1], c.pin[2], c.pin[3]
    pcall(function() local v = world:get("Velocity", id).velocity v.x, v.y, v.z = 0, 0, 0 end)
    if not c.pushed then c.pushed = true log(string.format("inventory %s: pushed while the chest is open: put back", name_of[id])) end
  end
end

-- (owner 2026-11-20 08:22 "I wanted the "E" button to just say "Close" chest. it doesn't have to bring up the whole wheel
-- when the chest is open") his E prompt: "Talk" (the wheel), or while his chest is open the game's door "Close" text
-- and E closes the chest at once (on_talk). EMF's verbs have no "Close": inv.CLOSE_VERB is FNV-1a of the onToOffVerb
-- GUID of Base_Door's InteractionToggle (da5990c2-f8f0-413c-bb4d-fe057f4b4ca1), UNPROVEN: the same hash of its
-- offToOnVerb is not EMF's Open id, so the prompt may show "E" with no word (then the id is wrong).
inv.CLOSE_VERB = 0x3959A87F
-- (owner 2026-11-20 08:32 "the companion doesn't have an E button at all now": EMF refuses a new offer in the same
-- step the old one is taken off, "an earlier offer is still being taken off it: try again in a moment") the old offer
-- comes off now, the new one is made from the next steps on until EMF takes it (inv.want, F.tick)
inv.want = {}  -- entity -> { verb, at, tries }
function inv.prompt(world, id, open)
  -- (13:57) a pet (an animal) keeps the game's own E (EMF refuses ours there): its press opens his wheel (F.setup)
  if not world:get("DynamicEnemy01BehaviorState", id) and world:get("DynamicWildlife", id) then return end
  pcall(emf.offer_remove, world, id)
  inv.want[id] = { verb = open and inv.CLOSE_VERB or "Talk", at = world:tick() + 2, tries = 0 }
end
-- Offers the E prompt on the companions that wait for one, once the game takes it (at most 50 tries each).
function inv.want_tick(world)
  local t = world:tick()
  for id, w in pairs(inv.want) do
    if not world:position(id) then
      inv.want[id] = nil
    elseif t >= w.at then
      local ok, res = pcall(emf.offer, world, id, { verb = w.verb }, function(ww, p, npc) on_talk(ww, p, npc) end)
      w.tries = w.tries + 1
      if ok and res then
        inv.want[id] = nil
        log(string.format("prompt: E on %s offered (%s) after %d try(s)", tostring(id),
          w.verb == "Talk" and "Talk" or string.format("verb 0x%08X", w.verb), w.tries))
      elseif w.tries >= 50 then
        inv.want[id] = nil
        log(string.format("prompt: E on %s could NOT be offered after %d tries (%s)", tostring(id), w.tries, tostring(res)))
      else
        w.at = t + 6
      end
    end
  end
end

-- his chest is open: he is frozen (drive_step)
function inv.frozen(id) local n = name_of[id] return n ~= nil and inv.open[n] ~= nil end

-- (owner 2026-11-20 08:57 "upgraded items don't appear to be preserved :( it definitely stripped the upgrades off it")
-- emf.put remakes gear with its level and rarity only: the upgrades (PerkContainerNew.unlockedPerks; 08:56:41 out
-- "perks 4/1", 08:56:47 back "4/0") are now kept in his record and written back onto the new piece once the chest is
-- filled (inv.apply_unlocked)
function inv.gear_list(world, chest)
  local out = {}
  local okset, setup = pcall(world.get, world, "InventorySetup", chest)
  if not (okset and setup) then return out end
  for i = 1, #(setup.linksEntities or {}) do
    local okv, invc = pcall(world.get, world, "Inventory", setup.linksEntities[i])
    for k = 1, #((okv and invc and invc.slots) or {}) do
      local sl = invc.slots[k]
      local pide = sl.data and sl.data.pide or 0
      if sl.id ~= 0 and pide ~= 0 then
        local st, pc
        pcall(function() st = world:get("ItemState", pide) end)
        pcall(function() pc = world:get("PerkContainerNew", pide) end)
        out[#out + 1] = { item = sl.id, pide = pide, level = st and st.itemLevelUi, rarity = st and st.itemRarityUi,
          unlocked = pc and pc.unlockedPerks or 0 }
      end
    end
  end
  return out
end

-- Puts the saved upgrade levels (unlocked perks) back on the gear in a companion's chest.
function inv.apply_unlocked(world, name, c)
  local gear = inv.gear_list(world, c.chest)
  for _, f in ipairs(c.fix or {}) do
    local done = false
    for _, g in ipairs(gear) do
      if not g.used and g.item == f.item and (f.level == nil or g.level == f.level) and (g.unlocked or 0) < f.unlocked then
        g.used = true
        local ok, err = pcall(function() world:get("PerkContainerNew", g.pide).unlockedPerks = f.unlocked end)
        local now
        pcall(function() now = world:get("PerkContainerNew", g.pide).unlockedPerks end)
        log(string.format("inventory %s: upgrades put back on item %s (level %s): unlocked %s -> %s%s", name, tostring(f.item),
          tostring(g.level), tostring(g.unlocked), tostring(now), ok and "" or (" FAILED: " .. tostring(err))))
        done = true
        break
      end
    end
    if not done then log(string.format("inventory %s: upgrades for item %s (level %s, %d unlocked) found no piece to go on", name, tostring(f.item), tostring(f.level), f.unlocked)) end
  end
  c.fix = nil
end

function inv.list(world, chest)
  -- only a chest that is there and set up is read (bag.entity_stacks gives an empty list for anything else, which
  -- would empty his record)
  if not world:position(chest) then return nil end
  local okset, setup = pcall(world.get, world, "InventorySetup", chest)
  if not (okset and setup) then return nil end
  inv.bag = inv.bag or require("core.bag")
  local ok, stacks = pcall(inv.bag.entity_stacks, world, chest)
  if not (ok and type(stacks) == "table") then return nil end
  local out = {}
  local gear = inv.gear_list(world, chest)
  for _, st in ipairs(stacks) do
    out[#out + 1] = { item = st.item, count = st.count, level = st.level, rarity = st.rarity }
    if st.gear then  -- (upgrades) from the matching piece
      for _, g in ipairs(gear) do
        if not g.used and g.item == st.item and g.level == st.level then
          g.used = true
          if (g.unlocked or 0) > 0 then out[#out].unlocked = g.unlocked end
          break
        end
      end
    end
    if st.gem and st.gem ~= 0 then out[#out + 1] = { item = st.gem, count = 1 } end  -- a socketed gem: kept on its own
  end
  return out
end

-- A text that is the same for two equal item lists (order does not matter).
function inv.sig(list)
  local parts = {}
  for _, e in ipairs(list or {}) do parts[#parts + 1] = table.concat({ e.item, e.count, e.level or "", e.rarity or "", e.unlocked or "" }, ":") end
  table.sort(parts)
  return table.concat(parts, ",")
end

-- How many items a list holds.
function inv.count(list) local n = 0 for _, e in ipairs(list or {}) do n = n + (e.count or 0) end return n end

-- his record from the open chest (plus what did not fit into it); false when the chest could not be read
function inv.snapshot(world, r, c)
  local list = inv.list(world, c.chest)
  if not list then return false end
  for _, e in ipairs(c.rest) do list[#list + 1] = e end
  local sig = inv.sig(list)
  if sig ~= c.sig then
    c.sig, r.inv = sig, list
    roster_save()
    log(string.format("inventory %s: saved %d stack(s), %d item(s)", r.name, #list, inv.count(list)))
  end
  return true
end

-- (owner 2026-11-20 12:12 "N1's chest spawned in the air... can you make that stay on the ground..?" / "it spawned too
-- close to the other chest I guess": at 12:11 N1 stood about 1 m above N2, likely on another chest, and his chest was
-- spawned at his height) the server probe (C++) looks for the ground under four places around him (his left first, as
-- the owner asked 09:31, then his right, behind, in front; inv.SPOT m): chest_ground.request / .answer (the game's ray
-- straight down). The first place whose ground is near his feet (GROUND_BELOW under to GROUND_ABOVE over: not on top
-- of another chest, not down a drop) gets the chest, on that ground; else the lowest ground found near him; without
-- an answer within GROUND_WAIT (no probe) his left at his height, as before.
inv.ground = {}  -- name -> { player, npc, rr, cands, feet, at }
inv.GROUND_BELOW, inv.GROUND_ABOVE, inv.GROUND_WAIT = 1.2, 0.4, 60
inv.open_chest = function(world, player, npc, rr)
  if not rr then say(world, player, "Not on the list: no inventory.") return end
  if inv.open[rr.name] or inv.ground[rr.name] then return end
  local x, y, z = world:position(npc)
  if not x then return end
  local yaw = 0
  pcall(function()
    local q = world:get("CurrentTransform", npc).transform.orientation
    yaw = math.atan(2 * (q.x * q.z + q.w * q.y), 1 - 2 * (q.x * q.x + q.y * q.y))
  end)
  local c, sn = math.cos(yaw), math.sin(yaw)
  local d = inv.SPOT
  -- forward = (sin yaw, cos yaw); his left = (-cos yaw, sin yaw)
  local cands = { { x - c * d, z + sn * d }, { x + c * d, z - sn * d }, { x - sn * d, z - c * d }, { x + sn * d, z + c * d } }
  local lines = {}
  for i, p in ipairs(cands) do lines[#lines + 1] = string.format("%s#%d %.3f %.3f %.3f", rr.name:gsub("%s", "_"), i, p[1], y, p[2]) end
  local f = emf.dir and io.open(emf.dir .. "\\chest_ground.request", "a")
  if f then f:write(table.concat(lines, "\n") .. "\n") f:close() end
  pcall(os.remove, emf.dir and (emf.dir .. "\\chest_ground.answer") or "")
  inv.ground[rr.name] = { player = player, npc = npc, rr = rr, cands = cands, feet = y, at = world:tick() + inv.GROUND_WAIT,
    key = rr.name:gsub("%s", "_") }
end

-- FlameKit Native's ground answers (chest_ground.answer): picks the chest's place (ground near his feet, else the lowest, else his height) and opens the chest there.
function inv.ground_tick(world)
  local text
  local f = emf.dir and io.open(emf.dir .. "\\chest_ground.answer", "r")
  if f then text = f:read("a") f:close() end
  local t = world:tick()
  for name, g in pairs(inv.ground) do
    local hits, all = {}, true
    for i = 1, #g.cands do
      local v = text and text:match(g.key:gsub("%p", "%%%0") .. "#" .. i .. " (%S+)")
      if v == nil then all = false else hits[i] = tonumber(v) end
    end
    if all or t >= g.at then
      inv.ground[name] = nil
      local pick, py, how
      for i = 1, #g.cands do
        local h = hits[i]
        if h and h >= g.feet - inv.GROUND_BELOW and h <= g.feet + inv.GROUND_ABOVE then pick, py, how = i, h, "ground" break end
      end
      if not pick then
        for i = 1, #g.cands do
          local h = hits[i]
          if h and h >= g.feet - 3 and h <= g.feet + 1 and (not py or h < py) then pick, py, how = i, h, "lowest ground" end
        end
      end
      if not pick then pick, py, how = 1, g.feet, all and "no ground found: his height" or "no answer: his height" end
      if text then pcall(os.remove, emf.dir .. "\\chest_ground.answer") end
      log(string.format("inventory %s: chest place %d of 4 (%s): ground answers %s, his feet %.2f", name, pick, how,
        (function() local o = {} for i = 1, #g.cands do o[i] = tostring(hits[i] and string.format("%.2f", hits[i]) or "-") end return table.concat(o, "/") end)(),
        g.feet))
      if g.rr and find(g.rr.name) and not inv.open[g.rr.name] then
        inv.open_at(world, g.player, g.npc, g.rr, g.cands[pick][1], py, g.cands[pick][2])
      end
    end
  end
end

-- Spawns companion rr's chest at cx, y, cz (with his name label) and starts filling it from his record (the chest is his inventory while it is open).
function inv.open_at(world, player, npc, rr, cx, y, cz)
  local px, _, pz = world:position(player)
  -- (18:54) an empty label at the spawn: the C++ part writes his name's key (labels.txt, inv.write_labels)
  local oks, chest = pcall(emf.spawn, world, inv.CHEST, cx, y, cz, { CustomPlayerString = { stringId = 0 } })
  if not (oks and chest and chest ~= 0) then  -- (names) without the label rather than no chest
    log(string.format("inventory %s: the chest with his name label was refused (%s): spawned without it", rr.name, tostring(chest)))
    oks, chest = pcall(emf.spawn, world, inv.CHEST, cx, y, cz)
  end
  if not (oks and chest and chest ~= 0) then
    log(string.format("inventory %s: the chest could not be spawned (%s)", rr.name, tostring(chest)))
    say(world, player, rr.name .. ": The chest could not be opened.")
    return
  end
  local okr, rule = pcall(emf.hit_rule, { to = chest, cancel = true })  -- no damage to it
  local t = world:tick()
  local queue = {}
  for _, e in ipairs(rr.inv or {}) do queue[#queue + 1] = { item = e.item, count = e.count, level = e.level, rarity = e.rarity, unlocked = e.unlocked, tries = 0 } end
  inv.open[rr.name] = { chest = chest, player = player, t0 = t, state = "filling", queue = queue, rest = {}, at = t + inv.PUT_WAIT,
    rule = okr and rule or nil }
  rr.chest = { id = chest, session = emf.session(), state = "filling" }
  roster_save()
  inv.prompt(world, npc, true)
  log(string.format("inventory %s: chest %s opened at %.1f %.1f %.1f (%.1f m from the player) with %d stack(s), %d item(s) to put in",
    rr.name, tostring(chest), cx, y, cz, px and math.sqrt((cx - px) ^ 2 + (cz - pz) ^ 2) or -1, #queue, inv.count(rr.inv)))
  say(world, player, rr.name .. ": Inventory open.")
end

-- why: "the player" or "he died"
function inv.close(world, r, why, by)  -- by: the player who closed it (the notice goes to him)
  local c = inv.open[r.name]
  if not c then return end
  local gone = not world:position(c.chest)  -- removed by something else: his record keeps the last save
  if gone then log(string.format("inventory %s: chest %s is gone; his record keeps the last save", r.name, tostring(c.chest))) end
  if not gone then pcall(inv.log_gear, world, r.name, c.chest, "closing") end
  -- within SAVE_EVERY of the filling the new gear may not be set up yet: his record from before the opening stays
  local fresh = c.ready_t and world:tick() < c.ready_t
  if fresh then log(string.format("inventory %s: closed right after the filling: his record from before stays", r.name)) end
  if c.state == "open" and not gone and not fresh and not inv.snapshot(world, r, c) then
    log(string.format("inventory %s: the chest could not be read: it stays open for now", r.name))
    return false
  end
  -- still filling: r.inv still holds everything (nothing saved from the chest yet)
  if c.rule then pcall(emf.hit_rule_remove, c.rule) end
  pcall(emf.destroy, world, c.chest)
  inv.open[r.name] = nil
  r.chest = nil
  roster_save()
  if ent_of[r.name] then inv.prompt(world, ent_of[r.name], false) end
  log(string.format("inventory %s: chest %s closed (%s): %d stack(s), %d item(s) kept", r.name, tostring(c.chest), why,
    #(r.inv or {}), inv.count(r.inv)))
  local p = by or c.player  -- (09:17) after a log off and back on c.player is an old entity id
  if p and world:position(p) then say(world, p, r.name .. ": Inventory closed" .. (why == "the player" and "." or " (" .. why .. ").")) end
  return true
end

-- The wheel's Close Chest: closes companion rr's chest (his items back into his record).
inv.close_chest = function(world, player, npc, rr)
  if rr then inv.close(world, rr, "the player", player) end
end

-- (owner 2026-11-20 09:21 "is there a way to make a check so ONLY the player who owns the companion can open the
-- chest?") the game has no owner lock on a chest a mod spawns; when anyone else opens it (the game's
-- InteractionAcceptedEvent, guest = the player, host = the chest) it is closed at once: everything goes back into his
-- record and the chest is gone before they can take anything
function inv.on_accept(world, e)
  local host, guest = rawget(e, "hostEntityId"), rawget(e, "guestEntityId")
  for name, c in pairs(inv.open) do
    if c.chest == host then
      local r = find(name)
      local acc = guest and world:account(guest)
      if r and r.owner and acc ~= r.owner then
        log(string.format("inventory %s: chest %s opened by player %s (account %s), not the owner: closed", name, tostring(host),
          tostring(guest), tostring(acc)))
        inv.close(world, r, "someone else opened it")
        if guest then say(world, guest, name .. "'s chest: only the companion's owner can open it.") end
      else  -- (09:24) proof the game's open event reaches us for this chest (the check above rests on it)
        log(string.format("inventory %s: chest %s opened by its owner (player %s)", name, tostring(host), tostring(guest)))
      end
      return
    end
  end
end

-- every tick: fill new chests, keep open ones saved, pin him (09:21: "it needs to be pinned for all players so if I log
-- off no one can mess with it")
function inv.tick(world)
  local t = world:tick()
  for name, c in pairs(inv.open) do
    local r = find(name)
    if ent_of[name] then pcall(inv.pin, world, ent_of[name]) end
    if not r then
      inv.open[name] = nil
    elseif c.state == "filling" then
      if t >= c.at and not c.busy then
        local e = table.remove(c.queue, 1)
        if not e then
          -- (2026-11-20 08:24:10 in game: read at once, a fresh gear piece showed level 0 / rarity 0 / damage 0, item
          -- state 64; right 0.5 s later) the first save waits SAVE_EVERY after the filling
          c.state, c.ready_t = "open", t + inv.SAVE_EVERY
          r.chest.state = "open"
          roster_save()
          log(string.format("inventory %s: chest filled%s", name, #c.rest > 0 and string.format(" (%d stack(s) did not fit: kept in his record)", #c.rest) or ""))
          pcall(function()  -- (names) 0 here: the server did not know his name when the chest was spawned
            local k = world:get("CustomPlayerString", c.chest)
            k = k and k.stringId
            if type(k) ~= "number" and k then k = k.value end
            log(string.format("inventory %s: name label key on the chest %s (his name's 0x%016X)", name,
              k == nil and "none" or (math.type(k) == "integer" and string.format("0x%016X", k) or tostring(k)), inv.name_key(name)))
          end)
        else
          c.busy = true
          local opts = (e.level or e.rarity) and { level = e.level, rarity = e.rarity } or nil
          local okp = pcall(emf.put, world, c.chest, e.item, e.count, function(w, added)
            added = tonumber(added) or 0
            c.busy = false
            if added > 0 and (e.unlocked or 0) > 0 then  -- (upgrades) written back once the piece reads right
              c.fix = c.fix or {}
              c.fix[#c.fix + 1] = { item = e.item, level = e.level, unlocked = e.unlocked }
            end
            if added >= e.count then return end
            e.count = e.count - added
            if added == 0 and e.tries < inv.RETRIES then  -- a fresh chest refuses at first: again in a moment
              e.tries = e.tries + 1
              table.insert(c.queue, 1, e)
              c.at = world:tick() + inv.PUT_WAIT
            else
              c.rest[#c.rest + 1] = { item = e.item, count = e.count, level = e.level, rarity = e.rarity, unlocked = e.unlocked }
              log(string.format("inventory %s: %d of item %s did not fit into the chest (kept in his record)", name, e.count, tostring(e.item)))
            end
          end, opts)
          if not okp then
            c.busy = false
            c.rest[#c.rest + 1] = { item = e.item, count = e.count, level = e.level, rarity = e.rarity, unlocked = e.unlocked }
            log(string.format("inventory %s: emf.put refused item %s (kept in his record)", name, tostring(e.item)))
          end
        end
      end
    else
      if c.ready_t and t >= c.ready_t and not c.gear_logged then
        c.gear_logged = true
        if c.fix then pcall(inv.apply_unlocked, world, name, c) end
        pcall(inv.log_gear, world, name, c.chest, "filled")
        inv.snapshot(world, r, c)
      elseif (not c.ready_t or t >= c.ready_t) and (t - c.t0) % inv.SAVE_EVERY == 0 then
        inv.snapshot(world, r, c)
      end
    end
  end
end

-- (a script reload) his chest of this server run: an open one is taken up again, a half-filled one removed (r.inv still
-- holds everything); one of another server run is gone with it (r.inv is the last save)
inv.adopt = function(world, r)
  local ch = r.chest
  if not (type(ch) == "table" and ch.id) then r.chest = nil return end
  if ch.session ~= emf.session() or not world:position(ch.id) then
    log(string.format("inventory %s: the chest of an earlier server run is gone; his record keeps %d item(s)", r.name, inv.count(r.inv)))
    r.chest = nil
    return
  end
  if ch.state ~= "open" then
    pcall(emf.destroy, world, ch.id)
    r.chest = nil
    log(string.format("inventory %s: a half-filled chest %s removed after a reload (his record keeps everything)", r.name, tostring(ch.id)))
    return
  end
  local okr, rule = pcall(emf.hit_rule, { to = ch.id, cancel = true })
  inv.open[r.name] = { chest = ch.id, player = player_of(world, r.owner), t0 = world:tick(), state = "open", queue = {}, rest = {},
    rule = okr and rule or nil }
  log(string.format("inventory %s: chest %s taken up again after a reload", r.name, tostring(ch.id)))
end

-- ===== Auto Loot (0.15.376, owner 2026-11-21 09:35) =========================================================================
-- core/loot_route.lua puts a killed monster's loot into the bags of the companions that are out and following the
-- killer ("the player MUST have the companion spawned and following them"): his main companion first, then the others
-- in roster order; each holds at most inv.LOOT_CAP stacks (owner 08:37 "i agree with the cap 72 stack limit.. thats per
-- companion"), the same item with the same level and quality fills an existing stack first. A companion whose chest is
-- open gets nothing meanwhile (what is in the chest is saved from the chest). The roster is saved at most every
-- inv.LOOT_SAVE steps while loot comes in (every kill saving the whole roster would be too much). Returns how many it stored.
inv.LOOT_CAP, inv.LOOT_SAVE = 72, 300
inv.loot_dirty = false
function inv.loot_into(world, player, account, item, count, level, rarity)
  local items = require("core.items")
  local cands = {}
  for _, r in ipairs(roster.list) do
    local ent = ent_of[r.name]
    local d = ent and drives[ent]
    if r.out and r.mode == "follow" and d and d.player == player and not r.chest then
      cands[#cands + 1] = r
    end
  end
  local main = account and roster.main[account]
  table.sort(cands, function(a, b) return (a.name == main and 0 or 1) < (b.name == main and 0 or 1) end)
  local max = items.max_stack(item) or 1
  local left, stored, first = count, 0, nil
  for _, r in ipairs(cands) do
    if left <= 0 then break end
    if type(r.inv) ~= "table" then r.inv = {} end
    local list, n0 = r.inv, 0
    for _, e in ipairs(list) do
      if left <= 0 then break end
      if e.item == item and (e.level or 0) == (level or 0) and (e.rarity or 0) == (rarity or 0) and not e.unlocked and (e.count or 0) < max then
        local add = math.min(left, max - (e.count or 0))
        e.count, left, n0 = (e.count or 0) + add, left - add, n0 + add
      end
    end
    while left > 0 and #list < inv.LOOT_CAP do
      local add = math.min(left, max)
      list[#list + 1] = { item = item, count = add, level = level or 0, rarity = rarity or 0 }
      left, n0 = left - add, n0 + add
    end
    if n0 > 0 then
      stored = stored + n0
      first = first or r.name
      inv.loot_dirty = true
      log(string.format("auto loot: %s took %d of item %s (%d stack(s) now)", r.name, n0, tostring(item), #list))
    end
  end
  return stored, first
end

-- The player whose companion or pet `entity` is: the one he follows, else his owner when online; nil when it is none.
function inv.loot_owner(world, entity)
  local name = name_of[entity]
  local r = name and find(name)
  if not r then return nil end
  local d = drives[entity]
  if d and d.player then return d.player end
  return player_of(world, r.owner)
end
