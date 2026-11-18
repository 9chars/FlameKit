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
    { separator = true } }
end

local function send_call(why)
  local oks, sent = pcall(emf.net.send, CHANNEL, emf.json.encode({ op = "call" }))
  log("call sent (" .. why .. "): " .. tostring(oks and sent))
end

function F.click(world, key)
  if key == "npc:call" then send_call("button") end
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
  -- (owner 2026-11-18 07:06: "a key binding on P and make that action call the companion") the same as the
  -- "Call my companion" button, on the client world
  local okk, errk = pcall(emf.on_key, "P", function(world) send_call("P key") end, "client")
  log("P key: " .. tostring(okk and errk ~= false or errk))
end

return F
