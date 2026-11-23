-- features/companions/11_roster_window.lua: part 11 of the companion code (the server side), split from npc_probe.lua in 0.15.362
-- (owner 2026-11-20 18:11). The parts run in order in ONE shared environment (features/companions.lua): what was a
-- top-level local is a name in that environment, seen by every part.
-- ===== The Companion Roster window (owner 2026-11-20 10:00) =============================================================
-- "Companion Roster needs to be its own complete window" (opened by a button next to "Call my companion"): every
-- companion with its owner, kind, mode, items and chest; rename, change the kind (any non-boss monster template),
-- give / share / unshare, set main, put away / bring back, delete. No admin checks for now (owner: "another task for
-- another day"). The players' games ask on the channel flamekit/roster ({op = "get"}) and act ({op = "do", what, name,
-- arg}); a player who asked gets every change for 10 minutes ({op = "roster", list, players}) and the result of each
-- of his actions ({op = "result", text, ok}). Everything is kept in the roster table (the file is at Lua's 200
-- top-level locals). The existing console actions are reused (roster_cmd), their replies become the result line.
roster.RCH = "roster"
roster.subs = {}                   -- player entity -> tick of his last ask
roster.known = roster.known or {}  -- account -> the name last seen (players picked by name, also when offline)
roster.NAME_MAX = 20

-- Notes the character name of every player here (roster.known: account -> name).
function roster.ui_known(world)
  local ok, ids = pcall(players.ids, world)
  for _, pid in ipairs(ok and ids or {}) do
    local acc = world:account(pid)
    local n = acc and players.name(world, pid, nil)
    if n and roster.known[acc] ~= n then
      roster.known[acc] = n
      roster.known_changed = true
    end
  end
end

-- The Companion Roster window's data as one message: every companion and every known player (online or not).
function roster.ui_state(world)
  local online = {}
  local ok, ids = pcall(players.ids, world)
  for _, pid in ipairs(ok and ids or {}) do local a = world:account(pid) if a then online[a] = true end end
  local list, seen, pl = {}, {}, {}
  -- Adds a player (once) to the window's player list.
  local function person(acc, fallback)
    if not acc or seen[acc] then return end
    seen[acc] = true
    pl[#pl + 1] = { a = acc, n = roster.known[acc] or fallback or acc, on = online[acc] or false }
  end
  for acc, n in pairs(roster.known) do person(acc, n) end
  for _, r in ipairs(roster.list) do
    for _, a in ipairs(r.controllers or {}) do person(a, (r.names or {})[a]) end
    list[#list + 1] = { n = r.name, k = r.guid, o = r.owner or "", m = r.mode or "follow", f = r.fight or "Passive",
      out = r.out and true or false, it = inv.count(r.inv), ch = inv.open[r.name] and true or false,
      main = (r.owner and roster.main[r.owner] == r.name) and true or false, c = r.controllers or {} }
  end
  table.sort(pl, function(a, b) return tostring(a.n):lower() < tostring(b.n):lower() end)
  return emf.json.encode({ op = "roster", list = list, players = pl })
end

-- Sends the window's data to player `pid`.
function roster.ui_send(world, pid, text)
  local ok, res = pcall(emf.net.send_to, world, pid, roster.RCH, text)
  if not (ok and res) then log("roster window: not sent to " .. tostring(pid) .. " (" .. tostring(res) .. ")") end
end

-- Sends the window's data to every player who has it open, when it changed (or `force`); viewers gone or older than 10 min are dropped.
function roster.ui_push(world, force)
  local text = roster.ui_state(world)
  if not force and text == roster.ui_last then return end
  roster.ui_last = text
  local t = world:tick()
  for pid, at in pairs(roster.subs) do
    if t - at > 36000 or not world:position(pid) then roster.subs[pid] = nil else roster.ui_send(world, pid, text) end
  end
end

-- Every second while someone views the window: known names (saved when new) and the data.
function roster.ui_tick(world)
  roster.ui_known(world)
  if roster.known_changed then
    roster.known_changed = false
    roster_save()
  end
  roster.ui_push(world, false)
end

-- a new name: 1 to NAME_MAX letters, digits, spaces, - _ ' . (the chest label shows it); not another companion's
function roster.ui_rename(world, r, new)
  new = tostring(new or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
  if new == "" or #new > roster.NAME_MAX then return "A name needs 1 to " .. roster.NAME_MAX .. " characters.", false end
  if new:find("[^%w %-_'%.]") then return "Names can only have letters, digits, spaces and - _ ' .", false end
  for _, o in ipairs(roster.list) do
    if o ~= r and o.name:lower() == new:lower() then return "Another companion is already called " .. o.name .. ".", false end
  end
  if inv.open[r.name] then return r.name .. ": close his chest first.", false end
  local old = r.name
  if old == new then return "That is already his name.", true end
  for _, t in ipairs({ ent_of, returning, mana_of, waiting }) do
    if t[old] ~= nil then t[new], t[old] = t[old], nil end
  end
  for id, n in pairs(name_of) do if n == old then name_of[id] = new end end
  for a, n in pairs(roster.main) do if n == old then roster.main[a] = new end end
  r.name = new
  roster_save()
  log(string.format("roster window: %s renamed to %s", old, new))
  return old .. " is now called " .. new .. ".", true
end

-- another kind: any non-boss monster template (core/monsters.lua); a body that is out is replaced at its spot
function roster.ui_kind(world, r, guid, pid)
  local kind
  for _, m in ipairs(require("core.monsters")) do if m[3] == guid then kind = m end end
  -- (0.15.313, owner 11:40) the Pets section: the game's peaceful animals (core/pets.lua; no babies since 0.15.345)
  for _, m in ipairs(require("core.pets")) do if m[3] == guid then kind = m end end
  if not kind then return "Unknown kind.", false end
  if kind[4] then return "Bosses cannot be companions.", false end
  if inv.open[r.name] then return r.name .. ": close his chest first.", false end
  if r.guid == guid then return r.name .. " already is a " .. kind[2] .. ".", true end
  local was = r.guid
  r.guid, r.sus_base = guid, nil  -- (armor) the new body's own values are read again
  local ent = ent_of[r.name]
  if ent and world:position(ent) then
    local x, y, z = world:position(ent)
    local h = drives[ent]
    drives[ent], name_of[ent], ent_of[r.name] = nil, nil, nil
    pcall(emf.destroy, world, ent)
    spawn_body(world, r, x, y + 0.3, z, r.mode == "follow" and (h and h.player or player_of(world, r.owner)) or nil)
  end
  roster_save()
  log(string.format("roster window: %s is now %s / %s (%s, was %s)", r.name, kind[1], kind[2], guid, tostring(was)))
  if kind[1] == "Pets" then return r.name .. " is now a pet: " .. kind[2] .. ".", true end  -- (16:08: the "do not follow yet" text was old)
  return r.name .. " is now a " .. kind[2] .. " (" .. kind[1] .. ").", true
end

-- (owner 11:26 "can you make "Bring back" spawn the companion next to the player? I just put N2 away and brought back
-- and its not near me") next to the player who clicked, 0.3 m to his right and facing his way (as Call): a follower
-- follows him, a stayer stays at that new spot
function roster.ui_back(world, r, pid)
  if r.out and still_ours(world, ent_of[r.name]) then return r.name .. " is already out.", false end
  local x, y, z = world:position(pid)
  if not x then return "You are not in the world.", false end
  local yaw
  pcall(function()
    local o = world:get("CurrentTransform", pid).transform.orientation
    yaw = math.atan(2 * (o.x * o.z + o.w * o.y), 1 - 2 * (o.x * o.x + o.y * o.y))
    x, z = x + math.cos(yaw) * 0.3, z - math.sin(yaw) * 0.3
  end)
  if r.mode == "stay" then r.x, r.y, r.z = x, y, z end
  r.face_yaw = yaw
  local id = spawn_body(world, r, x, y + 0.5, z, r.mode == "follow" and pid or nil)
  if id and yaw then
    pcall(function()
      local o = world:get("CurrentTransform", id).transform.orientation
      o.x, o.y, o.z, o.w = 0, math.sin(yaw / 2), 0, math.cos(yaw / 2)
    end)
  end
  roster_save()
  if not id then return r.name .. " could not be spawned.", false end
  return r.name .. " is back next to you" .. (r.mode == "stay" and " (staying there)." or ", following you."), true
end

-- (pets, owner 12:43/12:48 "n2 is a dog now") petlog: the wildlife AI of an animal body (program "wildlife": it writes
-- ActorInput, DynamicLocomotion, DynamicPathWalker, DynamicWildlife)
function roster.petlog_tick(world)
  local pl = roster.petlog
  local id = pl.id
  if world:tick() > pl.untill or not world:position(id) then roster.petlog = nil log("petlog " .. id .. ": done") return end
  -- A value read for the log ("err" when it cannot be read).
  local function rd(f) local ok, v = pcall(f) if ok then return v end return "err" end
  local x, y, z = world:position(id)
  local wl = rd(function() local w = world:get("DynamicWildlife", id) return string.format("state %s (last %s), target %.1f %.1f %.1f, keep until %s, flee %s",
    tostring(w.state), tostring(w.lastState), w.currentTargetPosition.x, w.currentTargetPosition.y, w.currentTargetPosition.z,
    tostring(w.keepRoamingTargetUntilTime), tostring(w.lastFleeTime)) end)
  local ai = rd(function() local a = world:get("ActorInput", id) return string.format("move %.2f %.2f speed %s",
    a.desiredWorldMoveInput.x, a.desiredWorldMoveInput.z, tostring(a.locomotionSpeed)) end)
  local pw = rd(function() local p = world:get("DynamicPathWalker", id) return string.format("walker %s, to %.1f %.1f %.1f",
    tostring(p.state), p.targetPosition.x, p.targetPosition.y, p.targetPosition.z) end)
  local an = rd(function() local a = world:get("DynamicAnimal", id) return "animal state " .. tostring(a.state) end)
  log(string.format("petlog %d at %.1f %.1f %.1f: %s | %s | %s | %s | time %s", id, x, y, z, tostring(wl), tostring(ai), tostring(pw),
    tostring(an), tostring(rd(function() return world:get("SpawnTime", id).time end))))
  -- (owner 14:09 "remove the pick up and pet option") the game's offer on the animal: which sequence / verb it shows
  local function sv(v)
    if type(v) ~= "table" then return tostring(v) end
    local t = {}
    for k, x in pairs(v) do t[#t + 1] = tostring(k) .. "=" .. sv(x) end
    table.sort(t)
    return "{" .. table.concat(t, " ") .. "}"
  end
  local of = rd(function() local o = world:get("InteractionOfferRuntime", id) if not o then return "none" end
    return string.format("default seq %s verb %s, override seq %s verb %s, offerId %s, offered %s, disabled %s, last guest %s offer %s",
      sv(o.defaultSequence), sv(o.defaultVerbId), sv(o.overrideSequence), sv(o.overrideVerbLocaId), sv(o.offerId),
      sv(o.isOffered), sv(o.isDisabled), sv(rd(function() return o.lastAcceptData.guestId end)), sv(rd(function() return o.lastAcceptData.offerId end))) end)
  -- (14:42 "still nothing": E on the Talk prompt fires no InteractionAcceptedEvent) what may refuse the press
  local function comp(n) return rd(function() local c = world:get(n, id) if c == nil then return "none" end return sv(c) end) end
  log(string.format("petlog %d locks: InteractionLock %s | InteractionKnowledgeLock %s | InteractionOffer %s | ClientInteractionOffer %s | InteractionPause %s",
    id, comp("InteractionLock"), comp("InteractionKnowledgeLock"), comp("InteractionOffer"), comp("ClientInteractionOffer"), comp("InteractionPause")))
  log(string.format("petlog %d offer: %s | tame %s | emf offer %s", id, tostring(of),
    tostring(rd(function() return world:get("IsTame", id) ~= nil end)), tostring(rd(function() return emf.offered and emf.offered(world, id) end))))
end

-- (pets) the drive's inputs for the server probe, in pet_drive.txt beside the mod: a line per pet "<entity> <target x y
-- z> <player spot x y z> <code>" (code: pace 2 walk / 3 run / 4 sprint, + 10 edge stop off, + 20 drops allowed; 0 = not
-- driven), written each tick it changes; its drive_post reads it. (13:04: the first try kept them in the animal's own
-- AnimalSaved / DynamicWildlife spawn positions: the game moved the dog by them, 20 m jumps every half second.)
-- (owner 14:49 / 14:59) "Pet" in a pet's wheel. The game offers no call that plays its petting, and the server sending
-- AcceptOfferedInteractionEvent in the player's name did nothing (0.15.335, 15:05: never accepted; the player's own game
-- starts the petting). So (owner 15:06 "it lets me press E again for the pet") Pet switches the pet's offer to the
-- game's pet action (the server probe, 9th field of pet_drive.txt = 1; sequence 0xB1EB4A70, verb Pet) and tells the
-- player to press E; that E plays the game's petting. Back to Talk PET_AFTER ticks after that press is accepted
-- (InteractionAcceptedEvent, "petting accepted", no wheel), or after PET_HOLD ticks without one.
roster.pet_mode = {}   -- pet entity -> { player, at = tick set, accepted = tick or nil }
roster.PET_HOLD, roster.PET_AFTER = 600, 30
function roster.do_pet(world, player, npc, rr)
  roster.pet_mode[npc] = { player = player, at = world:tick() }
  say(world, player, "Press E to pet " .. tostring(rr and rr.name or "your pet") .. ".")
  log(string.format("pet %s (%s): Pet picked by player %s: his offer goes to the game's pet action", tostring(rr and rr.name), tostring(npc), tostring(player)))
end
-- A "Pet" from the wheel under way: the pet's offer goes back to Talk once it was petted, or after PET_HOLD.
function roster.pet_mode_tick(world)
  local t = world:tick()
  for npc, m in pairs(roster.pet_mode) do
    if not world:position(npc) then
      roster.pet_mode[npc] = nil
    elseif (m.accepted and t - m.accepted >= roster.PET_AFTER) or t - m.at >= roster.PET_HOLD then
      log(string.format("pet %s: back to Talk (%s)", tostring(npc), m.accepted and "petted" or "not petted"))
      roster.pet_mode[npc] = nil
    end
  end
end

-- (owner 15:39 "in the wheel menu, id like a new section called "Companions" this option would apply to both Pets and
-- the Monster Companions" / "this wheel should should all the assigned pets and companions to that user and let them
-- spawn them to them"; confirmed "yup": every companion and pet he controls, by name and kind; a pick spawns it beside
-- him, following him, as the roster window's Bring back; one already out is put away first; the main is unchanged)
roster.cw = {}   -- player -> { map = label -> companion name, at = tick } of the Companions wheel sent to him
function roster.wheel_list(world, player, npc, rr)
  local account = world:account(player)
  local names = {}
  for _, r in ipairs(roster.list) do if account and controls(r, account) then names[#names + 1] = r end end
  table.sort(names, function(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end)
  if #names == 0 then say(world, player, "You have no companions.") return end
  local kinds = {}
  for _, m in ipairs(require("core.monsters")) do kinds[m[3]] = m[2] end
  for _, m in ipairs(require("core.pets")) do kinds[m[3]] = m[2] end
  local labels, map = {}, {}
  for _, r in ipairs(names) do
    local label = r.name .. " (" .. tostring(kinds[r.guid] or "?") .. ")" .. (r.out and still_ours(world, ent_of[r.name]) and " - out" or "")
    labels[#labels + 1] = label
    map[label] = r.name
  end
  roster.cw[player] = { map = map, at = world:tick() }
  local oks, sent = pcall(emf.net.send_to, world, player, WHEEL, emf.json.encode({ op = "wheel", npc = npc, title = "Companions", labels = labels }))
  log(string.format("wheel: Companions for player %s: %s (sent %s)", tostring(player), table.concat(labels, ", "), tostring(oks and sent)))
end
-- The wheel's Companions list: brings companion `name` to the player (put away first when he is out elsewhere).
function roster.wheel_summon(world, player, name)
  local r = find(name)
  if not r then say(world, player, tostring(name) .. " is no longer on the roster.") return end
  local account = world:account(player)
  if not (account and controls(r, account)) then refuse(world, player, r) return end
  if r.out and still_ours(world, ent_of[r.name]) then
    local real = emf.reply
    -- (roster_cmd answers through emf.reply: silenced here)
    emf.reply = function() end
    local okc, errc = pcall(roster_cmd, world, { "roster", "away", r.name })
    emf.reply = real
    if not okc then log("wheel: Companions: away " .. r.name .. " failed: " .. tostring(errc)) end
  end
  r.mode = "follow"
  local said, good = roster.ui_back(world, r, player)
  log(string.format("wheel: Companions: player %s called %s: %s", tostring(player), r.name, tostring(said)))
  say(world, player, said, good and "#5ad25a" or nil)
  roster.ui_push(world, true)
end

roster.pet_lines = {}
-- Keeps pet `id`'s drive target for FlameKit Native (one line of pet_drive.txt).
function roster.pet_flush(world, id, h)
  local a = h.shim
  local cd = a.combatData
  local code = a.movementTargetIsValid and ((tonumber(cd.prowlAngle) or 2) + (cd.targetOfMyTarget and 10 or 0)
    + (cd.isTargetInsideLeash and 20 or 0)) or 0
  roster.pet_lines[id] = string.format("%d %.3f %.3f %.3f %.3f %.3f %.3f %g %d", id, a.movementTarget.x, a.movementTarget.y,
    a.movementTarget.z, a.homeZonePosition.x, a.homeZonePosition.y, a.homeZonePosition.z, code,
    -- the offer (the probe's pet_offers): 1 = the game's pet action (Pet in his wheel), 2 = "Close" while his chest is
    -- open (owner 16:10 "when their inventory crate is open, the pet still says "E" Talk instead of "E" Close"), 0 = Talk
    roster.pet_mode[id] and 1 or ((name_of[id] and inv.open[name_of[id]]) and 2 or 0))
  cd.targetOfMyTarget = false  -- set again each tick where the edge stop is off (edge_off)
end
-- Writes pet_drive.txt (the driven pets' targets) for FlameKit Native when it changed (a temporary file moved over it).
function roster.pet_write()
  local list = {}
  for id, line in pairs(roster.pet_lines) do if drives[id] then list[#list + 1] = line end end
  roster.pet_lines = {}
  table.sort(list)
  local text = table.concat(list, "\n") .. "\n"
  if text == roster.pet_text or not emf.dir then return end
  local f = io.open(emf.dir .. "\\pet_drive.tmp", "w")
  if not f then return end
  f:write(text)
  f:close()
  os.remove(emf.dir .. "\\pet_drive.txt")
  os.rename(emf.dir .. "\\pet_drive.tmp", emf.dir .. "\\pet_drive.txt")
  roster.pet_text = text
end

-- Keeps every pet's own animal AI still (wildlife state 3, no path walking): FlameKit drives them.
function roster.pets_quiet(world)
  for _, id in pairs(ent_of) do
    local wl = world:get("DynamicWildlife", id)
    if wl and not world:get("DynamicEnemy01BehaviorState", id) then
      if wl.state ~= 3 then wl.state = 3 end
      local pw = world:get("DynamicPathWalker", id)
      if pw and pw.isWalkingActive ~= false then pw.isWalkingActive = false end
    end
  end
end

-- (owner 14:09 "yeah we need to remove the pick up and pet option, the pet option could be put in the wheel"; 14:22
-- "pick up is gone, but so is the E menu") a pet is spawned wild (spawn_body); its E offer is set by the server probe
-- (C++, pet_offers: right before the game's interaction_offer program each step; a Lua write after the step lost to
-- the game's own offer every step, 0.15.328-0.15.329). E then fires InteractionAcceptedEvent: his wheel (F.setup).

-- A message from the Companion Roster window (admins only): get the data, or an action (new, rename, delete, give, share, unshare, main, kind, away, back); the answer goes back to the window.
function roster.ui_do(world, from, data)
  local okd, m = pcall(emf.json.decode, data)
  if not (okd and type(m) == "table") then return end
  local pid = from.player
  if not pid then return end
  -- (owner 17:42 "I think the Companion Roster needs to be protected by admin rights"; 17:46 "yes": only admins use it,
  -- the server refuses everyone else; the game greys the button out from {op = "admin"} on npcwheel)
  if not is_admin(from.account, from) then
    roster.ui_send(world, pid, emf.json.encode({ op = "denied", text = "Only admins can use the Companion Roster." }))
    -- (0.15.375) said once per account (a game from before 0.15.375 asks every 5 s)
    F.denied_said = F.denied_said or {}
    if not F.denied_said[from.account or pid] then
      F.denied_said[from.account or pid] = true
      log(string.format("roster window: player %s (%s) is not an admin: %s refused (said once)", tostring(pid), tostring(from.account), tostring(m.op)))
    end
    return
  end
  roster.subs[pid] = world:tick()
  if m.op == "get" then
    roster.ui_known(world)
    roster.ui_send(world, pid, roster.ui_state(world))
    return
  end
  if m.op ~= "do" then return end
  local what, arg = tostring(m.what or ""), m.arg
  local r = find(tostring(m.name or ""))
  local said, good
  if what == "new" then  -- (0.15.310) a hound of the asking player, next to him, following him (roster new)
    local real = emf.reply
    -- (roster_cmd's answer is caught for the window)
    emf.reply = function(t) said = t end
    local okc, errc = pcall(roster_cmd, world, { "roster", "new", tostring(pid) })
    emf.reply = real
    local made = okc and tostring(said or ""):match("^roster: new (.+)$")
    said, good = made and (made .. " is made: a hound next to you, following you.") or ("Not made: " .. tostring(okc and said or errc)), made and true
  elseif not r then
    said, good = "No companion called " .. tostring(m.name) .. ".", false
  elseif what == "rename" then
    said, good = roster.ui_rename(world, r, arg)
  elseif what == "kind" then
    said, good = roster.ui_kind(world, r, tostring(arg or ""), pid)
  elseif what == "back" then
    said, good = roster.ui_back(world, r, pid)
  else
    local args
    if what == "away" or what == "delete" then args = { "roster", what, r.name }
    elseif what == "give" or what == "share" or what == "unshare" then args = { "roster", what, r.name, tostring(arg or "") }
    elseif what == "main" then args = r.owner and { "roster", "main", r.name, r.owner } end
    if not args then
      said, good = what == "main" and (r.name .. " has no owner.") or "Unknown action.", false
    else
      local real = emf.reply
      -- (roster_cmd's answer is caught for the window)
      emf.reply = function(t) said = t end
      local okc, errc = pcall(roster_cmd, world, args)
      emf.reply = real
      if not okc then said = "Failed: " .. tostring(errc) end
      said = tostring(said or "Done."):gsub("^roster: ", "")
      good = okc and not said:find("refused") and not said:find("^no ") and not said:find("already")
      if good then  -- the window's words for what was done
        local who = arg and (roster.known[tostring(arg)] or tostring(arg))
        local owner = r.owner and (roster.known[r.owner] or r.owner)
        local nice = { give = r.name .. " now belongs to " .. tostring(who) .. ".",
          share = tostring(who) .. " can now command " .. r.name .. ".",
          unshare = tostring(who) .. " can no longer command " .. r.name .. ".",
          main = r.name .. " is now " .. tostring(owner) .. "'s main companion.",
          away = r.name .. " is put away.", back = r.name .. " is back.", delete = r.name .. " is deleted." }
        said = nice[what] or said
      end
    end
  end
  log(string.format("roster window: player %s (%s): %s %s %s -> %s", tostring(pid), tostring(from.account), what,
    tostring(m.name), tostring(arg), tostring(said)))
  roster.ui_send(world, pid, emf.json.encode({ op = "result", text = said, ok = good and true or false }))
  roster.ui_push(world, true)
end

return F
