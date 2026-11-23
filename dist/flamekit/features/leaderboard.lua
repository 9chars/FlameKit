-- features/leaderboard.lua: the PvP Leaderboard (0.15.95, owner): kills and deaths between players, ranked.
--
-- Where the world is hosted (your own game, or a server with FlameKit): EMF reports each player's death with the
-- player who hit them last within 10 s (emf.on_player_died, p.killer: an entity id, 0 for none). When that is another
-- player, the killer gets a kill and the one who died a death. Deaths to monsters, falls and the like are not counted:
-- this is the PvP board. The counts are kept per player account in leaderboard.json on the server (beside the world;
-- they survive restarts) with the name each player had last. Each kill is announced in everyone's Messages window.
--
-- The ranking: most kills first; equal kills, fewer deaths first; then by name. Everyone with at least one kill or
-- death is on it. The server sends the board on the channel flamekit/board to every player's game (when it changes,
-- when someone joins and every 30 s); a player's game writes it to emf\mods\flamekit\ui_board.dat for the DLL's
-- "PvP Leaderboard" window (its key: setting board_window_key, F5):
--   source server|none
--   r <rank> <kills> <deaths> <you 0|1> <name>    (fields separated by tabs, best first)
--   end
-- "source none": no board has come from the server (a server without FlameKit, or an older one).
-- Console (server, emf\commands.txt): flamekit.board_reset clears the board.
-- ui_board.dat is a runtime file: never deployed or diffed.

local players = require("core.players")

local F = { id = "leaderboard", title = "PvP Leaderboard" }
local CHANNEL = "board"
local MAX_ROWS = 50
local kit

-- ---- where the world is hosted ----

local board = nil     -- account -> { kills, deaths, name }
local changed = true  -- send the board out at the next step
local steps = 0

-- Loads the board (kills, deaths, name per account) from leaderboard.json, once.
local function load_board()
  if board then return end
  board = {}
  for account, e in pairs(kit.store.load("leaderboard", {})) do
    if type(e) == "table" then
      board[account] = { kills = tonumber(e.kills) or 0, deaths = tonumber(e.deaths) or 0, name = tostring(e.name or "Player") }
    end
  end
end

-- Text without control characters (a line of the board stays one line).
local function clean(text)
  return (tostring(text or ""):gsub("[%c]", " "))
end

-- A player's character name, or `fallback`.
local function name_of(world, entity, fallback)
  return players.name(world, entity, fallback)  -- core/players.lua: the character name first, as everywhere
end

-- The board's entry for `account` (made when it has none), with the newest name.
local function entry(account, name)
  local e = board[account]
  if not e then
    e = { kills = 0, deaths = 0, name = name }
    board[account] = e
  end
  if name and name ~= "" then e.name = name end
  return e
end

-- The board, best first (see the top).
local function ranked()
  local list = {}
  for account, e in pairs(board) do
    if e.kills > 0 or e.deaths > 0 then list[#list + 1] = { account = account, kills = e.kills, deaths = e.deaths, name = e.name } end
  end
  table.sort(list, function(a, b)
    if a.kills ~= b.kills then return a.kills > b.kills end
    if a.deaths ~= b.deaths then return a.deaths < b.deaths end
    return a.name:lower() < b.name:lower()
  end)
  return list
end
F.ranked = ranked

-- The lines for the player with this account (their own row marked). Equal kills and deaths share a rank.
local function lines_for(list, account)
  local out = {}
  local rank = 0
  for i, r in ipairs(list) do
    if i > MAX_ROWS then break end
    local prev = list[i - 1]
    if not prev or prev.kills ~= r.kills or prev.deaths ~= r.deaths then rank = i end
    out[#out + 1] = table.concat({ "r", tostring(rank), tostring(r.kills), tostring(r.deaths), r.account == account and "1" or "0", r.name }, "\t")
  end
  return table.concat(out, "\n")
end

local receive  -- forward: a player's game (below); the host's own game gets the board directly

-- Sends every player the ranked board with their own row marked (straight in for the host's own player).
local function send_all(world)
  local list = ranked()
  local me = emf.local_player()
  for _, id in ipairs(players.ids(world)) do
    local ok, account = pcall(world.account, world, id)
    if ok and account then
      local text = lines_for(list, tostring(account))
      if id == me and kit.is_host() then
        receive(world, text)
      else
        pcall(emf.net.send_to, world, id, CHANNEL, text)
      end
    end
  end
end

-- A player died (EMF, server world). Counted only when another player hit them last.
local function died(world, p)
  if type(p) ~= "table" or not p.player or p.player == 0 then return end
  local killer = tonumber(p.killer) or 0
  if killer == 0 or killer == p.player then return end
  local okk, killer_account = pcall(world.account, world, killer)
  if not okk or not killer_account then return end  -- a monster, a duelist, a trap: not on the PvP board
  local okv, victim_account = pcall(world.account, world, p.player)
  victim_account = okv and victim_account or p.account
  if not victim_account then return end
  load_board()
  -- (0.15.112) both by the one name function: EMF's p.name is the connection (account) name, only a last resort
  local reported = type(p.name) == "string" and p.name ~= "" and clean(p.name) or nil
  local killer_name, victim_name = name_of(world, killer), name_of(world, p.player, reported)
  local k = entry(tostring(killer_account), killer_name)
  local v = entry(tostring(victim_account), victim_name)
  k.kills = k.kills + 1
  v.deaths = v.deaths + 1
  kit.store.save("leaderboard", board)
  changed = true
  emf.log(string.format("leaderboard: %s killed %s (%d kills; %d deaths)", killer_name, victim_name, k.kills, v.deaths))
  local okc, chat = pcall(require, "features.chat")
  -- (0.15.134, owner) red in Messages, and the same line in everyone's Notices window; (0.15.136, owner) red there too,
  -- for 2 minutes so everyone sees it
  if okc and chat.announce then
    chat.announce(world, string.format("%s brutally murdered %s in PvP.", killer_name, victim_name), "#ff4040",
      { colour = "#ff4040", seconds = 120 })
  end
end
F.died = died

-- Every server step: sends the board when it changed, and every 30 s.
function F.tick(world)
  steps = steps + 1
  load_board()
  if changed or steps % 1800 == 0 then  -- 30 s at 60 steps a second
    changed = false
    send_all(world)
  end
end

-- ---- a player's game ----

local written = nil
local heard = false
local client_steps = 0
local fake = false         -- (0.15.116) the Debug section's test data is shown instead of the server's board
local real_text = nil      -- the server's last board, kept while the test data is shown

-- Writes ui_board.dat for FlameKit Native when it changed.
local function write(text)
  if text == written then return end
  local f = io.open(emf.dir .. "\\ui_board.dat", "w")
  if not f then
    kit.debug("warn", "leaderboard: ui_board.dat could not be written")
    return
  end
  f:write(text)
  f:close()
  written = text
end

-- (0.15.116, owner) Made-up players for seeing the board with data: a dozen, short and long names, ties (shared ranks),
-- big numbers, your own row in the middle. Only in this game.
local FAKE = {
  { 1, 42, 3, 0, "Thornwick" }, { 2, 37, 9, 0, "Lady Ashenvale the Unyielding" }, { 3, 21, 4, 0, "Mo" },
  { 4, 21, 7, 0, "Brakkus" }, { 5, 15, 15, 1, "You (test)" }, { 6, 12, 2, 0, "Sylvie" }, { 6, 12, 2, 0, "Fennick" },
  { 8, 8, 20, 0, "Grimble Stonefoot" }, { 9, 3, 1, 0, "Quill" }, { 10, 1, 1234, 0, "Unlucky Larry" },
  { 11, 0, 7, 0, "Pacifist Pete" }, { 12, 0, 99, 0, "Ve" },
}
-- The test board (FAKE) in the server's format.
local function fake_text()
  local lines = {}
  for _, r in ipairs(FAKE) do lines[#lines + 1] = table.concat({ "r", r[1], r[2], r[3], r[4], r[5] }, "\t") end
  return table.concat(lines, "\n")
end

-- The player's game: a board from the server (kept while the test board is shown), written for FlameKit Native.
receive = function(world, text)
  if type(text) ~= "string" or #text > 12000 then return end
  heard = true
  if text ~= fake_text() then
    real_text = text  -- the server's board: kept, so switching the test data off shows it again at once
    if fake then return end  -- it waits while the test data is shown
  end
  local lines = {}
  for line in text:gmatch("[^\n]+") do
    if line:match("^r\t%d+\t%d+\t%d+\t[01]\t") then lines[#lines + 1] = line end
  end
  write("source server\n" .. (#lines > 0 and (table.concat(lines, "\n") .. "\n") or "") .. "end\n")
end

-- Whether the test board is shown.
function F.fake_on() return fake end

-- Shows the test board, or the server's board again.
function F.set_fake(world, on)
  if on == fake then return end
  if on then
    fake = true
    receive(world, fake_text())
  else
    fake = false
    if real_text then
      receive(world, real_text)
    else
      write("source none\nend\n")  -- no board from the server yet
    end
  end
  kit.debug("info", "leaderboard: test data %s", on and "on" or "off")
end

-- The player's game: says "no board" when nothing came from a server after 20 s.
function F.client_tick(world)
  client_steps = client_steps + 1
  -- nothing from a server half after 20 s: say so (a server without FlameKit, or an older one)
  if not heard and client_steps == 1200 then write("source none\nend\n") end
end

-- Opens the board's channel and listens for player deaths (kills and deaths count in PvP).
function F.setup(k)
  kit = k
  players.setup(kit)
  local ok = emf.net.channel(CHANNEL, {
    version = 1, to = "players", max = 12000, per_10s = 30,
    on_player = kit.guard(F, function(world, from, data) receive(world, data) end, "the PvP Leaderboard from the server"),
  })
  if not ok then kit.debug("warn", "leaderboard: the channel flamekit/board was refused: no PvP Leaderboard") end
  -- EMF needs this in the script's first run (lua.md); it is only called on the server world
  local okd = pcall(emf.on_player_died, kit.guard(F, died, "a player's death"))
  if not okd then emf.log("leaderboard: emf.on_player_died is not there: PvP kills are not counted") end
  -- someone joined: send the board soon (EMF reports joins about 1 s after the world data)
  pcall(emf.on_player_joined, function() changed = true end)
  pcall(emf.command, "board_reset", "clears the PvP Leaderboard (every player's kills and deaths)",
    kit.guard(F, function(world)
      load_board()
      board = {}
      kit.store.save("leaderboard", board)
      changed = true
      emf.log("leaderboard: cleared")
      emf.reply("PvP Leaderboard cleared")
    end, "the board_reset command"))
end

return F
