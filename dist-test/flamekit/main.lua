-- FlameKit: one mod, many features.
--
-- This file only lists the features. Each one lives in features/<name>.lua and is plugged into the shared core
-- (core/kit.lua): one settings page, one panel with a tab per feature, one set of console commands.
--
-- To add a feature: copy features/_template.lua, give it an id, add its line below and its settings to mod.json.
-- Save any file while the game runs and EMF reloads the mod within a second.

local kit = require("core.kit")

kit.start({
  "features.changes",       -- the update message (no tab since 0.15.193). The tabs of FlameKit's window come in this order (then the DLL's own Windows and About tabs)
  "features.loot_filter",
  "features.minimap",
  "features.experimental",  -- its Debug section has the party's test players
  "features.building",      -- (0.15.452) the Building tab: Free build, Bigger altar areas, remembered spots
  "features.spawn_nodes",   -- (0.15.476) the Spawn Nodes tab (admins): nodes in groups that spawn monsters on a trigger
  "features.settings",
  "features.party",         -- no tab of its own
  "features.native_ui",
  "features.server_save",
  "features.server_version",  -- the notice when the server's FlameKit is older
  "features.chat",            -- chat copied into the Messages window, FlameKit's announcements there
  "features.leaderboard",     -- the PvP Leaderboard (kills and deaths between players)
  "features.loot_drop",       -- (0.15.142) a killed monster's loot; since 0.15.376 by the killer's Auto Loot setting
  "features.loose_loot",      -- (0.15.389, 0.15.390) loose drops of what a tool breaks or a kill leaves, by the player's Auto Loot setting
  "features.chest_overflow",  -- (0.15.410) what a full bag refuses from a loot chest goes to the companions
  "features.build_anywhere",  -- (0.15.412) the build hammer's "Needs a Flame Altar nearby" check (step 1: logging)
  "features.travel_hide",     -- (0.15.281) FlameKit's UI hides during a fast travel (the server tells the game when)
  "features.npc_wheel_probe",  -- the companion system, the player's end: the wheel, the Companion Roster window (2026-11-17)
  "features.msg_tabs",         -- (0.15.377) the Messages window's Battle and Loot tabs (the server's half and the channel)
  "features.water_debug",      -- (0.15.450) /flamekit.water [radius]: the water entities near you into the server's log (admins)
  "features.companions",       -- the companion system, the server end (0.15.362; in the release since 0.15.368, owner
                               -- 2026-11-20 19:05). Both share their channels through core/companion_net
  -- "features.my_next_feature",
})
