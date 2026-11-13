-- features/native_ui.lua: the Lua side of FlameKit's own window (drawn by flamekit_native.dll, not by EMF).
--
-- The DLL only draws and takes clicks; everything it shows comes from here, and every change goes through here, so
-- the DLL never reads the game itself. The two talk through two small files in emf\mods\flamekit, each with one
-- writer (EMF has no channel between a native mod and a Lua mod yet: EMF_REQUESTS.md, 8):
--
--   ui_list.dat     written here when it changed: the Auto Junk List window's content, a line per entry, then "end"
--                   (a file without "end" is half written: the DLL reads it again later)
--                     O <0|1 auto> <drop|delete>                            the options
--                     B <item id hex> <count> <debug name> <name>           an item you carry that is not junk (but can be)
--                     J <item id hex, 0 = unknown> <count carried> <debug name> <name>   an entry of the junk list
--                   (the name, the game's own text in your language, is the rest of the line)
--   ui_actions.txt  written by the DLL (replaced whole): the last clicks, a line "<number> <what> <argument>":
--                     junk <debug name> | keep <debug name> | dump - | auto 0|1 | action drop|delete
--                   The numbers only grow. A number not seen before is done once. At a (re)load the numbers already
--                   in the file are taken as done, so a click is never done twice.
-- Both are runtime files: never deployed or diffed.

local F = { id = "native_ui", title = "Native UI" }

local kit, junk_list
local steps = 0
local last_list = nil   -- ui_list.dat as last written
local done = nil        -- the highest action number done (nil: the file is not read yet since this load)

function F.setup(k)
  kit = k
  junk_list = require("features.loot_filter.client")
end

local function one_line(text)
  return (tostring(text or ""):gsub("[\r\n]", " "))
end

local function write_list(world)
  local in_bag, junk, opts = junk_list.ui_lists(world)
  if not in_bag then return end
  local lines = { string.format("O %d %s", opts.auto and 1 or 0, opts.action) }
  for _, e in ipairs(in_bag) do
    lines[#lines + 1] = string.format("B %x %d %s %s", e.item, e.count, e.debug_name, one_line(e.name))
  end
  for _, e in ipairs(junk) do
    lines[#lines + 1] = string.format("J %x %d %s %s", e.item or 0, e.count, e.debug_name, one_line(e.name))
  end
  lines[#lines + 1] = "end"
  local text = table.concat(lines, "\n") .. "\n"
  if text == last_list then return end
  local f = io.open(emf.dir .. "\\ui_list.dat", "w")
  if not f then
    kit.debug("warn", "native ui: ui_list.dat could not be written")
    return
  end
  f:write(text)
  f:close()
  last_list = text
  kit.debug("debug", "native ui: ui_list.dat written: %d in the bag, %d on the junk list, auto %s, %s", #in_bag, #junk,
    tostring(opts.auto), opts.action)
end

local function act(world, what, arg)
  kit.debug("info", "native ui: click from FlameKit's window: %s %s", tostring(what), tostring(arg))
  if what == "junk" or what == "keep" then
    junk_list.ui_set(world, arg, what == "junk")
  elseif what == "dump" then
    junk_list.ui_dump(world)
  elseif what == "auto" or what == "action" then
    junk_list.ui_option(world, what, arg)
  end
end

local function read_actions(world)
  local f = io.open(emf.dir .. "\\ui_actions.txt", "r")
  local text = f and f:read("a") or ""
  if f then f:close() end
  local first = done == nil
  local highest = done or 0
  for line in text:gmatch("[^\r\n]+") do
    local n, what, arg = line:match("^(%d+) (%a+) (%S+)$")
    n = tonumber(n)
    if n and n > (done or math.huge) then
      act(world, what, arg)
      last_list = nil  -- the window shows the change at once
    end
    if n and n > highest then highest = n end
  end
  if first then kit.debug("info", "native ui: ui_actions.txt: clicks up to number %d taken as done (from before this load)", highest) end
  if first or highest > done then done = highest end
end

function F.client_tick(world)
  steps = steps + 1
  if steps % 3 == 0 then read_actions(world) end
  if steps % 10 == 0 or last_list == nil then write_list(world) end
end

return F
