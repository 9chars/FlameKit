-- core/game_events.lua (0.15.380): one emf.on_event registration per engine event for all of FlameKit, handed on to
-- every feature that listens (features/loot_filter and features/msg_tabs both want PickupEvent; a second
-- emf.on_event of the same name may replace the first). Shared core code (HANDOFF rule 0b).
--   events.on(name, fn)   fn(world, event) on the server world; true when the event is there

local events = {}

local listeners = {}   -- name -> { fn, ... }
local registered = {}  -- name -> what emf.on_event said

-- (0.15.405) `where`: "server" (default) or "client" (the player's own game's world)
function events.on(name, fn, where)
  where = where or "server"
  local key = where .. ":" .. name
  local list = listeners[key]
  if not list then
    list = {}
    listeners[key] = list
  end
  list[#list + 1] = fn
  if registered[key] == nil then
    local ok, res = pcall(emf.on_event, name, function(world, e)
      for _, f in ipairs(list) do
        local okf, err = pcall(f, world, e)
        if not okf then emf.log("events: " .. name .. ": " .. tostring(err)) end
      end
    end, where)
    registered[key] = ok and res ~= false
  end
  return registered[key]
end

return events
