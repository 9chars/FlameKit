-- features/loot_filter/client.lua: the half in your own game.
--
-- It keeps your junk list (junk_list.json in the mod's folder, the same for every world and server), draws the Loot
-- Filter tab of the panel, and tells the server half what you want: your list and options ("sync") and "dump".
-- In a world you host the server half is in this same game and is called directly; on a server you joined the
-- messages go over EMF's mod messages (the channel flamekit/lf), which needs FlameKit on that server too.

local C = {}

local kit, items, bag, server

local FILE = "junk_list"
local MAX_ROWS = 100       -- rows per list in the panel
local JUNK_RED = "#ff4a3d" -- junk in the panel: the list's heading and entries, and bag items that are on it
local RESEND_STEPS = 3600  -- your list is sent again about once a minute (a message can be lost)

local junk = {}            -- debug name -> true: the list as it is saved
local junk_ids = {}        -- item id -> debug name, for the names the game knows
local resolved = false
local dirty = true         -- the server half has not got the list and options as they are now
local last_peer = nil      -- the joined server's channel version as last seen (0: it has no FlameKit)
local since_sync = 0
local drawn_junk = {}      -- the junk rows of the panel as last drawn: index -> debug name
local auto_loot = nil      -- the game's auto loot setting as the server reports it (nil: not known yet)
local warning_shown = false

-- The game calls its auto loot setting "Auto-Collect Scattered Loot". The banner: one red message in FlameKit's
-- Messages window (kit.note), at most once a minute; the tab has room for one sentence.
local AUTO_LOOT_BANNER = { "FlameKit Junk List: dropped junk is coming back into your bag (drop failed).",
                           "Turn OFF \"Auto-Collect Scattered Loot\" in the game settings." }
local AUTO_LOOT_WARNING = "Turn OFF \"Auto-Collect Scattered Loot\" in the game settings: dropped junk comes back into your bag."

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
  if kit.is_host() then return false end  -- the server world of this game takes it on its own step
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
local GRID = 10  -- slots in a row of the bag grid (a slot is three text lines wide)

local function flow()
  local room = kit.hub.WIDTH - 3
  local used = 0
  return function(text)
    local need = #text * 0.56 + 1.6
    if used > 0 and used + need <= room then
      used = used + need
      return true
    end
    used = need
    return false
  end
end

-- What in the bag can be put on the junk list, one entry per item ({item, count, name, debug_name}), sorted by name;
-- how many stacks of junk are in it now; how many stacks are never junk (not listed); and false when the bag cannot
-- be read. The panel's tab and FlameKit's own window (C.ui_lists) both show this.
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

-- The Auto Junk List tab: the buttons, what is in your bag (click = junk or keep), and the whole list.
function C.panel(world)
  local rows = {}
  local where = link(world)
  local list, junk_stacks, kept, readable = bag_list(world)

  if not where then
    rows[#rows + 1] = { color = "#ffb060",
      text = "This server does not run FlameKit (or has not greeted your game yet): nothing can be removed here. "
        .. "You can still edit your list." }
  elseif where == "server" then
    rows[#rows + 1] = { text = "Connected to this server's FlameKit.", dim = true }
  end
  local drop = emf.setting("lf_action") ~= "delete"
  if auto_loot_problem() then rows[#rows + 1] = { text = AUTO_LOOT_WARNING, color = JUNK_RED } end
  rows[#rows + 1] = { button = "dump", text = "Dump junk now" .. (readable and (" (" .. junk_stacks .. ")") or ""),
    disabled = not where or (readable and junk_stacks == 0),
    tooltip = "Removes every stack of a junk item from your backpack now. Never weapons, armour, rings, tools or "
      .. "summoning items, and not the action bar (a setting)." }
  rows[#rows + 1] = { button = "auto", same_line = true, selected = emf.setting("lf_auto") == true,
    text = "On loot: " .. (emf.setting("lf_auto") and "ON" or "OFF"),
    tooltip = "ON: junk is removed as soon as you loot it. OFF: only when you press Dump junk now." }
  rows[#rows + 1] = { button = "action", same_line = true, text = drop and "Junk is dropped" or "Junk is deleted",
    tooltip = "Click to switch between dropping junk at your feet and deleting it for good. "
      .. "For dropping, turn off \"Auto-Collect Scattered Loot\" in the game settings: otherwise the game picks dropped junk back up." }

  -- Two blocks of "chips" (one button per item, as many on a line as fit): what is in the bag, then the junk list.
  -- A chip's colour is the item's quality (gear) or kind; a bag chip that is on the junk list is lit.
  rows[#rows + 1] = { separator = true }
  rows[#rows + 1] = { heading = "IN YOUR BAG (" .. #list .. ")", color = "#ffd27a" }
  if not readable then
    rows[#rows + 1] = { text = "Your bag cannot be read here. Add items with the chat command: /flamekit.junk add <item>",
      dim = true }
  elseif #list == 0 then
    rows[#rows + 1] = { text = "Your bag is empty.", dim = true }
  else
    rows[#rows + 1] = { text = "Click an item to put it on your junk list (lit = junk). Click it again to keep it.", dim = true }
  end
  if kept > 0 then
    rows[#rows + 1] = { text = "Not listed, because they are never junked: weapons, armour, rings, tools and summoning items.",
      dim = true }
  end
  local line = flow()
  for i, e in ipairs(list) do
    if i > MAX_ROWS then
      rows[#rows + 1] = { text = "... and " .. (#list - MAX_ROWS) .. " more", dim = true }
      break
    end
    local is_junk = e.debug_name ~= nil and junk[e.debug_name] == true
    local label = e.name  -- the name only: how many are carried is in the tooltip
    local tip = items.details(e.item, e.debug_name, e.count)
    table.insert(tip, 1, e.name)
    tip[#tip + 1] = is_junk and "ON YOUR JUNK LIST. Click to keep it." or "Click to put it on your junk list."
    if items.data(e.item) then
      -- a grid like the game's bag: the item's icon on its rarity's colour (its name until the picture is made)
      local icon = items.icon(e.item)
      rows[#rows + 1] = {
        slot = string.format("t:%x", e.item),
        text = icon and "" or label,
        icon = icon,
        same_line = (i - 1) % GRID ~= 0,
        selected = is_junk,
        color = items.color(e.debug_name, e.item),
        disabled = e.debug_name == nil,
        tooltip = table.concat(tip, "\n"):sub(1, 500),
      }
    else
      rows[#rows + 1] = {
        button = string.format("t:%x", e.item),
        text = label,
        same_line = line(label),
        selected = is_junk,
        color = items.color(e.debug_name, e.item),
        disabled = e.debug_name == nil,
        tooltip = table.concat(tip, "\n"):sub(1, 500),
      }
    end
  end

  local names = sorted_names()
  local shown = {}
  for i, name in ipairs(names) do shown[i] = { name = name, text = items.name(name) } end
  table.sort(shown, function(a, b)
    if a.text ~= b.text then return a.text < b.text end
    return a.name < b.name
  end)
  rows[#rows + 1] = { separator = true }
  rows[#rows + 1] = { heading = "YOUR JUNK LIST (" .. #names .. ")", color = JUNK_RED }
  if #names == 0 then
    rows[#rows + 1] = { text = "Nothing yet.", dim = true }
  else
    rows[#rows + 1] = { text = "Click an item to take it off the list.", dim = true }
  end
  drawn_junk = {}
  line = flow()
  for i, e in ipairs(shown) do
    if i > MAX_ROWS then
      rows[#rows + 1] = { text = "... and " .. (#shown - MAX_ROWS) .. " more (junk_list.json has them all)", dim = true }
      break
    end
    drawn_junk[i] = e.name
    local tip = items.details(items.id(e.name), e.name, nil)
    table.insert(tip, 1, e.text)
    tip[#tip + 1] = "Click to keep it (take it off your junk list)."
    rows[#rows + 1] = { button = "r:" .. i, text = e.text, same_line = line(e.text), color = items.color(e.name, items.id(e.name)),
      tooltip = table.concat(tip, "\n"):sub(1, 500) }
  end
  return rows
end

function C.click(world, key)
  if key == "dump" then
    dump(world)
  elseif key == "auto" then
    emf.set_setting("lf_auto", not emf.setting("lf_auto"))
    dirty = true
  elseif key == "action" then
    emf.set_setting("lf_action", emf.setting("lf_action") == "delete" and "drop" or "delete")
    dirty = true
  else
    local hex = key:match("^t:(%x+)$")
    local index = key:match("^r:(%d+)$")
    if hex then
      local name = items.debug_name(tonumber(hex, 16))
      if name then set_junk(name, not junk[name]) end
    elseif index then
      local name = drawn_junk[tonumber(index)]
      if name then set_junk(name, false) end
    end
  end
  refresh_warning()
  if dirty then sync(world) end  -- at once where it can (a world you host); else on the next step
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

-- A click in FlameKit's own window: put the item on the junk list (on = true) or take it off. The same as a click in
-- the panel's tab.
function C.ui_set(world, debug_name, on)
  if type(debug_name) ~= "string" or debug_name == "" then return end
  set_junk(debug_name, on)
  refresh_warning()
  if dirty then sync(world) end
end

-- Dump Junk in FlameKit's own window: the same as the panel's button.
function C.ui_dump(world)
  dump(world)
end

-- Auto (on/off) and Drop/Delete in FlameKit's own window: the same settings the panel's buttons change.
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
