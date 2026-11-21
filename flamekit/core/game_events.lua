-- core/game_events.lua (0.15.380): one emf.on_event registration per engine event for all of FlameKit, handed on to
-- every feature that listens (features/loot_filter and features/msg_tabs both want PickupEvent; a second
-- emf.on_event of the same name may replace the first). Shared core code (HANDOFF rule 0b).
--   events.on(name, fn)   fn(world, event) on the server world; true when the event is there

local events = {}

local listeners = {}   -- name -> { fn, ... }
local registered = {}  -- name -> what emf.on_event said

function events.on(name, fn)
  local list = listeners[name]
  if not list then
    list = {}
    listeners[name] = list
  end
  list[#list + 1] = fn
  if registered[name] == nil then
    local ok, res = pcall(emf.on_event, name, function(world, e)
      for _, f in ipairs(list) do
        local okf, err = pcall(f, world, e)
        if not okf then emf.log("events: " .. name .. ": " .. tostring(err)) end
      end
    end, "server")
    registered[name] = ok and res ~= false
  end
  return registered[name]
end

return events
