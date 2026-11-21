-- the Companion Roster window's rows and clicks (features/npc_wheel_probe.lua); run it from the flamekit folder:
--   cd flamekit && texlua ../local_server/tests/rostui.lua
package.path = "./?.lua;" .. package.path
local chans = {}
local sent = {}
emf = setmetatable({ log = print, dir = "/tmp",
  json = { decode = function(d) return d end, encode = function(t) return t end },
  net = { channel = function(name, def) chans[name] = def return true end, send = function(ch, m) sent[#sent+1] = m return true end },
  on_key = function() return true end, wheel = function() end }, { __index = function() return function() end end })
local F = dofile("features/npc_wheel_probe.lua")
F.setup({ notice = function() end })
local tick = 1000
local W = { tick = function() return tick end }
-- (0.15.375) a game that is not an admin never asks the server for the roster
for i = 1, 5 do F.roster_rows(W) tick = tick + 400 end
local asked = 0
for _, m in ipairs(sent) do if m.op == "get" then asked = asked + 1 end end
print("not an admin: asks", asked, "(want 0)")
chans.npcwheel.on_player(W, {}, { op = "admin", admin = true })
F.roster_rows(W)
asked = 0
for _, m in ipairs(sent) do if m.op == "get" then asked = asked + 1 end end
print("an admin: asks", asked, "(want 1)")
print(#F.roster_rows(W), "rows before data")
chans.roster.on_player(W, {}, { op = "roster", list = {
  { n = "N1", k = "18eefd30-da1d-49f5-a6d8-7da8f2d01f43", o = "0xa", m = "follow", f = "Passive", out = true, it = 1, ch = false, main = true, c = { "0xa", "0xb" } },
  { n = "N2", k = "nope", o = "0xa", m = "stay", out = false, it = 0, ch = true, main = false, c = { "0xa" } } },
  players = { { a = "0xa", n = "Midevil", on = true }, { a = "0xb", n = "Bob", on = false } } })
local rows = F.roster_rows(W)
for _, r in ipairs(rows) do
  print(r.separator and "---" or r.heading and ("H " .. r.heading) or r.edit and ("E " .. r.edit .. " [" .. r.text .. "]") or r.options and ("D " .. r.text .. " (" .. #r.options .. ")" .. (r.disabled and " disabled" or "")) or r.label and ("L " .. tostring(r.text)) or r.button and ("B " .. r.text .. " -> " .. r.button .. (r.disabled and " disabled" or "")) or ("T " .. tostring(r.text)))
end
F.roster_click(W, "ros:rename:N1", "Rex") print("sent", sent[#sent].what, sent[#sent].name, sent[#sent].arg)
F.roster_click(W, "ros:kind:N1:d5d05217-52dc-467a-9192-26b4f661d8d9", nil) print("sent", sent[#sent].what, sent[#sent].arg)
local n = #sent
F.roster_click(W, "ros:delete:N2", nil) print("first delete click sends?", #sent > n)
F.roster_click(W, "ros:delete:N2", nil) print("second sends", sent[#sent].what, sent[#sent].name)
F.click(W, "npc:roster") print("toggle file", io.open("/tmp\\ui_roster_toggle.request") ~= nil, sent[#sent].op)
