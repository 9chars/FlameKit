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

local settings = { lf_show_all = false, open_on_start = false, window_key = "F6", pointer_key = "right_alt", map_clock = true, map_size = 300, map_toggle_key = "F10", notify = true, show_label = true, lf_enabled = true, lf_auto = true,
  lf_action = "delete", lf_dump_key = "", lf_keep_hotbar = true, map_hide = "-" }
local ticks, events, keys, commands, notes, replies, pending, tells = {}, {}, {}, {}, {}, {}, {}, {}
local to_server, to_client, channel, pdata, sender = {}, {}, nil, {}, nil
local teleports = {}
left_fns = {}
joined_fns = {}  -- EMF reports the players already there (the test player) after the world data
SESSION_TOKEN = "run-1"
held_key = nil
local channels, exp_up, exp_down, hit_rules, next_rule, ADMIN, casts = {}, {}, {}, {}, 0, false, {}
local window, gives, next_pickup = nil, {}, 5000
local emf_hud = {}  -- what the mod asked EMF to show (nothing since 0.15.14: FlameKit draws its own lines)
-- The lower-left lines as the DLL would draw them: ui_hud.dat in the mod's folder (kit.lua writes it).
-- status: the newest message in FlameKit's Messages window (ui_messages.dat, kit.note), messages: how many there are
local hud = setmetatable({}, { __index = function(_, key)
  local t = { label = nil, status = "", status_colour = nil, messages = 0, newest = 0 }
  local f = io.open(TMP .. "\\ui_hud.dat", "r")
  if f then
    for line in f:lines() do
      local label = line:match("^label (.*)$")
      if label then t.label = label end
    end
    f:close()
  end
  f = io.open(TMP .. "\\ui_messages.dat", "r")
  if f then
    for line in f:lines() do
      local n, rgb, text = line:match("^m (%d+) (%x%x%x%x%x%x) (.*)$")
      if n then t.status, t.status_colour, t.messages, t.newest = text, "#" .. rgb, t.messages + 1, tonumber(n) end
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
local last_ask  -- the last request for test players sent to the server half
local ptest_up = {}  -- requests for test players, from the player's game to the server half
local party_down = {}  -- party lists the server half sent to the player's game
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
  on_player_joined = function(fn) joined_fns[#joined_fns + 1] = fn; return true end,
  -- buffs (Lua 1.24): the player is Wet (812.4 s left) and has a buff without a timer and one the game hides
  buffs = function(w, id)
    if id ~= PLAYER then return {} end
    return { { type = 0xAC13C6C3, slot = "debuff", seconds_left = 812.4 }, { type = 0x1234, slot = "buff" },
             { type = 0x9999, slot = "buff", seconds_left = 5 }, { type = 0x5555, slot = "food", seconds_left = 9, cleansed = true } }
  end,
  buff_type = function(w, id)
    local names = { [0xAC13C6C3] = "Wet", [0x1234] = "Blessing", [0x9999] = "Secret", [0x5555] = "Stew" }
    return names[id] and { id = id, name = names[id], hidden = id == 0x9999 } or nil
  end,
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
      if name == "map" or name == "party" then assert(def.to == "players") elseif name == "party_test" then assert(def.to == "server") elseif name == "ver" then assert(def.to == "both") else assert((name == "lf" or name == "exp" or name == "upd") and def.to == "both") end
      channels[name] = def
      if name == "lf" then channel = def end
      return true
    end,
    peer = function(w, player, name) return JOINED and 1 or 0 end,
    send = function(name, data)
      assert(JOINED and side == "client", "emf.net.send is for a joined game here")
      assert(#data <= 16384)
      if name == "exp" then exp_up[#exp_up + 1] = data; return true end
      if name == "party_test" then ptest_up[#ptest_up + 1] = data; last_ask = data; return true end
      if name == "ver" then ver_asks = (ver_asks or 0) + 1; return true end
      to_server[#to_server + 1] = data
      return true
    end,
    send_to = function(w, player, name, data)
      if not JOINED then return false end
      assert(player == PLAYER and w:is_server())
      if name == "exp" then exp_down[#exp_down + 1] = data; return true end
      if name == "party" then party_down[#party_down + 1] = data; return true end
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

do local m = io.open(TMP .. "\\mod.json", "w"); m:write('{"version":"9.9.9","authors":["Tester"],"settings":['
  .. '{"key":"pointer_key","type":"select","default":"right_alt","label":"Pointer key","group":"FlameKit","options":[{"value":"right_alt","label":"Right Alt"},{"value":"right_ctrl","label":"Right Ctrl"}]},'
  .. '{"key":"map_toggle_key","type":"keybind","default":"F10","label":"Key that shows and hides the minimap","group":"Minimap"},'
  .. '{"key":"map_size","type":"slider","min":120,"max":480,"step":20,"default":300,"label":"Size","group":"Minimap"},'
  .. '{"key":"map_hide","type":"text","default":"-","label":"Hidden kinds","group":"Minimap"},'
  .. '{"key":"lf_keep_hotbar","type":"bool","default":true,"label":"Never touch the action bar","group":"Auto Junk List"},'
  .. '{"key":"lf_show_all","type":"bool","default":false,"label":"Show all bag items","group":"Auto Junk List"},'
  .. '{"key":"map_clock","type":"bool","default":true,"label":"Show the clock under the minimap","group":"Minimap"}]}'); m:close() end
dofile(MOD .. "/main.lua")
local function join_all() for _, fn in ipairs(joined_fns) do fn(SW, { player = PLAYER, account = ACCOUNT, host = not JOINED }) end end
join_all()
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
    local asks = ptest_up
    ptest_up = {}
    for _, data in ipairs(asks) do channels.party_test.on_server(SW, { player = PLAYER, account = ACCOUNT }, data) end
    if JOINED then server.tick(SW); require("features.experimental").tick(SW); require("features.party").tick(SW); require("features.server_save").tick(SW) else for _, f in ipairs(ticks) do f(SW) end end
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
-- The panel as the tests use it: the features' tabs (panel / click), as FlameKit's window shows them (the Auto Junk
-- List has its own view instead: ui_list.dat, tested through junk_view). (EMF's panel,
-- core/hub.lua, was removed in 0.15.26; these tests keep its "tab:<n>" and "f<n>:<key>" keys.)
local panel_tab = 1
local function panel_list()
  local kit = require("core.kit")
  local list = {}
  for _, f in ipairs(kit.features) do if f.panel and kit.enabled(f) and f.id ~= "changes" then list[#list + 1] = f end end  -- (What's New: not used here)
  return list
end
local function panel_rows()
  local kit = require("core.kit")
  local list, rows = panel_list(), {}
  if panel_tab > #list then panel_tab = 1 end
  for i, f in ipairs(list) do rows[#rows + 1] = { button = "tab:" .. i, text = f.title, same_line = i > 1, selected = i == panel_tab } end
  rows[#rows + 1] = { separator = true }
  local own = kit.call(list[panel_tab], "panel", UI) or {}
  for _, r in ipairs(own) do
    local c = {}
    for k, v in pairs(r) do c[k] = v end
    for _, fld in ipairs({ "button", "row", "slot", "key" }) do if type(c[fld]) == "string" then c[fld] = "f" .. panel_tab .. ":" .. c[fld] end end
    rows[#rows + 1] = c
  end
  check_def({ place = "centre", rows = rows })
  return rows
end
local function toggle_panel()
  if window then window = nil return end
  local kit = require("core.kit")
  window = {
    def = setmetatable({}, { __index = function(_, k)
      if k == "rows" then return panel_rows() end
      if k == "title" then return string.format("%s v%s by %s", kit.name, kit.version, kit.author) end
    end }),
    fn = function(w, ev)
      local tab = ev.key:match("^tab:(%d+)$")
      if tab then panel_tab = tonumber(tab) return end
      local n, own = ev.key:match("^f(%d+):(.+)$")
      local f = n and panel_list()[tonumber(n)]
      if f then kit.call(f, "click", w, own, false) end
    end,
  }
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

-- FlameKit's window, the Auto Junk List's own view: what it shows comes from ui_list.dat (features/native_ui.lua), its
-- clicks go back through ui_actions.txt ("<n> junk|keep <debug name>", "dump -", "auto 1|0", "action drop|delete")
local action_n = 9000000000000
local action_lines = {}
local function ui_action(what, arg)
  action_n = action_n + 1
  action_lines[#action_lines + 1] = action_n .. " " .. what .. " " .. arg
  local f = io.open(TMP .. "\\ui_actions.txt", "w"); f:write(table.concat(action_lines, "\n") .. "\n"); f:close()
end
local function junk_view()
  step(11)  -- native_ui reads the clicks every 3 steps and writes the view every 10
  local f = io.open(TMP .. "\\ui_list.dat", "r")
  local t = f and f:read("a") or ""
  if f then f:close() end
  local v = { bag = {}, junk = {}, text = t }
  for line in t:gmatch("[^\n]+") do
    local auto, action = line:match("^O (%d) (%a+)$")
    if auto then v.auto, v.action = auto == "1", action end
    v.warning = v.warning or line:match("^W\t(.*)$")
    local fl = {}
    for field in (line .. "\t"):gmatch("([^\t]*)\t") do fl[#fl + 1] = field end
    if fl[1] == "B" or fl[1] == "J" then
      table.insert(fl[1] == "B" and v.bag or v.junk, { id = tonumber(fl[2], 16), count = tonumber(fl[3]), debug = fl[4],
        rarity = tonumber(fl[5]), level = fl[6], type = fl[7], name = fl[8] })
    end
  end
  return v
end
local function tile(list, pattern)
  for _, e in ipairs(list) do if e.name:find(pattern) then return e end end
end

-- mark Twigs as junk by clicking its tile in the bag
local v = junk_view()
check(v.text:find("\nend\n$") ~= nil, "ui_list.dat is written, complete")
local twigs = tile(v.bag, "^Twigs")
check(twigs and twigs.debug == "Material_T1_Twigs" and tile(v.junk, "^Twigs") == nil, "a bag tile for Twigs, not junk yet")
check(twigs.type == "Material, tier 1" and twigs.count == 42, "a material's tile: its type, and how many you carry (" .. tostring(twigs.count) .. ")")
check(tile(v.bag, "^Sword") == nil and tile(v.bag, "^Torch") == nil and tile(v.bag, "Farmer") == nil,
  "weapons, tools and summoning items are not offered")
check(tile(v.bag, "Ceiling") == nil, "a building blueprint is not offered")
check(tile(v.bag, "^String") ~= nil, "a material whose name merely contains 'ring' is offered")
ui_action("junk", "Material_T1_Twigs")
v = junk_view()
check(tile(v.junk, "^Twigs") ~= nil and tile(v.bag, "^Twigs") == nil, "after the click Twigs is on the junk list, not among the bag's tiles")
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
check(hud.messages >= 1, "the message stays in the Messages window's list")
settings.show_label = false
step(1)
check(hud.label == "", "the label can be switched off")
settings.show_label = true
settings.notify = false
local newest_before = hud.newest
comps.Inventory[201].slots[1] = stack(0x11, 4)
pickup({ itemId = 0x11, itemCount = 4, pickedUpByEntityId = PLAYER, pickedUpFromEntityId = 0 })
step(10)
check(count(201, 0x11) == 0 and hud.newest == newest_before, "with messages off the junk still goes, silently")
check(next(emf_hud) == nil, "nothing is drawn by EMF: no emf.hud line")
settings.notify = true

-- gear, tools and summoning items are never junk, whatever a list or a command says
reset_world()
step(30)
side = "server"
channel.on_server(SW, { player = PLAYER, account = ACCOUNT }, emf.json.encode({ op = "sync",
  items = { "Material_T1_Twigs", "Weapon_T1_Sword", "Tool_T1_Torch", "NPC_Crafter_Farmer01" }, opts = { auto = false, action = "delete" } }))
side = "client"
check(pdata[ACCOUNT]:find("Twigs") ~= nil, "the server keeps the list (kept kinds stay on it, but are never removed: below)")
ui_action("auto", "0")
check(junk_view().auto == false and settings.lf_auto == false, "the Auto button switches the setting, and the view shows it")
step(SYNC)
pickup({ itemId = 0x11, itemCount = 3, pickedUpByEntityId = PLAYER, pickedUpFromEntityId = 0 })
step(10)
check(count(201, 0x11) == 37, "with auto off a pickup removes nothing")
check(tile(junk_view().junk, "^Twigs") ~= nil, "the view follows the bag by itself")
ui_action("dump", "-")
step(10)
check(count(201, 0x11) == 0, "dump removes the junk in the backpack")
check(count(201, 0x33) == 1 and count(201, 0x55) == 1 and count(201, 0x66) == 1, "sword, torch and summoning item are still there")
check(count(203, 0x33) == 1, "worn equipment is never touched")
-- Show all bag items (lf_show_all): the sword is offered, can be put on the list, and goes on a dump
check(tile(junk_view().bag, "^Sword") == nil, "the sword is not offered while Show all bag items is off")
ui_action("opt", "b:lf_show_all")
step(6)
check(settings.lf_show_all == true, "Show All Bag Items is switched on from the view: " .. tostring(settings.lf_show_all))
check(tile(junk_view().bag, "^Sword") ~= nil, "with Show all bag items on, the sword is offered")
ui_action("junk", "Weapon_T1_Sword")
step(SYNC + 40)
ui_action("dump", "-")
step(10)
check(count(201, 0x33) == 0, "and a dump removes it")
check(count(203, 0x33) == 1, "worn equipment is still never touched")
ui_action("opt", "b:lf_show_all")
step(SYNC + 40)
check(settings.lf_show_all == false, "and off again")
ui_action("dump", "-")
step(5)
check(hud.status == "No junk in your bag.", "a dump with nothing to do says so: " .. tostring(hud.status))

-- drop mode: handed to emf.give at once; a drop the game's auto loot takes straight back gets one warning
reset_world()
settings.lf_auto = true
ui_action("action", "drop")
check(junk_view().action == "drop" and settings.lf_action == "drop", "the Drop/Delete choice switches to drop")
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
-- the game's auto loot is on (the mock's flags have bit 12): a notice stays on screen while junk is set to drop
step(70)
local function notice()
  local f = io.open(TMP .. "\\ui_notices.dat", "r")
  if not f then return nil end
  local t = f:read("a")
  f:close()
  return t:match("\nn autoloot ff5a50 ([^\n]*)") or t:match("^n autoloot ff5a50 ([^\n]*)"), t
end
local function yells()
  local n = 0
  local f = io.open(TMP .. "\\ui_messages.dat", "r")
  if not f then return 0 end
  for line in f:lines() do if line:find("Auto%-Collect Scattered Loot") then n = n + 1 end end
  f:close()
  return n
end
local text, whole = notice()
check(text and text:find("Auto%-Collect Scattered Loot") and whole:find("\nend\n$"), "auto loot on and junk dropped: a red notice in ui_notices.dat (the Notices window)")
check(yells() == 0, "and nothing about it in the Messages window any more")
check((junk_view().warning or ""):find("Auto%-Collect Scattered Loot") ~= nil, "and the window's Auto Junk List view shows the warning over the bag")
check((hud.autoloot or "") == "", "no extra line is left on the screen")
ui_action("action", "delete")
check(junk_view().action == "delete" and junk_view().warning == nil and notice() == nil, "junk set to delete: the notice and the line go")
ui_action("action", "drop")
check(junk_view().action == "drop" and junk_view().warning ~= nil and notice() ~= nil, "back to drop: both are back")
step(SYNC)
comps.PlayerInput[PLAYER].fromClientSettings.flags = 0x0853
step(70)
check(notice() == nil and junk_view().warning == nil, "auto loot switched off in the game: the notice and the line go")
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
check(tile(junk_view().junk, "^Stone") ~= nil, "the view's junk list shows Stone, added by the command")
f = io.open(TMP .. "\\junk_list.json"); saved = f:read("a"); f:close()
check(saved:find("Material_T1_Stone", 1, true) ~= nil, "and junk_list.json has it")
ui_action("keep", "Material_T1_Stone")
check(tile(junk_view().junk, "^Stone") == nil, "clicking a junk tile takes it off the list")
step(SYNC)
check(not pdata[ACCOUNT]:find("Material_T1_Stone", 1, true), "and off the server half's list")
cmd({ "list" })
cmd({ "clear" })
cmd({ "clear", "yes" })
step(31)
check(#junk_view().junk == 0, "junk clear yes empties the list")

toggle_panel()  -- the other features' tabs (panel rows), as the tests drive them
-- the Minimap tab's marker filters
click("tab:1")
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
click("tab:2")
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
local pl = require("core.players")
check(#pl.ids(SW) == 0, "the player left: core/players.lua no longer lists them")
join_all()  -- and comes back
check(#pl.ids(SW) == 1 and pl.ids(SW)[1] == PLAYER, "EMF reports the player joined: core/players.lua lists their entity id")
local vt = io.open(TMP .. "\\experimental.json"); local visit = vt:read("a"); vt:close()
check(visit:find('"fall":true', 1, true) ~= nil, "but the option stays saved")
step(JOINED and 320 or 40)
check(find_row("No Fall Damage").selected == true and rule_count() == 1, "and it is on again when they are back")
click(find_row("No Fall Damage").button)
step(5)
click("tab:1")
step(2)

-- closing with the same key does not reopen
toggle_panel()
check(window == nil, "the panel closes")
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
-- the party window's data (party.lua): you are in the list, marked
step(40)
for _, data in ipairs(party_down) do channels.party.on_player(nil, { player = 0 }, data) end
local pf = io.open(TMP .. "\\ui_party.dat", "r")
local party = pf and pf:read("a") or ""
if pf then pf:close() end
check(party:find("^source %a+\n") ~= nil and party:find("\nend\n$") ~= nil, "ui_party.dat is written, complete")
check(party:find("\np\t1\t", 1, true) ~= nil, "you are in the party list, marked as you")
check(party:find("\tPlayer\nb\tac13c6c3\t2\t812\tWet\nb\t1234\t1\t-1\tBlessing\n", 1, true) ~= nil,
  "your buffs follow your line: type, slot, seconds left (-1: none), name in your language")
check(not party:find("Secret", 1, true) and not party:find("Stew", 1, true), "buffs the game hides, and one being removed, are left out")
-- test players (core/test_players.lua): asked for in the Party tab, sent back by the server half like real players
local function party_text()
  for _, data in ipairs(party_down) do channels.party.on_player(nil, { player = 0 }, data) end
  party_down = {}
  local f = io.open(TMP .. "\\ui_party.dat", "r")
  local t = f and f:read("a") or ""
  if f then f:close() end
  return t
end
ui_action("view", "experimental")
step(12)
tabs_text = read_tabs()
local pgen = tabs_text:match("view\texperimental\t(%d+)")
check(pgen ~= nil, "the Experimental tab's rows are written")
local three
for line in tabs_text:gmatch("[^\n]+") do
  local f = {}
  for field in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = field end
  if f[1] == "r" and f[2] == "b" and f[9] == "3" then three = f[8] end
end
check(three ~= nil, "the Experimental tab's Debug section has a button for 3 test players")
ui_action("tab", "experimental/" .. pgen .. "/" .. three)
step(70)
local tp = require("core.test_players")
if JOINED then
  check(last_ask == "3", "the request for 3 test players is sent to the server half")
  print("note: the list itself is checked in host mode")
else
  check(tp.count(PLAYER) == 3, "3 test players are set for you")
  party = party_text()
  check(party:find("source server", 1, true) and party:find("\tTest Ayla\n", 1, true) and party:find("\tTest Cora\n", 1, true)
    and not party:find("Test Dain", 1, true), "3 test players come back from the server half in the party list")
  check(party:find("\np\t1\t", 1, true) ~= nil, "you are still in the list, marked as you")
  check(party:find("\tTest Ayla\nb\t%x+\t%d\t%d+\t") ~= nil, "a test player has buffs too, with a timer")
  local ayla = party:match("\n(p\t0\t[^\n]*\tTest Ayla)\n")
  local _, tabs = (ayla or ""):gsub("\t", "")
  local ax, az = (ayla or ""):match("^p\t0\t[^\t]*\t[^\t]*\t[^\t]*\t[^\t]*\t[^\t]*\t(%-?%d+)\t(%-?%d+)\t")
  check(tabs == 9 and tonumber(ax) and tonumber(ax) >= 0 and tonumber(az) >= 0, "each player's line has a place (x and z) before the name")
  local names = {}
  for _, p in ipairs(tp.list(SW, PLAYER)) do names[#names + 1] = p.x and p.name end
  check(#names == 3, "the test players have places around you (for the minimap)")
end
ui_action("view", "-")
step(12)
ui_action("view", "experimental")
step(12)
tabs_text = read_tabs()
pgen = tabs_text:match("view\texperimental\t(%d+)")
local off
for line in tabs_text:gmatch("[^\n]+") do
  local f = {}
  for field in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = field end
  if f[1] == "r" and f[2] == "b" and f[9] == "Off" and not off then off = f[8] end  -- the first Off: the test players' (the log level's comes later)
end
ui_action("tab", "experimental/" .. pgen .. "/" .. off)
step(70)
check(not party_text():find("Test ", 1, true) and tp.count(PLAYER) == 0 and (not JOINED or last_ask == "0"), "Off: the test players are gone")
-- the Settings tab (features/settings.lua): a switch, a slider, a choice and a key, as FlameKit's window clicks them
do
  toggle_panel()
  local tab
  for _, r in ipairs(window.def.rows) do if r.text == "Settings" then tab = r.button end end
  check(tab ~= nil, "FlameKit's window has a Settings tab")
  click(tab)
  check(find_row("Show the clock") == nil and find_row("Key that shows and hides the minimap") == nil, "the Settings tab has no feature's settings")
  click(find_row("^Right Ctrl$").button)
  check(settings.pointer_key == "right_ctrl", "a choice sets the option's value")
  click("tab:1")  -- the Minimap tab has the minimap's keys
  click(find_row("^Change$", ":set:k:map_toggle_key:").button)
  check(find_row("press a key now") ~= nil, "Change waits for a key")
  require("features.settings").key(UI, "F9")
  check(settings.map_toggle_key == "F9", "the next key pressed in the window becomes the key")
  click(find_row("^No key$", ":set:k:map_toggle_key:").button)
  check(settings.map_toggle_key == "", "No key clears it")
  toggle_panel()
end
-- the Auto Junk List's own settings are buttons on its view (ui_list.dat P lines, clicks as "opt"); the log level in Debug
do
  step(12)
  local f = io.open(TMP .. "\\ui_list.dat", "r")
  local list_text = f and f:read("a") or ""
  if f then f:close() end
  check(list_text:find("\nP b:lf_keep_hotbar 1 Exclude Action Bar: ON\t", 1, true) ~= nil, "the Auto Junk List's view has its action bar switch")
  local b_line = list_text:match("\n(B\t[^\n]*)")
  local _, n_tabs = (b_line or ""):gsub("\t", "")
  check(n_tabs == 7 and b_line:find("\tMaterial, tier %d\t") ~= nil, "a bag item comes as an item tile: id, count, command name, rarity, level, type, name")
  ui_action("opt", "b:lf_keep_hotbar")
  step(6)
  check(settings.lf_keep_hotbar == false, "clicking it switches the setting")
  ui_action("opt", "b:lf_keep_hotbar")
  step(6)
  check(settings.lf_keep_hotbar == true, "and back")
  toggle_panel()
  local tab
  for _, r in ipairs(window.def.rows) do if r.text == "Experimental" then tab = r.button end end
  click(tab)
  click(find_row("^Full$", ":dbg:log:full").button)
  check(require("core.kit").debug_level(true) == "full", "the Debug section sets the log level")
  click(find_row("^Normal$", ":dbg:log:normal").button)
  check(require("core.kit").debug_level(true) == "normal", "and back to normal")
  toggle_panel()
end
-- after an update FlameKit's window is asked to open on What's New (once)
do
  local f = io.open(TMP .. "\\ui_open.dat", "r")
  local what = f and f:read("a") or ""
  if f then f:close() end
  check(what == "changes", "after an update FlameKit's window is asked to open on the What's New tab")
end
check(require("core.items").is_keeper("_Material_TX_Trophy_Wolf_Heavy_head"), "a trophy is kept: not offered in the bag list")
-- the server's FlameKit version (features/server_version.lua): an older one gets an orange notice in a joined game
if JOINED then
  step(3700)
  check((ver_asks or 0) >= 1, "the player's game asks the server for its FlameKit version")
  channels.ver.on_player(CW, {}, "0.15.30")
  step(2)
  local f = io.open(TMP .. "\\ui_hud.dat", "r")
  local hud_text = f and f:read("a") or ""
  if f then f:close() end
  check(hud_text:find("notice This server runs FlameKit v0.15.30 (you: v9.9.9): some features are off", 1, true) ~= nil,
    "an older FlameKit on the server gets the orange notice")
  channels.ver.on_player(CW, {}, "9.9.9")
  step(2)
  f = io.open(TMP .. "\\ui_hud.dat", "r")
  hud_text = f and f:read("a") or ""
  if f then f:close() end
  check(not hud_text:find("notice", 1, true), "the same version: no notice")
end
-- a world save on request from the restart helper (features/server_save.lua)
do
  local f = io.open(TMP .. "\\save_now.request", "w"); f:write("1234\n"); f:close()
  step(40)
  local d = io.open(TMP .. "\\save_now.done", "r")
  local done_text = d and d:read("a") or ""
  if d then d:close() end
  check(done_text == "1234", "a save request from the restart helper is answered with its number")
end
print("ALL PASSED (" .. MODE .. ")")
