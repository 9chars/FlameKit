-- features/companions/10_tick.lua: part 10 of the companion code (the server side), split from npc_probe.lua in 0.15.362
-- (owner 2026-11-20 18:11). The parts run in order in ONE shared environment (features/companions.lua): what was a
-- top-level local is a name in that environment, seen by every part.
function put_away_for(world, id, h)
  local name = name_of[id]
  local r = name and find(name)
  drives[id], name_of[id] = nil, nil
  pcall(emf.destroy, world, id)
  if r then ent_of[r.name], r.out = nil, false roster_save() end
  status(world, h.player, "companion_stuck", nil)
  if h.go_away == "can't follow" and F.follow_notices(world, h.player) then  -- (owner 22:22 "show the error") the same
    -- words for 5 s, as he is respawned at once; (owner 2026-11-20 16:20) only with the Debug option on
    say(world, h.player, STUCK_TEXT[h.cant] or STUCK_TEXT.blocked, "#ff9050")
  end
  if h.go_away == "glide" then
    status(world, h.player, "companion_away", "Companion put away, waiting for your landing.", "#8cd2ff")
  end
  local okacc, acc = pcall(world.account, world, h.player)
  if name then returning[name] = { player = h.player, account = (r and r.owner) or (okacc and acc), why = h.go_away } end
  log(string.format("away: %s (%s) put away (%s); back beside player %s once he stands on the ground", tostring(name),
    tostring(id), tostring(h.go_away), tostring(h.player)))
end
companions_core = require("core.companions")  -- the minimap's companion dots
function F.tick(world)
  if not world:is_server() then return end
  local t = world:tick()
  if t % 60 == 13 and next(roster.subs) then pcall(roster.ui_tick, world) end  -- (roster window) changes to its viewers
  if roster.petlog and t % 30 == 0 then pcall(roster.petlog_tick, world) end  -- (pets) the animal AI watched
  if next(roster.pet_mode) then pcall(roster.pet_mode_tick, world) end  -- (pets) a "Pet" from the wheel under way
  if #heal_fx_shown > 0 then  -- (healfx preview) effects go after 10 s
    local keep = {}
    for _, f in ipairs(heal_fx_shown) do
      if f.at <= t then pcall(emf.destroy, world, f.id) else keep[#keep + 1] = f end
    end
    heal_fx_shown = keep
  end
  if next(inv.want) then pcall(inv.want_tick, world) end  -- (his E prompt) made once EMF takes it
  if next(inv.ground) then  -- (12:12) his chest's place on the ground, once the probe answered
    local okg, errg = pcall(inv.ground_tick, world)
    if not okg then log("inventory: ground: " .. tostring(errg)) inv.ground = {} end
  end
  if next(inv.open) then  -- (inventory) fill new chests, keep open ones saved, close forgotten ones
    local oki, erri = pcall(inv.tick, world)
    if not oki then log("inventory: tick failed: " .. tostring(erri)) end
  end
  -- (fight, step 2: watching only) the monster scan, and once a second what each companion would do
  local okw, errw = pcall(monster_scan_step, world)
  if not okw then mscan = nil log("fight scan failed: " .. tostring(errw)) end
  if t % 60 == 0 then
    local okf, errf = pcall(fight_watch, world)
    if not okf then log("fight watch failed: " .. tostring(errf)) end
  end
  if t % 30 == 0 then  -- where every companion is, with its owner's character name (the dot's colour)
    local places = {}
    for name, id in pairs(ent_of) do
      local x, _, z = world:position(id)
      local r = find(name)
      if x and r then
        local p = player_of(world, r.owner)
        local okn, cname = pcall(function() return p and require("core.players").name(world, p) end)  -- the dot's colour comes from the same name the far list uses
        places[#places + 1] = { x = x, z = z, owner = (okn and cname) or "", name = name }  -- the dot shows the companion's name
      end
    end
    companions_core.set_places(places)
  end
  if t % 15 == 0 then
    for name, id in pairs(ent_of) do
      if not dead_told[id] then
        local okh, hp = pcall(function() return world:get("Health", id).dataStorage[1] end)
        if okh and hp and hp <= 0 then
          dead_told[id] = true
          local r = find(name)
          local p = r and player_of(world, r.owner)
          local x, y, z = world:position(id)
          log(string.format("died: %s (%s) at %s", name, tostring(id), x and string.format("%.1f %.1f %.1f", x, y, z) or "?"))
          if p then
            status(world, p, "companion_stuck", nil)
            status(world, p, "companion_dead", "Companion has died!", "#ff4040")
          end
          -- (owner 2026-11-20 08:15 "if the companion dies with the chest open, the chest needs to despawn") closed the
          -- usual way: what is in it is saved first
          if r and inv.open[r.name] then pcall(inv.close, world, r, "he died") end
        end
      end
    end
  end
  if t % 600 == 0 then
    for name, id in pairs(ent_of) do
      local r = find(name)
      if r and world:position(id) then
        local okm, errm = pcall(match_level, world, id, r, nil)
        if not okm then log("level: " .. tostring(errm)) end
      end
    end
  end
  if t % 60 == 0 then  -- armor, every second
    for name, id in pairs(ent_of) do
      local r = find(name)
      if r and world:position(id) then
        local oka, erra = pcall(match_armor, world, id, r)
        if not oka and not armor_err then armor_err = true log("armor: " .. tostring(erra)) end
      end
    end
  end
  for id, r in pairs(fullrecs) do
    if t > r.untill or not world:position(id) then
      fr_write(r, fr_stamp(world) .. " END")
      pcall(function() r.file:close() end)
      fullrecs[id] = nil
      log("fullrec " .. tostring(id) .. ": ended")
    elseif t >= r.next then
      r.next = t + 30
      local okf, errf = pcall(fullrec_step, world, id, r)
      if not okf then log("fullrec " .. tostring(id) .. ": " .. tostring(errf)) end
    end
  end
  for id, pl in pairs(pending_life) do
    if t >= pl.at then
      pending_life[id] = nil
      local okb, errb = pcall(bring_to_life, world, pl.r, id, pl.player)
      log(string.format("roster: %s set up (%s)", pl.r.name, okb and "ok" or tostring(errb)))
    end
  end
  for name, wt in pairs(waiting) do
    local r = find(name)
    local x, y, z = world:position(wt.player)
    wt.tries = wt.tries + 1
    if not r or wt.tries > 600 then waiting[name] = nil
    elseif x then
      waiting[name] = nil
      local okw, errw = pcall(spawn_body, world, r, x, y + 0.5, z, wt.player)
      if not okw then log("roster: " .. tostring(errw)) end
      roster_save()
    end
  end
  for id, h in pairs(drives) do
    local okd, errd = pcall(drive_step, world, id, h)
    if not okd and not h.err_said then h.err_said = true log("drive " .. tostring(id) .. ": " .. tostring(errd)) end
    if h.shim then pcall(roster.pet_flush, world, id, h) end  -- (pets) the drive's answer to the server probe
  end
  pcall(roster.pet_write)  -- (pets) the drive's inputs for the server probe
  if t % 30 == 7 then pcall(inv.write_labels) end  -- (18:54) the name labels for the C++ part
  pcall(roster.pets_quiet, world)  -- (pets) their own AI kept idle
  for id, h in pairs(drives) do
    if h.go_away then
      local okp, errp = pcall(put_away_for, world, id, h)
      if not okp then log("away: " .. tostring(errp)) drives[id] = nil end
    end
  end
  -- logging: the game's own "ready for gameplay" flag the player's client sends (PlayerInput.fromClientIsReadyForGameplay)
  -- and his TeleportCount, for every player, whenever either changes
  for _, pid in ipairs((function() local ids = {} for _, r in pairs(returning) do ids[#ids + 1] = r.player end
      for _, hh in pairs(drives) do ids[#ids + 1] = hh.player end return ids end)()) do
    local okr, ready = pcall(function() return world:get("PlayerInput", pid).fromClientIsReadyForGameplay end)
    local okc, cnt = pcall(function() return world:get("TeleportCount", pid).counter end)
    -- and the player's own fast travel request (PlayerInput.fromClient.teleportAction)
    local okq, req = pcall(function()
      local ta = world:get("PlayerInput", pid).fromClient.teleportAction
      return string.format("%s/%s/%s", tostring(ta.target), tostring(ta.teleporterType), tostring(ta.versionData))
    end)
    if not okq and not load_err then load_err = true log("load: travel request not readable: " .. tostring(req)) end
    local key = tostring(okr and ready) .. "/" .. tostring(okc and cnt) .. "/" .. tostring(okq and req)
    load_seen = load_seen or {}
    if load_seen[pid] ~= key then
      load_seen[pid] = key
      local x, y, z = world:position(pid)
      log(string.format("load: player %s ready for gameplay %s, teleport count %s, travel request %s, at %s", tostring(pid),
        tostring(okr and ready), tostring(okc and cnt), tostring(okq and req), x and string.format("%.1f %.1f %.1f", x, y, z) or "-"))
    end
  end
  -- back beside the player once he has stood on the ground (not in the air, not swimming) for LAND_TICKS
  for name, rt in pairs(returning) do
    if ent_of[name] then
      returning[name] = nil  -- called back some other way (P, the wheel)
    elseif not world:position(rt.player) then
      -- the player is gone (left the game): the roster brings him back when the player joins
      returning[name] = nil
    else
      local okw, w = pcall(function() return tonumber(world:get("DynamicLocomotion", rt.player).currentWaterState) end)
      -- and his game reports it has loaded (PlayerInput.fromClientIsReadyForGameplay is false from the teleport until
      -- the loading screen is over)
      local okr, ready = pcall(function() return world:get("PlayerInput", rt.player).fromClientIsReadyForGameplay end)
      -- (owner 17:27 "yes": pets swim now) after a "can't follow" he comes back beside a swimming player at once too
      local swimming = okw and (w or 0) > 0.5
      local on_ground = not (okr and ready == false) and ((swimming and rt.why == "can't follow")
        or (not swimming and not player_airborne(world, rt.player)))
      if on_ground then
        rt.ground = rt.ground or t
        if t - rt.ground >= LAND_TICKS then
          returning[name] = nil
          log(string.format("away: %s back beside player %s (%s over)", name, tostring(rt.player), tostring(rt.why)))
          -- (owner 2026-11-20 12:37 "when I teleported I only see N1 again": this called on_call, which brings the
          -- player's MAIN companion, so N1 came twice and N2 not at all) this companion himself comes back beside him
          local r = find(name)
          if r then
            local okc, said = pcall(roster.ui_back, world, r, rt.player)
            log(string.format("away: %s: %s", name, tostring(said)))
            status(world, rt.player, "companion_away", nil)
            status(world, rt.player, "companion_stuck", nil)
            if okc and roster.main[rt.account or ""] == name then
              pcall(function() require("features.chat").notice_to(world, rt.player, "Companion has spawned near you!", "#8cd2ff", 5) end)
            end
          end
        end
      else
        rt.ground = nil
      end
    end
  end
end
