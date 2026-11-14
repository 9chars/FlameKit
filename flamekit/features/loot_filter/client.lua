-- features/loot_filter/client.lua: the half in your own game.
--
-- It keeps your junk list (junk_list.json in the mod's folder, the same for every world and server), gives FlameKit's
-- window (features/native_ui.lua) what to show, and tells the server half what you want: your list and options
-- ("sync") and "dump".
-- In a world you host the server half is in this same game and is called directly; on a server you joined the
-- messages go over EMF's mod messages (the channel flamekit/lf), which needs FlameKit on that server too.

local C = {}

local kit, items, bag, server

local FILE = "junk_list"
local JUNK_RED = "#ff4a3d" -- the colour of junk messages
local RESEND_STEPS = 3600  -- your list is sent again about once a minute (a message can be lost)

local junk = {}            -- debug name -> true: the list as it is saved
local junk_ids = {}        -- item id -> debug name, for the names the game knows
local resolved = false
local dirty = true         -- the server half has not got the list and options as they are now
local last_peer = nil      -- the joined server's channel version as last seen (0: it has no FlameKit)
local since_sync = 0
local auto_loot = nil      -- the game's auto loot setting as the server reports it (nil: not known yet)
local warning_shown = false
local for_host = {}        -- in a world this game hosts: requests made on the client world (FlameKit's window), handed to
                           -- the server half on the server world's next step (C.server_tick)

-- The game calls its auto loot setting "Auto-Collect Scattered Loot". The banner: one red message in FlameKit's
-- Messages window (kit.note), at most once a minute.
local AUTO_LOOT_BANNER = { "FlameKit Junk List: dropped junk is coming back into your bag.",
                           "Turn OFF \"Auto-Collect Scattered Loot\" in the game settings." }
-- The warning line in FlameKit's window (the Auto Junk List's view), shown as long as the problem is there.
local AUTO_LOOT_WARNING = "\"Auto-Collect Scattered Loot\" is on in the game's settings: dropped junk comes straight back "
  .. "into your bag. Turn it off, or set Drop / Delete to Delete."

-- True while junk is to be dropped and the game's auto loot would take it straight back.
local function auto_loot_problem()
  return auto_loot == true and emf.setting("lf_action") ~= "delete" and emf.setting("lf_enabled") ~= false
end

-- The banner: a red message, at most once a minute (FlameKit's Messages window keeps it in its list).
local banner_at = 0

local function banner()
  if os.time() < banner_at then return end
  kit.note(table.concat(AUTO_LOOT_BANNER, " "), "#ff5a50", true)
  banner_at = os.time() + 60
end

local function refresh_warning()
  local show = auto_loot_problem()
  if show == warning_shown then return end
  warning_shown = show
  if show then banner() end
end

-- ---- the list ----

local function sorted_names()
  local names = {}
  for name in pairs(junk) do names[#names + 1] = name end
  table.sort(names)
  return names
end

-- The setting lf_show_all: every item in the bag can be put on the junk list, also weapons, armour, rings, tools,
-- summoning items, trophies and pieces of gear (items.is_keeper, stack.gear). Off (the default), those are never junk:
-- they are not offered, and if one is on the list (put there while it was on) it is left alone.
local function show_all()
  return kit.setting("lf_show_all", false) == true
end

local function load_list()
  junk = {}
  local data = kit.store.load(FILE, {})
  local list = type(data.items) == "table" and data.items or {}
  for _, name in ipairs(list) do
    if type(name) == "string" and name ~= "" then junk[name] = true end
  end
  resolved = false
end

local function save_list()
  kit.store.save(FILE, { version = 1, items = sorted_names() })
end

local function set_junk(name, on)
  kit.debug("info", "junk list (client): %s %s", on and "junk" or "keep", tostring(name))
  if on and items.is_keeper(name) and not show_all() then return end  -- weapons, armour, rings, tools, ...: kept
  if on and not junk[name] and #sorted_names() >= server.MAX_ITEMS then
    kit.note("Auto Junk List: your junk list is full (" .. server.MAX_ITEMS .. " items).", "#ff9050", true)
    return
  end
  junk[name] = on and true or nil
  resolved = false
  dirty = true
  save_list()
end

-- Needs a world (item lookups): call inside callbacks.
local function resolve()
  if resolved then return end
  junk_ids = {}
  for name in pairs(junk) do
    local id = items.id(name)
    if id then junk_ids[id] = name end
  end
  resolved = true
end

local function options()
  return {
    auto = emf.setting("lf_auto") == true,
    action = emf.setting("lf_action") == "delete" and "delete" or "drop",
    keep_hotbar = emf.setting("lf_keep_hotbar") ~= false,
    show_all = show_all(),
  }
end

-- ---- talking to the server half ----

-- "host": the world runs in this game. "server": a joined server that has FlameKit. nil: a joined server without it.
local function link(world)
  if world:is_server() then return "host" end
  if kit.is_host() then return "host" end
  local ok, version = pcall(emf.net.peer, nil, 0, server.CHANNEL)
  if ok and version and version ~= 0 then return "server" end
  return nil
end

-- For the FlameKit label: false on a joined server that has no FlameKit (or has not greeted this game yet).
function C.connected(world)
  return link(world) ~= nil
end

-- Sends `msg` to the server half. True when it went.
local function request(world, msg)
  if world:is_server() then
    local player = emf.local_player()
    if not player or player == 0 then return false end
    local ok, account = pcall(world.account, world, player)
    if not ok or not account then return false end
    return server.handle(world, { player = player, account = account }, msg) == true
  end
  if kit.is_host() then  -- clicked on the client world (FlameKit's window): the server world's next step takes it
    if #for_host < 16 then for_host[#for_host + 1] = msg end
    return true
  end
  local text = emf.json.encode(msg)
  if not text or #text > 16000 then
    emf.log("an Auto Junk List message was too long to send (" .. tostring(text and #text) .. " bytes)")
    return false
  end
  local ok, sent = pcall(emf.net.send, server.CHANNEL, text)
  return ok and sent == true
end

local function sync(world)
  local names = sorted_names()
  if request(world, { op = "sync", items = names, opts = options() }) then
    dirty = false
    since_sync = 0
    kit.debug("debug", "junk list (client): sent the list to the server half: %d item(s), auto %s, %s", #names,
      tostring(emf.setting("lf_auto") == true), emf.setting("lf_action") == "delete" and "delete" or "drop")
  else
    kit.debug("debug", "junk list (client): the list could not be sent yet (tried again)")
  end
end

-- A message from the server half (also called directly in a world you host).
function C.receive(world, msg)
  if type(msg) ~= "table" then return end
  kit.debug("debug", "junk list (client): from the server half: %s", tostring(msg.op))
  if msg.op == "done" and type(msg.total) == "number" then
    kit.note(server.summary(msg), JUNK_RED)
    if msg.action == "drop" and auto_loot_problem() then banner() end  -- each time junk is dropped into auto loot (once a minute at most)
  elseif msg.op == "autoloot" then
    auto_loot = msg.on == true
    refresh_warning()
  elseif msg.op == "info" and type(msg.text) == "string" then
    kit.note(msg.text, nil, true)
  elseif msg.op == "list" and type(msg.items) == "table" then  -- the chat command changed your list
    junk = {}
    for _, name in ipairs(msg.items) do
      if type(name) == "string" and name ~= "" then junk[name] = true end
    end
    resolved = false
    save_list()
  end
end

-- The button and the key: remove the junk in your bag now.
local function dump(world)
  local where = link(world)
  if not where then
    kit.note("Auto Junk List: this server does not run FlameKit, so nothing can be removed here.", "#ff9050", true)
    return
  end
  if dirty then sync(world) end
  if not request(world, { op = "dump" }) then kit.note("Auto Junk List: the server could not be reached.", "#ff9050", true) end
end

-- ---- the feature's callbacks (init.lua hands them on) ----

function C.setup(k, F, s)
  kit, items, bag, server = k, k.items, k.bag, s
  load_list()
  emf.on_key("lf_dump_key", kit.guard(F, function(world)
    dump(world)
  end, "the dump key"))
end

-- A step of the world this game hosts: the server half is right here.
function C.server_tick(world)
  if emf.local_player() == 0 then return end  -- a dedicated server: nobody plays in this game
  since_sync = since_sync + 1
  if dirty then sync(world) end
  local waiting = for_host
  for_host = {}
  for _, msg in ipairs(waiting) do request(world, msg) end
end

-- A step of your own screen's world. On a joined server: say hello with your list once the server has greeted this
-- game, after every change, and now and then again.
function C.client_tick(world)
  if kit.is_host() then return end
  local ok, version = pcall(emf.net.peer, nil, 0, server.CHANNEL)
  version = ok and version or 0
  if version ~= last_peer then
    last_peer = version
    dirty = true
  end
  since_sync = since_sync + 1
  if since_sync >= RESEND_STEPS then dirty = true end
  if dirty and version ~= 0 and since_sync >= 30 then sync(world) end  -- at most twice a second
end

function C.setting_changed(key)
  if key:sub(1, 3) == "lf_" then
    dirty = true
    refresh_warning()
  end
end

local function removable(stack)
  if not junk_ids[stack.item] then return false end
  if stack.hotbar and emf.setting("lf_keep_hotbar") then return false end
  if not show_all() and (stack.gear or items.is_keeper(junk_ids[stack.item])) then return false end
  return true
end

-- Lays chips out left to right: line(text) says whether the next chip still fits on the running line. EMF gives no
-- text widths, so a chip's width is estimated from its length, on the safe side (in text heights).
-- What in the bag can be put on the junk list, one entry per item ({item, count, name, debug_name}), sorted by name;
-- how many stacks of junk are in it now; how many stacks are never junk (not listed); and false when the bag cannot
-- be read. FlameKit's window shows this (C.ui_lists).
local function bag_list(world)
  resolve()
  local by_item, list, junk_stacks, kept = {}, {}, 0, 0
  local stacks, readable = bag.stacks(world, emf.local_player())
  for _, stack in ipairs(stacks) do
    local debug_name = items.debug_name(stack.item)
    if not show_all() and (stack.gear or items.is_keeper(debug_name)) then
      kept = kept + 1  -- gear, tools, summoning items: never junk, so not listed
    else
      local e = by_item[stack.item]
      if not e then
        e = { item = stack.item, count = 0, name = items.name(stack.item), debug_name = debug_name }
        by_item[stack.item] = e
        list[#list + 1] = e
      end
      e.count = e.count + stack.count
      if removable(stack) then junk_stacks = junk_stacks + 1 end
    end
  end
  table.sort(list, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.item < b.item
  end)
  return list, junk_stacks, kept, readable
end

-- ---- FlameKit's own window (features/native_ui.lua) ----

-- What the window shows. bag: the items you carry that are not junk and can be ({item, count, debug_name, name});
-- junk: the junk list ({item or nil when the game does not know the name, count you carry, debug_name, name}); both
-- sorted by name; opts: auto (true/false), action ("drop"/"delete"). nil when the bag cannot be read.
function C.ui_lists(world)
  local list, _, _, readable = bag_list(world)
  if not readable then return nil end
  local in_bag, carried = {}, {}
  for _, e in ipairs(list) do
    if e.debug_name then
      if junk[e.debug_name] then
        carried[e.debug_name] = e.count
      else
        in_bag[#in_bag + 1] = { item = e.item, count = e.count, debug_name = e.debug_name, name = e.name }
      end
    end
  end
  local shown = {}
  for i, name in ipairs(sorted_names()) do
    shown[i] = { debug_name = name, item = items.id(name), name = items.name(name), count = carried[name] or 0 }
  end
  table.sort(shown, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.debug_name < b.debug_name
  end)
  local opts = options()
  return in_bag, shown, { auto = opts.auto, action = opts.action }
end

-- The warning FlameKit's window shows over the bag (red), or nil: junk is dropped while the game's auto loot is on.
function C.ui_warning()
  return auto_loot_problem() and AUTO_LOOT_WARNING or nil
end

-- A click in FlameKit's own window: put the item on the junk list (on = true) or take it off.
function C.ui_set(world, debug_name, on)
  if type(debug_name) ~= "string" or debug_name == "" then return end
  set_junk(debug_name, on)
  refresh_warning()
  if dirty then sync(world) end
end

-- Dump Junk in FlameKit's own window.
function C.ui_dump(world)
  dump(world)
end

-- Auto (on/off) and Drop/Delete in FlameKit's own window.
function C.ui_option(world, key, value)
  if key == "auto" then
    emf.set_setting("lf_auto", value == "1")
  elseif key == "action" and (value == "drop" or value == "delete") then
    emf.set_setting("lf_action", value)
  else
    return
  end
  dirty = true
  refresh_warning()
  sync(world)
end

return C
