-- features/companions/09_setup.lua: part 9 of the companion code (the server side), split from npc_probe.lua in 0.15.362
-- (owner 2026-11-20 18:11). The parts run in order in ONE shared environment (features/companions.lua): what was a
-- top-level local is a name in that environment, seen by every part.
-- ===== Read-only tools =================================================================================================
function look(world, id)
  local okf, f = pcall(world.get, world, "Faction", id)
  local oka, a = pcall(world.get, world, "DynamicEnemy01BehaviorState", id)
  local x, y, z = world:position(id)
  log(string.format("entity %s at %s: faction %s, AI %s, state %s, offered %s, %s", tostring(id),
    x and string.format("%.1f %.1f %.1f", x, y, z) or "nowhere", okf and f and tostring(f.faction) or "-",
    oka and a and tostring(a.enabled) or "-", oka and a and tostring(a.state) or "-",
    tostring(emf.offered and emf.offered(world, id)), drives[id] and "driven" or "not driven"))
end

hit_watch = {}  -- entity -> true: its hits go into the HIT log too (npc spawnwild adds the body)
function F.setup(k)
  -- every hit a companion gives or takes: amount, health around it, types, attack kind, reaction
  pcall(emf.on_hit, function(world, hit)
    if not hit or hit.kind ~= "hit" then return end
    pcall(note_threat, world, hit)  -- (fight, step 2) watching only
    pcall(note_my_hit, world, hit)
    local mine = false
    for _, e in pairs(ent_of) do if e == hit.attacker or e == hit.source or e == hit.target then mine = true break end end
    if hit_watch[hit.attacker or 0] or hit_watch[hit.target or 0] then mine = true end
    if not mine then return end
    local okl, line = pcall(function()
      return string.format("HIT %s -> %s (source %s, part %s): amount %s, stamina %s, health %s -> %s, types %s, attack %s, "
        .. "blocked %s, parried %s, crit %s, reaction %s, impact %s, program %s, from_mod %s", tostring(hit.attacker),
        tostring(hit.target), tostring(hit.source), tostring(hit.part), tostring(hit.amount), tostring(hit.stamina),
        tostring(hit.health_before), tostring(hit.health_after), table.concat(hit.types or {}, ","),
        table.concat(hit.attacks or {}, ","), tostring(hit.blocked), tostring(hit.parried), tostring(hit.crit),
        tostring(hit.reaction), tostring(hit.impact), tostring(hit.program), tostring(hit.from_mod))
    end)
    log(okl and line or ("HIT: " .. tostring(line)))
  end)
  pcall(emf.on_event, "InteractionAcceptedEvent", function(world, e)  -- (09:21) only the owner opens his chest
    -- (13:57) the game's own E on a pet of ours (an animal): his wheel, as E on a companion
    local host, guest = rawget(e, "hostEntityId"), rawget(e, "guestEntityId")
    if host and guest and roster.pet_mode[host] then  -- (15:06) E after "Pet" in his wheel: the game's petting, no wheel
      log(string.format("pet %s (%s): petting accepted (player %s, offer %s)", tostring(name_of[host]), tostring(host),
        tostring(guest), tostring(rawget(e, "offerId"))))
      roster.pet_mode[host].accepted = roster.pet_mode[host].accepted or world:tick()
    elseif host and guest and name_of[host] and not world:get("DynamicEnemy01BehaviorState", host) then
      log(string.format("pet %s (%s): the game's E pressed by player %s: his wheel", tostring(name_of[host]), tostring(host), tostring(guest)))
      local okt, errt = pcall(on_talk, world, guest, host)
      if not okt then log("pet E: " .. tostring(errt)) end
    end
    if not next(inv.open) then return end
    local oka, erra = pcall(inv.on_accept, world, e)
    if not oka then log("inventory: open check failed: " .. tostring(erra)) end
  end, "server")
  pcall(emf.on_player_joined, function(world, p)
    log(string.format("join: player %s (account %s)%s", tostring(p.player), tostring(p.account), p.host and " (the host)" or ""))
    if p.host and p.account then F.hosts[p.account] = true end  -- (0.15.368) the host of a hosted game is an admin
    pcall(roster.ui_known, world)  -- (roster window) his name kept for when he is offline
    local okr, errr = pcall(roster_joined, world, p)
    if not okr then log("roster: join failed: " .. tostring(errr)) end
  end)
  -- (0.15.368) the channels are core/companion_net's: features/npc_wheel_probe sets the player's end of the same two.
  -- who(): in a game someone hosts, the host's own messages come with the all-zero account (EMF's docs): his real
  -- one is his player's
  local function who(world, from)
    local w = {}
    for k, v in pairs(from or {}) do w[k] = v end
    if (not w.account or tostring(w.account):match("^0x0*$")) and w.player then
      local oka, acc = pcall(world.account, world, w.player)
      if oka and acc then w.account = acc end
    end
    return w
  end
  local net = require("core.companion_net")
  local okc = net.handle(WHEEL, "server", function(world, from, data)
    local okw, errw = pcall(function() return on_pick(world, who(world, from), data) end)
    if not okw then log("wheel: " .. tostring(errw)) end
  end)
  log("wheel channel: " .. tostring(okc))
  -- (owner 2026-11-20 10:00) the Companion Roster window in the players' games: their asks and actions come here
  local okr = net.handle(roster.RCH, "server", function(world, from, data)
    local oku, erru = pcall(function() return roster.ui_do(world, who(world, from), data) end)
    if not oku then log("roster window: " .. tostring(erru)) end
  end)
  log("roster window channel: " .. tostring(okr))
  -- the roster lives in the world's data. (loot_filter registers an empty one only to ask for the data; this one,
  -- registered later, does that too.) TODO for the release: one owner of the world data in FlameKit's core.
  pcall(emf.on_world_data, function(world, text)
    local okl, errl = pcall(roster_loaded, world, text)
    if not okl then log("roster: load failed: " .. tostring(errl)) end
  end)
  emf.log("[flamekit] npc probe: loaded (companion test: flamekit.npc)")
  pcall(F.set_debug, (store.load("companion_debug", {}) or {}).on == true)  -- (18:11) the debug log as last switched
  pcall(emf.command, "npc", "debug on|off | roster ... | drive <npc> <player>|stop | fullrec <entity> [s] | look <entity> | near <x> <y> <z> [r] | remove <entity>: companion test",
    function(world, args)
      local what = args[1]
      if what == "roster" then
        local okc2, errc = pcall(roster_cmd, world, args)
        if not okc2 then log("roster: " .. tostring(errc)) emf.reply("roster: failed") end
      elseif what == "drive" then  -- drive <npc> <player> | drive <npc> stop (he stays where he is)
        local id = tonumber(args[2])
        if args[3] == "stop" then
          drives[id or 0] = nil
          local x, y, z = world:position(id or 0)
          if x then pcall(stay_at, world, id, x, y, z) end
          log("drive " .. tostring(id) .. ": stopped, staying")
        elseif id then
          drives[id] = { player = tonumber(args[3]) or 1, trail = {} }
          log("drive " .. tostring(id) .. ": following player " .. tostring(args[3] or 1))
        end
        emf.reply("npc: drive")
      elseif what == "fullrec" then  -- fullrec <entity> [seconds] | fullrec <entity> stop
        local id = tonumber(args[2])
        if args[3] == "stop" then
          if fullrecs[id or 0] then fullrecs[id].untill = 0 end
        elseif id then
          local okr, err = pcall(fullrec_start, world, id, tonumber(args[3]) or 600)
          if not okr then log("fullrec: " .. tostring(err)) end
        end
        emf.reply("npc: fullrec")
      elseif what == "look" then
        local id = tonumber(args[2])
        if id then look(world, id) end
        emf.reply("npc: logged")
      elseif what == "near" then  -- near <x> <y> <z> [r]: every entity with the monster AI within r m (default 15)
        local x, y, z, r = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]), tonumber(args[5]) or 15
        local n = 0
        for _, id in ipairs(world:entities()) do
          local ex, ey, ez = world:position(id)
          if ex and x and math.abs(ex - x) < r and math.abs(ez - z) < r and math.abs(ey - y) < r then
            local oka, a = pcall(world.get, world, "DynamicEnemy01BehaviorState", id)
            if oka and a then n = n + 1 look(world, id) end
          end
        end
        log(string.format("near: %d with the monster AI", n))
        emf.reply("npc: near")
      elseif what == "spawnwild" then  -- spawnwild <guid> <player> [metres]: a wild body with its own AI, to watch
        local guid, player, m = args[2], tonumber(args[3]) or 1, tonumber(args[4]) or 6
        local x, y, z = world:position(player)
        if not (guid and x) then emf.reply("npc: spawnwild <guid> <player> [metres]") return end
        local ok, id = pcall(emf.spawn, world, guid, x, y + 0.5, z + m)
        if ok and id then hit_watch[id] = true end
        log(string.format("spawnwild %s %.0f m north of %s: %s", guid, m, tostring(player), ok and tostring(id) or ("error: " .. tostring(id))))
        emf.reply("npc: spawnwild " .. tostring(ok and id))
      elseif what == "face" then  -- face <npc> <target> [metres]: the npc put m metres in front of
        -- the target, on the line from the target to where the npc stands, turned to face the target
        local id, tg, m = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 1.5
        local nx, _, nz = world:position(id or 0)
        local tx, ty, tz = world:position(tg or 0)
        if not (nx and tx) then emf.reply("npc: face <npc> <target> [metres]") return end
        local dx, dz = nx - tx, nz - tz
        local d = math.sqrt(dx * dx + dz * dz)
        if d < 0.01 then dx, dz, d = 0, 1, 1 end
        local px, pz = tx + dx / d * m, tz + dz / d * m
        local okt = pcall(emf.teleport, world, id, px, ty, pz, {})
        local yaw = math.atan(tx - px, tz - pz)
        local o = world:get("CurrentTransform", id).transform.orientation
        o.x, o.y, o.z, o.w = 0, math.sin(yaw / 2), 0, math.cos(yaw / 2)
        log(string.format("face: %s put %.1f m from %s at %.1f %.1f %.1f, yaw %.0f deg: %s", tostring(id), m, tostring(tg),
          px, ty, pz, math.deg(yaw), tostring(okt)))
        emf.reply("npc: face")
      elseif what == "level" then  -- level <entity> <level>: the way
        -- experimental.lua's set_level does it: Level.dataStorage[1] and DynamicEnemyScaling.nextUpdateTime = 0, so the
        -- game's own next scaling update rescales health and hits to that level
        local id, lvl = tonumber(args[2]), tonumber(args[3])
        local lv = id and world:get("Level", id)
        if not (lv and lvl) then emf.reply("npc: level <entity> <level>") return end
        lv.dataStorage[1] = lvl
        local sc = world:get("DynamicEnemyScaling", id)
        if sc then
          if type(sc.nextUpdateTime) == "table" then sc.nextUpdateTime.value = 0 else sc.nextUpdateTime = 0 end
        end
        log(string.format("level: %s set to %d (scaling update asked: %s)", tostring(id), lvl, tostring(sc ~= nil)))
        emf.reply("npc: level")
      elseif what == "combat" then  -- combat <npc> <target> [attack]: the combat numbers a wild
        -- hound has while it bites (taken from a full recording), copied as plain values, AI stays off
        local id, tg, ix = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
        local st = id and world:get("DynamicEnemy01BehaviorState", id)
        if not (st and tg) then emf.reply("npc: combat <npc> <target> [attack]") return end
        local cd = st.combatData
        st.state = 6
        cd.state = 3
        cd.selectedAttackIndex = ix
        cd.lastTargetId = tg
        cd.isTargetReachable = true
        cd.isTargetInsideLeash = true
        local gx, _, gz = world:position(tg)
        local nx, _, nz = world:position(id)
        if gx and nx then cd.distanceToTarget = math.sqrt((gx - nx) ^ 2 + (gz - nz) ^ 2) end
        log(string.format("combat: %s state 6, combat state 3, attack %d, target %s", tostring(id), ix, tostring(tg)))
        emf.reply("npc: combat")
      elseif what == "faction" then  -- faction <entity> <n>: EMF combat.md: 7 Player, 11 PlayerAlly,
        -- 1 HitAll, 10 Skeleton. The PvP notes: a monster body with faction 7 did 0 damage, with faction 1 it did damage.
        local id, fn = tonumber(args[2]), tonumber(args[3])
        local f = id and world:get("Faction", id)
        if not (f and fn) then emf.reply("npc: faction <entity> <n>") return end
        f.faction = fn
        log(string.format("faction: %s now %d", tostring(id), fn))
        emf.reply("npc: faction")
      elseif what == "attr" then  -- attr <entity> <Strength|Dexterity|Intelligence> <value>:
        -- dataStorage[1] and [2] (a player has total, base, bonus: Strength 26 11 15)
        local id, comp, v = tonumber(args[2]), args[3], tonumber(args[4])
        local c = id and comp and world:get(comp, id)
        if not (c and v) then emf.reply("npc: attr <entity> <component> <value>") return end
        c.dataStorage[1] = v
        c.dataStorage[2] = v
        log(string.format("attr: %s %s = %s", tostring(id), comp, tostring(v)))
        emf.reply("npc: attr")
      elseif what == "tpground" then  -- tpground <entity> <x> <y> <z>: EMF's teleport with the game's
        -- ground search: does the walkable search answer at this spot, and where does it put the body?
        local id, x, y, z = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]), tonumber(args[5])
        if not (id and x and y and z) then emf.reply("npc: tpground <entity> <x> <y> <z>") return end
        local c0 = os.clock()
        -- the callback must not touch `world` (EMF pauses the whole script for that)
        local okt, res = pcall(emf.teleport, world, id, x, y, z, { ground = true }, function(moved, mx, my, mz)
          log(string.format("tpground %s -> %.1f %.1f %.1f: moved %s to %s %s %s (%.1f s)", tostring(id), x, y, z,
            tostring(moved), tostring(mx and string.format("%.2f", mx)), tostring(my and string.format("%.2f", my)),
            tostring(mz and string.format("%.2f", mz)), os.clock() - c0))
        end)
        log(string.format("tpground %s -> %.1f %.1f %.1f: queued %s", tostring(id), x, y, z, tostring(okt and res)))
        emf.reply("npc: tpground")
      elseif what == "lure" then  -- lure <npc> <x> <y> <z> [seconds]: edge stop test, see drive_lure
        local id, x, y, z, sec = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]), tonumber(args[5]), tonumber(args[6]) or 15
        local h = id and drives[id]
        if not (h and x and y and z) then emf.reply("npc: lure <following npc> <x> <y> <z> [seconds]") return end
        h.lure = { x = x, y = y, z = z, untill = world:tick() + math.floor(sec * 60) }
        log(string.format("lure: %s walks toward %.1f %.1f %.1f for %.0f s", tostring(id), x, y, z, sec))
        emf.reply("npc: lure")
      elseif what == "still" then  -- still <entity>: a test target's monster AI off, so it stands
        -- still and does not go for the player (his reflect kills it)
        local id = tonumber(args[2])
        local st = id and world:get("DynamicEnemy01BehaviorState", id)
        if not st then emf.reply("npc: still <entity>") return end
        st.enabled = false
        log("still: " .. tostring(id) .. " AI off")
        emf.reply("npc: still")
      elseif what == "healfx" then  -- healfx <n>: heal effect candidate n on the nearest player for 10 s (owner 22:09)
        local n = tonumber(args[2])
        local c = n and HEAL_FX[n]
        if not c then emf.reply("npc healfx: 1-" .. #HEAL_FX) return end
        local okp, ids = pcall(players.ids, world)
        local pid = tonumber(args[3]) or (okp and ids and ids[1])  -- (22:17) healfx <n> [entity]: on that body
        if not pid then emf.reply("npc healfx: no player") return end
        local x, y, z = world:position(pid)
        if not x then emf.reply("npc healfx: no player") return end
        local oks, fid = pcall(emf.spawn, world, c[2], x, y, z)
        if oks and fid and fid ~= 0 then
          heal_fx_shown[#heal_fx_shown + 1] = { id = fid, at = world:tick() + 600 }
          log(string.format("heal fx %d (%s) shown on %s as entity %s", n, c[1], tostring(pid), tostring(fid)))
          emf.reply("healfx " .. n .. ": " .. c[1])
        else
          log(string.format("heal fx %d (%s) refused (%s)", n, c[1], tostring(fid)))
          emf.reply("healfx " .. n .. ": refused")
        end
      elseif what == "unlock" then  -- unlock <chest> <item> <n>: (08:57) puts the upgrades back on a piece in a chest
        local ch, item, n = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
        local rr = not ch and args[2] and find(args[2])
        if rr and item and n then  -- unlock <companion> <item> <n>: in his record (put back at the next opening)
          for _, e in ipairs(rr.inv or {}) do
            if e.item == item and e.level then
              e.unlocked = math.floor(n)
              roster_save()
              log(string.format("unlock: %s's record: item %s level %s now %d unlocked", rr.name, tostring(item), tostring(e.level), e.unlocked))
              emf.reply("npc: unlock set in the record")
              return
            end
          end
          emf.reply("npc: unlock: no such gear in his record")
          return
        end
        if not (ch and item and n) then emf.reply("npc: unlock <chest>|<companion> <item> <n>") return end
        local c = { chest = ch, fix = { { item = item, unlocked = math.floor(n) } } }
        inv.apply_unlocked(world, "command", c)
        emf.reply("npc: unlock done (see the log)")
      elseif what == "debug" then  -- debug on|off: (owner 18:11) the companion debug log (F.debug, companion_debug.txt)
        if args[2] == "on" or args[2] == "off" then F.set_debug(args[2] == "on") end
        emf.reply("npc: companion debug log " .. (F.debug and "on" or "off"))
      elseif what == "petlog" then  -- petlog <entity> [seconds]: (pets, 12:48) what an animal's own AI does, twice a second
        local id, sec = tonumber(args[2]), tonumber(args[3]) or 30
        if not id then emf.reply("npc: petlog <entity> [seconds]") return end
        roster.petlog = { id = id, untill = world:tick() + math.floor(sec * 60) }
        emf.reply("npc: petlog " .. id .. " for " .. sec .. " s")
      elseif what == "names" then  -- names [copy <from> <to> | set <entity> <id>]: the game's own floating names
        -- (CustomPlayerString.stringId, the key of a name players gave a chest or altar; owner 08:41 "research the
        -- first point and see what it looks like?") lists every entity with one, or copies one onto another
        local function key_of(id)
          local ok, c = pcall(world.get, world, "CustomPlayerString", id)
          if not ok or not c then return nil end
          local k = c.stringId
          if type(k) ~= "number" then k = k.value end  -- (a HashKey64 may read as a number or as {value})
          return k
        end
        local function hex(v)
          if v == nil then return "none" end
          if math.type(v) == "integer" then return string.format("0x%016X", v) end
          return string.format("%.0f (float)", v)
        end
        if args[2] == "spawn" then  -- (08:47: our spawned chest has no CustomPlayerString, emf.add_component only
          -- takes 2 kinds, emf.spawn takes any) spawn <from>: a test chest 2 m from the player with <from>'s name key, 60 s
          local v = key_of(tonumber(args[3]) or 0)
          local okp, ids = pcall(players.ids, world)
          local pid = okp and ids and ids[1]
          local x, y, z
          if pid then x, y, z = world:position(pid) end
          if not (v and x) then emf.reply("npc names: spawn <entity with a name> (near a player)") return end
          local ok, fid = pcall(emf.spawn, world, inv.CHEST, x + 2, y, z, { CustomPlayerString = { stringId = v } })
          if not ok then ok, fid = pcall(emf.spawn, world, inv.CHEST, x + 2, y, z, { CustomPlayerString = { stringId = { value = v } } }) end
          if ok and fid and fid ~= 0 then
            heal_fx_shown[#heal_fx_shown + 1] = { id = fid, at = world:tick() + 3600 }
            log(string.format("names: test chest %s spawned with %s's key %s (reads %s), gone in 60 s", tostring(fid), args[3], hex(v), hex(key_of(fid))))
            emf.reply("npc names: test chest " .. tostring(fid))
          else
            log("names: test chest refused: " .. tostring(fid))
            emf.reply("npc names: refused")
          end
        elseif args[2] == "copy" or args[2] == "set" then
          local from, to = tonumber(args[3]), tonumber(args[4])
          local v = args[2] == "copy" and from and key_of(from) or (args[2] == "set" and math.tointeger(tonumber(args[4])))
          if args[2] == "set" then to = from end
          local c = to and world:get("CustomPlayerString", to)
          if not (v and c) then emf.reply("npc names: copy <from> <to> | set <entity> <number> (both need the component)") return end
          local was = key_of(to)
          if type(c.stringId) == "number" then c.stringId = v else c.stringId.value = v end
          log(string.format("names: %s stringId %s -> %s (now reads %s)", tostring(to), hex(was), hex(v), hex(key_of(to))))
          emf.reply("npc names: set")
        else
          local px, py, pz
          pcall(function() local ids = players.ids(world) px, py, pz = world:position(ids[1]) end)
          local n, named = 0, 0
          for _, id in ipairs(world:entities()) do
            local v = key_of(id)
            if v ~= nil then
              n = n + 1
              local x, y, z = world:position(id)
              local d = (px and x) and math.sqrt((x - px) ^ 2 + (y - py) ^ 2 + (z - pz) ^ 2) or -1
              if v ~= 0 or d >= 0 and d < 30 then
                if v ~= 0 then named = named + 1 end
                local okm, m = pcall(function() return world:template("ModelResource", id).model end)
                log(string.format("names: %s key %s at %.0f m (model %s)", tostring(id), hex(v), d, okm and tostring(m) or "?"))
              end
            end
          end
          log(string.format("names: %d entities have the component, %d with a name key", n, named))
          emf.reply(string.format("npc names: %d / %d", named, n))
        end
      elseif what == "hold" then  -- hold <npc> <target> [seconds]: stays put and faces the target (drive_hold)
        local id, tg, sec = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 10
        if not (id and tg) then emf.reply("npc: hold <npc> <target> [seconds]") return end
        holds[id] = { target = tg, untill = world:tick() + math.floor(sec * 60) }
        log(string.format("hold: %s holds and faces %s for %.0f s", tostring(id), tostring(tg), sec))
        emf.reply("npc: hold")
      elseif what == "atk" then  -- atk <entity> <index>: combatData.selectedAttackIndex, the number
        -- the monster AI keeps for the attack it is doing (wild hound: 0 bite, 1 lunge; ours: 255 = none). Only a value.
        local id, ix = tonumber(args[2]), tonumber(args[3])
        local st = id and world:get("DynamicEnemy01BehaviorState", id)
        if not (st and ix) then emf.reply("npc: atk <entity> <index>") return end
        st.combatData.selectedAttackIndex = ix
        log(string.format("atk: %s selectedAttackIndex = %d", tostring(id), ix))
        emf.reply("npc: atk")
      elseif what == "remove" then
        local id = tonumber(args[2])
        drives[id or 0] = nil
        local ok, res = pcall(emf.destroy, world, id)
        log(string.format("remove %s: %s", tostring(id), tostring(ok and res)))
        emf.reply("npc: removed " .. tostring(ok and res))
      else
        emf.reply("npc: roster ... | drive <npc> <player>|stop | fullrec <entity> [s] | look <entity> | near <x> <y> <z> [r] | remove <entity>")
      end
    end)
end

dead_told = {}  -- entity -> true: "Companion has died!" sent once per body
-- put away by the glider, a fast travel or can't follow: name -> { player, account, why, ground }
returning = {}
load_seen = nil  -- player -> "ready/teleport count" last logged
load_err = nil   -- the travel request read failed once (logged)
