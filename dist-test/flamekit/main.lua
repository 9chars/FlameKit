-- FlameKit: one mod, many features.
--
-- This file only lists the features. Each one lives in features/<name>.lua and is plugged into the shared core
-- (core/kit.lua): one settings page, one panel with a tab per feature, one set of console commands.
--
-- To add a feature: copy features/_template.lua, give it an id, add its line below and its settings to mod.json.
-- Save any file while the game runs and EMF reloads the mod within a second.

local kit = require("core.kit")

kit.start({
  "features.loot_filter",
  "features.minimap",
  "features.experimental",
  "features.changes",
  "features.native_ui",
  "features.party",
  "features.server_save",
  -- "features.my_next_feature",
})
