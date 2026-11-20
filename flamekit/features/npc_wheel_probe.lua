-- npc_wheel_probe.lua (2026-11-17, owner: "I want to move away from windows panels and buttons ... move my interactions
-- more into the game"). Companion test code (since 0.15.278 in the release, owner 2026-11-18: keep what we added; it
-- does nothing on a server without the companion code): when he presses E on one of his NPCs the
-- local test server sends "open the wheel" on the channel flamekit/npcwheel; this opens EMF's radial wheel on his
-- screen and sends his pick back. The server decides everything (who may, what happens).
local F = { id = "npc_wheel_probe", title = "NPC Wheel Probe" }

local CHANNEL = "npcwheel"

local function log(s) emf.log("[flamekit] npc wheel: " .. s) end

local kit  -- set in F.setup

local function on_message(world, from, data)
  local okd, m = pcall(emf.json.decode, data)
  -- (owner 2026-11-18 07:30: "that one needs to stay on the screen until the condition is cleared... same with the
  -- Companion death") a status notice from the server: shown until the server takes it back (no time limit)
  if okd and type(m) == "table" and m.op == "status" and type(m.tag) == "string" and kit then
    if m.clear then kit.notice(m.tag, nil) else kit.notice(m.tag, tostring(m.text or ""), m.colour) end
    log("status " .. m.tag .. ": " .. (m.clear and "cleared" or tostring(m.text)))
    return
  end
  if not (okd and type(m) == "table" and m.op == "wheel" and type(m.labels) == "table") then return end
  local labels = m.labels
  local opened = emf.wheel(m.title or "Companion", labels, "", function(w, choice)
    log("picked " .. tostring(choice) .. " (" .. tostring(choice and labels[choice]) .. ")")
    if not choice then return end
    local oks, sent = pcall(emf.net.send, CHANNEL, emf.json.encode({ op = "pick", npc = m.npc, choice = choice,
      label = labels[choice] }))
    if not (oks and sent) then log("the pick was not sent: " .. tostring(sent)) end
  end)
  log("wheel for " .. tostring(m.npc) .. " opened: " .. tostring(opened))
end

-- (owner 13:03: "make a button on the Experimental panel that just calls the players assigned pet") the Experimental
-- panel asks for these rows (a TEMPORARY hook in experimental.lua) and sends clicks on "npc:" keys here
function F.panel_rows(world)
  return { { button = "npc:call", text = "Call my companion",
    tooltip = "Brings your companion to you and has it follow you (put away or far away: it comes back next to you)." },
    { button = "npc:roster", text = "Companion Roster", same_line = true,
      tooltip = "Opens or closes the Companion Roster window: every companion on this server, to rename, change, give, share or put away." },
    { separator = true } }
end

-- ---- the Companion Roster window (0.15.309, owner 2026-11-20 10:00) ----
-- "Companion Roster needs to be its own complete window", opened by the button above (the DLL shows and hides it when
-- ui_roster_toggle.request appears). The server keeps the roster: this asks it ({op = "get"} on flamekit/roster), shows
-- what it sends ({op = "roster", list, players}) as rows (features/native_ui.lua writes them for the DLL) and sends
-- each action ({op = "do", what, name, arg}); the server's answer ({op = "result", text, ok}) is the line at the top.
local ROSTER = "roster"
local ros = { list = nil, players = {}, result = nil, ok = true, confirm = {}, asked = nil }

local function roster_send(m)
  local oks, sent = pcall(emf.net.send, ROSTER, emf.json.encode(m))
  if not (oks and sent) then log("roster: not sent: " .. tostring(sent)) end
  return oks and sent
end

local function on_roster(world, from, data)
  local okd, m = pcall(emf.json.decode, data)
  if not (okd and type(m) == "table") then return end
  if m.op == "roster" and type(m.list) == "table" then
    ros.list, ros.players = m.list, type(m.players) == "table" and m.players or {}
  elseif m.op == "result" then
    ros.result, ros.ok = tostring(m.text or ""), m.ok and true or false
    log("roster: " .. ros.result)
  end
end

local function kind_of(guid)
  for _, m in ipairs(require("core.monsters")) do if m[3] == guid then return m end end
end

local function player_name(acc)
  for _, p in ipairs(ros.players) do if p.a == acc then return p.n end end
  return acc or "nobody"
end

function F.roster_rows(world)
  local rows = {}
  -- (0.15.310, owner 10:47 "how do I add a new entry?") a new companion: a hound of yours, next to you, following you
  rows[#rows + 1] = { button = "ros:new:", text = "New companion",
    tooltip = "Makes a new companion (a hound) next to you that follows you; rename it, change its kind or give it away below." }
  if ros.result then rows[#rows + 1] = { text = ros.result, color = ros.ok and "#7fd67f" or "#ff9050" } end
  if not ros.list then
    rows[#rows + 1] = { text = "Asking the server for the roster... (a server without the companion code does not answer)", dim = true }
    return rows
  end
  if #ros.list == 0 then rows[#rows + 1] = { text = "No companions on this server yet.", dim = true } end
  local t = world:tick()
  for _, c in ipairs(ros.list) do
    local k = kind_of(c.k)
    rows[#rows + 1] = { separator = true }
    rows[#rows + 1] = { heading = c.n .. "   " .. (k and (k[2] .. " (" .. k[1] .. ")") or "unknown kind") }
    local shared = {}
    for _, a in ipairs(c.c or {}) do if a ~= c.o then shared[#shared + 1] = player_name(a) end end
    local facts = { "Owner: " .. player_name(c.o ~= "" and c.o or nil), c.m == "stay" and "Stays" or "Follows",
      c.out and "Out" or "Put away", c.f or "Passive", (c.it or 0) .. " item" .. ((c.it or 0) == 1 and "" or "s") }
    if c.ch then facts[#facts + 1] = "Chest open" end
    if c.main then facts[#facts + 1] = "Main companion" end
    rows[#rows + 1] = { text = table.concat(facts, "  \u{00B7}  ") .. (#shared > 0 and ("\nShared with: " .. table.concat(shared, ", ")) or ""), dim = true }
    rows[#rows + 1] = { label = true, text = "Name" }
    rows[#rows + 1] = { edit = "ros:rename:" .. c.n, text = c.n, same_line = true,
      tooltip = "Click, type a new name (up to 20 letters, digits, spaces, - _ ' .) and press Enter. Esc cancels." }
    -- the kinds: every monster that is not a boss, by group
    local kinds, group = {}, nil
    for _, m in ipairs(require("core.monsters")) do
      if not m[4] then
        if m[1] ~= group then
          group = m[1]
          kinds[#kinds + 1] = { text = group, heading = true }
        end
        kinds[#kinds + 1] = { text = m[2], key = "ros:kind:" .. c.n .. ":" .. m[3], selected = m[3] == c.k }
      end
    end
    rows[#rows + 1] = { label = true, text = "Kind", same_line = true }
    rows[#rows + 1] = { options = kinds, text = k and k[2] or "unknown", same_line = true,
      tooltip = "What he is: any monster that is not a boss. A body that is out is replaced at once." }
    local give, share, unshare = {}, {}, {}
    for _, p in ipairs(ros.players) do
      local name = p.n .. (p.on and " (online)" or "")
      if p.a ~= c.o then give[#give + 1] = { text = name, key = "ros:give:" .. c.n .. ":" .. p.a } end
      local has = false
      for _, a in ipairs(c.c or {}) do if a == p.a then has = true end end
      if not has then share[#share + 1] = { text = name, key = "ros:share:" .. c.n .. ":" .. p.a } end
      if has and p.a ~= c.o then unshare[#unshare + 1] = { text = name, key = "ros:unshare:" .. c.n .. ":" .. p.a } end
    end
    rows[#rows + 1] = { options = give, text = "Give to...", disabled = #give == 0,
      tooltip = "Makes that player his only owner (also when they are offline); he becomes their main companion." }
    rows[#rows + 1] = { options = share, text = "Share with...", same_line = true, disabled = #share == 0,
      tooltip = "That player can command him too." }
    rows[#rows + 1] = { options = unshare, text = "Unshare...", same_line = true, disabled = #unshare == 0,
      tooltip = "That player can no longer command him." }
    rows[#rows + 1] = { button = "ros:main:" .. c.n, text = c.main and "Main companion" or "Set as main", selected = c.main,
      disabled = c.main or c.o == "", tooltip = "His owner's main companion: the one Call my companion (P) brings." }
    rows[#rows + 1] = { button = (c.out and "ros:away:" or "ros:back:") .. c.n, text = c.out and "Put away" or "Bring back",
      same_line = true, tooltip = c.out and "His body goes; he stays on the roster with his items." or
        "He comes back next to you, facing your way: a follower follows you, a stayer stays there." }
    local armed = ros.confirm[c.n] and t - ros.confirm[c.n] < 300
    rows[#rows + 1] = { button = "ros:delete:" .. c.n, text = armed and "Click again to delete" or "Delete", same_line = true,
      color = "#ff7060", tooltip = "Removes him for good (refused while his chest is open or he carries items)." }
  end
  return rows
end

function F.roster_click(world, key, typed)
  local what, name, arg = tostring(key):match("^ros:(%a+):([^:]*):?(.*)$")
  if not what then return end
  if what == "delete" then  -- two clicks within 5 s
    local t = world:tick()
    if not (ros.confirm[name] and t - ros.confirm[name] < 300) then
      ros.confirm[name] = t
      return
    end
    ros.confirm[name] = nil
  end
  if what == "rename" then
    if not typed then return end
    arg = typed
  end
  ros.result = nil
  roster_send({ op = "do", what = what, name = name, arg = arg ~= "" and arg or nil })
end

local function send_call(why)
  local oks, sent = pcall(emf.net.send, CHANNEL, emf.json.encode({ op = "call" }))
  log("call sent (" .. why .. "): " .. tostring(oks and sent))
end

function F.click(world, key)
  if key == "npc:call" then send_call("button") end
  if key == "npc:roster" then  -- the Companion Roster window: the DLL shows or hides it; the roster is asked for again
    local f = emf.dir and io.open(emf.dir .. "\\ui_roster_toggle.request", "w")
    if f then f:write("toggle\n") f:close() end
    roster_send({ op = "get" })
    log("roster: window toggled, roster asked for")
  end
end

function F.setup(k)
  kit = k
  local ok = emf.net.channel(CHANNEL, { version = 1, to = "both", max = 1024, per_10s = 60,
    on_player = function(world, from, data)
      local okm, err = pcall(on_message, world, from, data)
      if not okm then log("failed: " .. tostring(err)) end
    end,
    on_server = function() end })
  log("channel: " .. tostring(ok))
  local okr = emf.net.channel(ROSTER, { version = 1, to = "both", max = 16384, per_10s = 60,
    on_player = function(world, from, data)
      local okm, err = pcall(on_roster, world, from, data)
      if not okm then log("roster: failed: " .. tostring(err)) end
    end,
    on_server = function() end })
  log("roster channel: " .. tostring(okr))
  -- (owner 2026-11-18 07:06: "a key binding on P and make that action call the companion") the same as the
  -- "Call my companion" button, on the client world
  local okk, errk = pcall(emf.on_key, "P", function(world) send_call("P key") end, "client")
  log("P key: " .. tostring(okk and errk ~= false or errk))
end

return F
