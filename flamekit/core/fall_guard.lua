-- core/fall_guard.lua (0.15.209): keeps a falling player's fall short, so the landing never hurts.
--
-- The game measures a fall from DynamicFallDamage.fallStartAltitude (the height where the fall began) to the landing.
-- step() sets that start to where the player is now, every server step while they fall, so the game never sees a long
-- fall. Moved here from experimental.lua's No Fall Damage (0.15.208) so every feature that needs it uses this one copy
-- (owner, 2026-11-16: No Fall Damage, Invincible Mode and Super B Jump). Server world only.

local M = { broken = false }

local said = 0  -- the first few resets go into the log (start and height, the same unit: metres)

-- Call every server step for a player who must not take fall damage. Returns true while they fall.
function M.step(world, entity)
  if M.broken then return false end
  local falling = false
  local ok, err = pcall(function()
    local fd = world:get("DynamicFallDamage", entity)
    if not fd or not fd.wasFalling then return end
    falling = true
    local _, y = world:position(entity)
    local start = tonumber(fd.fallStartAltitude)
    if not y or not start then return end
    if said < 3 and start - y > 5 then
      said = said + 1
      emf.log(string.format("fall guard: fall start %.2f, height now %.2f", start, y))
    end
    if start > y and start - y < 5000 then fd.fallStartAltitude = y end
  end)
  if not ok then
    M.broken = true
    emf.log("fall guard: the fall height cannot be reset on this game version (" .. tostring(err) .. ")")
  end
  return falling
end

return M
