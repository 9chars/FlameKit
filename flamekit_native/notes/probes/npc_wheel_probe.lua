-- npc_wheel_probe.lua (2026-11-17, owner: "I want to move away from windows panels and buttons ... move my interactions
-- more into the game"). TEMPORARY test file for the owner's own game only: when he presses E on one of his NPCs the
-- local test server sends "open the wheel" on the channel flamekit/npcwheel; this opens EMF's radial wheel on his
-- screen and sends his pick back. The server decides everything (who may, what happens).
local F = { id = "npc_wheel_probe", title = "NPC Wheel Probe" }

local CHANNEL = "npcwheel"

local function log(s) emf.log("[flamekit] npc wheel: " .. s) end

local function on_message(world, from, data)
  local okd, m = pcall(emf.json.decode, data)
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

function F.setup(k)
  local ok = emf.net.channel(CHANNEL, { version = 1, to = "both", max = 1024, per_10s = 60,
    on_player = function(world, from, data)
      local okm, err = pcall(on_message, world, from, data)
      if not okm then log("failed: " .. tostring(err)) end
    end,
    on_server = function() end })
  log("channel: " .. tostring(ok))
end

return F
