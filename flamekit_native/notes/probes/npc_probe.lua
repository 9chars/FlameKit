-- npc_probe.lua (2026-11-17, owner: "spawn a villager-looking character that has no prompt of its own and add my own
-- prompts in it"): a test feature. Not loaded by FlameKit: see README.md here (local server only, never published).
--
-- Console (or emf\commands.txt on the server):
--   flamekit.npc spawn <player entity> [m1|m2|m3|f1|f2|f3|fp|fr]   one of the game's unused test villagers, 4 m in front
--   flamekit.npc offer <npc entity>                           put FlameKit's "E Talk" on it (tried again by itself)
--   flamekit.npc look <npc entity>                            log its parts: prompt, villager state, faction
--   flamekit.npc stay <npc entity>                            hold him where he stands (again: free)
--   flamekit.npc here <npc entity> <player entity>            move him next to the player and hold him there
--   flamekit.npc remove <npc entity>                          take it out of the world again
--   flamekit.npc bot <player> [ap|pv|p1] / walk <bot> <seconds> [yaw] [direct] / botlook <bot>   a player-type body fed input
-- Logs "npc probe: ..." in emf\emf_core.log. Villager templates are saved with the world (ForceSave): remove the test
-- villager afterwards.

local F = { id = "npc_probe", title = "NPC Probe" }

local TEMPLATES = {  -- claude_scratch\tpl\templates.csv (faction 7, npc)
  m1 = { "test_Townsfolk_Male_01", "8bd1dac4-91a5-4287-93c1-7481a4211fce" },
  m2 = { "test_Townsfolk_Male_02", "5a6266dc-0339-445a-8f96-53b446a96533" },
  m3 = { "test_Townsfolk_Male_03", "2a8818f4-2a65-41de-9538-808a426110db" },
  f1 = { "test_Townsfolk_Female_01", "e413c5e8-5555-45fe-a776-3075d7081cbd" },
  f2 = { "test_Townsfolk_Female_02", "cffcaf28-142b-47bb-b385-647fece4f984" },
  f3 = { "test_Townsfolk_Female_03", "2a1de535-c633-439c-abbb-78b31f4ca6c1" },
  -- (owner: "can't we just use one of the models the player use") the game's player-like bodies, faction 7 (Player)
  fp = { "FakePlayer_Vukah_Melee", "9543cfb0-b4d7-408e-905c-ccb79a15136d" },
  fr = { "FakePlayer_Scavenger_Ranger", "4227fee0-b8e6-4518-9dc6-358472b3957b" },
}
local PARTS = { "InteractionOfferRuntime", "ClientInteractionOffer", "DynamicActiveNpcState", "Faction", "NpcCommon",
  "DynamicEnemy01BehaviorState", "Health", "MovementCollider", "DynamicLocomotion", "PlayerInput", "InventorySetup",
  "Equipment", "DynamicAggro" }

-- (owner: "connect a fake player to the server and feed it data like a real player would do") player-type bodies:
-- they have PlayerInput instead of monster AI; FlameKit writes that input every step as a player's game would
local BOTS = {
  ap = { "AutomatedPlayer", "454b15fd-5839-44d4-9dec-bd2e9156d9e8" },
  pv = { "Player_Vukah_Melee", "44604a7b-946b-4727-bb72-8c0eb3c08fa1" },
  p1 = { "1_Player", "c3db66d6-89a5-4a6c-a8e3-d9a1f6009812" },
}
local bots = {}      -- bot entity -> { stick = forward 0..1, yaw = degrees, walk_until = tick, said = n }
local pending = {}   -- npc entity -> { tries, next_tick }
local function log(s) emf.log("npc probe: " .. s) end

-- (owner, 2026-11-17: "probing everything my character does ... from the moment I connect into the server to when I
-- appear and move") the join recorder: "flamekit.npc arm [seconds]" starts it. Every quarter second it compares the
-- world's entity list with the last one and logs every new and every gone entity with the parts it has (from KEYS),
-- and every player entity's state; for each player it logs which of KEYS appear and when.
local KEYS = { "Actor", "PlayerInput", "PlayerState", "CharacterSetup", "NewCharacterSetup", "Equipment", "Inventory",
  "InventorySetup", "CurrentTransform", "DynamicLocomotion", "MovementCollider", "Health", "Faction", "PlayerSkillsUi",
  "UnlockedSkillNodes", "ServerConsumedPlayerInput", "ServerCursor", "DynamicPathWalker", "SteeringLocomotion",
  "PlayerWaypoint", "ModelResource", "SlotSelection", "DynamicActiveNpcState", "DynamicEnemy01BehaviorState",
  "Level", "Experience", "BuffContainer", "DoNotSave", "ForceSave", "OwnerRelationship", "SpawnedByLogicSystem",
  "Teleport", "ClientInteractionOffer", "InteractionOfferRuntime", "DynamicSafePlayerPosition", "PlayerSpawnPoint" }
local join = nil   -- { until_tick, next, known = {[id]=true}, players = {[id]={parts}} }
local function parts_of(world, id)
  local have = {}
  for _, c in ipairs(KEYS) do
    local ok, v = pcall(world.get, world, c, id)
    if ok and v ~= nil then have[#have + 1] = c end
  end
  return have
end
local function join_tick(world, t)
  if not join or t < join.next then return end
  if t > join.until_tick then log("join recorder: stopped") join = nil return end
  join.next = t + 15
  local list = world:entities()
  local now = {}
  local fresh, shown = 0, 0
  for _, id in ipairs(list) do
    now[id] = true
    if not join.known[id] then fresh = fresh + 1 end
    -- (the world streams in thousands of entities around a joining player: only the first 40 a check, 1500 in all,
    -- are logged one by one; the count always)
    if not join.known[id] and shown < 40 and join.lines < 1500 then
      shown, join.lines = shown + 1, join.lines + 1
      local x, y, z = world:position(id)
      local oka, acc = pcall(world.account, world, id)
      log(string.format("join: NEW entity %s%s at %s: [%s]", tostring(id), oka and acc and (" (account " .. tostring(acc) .. ")") or "",
        x and string.format("%.1f %.1f %.1f", x, y, z) or "no position", table.concat(parts_of(world, id), ", ")))
    end
  end
  local gone = 0
  for id in pairs(join.known) do
    if not now[id] then
      gone = gone + 1
      if gone <= 20 then log("join: GONE entity " .. tostring(id)) end
    end
  end
  if fresh > 0 or gone > 0 then log(string.format("join: %d new, %d gone (%d entities)", fresh, gone, #list)) end
  join.known = now
  -- every player entity: which KEYS it has now, and its state, when it changed
  for _, id in ipairs(list) do
    local oka, acc = pcall(world.account, world, id)
    if oka and acc then
      local p = parts_of(world, id)
      local line = table.concat(p, ",")
      local st = ""
      pcall(function()
        local a = world:get("Actor", id)
        local inp = world:get("PlayerInput", id)
        local cs = a and math.tointeger(a.currentState) or 0
        st = string.format("ready bit %d, ready flag %s, state bits %x", (cs >> 50) & 1, tostring(inp and inp.fromClientIsReadyForGameplay), cs)
      end)
      local key = line .. "|" .. st
      if join.players[id] ~= key then
        join.players[id] = key
        local x, y, z = world:position(id)
        log(string.format("join: player %s (%s) at %s: %s; parts [%s]", tostring(id), tostring(acc),
          x and string.format("%.1f %.1f %.1f", x, y, z) or "no position", st, line))
      end
    end
  end
end
local recs = {}      -- entity -> { untill, next } (owner walking, to copy what a real player's game sends)
local function rec_line(world, id)
  local okr, errr = pcall(function()
    local inp = world:get("PlayerInput", id)
    local a = world:get("ActorInput", id)
    local c = inp and inp.fromClient
    local q = c and c.camera.orientation
    local cri = c and c.cameraRotationInput
    log(string.format("rec %s: stick %s mode %s mask %s buttons %s cam %s campos %s dist %s | inputmode %s toggles %s dbl %s | move world %s local %s speed %s last %s",
      tostring(id),
      c and string.format("%.2f %.2f", tonumber(c.movementStick.x) or 0, tonumber(c.movementStick.y) or 0) or "-",
      tostring(c and c.movementStickInputMode), tostring(c and c.mask), tostring(c and c.digitalInput),
      q and string.format("%.2f %.2f %.2f %.2f", tonumber(q.x) or 0, tonumber(q.y) or 0, tonumber(q.z) or 0, tonumber(q.w) or 0) or "-",
      "-", c and tostring(c.camera.distance) or "-",
      tostring(inp and inp.fromClientInputMode), "-", tostring(inp and inp.fromClientDoubleInputBindings),
      a and string.format("%.2f %.2f %.2f", tonumber(a.desiredWorldMoveInput.x) or 0, tonumber(a.desiredWorldMoveInput.y) or 0, tonumber(a.desiredWorldMoveInput.z) or 0) or "-",
      a and string.format("%.2f %.2f %.2f", tonumber(a.desiredLocalMoveInput.x) or 0, tonumber(a.desiredLocalMoveInput.y) or 0, tonumber(a.desiredLocalMoveInput.z) or 0) or "-",
      tostring(a and a.locomotionSpeed), tostring(a and a.lastLocomotionSpeed)))
  end)
  if not okr then log("rec failed: " .. tostring(errr)) end
end
local stays = {}     -- npc entity -> { x, y, z, moved = count of put-backs } (owner: "can you make him stop moving around")
local said = {}

local function look(world, id)
  local have = {}
  for _, c in ipairs(PARTS) do
    local ok, v = pcall(world.get, world, c, id)
    if ok and v ~= nil then have[#have + 1] = c end
  end
  local okf, f = pcall(world.get, world, "Faction", id)
  local x, y, z = world:position(id)
  log(string.format("entity %s at %s: parts [%s], faction %s, offered %s", tostring(id),
    x and string.format("%.1f %.1f %.1f", x, y, z) or "nowhere", table.concat(have, ", "),
    okf and f and tostring(f.faction) or "-", tostring(emf.offered and emf.offered(world, id))))
end

local following = {}  -- npc entity -> player entity it follows

local function say(world, player, text)
  pcall(function() require("features.chat").notice_to(world, player, text, "#8cd2ff", 5) end)
end

-- the game's own guard order (StartGuardingEvent / StopGuardingEvent {timeStamp, guardingEntityId, guardedEntityId});
-- the server's main.lua must declare them at the start (emf.emits): a server restart the first time
local function guard(world, npc, player, start)
  local name = start and "StartGuardingEvent" or "StopGuardingEvent"
  local ok, res = pcall(emf.emit, "server", name, { guardingEntityId = npc, guardedEntityId = player })
  log(string.format("%s %s -> %s: %s", name, tostring(npc), tostring(player), ok and tostring(res) or ("error: " .. tostring(res))))
  return ok and res ~= false
end

-- (owner: "he's still walking in place" while held by force) staying = guarding a still marker at his spot: the
-- game's own guard behaviour stands him there with its own idle animation, nothing forced. The marker is an
-- invisible effect entity (Base_VFX_Dummy). Without a marker: held by force as before.
local MARKER = "bd93835e-5dd8-481c-9457-7ad5f3f516f9"
local markers = {}   -- npc entity -> marker entity
local function drop_marker(world, id)
  if markers[id] then pcall(emf.destroy, world, markers[id]) markers[id] = nil end
end
local function stay_here(world, id)
  local x, y, z = world:position(id)
  if not x then return end
  drop_marker(world, id)
  local ok, m = pcall(emf.spawn, world, MARKER, x, y, z)
  if ok and m and m ~= 0 then
    markers[id] = m
    local okg, res = pcall(emf.emit, "server", "StartGuardingEvent", { guardingEntityId = id, guardedEntityId = m })
    log(string.format("stay: %s guards marker %s: %s", tostring(id), tostring(m), okg and tostring(res) or tostring(res)))
    if okg then stays[id] = nil return end
  end
  log("stay: no marker (" .. tostring(m) .. "): held by force")
  stays[id] = { x = x, y = y, z = z, moved = 0 }
end

-- (owner: "yes follow me and stay options") E switches between following the player who pressed it and staying put
local function on_talk(world, player, npc)
  log(string.format("E pressed on %s by player %s (now %s)", tostring(npc), tostring(player),
    following[npc] and "following" or "staying"))
  if following[npc] then
    guard(world, npc, following[npc], false)
    following[npc] = nil
    stay_here(world, npc)
    say(world, player, "Staying here.")
  else
    stays[npc] = nil
    drop_marker(world, npc)
    if guard(world, npc, player, true) then
      following[npc] = player
      say(world, player, "Following you.")
    else
      stay_here(world, npc)
      say(world, player, "Cannot follow (see the server's log).")
    end
  end
end

local function try_offer(world, id)
  local ok, res = pcall(emf.offer, world, id, { verb = "Talk" }, on_talk)
  log(string.format("offer on %s: %s", tostring(id), ok and tostring(res) or ("error: " .. tostring(res))))
  return ok and res == true
end

function F.setup(k)
  pcall(emf.on_player_joined, function(world, p)
    log(string.format("join: EVENT player joined: entity %s, account %s", tostring(p.player), tostring(p.account)))
  end)
  pcall(emf.on_player_left, function(world, p)
    log(string.format("join: EVENT player left: entity %s", tostring(p.player)))
  end)
  emf.log("[flamekit] npc probe: loaded (test villager commands: flamekit.npc)")
  pcall(emf.command, "npc", "spawn <player> [m1..m3|f1..f3|fp|fr] | offer <npc> | look <npc> | stay <npc> | remove <npc>: NPC probe (test)",
    function(world, args)
      local what = args[1]
      if what == "spawn" then
        local player = tonumber(args[2])
        local t = TEMPLATES[args[3] or "m2"]
        if not player or not t then emf.reply("npc: spawn <player entity> [m1|m2|m3|f1|f2|f3|fp|fr]") return end
        local x, y, z = world:position(player)
        if not x then emf.reply("npc: no player " .. tostring(player)) return end
        local ok, id = pcall(emf.spawn, world, t[2], x + 4, y + 0.5, z)
        log(string.format("spawn %s near player %s: %s", t[1], tostring(player), ok and tostring(id) or ("error: " .. tostring(id))))
        if ok and id then
          pending[id] = { tries = 0, next_tick = world:tick() + 60 }
          stays[id] = { x = x + 4, y = y + 0.5, z = z, moved = 0 }  -- (owner: "stop moving around") stays at first
        end
        emf.reply("npc: spawned " .. tostring(ok and id))
      elseif what == "offer" then
        local id = tonumber(args[2])
        if id then try_offer(world, id) end
        emf.reply("npc: offer tried")
      elseif what == "look" then
        local id = tonumber(args[2])
        if id then look(world, id) end
        emf.reply("npc: logged")
      elseif what == "stay" then  -- stay <npc>: held where he stands now; again: free
        local id = tonumber(args[2])
        if id and stays[id] then
          stays[id] = nil
          log("stay off for " .. tostring(id))
          emf.reply("npc: free again")
        elseif id then
          stay_here(world, id)
          log("stay on for " .. tostring(id))
          emf.reply("npc: holding " .. tostring(id))
        end
      elseif what == "here" then  -- here <npc> <player>: moved next to the player (1.5 m), then held there
        local id, player = tonumber(args[2]), tonumber(args[3])
        local x, y, z = world:position(player or 0)
        if not (id and x) then emf.reply("npc: here <npc entity> <player entity>") return end
        stays[id] = { x = x + 1.5, y = y, z = z, moved = 0, busy = true }
        local ok = pcall(emf.teleport, world, id, x + 1.5, y, z, { ground = true }, function(moved, nx, ny, nz, info, w)  -- the teleport's own world (the command's world is gone by then)
          stays[id] = nil
          if nx and w then stay_here(w, id) end
          log(string.format("here: %s moved %s, now at %s", tostring(id), tostring(moved),
            nx and string.format("%.1f %.1f %.1f", nx, ny, nz) or "?"))
        end)
        emf.reply("npc: moving " .. tostring(ok))
      elseif what == "bot" then  -- bot <player> [ap|pv|p1]: a player-type body, 2 m from the player, fed input by FlameKit
        local player = tonumber(args[2])
        local t = BOTS[args[3] or "ap"]
        local x, y, z = world:position(player or 0)
        if not (t and x) then emf.reply("npc: bot <player entity> [ap|pv|p1]") return end
        local ok, id = pcall(emf.spawn, world, t[2], x + 2, y + 0.5, z)
        log(string.format("bot %s near player %s: %s", t[1], tostring(player), ok and tostring(id) or ("error: " .. tostring(id))))
        if ok and id and id ~= 0 then bots[id] = { stick = 0, yaw = 0, said = 0, owner = player } end
        emf.reply("npc: bot " .. tostring(ok and id))
      elseif what == "walk" then  -- walk <bot> <seconds> [yaw degrees]: push its stick forward for that long
        local id, secs = tonumber(args[2]), tonumber(args[3]) or 3
        local b = id and bots[id]
        if not b then emf.reply("npc: no bot " .. tostring(id)) return end
        b.yaw = tonumber(args[4]) or b.yaw
        b.direct = args[5] == "direct" or args[5] == "move"  -- also write the move wish (ActorInput)
        -- (owner: "why can't we do the calculations and feed whatever the server needs?") "move": FlameKit moves the
        -- body itself (CurrentTransform, at b.mps metres a second, facing the walk), as a player's game would report it
        b.manual = args[5] == "move"
        b.mps = tonumber(args[6]) or b.mps or 4
        b.stick, b.walk_until = 1, world:tick() + math.floor(secs * 60)
        log(string.format("walk: bot %s forward for %.1f s, facing %d", tostring(id), secs, b.yaw))
        emf.reply("npc: walking")
      elseif what == "place" then  -- place <bot> <player> [metres]: written next to the player (no teleport)
        local id, player, d = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 3
        local okp, ptr = pcall(world.get, world, "CurrentTransform", player or 0)
        local okb, btr = pcall(world.get, world, "CurrentTransform", id or 0)
        if okp and ptr and okb and btr then
          local bp, pp = btr.transform.position, ptr.transform.position
          if args[5] == "north" then  -- (owner: "north of me would be a better direction"; z is north)
            bp.x, bp.y, bp.z = pp.x, pp.y + math.floor(0.5 * 2 ^ 32), pp.z + math.floor(d * 2 ^ 32)
          else
            bp.x, bp.y, bp.z = pp.x + math.floor(d * 2 ^ 32), pp.y, pp.z
          end
          log(string.format("place: %s next to %s (%.1f m)", tostring(id), tostring(player), d))
        end
        emf.reply("npc: placed")
      elseif what == "appear" then  -- appear <entity>: its Hide and CharacterSetup (how a player body is drawn), read only
        local id = tonumber(args[2])
        local ok, err = pcall(function()
          local h = world:get("Hide", id)
          local c = world:get("CharacterSetup", id)
          log(string.format("appear %s: Hide hidden %s locally %s | CharacterSetup gender %s voice %s preset %s hair %s beard %s haircol %s beardcol %s skin %s brow %s eye %s newprop %s",
            tostring(id), tostring(h and h.isHidden), tostring(h and h.isLocallyHidden),
            tostring(c and c.gender), tostring(c and c.voicePackId), tostring(c and c.presetId), tostring(c and c.hair),
            tostring(c and c.beard), tostring(c and c.hairColorId), tostring(c and c.beardColorId), tostring(c and c.skinColor),
            tostring(c and c.eyeBrowColor), tostring(c and c.eyeColor), tostring(c and c.useNewProportions)))
        end)
        if not ok then log("appear failed: " .. tostring(err)) end
        emf.reply("npc: logged")
      elseif what == "copylook" then  -- copylook <from> <to>: CharacterSetup copied field by field (write test)
        local from, to = tonumber(args[2]), tonumber(args[3])
        local ok, err = pcall(function()
          local a, b = world:get("CharacterSetup", from), world:get("CharacterSetup", to)
          for _, f in ipairs({ "gender", "voicePackId", "presetId", "hair", "beard", "hairColorId", "beardColorId",
                               "skinColor", "eyeBrowColor", "eyeColor", "useNewProportions" }) do
            b[f] = a[f]
          end
        end)
        log(string.format("copylook %s -> %s: %s", tostring(from), tostring(to), ok and "copied" or ("failed: " .. tostring(err))))
        emf.reply("npc: copylook " .. tostring(ok))
      elseif what == "spawnat" then  -- spawnat <guid> <player> [metres north]: an ordinary spawn of any template
        local guid, player, d = args[2], tonumber(args[3]) or 1, tonumber(args[4]) or 2
        local x, y, z = world:position(player)
        if not (guid and x) then emf.reply("npc: spawnat <guid> <player> [metres north]") return end
        local ok, id = pcall(emf.spawn, world, guid, x, y + 0.2, z + d)
        log(string.format("spawnat %s %.1f m north of %s: %s", guid, d, tostring(player), ok and tostring(id) or ("error: " .. tostring(id))))
        emf.reply("npc: spawned " .. tostring(ok and id))
      elseif what == "tpl" then  -- tpl <entity> <component>: the template half of a component, field by field (read only)
        local id, comp = tonumber(args[2]), args[3]
        local ok, t = pcall(world.template, world, comp, id)
        if not ok or t == nil then log(string.format("tpl %s %s: %s", tostring(id), tostring(comp), ok and "none" or tostring(t)))
        else
          log(string.format("tpl %s %s: found (a proxy: read its fields by name; the console's tpl dumps bytes)", tostring(id), comp))
        end
        emf.reply("npc: logged")
      elseif what == "adopt" then  -- adopt <bot>: feed an existing player-type body again (after a reload)
        local id = tonumber(args[2])
        if id then bots[id] = { stick = 0, yaw = 0, said = 0, owner = tonumber(args[3]) or 1 } end
        log("adopt: " .. tostring(id))
        emf.reply("npc: adopted " .. tostring(id))
      elseif what == "botlook" then
        local id = tonumber(args[2])
        pcall(function()
          local a = world:get("Actor", id)
          local m = world:get("DynamicLocomotion", id)
          local inp = world:get("PlayerInput", id)
          local cs = a and math.tointeger(a.currentState) or 0
          local x, y, z = world:position(id)
          local q = inp and inp.fromClient.camera.orientation
          log(string.format("bot %s at %s: ready bit %s, movement state %s, ready flag %s, stick %s, mask %s, stick mode %s, input mode %s, server time %s, buttons %s, camera %s",
            tostring(id), x and string.format("%.1f %.1f %.1f", x, y, z) or "nowhere", tostring((cs >> 50) & 1),
            tostring(m and m.state), tostring(inp and inp.fromClientIsReadyForGameplay),
            inp and string.format("%.2f %.2f", tonumber(inp.fromClient.movementStick.x) or 0, tonumber(inp.fromClient.movementStick.y) or 0) or "-",
            tostring(inp and inp.fromClient.mask), tostring(inp and inp.fromClient.movementStickInputMode),
            tostring(inp and inp.fromClientInputMode), tostring(inp and inp.serverTime), tostring(inp and inp.fromClient.digitalInput),
            q and string.format("%.2f %.2f %.2f %.2f", tonumber(q.x) or 0, tonumber(q.y) or 0, tonumber(q.z) or 0, tonumber(q.w) or 0) or "-"))
          local ai = world:get("ActorInput", id)
          local have = {}
          for _, c in ipairs({ "ActorInput", "PlayerState", "ServerConsumedPlayerInput", "MovementCollider", "DynamicLocomotion",
                               "Velocity", "ServerCursor", "PlayerSkillsUi", "Equipment", "InventorySetup" }) do
            local okc, v = pcall(world.get, world, c, id)
            if okc and v ~= nil then have[#have + 1] = c end
          end
          log(string.format("bot %s: ActorInput world move %s, local move %s, speed %s | parts [%s]", tostring(id),
            ai and string.format("%.2f %.2f %.2f", tonumber(ai.desiredWorldMoveInput.x) or 0, tonumber(ai.desiredWorldMoveInput.y) or 0, tonumber(ai.desiredWorldMoveInput.z) or 0) or "-",
            ai and string.format("%.2f %.2f %.2f", tonumber(ai.desiredLocalMoveInput.x) or 0, tonumber(ai.desiredLocalMoveInput.y) or 0, tonumber(ai.desiredLocalMoveInput.z) or 0) or "-",
            tostring(ai and ai.locomotionSpeed), table.concat(have, ", ")))
        end)
        emf.reply("npc: logged")
      elseif what == "arm" then  -- arm [seconds]: the join recorder
        local secs = tonumber(args[2]) or 180
        join = { until_tick = world:tick() + secs * 60, next = 0, known = {}, players = {}, lines = 0 }
        for _, id in ipairs(world:entities()) do join.known[id] = true end
        log(string.format("join recorder: armed for %d s (%d entities now)", secs, #world:entities()))
        emf.reply("npc: join recorder armed")
      elseif what == "rec" then  -- rec <entity> <seconds>: its input and move wish, 4 times a second
        local id, secs = tonumber(args[2]), tonumber(args[3]) or 10
        if id then recs[id] = { untill = world:tick() + math.floor(secs * 60), next = 0 } end
        log(string.format("rec: %s for %.0f s", tostring(id), secs))
        emf.reply("npc: recording")
      elseif what == "remove" then
        local id = tonumber(args[2])
        local ok, res = pcall(emf.destroy, world, id)
        log(string.format("remove %s: %s", tostring(id), tostring(ok and res)))
        pending[id or 0], stays[id or 0], following[id or 0], bots[id or 0] = nil, nil, nil, nil
        drop_marker(world, id or 0)
        emf.reply("npc: removed " .. tostring(ok and res))
      else
        emf.reply("npc: spawn <player> [m1..m3|f1..f3|fp|fr] | offer <npc> | look <npc> | remove <npc>")
      end
    end)
end

-- a spawned villager: looked at after 1 s, then FlameKit's offer tried once a second, 10 times at most
-- a held NPC: his speed is set to 0 every step (Velocity), and when he still got more than 1 m away he is put back
-- (emf.teleport, as fast travel moves a creature); the first put-backs are logged
local function hold(world, id, h)
  pcall(function()
    local v = world:get("Velocity", id)
    if v then v.velocity.x, v.velocity.z = 0, 0 end
  end)
  -- (owner: "he's walking in place") his AI still asks to walk: the wish to move and the walking speed are taken
  -- away too (ActorInput: desiredLocalMoveInput, desiredWorldMoveInput, locomotionSpeed 0 = standing)
  if not h.input_broken then
    local ok, err = pcall(function()
      local a = world:get("ActorInput", id)
      if not a then return end
      a.desiredLocalMoveInput.x, a.desiredLocalMoveInput.y, a.desiredLocalMoveInput.z = 0, 0, 0
      a.desiredWorldMoveInput.x, a.desiredWorldMoveInput.y, a.desiredWorldMoveInput.z = 0, 0, 0
      a.locomotionSpeed = 0
    end)
    if not ok then
      h.input_broken = true
      log("stay: his input cannot be changed (" .. tostring(err) .. ")")
    end
  end
  local x, y, z = world:position(id)
  if not x then return end
  if (x - h.x) ^ 2 + (z - h.z) ^ 2 > 1 and not h.busy then
    h.busy = true
    h.moved = h.moved + 1
    if h.moved <= 5 then log(string.format("stay: %s had moved %.1f m: put back", tostring(id), math.sqrt((x - h.x) ^ 2 + (z - h.z) ^ 2))) end
    local ok = pcall(emf.teleport, world, id, h.x, h.y, h.z, {}, function() h.busy = nil end)
    if not ok then h.busy = nil end
  end
end

-- a bot's input, every step: "ready for gameplay", the stick, the camera's direction (the stick is read relative to it)
local function feed(world, id, b, t)
  if b.walk_until and t >= b.walk_until then b.stick, b.walk_until = 0, nil log("walk: bot " .. tostring(id) .. " stops") end
  local ok, err = pcall(function()
    local inp = world:get("PlayerInput", id)
    if not inp then error("no PlayerInput") end
    inp.fromClientIsReadyForGameplay = true
    inp.fromClient.movementStick.x, inp.fromClient.movementStick.y = 0, b.stick
    inp.fromClient.mask = 256  -- (a real player's game sends 256: measured on player 1, 2026-11-17)
    -- a real player's input carries the server time it arrived at (the bot's stayed 0): the owner's is copied
    local okp, pi = pcall(world.get, world, "PlayerInput", b.owner or 1)
    if okp and pi then
      inp.serverTime = pi.serverTime
      -- (2026-11-17, the owner walking: his input differs from the bot's only in the camera's other values and the
      -- double-input bindings 8) the rest of the owner's camera is copied (the bot's had distance, fov and planes 0)
      local cs, cd = pi.fromClient.camera, inp.fromClient.camera
      cd.distance, cd.fovY, cd.aspectRatio, cd.nearPlane, cd.farPlane = cs.distance, cs.fovY, cs.aspectRatio, cs.nearPlane, cs.farPlane
      if not b.pos_broken then
        local okc, errc = pcall(function() cd.position.x, cd.position.y, cd.position.z = cs.position.x, cs.position.y, cs.position.z end)
        if not okc then b.pos_broken = true log("bot: camera position not copied (" .. tostring(errc) .. ")") end
      end
      inp.fromClientDoubleInputBindings = pi.fromClientDoubleInputBindings
    end
    if b.manual and b.stick > 0 then
      local tr = world:get("CurrentTransform", id)
      local r = math.rad(b.yaw)
      local step = b.mps / 60 * 2 ^ 32
      local p = tr.transform.position
      p.x = p.x + math.floor(math.sin(r) * step)
      p.z = p.z + math.floor(math.cos(r) * step)
      local q = tr.transform.orientation
      q.x, q.y, q.z, q.w = 0, math.sin(r / 2), 0, math.cos(r / 2)
    end
    if b.direct then
      local a = world:get("ActorInput", id)
      if a then
        local r = math.rad(b.yaw)
        local dx, dz = math.sin(r) * b.stick, math.cos(r) * b.stick
        a.desiredWorldMoveInput.x, a.desiredWorldMoveInput.y, a.desiredWorldMoveInput.z = dx, 0, dz
        a.desiredLocalMoveInput.x, a.desiredLocalMoveInput.y, a.desiredLocalMoveInput.z = 0, 0, b.stick
        a.locomotionSpeed = b.stick > 0 and 3 or 0
      end
    end
    local half = math.rad(b.yaw) / 2
    local q = inp.fromClient.camera.orientation
    q.x, q.y, q.z, q.w = 0, math.sin(half), 0, math.cos(half)
  end)
  if not ok and b.said < 3 then
    b.said = b.said + 1
    log("bot " .. tostring(id) .. ": input not written (" .. tostring(err) .. ")")
  end
end

function F.tick(world)
  if not world:is_server() then return end
  local t = world:tick()
  for id, b in pairs(bots) do feed(world, id, b, t) end
  local okj, errj = pcall(join_tick, world, t)
  if not okj then log("join recorder failed: " .. tostring(errj)) join = nil end
  for id, r in pairs(recs) do
    if t > r.untill then recs[id] = nil elseif t >= r.next then rec_line(world, id) r.next = t + 15 end
  end
  for id, h in pairs(stays) do hold(world, id, h) end
  for id, p in pairs(pending) do
    if t >= p.next_tick then
      p.tries = p.tries + 1
      if p.tries == 1 then look(world, id) end
      if try_offer(world, id) then
        look(world, id)
        pending[id] = nil
      elseif p.tries >= 10 then
        log("offer on " .. tostring(id) .. " gave up after 10 tries")
        look(world, id)
        pending[id] = nil
      else
        p.next_tick = t + 60
      end
    end
  end
end

return F
