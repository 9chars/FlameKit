-- features/companions/06_wheel.lua: part 6 of the companion code (the server side), split from npc_probe.lua in 0.15.362
-- (owner 2026-11-20 18:11). The parts run in order in ONE shared environment (features/companions.lua): what was a
-- top-level local is a name in that environment, seen by every part.
-- E opens a wheel on the presser's own screen (FlameKit's game side, channel flamekit/npcwheel). The server checks who
-- may command the companion, again at the pick. There is no other way (a game without FlameKit gets a notice).
-- (owner 2026-11-18 20:09/20:11) "Attack" opens a second wheel with the fight modes: Passive, Defensive, Aggressive,
-- Healing. The mode is kept in the roster (r.fight; a companion without one is Passive) until the player changes it.
-- The game side sends back the label it showed, so a pick is matched by its label.
WHEEL = "npcwheel"
WHEEL_LABELS = { "Follow me", "Stay here", "Attack", "Inventory", "Put away", "Companions" }  -- Companions: owner 15:39
inv.WHEEL = { "Close Chest" }  -- (owner 08:02) while his chest is open the wheel offers only this
-- (owner 14:49 "the wheel for pets would need to be different than the wheel for the monster companions"; 14:59 "lets
-- try it") a pet's wheel: no Attack (pets do not fight), and Pet (roster.do_pet: his next E is the game's petting)
PET_WHEEL = { "Follow me", "Stay here", "Pet", "Inventory", "Put away", "Companions" }
FIGHT_MODES = { "Passive", "Defensive", "Aggressive", "Healing" }

function refuse(world, player, rr)
  local who = {}
  for _, a in ipairs(rr.controllers or {}) do who[#who + 1] = (rr.names or {})[a] or "someone else" end
  say(world, player, rr.name .. ": " .. (#who > 0 and ("This companion belongs to " .. table.concat(who, ", ") .. ".") or "This companion is not yours."))
end


function do_follow(world, player, npc, rr)
  drives[npc] = { player = player, trail = {} }
  calm(world, npc)
  log(string.format("E: %s follows player %s", tostring(npc), tostring(player)))
  if rr then rr.mode, rr.owner = "follow", world:account(player) roster_save() end
  say(world, player, (rr and (rr.name .. ": ") or "") .. "Following you.")
end

function do_stay(world, player, npc, rr)
  drives[npc] = nil
  local x, y, z = world:position(npc)
  stay_at(world, npc, x, y, z)
  log(string.format("E: %s stays at %.1f %.1f %.1f", tostring(npc), x, y, z))
  if rr then rr.mode, rr.x, rr.y, rr.z = "stay", x, y, z roster_save() end
  say(world, player, (rr and (rr.name .. ": ") or "") .. "Staying here.")
end

function do_away(world, player, npc, rr)
  if not rr then say(world, player, "Not on the list: cannot be put away.") return end
  local x, y, z = world:position(npc)
  if x and rr.mode == "stay" then rr.x, rr.y, rr.z = x, y, z end
  drives[npc], name_of[npc] = nil, nil
  pcall(emf.destroy, world, npc)
  ent_of[rr.name], rr.out = nil, false
  roster_save()
  log(string.format("E: %s put away", rr.name))
  say(world, player, rr.name .. ": Put away.")
end

-- the Attack wheel: the four fight modes, the current one named in the title
function do_attack_menu(world, player, npc, rr)
  if not rr then say(world, player, "Not on the list: no fight modes.") return end
  local oks, sent = pcall(emf.net.send_to, world, player, WHEEL, emf.json.encode({ op = "wheel", npc = npc,
    title = rr.name .. ": Attack (now " .. (rr.fight or "Passive") .. ")", labels = FIGHT_MODES }))
  log(string.format("E: attack wheel for %s (%s, now %s) sent to player %s: %s", tostring(npc), rr.name, rr.fight or "Passive",
    tostring(player), tostring(oks and sent)))
end

-- a fight mode picked: kept in the roster
function set_fight(world, player, npc, rr, mode)
  if not rr then return end
  local was = rr.fight or "Passive"
  rr.fight = mode
  roster_save()
  log(string.format("fight: %s (%s) %s -> %s (player %s)", rr.name, tostring(npc), was, mode, tostring(player)))
  say(world, player, rr.name .. ": " .. mode .. ".")
end

on_talk = function(world, player, npc)
  log(string.format("E pressed on %s by player %s", tostring(npc), tostring(player)))
  local rr = name_of[npc] and find(name_of[npc])
  local account = world:account(player)
  if rr and not may_command(rr, account) then
    log(string.format("E: %s refused for %s (controllers %s)", rr.name, tostring(account), table.concat(rr.controllers or {}, ",")))
    refuse(world, player, rr)
    return
  end
  if rr and inv.open[rr.name] then  -- (owner 08:22) E closes his open chest at once, no wheel
    inv.close(world, rr, "the player", player)
    return
  end
  local okp, ver = pcall(emf.net.peer, world, player, WHEEL)
  if not (okp and (tonumber(ver) or 0) > 0) then
    say(world, player, "This companion needs FlameKit in your game.")
    return
  end
  local oks, sent = pcall(emf.net.send_to, world, player, WHEEL, emf.json.encode({ op = "wheel", npc = npc,
    title = rr and rr.name or "Companion", labels = (rr and inv.open[rr.name]) and inv.WHEEL
      or (world:get("DynamicWildlife", npc) and not world:get("DynamicEnemy01BehaviorState", npc)) and PET_WHEEL or WHEEL_LABELS }))
  log(string.format("E: wheel for %s sent to player %s: %s", tostring(npc), tostring(player), tostring(oks and sent)))
end

-- "Call my companion" (P, the Experimental panel, and every return after a put-away): the main companion's old body,
-- if any (alive, dead or stuck anywhere), is removed and a fresh one is spawned beside the player, following him
function on_call(world, from)
  local player, account = from.player, from.account
  local x, y, z = world:position(player)
  if not x then return end
  local r = roster.main[account] and find(roster.main[account])
  if not r or not controls(r, account) then
    if r then roster.main[account] = nil roster_save() end
    say(world, player, "You have no companion yet.")
    return
  end
  if inv.open[r.name] then  -- (owner 2026-11-20 08:13) no call while his chest is open
    say(world, player, r.name .. ": Close the chest first.")
    log(string.format("call: %s refused for %s: his chest is open", r.name, tostring(account)))
    return
  end
  local old = ent_of[r.name]
  if old then
    drives[old], name_of[old] = nil, nil
    pcall(emf.destroy, world, old)
    ent_of[r.name] = nil
  end
  r.mode, r.owner = "follow", account
  -- 0.3 m to the player's right (his facing: forward = (sin yaw, cos yaw), right = (cos yaw, -sin yaw))
  local pyaw
  pcall(function()
    local o = world:get("CurrentTransform", player).transform.orientation
    local yaw = math.atan(2 * (o.x * o.z + o.w * o.y), 1 - 2 * (o.x * o.x + o.y * o.y))
    x, z = x + math.cos(yaw) * 0.3, z - math.sin(yaw) * 0.3
    pyaw = yaw
  end)
  local id = spawn_body(world, r, x, y + 0.5, z, player)
  -- his body turned the way the player faces, now and again when he is set up half a second later (bring_to_life)
  if id and pyaw then
    r.face_yaw = pyaw
    pcall(function()
      local o = world:get("CurrentTransform", id).transform.orientation
      o.x, o.y, o.z, o.w = 0, math.sin(pyaw / 2), 0, math.cos(pyaw / 2)
    end)
  end
  roster_save()
  -- every time he spawns beside the player: "Companion has spawned near you!"
  status(world, player, "companion_away", nil)
  status(world, player, "companion_stuck", nil)
  pcall(function() require("features.chat").notice_to(world, player, "Companion has spawned near you!", "#8cd2ff", 5) end)
  log(string.format("call: %s (main of %s) respawned on player %s as %s (old body %s)", r.name, account,
    tostring(player), tostring(id), tostring(old)))
end

function on_pick(world, from, data)
  local okd, m = pcall(emf.json.decode, data)
  if okd and type(m) == "table" and m.op == "call" then return on_call(world, from) end
  if okd and type(m) == "table" and m.op == "prefs" then  -- (owner 16:20) the player's "Companion follow notices"
    if from.account and (F.notice_pref[from.account] == true) ~= (m.notices == true) then
      F.notice_pref[from.account] = m.notices == true or nil
      log(string.format("prefs: player %s (%s): follow notices %s", tostring(from.player), tostring(from.account), m.notices == true and "on" or "off"))
    end
    -- (owner 17:46) the answer: whether he is an admin (his game greys the Companion Roster button out otherwise)
    pcall(emf.net.send_to, world, from.player, WHEEL, emf.json.encode({ op = "admin", admin = is_admin(from.account) }))
    return
  end
  if not (okd and type(m) == "table" and m.op == "pick") then return end
  local npc, player = tonumber(m.npc), from.player
  local rr = npc and name_of[npc] and find(name_of[npc])
  log(string.format("wheel: player %s picked %s (%s) for %s", tostring(player), tostring(m.choice), tostring(m.label), tostring(npc)))
  if not (npc and world:position(npc)) then return end
  if rr and not may_command(rr, from.account) then refuse(world, player, rr) return end
  local label = type(m.label) == "string" and m.label or ""
  -- (owner 15:39) a pick in the Companions wheel (roster.wheel_list): that companion comes to the player
  local cw = roster.cw and roster.cw[player]
  if cw and cw.map[label] and world:tick() - cw.at < 3600 then
    roster.cw[player] = nil
    local okb, errb = pcall(roster.wheel_summon, world, player, cw.map[label])
    if not okb then log("wheel: Companions failed: " .. tostring(errb)) say(world, player, "Cannot do that (see the server's log).") end
    return
  end
  local act = ({ ["Follow me"] = do_follow, ["Stay here"] = do_stay, ["Attack"] = do_attack_menu, ["Put away"] = do_away,
    ["Inventory"] = inv.open_chest, ["Close Chest"] = inv.close_chest,
    ["Pet"] = function(w, pl, n, r) roster.do_pet(w, pl, n, r) end,
    ["Companions"] = function(w, pl, n, r) roster.wheel_list(w, pl, n, r) end })[label]
  if rr and inv.open[rr.name] and label ~= "Close Chest" then act = nil end  -- an old wheel: only "Close Chest" now
  for _, mode in ipairs(FIGHT_MODES) do
    if label == mode then act = function(w, pl, n, r) set_fight(w, pl, n, r, mode) end end
  end
  if not act then return end
  local ok, err = pcall(act, world, player, npc, rr)
  if not ok then log("wheel: failed: " .. tostring(err)) say(world, player, "Cannot do that (see the server's log).") end
end
