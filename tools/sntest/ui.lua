-- (0.15.539) the Spawn Nodes tab and window: rows for every trigger, with and without nodes; no errors; every label
-- that starts a line is followed by a drop-down on it (a form row) or is a node line.
-- usage: texlua tools/sntest/ui.lua flamekit/features/spawn_nodes.lua
package.path = (arg[0]:match("(.*/)") or "./") .. "?.lua;" .. package.path
package.path = (arg[1]:match("(.*/)features/") or "./") .. "?.lua;" .. package.path
local M = require("mock")
local F = dofile(arg[1])
F.setup(M.kit)
local W = M.world
local fails = 0
local function ok(c, what) if c then print("ok   " .. what) else fails = fails + 1 print("FAIL " .. what) end end
M.player(1, 0, 0, 0)
local function run(sec) for _ = 1, math.floor(sec * 60) do F.tick(W) M.advance(1 / 60) end end
run(0.2)
emf.local_player = function() return 1 end  -- the player of the tab and window is player 1 (acc1, an admin in the mock?)
local function check(rows)
  local bad = 0
  for i, r in ipairs(rows) do
    if r.label and not r.same_line and not (rows[i + 1] and rows[i + 1].options and rows[i + 1].same_line) then bad = bad + 1 print("  lone label: " .. tostring(r.text)) end
  end
  return bad
end
local function show(rows, what)
  if os.getenv("SHOW") then
    print("---- " .. what)
    for _, r in ipairs(rows) do
      print(string.format("%s%s %s", r.same_line and "    + " or "", r.heading and "##" or r.label and "[L]" or r.options and "[v]" or r.button and "[B]" or r.dim and "(d)" or "", tostring(r.heading or r.text)))
    end
  end
end
local okp0, rows0 = pcall(F.panel, W)
ok(okp0 and check(rows0) == 0, "tab with no groups: " .. (okp0 and #rows0 or -1) .. " rows")
local okw0, wr0 = pcall(F.window_rows, W)
ok(okw0, "window with no groups")
F._handle(W, "acc1", 1, { op = "new_group" }, {})
for _, trig in ipairs({ "manual", "timer", "wire", "time", "raid" }) do
  F._handle(W, "acc1", 1, { op = "set", g = 1, key = "trigger", value = trig }, {})
  F._handle(W, "acc1", 1, { op = "set", g = 1, key = "breaks", value = trig == "timer" }, {})
  for _, add in ipairs({ 0, 2 }) do
    for k = 1, add do M.ents[1].x = 10 * k F._handle(W, "acc1", 1, { op = "add_node", g = 1 }, {}) end
    M.ents[1].x = 0
    local okp, rows = pcall(F.panel, W)
    ok(okp and type(rows) == "table" and #rows > 10 and check(rows) == 0, string.format("tab, trigger %s: %d rows", trig, okp and #rows or -1))
    if not okp then print("  " .. tostring(rows)) else show(rows, "tab " .. trig) end
    local okw, wr = pcall(F.window_rows, W)
    ok(okw and type(wr) == "table" and #wr > 4, string.format("window, trigger %s: %d rows", trig, okw and #wr or -1))
    if not okw then print("  " .. tostring(wr)) else show(wr, "window " .. trig) end
  end
end
-- the window button writes the toggle request
os.remove(emf.dir .. "\\ui_nodes_toggle.request")
F.click(W, "window")
local f = io.open(emf.dir .. "\\ui_nodes_toggle.request", "r")
ok(f ~= nil, "the Spawn Nodes window button asks FlameKit Native to show it")
if f then f:close() end
print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
