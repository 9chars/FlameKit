-- features/changes.lua: after an update, a window that says what is new.
--
-- changes.txt lists the versions, newest first: a line with the version and its date ("0.15.0 Nov 12, 2026"), then
-- its lines, then an empty line. The
-- last version this player has seen is kept in seen_version.json; when the mod's version is another one, the window
-- opens once, the first time the game is in a world: this version's lines, and under them every version before it.

local F = { id = "changes", title = "What's New" }

local kit
local ID = "changes"
local entries = {}     -- {version, lines}, newest first
local pending = nil    -- the rows to show, until the window has opened
local steps = 0

local function load_entries()
  local f = io.open(emf.dir .. "\\changes.txt", "r")
  if not f then return end
  local entry = nil
  for line in f:lines() do
    line = line:gsub("\r$", ""):gsub("^\239\187\191", "")
    local version, date = line:match("^(%d+%.[%d%.]+)%s*(.-)%s*$")
    if version then
      entry = { version = version, date = date ~= "" and " (" .. date .. ")" or "", lines = {} }
      entries[#entries + 1] = entry
    elseif entry and line:match("%S") then
      entry.lines[#entry.lines + 1] = (line:gsub("^%s*%-%s*", ""))
    end
  end
  f:close()
end

local MOST_ROWS = 240  -- EMF draws at most 256 rows: the oldest versions fall off a list longer than that

-- The window's rows: this version's lines, then the versions before it (for a player who was away for a while).
local function rows_for()
  local rows = {}
  local older = 0
  for _, e in ipairs(entries) do
    if #e.lines > 0 and not kit.newer(e.version, kit.version) then
      if e.version == kit.version then
        rows[#rows + 1] = { heading = "New Version" }
        rows[#rows + 1] = { text = e.version .. e.date, color = "#9fd2ff" }
        for _, line in ipairs(e.lines) do rows[#rows + 1] = { text = "- " .. line } end
      elseif #rows + #e.lines < MOST_ROWS then
        older = older + 1
        if older == 1 then
          rows[#rows + 1] = { text = " " }
          rows[#rows + 1] = { heading = "Previous Versions" }
        end
        rows[#rows + 1] = { text = e.version .. e.date, color = "#9fd2ff" }
        for _, line in ipairs(e.lines) do rows[#rows + 1] = { text = "- " .. line } end
      end
    end
  end
  if #rows == 0 then return nil end  -- nothing is written down about this version or the ones before
  rows[#rows + 1] = { separator = true }
  rows[#rows + 1] = { button = "close", text = "Close" }
  return rows
end

function F.client_tick(world)
  if not pending then return end
  steps = steps + 1
  if steps < 180 or steps % 60 ~= 0 then return end  -- a moment after the world is there; again while another window is open
  local player = emf.local_player()
  if not player or player == 0 then return end
  local opened = emf.window(ID, { title = kit.name .. " Updated", width = 34, place = "centre", world = "client", rows = pending }, function(_, ev)
    if ev.kind ~= "closed" then emf.window_close(ID) end
  end)
  if opened then
    pending = nil
    kit.store.save("seen_version", { version = kit.version })
  end
end

function F.setup(k)
  kit = k
  load_entries()
  local seen = kit.store.load("seen_version", {}).version
  if type(seen) ~= "string" then seen = nil end
  if seen == kit.version then return end
  pending = rows_for()
  if not pending then kit.store.save("seen_version", { version = kit.version }) end  -- nothing to tell about this one
end

return F
