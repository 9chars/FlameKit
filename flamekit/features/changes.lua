-- features/changes.lua: the What's New tab of FlameKit's window (F6), and after an update a message that says so.
--
-- changes.txt lists the versions, newest first: a line with the version and its date ("0.15.0 Nov 12, 2026"), then
-- its lines, then an empty line. The
-- last version this player has seen is kept in seen_version.json; when the mod's version is another one, a message
-- (kit.note: FlameKit's Messages window) says once, the first time the game is in a world, that the tab has what is new.
-- The tab: this version's lines, and under them the versions before it.

local F = { id = "changes", title = "What's New" }

local kit
local entries = {}     -- {version, lines}, newest first
local pending = false  -- a new version: the message is still to be shown
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

local MOST_VERSIONS = 12  -- the tab shows this version and the ones before it, up to this many

function F.panel(world)
  local rows = {}
  local shown = 0
  for _, e in ipairs(entries) do
    if #e.lines > 0 and not kit.newer(e.version, kit.version) and shown < MOST_VERSIONS then
      shown = shown + 1
      if shown == 2 then
        rows[#rows + 1] = { separator = true }
        rows[#rows + 1] = { heading = "Previous Versions" }
      end
      rows[#rows + 1] = { heading = e.version .. e.date, color = e.version == kit.version and "#9fd2ff" or nil }
      for _, line in ipairs(e.lines) do rows[#rows + 1] = { text = "- " .. line } end
    end
  end
  if #rows == 0 then rows[1] = { dim = true, text = "Nothing is written down about this version." } end
  return rows
end

function F.client_tick(world)
  if not pending then return end
  steps = steps + 1
  if steps < 180 or steps % 60 ~= 0 then return end  -- a moment after the world is there
  local player = emf.local_player()
  if not player or player == 0 then return end
  pending = false
  kit.store.save("seen_version", { version = kit.version })
  kit.note(string.format("%s was updated to v%s: see What's New in FlameKit's window (F6).", kit.name, kit.version), "#9fd2ff")
end

function F.setup(k)
  kit = k
  load_entries()
  local seen = kit.store.load("seen_version", {}).version
  if type(seen) ~= "string" then seen = nil end
  pending = seen ~= kit.version
end

return F
