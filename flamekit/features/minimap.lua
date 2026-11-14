-- features/minimap: the Minimap tab of the FlameKit panel.
--
-- The minimap itself is drawn by the native part (the mod "FlameKit Native", flamekit_native.dll, in your game only).
-- It reads its settings from this mod, so this tab only shows and changes those settings: nothing here runs on a
-- server.

local F = { id = "minimap", title = "Minimap" }

local kit

-- The switches of the tab: setting, what it says, and false for the ones that are off unless switched on.
local SWITCHES = {
  { "map_show", "Show the minimap", nil, "Shows or hides the whole minimap. The minimap key (F10 unless you changed it) does the same while you play." },
  { "map_labels", "Display map marker labels while zoomed in", nil, "Writes each marker's name under it: places, your own markers, named flame altars. Not at the two farthest zoom levels." },
  { "map_undiscovered", "Show undiscovered map locations", false, "Also shows places you have not found yet, in grey with a small question mark. A spoiler." },
  { "map_players", "Other players", nil, "Shows the other players as white dots with their names, at the minimap's edge when they are far away." },
  { "map_clock", "The clock", nil, "Shows the time of day under the minimap, and how many minutes are left until night or day." },
  { "map_altitude", "Your altitude in metres", nil, "Shows how high you are, at the end of the clock's line. Useful while gliding, climbing and digging." },
  { "map_where", "The region and the nearest place", nil, "Shows the region you are in and the nearest named place under the minimap." },
  { "map_big_text", "Minimaps larger than Large magnify (off: they show more of the world)", false,
    "Off: a minimap bigger than Large shows more of the world, with icons and text as big as on Large. On: it shows the same piece of the world, with everything bigger." },
  { "map_hide_in_menus", "Hide it while the big map, the bag or any menu is open", nil, "Hides the minimap while one of the game's menus is open, so it is not in the way." },
  { "ui_hide_build", "Hide FlameKit's windows in build mode", nil, "While you build, all of FlameKit on your screen is hidden so nothing is in the way: the minimap, the party window, Messages, Notices and the FlameKit lines in the lower left corner. FlameKit's window (F6) still opens." },
}

-- The marker filters: the short name the native part knows the kind by (kFilter in flamekit_native.cpp) and what the
-- tab calls it. The setting map_hide lists the names that are switched off, with commas between ("-": none).
local GROUPS = {
  { "FLAME", "#ffc85a", {
    { "al", "Flame Altars" }, { "hb", "Bases" }, { "sp", "Ancient Spires" }, { "tp", "Travel Points" },
    { "fs", "Flame Shrines" }, { "sa", "Flame Sanctums" }, { "ob", "Obelisks" } } },
  { "SHROUD AND DUNGEONS", "#c79bff", {
    -- "sr" is the game's well_plant marker, which is the Elixir Well (the short name is from a first, wrong guess and
    -- is kept so saved filters stay right); "ew" is its plain "dungeon" marker, not yet seen in the game
    { "sr", "Elixir Wells" }, { "ew", "Other dungeons" }, { "sn", "Shroud Nests" }, { "sf", "Gem Forges" },
    { "hh", "Hollow Halls" }, { "va", "Vaults" }, { "to", "Tombs" } } },
  { "PLACES", "#e6dcc0", {
    { "vi", "Villages" }, { "fa", "Farms" }, { "ca", "Caves" }, { "mi", "Mines" },
    { "cp", "Camps" }, { "ec", "Enemy Camps" }, { "ba", "Balefires" } } },
  { "YOURS", "#9fd2ff", {
    { "qu", "Quests" }, { "gr", "Graves" }, { "wa", "Water sources" } } },
  { "YOUR CUSTOM MARKERS", "#9fe6a0", {
    { "m0", "Flag" }, { "m1", "Chest" }, { "m2", "Glider" }, { "m3", "Loot" }, { "m4", "Plants" },
    { "m5", "Wildlife" }, { "m6", "Water" }, { "m7", "Fish" }, { "m8", "Ore" }, { "m9", "Combat" } } },
}
local FILTERS = {}  -- every filter, in the order of the groups
for _, g in ipairs(GROUPS) do
  for _, f in ipairs(g[3]) do FILTERS[#FILTERS + 1] = f end
end

local function hidden_set()
  local set = {}
  for name in tostring(kit.setting("map_hide", "-")):gmatch("[%w]+") do set[name] = true end
  return set
end

local function save_hidden(set)
  local names = {}
  for _, f in ipairs(FILTERS) do
    if set[f[1]] then names[#names + 1] = f[1] end
  end
  emf.set_setting("map_hide", #names > 0 and table.concat(names, ",") or "-")
end

-- The sizes the tab offers: the dial's width in pixels (the setting map_size takes any size from 120 to 480).
local SIZES = { { 160, "Small" }, { 220, "Medium" }, { 300, "Large" }, { 380, "Extra large" }, { 480, "Extra extra large" } }  -- Large is the default

local function on(key)
  for _, s in ipairs(SWITCHES) do
    if s[1] == key then return kit.setting(key, s[3] ~= false) == true end
  end
  return kit.setting(key, true) == true
end

-- ---- other players at any distance ----
--
-- A player's game only knows the players near it, so far-away friends would be missing from the minimap. The half of
-- this mod that runs where the world is hosted knows everyone: twice a second it tells each player's game where the
-- others are, and that game writes the list to far_players.dat in this folder, where the native minimap reads it
-- (a Lua mod and a native mod have no other way to talk; the file is tiny).

local CHANNEL = "map"
local test_players = require("core.test_players")
local players = require("core.players")
local steps = 0
local seq = 0

-- In a player's game: the list as the host sent it ("x z name" lines), handed on to the native minimap.
local function receive(text)
  if type(text) ~= "string" or #text > 8000 then return end
  seq = seq + 1
  local f = io.open(emf.dir .. "\\far_players.dat", "w")
  if not f then return end
  f:write(seq, "\n", text)
  f:close()
end

-- Where the world is hosted: everyone's place, sent to everyone else.
function F.tick(world)
  steps = steps + 1
  if steps % 30 ~= 0 then return end
  local here = {}
  for _, id in ipairs(players.ids(world)) do  -- core/players.lua: from EMF's join and leave events
    local ok, account = pcall(world.account, world, id)
    if ok and account then
      local x, _, z = world:position(id)
      if x then
        local okn, name = pcall(world.name, world, id)
        if not okn or type(name) ~= "string" or name == "" then
          okn, name = pcall(world.character_name, world, id)
        end
        if not okn or type(name) ~= "string" or name == "" then name = "Player" end
        here[#here + 1] = { id = id, line = string.format("%.1f %.1f %s", x, z, (name:gsub("[%c]", " "))) }
      end
    end
  end
  local me = emf.local_player()
  for _, to in ipairs(here) do
    local lines = {}
    for _, p in ipairs(here) do
      if p.id ~= to.id then lines[#lines + 1] = p.line end
    end
    for _, p in ipairs(test_players.list(world, to.id)) do  -- this player's test players (core/test_players.lua)
      if p.x then lines[#lines + 1] = string.format("%.1f %.1f %s", p.x, p.z, p.name) end
    end
    local text = table.concat(lines, "\n")
    if to.id == me then
      receive(text)  -- the host's own game is right here
    else
      pcall(emf.net.send_to, world, to.id, CHANNEL, text)
    end
  end
end

function F.setup(k)
  kit = k
  players.setup(k)
  local ok = emf.net.channel(CHANNEL, {
    version = 1, to = "players", max = 8192, per_10s = 60,
    on_player = kit.guard(F, function(world, from, data) receive(data) end, "the players' places from the server"),
  })
  pcall(receive, "")  -- an empty list to begin with: one left over from an earlier game is not shown
  if not ok then emf.log("the channel flamekit/map was refused: far-away players are not shown on the minimap") end
end

local ZOOM_STEPS = 7  -- the setting map_zoom: 0 closest .. 6 farthest

function F.panel(world)
  local rows = {}
  rows[#rows + 1] = { heading = "Location" }
  local placed = (tonumber(kit.setting("map_x", -1)) or -1) >= 0
  rows[#rows + 1] = { button = "reset", text = "Reset Default Position", disabled = not placed,
                      tooltip = "Puts the minimap back in its corner of the screen (the corner is below)." }
  for _, r in ipairs(require("features.settings").rows({ "map_corner", "map_margin" })) do rows[#rows + 1] = r end
  rows[#rows + 1] = { separator = true }
  rows[#rows + 1] = { heading = "Size" }
  local size = tonumber(kit.setting("map_size", 300)) or 300
  for i, z in ipairs(SIZES) do
    rows[#rows + 1] = { button = "size:" .. z[1], text = z[2], same_line = i > 1, selected = size == z[1],
                        tooltip = z[1] > 300 and "A bigger minimap that shows more of the world around you." or "How big the minimap is on your screen." }
  end
  rows[#rows + 1] = { separator = true }
  rows[#rows + 1] = { heading = "Zoom" }
  local zoom = math.floor((tonumber(kit.setting("map_zoom", 2)) or 2) + 0.5)
  rows[#rows + 1] = { button = "zoom:in", text = "Zoom in", disabled = zoom <= 0,
                      tooltip = "Shows a smaller piece of the world in more detail." }
  rows[#rows + 1] = { button = "zoom:out", text = "Zoom out", same_line = true, disabled = zoom >= ZOOM_STEPS - 1,
                      tooltip = "Shows a bigger piece of the world." }
  rows[#rows + 1] = { text = string.format("Zoom level %d of %d", ZOOM_STEPS - zoom, ZOOM_STEPS), same_line = true }
  rows[#rows + 1] = { separator = true }
  rows[#rows + 1] = { heading = "What it shows" }
  for _, s in ipairs(SWITCHES) do
    local is_on = on(s[1])
    rows[#rows + 1] = { button = "sw:" .. s[1], text = (is_on and "On    " or "Off   ") .. s[2], selected = is_on, tooltip = s[4] }
  end
  rows[#rows + 1] = { separator = true }
  rows[#rows + 1] = { heading = "Marker filters" }
  rows[#rows + 1] = { dim = true, text = "Click a kind of marker to hide it on the minimap (lit = shown). Click it again to show it." }
  rows[#rows + 1] = { button = "all:on", text = "Show all", tooltip = "Shows every kind of marker on the minimap." }
  rows[#rows + 1] = { button = "all:off", text = "Hide all", same_line = true, tooltip = "Hides every kind of marker on the minimap." }
  local hidden = hidden_set()
  for _, g in ipairs(GROUPS) do
    local on = 0
    for _, f in ipairs(g[3]) do
      if not hidden[f[1]] then on = on + 1 end
    end
    rows[#rows + 1] = { heading = string.format("%s (%d of %d)", g[1], on, #g[3]), color = g[2] }
    -- chips that run along the line and wrap, like the Auto Junk List's
    local room, used = kit.hub.WIDTH - 3, 0
    for _, f in ipairs(g[3]) do
      local need = #f[2] * 0.56 + 1.6
      local same = used > 0 and used + need <= room
      used = same and used + need or need
      rows[#rows + 1] = { button = "f:" .. f[1], text = f[2], selected = not hidden[f[1]], same_line = same,
                          tooltip = hidden[f[1]] and "Hidden. Click to show it." or "Shown. Click to hide it." }
    end
  end
  rows[#rows + 1] = { separator = true }
  rows[#rows + 1] = { heading = "Keys" }
  for _, r in ipairs(require("features.settings").rows({ "map_toggle_key", "map_zoom_in_key", "map_zoom_out_key" })) do rows[#rows + 1] = r end
  rows[#rows + 1] = { separator = true }
  rows[#rows + 1] = { dim = true, text = "The minimap needs the FlameKit Native part in your game." }
  return rows
end

function F.click(world, key)
  if key:sub(1, 4) == "set:" then return require("features.settings").click(world, key:sub(5)) end  -- a settings row
  if key == "reset" then
    emf.set_setting("map_x", -1)
    emf.set_setting("map_y", -1)
  elseif key == "zoom:in" or key == "zoom:out" then
    local zoom = math.floor((tonumber(kit.setting("map_zoom", 2)) or 2) + 0.5) + (key == "zoom:in" and -1 or 1)
    emf.set_setting("map_zoom", math.max(0, math.min(ZOOM_STEPS - 1, zoom)))
  elseif key:sub(1, 5) == "size:" then
    local px = tonumber(key:sub(6))
    if px then emf.set_setting("map_size", px) end
  elseif key == "all:on" then
    save_hidden({})
  elseif key == "all:off" then
    local set = {}
    for _, f in ipairs(FILTERS) do set[f[1]] = true end
    save_hidden(set)
  elseif key:sub(1, 2) == "f:" then
    local set = hidden_set()
    local name = key:sub(3)
    set[name] = not set[name] or nil
    save_hidden(set)
  elseif key:sub(1, 3) == "sw:" then
    local setting = key:sub(4)
    emf.set_setting(setting, not on(setting))
  end
end

return F
