-- core/companion_notices.lua (0.15.349, owner 2026-11-20 16:20: "were going to add an option that turns all those "cant
-- follow" "can't reach", "afraid to jump", etc messages and default it off... players don't need to see that, its mostly
-- for me and for debugging, so put that option under the debug section"): this player's choice whether the companion
-- "can't follow" notices show. Off by default. Saved in companion_notices.json (core.store). The Experimental tab's
-- Debug section switches it; npc_wheel_probe tells the server (op "prefs" on the channel npcwheel), which sends the
-- notices only to players who have it on.
local store = require("core.store")
local M = {}
local cache

function M.on()
  if cache == nil then
    local saved = store.load("companion_notices", {})
    cache = type(saved) == "table" and saved.on == true
  end
  return cache
end

function M.set(on)
  cache = on and true or false
  store.save("companion_notices", { on = cache })
end

return M
