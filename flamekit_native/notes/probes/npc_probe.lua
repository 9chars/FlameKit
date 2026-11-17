-- npc_probe.lua (2026-11-17, owner: "spawn a villager-looking character that has no prompt of its own and add my own
-- prompts in it"): a test feature. Not loaded by FlameKit: see README.md here (local server only, never published).
--
-- Console (or emf\commands.txt on the server):
--   flamekit.npc spawn <player entity> [m1|m2|m3|f1|f2|f3]   one of the game's unused test villagers, 4 m in front
--   flamekit.npc offer <npc entity>                           put FlameKit's "E Talk" on it (tried again by itself)
--   flamekit.npc look <npc entity>                            log its parts: prompt, villager state, faction
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
}
local PARTS = { "InteractionOfferRuntime", "ClientInteractionOffer", "DynamicActiveNpcState", "Faction", "NpcCommon",
  "DynamicEnemy01BehaviorState", "Health", "MovementCollider", "DynamicLocomotion" }

local pending = {}   -- npc entity -> { tries, next_tick }
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

local function on_talk(world, player, npc)
  log(string.format("E pressed on %s by player %s", tostring(npc), tostring(player)))
  pcall(function()
    require("features.chat").notice_to(world, player, "The villager says hello (FlameKit's own prompt).", "#8cd2ff", 6)
  end)
end

local function try_offer(world, id)
  local ok, res = pcall(emf.offer, world, id, { verb = "Talk" }, on_talk)
  log(string.format("offer on %s: %s", tostring(id), ok and tostring(res) or ("error: " .. tostring(res))))
  return ok and res == true
end

function F.setup(k)
  emf.log("[flamekit] npc probe: loaded (test villager commands: flamekit.npc)")
  pcall(emf.command, "npc", "spawn <player> [m1..m3|f1..f3] | offer <npc> | look <npc> | remove <npc>: NPC probe (test)",
    function(world, args)
      local what = args[1]
      if what == "spawn" then
        local player = tonumber(args[2])
        local t = TEMPLATES[args[3] or "m2"]
        if not player or not t then emf.reply("npc: spawn <player entity> [m1|m2|m3|f1|f2|f3]") return end
        local x, y, z = world:position(player)
        if not x then emf.reply("npc: no player " .. tostring(player)) return end
        local ok, id = pcall(emf.spawn, world, t[2], x + 4, y + 0.5, z)
        log(string.format("spawn %s near player %s: %s", t[1], tostring(player), ok and tostring(id) or ("error: " .. tostring(id))))
        if ok and id then pending[id] = { tries = 0, next_tick = world:tick() + 60 } end
        emf.reply("npc: spawned " .. tostring(ok and id))
      elseif what == "offer" then
        local id = tonumber(args[2])
        if id then try_offer(world, id) end
        emf.reply("npc: offer tried")
      elseif what == "look" then
        local id = tonumber(args[2])
        if id then look(world, id) end
        emf.reply("npc: logged")
      elseif what == "remove" then
        local id = tonumber(args[2])
        local ok, res = pcall(emf.destroy, world, id)
        log(string.format("remove %s: %s", tostring(id), tostring(ok and res)))
        pending[id or 0] = nil
        emf.reply("npc: removed " .. tostring(ok and res))
      else
        emf.reply("npc: spawn <player> [m1..m3|f1..f3] | offer <npc> | look <npc> | remove <npc>")
      end
    end)
end

-- a spawned villager: looked at after 1 s, then FlameKit's offer tried once a second, 10 times at most
function F.tick(world)
  if not world:is_server() then return end
  local t = world:tick()
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
