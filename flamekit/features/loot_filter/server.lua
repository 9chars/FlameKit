-- features/loot_filter/server.lua: the half that changes inventories.
--
-- It runs wherever the world is hosted: your own game (single-player, friends joined) or a dedicated server. It keeps
-- one junk list per player account and removes that player's junk when they loot it or ask for a dump.
--
-- A player's list comes from their own game (a "sync" message from client.lua) or from the chat command, and is kept
-- with the world (emf.save_player_data), so it is there again when they join, before their game has said hello.
--
-- How a removal runs: the player's bag is read, every junk stack is queued, and a few stacks per step are taken out
-- with emf.take from exactly their slot (the game's own inventory transaction; a stack that moved meanwhile is
-- skipped). A taken stack that is not handed on is gone; "drop" hands it to emf.give, which makes a loose pickup.
--
-- Dropping: a loose pickup is what mining and harvesting leave, and with the game's auto loot on the game collects it
-- again within a tenth of a second (seen in game). A mod cannot switch that off, but the server knows each player's
-- auto loot setting (PlayerInput.fromClientSettings.flags, bit 12: checked in game), so the player's own game is told
-- and warns them (client.lua).

local S = {}

local kit, items, bag

local PER_STEP = 4       -- stacks taken per player and server step
local SETTLE_STEPS = 3   -- steps between a pickup and the removal (the stack has to be in the bag first)
S.MAX_ITEMS = 400        -- names on one player's list (a player's saved text may be 16 KiB)
local AUTO_LOOT_BIT = 12  -- ClientPlayerSettings.flags: auto collect loose loot

local players = {}       -- account -> the player's state (below)
local by_entity = {}     -- player entity -> account, in this session
local own_drops = {}     -- pickup entity -> {item, left}: what this mod dropped is not junk when picked up again
local now = 0            -- server steps
local session = nil

S.to_local = nil         -- set by init.lua: function(world, msg) for the player whose game hosts the world
S.CHANNEL = "lf"

local function default_opts()
  return { auto = true, action = "drop", keep_hotbar = true, show_all = false }
end

local function new_state(account)
  return { account = account, junk = {}, ids = nil, opts = default_opts(), entity = 0,
           queue = {}, inflight = 0, inflight_since = 0, sweep_at = nil, again = false, tally = {}, auto_loot = nil }
end

-- ---- a player's state ----

local function clean_names(list)
  local junk, n = {}, 0
  if type(list) == "table" then
    for _, name in ipairs(list) do
      if type(name) == "string" and name ~= "" and #name <= 96 and not junk[name] and n < S.MAX_ITEMS then
        -- (a kept kind on the list stays on it: it is only removed while the player's show_all is on: removable)
        junk[name] = true
        n = n + 1
      end
    end
  end
  return junk
end

local function clean_opts(o)
  local opts = default_opts()
  if type(o) == "table" then
    if type(o.auto) == "boolean" then opts.auto = o.auto end
    if o.action == "drop" or o.action == "delete" then opts.action = o.action end
    if type(o.keep_hotbar) == "boolean" then opts.keep_hotbar = o.keep_hotbar end
    if type(o.show_all) == "boolean" then opts.show_all = o.show_all end  -- the player's lf_show_all
  end
  return opts
end

function S.names(st)
  local names = {}
  for name in pairs(st.junk) do names[#names + 1] = name end
  table.sort(names)
  return names
end

-- The state of the player with this account, read from the world's saved data the first time. nil while the world's
-- data has not come yet (right after a load).
local function state(account)
  if not account then return nil end
  local st = players[account]
  if st then return st end
  local ok, text = pcall(emf.player_data, account)
  if not ok or text == nil then return nil end
  st = new_state(account)
  if text ~= "" then
    local data = emf.json.decode(text)
    if type(data) == "table" then
      st.junk = clean_names(data.items)
      st.opts = clean_opts(data.opts)
    end
  end
  players[account] = st
  return st
end

local function save(st)
  local text = emf.json.encode({ items = S.names(st), opts = st.opts })
  local ok, saved = pcall(emf.save_player_data, st.account, text)
  if not ok or not saved then emf.log("the junk list of " .. tostring(st.account) .. " was not saved with the world") end
end

local function account_of(world, entity)
  if not entity or entity == 0 then return nil end
  local account = by_entity[entity]
  if account then return account end
  local ok, a = pcall(world.account, world, entity)
  if ok and a then
    by_entity[entity] = a
    return a
  end
  return nil
end

-- Needs a world (item lookups): call inside callbacks.
local function resolve(st)
  if st.ids then return end
  st.ids = {}
  for name in pairs(st.junk) do
    local id = items.id(name)
    if id then st.ids[id] = name end
  end
end

-- ---- telling the player ----

-- "Junk discarded: Twigs x30, Plant Fibre x7" (msg: {action, total, items = {{id, count}, ...}}, at most 3 kinds).
function S.summary(msg)
  local parts, named = {}, 0
  for _, pair in ipairs(msg.items or {}) do
    parts[#parts + 1] = items.name(pair[1]) .. " x" .. pair[2]
    named = named + pair[2]
  end
  local text = (msg.action == "drop" and "Junk dropped: " or "Junk discarded: ") .. table.concat(parts, ", ")
  if msg.total > named then text = text .. " and " .. (msg.total - named) .. " more" end
  return text
end

-- A message for the player's own game (client.lua): straight to it when it is this game, over EMF's mod messages
-- when it is a joined game with FlameKit, and as a chat line when the player has no FlameKit (`text` then).
local function send(world, st, msg, text)
  local player = st.entity
  if S.to_local and player ~= 0 and player == emf.local_player() then
    S.to_local(world, msg)
    return
  end
  if player == 0 then return end
  local ok, sent = pcall(emf.net.send_to, world, player, S.CHANNEL, emf.json.encode(msg))
  if ok and sent then return end
  if text then pcall(emf.tell, world, player, text, { system = true }) end
end

-- Tells the player's own game whether their auto loot is on (a player without FlameKit gets a chat line when it is on
-- and their junk is to be dropped).
local function tell_auto_loot(world, st)
  if st.auto_loot == nil then return end
  local text = nil
  if st.auto_loot and st.opts.action == "drop" then
    text = "FlameKit: dropped junk is coming back into your bag. Turn OFF \"Auto-Collect Scattered Loot\" in the game settings."
  end
  send(world, st, { op = "autoloot", on = st.auto_loot }, text)
end

-- ---- removing ----

local function removable(st, stack)
  if not st.ids[stack.item] then return false end
  if stack.hotbar and st.opts.keep_hotbar then return false end
  -- a piece with its own level and perks, and the kept kinds (weapons, armour, rings, tools, summoning items, trophies),
  -- are junk only while the player has switched on Show all bag items
  if not st.opts.show_all and (stack.gear or items.is_keeper(st.ids[stack.item])) then return false end
  return true
end

-- Queues every junk stack of the player's bag. Returns how many stacks, or nil while an earlier removal still runs.
local function sweep(world, st)
  if st.inflight > 0 or #st.queue > 0 then
    st.again = true
    return nil
  end
  resolve(st)
  for _, stack in ipairs(bag.stacks(world, st.entity)) do
    if removable(st, stack) then st.queue[#st.queue + 1] = stack end
  end
  return #st.queue
end

local function finish(world, st)
  local total, list = 0, {}
  for id, count in pairs(st.tally) do
    total = total + count
    if #list < 3 then list[#list + 1] = { id, count } end
  end
  st.tally = {}
  if total > 0 then
    local msg = { op = "done", action = st.opts.action, total = total, items = list }
    send(world, st, msg, S.summary(msg))
  end
  if st.again then
    st.again = false
    st.sweep_at = now + SETTLE_STEPS
  end
end

local function on_taken(world, st, stack, taken, action, run)
  if run ~= session then return end  -- an answer from the world before this one
  st.inflight = math.max(0, st.inflight - 1)
  if taken and taken > 0 then
    if action == "drop" then
      local pickup = emf.give(world, st.entity, stack.item, taken)
      if pickup and pickup ~= 0 then
        own_drops[pickup] = { item = stack.item, left = taken }
      else
        emf.put(world, st.entity, stack.item, taken)  -- it could not be dropped: back into the bag, nothing is lost
        taken = 0
      end
    end
    if taken > 0 then st.tally[stack.item] = (st.tally[stack.item] or 0) + taken end
  end
  if st.inflight == 0 and #st.queue == 0 then finish(world, st) end
end

local function pump(world, st)
  if #st.queue == 0 then return end
  local action, run = st.opts.action, session
  for _ = 1, PER_STEP do
    local stack = table.remove(st.queue, 1)
    if not stack then break end
    local asked = emf.take(world, stack.owner or st.entity, stack.item, stack.count, function(w, taken)
      on_taken(w, st, stack, taken, action, run)
    end, { slot = stack.slot, exact = true })
    if asked then
      if st.inflight == 0 then st.inflight_since = now end
      st.inflight = st.inflight + 1
    end
  end
  if st.inflight == 0 and #st.queue == 0 then finish(world, st) end
end

-- Remove the junk in the player's bag now. Returns a line when there is nothing to do.
local function dump(world, st)
  local n = sweep(world, st)
  if n == nil then return "The Auto Junk List is still busy with the last removal." end
  if n == 0 then return "No junk in your bag." end
  return nil
end

-- ---- what comes in ----

-- A message from a player's game. `from` = {player = entity, account = text}: who it is comes from the server's own
-- records, never from the message, so a player can only ever change their own list and their own bag. True when taken.
function S.handle(world, from, msg)
  if type(msg) ~= "table" or not from or not from.player or from.player == 0 then return false end
  local st = state(from.account)
  if not st then return false end  -- the world's saved data has not come yet: the sender tries again
  st.entity = from.player
  by_entity[from.player] = from.account
  kit.debug("debug", "junk list (server): %s from player entity %s", tostring(msg.op), tostring(from.player))
  if msg.op == "sync" then
    st.junk = clean_names(msg.items)
    st.opts = clean_opts(msg.opts)
    st.ids = nil
    save(st)
    tell_auto_loot(world, st)  -- a game that just said hello learns it at once
  elseif msg.op == "dump" then
    local why = dump(world, st)
    if why then send(world, st, { op = "info", text = why }, why) end
  end
  return true
end

-- The game's PickupEvent, once per pickup by anyone.
function S.on_pickup(world, e)
  if e.itemCount == 0 then return end
  local mine = own_drops[e.pickedUpFromEntityId]
  if mine and mine.item == e.itemId then  -- something this mod dropped is back in a bag: left alone (no loop)
    mine.left = mine.left - e.itemCount
    if mine.left <= 0 then own_drops[e.pickedUpFromEntityId] = nil end
    return
  end
  local st = state(account_of(world, e.pickedUpByEntityId))
  if not st or not st.opts.auto or next(st.junk) == nil then return end
  st.entity = e.pickedUpByEntityId
  resolve(st)
  if st.ids[e.itemId] then st.sweep_at = now + SETTLE_STEPS end
end

function S.tick(world)
  local s = emf.session()
  if s ~= session then  -- another world: entity ids and saved lists of the old one mean nothing
    session = s
    players, by_entity, own_drops = {}, {}, {}
  end
  now = now + 1
  for _, st in pairs(players) do
    if st.inflight > 0 and now - st.inflight_since > 600 then st.inflight = 0 end  -- an answer that never came (10 s)
    if st.sweep_at and now >= st.sweep_at then
      st.sweep_at = nil
      sweep(world, st)
    end
    if now % 60 == 0 and st.entity ~= 0 then  -- the player's auto loot setting, as their game sent it to the server
      local ok, input = pcall(world.get, world, "PlayerInput", st.entity)
      local flags = ok and input and input.fromClientSettings and input.fromClientSettings.flags
      if flags then
        local on = (flags >> AUTO_LOOT_BIT) & 1 == 1
        if on ~= st.auto_loot then
          st.auto_loot = on
          emf.log("auto loot of " .. tostring(st.account) .. ": " .. (on and "on" or "off"))
          tell_auto_loot(world, st)
        end
      end
    end
    pump(world, st)
  end
end

-- The chat and console command: /flamekit.junk add <item> ... It acts on whoever typed it, so players without FlameKit
-- in their own game can use the filter on a server that has it.
local function command(world, args)
  local who = emf.sender()
  local player, account
  if who and who.chat then
    player, account = who.entity, who.account
  else
    player = emf.local_player()
    account = account_of(world, player)
  end
  local st = player and player ~= 0 and state(account) or nil
  if not st then
    emf.reply("The Auto Junk List does not know which player you are (try again in a moment).")
    return
  end
  st.entity = player
  by_entity[player] = account

  local verb = (args[1] or "list"):lower()
  local text = table.concat(args, " ", 2)
  local changed = false
  if verb == "list" then
    local names = S.names(st)
    emf.reply(#names .. " item(s) on your junk list")
    for i, name in ipairs(names) do
      if i > 8 then
        emf.reply("... and " .. (#names - 8) .. " more")
        break
      end
      emf.reply("  " .. items.name(name) .. "  [" .. name .. "]")
    end
  elseif verb == "add" then
    local _, name = items.find(text)
    if not name then
      emf.reply("no item named \"" .. text .. "\": `items <part of the name>` lists names")
    elseif items.is_keeper(name) and not st.opts.show_all then
      emf.reply(items.name(name) .. " cannot be junk: weapons, armour, rings, tools and summoning items are always kept")
    elseif #S.names(st) >= S.MAX_ITEMS then
      emf.reply("your junk list is full (" .. S.MAX_ITEMS .. " items)")
    else
      st.junk[name] = true
      changed = true
      emf.reply(items.name(name) .. " is junk now")
    end
  elseif verb == "remove" then
    local _, name = items.find(text)
    if not name and st.junk[text] then name = text end
    if name and st.junk[name] then
      st.junk[name] = nil
      changed = true
      emf.reply(items.name(name) .. " is kept again")
    else
      emf.reply("\"" .. text .. "\" is not on your junk list")
    end
  elseif verb == "dump" then
    emf.reply(dump(world, st) or "removing the junk in your bag")
  elseif verb == "clear" then
    if (args[2] or "") ~= "yes" then
      emf.reply("this empties your whole junk list: type `junk clear yes` to do it")
    else
      st.junk = {}
      changed = true
      emf.reply("your junk list is empty")
    end
  else
    emf.reply("junk add <item> | junk remove <item> | junk list | junk dump | junk clear yes")
  end
  if changed then
    st.ids = nil
    save(st)
    send(world, st, { op = "list", items = S.names(st) })  -- the player's own game keeps its copy in step
  end
end

function S.setup(k, F)
  kit, items, bag = k, k.items, k.bag
  emf.on_event("PickupEvent", kit.guard(F, S.on_pickup, "PickupEvent"), "server")
  emf.on_world_data(function() end)  -- asks EMF for this world's saved data: the players' lists are kept beside it
  emf.on_player_left(kit.guard(F, function(world, p)
    players[p.account] = nil  -- the list stays saved with the world; what was running for them stops
    by_entity[p.player] = nil
  end, "a player leaving"))
  emf.command("junk", "<add|remove|list|dump|clear> <item>: your Auto Junk List",
    kit.guard(F, command, "the junk command"), { players = true })
end

return S
