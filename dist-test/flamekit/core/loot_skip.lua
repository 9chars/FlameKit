-- core/loot_skip.lua (0.15.547, owner 2026-11-24 10:08 "fix that bug"): bodies whose game loot another feature takes
-- care of itself, so FlameKit's Auto Loot (features/loot_drop.lua) leaves them alone. Spawn Nodes marks the monsters of
-- a group whose Loot is "Reward loot" or "No loot" (it removes their game loot itself); without this, Auto Loot looks at
-- a body 0.5 s after the death and moved the game loot into the killer's bag or onto the ground before Spawn Nodes'
-- removal at 2 s, so "No loot" still dropped loot for a killer with Auto Loot on (found by reading both 10:05).
-- Shared core code (HANDOFF rule 0b): any feature may mark or ask; it uses no feature. In memory only.
local M = {}
local marked = {}
-- Marks (on = true) or unmarks entity `id`.
function M.set(id, on)
  if id then marked[id] = on and true or nil end
end
-- Whether entity `id` is marked.
function M.is(id)
  return id ~= nil and marked[id] == true
end
return M
