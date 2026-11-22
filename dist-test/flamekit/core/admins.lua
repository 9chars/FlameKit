-- core/admins.lua (0.15.422): who is a FlameKit admin, for any feature (HANDOFF rule 0b: features never call each
-- other, so this does not ask features/companions). The same rule as the companions' is_admin (04_roster.lua):
-- EMF's own admins (from.admin: the server's console, its [chat] admins), the host of a hosted game (from.is_local),
-- and the accounts in npc_admins.json beside the mod on the server (the companions' list, kept and changed there with
-- "flamekit.npc roster admin add|remove"). Read only; the list is read again at most every 10 s.
local store = require("core.store")

local M = {}

local OWNER_ACCOUNT = "0x485890b753e75ad1"  -- the server owner, the first admin (as in 04_roster.lua)
local list, read_at = nil, -1

local function accounts()
  local now = os.time()
  if not list or now - read_at >= 10 then
    local ok, l = pcall(store.load, "npc_admins", nil)
    list = (ok and type(l) == "table") and l or { OWNER_ACCOUNT }
    read_at = now
  end
  return list
end

-- Is this player (account; `from` as EMF's net messages give it, may be nil) a FlameKit admin?
function M.is(account, from)
  if type(from) == "table" and (from.admin == true or from.is_local == true) then return true end
  if account == nil then return false end
  account = tostring(account)
  for _, a in ipairs(accounts()) do if a == account then return true end end
  return false
end

return M
