-- features/server_save.lua: a world save on request, for FlameKit's restart helper (tools/restart_helper).
--
-- Before the restart helper restarts the local dedicated server (only after the owner said yes, and after it closed
-- the game client so no player is connected), it writes a number into save_now.request in this mod's folder on the
-- server. Where the world is hosted, this feature then asks the game to save the world at once (emf.request_save: the
-- same save the game's 30 s timer makes) and writes the same number into save_now.done. The restart helper waits until
-- a save file newer than its request exists, and only then stops the server. Without that file nothing happens here.

local F = { id = "server_save", title = "Server save" }

local kit
local steps = 0
local handled = nil  -- the request number last handled (nil: none yet in this run)

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text
end

function F.tick(world)
  steps = steps + 1
  if steps % 30 ~= 0 then return end
  local text = read(emf.dir .. "\\save_now.request")
  local number = text and text:match("^%s*(%d+)%s*$")
  if not number or number == handled then return end
  handled = number
  if read(emf.dir .. "\\save_now.done") == number then return end  -- done before a reload of this mod
  local ok, asked = pcall(emf.request_save)
  kit.debug(ok and asked and "info" or "warn", "server save: request %s from the restart helper: %s", number,
    ok and asked and "the game saves the world now" or "the game did not take the save request")
  local f = io.open(emf.dir .. "\\save_now.done", "w")
  if f then
    f:write(number)
    f:close()
  end
end

function F.setup(k)
  kit = k
end

return F
