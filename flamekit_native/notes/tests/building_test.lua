-- features/building.lua (0.15.452): Free build's switch, PvP, Bigger altar areas, remembered spots, the files.
-- texlua flamekit_native/notes/tests/building_test.lua   (from the repo's top folder)
package.path = "flamekit/?.lua;" .. package.path
local fails = 0
local function check(ok, what) print((ok and "ok   " or "FAIL ") .. what) if not ok then fails = fails + 1 end end

local files, store, logs, announced = {}, {}, {}, {}
local dir = "D"
local function fake_open(path, mode)
  local name = path:match("[^\\]+$")
  if mode == "r" then
    local text = files[name]
    if not text then return nil end
    return { lines = function() return text:gmatch("[^\n]+") end, close = function() end, read = function() return text end }
  end
  local buf = {}
  return { write = function(_, ...) for _, x in ipairs({ ... }) do buf[#buf + 1] = x end end,
           close = function() files[name] = table.concat(buf) end }
end
io.open = fake_open
emf = { dir = dir, log = function(s) logs[#logs + 1] = s end, local_player = function() return 1 end,
  json = { encode = function(t) return t end, decode = function(t) return t end },
  net = { channel = function() return true end, send = function() return true end, send_to = function() return true end,
          peer = function() return 1 end } }
package.loaded["core.players"] = { setup = function() end, ids = function() return { 1, 2 } end,
  name = function(w, id, fb) return "P" .. id end }
package.loaded["core.game_events"] = { on = function() return true end }
package.loaded["core.admins"] = { is = function(account, from) return account == "0xa1" end }
package.loaded["features.chat"] = { announce = function(w, line) announced[#announced + 1] = line end }
local kit = { guard = function(F, fn) return fn end, is_host = function() return true end,
  store = { load = function(name, default) if store[name] ~= nil then return store[name] end return default end,
            save = function(name, v) store[name] = v return true end } }
store.experimental = { ["0xa1"] = { freebuild = true, shroud = true }, ["0xb2"] = { shroud = true } }
local pos = { [1] = { 100, 50, 100 }, [2] = { 900, 50, 900 } }
local W = { is_server = function() return true end, account = function(self, id) return ({ [1] = "0xa1", [2] = "0xb2" })[id] end,
  position = function(self, id) local p = pos[id] if p then return p[1], p[2], p[3] end end }

local B = require("features.building")
B.setup(kit)
local st = B._state(W, "0xa1", 1, nil)
check(st.freebuild == true and store.building and store.building.freebuild["0xa1"] == true, "Free build copied from experimental.json")
check(B._state(W, "0xb2", 2, nil).freebuild == nil, "a player without it: off")
for _ = 1, 30 do B.tick(W) end
check(files["free_build_server.txt"] == "1\n", "the server's list: player 1 only")
check(files["altar_size_server.txt"] == "1.5\n", "bigger altar areas on by default")

local pvp = require("core.pvp_state")
pvp.set("0xa1", true)
for _ = 1, 30 do B.tick(W) end
check(files["free_build_server.txt"] == "", "in PvP: nobody on the list")
check(B._handle(W, "0xa1", 1, { op = "set", key = "freebuild", on = true }).note == "Off while you are in PvP.", "switching on in PvP: refused")
pvp.set("0xa1", false)

B._handle(W, "0xb2", 2, { op = "set", key = "freebuild", on = true })
check(store.building.freebuild["0xb2"] == true and #announced == 1 and announced[1]:find("ON free build"), "switched on, saved, told")
check(B._handle(W, "0xb2", 2, { op = "set", key = "bigaltars", on = false }).note:find("Only FlameKit admins"), "bigger altar areas: admins only")
B._handle(W, "0xa1", 1, { op = "set", key = "bigaltars", on = false })
for _ = 1, 30 do B.tick(W) end
check(store.experimental_world.bigaltars == false and files["altar_size_server.txt"] == "1\n", "an admin switched it off")

files["altar_areas_server.txt"] = "0 0 0 50 100 50\n"
B._on_place(W, { ownerId = 1, position = { x = 10, y = 10, z = 10 } })
check(next(store.free_build_spots or {}) == nil, "a piece in an altar area: no spot")
B._on_place(W, { ownerId = 1, position = { x = 100, y = 50, z = 100 } })
local n = 0 for _ in pairs(store.free_build_spots or {}) do n = n + 1 end
check(n == 1 and files["free_build_spots.txt"] == "112.0 48.0 112.0\n", "a piece outside: its 32 m cell remembered")
B._on_place(W, { ownerId = 1, position = { x = 129, y = 50, z = 100 } })
n = 0 for _ in pairs(store.free_build_spots) do n = n + 1 end
check(n == 1, "a piece over the grid line but inside the spot's area: no new spot")
B._handle(W, "0xa1", 1, { op = "set", key = "freebuild", on = false })
B._on_place(W, { ownerId = 1, position = { x = 500, y = 50, z = 500 } })
n = 0 for _ in pairs(store.free_build_spots) do n = n + 1 end
check(n == 1, "Free build off: no spot")
B._handle(W, "0xa1", 1, { op = "set", key = "freebuild", on = true })

local s1 = B._state(W, "0xa1", 1, nil)
check(s1.spot.total == 1 and s1.spot.key and s1.spot.dist == 17, "the tab: the nearest spot and how far")
check(B._handle(W, "0xb2", 2, { op = "forget_spot" }).note:find("Only FlameKit admins"), "forget: admins only")
check(B._handle(W, "0xa1", 1, { op = "forget_spot" }).note:find("Forgot the spot at 112, 112"), "forget this spot")
check(files["free_build_spots.txt"] == "", "the spots file empty again")

for i = 1, 100 do store.free_build_spots[i .. ",0,0"] = { i * 32 + 16, 16, 16 } end
B._reset() store.free_build_spots = store.free_build_spots
B._on_place(W, { ownerId = 1, position = { x = 5000, y = 50, z = 5000 } })
n = 0 for _ in pairs(store.free_build_spots) do n = n + 1 end
check(n == 100 and B._state(W, "0xa1", 1, nil).note:find("limit of 100"), "at 100 spots: not kept, the player told")
check(B._handle(W, "0xa1", 1, { op = "forget_all_spots" }).note:find("Forgot all 100"), "forget all spots")

local rows = B.panel(W)
local keys = {}
for _, r in ipairs(rows) do if r.button then keys[#keys + 1] = r.button .. (r.disabled and "(off)" or "") end end
check(table.concat(keys, " ") == "b:free b:big b:forget(off) b:forgetall(off)", "the tab's buttons, always shown: " .. table.concat(keys, " "))
print(fails == 0 and "ALL PASSED (building)" or (fails .. " FAILED"))
