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
  "features.settings",
  "features.server_tab",     -- (0.15.142) the Server tab: settings for the whole server
  "features.party",         -- no tab of its own
  "features.native_ui",
  "features.server_save",
  "features.server_version",  -- the notice when the server's FlameKit is older
  "features.chat",            -- chat copied into the Messages window, FlameKit's announcements there
  "features.leaderboard",     -- the PvP Leaderboard (kills and deaths between players)
  "features.loot_drop",       -- (0.15.142) monsters drop their loot on the ground (a Server tab setting)
  "features.travel_hide",     -- (0.15.281) FlameKit's UI hides during a fast travel (the server tells the game when)
  "features.npc_probe",        -- TEMPORARY probe (local server only)
  -- "features.my_next_feature",
})
