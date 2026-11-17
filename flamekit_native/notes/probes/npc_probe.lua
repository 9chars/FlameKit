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

local pending = {}   -- npc entity -> { tries, next_tick }
local stays = {}     -- npc entity -> { x, y, z, moved = count of put-backs } (owner: "can you make him stop moving around")
local said = {}

local function log(s) emf.log("npc probe: " .. s) end

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

local function stay_here(world, id)
  local x, y, z = world:position(id)
  if x then stays[id] = { x = x, y = y, z = z, moved = 0 } end
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
          local x, y, z = world:position(id)
          if x then stays[id] = { x = x, y = y, z = z, moved = 0 } end
          log(string.format("stay on for %s at %s", tostring(id), x and string.format("%.1f %.1f %.1f", x, y, z) or "?"))
          emf.reply("npc: holding " .. tostring(id))
        end
      elseif what == "here" then  -- here <npc> <player>: moved next to the player (1.5 m), then held there
        local id, player = tonumber(args[2]), tonumber(args[3])
        local x, y, z = world:position(player or 0)
        if not (id and x) then emf.reply("npc: here <npc entity> <player entity>") return end
        stays[id] = { x = x + 1.5, y = y, z = z, moved = 0, busy = true }
        local ok = pcall(emf.teleport, world, id, x + 1.5, y, z, { ground = true }, function(moved, nx, ny, nz)
          if nx then stays[id] = { x = nx, y = ny, z = nz, moved = 0 } end
          log(string.format("here: %s moved %s, now at %s", tostring(id), tostring(moved),
            nx and string.format("%.1f %.1f %.1f", nx, ny, nz) or "?"))
        end)
        emf.reply("npc: moving " .. tostring(ok))
      elseif what == "remove" then
        local id = tonumber(args[2])
        local ok, res = pcall(emf.destroy, world, id)
        log(string.format("remove %s: %s", tostring(id), tostring(ok and res)))
        pending[id or 0], stays[id or 0], following[id or 0] = nil, nil, nil
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

function F.tick(world)
  if not world:is_server() then return end
  local t = world:tick()
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
