-- features/msg_tabs.lua (0.15.377, owner 2026-11-21 09:35): the Battle and Loot tabs of the Messages window. Where the
-- world is hosted it hands every hit (emf.on_hit) and every Auto Loot item (core/loot_route.lua) to core/msg_feed.lua,
-- which sends each player the lines meant for them; every game registers the channel that brings them (the lines go
-- into its tabs through kit.note_tab; FlameKit's DLL draws the tabs). The player's switches are in the Settings tab,
-- section Messages (features/settings.lua sends them: core/player_prefs.lua).

local feed = require("core.msg_feed")
local route = require("core.loot_route")
local prefs = require("core.player_prefs")

local F = { id = "msg_tabs", title = "Message tabs" }
local kit

function F.tick(world)
  feed.tick(world)
end

function F.setup(k)
  kit = k
  prefs.setup()
  local ok = feed.setup(kit)
  if not ok then emf.log("message tabs: the channel flamekit/feed was refused: no Battle and Loot lines") end
  route.set_report(function(world, r) feed.loot(world, r) end)
  local okh, hooked = pcall(emf.on_hit, kit.guard(F, function(world, hit) feed.hit(world, hit) end, "a hit"))
  if not (okh and hooked ~= false) then emf.log("message tabs: emf.on_hit is not there: no Battle lines") end
  -- (0.15.380) loot taken by hand (a body, a chest, the ground)
  local okp = require("core.game_events").on("PickupEvent", kit.guard(F, function(world, e) feed.pickup(world, e) end, "a pickup"))
  if not okp then emf.log("message tabs: PickupEvent refused: hand pickups are not in the Loot tab") end
  pcall(emf.on_player_left, kit.guard(F, function(world, p) if p and p.player then feed.forget(p.player) end end, "a player leaving"))
end

return F
