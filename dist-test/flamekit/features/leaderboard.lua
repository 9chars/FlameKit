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

local function load_board()
  if board then return end
  board = {}
  for account, e in pairs(kit.store.load("leaderboard", {})) do
    if type(e) == "table" then
      board[account] = { kills = tonumber(e.kills) or 0, deaths = tonumber(e.deaths) or 0, name = tostring(e.name or "Player") }
    end
  end
end

local function clean(text)
  return (tostring(text or ""):gsub("[%c]", " "))
end

local function name_of(world, entity)
  for _, how in ipairs({ "name", "character_name" }) do  -- the order the party window uses (the same colour)
    local ok, name = pcall(world[how], world, entity)
    if ok and type(name) == "string" and name ~= "" then return clean(name) end
  end
  return "Player"
end

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
  local killer_name, victim_name = name_of(world, killer), clean(p.name ~= "" and p.name or name_of(world, p.player))
  local k = entry(tostring(killer_account), killer_name)
  local v = entry(tostring(victim_account), victim_name)
  k.kills = k.kills + 1
  v.deaths = v.deaths + 1
  kit.store.save("leaderboard", board)
  changed = true
  emf.log(string.format("leaderboard: %s killed %s (%d kills; %d deaths)", killer_name, victim_name, k.kills, v.deaths))
  local okc, chat = pcall(require, "features.chat")
  if okc and chat.announce then chat.announce(world, string.format("PvP: %s killed %s.", killer_name, victim_name)) end
end
F.died = died

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

receive = function(world, text)
  if type(text) ~= "string" or #text > 12000 then return end
  heard = true
  local lines = {}
  for line in text:gmatch("[^\n]+") do
    if line:match("^r\t%d+\t%d+\t%d+\t[01]\t") then lines[#lines + 1] = line end
  end
  write("source server\n" .. (#lines > 0 and (table.concat(lines, "\n") .. "\n") or "") .. "end\n")
end

function F.client_tick(world)
  client_steps = client_steps + 1
  -- nothing from a server half after 20 s: say so (a server without FlameKit, or an older one)
  if not heard and client_steps == 1200 then write("source none\nend\n") end
end

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
