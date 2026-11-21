-- features/companions/04_roster.lua: part 4 of the companion code (the server side), split from npc_probe.lua in 0.15.362
-- (owner 2026-11-20 18:11). The parts run in order in ONE shared environment (features/companions.lua): what was a
-- top-level local is a name in that environment, seen by every part.
-- ===== Staying =========================================================================================================
-- No game AI at all: his AI stays off (as while following), his route planner off, and FlameKit gives no target, so
-- the native hook writes nothing and he stands still where he is.
CALM = (1 << 8) | (1 << 26)  -- EnemyFeature Roaming, Investigate: also marks the body as ours (still_ours)
function calm(world, npc)
  local d = world:get("DynamicEnemy01BehaviorState", npc)
  d.disabledFeatures = (tonumber(d.disabledFeatures) or 0) | CALM
end
function stay_at(world, npc, x, y, z)
  local a = world:get("DynamicEnemy01BehaviorState", npc)
  a.enabled = false
  pcall(function() world:get("DynamicPathWalker", npc).isWalkingActive = false end)
  a.movementTargetIsValid = false
  calm(world, npc)
end

-- ===== The roster: FlameKit's own list of companions, kept in the world's data =========================================
-- Each companion has a name (N1, N2 ...) and keeps it whether its body is out in the world or put away. A record: body
-- (template GUID), spot, mode (stay/follow), owner (account), out (true: has a body in the world). The game deletes
-- our bodies on a restart: out ones come back, stayers at their spot when the world loads, followers next to their
-- owner when he joins. A script reload finds its bodies again (by entity, faction and the calm switches) instead of
-- spawning a second one.
-- Companions are PlayerAlly (faction 11), the game's own "on the players' side": friends of players, enemies of
-- monsters (with faction 7, Player, their attacks on monsters did no damage).
COMPANION_FACTION = 11
HOUND = "18eefd30-da1d-49f5-a6d8-7da8f2d01f43"  -- Enemy_Skeleton_Hound, the owner's pick
roster = { list = {}, next_n = 1, loaded = false, main = {} }  -- main: account -> name (one main companion per player)
pending_life = {}  -- entity -> { r, player, at }: set up half a second after spawning
waiting = {}       -- name -> { player, tries }: a follower waiting for its owner's body
ent_of = {}     -- name -> entity (this session only)
name_of = {}    -- entity -> name

-- who may command a companion: its controllers (a list of accounts: one for a personal companion,
-- several for a shared one) and FlameKit's admins (their own list of accounts, npc_admins.json beside the mod on the
-- server; the shared server password says nothing about who is who, the account does). Anyone else: a notice only.
store = require("core.store")
players = require("core.players")
OWNER_ACCOUNT = "0x485890b753e75ad1"  -- the server owner, the first admin
admins = store.load("npc_admins", nil)
if type(admins) ~= "table" then admins = { OWNER_ACCOUNT } store.save("npc_admins", admins) end
function is_admin(account)
  for _, a in ipairs(admins) do if a == account then return true end end
  return false
end
function controls(r, account)
  for _, a in ipairs(r.controllers or {}) do if a == account then return true end end
  return false
end
function may_command(r, account) return account and (controls(r, account) or is_admin(account)) end

-- (owner 2026-11-20 08:51 "when the chest spawns and opens I just want it to have the companions name on it") the
-- game's floating name: the chest is spawned with CustomPlayerString.stringId = FNV-1a 64 of his name (the game's own
-- key for a text); the server probe (C++) puts each name of custom_names.txt into the server's name table, which the
-- key needs BEFORE the chest is spawned (the game clears a key it does not know)
function inv.name_key(text)
  local h = 0xcbf29ce484222325
  for i = 1, #text do h = (h ~ text:byte(i)) * 0x100000001b3 end
  return h
end
function inv.write_names()
  if not emf.dir then return end
  local list = {}
  for _, r in ipairs(roster.list) do list[#list + 1] = r.name end
  table.sort(list)
  local text = table.concat(list, "\n") .. "\n"
  if text == inv.names_text then return end
  local f = io.open(emf.dir .. "\\custom_names.txt", "w")
  if not f then return end
  f:write(text)
  f:close()
  inv.names_text = text
  log("names: custom_names.txt now has " .. #list .. " name(s) for the chest labels")
end

function roster_save()
  if not roster.loaded then return false end
  pcall(inv.write_names)
  local out = { next_n = roster.next_n, main = roster.main, known = roster.known, npcs = {} }
  for _, r in ipairs(roster.list) do
    out.npcs[#out.npcs + 1] = { name = r.name, guid = r.guid, x = r.x, y = r.y, z = r.z, mode = r.mode, fight = r.fight, sus_base = r.sus_base, inv = r.inv, chest = r.chest,
      owner = r.owner, controllers = r.controllers, names = r.names, out = r.out, ent = ent_of[r.name] }
  end
  local okj, text = pcall(emf.json.encode, { npc_roster = out })
  local oks, res = pcall(emf.save_world_data, okj and text or "")
  if not (okj and oks and res) then log("roster: NOT saved (" .. tostring(okj and res or text) .. ")") end
  return oks and res
end

-- (owner 17:24) the small pets (core/pets.lua guids): they swim in shallower water (drive_read)
F.SMALL_PETS = {
  ["1ce5ac27-d8b1-4fa8-92db-f568994d080f"] = true,  -- Cat (black)
  ["60065215-15ca-424c-9bc3-5665685fed60"] = true,  -- Cat (striped)
  ["8d2e50d2-ed98-4231-9846-ca1b7fb69041"] = true,  -- Cat (bright)
  ["7e389a60-f74b-4133-a5aa-68e91623985c"] = true,  -- Bunny
  ["1b8afedd-e02c-4746-88ff-c4367b53fa8e"] = true,  -- Bunny (Cold Heights)
  ["5b609722-0dae-444b-b96c-283054a05495"] = true,  -- Turkey
  ["4757dca8-d76b-4d1c-8215-cb1e7ee533a2"] = true,  -- Desert bird
  ["0eaf60f1-7ab9-4936-9cd0-17233fb339ea"] = true,  -- Bird (flying)
}
function find(name)
  for i, r in ipairs(roster.list) do if r.name == name then return r, i end end
end
function F.is_small(id)
  local n = name_of[id]
  local r = n and find(n)
  return r and F.SMALL_PETS[r.guid] or false
end

function player_of(world, account)
  if not account then return nil end
  for id = 1, 64 do  -- player entities are the low ids (1..1023; a local server has a handful)
    local ok, a = pcall(world.account, world, id)
    if ok and a == account then return id end
  end
end

-- the body's setup: our side, calm, our E prompt, then stay or follow
on_talk = nil  -- defined below
-- a companion's level is its owner's level, set the way the game's own scaling does it (Level.dataStorage[1], then
-- DynamicEnemyScaling.nextUpdateTime = 0: the game rescales health and hits). Checked at setup and every 10 s (the
-- owner joins later, or levels up).
function match_level(world, id, r, player)
  local p = player or player_of(world, r.owner)
  if not p then return end
  local pl = world:get("Level", p)
  local lv = world:get("Level", id)
  if not (pl and lv) then return end
  local want = tonumber(pl.dataStorage[1]) or 0
  if want < 1 or lv.dataStorage[1] == want then return end
  lv.dataStorage[1] = want
  local sc = world:get("DynamicEnemyScaling", id)
  if sc then
    if type(sc.nextUpdateTime) == "table" then sc.nextUpdateTime.value = 0 else sc.nextUpdateTime = 0 end
  end
  log(string.format("level: %s (%s) set to its owner's level %d", r.name, tostring(id), want))
end

-- (owner 2026-11-18 21:35 "he definitely needs "Armor"", 21:37 "build it") armor: he takes ARMOR of the damage of every
-- type: his 19 DamageSusceptibility multipliers (one per damage type) are the base ones times ARMOR. The base is read
-- once from a body and kept in the roster (r.sus_base), so it is never scaled twice (the template's half is not
-- readable: world:template gave nothing, 21:38). Checked at setup and every second (the game may set them again, e.g.
-- when it rescales his level); logged when written.
ARMOR = 1 / 3
-- the skeleton hound's own multipliers (logged 21:22); the 21:38 version scaled the live bodies without keeping the
-- base: values that are exactly these times ARMOR are taken back to these once
HOUND_SUS = { 0, 1, 0.8, 0.6, 1.5, 0, 0, 0, 0, 1, 1, 1, 1, 0, 1, 1.2, 0.6, 0.8, 1 }
armor_err = false  -- an armor failure is logged once
function match_armor(world, id, r)
  local ds = world:get("DamageSusceptibility", id)
  if not ds then return end
  local base = r.sus_base
  if type(base) ~= "table" or #base < 19 then
    local v, scaled = {}, true
    for i = 1, 19 do
      v[i] = tonumber(ds.dataStorage[i]) or 0
      if math.abs(v[i] - HOUND_SUS[i] * ARMOR) > 0.001 then scaled = false end
    end
    base = scaled and HOUND_SUS or v
    r.sus_base = {}
    for i = 1, 19 do r.sus_base[i] = base[i] end
    base = r.sus_base
    roster_save()
    local parts = {}
    for i = 1, 19 do parts[i] = string.format("%.2f", base[i]) end
    log(string.format("armor: %s (%s) base susceptibility kept in the roster: [%s]%s", r.name, tostring(id), table.concat(parts, " "),
      scaled and " (the body was already armored: the hound's own values)" or " (from the body)"))
  end
  local changed = false
  for i = 1, 19 do
    local want = (tonumber(base[i]) or 0) * ARMOR
    if math.abs((tonumber(ds.dataStorage[i]) or 0) - want) > 0.001 then
      ds.dataStorage[i] = want
      changed = true
    end
  end
  if changed then
    local parts = {}
    for i = 1, 19 do parts[i] = string.format("%.2f", tonumber(ds.dataStorage[i]) or -1) end
    log(string.format("armor: %s (%s) susceptibility set to base x %.2f: [%s]", r.name, tostring(id), ARMOR, table.concat(parts, " ")))
  end
end

function bring_to_life(world, r, id, player)
  ent_of[r.name], name_of[id] = id, r.name
  -- a living body again: the death and stuck notices go
  local owner_p = player or player_of(world, r.owner)
  status(world, owner_p, "companion_dead", nil)
  status(world, owner_p, "companion_stuck", nil)
  if r.face_yaw then  -- a Call: he faces the way the player faced
    local yaw = r.face_yaw
    r.face_yaw = nil
    pcall(function()
      local o = world:get("CurrentTransform", id).transform.orientation
      o.x, o.y, o.z, o.w = 0, math.sin(yaw / 2), 0, math.cos(yaw / 2)
    end)
  end
  pcall(function() world:get("Faction", id).faction = COMPANION_FACTION end)
  pcall(calm, world, id)
  -- (pets, owner 09:51 "they don't die") an animal body takes no damage
  if not world:get("DynamicEnemy01BehaviorState", id) and world:get("DynamicWildlife", id) then
    roster.pet_rules = roster.pet_rules or {}
    if not roster.pet_rules[id] then
      local okr, rule = pcall(emf.hit_rule, { to = id, cancel = true })
      roster.pet_rules[id] = okr and rule or false
      log(string.format("pet %s (%s): takes no damage (%s)", r.name, tostring(id), tostring(okr and rule)))
    end
  end
  inv.prompt(world, id, inv.open[r.name] ~= nil)
  local oka, erra = pcall(match_armor, world, id, r)
  if not oka then log("armor: " .. tostring(erra)) end
  local okm, errm = pcall(match_level, world, id, r, player)
  if not okm then log("level: " .. tostring(errm)) end
  if r.mode == "follow" and player then
    drives[id] = { player = player, trail = {} }
  else
    drives[id] = nil
    pcall(stay_at, world, id, r.x, r.y, r.z)
  end
end

function spawn_body(world, r, x, y, z, player)
  -- (12:22) not inside another companion: 1.2 m further along x for each one already within 1 m of the spot
  for _ = 1, 6 do
    local busy = false
    for n, e in pairs(ent_of) do
      local ex, _, ez = world:position(e)
      if n ~= r.name and ex and (ex - x) ^ 2 + (ez - z) ^ 2 < 1 then busy = true break end
    end
    if not busy then break end
    x = x + 1.2
  end
  -- (owner 14:20 "the 'pick up' option is still there") a pet is spawned wild again: the game's pick-up comes with its
  -- IsTame tag (0.15.326-0.15.328 spawned them tame), not with the offer; his E comes from the server probe instead.
  -- (owner 18:28 "anyway to float the companion/pets name above them?" / 18:29 "lets do #1 like how the chests show
  -- it") the body gets the game's player-name label, as his chest: CustomPlayerString.stringId = FNV-1a 64 of his name
  -- (the server probe keeps the names of custom_names.txt in the server's name table). Whether the game shows it over
  -- a creature: untested.
  inv.write_names()
  local ok, id = pcall(emf.spawn, world, r.guid, x, y, z, { CustomPlayerString = { stringId = inv.name_key(r.name) } })
  if not (ok and id and id ~= 0) then  -- (as the chest) without the label rather than no body
    log(string.format("roster: %s: the spawn with his name label was refused (%s): spawned without it", r.name, tostring(id)))
    ok, id = pcall(emf.spawn, world, r.guid, x, y, z)
  else
    pcall(function()
      local k = world:get("CustomPlayerString", id)
      k = k and k.stringId
      if type(k) ~= "number" and k then k = k.value end
      log(string.format("roster: %s: name label key on his body %s (his name's 0x%016X)", r.name,
        k == nil and "none" or (math.type(k) == "integer" and string.format("0x%016X", k) or tostring(k)), inv.name_key(r.name)))
    end)
  end
  if not (ok and id and id ~= 0) then
    log(string.format("roster: %s could not be spawned (%s)", r.name, tostring(id)))
    return nil
  end
  pcall(function() world:get("Faction", id).faction = COMPANION_FACTION end)  -- at once, before its AI picks a target
  pcall(function() world:get("DynamicEnemy01BehaviorState", id).enabled = false end)  -- no game AI, ever
  r.out = true
  pending_life[id] = { r = r, player = player, at = world:tick() + 30 }  -- the rest half a second later
  ent_of[r.name], name_of[id] = id, r.name
  log(string.format("roster: %s spawned as %s at %.1f %.1f %.1f (%s)", r.name, tostring(id), x, y, z, r.mode))
  return id
end

-- is this entity still our body (a script reload keeps the bodies; a restart may give the id to something else)?
function still_ours(world, id)
  if not id or not world:position(id) then return false end
  local ok, yes = pcall(function()
    local a = world:get("DynamicEnemy01BehaviorState", id)
    local f = world:get("Faction", id)
    -- (0.15.313) a pet (an animal: no monster AI) of ours: companion faction and the animal's own data
    if not a then return f and f.faction == COMPANION_FACTION and world:get("DynamicAnimal", id) ~= nil end
    return a and f and (f.faction == COMPANION_FACTION or f.faction == 7) and ((tonumber(a.disabledFeatures) or 0) & CALM) == CALM
  end)
  return ok and yes
end

function roster_loaded(world, text)
  roster.list, roster.next_n, roster.main, ent_of, name_of = {}, 1, {}, {}, {}
  local okd, data = pcall(emf.json.decode, text or "")
  local saved = okd and type(data) == "table" and data.npc_roster
  if saved then
    roster.next_n = saved.next_n or 1
    roster.main = type(saved.main) == "table" and saved.main or {}
    roster.known = type(saved.known) == "table" and saved.known or {}  -- (roster window) account -> name
    for _, r in ipairs(saved.npcs or {}) do
      -- a record without a controller list: its owner is the only controller
      if not r.controllers then r.controllers = r.owner and { r.owner } or {} end
      r.names = r.names or {}
      roster.list[#roster.list + 1] = r
    end
  end
  roster.loaded = true
  log(string.format("roster: loaded, %d NPC(s)", #roster.list))
  for _, r in ipairs(roster.list) do if r.chest and inv.adopt then pcall(inv.adopt, world, r) end end
  for _, r in ipairs(roster.list) do
    local ent = r.ent
    r.ent = nil
    if r.out then
      local player = player_of(world, r.owner)
      if still_ours(world, ent) then  -- a script reload: the body is still there
        bring_to_life(world, r, ent, player)
        log(string.format("roster: %s found again as %s", r.name, tostring(ent)))
      elseif r.mode == "stay" then
        spawn_body(world, r, r.x, r.y, r.z, nil)
      elseif player then
        local x, y, z = world:position(player)
        if x then spawn_body(world, r, x, y + 0.5, z, player) end
      else
        log(string.format("roster: %s waits for its owner %s", r.name, tostring(r.owner)))
      end
    end
  end
  roster_save()
end

-- a player joined: his followers come to him (spawned, or found again)
function roster_joined(world, p)
  if not roster.loaded then return end
  for _, r in ipairs(roster.list) do
    if r.out and r.mode == "follow" and r.owner == p.account then
      local ent = ent_of[r.name]
      if still_ours(world, ent) then
        drives[ent] = { player = p.player, trail = {} }
        log(string.format("roster: %s follows %s again", r.name, tostring(p.player)))
      else
        waiting[r.name] = { player = p.player, tries = 0 }  -- spawned once his body is in the world
      end
    end
  end
end

function roster_cmd(world, args)
  local what = args[2]
  if what == "new" then  -- roster new <player> [guid]: a new NPC next to the player, following him
    local player = tonumber(args[3]) or 1
    local x, y, z = world:position(player)
    if not (roster.loaded and x) then emf.reply("roster: not ready / no player") return end
    local acc = world:account(player)
    local r = { name = "N" .. roster.next_n, guid = args[4] or HOUND, x = x, y = y, z = z + 3, mode = "follow",
      owner = acc, controllers = { acc }, names = { [acc] = players.name(world, player) }, out = false }
    roster.next_n = roster.next_n + 1
    roster.list[#roster.list + 1] = r
    if not roster.main[acc] then roster.main[acc] = r.name end
    spawn_body(world, r, x, y + 0.5, z, player)
    roster_save()
    emf.reply("roster: new " .. r.name)
  elseif what == "list" then
    for _, r in ipairs(roster.list) do
      local who = {}
      for _, a in ipairs(r.controllers or {}) do who[#who + 1] = a .. ((r.names or {})[a] and (" " .. r.names[a]) or "") end
      log(string.format("roster: %s | %s | %s | %s | leader %s | controllers [%s] | %s | spot %.1f %.1f %.1f", r.name,
        r.out and ("out as " .. tostring(ent_of[r.name])) or "put away", r.mode, r.fight or "Passive", tostring(r.owner), table.concat(who, "; "),
        r.guid, r.x or 0, r.y or 0, r.z or 0))
    end
    local mains = {}
    for a, n in pairs(roster.main) do mains[#mains + 1] = a .. " -> " .. n end
    log(string.format("roster: %d NPC(s); main companions %s; admins %s", #roster.list, table.concat(mains, ", "), table.concat(admins, ", ")))
    emf.reply("roster: listed in the log")
  elseif what == "away" or what == "delete" then  -- away <name>: body gone, kept on the list; delete: gone for good
    local r, i = find(args[3] or "")
    if not r then emf.reply("roster: no " .. tostring(args[3])) return end
    -- (owner 2026-11-20 09:35 "yes delete should refuse it") his items would go with him, an open chest would stay
    -- behind with no owner: delete refuses while his chest is open or he carries anything
    if what == "delete" and (inv.open[r.name] or inv.count(r.inv) > 0) then
      local why = inv.open[r.name] and "his chest is open: close it first" or
        string.format("he carries %d item(s): take them out of his chest first", inv.count(r.inv))
      log(string.format("roster: delete %s refused (%s)", r.name, why))
      emf.reply("roster: delete " .. r.name .. " refused: " .. why)
      return
    end
    -- (09:35) away with his chest open: without his body nothing could close it (E is on him, P is blocked): closed
    -- first, his items saved
    if inv.open[r.name] then inv.close(world, r, "put away") end
    local ent = ent_of[r.name]
    if ent then
      local x, y, z = world:position(ent)
      if x and r.mode == "stay" then r.x, r.y, r.z = x, y, z end
      drives[ent], name_of[ent] = nil, nil
      pcall(emf.destroy, world, ent)
    end
    ent_of[r.name], r.out = nil, false
    if what == "delete" then
      table.remove(roster.list, i)
      for a, n in pairs(roster.main) do if n == r.name then roster.main[a] = nil end end
    end
    roster_save()
    log(string.format("roster: %s %s", r.name, what == "away" and "put away" or "deleted"))
    emf.reply("roster: " .. what .. " " .. r.name)
  elseif what == "back" then  -- back <name> <player>: a stayer at its spot, a follower next to the player
    local r = find(args[3] or "")
    local player = tonumber(args[4]) or 1
    if not r then emf.reply("roster: no " .. tostring(args[3])) return end
    if r.out and still_ours(world, ent_of[r.name]) then emf.reply("roster: " .. r.name .. " is already out") return end
    if r.mode == "stay" then
      spawn_body(world, r, r.x, r.y + 0.5, r.z, nil)
    else
      local x, y, z = world:position(player)
      if not x then emf.reply("roster: no player " .. tostring(player)) return end
      r.owner = r.owner or world:account(player)
      spawn_body(world, r, x, y + 0.5, z, player)
    end
    roster_save()
    emf.reply("roster: back " .. r.name)
  elseif what == "give" or what == "share" or what == "unshare" then
    -- give <name> <player|account>: that player's alone; share: one more controller; unshare: one less
    local r = find(args[3] or "")
    if not r then emf.reply("roster: no " .. tostring(args[3])) return end
    -- "0x..." is an account, not a player entity (tonumber would read 0x...02 as player 2)
    local p = not tostring(args[4]):match("^0x") and tonumber(args[4]) or nil
    local acc = (p and world:account(p)) or args[4]
    if not (acc and acc:match("^0x%x+$")) then emf.reply("roster: no player/account " .. tostring(args[4])) return end
    r.names = r.names or {}
    if p then r.names[acc] = players.name(world, p) end
    if what == "give" then
      r.controllers, r.owner = { acc }, acc
      roster.main[acc] = r.name  -- a companion given to a player is his main one
    elseif what == "share" then
      if not controls(r, acc) then r.controllers[#r.controllers + 1] = acc end
    else
      for i = #r.controllers, 1, -1 do if r.controllers[i] == acc then table.remove(r.controllers, i) end end
    end
    roster_save()
    log(string.format("roster: %s %s %s: controllers now %s", r.name, what, acc, table.concat(r.controllers, ",")))
    emf.reply("roster: " .. what .. " done")
  elseif what == "here" then  -- here <name> <player>: moved onto the player's spot
    local r = find(args[3] or "")
    local player = tonumber(args[4]) or 1
    local ent = r and ent_of[r.name]
    local x, y, z = world:position(player)
    if not (ent and x) then emf.reply("roster: here <name> <player>") return end
    local okt = pcall(emf.teleport, world, ent, x, y, z, {})
    log(string.format("roster: %s moved onto player %s: %s", r.name, tostring(player), tostring(okt)))
    emf.reply("roster: here")
  elseif what == "main" then  -- main <name> <player|account>: that player's main companion (the one the functions use)
    local r = find(args[3] or "")
    local p = not tostring(args[4]):match("^0x") and tonumber(args[4]) or nil
    local acc = (p and world:account(p)) or args[4]
    if not (r and acc and acc:match("^0x%x+$")) then emf.reply("roster: main <name> <player|account>") return end
    roster.main[acc] = r.name
    roster_save()
    log(string.format("roster: %s is now the main companion of %s", r.name, acc))
    emf.reply("roster: main set")
  elseif what == "admin" then  -- admin add|remove <player|account>
    -- "0x..." is an account, not a player entity (tonumber would read 0x...02 as player 2)
    local p = not tostring(args[4]):match("^0x") and tonumber(args[4]) or nil
    local acc = (p and world:account(p)) or args[4]
    if not (acc and acc:match("^0x%x+$")) then emf.reply("roster: no player/account " .. tostring(args[4])) return end
    for i = #admins, 1, -1 do if admins[i] == acc then table.remove(admins, i) end end
    if args[3] == "add" then admins[#admins + 1] = acc end
    store.save("npc_admins", admins)
    log("roster: admins now " .. table.concat(admins, ", "))
    emf.reply("roster: admins changed")
  else
    emf.reply("roster: new <player> [guid] | list | away <name> | back <name> <player> | delete <name> | give/share/unshare <name> <player|account> | admin add|remove <player|account>")
  end
end

-- ===== E: the wheel ====================================================================================================
