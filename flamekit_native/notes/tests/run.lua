-- A mock of EMF's Lua API, enough to run Flamekit's logic outside the game.
-- Usage: texlua run.lua <mod folder> <tmp dir> host|joined
--   host:   the world runs in this game (single-player): both halves in one game, called directly.
--   joined: a dedicated server with Flamekit, and a player's game with Flamekit: the halves talk over emf.net.
--           (Both halves run in this one Lua state; `side` says whose code is running, as emf.local_player() differs.)
local MOD, TMP, MODE = arg[1], arg[2], arg[3] or "host"
package.path = MOD .. "/?.lua;" .. MOD .. "/?/init.lua"
local JOINED = MODE == "joined"

local ITEMS = { Material_T1_Twigs = 0x11, Material_T1_Wood_Logs = 0x22, Weapon_T1_Sword = 0x33, Material_T1_Stone = 0x44,
  Tool_T1_Torch = 0x55, NPC_Crafter_Farmer01 = 0x66, Material_T2_String = 0x77, Blueprint_Voxel_Block_Ceiling_4m = 0x88 }
local NAMES = {}
for n, id in pairs(ITEMS) do NAMES[id] = n end
local PLAYER, ACCOUNT = 100, "0x00000000000000aa"
local clock = 1000  -- the mod's wall clock (os.time), moved by hand
os.time = function() return clock end

local function stack(id, count, pide) return { id = id or 0, data = { count = count or 0, pide = pide or 0 } } end
local function inv(list)
  local slots = {}
  for i = 1, 8 do slots[i] = list[i] or stack() end
  return { slots = slots }
end
local comps
local function reset_world()
  comps = {
    DynamicLocomotion = {}, Velocity = {}, Impulse = {},  -- nobody is gliding yet
    InventorySetup = { [PLAYER] = { linksEntities = { 201, 202, 203, 0 }, linksCategories = { 4, 4, 2, 0 } } },
    SlotSelection = { [PLAYER] = { actionbarEntityIds = { 202, 0 } } },
    PlayerInput = { [PLAYER] = { fromClientSettings = { flags = 0x1000 } } },
    ItemState = { [900] = { itemRarityUi = 2, itemLevelUi = 12, baseDamageUi = 34, itemState = 0 },
                  [901] = { itemRarityUi = 4, itemLevelUi = 30, baseDamageUi = 0, itemState = 0 } },
    WeaponGemSlot = { [900] = { weaponGem = { id = 0x44 } } },
    Inventory = {
      [201] = inv({ stack(0x11, 30), stack(0x22, 50), stack(0x33, 1, 900), stack(0x11, 7), stack(0x55, 1),
                    stack(0x66, 1), stack(0x77, 3), stack(0x88, 1) }),  -- backpack
      [202] = inv({ stack(0x11, 5) }),                                                            -- action bar
      [203] = inv({ stack(0x33, 1, 901) }),                                                       -- equipment
    },
  }
end
reset_world()

local pos, moving = { 0, 0, 0 }, false
local function make_world(server)
  local w = {}
  function w:position(id) if id == PLAYER then return pos[1], pos[2], pos[3] end end
  function w:entities() return { 900, 901, PLAYER } end
  function w:tick() world_tick = (world_tick or 1000) + 1 return world_tick end
  function w:is_server() return server end
  function w:is_client() return not server end
  function w:get(c, id)
    if not comps[c] then error("no component " .. c) end
    return comps[c][id]
  end
  function w:account(id)
    assert(server, "world:account is for the server world")
    return id == PLAYER and ACCOUNT or nil
  end
  return w
end
local SW, CW = make_world(true), make_world(false)
local side = "client"  -- whose code runs now (joined mode)

local settings = { hub_key = "F4", hub_place = "right", notify = true, show_label = true, lf_enabled = true, lf_auto = true,
  lf_action = "delete", lf_dump_key = "", lf_keep_hotbar = true, map_hide = "-" }
local ticks, events, keys, commands, notes, replies, pending, tells = {}, {}, {}, {}, {}, {}, {}, {}
local to_server, to_client, channel, pdata, sender = {}, {}, nil, {}, nil
local teleports = {}
left_fns = {}
SESSION_TOKEN = "run-1"
held_key = nil
local channels, exp_up, exp_down, hit_rules, next_rule, ADMIN, casts = {}, {}, {}, {}, 0, false, {}
local window, gives, next_pickup = nil, {}, 5000
local emf_hud = {}  -- what the mod asked EMF to show (nothing since 0.15.14: FlameKit draws its own lines)
-- The lower-left lines as the DLL would draw them: ui_hud.dat in the mod's folder (kit.lua writes it).
local hud = setmetatable({}, { __index = function(_, key)
  local t = { label = nil, status = "", status_colour = nil }
  local f = io.open(TMP .. "\\ui_hud.dat", "r")
  if f then
    for line in f:lines() do
      local label = line:match("^label (.*)$")
      local rgb, status = line:match("^status (%x%x%x%x%x%x) (.*)$")
      if label then t.label = label end
      if status then t.status, t.status_colour = status, "#" .. rgb end
    end
    f:close()
  end
  return t[key]
end })
local ROW_FIELDS = {}
for _, f in ipairs({ "heading", "text", "button", "row", "slot", "bar", "separator", "value", "count", "tooltip", "color",
  "same_line", "selected", "disabled", "dim", "empty", "locked", "image", "icon", "fps", "height", "key" }) do ROW_FIELDS[f] = true end
local function check_def(def)
  assert(def.place == "right" or def.place == "left" or def.place == "centre")
  assert(#def.rows <= 256, "too many rows")
  for i, r in ipairs(def.rows) do
    for k in pairs(r) do assert(ROW_FIELDS[k], "row " .. i .. ": unknown field " .. tostring(k)) end
    local key = r.button or r.row or r.slot
    if key then assert(#key >= 1 and #key <= 48, "bad key length") end
    assert(r.heading or r.text or r.separator, "row " .. i .. " has no kind")
    assert(#(r.text or "") <= 256 and #(r.tooltip or "") <= 512, "text too long")
  end
end

local function enc(v)
  if type(v) == "table" then
    if #v > 0 then
      local p = {}
      for i, x in ipairs(v) do p[i] = enc(x) end
      return "[" .. table.concat(p, ",") .. "]"
    end
    local p = {}
    for k, x in pairs(v) do p[#p + 1] = string.format("%q:%s", k, enc(x)) end
    table.sort(p)
    return "{" .. table.concat(p, ",") .. "}"
  elseif type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

local logged = {}  -- emf.log lines
emf = {
  id = "flamekit", dir = TMP,
  log = function(...) logged[#logged + 1] = table.concat({ ... }, " "); print("[log]", ...) end,
  notify = function(t) notes[#notes + 1] = t end,
  hud = function(id, text, place, colour)
    assert(text == "" or place == "bottom_left", "hud place of " .. id)
    emf_hud[id], emf_hud[id .. "_colour"] = text, colour
  end,
  reply = function(t) replies[#replies + 1] = t end,
  tell = function(w, p, t) tells[#tells + 1] = t; return true end,
  on_tick = function(fn) ticks[#ticks + 1] = fn end,
  on_event = function(name, fn, kind) assert(kind == "server"); events[name] = fn end,
  on_key = function(key, fn) keys[key] = fn end,
  on_setting_changed = function() end,
  on_world_data = function() end,
  on_player_left = function(fn) left_fns[#left_fns + 1] = fn; return true end,
  session_token = function() return SESSION_TOKEN end,
  on_player_joined = function() return true end,
  command = function(name, help, fn, opts) commands[name] = fn end,
  sender = function() return sender end,
  local_player = function() return (JOINED and side == "server") and 0 or PLAYER end,
  session = function() return 1 end,
  setting = function(k) assert(settings[k] ~= nil, "unknown setting " .. k); return settings[k] end,
  set_setting = function(k, v) assert(settings[k] ~= nil); settings[k] = v end,
  item = function(n) return ITEMS[n] end,
  item_info = function(id) return NAMES[id] and { id = id, name = NAMES[id] } or nil end,
  item_name = function(x)
    local n = type(x) == "number" and NAMES[x] or (ITEMS[x] and x)
    if not n then return nil, false end
    return n, false
  end,
  player_data = function(a) assert(a == ACCOUNT); return pdata[a] or "" end,
  save_player_data = function(a, t) assert(a == ACCOUNT); pdata[a] = t; return true end,
  json = {
    encode = enc,
    decode = function(t)
      local src = t:gsub('("[^"]*"):', "[%1]="):gsub("%[", "{"):gsub("%]", "}"):gsub('{("[^"]*")}=', "[%1]=")
      local f = load("return " .. src)
      if not f then return nil, "bad json" end
      return f()
    end,
  },
  net = {
    channel = function(name, def)
      assert(def.version == 1)
      if name == "map" then assert(def.to == "players") else assert((name == "lf" or name == "exp" or name == "upd") and def.to == "both") end
      channels[name] = def
      if name == "lf" then channel = def end
      return true
    end,
    peer = function(w, player, name) return JOINED and 1 or 0 end,
    send = function(name, data)
      assert(JOINED and side == "client", "emf.net.send is for a joined game here")
      assert(#data <= 16384)
      if name == "exp" then exp_up[#exp_up + 1] = data; return true end
      to_server[#to_server + 1] = data
      return true
    end,
    send_to = function(w, player, name, data)
      if not JOINED then return false end
      assert(player == PLAYER and w:is_server())
      if name == "exp" then exp_down[#exp_down + 1] = data; return true end
      to_client[#to_client + 1] = data
      return true
    end,
  },
  teleport = function(w, id, x, y, z, opts) teleports[#teleports + 1] = opts.spawn_point or 'ground'; return true end,
  key_down = function(k) return held_key == k end,
  hit_rule = function(r) next_rule = next_rule + 1; hit_rules[next_rule] = r; return next_rule end,
  hit_rule_remove = function(id) local had = hit_rules[id] ~= nil; hit_rules[id] = nil; return had end,
  broadcast = function(t, opts) assert(type(t) == "string" and (opts == nil or type(opts) == "table"), "emf.broadcast takes (text [, opts])"); casts[#casts + 1] = t; return true end,
  take = function(w, entity, item, count, fn, opts)
    assert(w:is_server(), "emf.take needs the server world")
    assert(entity == PLAYER and opts and opts.exact and opts.slot)
    pending[#pending + 1] = function()
      local inv_id, s = opts.slot & 0xFFFFFFFF, (opts.slot >> 32) + 1
      local st = comps.Inventory[inv_id].slots[s]
      local taken = 0
      if st.id == item and st.data.count >= count then
        taken = count
        st.data.count = st.data.count - count
        if st.data.count == 0 then st.id, st.data.pide = 0, 0 end
      end
      fn(SW, taken)
    end
    return true
  end,
  give = function(w, player, item, count)
    assert(w:is_server() and player == PLAYER)
    next_pickup = next_pickup + 1
    gives[#gives + 1] = { id = next_pickup, item = item, count = count }
    return next_pickup
  end,
  put = function() error("put not expected") end,
  window = function(id, def, fn) check_def(def); window = { def = def, fn = fn }; return true end,
  window_update = function(id, def) check_def(def); if not window then return false end; window.def = def; return true end,
  window_close = function(id) local w = window; window = nil; if w then w.fn(nil, { kind = "closed", reason = "mod" }) end; return w ~= nil end,
}

do local m = io.open(TMP .. "\\mod.json", "w"); m:write('{"version":"9.9.9","authors":["Tester"]}'); m:close() end
dofile(MOD .. "/main.lua")
local server = require("features.loot_filter.server")

local UI = JOINED and CW or SW  -- the world keys and the window run in
local function step(n)
  for _ = 1, n or 1 do
    side = "server"
    local msgs = to_server
    to_server = {}
    for _, data in ipairs(msgs) do channel.on_server(SW, { player = PLAYER, account = ACCOUNT }, data) end
    local run = pending
    pending = {}
    for _, f in ipairs(run) do f() end
    if moving then pos[1] = pos[1] + 0.2 end
    local ups = exp_up
    exp_up = {}
    for _, data in ipairs(ups) do channels.exp.on_server(SW, { player = PLAYER, account = ACCOUNT, admin = ADMIN }, data) end
    if JOINED then server.tick(SW); require("features.experimental").tick(SW) else for _, f in ipairs(ticks) do f(SW) end end
    side = "client"
    msgs = to_client
    to_client = {}
    for _, data in ipairs(msgs) do channel.on_player(CW, {}, data) end
    local downs = exp_down
    exp_down = {}
    for _, data in ipairs(downs) do channels.exp.on_player(CW, {}, data) end
    for _, f in ipairs(ticks) do f(CW) end
  end
end
local function pickup(e)
  side = "server"
  events.PickupEvent(SW, e)
  side = "client"
end
local function count(inv_id, item)
  local n = 0
  for _, s in ipairs(comps.Inventory[inv_id].slots) do if s.id == item then n = n + s.data.count end end
  return n
end
local function click(key) window.fn(UI, { kind = "click", key = key }) end
local function find_row(pattern, key)
  for _, r in ipairs(window.def.rows) do
    if (r.text or r.heading or ""):find(pattern) and (not key or (r.button or ""):find(key, 1, true)) then return r end
  end
end
local function check(cond, what) if not cond then error("FAILED: " .. what, 2) end print("ok   " .. what) end
local SYNC = JOINED and 40 or 3  -- steps until a change has reached the server half

step(3)

-- the panel: open it, mark Twigs as junk by clicking its bag row
keys.hub_key(UI)
check(window ~= nil, "panel opens on its key")
if JOINED then check(find_row("Connected to this server") ~= nil, "the panel says the server has Flamekit") end
local twigs = find_row("Twigs")
check(twigs and twigs.button == "f1:t:11" and not twigs.selected, "bag chip for Twigs, not junk yet")
check(twigs.color == "#cdbf9f", "a material has the materials' colour")
check(find_row("^Sword", ":t:") == nil and find_row("^Torch", ":t:") == nil and find_row("Farmer", ":t:") == nil,
  "weapons, tools and summoning items are not offered")
check(find_row("Ceiling", ":t:") == nil, "a building blueprint is not offered")
check(find_row("^String", ":t:") ~= nil, "a material whose name merely contains 'ring' is offered")
check(find_row("never junked") ~= nil, "the panel says what is left out")
check(twigs.tooltip:find("Material, tier 1", 1, true) and twigs.tooltip:find("Quantity: 42", 1, true), "a material's tooltip: " .. twigs.tooltip:gsub("\n", " | "))
check(window.def.title == "FlameKit v9.9.9 by Tester", "the window is titled with the kit's name, version and author: " .. tostring(window.def.title))
check(find_row("Dump junk now %(0%)").disabled, "dump button disabled without junk")
click(twigs.button)
check(find_row("^Twigs", ":t:").selected, "the Twigs chip is lit after the click")
check(find_row("^Twigs", ":r:") ~= nil, "and Twigs is in the junk block")
check(find_row("Dump junk now %(2%)") ~= nil, "dump counts the 2 backpack stacks (not the action bar)")
step(SYNC)
check(count(201, 0x11) == 37, "marking does not remove anything by itself")
local f = io.open(TMP .. "\\junk_list.json"); local saved = f:read("a"); f:close()
check(saved:find("Material_T1_Twigs", 1, true) ~= nil, "junk_list.json holds the debug name")
check((pdata[ACCOUNT] or ""):find("Material_T1_Twigs", 1, true) ~= nil, "the server half saved the player's list with the world")

-- auto: a pickup of a junk item removes the junk stacks a few steps later
pickup({ itemId = 0x22, itemCount = 5, pickedUpByEntityId = PLAYER, pickedUpFromEntityId = 0 })
step(10)
check(count(201, 0x11) == 37, "a pickup of something else removes nothing")
pickup({ itemId = 0x11, itemCount = 3, pickedUpByEntityId = 999, pickedUpFromEntityId = 0 })
step(10)
check(count(201, 0x11) == 37, "another player's pickup removes nothing of yours")
pickup({ itemId = 0x11, itemCount = 3, pickedUpByEntityId = PLAYER, pickedUpFromEntityId = 0 })
step(10)
check(count(201, 0x11) == 0, "your pickup of junk empties the backpack of it")
check(count(202, 0x11) == 5, "the action bar is untouched")
check(count(201, 0x22) == 50, "other items are untouched")
check(hud.status == "Junk discarded: Twigs x37", "a status line says what was discarded: " .. tostring(hud.status))
check(hud.status_colour == "#ff4a3d", "the status line is red")
check(hud.label == "FlameKit v9.9.9 by Tester", "the label shows name, version and author: " .. tostring(hud.label))
step(500)
check(hud.status == "", "the status line goes away after a few seconds")
settings.show_label = false
step(1)
check(hud.label == "", "the label can be switched off")
settings.show_label = true
settings.notify = false
comps.Inventory[201].slots[1] = stack(0x11, 4)
pickup({ itemId = 0x11, itemCount = 4, pickedUpByEntityId = PLAYER, pickedUpFromEntityId = 0 })
step(10)
check(count(201, 0x11) == 0 and hud.status == "", "with status lines off the junk still goes, silently")
check(next(emf_hud) == nil, "nothing is drawn by EMF: no emf.hud line")
settings.notify = true

-- gear, tools and summoning items are never junk, whatever a list or a command says
reset_world()
step(30)
side = "server"
channel.on_server(SW, { player = PLAYER, account = ACCOUNT }, emf.json.encode({ op = "sync",
  items = { "Material_T1_Twigs", "Weapon_T1_Sword", "Tool_T1_Torch", "NPC_Crafter_Farmer01" }, opts = { auto = false, action = "delete" } }))
side = "client"
check(not pdata[ACCOUNT]:find("Sword") and not pdata[ACCOUNT]:find("Torch") and not pdata[ACCOUNT]:find("Farmer"),
  "the server refuses gear, tools and summoning items on a list")
settings.lf_auto = false
click("f1:auto"); click("f1:auto")
check(settings.lf_auto == false, "the auto button switches the setting")
step(SYNC)
pickup({ itemId = 0x11, itemCount = 3, pickedUpByEntityId = PLAYER, pickedUpFromEntityId = 0 })
step(10)
check(count(201, 0x11) == 37, "with auto off a pickup removes nothing")
step(30)
check(find_row("Dump junk now %(2%)") ~= nil, "the open panel refreshed by itself")
click("f1:dump")
step(10)
check(count(201, 0x11) == 0, "dump removes the junk in the backpack")
check(count(201, 0x33) == 1 and count(201, 0x55) == 1 and count(201, 0x66) == 1, "sword, torch and summoning item are still there")
check(count(203, 0x33) == 1, "worn equipment is never touched")
click("f1:dump")
step(5)
check(notes[#notes] == "No junk in your bag.", "a dump with nothing to do says so: " .. tostring(notes[#notes]))

-- drop mode: handed to emf.give at once; a drop the game's auto loot takes straight back gets one warning
reset_world()
settings.lf_auto = true
click("f1:action")
check(settings.lf_action == "drop", "the action button switches to drop")
step(SYNC)
pickup({ itemId = 0x11, itemCount = 3, pickedUpByEntityId = PLAYER, pickedUpFromEntityId = 0 })
step(10)
local dropped = 0
for _, g in ipairs(gives) do if g.item == 0x11 then dropped = dropped + g.count end end
check(dropped == 37 and count(201, 0x11) == 0 and #gives == 2, "drop mode hands the taken stacks to emf.give")
local n_gives = #gives
comps.Inventory[201].slots[1] = stack(0x11, 30)
pickup({ itemId = 0x11, itemCount = 30, pickedUpByEntityId = PLAYER, pickedUpFromEntityId = gives[1].id })
step(10)
check(count(201, 0x11) == 30 and #gives == n_gives, "a drop that came back stays in the bag (no loop)")
-- the game's auto loot is on (the mock's flags have bit 12): the player is warned while junk is dropped
step(70)
check(find_row("Auto%-Collect Scattered Loot") ~= nil, "auto loot on and junk dropped: the panel warns in red")
local function yells()
  local n = 0
  for _, t in ipairs(notes) do if t:find("Auto%-Collect Scattered Loot") then n = n + 1 end end
  return n
end
check(yells() == 1, "and a banner note came")
check((hud.autoloot or "") == "", "no extra line is left on the screen")
clock = clock + 8
step(2)
check(yells() == 2, "the banner is shown a second time after the first went")
clock = clock + 8
step(2)
check(yells() == 2, "and not a third time")
click("f1:action")
check(find_row("Auto%-Collect Scattered Loot") == nil, "junk set to delete: the warning goes")
click("f1:action")
check(find_row("Auto%-Collect Scattered Loot") ~= nil, "back to drop: the warning is back")
step(SYNC)
-- each drop into auto loot brings the banner back
clock = clock + 20
local before = yells()
comps.Inventory[201].slots[1] = stack(0x11, 5)
pickup({ itemId = 0x11, itemCount = 5, pickedUpByEntityId = PLAYER, pickedUpFromEntityId = 0 })
step(10)
check(yells() == before + 1, "junk dropped while auto loot is on: the banner comes again")
pickup({ itemId = 0x11, itemCount = 5, pickedUpByEntityId = PLAYER, pickedUpFromEntityId = 0 })
comps.Inventory[201].slots[2] = stack(0x11, 5)
step(10)
check(yells() == before + 1, "but not twice while it is still on screen")
comps.PlayerInput[PLAYER].fromClientSettings.flags = 0x0853
step(70)
check(find_row("Auto%-Collect Scattered Loot") == nil, "auto loot switched off in the game: the warning goes")
comps.Inventory[201].slots[1] = stack()

-- the chat command runs on the server half and the player's own game follows
local function cmd(words)
  side = "server"
  sender = JOINED and { chat = true, entity = PLAYER, account = ACCOUNT } or nil
  commands.junk(SW, words)
  side = "client"
end
cmd({ "add", "Material", "T1", "Stone" })
check(replies[#replies]:find("is junk now"), "junk add finds an item typed with spaces")
cmd({ "add", "Weapon_T1_Sword" })
check(replies[#replies]:find("cannot be junk"), "junk add refuses a weapon: " .. replies[#replies])
cmd({ "add", "nonsense" })
check(replies[#replies]:find("no item named"), "junk add refuses an unknown item")
step(31)
local keep = find_row("^Stone", ":r:")
check(keep ~= nil, "the panel's junk block shows Stone, added by the command")
f = io.open(TMP .. "\\junk_list.json"); saved = f:read("a"); f:close()
check(saved:find("Material_T1_Stone", 1, true) ~= nil, "and junk_list.json has it")
click(keep.button)
check(find_row("^Stone", ":r:") == nil, "clicking a junk chip takes it off the list")
step(SYNC)
check(not pdata[ACCOUNT]:find("Material_T1_Stone", 1, true), "and off the server half's list")
cmd({ "list" })
cmd({ "clear" })
cmd({ "clear", "yes" })
step(31)
check(find_row("Nothing yet") ~= nil, "junk clear yes empties the list")

-- the Minimap tab's marker filters
click("tab:2")
step(2)
click(find_row("Ancient Spires", "f:sp").button)
step(2)
check(settings.map_hide == "sp" and not find_row("Ancient Spires", "f:sp").selected, "a marker filter switched off is written to map_hide")
click(find_row("Hide all").button)
step(2)
check(#settings.map_hide > 60 and settings.map_hide:find("m9", 1, true), "Hide all lists every filter")
click(find_row("Show all").button)
step(2)
check(settings.map_hide == "-" and find_row("Ancient Spires", "f:sp").selected, "Show all clears the list")

-- the Experimental tab: the host's (or the server's) switches
local function rule_count() local n = 0; for _ in pairs(hit_rules) do n = n + 1 end; return n end
click("tab:3")
step(JOINED and 310 or 2)
local sw = find_row("Shroud Damage", "sw:shroud")
check(sw ~= nil and not sw.selected and rule_count() == 0, "the Experimental tab lists the shroud switch, off, and no rule is set")
click(find_row("Shroud Damage", "sw:shroud").button)
step(3)
sw = find_row("Shroud Damage", "sw:shroud")
local r = select(2, next(hit_rules)) or {}
check(sw.selected == true and rule_count() == 1 and r.kinds == "shroud" and r.to == PLAYER and r.cancel == true,
  "switched on: one rule cancels shroud damage for this player only")
local ef = io.open(TMP .. "\\experimental.json"); local etext = ef:read("a"); ef:close()
check(etext:find('"shroud":true', 1, true) ~= nil, "experimental.json keeps it")
check(#casts == 1 and casts[1] == "No Shroud Damage for a player ENABLED.", "everyone is told in the chat when a player switches an option on: " .. tostring(casts[1]))
step(JOINED and 700 or 5)
check(rule_count() == 1, "the rule stays while the player is here")
click(find_row("Shroud Damage", "sw:shroud").button)
step(3)
check(rule_count() == 0 and not find_row("Shroud Damage", "sw:shroud").selected, "switched off: the rule is gone")
comps.CurrentTransform = {}
comps.PlayerSpawnPoint = { [900] = { target = 1 }, [901] = { target = 2 } }
click(find_row("Nearest Flame Altar").button)
step(3)
check(#teleports == 1 and teleports[1] == 901, "the rescue button sends the player to a flame altar, not to a travel point")
local ia, ib = require("features.experimental")._marker_ids("c1e5524a-95f2-4b2f-b11d-c8fd0cd008ef")
check(ia == 445222884 and ib == 3431657214, "a marker type's number is worked out from its GUID")
comps.MapMarker = {}
click(find_row("Nearest Ancient Spire").button)
step(40)
check(find_row("knows no Ancient Spire") ~= nil and #teleports == 1, "no spire known: the tab says so and nobody is moved")
comps.MapMarker = { [900] = { markerType = "c1e5524a-95f2-4b2f-b11d-c8fd0cd008ef" } }
comps.CurrentTransform = { [900] = { transform = { position = { x = 50, y = 5, z = 60 } } } }
local SP = require("features.experimental")._spires
SP[445222884] = true
click(find_row("Nearest Ancient Spire").button)
step(40)
check(#teleports == 2 and teleports[2] == 900, "a spire is known: the player lands on the travel pad beside it")
SP[445222884] = nil
comps.DynamicLocomotion = { [PLAYER] = { state = 4, flags = 0 } }
local function slot() return { impulse = { x = 0, y = 0, z = 0 }, type = 0, startTime = 0, endTime = 0, keepAliveMask = 0 } end
comps.Impulse = { [PLAYER] = { impulses = { slot(), slot(), slot(), slot() } } }
comps.CurrentTransform[PLAYER] = { transform = { orientation = { x = 0, y = 0, z = 0, w = 1 } } }
comps.Velocity = { [PLAYER] = { velocity = { x = 3, y = -4.5, z = 0 } } }
check(find_row("Enhanced Glider Mode").selected == true, "the glider option is on without anyone switching it on")
click(find_row("Enhanced Glider Mode").button)
step(JOINED and 10 or 3)
held_key = "S"
step(5)
check(comps.Velocity[PLAYER].velocity.y == -4.5 and not find_row("Enhanced Glider Mode").selected, "glider option switched off, S held: the glide is left alone")
local gtext = io.open(TMP .. "\\experimental.json"); local gsaved = gtext:read("a"); gtext:close()
check(gsaved:find('"fly":false', 1, true) ~= nil, "and that it is off is kept")
click(find_row("Enhanced Glider Mode").button)
step(70)
check(#casts == 2 and casts[2] == "No Shroud Damage for a player DISABLED.", "and when they switch it off; nobody is told about the glider option")
check(comps.Velocity[PLAYER].velocity.y == 12 and comps.Velocity[PLAYER].velocity.z >= 10 and comps.Velocity[PLAYER].velocity.x == 0, "switch on, gliding, S held: the player climbs and keeps flying forward")
comps.Velocity[PLAYER].velocity.y = -4.5
comps.DynamicLocomotion[PLAYER].state = 0
step(5)
check(comps.Velocity[PLAYER].velocity.y == -4.5, "not gliding: nothing is written")
comps.DynamicLocomotion[PLAYER].state = 4
held_key = nil
step(5)
comps.Velocity[PLAYER].velocity.y = -4.5
step(5)
check(comps.Velocity[PLAYER].velocity.y == -4.5, "S let go: the climb stops at once")
held_key = "Space"
step(5)
held_key = nil
step(5)
check(comps.Impulse[PLAYER].impulses[2].endTime == 0, "the first burst of a flight is left to the game")
comps.DynamicLocomotion[PLAYER].flags = 64
step(3)
check(comps.DynamicLocomotion[PLAYER].flags == 0, "the game's note of a used burst is taken away")
held_key = "Space"
step(5)
held_key = nil
check(comps.Impulse[PLAYER].impulses[2].impulse.y == 9.78 and comps.Impulse[PLAYER].impulses[2].endTime > comps.Impulse[PLAYER].impulses[1].endTime,
  "a later press of the burst key lifts the player again")
-- every option is remembered when the player leaves
click(find_row("No Fall Damage").button)
step(5)
check(rule_count() == 1, "an option switched on makes its rule")
side = "server"
for _, fn in ipairs(left_fns) do fn(SW, { player = PLAYER, account = ACCOUNT }) end
side = "client"
check(rule_count() == 0, "the player leaves: their rule goes")
local vt = io.open(TMP .. "\\experimental.json"); local visit = vt:read("a"); vt:close()
check(visit:find('"fall":true', 1, true) ~= nil, "but the option stays saved")
step(JOINED and 320 or 40)
check(find_row("No Fall Damage").selected == true and rule_count() == 1, "and it is on again when they are back")
click(find_row("No Fall Damage").button)
step(5)
click("tab:1")
step(2)

-- closing with the same key does not reopen
keys.hub_key(UI)
check(window == nil, "the key closes the panel")
-- the debug level (debug.txt), read by the Lua part as by the DLL
local kit = require("core.kit")
local function lines_with(word)
  local n = 0
  for _, l in ipairs(logged) do if l:find(word, 1, true) then n = n + 1 end end
  return n
end
check(kit.debug_level(true) == "normal", "no debug.txt: the level is normal")
local df = io.open(TMP .. "\\debug.txt", "w"); df:write("full\n"); df:close()
check(kit.debug_level(true) == "full", "debug.txt full: the level is full")
kit.debug("debug", "test detail %d", 7)
check(lines_with("DEBUG test detail 7") == 1, "at full a detail line is written")
df = io.open(TMP .. "\\debug.txt", "w"); df:write("off"); df:close()
check(kit.debug_level(true) == "off", "debug.txt off: the level is off")
kit.debug("info", "test info")
kit.debug("warn", "test warning")
check(lines_with("INFO test info") == 0 and lines_with("WARN test warning") == 1, "at off only warnings and errors are written")
os.remove(TMP .. "\\debug.txt")
-- FlameKit's own window: the tab list, the rows of the tab shown, a click on one of its buttons (native_ui.lua)
local function read_tabs()
  local f = io.open(TMP .. "\\ui_tabs.dat", "r")
  local t = f and f:read("a") or ""
  if f then f:close() end
  return t
end
local action_n = 9000000000000
local action_lines = {}
local function ui_action(what, arg)
  action_n = action_n + 1
  action_lines[#action_lines + 1] = action_n .. " " .. what .. " " .. arg
  local f = io.open(TMP .. "\\ui_actions.txt", "w"); f:write(table.concat(action_lines, "\n") .. "\n"); f:close()
end
step(12)
check(read_tabs():find("tab\tminimap\tMinimap", 1, true) ~= nil, "ui_tabs.dat lists the Minimap tab")
check(read_tabs():find("\nview\t", 1, true) == nil, "no rows while the window shows no generic tab")
ui_action("view", "minimap")
step(12)
local tabs_text = read_tabs()
local gen = tabs_text:match("view\tminimap\t(%d+)")
check(gen ~= nil, "the Minimap tab's rows are written once the window shows it")
local number
for line in tabs_text:gmatch("[^\n]+") do
  local f = {}
  for field in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = field end
  if f[1] == "r" and f[2] == "b" and f[9] == "Ancient Spires" then number = f[8] end
end
check(number ~= nil, "the marker filter Ancient Spires is a button")
local before = settings.map_hide
ui_action("tab", "minimap/" .. gen .. "/" .. number)
step(6)
local after = settings.map_hide
check(after ~= before and after:find("sp", 1, true) ~= nil, "a click in FlameKit's window does what the panel's button does")
ui_action("tab", "minimap/0/" .. number)
step(6)
check(settings.map_hide == after, "a click for rows the window no longer shows is dropped")
ui_action("view", "-")
step(12)
check(read_tabs():find("\nview\t", 1, true) == nil, "no rows once the window is closed")
print("ALL PASSED (" .. MODE .. ")")
