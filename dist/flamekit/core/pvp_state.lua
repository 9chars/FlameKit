-- core/pvp_state.lua (0.15.452): who has PvP on right now, for any feature that must know (first: features/building.lua,
-- Free build is off in PvP). features/experimental.lua owns PvP and sets it here every server step for the players it
-- knows (HANDOFF rule 0b: features never call each other; shared state lives in core). Accounts as text. Not saved: PvP
-- lasts only while the player is here.
local M = {}
local on = {}  -- account -> true

-- Notes whether the player with this account has PvP on.
function M.set(account, value)
  if account == nil then return end
  on[tostring(account)] = value and true or nil
end

-- Whether the player with this account has PvP on.
function M.on(account)
  return account ~= nil and on[tostring(account)] == true
end

return M
