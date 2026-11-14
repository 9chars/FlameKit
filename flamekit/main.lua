-- FlameKit: one mod, many features.
--
-- This file only lists the features. Each one lives in features/<name>.lua and is plugged into the shared core
-- (core/kit.lua): one settings page, one panel with a tab per feature, one set of console commands.
--
-- To add a feature: copy features/_template.lua, give it an id, add its line below and its settings to mod.json.
-- Save any file while the game runs and EMF reloads the mod within a second.

local kit = require("core.kit")

kit.start({
  "features.changes",       -- What's New. The tabs of FlameKit's window come in this order (then the DLL's own Windows tab)
  "features.loot_filter",
  "features.minimap",
  "features.experimental",  -- its Debug section has the party's test players
  "features.settings",
  "features.party",         -- no tab of its own
  "features.native_ui",
  "features.server_save",
  "features.server_version",  -- the notice when the server's FlameKit is older
  -- "features.my_next_feature",
})
