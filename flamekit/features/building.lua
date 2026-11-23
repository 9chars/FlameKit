-- features/building.lua (0.15.452, owner 2026-11-22 14:58 "#10 lets make this happen. it should be its own feature
-- anyways", 15:09 "I'm good with it having its own tab", 17:16 "make it its own feature"): the Building tab. Free build
-- and Bigger altar areas, moved out of features/experimental.lua (Rule 0n: the Experimental tab's Building section is
-- gone; this tab has the same controls).
--
-- FREE BUILD (per player, saved; off while the player is in PvP). FlameKit Native (src/build_anywhere.cpp) adds a
-- building area for each player it is on for (free_build_server.txt on the server, free_build_client.txt in that
-- player's own game: entity ids, one a line), outside flame altar areas only: since 0.15.475 a 24 m area around the
-- player, only while a building item is selected (it was 112 m around the player always and overloaded G-Portal). Every piece such a player places outside
-- the altar areas and the remembered spots makes its 32 m grid cell a REMEMBERED SPOT (the server's BuildingPlaceEvent):
-- the spots are kept in free_build_spots.json (kit.store) and handed to FlameKit Native in free_build_spots.txt ("x y z"
-- of each cell's centre in m), which keeps a 48 m building area over each from the server's start, so what is built
-- there is saved like inside an altar's area. At most SPOTS_MAX spots. Admins forget the nearest spot or all of them.
--
-- FREE BUILD INSIDE ALTAR AREAS (0.15.453, owner 17:19 "alter area rule for admins" -> "make this a setting and put it
-- into the "Building" tab", 17:29 "add the setting for admin free build mode staying on inside other peoples bases"): an
-- admin's own switch; while it is on, his Free build also works inside flame altar areas (other players' bases too).
-- In the list files his line is "<entity> a". Only admins can switch it on; it works only while he is an admin.
--
-- BIGGER ALTAR AREAS (the world's option, admins only, on unless switched off): every altar's area 1.5 times as big.
-- Kept in experimental_world.json ({ bigaltars = false } when off; the same file as before the move); FlameKit Native
-- reads the factor from altar_size_server.txt (the server) / altar_size_client.txt (a player's own game).
--
-- The tab: a player's game asks the server for its state every ASK_STEPS on the channel "build" ({op = "get"}; the
-- answer {op = "state", freebuild, pvp, bigaltars, admin, spot, note}); a click sends {op = "set" | "forget_spot" |
-- "forget_all_spots"}. In a game that hosts the world everything is done right here (no message).
-- Players' Free build switch was in experimental.json (key "freebuild"): copied once into building.json.
-- Uses only core modules (HANDOFF rule 0b), and features.chat for the announcements, as features/experimental.lua does.

local admins = require("core.admins")
local players = require("core.players")
local pvp_state = require("core.pvp_state")

local F = { id = "building", title = "Building" }
local kit

local CHANNEL = "build"
local ASK_STEPS = 300          -- the player's game asks for its state every 5 s
local FILE_STEPS = 30          -- the files for FlameKit Native: every half second
local ALTAR_FACTOR = "1.5"
local SPOT_STEP, SPOTS_MAX = 32, 100   -- (0.15.449, owner 14:58 "put a cap on it for now"): each spot is one more zone in
                                       -- the game's building-area list, sent whole to every player at each change
local SPOT_HALF = 24           -- m each way: a spot's area (the same as kSpotHalf in build_anywhere.cpp)
local SPOT_EDGE = 2            -- m kept free inside a spot's edge for the piece itself
local SPOT_NEAR = 64           -- m: the nearest spot within this is the one the tab shows (and Forget this spot forgets)

local TIP = "Build anywhere outside flame altar areas. What you build is remembered and kept through restarts. Inside an "
  .. "altar's area the game's normal building rules apply. Outside them the hammer uses only the materials in your bag. "
  .. "Needs FlameKit on the server too. Off while you are in PvP. Everyone on the server is told when you switch it."

-- ---- the server's half (where the world is hosted) ----

local S = { saved = nil, altars = nil, world = nil, spots = nil, written = {}, said = {}, full_told = {}, steps = 0, notes = {},
            admin_seen = {}, no_altar_since = nil }

-- Writes `text` to file `name` beside the Lua part for FlameKit Native, only when it changed. (0.15.453) Through a
-- temporary file put in its place, so FlameKit Native never reads half a file (while the name is missing for a moment it
-- keeps what it read before).
local function write_file(name, text, what)
  if S.written[name] == text then return end
  local path = emf.dir .. "\\" .. name
  local f = io.open(path .. ".tmp", "w")
  if not f then return end
  f:write(text)
  f:close()
  os.remove(path)
  if not os.rename(path .. ".tmp", path) then
    emf.log("building: " .. name .. " could not be put in place")
    return
  end
  S.written[name] = text
  if what then emf.log("building: " .. what .. " now " .. (text ~= "" and text:gsub("\n", " ") or "(nobody)")) end
end

-- Every player's Free build switch (account -> true), loaded once; the first time copied from experimental.json.
local function saved()
  if S.saved then return S.saved end
  local ok, t = pcall(kit.store.load, "building", nil)
  if ok and type(t) == "table" then
    S.saved = type(t.freebuild) == "table" and t.freebuild or {}
    S.altars = type(t.altars) == "table" and t.altars or {}
    return S.saved
  end
  S.saved, S.altars = {}, {}
  local okx, x = pcall(kit.store.load, "experimental", {})
  local n = 0
  for account, set in pairs(okx and type(x) == "table" and x or {}) do
    if type(set) == "table" and set.freebuild == true then S.saved[account] = true n = n + 1 end
  end
  pcall(kit.store.save, "building", { freebuild = S.saved, altars = S.altars })
  emf.log(string.format("building: Free build switches copied from experimental.json: %d player(s)", n))
  return S.saved
end

-- Whether Free build works for this player now: switched on and not in PvP.
local function free_on(account)
  return account ~= nil and saved()[tostring(account)] == true and not pvp_state.on(account)
end

-- Saves both switches (building.json).
local function save_switches()
  saved()
  pcall(kit.store.save, "building", { freebuild = S.saved, altars = S.altars })
end

-- Whether this player is an admin: core/admins' list, or seen as one in a message (EMF's own admins, the host).
local function is_admin(account, from)
  account = tostring(account)
  local yes = admins.is(account, from) == true
  if from then S.admin_seen[account] = yes or nil end  -- a message says what he is now (also when he stopped being one)
  return yes or S.admin_seen[account] == true
end

-- Whether this player's Free build also works inside altar areas: his switch, while he is an admin.
local function altars_on(account)
  saved()
  return account ~= nil and S.altars[tostring(account)] == true and is_admin(account, nil)
end

-- How many altar areas the server knows (altar_areas_server.txt, written by FlameKit Native); nil while there is no file.
local function altar_count()
  local f = io.open(emf.dir .. "\\altar_areas_server.txt", "r")
  if not f then return nil end
  local n = 0
  for line in f:lines() do if line:match("%d") then n = n + 1 end end
  f:close()
  return n
end

-- (0.15.461) Whether FlameKit Native adds Free build's areas the old way, which needs a flame altar on the map
-- (free_build_way.txt "altar": its hooks on the game's list could not be set, or "fkbuild clear off"). Since 0.15.460 it
-- adds them right after the game empties its list ("clear"), with or without an altar: no file (an older FlameKit Native)
-- counts as that too.
local function needs_altar()
  local f = io.open(emf.dir .. "\\free_build_way.txt", "r")
  local way = f and f:read("l")
  if f then f:close() end
  return way ~= nil and way:match("^%s*altar") ~= nil
end

-- The world's Bigger altar areas: on unless an admin switched it off (experimental_world.json).
local function big_on()
  if S.world == nil then
    local ok, w = pcall(kit.store.load, "experimental_world", {})
    S.world = (ok and type(w) == "table") and w or {}
  end
  return S.world.bigaltars ~= false
end

-- The remembered spots (cell key -> { x, y, z } centre in m), loaded once.
local function spots()
  if S.spots == nil then
    local ok, t = pcall(kit.store.load, "free_build_spots", {})
    S.spots = (ok and type(t) == "table") and t or {}
  end
  return S.spots
end

-- How many spots there are.
local function spot_count()
  local n = 0
  for _ in pairs(spots()) do n = n + 1 end
  return n
end

-- Saves the spots and writes free_build_spots.txt for FlameKit Native (when it changed); how many there are.
local function spots_write(save)
  if save then pcall(kit.store.save, "free_build_spots", spots()) end
  local lines, n = {}, 0
  for _, c in pairs(spots()) do
    n = n + 1
    lines[n] = string.format("%.1f %.1f %.1f", c[1], c[2], c[3])
  end
  table.sort(lines)
  write_file("free_build_spot_half.txt", string.format("%d\n", SPOT_HALF))  -- (0.15.453) the one place the size is set
  write_file("free_build_spots.txt", table.concat(lines, "\n") .. (n > 0 and "\n" or ""))
  return n
end

-- Whether x, y, z lies in one of the server's altar areas (altar_areas_server.txt, written by FlameKit Native).
local function in_altar_area(x, y, z)
  local fa = io.open(emf.dir .. "\\altar_areas_server.txt", "r")
  if not fa then return false end
  for line in fa:lines() do
    local a = {}
    for v in line:gmatch("%-?[%d%.]+") do a[#a + 1] = tonumber(v) end
    if #a == 6 and x >= a[1] and x <= a[4] and y >= a[2] and y <= a[5] and z >= a[3] and z <= a[6] then
      fa:close()
      return true
    end
  end
  fa:close()
  return false
end

-- A BuildingPlaceEvent: for a player with Free build on, a piece outside the altar areas and every remembered spot makes
-- its 32 m cell a remembered spot (at most SPOTS_MAX; the player is told when the limit is reached).
local function on_place(world, e)
  local owner = tonumber((pcall(function() return e.ownerId end) and e.ownerId) or 0) or 0
  if owner == 0 then return end
  local oka, account = pcall(world.account, world, owner)
  account = oka and account and tostring(account) or nil
  if not free_on(account) then return end
  local x, y, z
  pcall(function() local q = e.position x, y, z = tonumber(q.x), tonumber(q.y), tonumber(q.z) end)
  if not (x and y and z) then
    local okp, px, py, pz = pcall(world.position, world, owner)
    if okp then x, y, z = px, py, pz end
  end
  if not (x and y and z) then return end
  if in_altar_area(x, y, z) then
    emf.log(string.format("building: free build: placed by %d at %.1f %.1f %.1f, in an altar area: no spot", owner, x, y, z))
    return
  end
  local cx, cy, cz = math.floor(x / SPOT_STEP), math.floor(y / SPOT_STEP), math.floor(z / SPOT_STEP)
  local key = cx .. "," .. cy .. "," .. cz
  local inside = spots()[key]
  if not inside then  -- (0.15.444) already inside a spot's area, even over a grid line: no new spot
    local lim = SPOT_HALF - SPOT_EDGE
    for _, c in pairs(spots()) do
      if math.abs(x - c[1]) <= lim and math.abs(y - c[2]) <= lim and math.abs(z - c[3]) <= lim then inside = c break end
    end
  end
  if inside then
    emf.log(string.format("building: free build: placed by %d at %.1f %.1f %.1f, in the remembered spot %.0f %.0f %.0f",
      owner, x, y, z, inside[1], inside[2], inside[3]))
    return
  end
  local n = spot_count()
  if n >= SPOTS_MAX then
    emf.log("building: free build: remembered spots full (" .. n .. "), not kept: " .. key)
    if os.time() - (S.full_told[account] or 0) >= 60 then
      S.full_told[account] = os.time()
      S.notes[account] = string.format("Free build: the server's limit of %d remembered spots is reached. What you build here is "
        .. "not kept: it goes at the next restart or after about 30 minutes. An admin can forget spots in the Building tab.", SPOTS_MAX)
    end
    return
  end
  spots()[key] = { cx * SPOT_STEP + SPOT_STEP / 2, cy * SPOT_STEP + SPOT_STEP / 2, cz * SPOT_STEP + SPOT_STEP / 2 }
  local total = spots_write(true)
  emf.log(string.format("building: free build: a spot remembered at %.0f %.0f %.0f (placed by %d at %.1f %.1f %.1f; %d spot(s))",
    spots()[key][1], spots()[key][2], spots()[key][3], owner, x, y, z, total))
end

-- The remembered spot nearest player entity `entity` (centre within SPOT_NEAR m across, 48 m up or down): its key, centre
-- and distance, and the player's position; nil when there is none.
local function spot_for(world, entity)
  if not world or not entity then return nil end
  local okp, x, y, z = pcall(world.position, world, entity)
  if not okp or not x then return nil end
  local best, bk, bc = nil, nil, nil
  for k, c in pairs(spots()) do
    local dx, dy, dz = x - c[1], y - c[2], z - c[3]
    local d = math.sqrt(dx * dx + dz * dz)
    if d <= SPOT_NEAR and math.abs(dy) <= 48 and (not best or d < best) then best, bk, bc = d, k, c end
  end
  return bk, bc, best, x, y, z
end

-- What the tab shows player `entity` about the spots: how many, and the nearest (logged when it changes).
local function spot_info(world, account, entity)
  local info = { total = spot_count() }
  local key, c, d, x, y, z = spot_for(world, entity)
  if key then
    info.key, info.x, info.y, info.z = key, math.floor(c[1] + 0.5), math.floor(c[2] + 0.5), math.floor(c[3] + 0.5)
    info.dist = math.floor(d + 0.5)
  end
  local said = string.format("%s|%s|%s", tostring(key), tostring(info.dist), x and (math.floor(x / 8) .. "," .. math.floor(z / 8)) or "?")
  if S.said[tostring(account)] ~= said then
    S.said[tostring(account)] = said
    emf.log(string.format("building: free build: panel spot for %s (entity %s at %s): %s", tostring(account), tostring(entity),
      x and string.format("%.1f %.1f %.1f", x, y, z) or "no position",
      key and string.format("%d %d %d, %d m", info.x, info.y, info.z, info.dist) or "none within " .. SPOT_NEAR .. " m"))
  end
  return info
end

-- A player's state for his tab.
local function state(world, account, entity, from)
  account = tostring(account)
  local admin = is_admin(account, from)
  local st = { op = "state", freebuild = saved()[account] == true or nil, pvp = pvp_state.on(account) or nil,
               altars = S.altars[account] == true or nil, altars_on = altars_on(account) or nil,
               bigaltars = big_on() or nil, admin = admin or nil, spot = spot_info(world, account, entity),
               noaltars = (S.no_altar_since ~= nil and os.time() - S.no_altar_since >= 60) or nil, note = S.notes[account] }
  S.notes[account] = nil
  return st
end

-- Tells everyone with FlameKit (the Messages and Notices windows), as the Experimental tab's switches do.
local function announce(world, line)
  local sent, why = pcall(function() return require("features.chat").announce(world, line, nil, { colour = "#ff9632", seconds = 10 }) end)
  if not sent then emf.log("building: the announcement was not sent (" .. tostring(why) .. ")") end
end

-- A message from a player's game (or the host's own click): does it, and answers with his state.
local function handle(world, account, entity, msg, from)
  account = tostring(account)
  local function refused(text) local st = state(world, account, entity, from) st.note = text return st end
  if msg.op == "set" and msg.key == "freebuild" then
    if pvp_state.on(account) and msg.on == true then return refused("Off while you are in PvP.") end
    local on = msg.on == true
    if (saved()[account] == true) ~= on then
      saved()[account] = on or nil
      save_switches()
      emf.log(string.format("building: player %s switched Free build %s", tostring(entity), on and "on" or "off"))  -- never the account in a log
      announce(world, string.format("%s turned %s free build.", players.name(world, entity, "a player"), on and "ON" or "OFF"))
    end
  elseif msg.op == "set" and msg.key == "altars" then  -- (0.15.453) an admin's Free build inside altar areas
    if not is_admin(account, from) then return refused("Only FlameKit admins can use Free build inside altar areas.") end
    local on = msg.on == true
    saved()
    if (S.altars[account] == true) ~= on then
      S.altars[account] = on or nil
      save_switches()
      emf.log(string.format("building: player %s switched Free build inside altar areas %s", tostring(entity), on and "on" or "off"))
    end
  elseif msg.op == "set" and msg.key == "bigaltars" then
    if not is_admin(account, from) then return refused("Only FlameKit admins can switch Bigger altar areas.") end
    big_on()
    if msg.on == true then S.world.bigaltars = nil else S.world.bigaltars = false end  -- only "off" is kept
    pcall(kit.store.save, "experimental_world", S.world)
    emf.log(string.format("building: player %s switched bigger altar areas %s", tostring(entity), msg.on == true and "on" or "off"))
    announce(world, string.format("%s turned %s bigger altar areas.", players.name(world, entity, "a player"), msg.on == true and "ON" or "OFF"))
  elseif msg.op == "forget_spot" then
    if not is_admin(account, from) then return refused("Only FlameKit admins can forget Free build spots.") end
    local key, c = spot_for(world, entity)
    if not key then return refused("There is no remembered spot within " .. SPOT_NEAR .. " m of you.") end
    spots()[key] = nil
    local total = spots_write(true)
    emf.log(string.format("building: free build: player %s forgot the spot at %.0f %.0f %.0f (%d left)", tostring(entity), c[1], c[2], c[3], total))
    return refused(string.format("Forgot the spot at %.0f, %.0f. What was built there is temporary again.", c[1], c[3]))
  elseif msg.op == "forget_all_spots" then
    if not is_admin(account, from) then return refused("Only FlameKit admins can forget Free build spots.") end
    local n = spot_count()
    S.spots = {}
    spots_write(true)
    emf.log(string.format("building: free build: player %s forgot all %d remembered spot(s)", tostring(entity), n))
    return refused(n > 0 and string.format("Forgot all %d remembered spot(s). What was built there is temporary again.", n)
      or "There are no remembered spots.")
  end
  return state(world, account, entity, from)
end

-- Every server step: every FILE_STEPS the files for FlameKit Native (who Free build is on for, the altar factor, the spots).
function F.tick(world)
  if not world:is_server() then return end
  S.steps = S.steps + 1
  if S.steps % FILE_STEPS ~= 0 then return end
  local ids = {}
  for _, id in ipairs(players.ids(world)) do
    local ok, account = pcall(world.account, world, id)
    if ok and account and free_on(account) then ids[#ids + 1] = tostring(id) .. (altars_on(account) and " a" or "") end
  end
  table.sort(ids)
  -- (0.15.453, owner 17:19 "#5 go ahead") a map without any flame altar while FlameKit Native adds Free build's areas the
  -- old way, which needs one: the tab says so once it has been so for a minute. (0.15.461, owner 20:15 "it does show the
  -- "map has no flame alter yet" message": since 0.15.460 Free build works without an altar, so only in the old way)
  local altars = altar_count()
  if altars == 0 and needs_altar() then S.no_altar_since = S.no_altar_since or os.time() else S.no_altar_since = nil end
  write_file("free_build_server.txt", table.concat(ids, "\n") .. (#ids > 0 and "\n" or ""), "free build: server list")
  write_file("altar_size_server.txt", (big_on() and ALTAR_FACTOR or "1") .. "\n", "bigger altar areas: altar_size_server.txt")
  spots_write(false)
end

-- ---- the player's game ----

local C = { shown = nil, since_ask = ASK_STEPS, steps = 0, note = nil, all_asked = nil, last_peer = nil }

-- Whether this Lua state hosts the world (a game that hosts, or the server).
local function hosting(world)
  return kit.is_host() or world:is_server()
end

-- The server's version of the channel (0: the server has no Building feature).
local function peer()
  local ok, version = pcall(emf.net.peer, nil, 0, CHANNEL)
  return ok and version or 0
end

-- This player's state: made right here in a world you host, else the server's last answer.
local function my_state(world)
  if hosting(world) then
    local me = emf.local_player()
    if not me or me == 0 then return nil end
    local ok, account = pcall(world.account, world, me)
    if not (ok and account) then return nil end
    return state(world, account, me, { is_local = true })
  end
  return C.shown
end

-- Sends `msg` to the server; true when sent.
local function ask(msg)
  local ok, sent = pcall(emf.net.send, CHANNEL, emf.json.encode(msg))
  C.since_ask = 0
  return ok and sent == true
end

-- A click in this game: done here in a world you host (the note comes back at once), else sent to the server.
local function act(world, msg)
  if hosting(world) then
    local me = emf.local_player()
    local ok, account = pcall(world.account, world, me)
    if ok and account then C.note = handle(world, account, me, msg, { is_local = true }).note end
  elseif C.shown then
    ask(msg)
  end
end

-- Every step of the player's game: asks the server for the state every ASK_STEPS, and writes this game's files for
-- FlameKit Native every FILE_STEPS (Free build on for me, the altar factor: from the server's answer).
function F.client_tick(world)
  C.steps = C.steps + 1
  local version = peer()
  if version ~= C.last_peer then
    C.last_peer, C.shown, C.since_ask = version, nil, ASK_STEPS
  end
  C.since_ask = C.since_ask + 1
  if not hosting(world) and version ~= 0 and C.since_ask >= ASK_STEPS then ask({ op = "get" }) end
  if C.steps % FILE_STEPS ~= 0 then return end
  local okv, v = pcall(my_state, world)
  v = okv and v or nil
  -- no answer from the server yet (just joined, or a server without this tab): the files are left as they are, so a
  -- reload of the Lua part never switches the bigger altar areas or Free build off in this game for a moment
  if not v then return end
  local me = emf.local_player()
  local on = v and v.freebuild == true and not v.pvp and me and me ~= 0
  write_file("free_build_client.txt", on and (tostring(me) .. (v.altars_on and " a" or "") .. "\n") or "", "free build: this game's list")
  write_file("altar_size_client.txt", ((v and v.bigaltars == true) and ALTAR_FACTOR or "1") .. "\n", "bigger altar areas: altar_size_client.txt")
end

-- The Building tab's rows.
function F.panel(world)
  local v = my_state(world)
  if not v then
    return { { dim = true, text = (hosting(world) or peer() ~= 0) and "Asking the server..."
      or "This server does not run FlameKit's Building tab (or not this version)." } }
  end
  local rows = {}
  local note = C.note or v.note
  if note then rows[#rows + 1] = { color = "#ffb060", text = note } end
  rows[#rows + 1] = { heading = "Free build" }
  if v.pvp then
    rows[#rows + 1] = { button = "b:free", text = "Off   Free build (off in PvP)", disabled = true,
      tooltip = "Off while you are in PvP, so nobody can cheat in a fight. It comes back when you switch PvP off." }
  else
    rows[#rows + 1] = { button = "b:free", text = (v.freebuild and "On    " or "Off   ") .. "Free build", selected = v.freebuild == true, tooltip = TIP }
  end
  local admin = v.admin == true
  local only = admin and "" or " (admins only)"
  rows[#rows + 1] = { button = "b:altars", text = (v.altars and "On    " or "Off   ") .. "Free build inside altar areas" .. only,
    selected = v.altars == true, disabled = (not admin) or nil,
    tooltip = "For admins: your Free build keeps working inside flame altar areas too, other players' bases included, so you can "
      .. "fix or remove pieces there. Only for you, and only while Free build is on. Off: inside an altar's area the game's "
      .. "normal building rules apply." .. (admin and "" or " Only FlameKit admins can use it.") }
  if v.noaltars then
    rows[#rows + 1] = { color = "#ffb060", text = "This map has no flame altar yet: Free build needs at least one flame altar somewhere on the map for now." }
  end
  local on = v.bigaltars == true
  rows[#rows + 1] = { heading = "Flame altars" }
  rows[#rows + 1] = { button = "b:big", text = (on and "On    " or "Off   ") .. "Bigger altar areas (1.5x)" .. only,
    selected = on, disabled = (not admin) or nil,
    tooltip = "Every flame altar's building area is 1.5 times as wide, high and deep; an altar's level still sets its size (40 m becomes "
      .. "60 m, 160 m becomes 240 m). For the whole server: everyone's altars. What you build in the bigger area is kept like anything "
      .. "inside an altar's area. Players need this FlameKit version in their own game to see and use the bigger area. On unless an "
      .. "admin switches it off. Only FlameKit admins can switch it; everyone on the server is told." }
  local sp = v.spot or { total = 0 }
  local total = sp.total or 0
  rows[#rows + 1] = { heading = "Remembered spots" }
  rows[#rows + 1] = { dim = true, text = string.format("Remembered Free build spots: %d of %d", total, SPOTS_MAX),
    tooltip = "Places where someone built with Free build. Each is a 32 m square of the world with a building area over it (48 m wide "
      .. "and high), so what was built there stays through restarts like inside an altar's area." }
  if sp.key then
    rows[#rows + 1] = { dim = true, text = string.format("Nearest spot: %d, %d (height %d), centre %d m away", sp.x, sp.z, sp.y, sp.dist or 0) }
  else
    rows[#rows + 1] = { dim = true, text = "No remembered spot within " .. SPOT_NEAR .. " m of you." }
  end
  rows[#rows + 1] = { button = "b:forget", text = "Forget this spot" .. only, disabled = (not admin or not sp.key) or nil,
    tooltip = (sp.key and string.format("Forgets the remembered spot at %d, %d. What was built in it is temporary again: the game removes "
      .. "it at the next restart or after about 30 minutes. Its border shows while your building tool is out.", sp.x, sp.z)
      or ("No remembered spot within " .. SPOT_NEAR .. " m of you: walk to one to forget it.")) .. (admin and "" or " Only FlameKit admins can use it.") }
  local asked = admin and total > 0 and C.all_asked and os.time() - C.all_asked <= 5
  rows[#rows + 1] = { button = "b:forgetall", selected = asked or nil, disabled = (not admin or total == 0) or nil,
    text = asked and string.format("Click again to forget all %d spots", total) or (string.format("Forget all spots (%d)", total) .. only),
    tooltip = "Forgets every remembered Free build spot on the map at once. What was built in them is temporary again: the game removes "
      .. "it at the next restart or after about 30 minutes. Click twice within 5 seconds."
      .. (total == 0 and " There are no remembered spots now." or "") .. (admin and "" or " Only FlameKit admins can use it.") }
  return rows
end

-- A click in the Building tab.
function F.click(world, key)
  C.note = nil
  local v = my_state(world)
  if not v then return end
  if key == "b:free" then
    if v.pvp then return end
    act(world, { op = "set", key = "freebuild", on = not (v.freebuild == true) })
  elseif key == "b:altars" then
    act(world, { op = "set", key = "altars", on = not (v.altars == true) })
  elseif key == "b:big" then
    act(world, { op = "set", key = "bigaltars", on = not (v.bigaltars == true) })
  elseif key == "b:forget" then
    act(world, { op = "forget_spot" })
  elseif key == "b:forgetall" then  -- the second click within 5 s does it
    if not (C.all_asked and os.time() - C.all_asked <= 5) then C.all_asked = os.time() return end
    C.all_asked = nil
    act(world, { op = "forget_all_spots" })
  end
end

-- (No F.connected: kit.connected says "FlameKit not supported by server!" when any feature answers false, and this
-- tab's channel only works after a rejoin when it is new (0.15.452, 17:26: the message came for that reason). The tab
-- itself says when the server does not answer.)

-- The channel (the server's and the players' ends), the building pieces (remembered spots) and the files at the start.
function F.setup(k)
  kit = k
  players.setup(k)
  local ok = emf.net.channel(CHANNEL, {
    version = 1, to = "both", max = 4096, per_10s = 60,
    on_server = kit.guard(F, function(world, from, data)
      if type(from) ~= "table" or not from.player or from.player == 0 then return end
      local okd, msg = pcall(emf.json.decode, data)
      if not (okd and type(msg) == "table") then return end
      local account = from.account
      if (not account or tostring(account):match("^0x0*$")) then
        local oka, a = pcall(world.account, world, from.player)
        account = oka and a or nil
      end
      if not account then return end
      local st = handle(world, account, from.player, msg, from)
      pcall(emf.net.send_to, world, from.player, CHANNEL, emf.json.encode(st))
    end, "a Building message from a player"),
    on_player = kit.guard(F, function(world, from, data)
      local okd, msg = pcall(emf.json.decode, data)
      if okd and type(msg) == "table" and msg.op == "state" then
        C.shown = msg
        if msg.note then C.note = msg.note end
      end
    end, "the Building state from the server"),
  })
  if not ok then emf.log("building: the channel flamekit/build was refused: the Building tab cannot reach the server") end
  local okr = require("core.game_events").on("BuildingPlaceEvent", function(world, e) pcall(on_place, world, e) end)
  if not okr then emf.log("building: BuildingPlaceEvent cannot be heard: no remembered spots") end
  pcall(spots_write, false)
end

-- tests only
F._state = function(world, account, entity, from) return state(world, account, entity, from) end
F._handle = function(world, account, entity, msg, from) return handle(world, account, entity, msg, from) end
F._on_place = function(world, e) return on_place(world, e) end
F._reset = function() S.saved, S.altars, S.world, S.spots, S.written, S.said, S.notes = nil, nil, nil, nil, {}, {}, {} end

return F
