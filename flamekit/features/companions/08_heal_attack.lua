-- features/companions/08_heal_attack.lua: part 8 of the companion code (the server side), split from npc_probe.lua in 0.15.362
-- (owner 2026-11-20 18:11). The parts run in order in ONE shared environment (features/companions.lua): what was a
-- top-level local is a name in that environment, seen by every part.
-- ===== Healing (owner 2026-11-19 19:21-21:01) ===========================================================================
-- The game gives him no mana and no health recharge (log 19:21: only Health and Stamina), so his mana is FlameKit's own
-- number (owner 19:25 "I would give him 800 mana and see how that works?"), refilling in every mode. A heal goes through
-- the game's attribute code (emf.attribute_add "health": stops at the maximum, not a hit) and plays Wolf Shout
-- (combatData.selectedAttackIndex 2 -> the C++ starts 0x89A1BC53; owner 20:59 "I want Wolf Shout", 21:01 "every heal
-- would be a good queue that its happening"). Who and when (owner 20:35 "yes that would be good"; 22:04 "when he's in
-- heal mode, he should just always heal me to full, when he's in attack or defense I meant more like when all the
-- attack sequences are all done, he should do full heals on himself and me, but can wait until all attack sequences
-- are done"):
--   Healing: the player (within FIGHT_RANGE) up to full, always; else himself below HEAL_BELOW;
--   Defensive / Aggressive: in an attack sequence only himself, below HEAL_BELOW_FIGHT (the mana lasts the fight); with
--   no attack sequence going on, the player and then himself up to full;
--   Passive: no heals; a slow recovery once he has not been hit for RECOVER_AFTER (no mana, no shout).
-- Not while one of his attacks plays (the shout would cut it). Logs "heal <name>: ...".
MANA_MAX, MANA_REFILL = 800, 10                     -- refill: a second
HEAL_PART, HEAL_COST, HEAL_GAP = 0.25, 100, 240     -- 25 % of the target's maximum, 100 mana (owner 2026-11-20
                                                          -- 15:16 "that seems high", 15:17: 100, was 200), 4 s apart
HEAL_BELOW, HEAL_BELOW_FIGHT = 0.6, 0.4
HEAL_FULL = 0.99                                    -- "full": a heal only when 1 % or more is missing
RECOVER_AFTER, RECOVER_PART = 600, 0.02             -- Passive: 10 s without a hit, then 2 % of his maximum a second
mana_of = {}                                        -- companion name -> mana
-- (owner 2026-11-19 22:09 "is there way to add an healing spakle animations?") the game's heal effects (VFX templates),
-- for the console preview "flamekit.npc healfx <n>" (spawned on the player for 10 s)
HEAL_FX = {
  { "VFX_Resource_Increase_Health", "2c411630-8a38-41a3-b3d2-a263609a1bdb" },
  { "VFX_Resource_Increase_Health_NoSound", "b8e9aca9-8713-4c4c-b51c-1591e74873b4" },
  { "VFX_Enemy_Skeleton_Melee_Elite_Heal_Ally_Player_Companion", "35183e7f-6b43-45da-a58c-c057f0c2f82e" },
  { "VFX_Enemy_Skeleton_Melee_Elite_Heal_Ally", "100772b0-a866-4d80-b9a8-a6052ccd0149" },
  { "VFX_Skill_Martyr_Heal", "21443035-d89f-40c5-bf61-009b8aaa413a" },
  { "VFX_Ability_Casting_Heal_Channel", "af4436da-8e80-436a-aa35-5cdf1f0b994e" },
  { "VFX_Spell_ChainHeal_SourceTarget_player", "fc4f8028-078d-4051-8cf1-33ddb08e72a6" },
  { "VFX_Spell_ChainHeal_SourceTarget_NoTarget", "c15e5bc4-6dc7-4b86-a27c-91d1db7cd5aa" },
}
heal_fx_shown = {}
SHOUT_TICKS = 90                                    -- the shout plays this long before his next attack

drive_heal = function(s)
  local world, id, h, t, a = s.world, s.id, s.h, s.t, s.a
  local name = tostring(name_of[id] or id)
  -- (owner 2026-11-20 15:22 "lets give the pets the same heal ability, same sparkle and that mode is just always
  -- active") a pet is always in Healing mode: the same mana, heals and sparkle; no Wolf Shout (an animal has none) and
  -- no self heal (pets take no damage)
  local pet = s.pet
  local mode = pet and "Healing" or fight_mode(id)
  local m = math.min(MANA_MAX, (mana_of[name] or MANA_MAX) + MANA_REFILL / 60)
  mana_of[name] = m
  local hp, hmax
  pcall(function() local d = world:get("Health", id).dataStorage hp, hmax = tonumber(d[1]), tonumber(d[3]) end)
  if not pet and not (hp and hmax and hp > 0) then return end
  if mode == "Passive" then
    if hp < hmax and t - (h.hit_t or -1e9) >= RECOVER_AFTER then
      if t % 60 == 0 then
        local okr, res = pcall(emf.attribute_add, world, id, "health", math.ceil(hmax * RECOVER_PART))
        if not h.recover_said then
          h.recover_said = true
          log(string.format("heal %s: recovers (Passive, not hit for %d s): %d/%d, +%d a second%s", name, RECOVER_AFTER / 60,
            hp, hmax, math.ceil(hmax * RECOVER_PART), (okr and res) and "" or " (could not add health: " .. tostring(res) .. ")"))
        end
      end
    elseif h.recover_said and hp >= hmax then
      h.recover_said = nil
      log(string.format("heal %s: recovered (%d/%d)", name, hp, hmax))
    end
    return
  end
  if t - (h.heal_t or -1e9) < HEAL_GAP then return end
  if not pet and not h.fight_init then return end  -- the fight's first step clears any move asked for: the shout would be lost
  local who, whp, wmax, whom
  local php, pmax = tonumber(emf.attribute(world, h.player, "health")), tonumber(emf.attribute(world, h.player, "max_health"))
  local px, py, pz = world:position(h.player)
  local near = px and (px - s.nx) ^ 2 + (py - s.ny) ^ 2 + (pz - s.nz) ^ 2 <= FIGHT_RANGE ^ 2
  local player_hurt = php and pmax and php > 0 and php < pmax * HEAL_FULL and near
  if mode == "Healing" then
    if player_hurt then
      who, whp, wmax, whom = h.player, php, pmax, "the player"
    elseif not pet and hp < hmax * HEAL_BELOW then
      who, whp, wmax, whom = id, hp, hmax, "himself"
    end
  elseif mode == "Defensive" or mode == "Aggressive" then
    if h.atk then
      if hp < hmax * HEAL_BELOW_FIGHT then who, whp, wmax, whom = id, hp, hmax, "himself" end
    elseif player_hurt then
      who, whp, wmax, whom = h.player, php, pmax, "the player"
    elseif hp < hmax * HEAL_FULL then
      who, whp, wmax, whom = id, hp, hmax, "himself"
    end
  end
  if not who then return end
  if m < HEAL_COST then
    if not h.nomana_said then
      h.nomana_said = true
      log(string.format("heal %s: would heal %s (%d/%d) but has %d mana of %d needed", name, whom, whp, wmax, math.floor(m), HEAL_COST))
    end
    return
  end
  h.nomana_said = nil
  if h.atk and h.atk.atk then return end  -- one of his attacks is playing: after it
  if not pet then
    local okq, asked = pcall(function() return (tonumber(a.combatData.selectedAttackIndex) or 255) ~= 255 end)
    if okq and asked then return end
  end
  local amount = math.ceil(wmax * HEAL_PART)
  local okh, res = pcall(emf.attribute_add, world, who, "health", amount)
  if not pet then pcall(function() a.combatData.selectedAttackIndex = 2 end) end  -- Wolf Shout
  mana_of[name] = m - HEAL_COST
  h.heal_t = t
  -- (owner 2026-11-19 22:18 "when the dog heals himself he can do the effect, when he heals the player he can do the
  -- effect on himself and me to highly the heal") the game's health-gain effect (HEAL_FX 1, the only one the owner saw)
  if okh and res then
    local function sparkle(e)
      local x, y, z = world:position(e)
      if not x then return end
      local oks, fid = pcall(emf.spawn, world, HEAL_FX[1][2], x, y, z)
      if oks and fid and fid ~= 0 then heal_fx_shown[#heal_fx_shown + 1] = { id = fid, at = t + 600 } end
    end
    sparkle(id)
    if who == h.player then sparkle(h.player) end
  end
  -- (owner 2026-11-19 21:29 "can you add a notice message that says Companion heals you for <number>!")
  -- (0.15.377, owner 2026-11-21 09:35 "should say which companion is healing you by name"; 09:44 "notice messages should
  -- stay for heals": the notice stays, its line goes to the Battle tab instead of the Messages window's Chat)
  if who == h.player and okh and res then
    pcall(function() require("features.chat").notice_to(world, h.player, string.format("%s heals you for %d!", name, amount), "#5ad25a", 5, { quiet = true }) end)
  end
  if okh and res then pcall(function() require("core.msg_feed").heal(world, id, who, amount) end) end
  log(string.format("heal %s: heals %s +%d (%d/%d before; %s mode%s); mana %d -> %d of %d%s%s", name, whom, amount, whp, wmax,
    mode, pet and ", pet" or "", math.floor(m), math.floor(m - HEAL_COST), MANA_MAX, pet and "" or "; Wolf Shout",
    (okh and res) and "" or " (could not add health: " .. tostring(res) .. ")"))
end

drive_fight = function(s)
  local world, id, h, a, t = s.world, s.id, s.h, s.a, s.t
  local cd = a.combatData
  local name = tostring(name_of[id] or id)
  local px, py, pz, nx, ny, nz = s.px, s.py, s.pz, s.nx, s.ny, s.nz
  if not h.fight_init then
    h.fight_init = true
    pcall(function() cd.selectedAttackIndex = 255 end)
  end
  local function clear_target()
    pcall(function() if cd.lastTargetId ~= 0 then cd.lastTargetId = 0 end end)
  end
  local function the_end(why)
    if h.atk then log(string.format("fight %s: the attack sequence ends: %s", name, why)) end
    h.atk = nil
    clear_target()
  end
  local mode = fight_mode(id)
  local hp, hmax
  pcall(function() local d = world:get("Health", id).dataStorage hp, hmax = tonumber(d[1]), tonumber(d[3]) end)
  if mode ~= "Defensive" and mode ~= "Aggressive" then the_end("mode " .. mode) return false end
  if s.pwet then the_end("the player swims") return false end
  if not hp or hp <= 0 then the_end("he is down") return false end
  local dpl = math.sqrt((px - nx) ^ 2 + (py - ny) ^ 2 + (pz - nz) ^ 2)
  if dpl > FIGHT_RANGE + FIGHT_BITE then the_end(string.format("he is %.1f m from the player, outside the %d m radius", dpl, FIGHT_RANGE)) return false end
  -- his hits since the last step (the hit handler notes them): on his target or on something else
  local hits = h.my_hits or {}
  h.my_hits = nil
  local A = h.atk
  if not A then
    clear_target()
    if t % 30 ~= 0 then return false end
    local list = fight_candidates(world, id, h, mode, px, py, pz, nx, ny, nz)
    if #list == 0 then return false end
    -- Defensive: something attacked; he fights every monster near the player until the sequence ends (owner
    -- 2026-11-19 10:25: "it should automatically switch to aggressive mode to keep fighting all monsters in the near
    -- area as any monsters around won't stop fighting"); the menu's mode stays Defensive
    A = { phase = "pick", list = list, i = 1, tries = 1, t = t, wide = mode == "Defensive" }
    h.atk = A
    log(string.format("fight %s: the attack sequence starts (%s%s): %d candidate(s), the nearest %s at %.1f m", name, mode,
      A.wide and ", something attacked: he fights like Aggressive until it ends" or "", #list, tostring(list[1].id), list[1].d))
  end
  local function hold_still() hold_at(a, nx, ny, nz) return true end
  local smode = (A.wide and mode == "Defensive") and "Aggressive" or mode
  local function repick(why)
    A.phase, A.target, A.list, A.i, A.tries, A.t, A.checking, A.atk = "pick", nil, nil, 1, 1, t, nil, nil
    A.best_d, A.prog_t, A.stall_said = nil, nil, nil
    A.rep, A.rep_t, A.ok_d, A.ok_t, A.base = 0, nil, nil, t, nil
    A.list = fight_candidates(world, id, h, smode, px, py, pz, nx, ny, nz)
    log(string.format("fight %s: picks again (%s): %d candidate(s)", name, why, #A.list))
  end
  -- picking
  if A.phase == "pick" then
    local c = A.list[A.i]
    while c and not (world:position(c.id) and monster_alive(world, c.id)) do
      A.i = A.i + 1
      c = A.list[A.i]
    end
    if not c then
      clear_target()
      if t - A.t >= PICK_EVERY then
        if A.tries >= PICK_TRIES then
          -- the blocked ones are dropped like a target he gave up on (else the sequence starts again on them at once)
          local n = 0
          h.fight_skip = h.fight_skip or {}
          for m in pairs(A.blocked_ids or {}) do h.fight_skip[m], n = t + SKIP_TICKS, n + 1 end
          the_end(string.format("nothing he can reach after %d tries%s", A.tries,
            n > 0 and string.format(" (%d blocked one(s) not again for %d s)", n, SKIP_TICKS / 60) or ""))
          return false
        end
        A.tries, A.t, A.i, A.checking = A.tries + 1, t, 1, nil
        A.list = fight_candidates(world, id, h, smode, px, py, pz, nx, ny, nz)
        log(string.format("fight %s: try %d: %d candidate(s)", name, A.tries, #A.list))
      end
      return false  -- (owner 18:47) he keeps following while he checks
    end
    if A.checking ~= c.id then
      A.checking, A.check_t = c.id, t
      pcall(function() cd.lastTargetId = c.id end)
      return false  -- (owner 18:47) he keeps following while he checks
    end
    if t - A.check_t < RAY_WAIT then return false end  -- (owner 18:47) he keeps following while he checks
    local okr, reach = pcall(function() return cd.isTargetReachable end)
    local okd, rd = pcall(function() return tonumber(cd.distanceToTarget) end)
    if okr and reach then
      A.phase, A.target, A.t0, A.atk = "fight", c.id, t, nil
      A.rep, A.rep_t, A.ok_d, A.ok_t, A.base = 0, nil, nil, t, nil
      log(string.format("fight %s: attacks %s (%s; %.1f m from him; ray clear; his health %s/%s; it: %s)", name, tostring(c.id), c.why, c.d,
        tostring(hp), tostring(hmax), describe(world, c.id)))
    else
      -- (owner 2026-11-19 14:02 a bat a little higher, "the dog doesn't see it?") where it and he are, and its model
      local cx, cy, cz = world:position(c.id)
      local model = "?"
      pcall(function() model = tostring(world:template("ModelResource", c.id).model) end)
      log(string.format("fight %s: %s is blocked (the ray hits something at %s m of %.1f m), the next one; it at %s, %s; him at %.1f %.1f %.1f; its model %s",
        name, tostring(c.id), okd and rd and string.format("%.1f", rd) or "?", c.d,
        cx and string.format("%.1f %.1f %.1f", cx, cy, cz) or "?", cy and string.format("%.1f m %s him", math.abs(cy - ny), cy >= ny and "above" or "below") or "?",
        nx, ny, nz, model))
      A.blocked_ids = A.blocked_ids or {}
      A.blocked_ids[c.id] = true
      A.i, A.checking = A.i + 1, nil
      return false  -- (owner 18:47) he keeps following while he checks
    end
  end
  -- fighting
  local tg = A.target
  local mx, my, mz = world:position(tg)
  if not (mx and monster_alive(world, tg)) then
    log(string.format("fight %s: %s is dead", name, tostring(tg)))
    if A.atk then  -- (13:57 logging) the attack that killed it (its own hit comes a tick after this)
      log(string.format("fight %s: his %s from %.1f m killed it %.2f s after it started", name, A.atk.ix == 0 and "bite" or "lunge",
        A.atk.d or -1, (t - A.atk.t) / 60))
    end
    repick("his target is dead")
    return hold_still()
  end
  if (mx - px) ^ 2 + (my - py) ^ 2 + (mz - pz) ^ 2 > FIGHT_RANGE ^ 2 then
    repick(string.format("%s left your %d m radius", tostring(tg), FIGHT_RANGE))
    return hold_still()
  end
  pcall(function()
    cd.lastTargetId = tg
    cd.isTargetInsideLeash = false
    cd.targetOfMyTarget = false
  end)
  local d = math.sqrt((mx - nx) ^ 2 + (my - ny) ^ 2 + (mz - nz) ^ 2)
  local okr, reach = pcall(function() return cd.isTargetReachable end)
  local hit_tg, hit_other = false, nil
  for _, e in ipairs(hits) do
    if e.tg == tg then hit_tg = true
    elseif e.obj then hit_other = hit_other or e.tg end  -- an object (another monster is no block)
  end
  if hit_tg then A.rep = 0 end
  if hit_tg or not A.ok_d or d < A.ok_d - 0.3 then A.ok_d, A.ok_t = math.min(d, A.ok_d or d), t end
  local tv = speed_of(world, tg)
  local waiting = d > FIGHT_BITE and tv > FAST
  if waiting then
    A.ok_d, A.ok_t = d, t  -- waiting is not failing
    if not A.wait_said then
      A.wait_said = true
      log(string.format("fight %s: waits: %s moves %.1f m/s (faster than %d); he lunges when it slows (%.1f m away)", name,
        tostring(tg), tv, FAST, d))
    end
  elseif A.wait_said then
    A.wait_said = nil
    log(string.format("fight %s: %s slowed to %.1f m/s (%.1f m away)", name, tostring(tg), tv, d))
  end
  -- a reposition step under way: MOVE_STEP, then he tries again from where he is
  if A.rep_t then
    if t - A.rep_t < MOVE_STEP then
      if A.rep == 1 then return hold_still() end
      local p = A.rep == 2 and A.base.left or A.base.right
      hold_at(a, p.x, p.y, p.z)
      return true
    end
    A.rep_t, A.ok_t, A.ok_d = nil, t, d
    log(string.format("fight %s: tries %s again from here (%.1f m away)", name, tostring(tg), d))
  end
  local why
  if okr and not reach then why = "the ray is blocked"
  elseif hit_other and not hit_tg then why = string.format("his attack hit something else (%s), not it", tostring(hit_other))
  elseif t - A.ok_t >= NO_HIT then why = string.format("no hit on it and no closer for %d s", NO_HIT / 60) end
  if why then
    A.rep = (A.rep or 0) + 1
    if A.rep > 3 then
      h.fight_skip = h.fight_skip or {}
      h.fight_skip[tg] = t + SKIP_TICKS
      log(string.format("fight %s: gives up on %s: %s after the hop, left and right (not again for %d s)", name,
        tostring(tg), why, SKIP_TICKS / 60))
      repick("he can't deliver attacks on his target")
      return hold_still()
    end
    A.rep_t, A.atk = t, nil
    local fx, fz = mx - nx, mz - nz
    local fl = math.max(0.05, math.sqrt(fx * fx + fz * fz))
    if A.rep == 1 or not A.base then
      A.base = { left = { x = nx - fz / fl * SIDE, y = ny, z = nz + fx / fl * SIDE },
                 right = { x = nx + fz / fl * SIDE, y = ny, z = nz - fx / fl * SIDE } }
    end
    log(string.format("fight %s: can't deliver attacks on %s (%s; %.1f m away): %s", name, tostring(tg), why, d,
      A.rep == 1 and "hops toward it" or A.rep == 2 and string.format("moves %d m to the left", SIDE) or string.format("moves %d m to the right", SIDE)))
    if A.rep == 1 then
      local hop = math.min(fl, 2)
      local vup, vh = launch_speeds(hop, math.max(0, math.min(2, my - ny)))
      local okv, vx, vz = launch(world, id, fx / fl * hop, fz / fl * hop, hop, vup, vh)
      edge_off(a)
      h.djump = { t0 = t, untill = t + DJ_TICKS, x1 = nx + fx / fl * hop, y1 = ny, z1 = nz + fz / fl * hop, hp = hp, vx = vx, vz = vz, vy = vup, up = false }
      if not okv then log(string.format("fight %s: the hop: could not set his speed", name)) end
      return hold_still()
    end
    local p = A.rep == 2 and A.base.left or A.base.right
    hold_at(a, p.x, p.y, p.z)
    return true
  end
  -- (owner 2026-11-19 11:17 "the companion should only get just as close as they need to be to land the attack and no
  -- closer": his lunge carries him past it) he runs at it until he is within lunge reach, then stands there
  if d > FIGHT_LUNGE then hold_at(a, mx, my, mz) else hold_at(a, nx, ny, nz) end
  -- (logging, owner 2026-11-19 07:50 fences) a stall with the ray clear: no 0.3 m closer for half a second, not within
  -- bite reach (something lower than the ray's line, or the monster keeps away): once per stall
  if d <= FIGHT_LUNGE or not A.best_d or d < A.best_d - 0.3 then A.best_d, A.prog_t, A.stall_said = math.min(d, A.best_d or d), t, nil end
  if t - (A.prog_t or t) > 30 and not A.stall_said then
    A.stall_said = true
    local st, spd, col = "?", -1, "?"
    pcall(function() st = tostring(world:get("DynamicLocomotion", id).state) end)
    pcall(function() local v = world:get("Velocity", id).velocity spd = math.sqrt(v.x * v.x + v.z * v.z) end)
    pcall(function()
      local r = world:get("MovementCollider", id).results.m_value
      col = string.format("collider: touching %s, a player %s, last slide side %s; ground %s (%.2f m, walkable %s), standing on %s",
        tostring(r.hasSpheroidCollision), tostring(r.hasPlayerSpheroidCollision), tostring(r.lastCollideAndSlideSide),
        tostring(r.hasGroundCollision), tonumber(r.groundDistance) or -1, tostring(r.isGroundWalkable), tostring(r.attachmentEntityId))
    end)
    log(string.format("fight %s: stalled (ray clear) on the way to %s: %.1f m away, %.1f m %s him, no closer for %.1f s; his state %s, speed %.1f m/s; %s",
      name, tostring(tg), d, math.abs(my - ny), my >= ny and "above" or "below", (t - A.prog_t) / 60, st, spd, col))
    report_blockers(s, "fight stall", mx - nx, mz - nz)
  end
  local act = action_of(world, id)
  local at = A.atk
  if at then
    if hit_tg then at.hit = true end
    -- (owner 2026-11-19 13:57 "yes log it": how far a lunge really reaches) every hit as it lands, and where he is
    -- at 0.4 s (the hits so far came 0.40-0.46 s after the start)
    for _, e in ipairs(hits) do
      log(string.format("fight %s: his %s's hit landed %.2f s after the start on %s: he is %.1f m from it, moved %.1f m",
        name, at.ix == 0 and "bite" or "lunge", (t - at.t) / 60, e.tg == tg and "it" or (e.obj and ("object " .. tostring(e.tg)) or ("monster " .. tostring(e.tg))),
        d, math.sqrt((nx - at.x) ^ 2 + (nz - at.z) ^ 2)))
    end
    if t - at.t == 24 then
      log(string.format("fight %s: his %s at 0.4 s: he is %.1f m from it (%.1f at the start), moved %.1f m; it moved %.1f m; he is %.1f m higher than at the start, it is %.1f m above him",
        name, at.ix == 0 and "bite" or "lunge", d, at.d or -1, math.sqrt((nx - at.x) ^ 2 + (nz - at.z) ^ 2),
        math.sqrt((mx - (at.mx or mx)) ^ 2 + (mz - (at.mz or mz)) ^ 2), ny - (at.y or ny), my - ny))
    end
    local asked = (tonumber(cd.selectedAttackIndex) or 255) ~= 255
    if not at.started and not asked then at.started = t end
    if at.jump and at.started and not at.jumped then
      at.jumped = t
      local okj = pcall(function()
        local tr = world:get("CurrentTransform", id).transform
        tr.position.y = tr.position.y + math.floor(0.3 * 2 ^ 32)
        world:get("Velocity", id).velocity.y = at.jump
      end)
      log(string.format("fight %s: jumps into his %s (up %.1f m/s)%s", name, at.ix == 0 and "bite" or "lunge", at.jump,
        okj and "" or " (could not set his speed)"))
    end
    if at.jumped and t > at.jumped and t <= at.jumped + 6 then  -- a speed written on the ground may not take: again until he is in the air
      local air = false
      pcall(function() air = world:get("DynamicLocomotion", id).state == 2 end)
      if not air then pcall(function() world:get("Velocity", id).velocity.y = at.jump end) end
    end
    if at.started and act and act ~= 0 then at.anim = act end
    local over = at.started and at.anim and (act == 0)
    if over or t - at.t > ATTACK_MAX then
      log(string.format("fight %s: %s %s after %.2f s, %s (%s; animation %s); he moved %.1f m, now %.1f m from it (was %.1f); %s", name,
        at.ix == 0 and "bite" or "lunge", over and "over" or "TIMED OUT", (t - at.t) / 60, at.hit and "HIT it" or "MISSED it",
        at.started and string.format("started after %d tick(s)", at.started - at.t) or "never started", tostring(at.anim),
        math.sqrt((nx - (at.x or nx)) ^ 2 + (nz - (at.z or nz)) ^ 2), d, at.d or -1, face_info(world, id, tg, nx, ny, nz, mx, my, mz)))
      A.atk, at = nil, nil
    end
  end
  local off = 0
  if not at then
    local okt, o = pcall(turn_toward, world, id, mx - nx, mz - nz)
    off = okt and o or 0
  end
  -- (healing) a move already asked for (the heal's Wolf Shout) is not overwritten, and the shout plays SHOUT_TICKS first
  local busy = (tonumber(cd.selectedAttackIndex) or 255) ~= 255 or t - (h.heal_t or -1e9) < SHOUT_TICKS
  if not at and d <= FIGHT_LUNGE and math.abs(off) <= FACE_OK and not waiting and not busy then
    -- (owner 2026-11-19 18:47 yes: jump bites at floating monsters hit 5 of 22, jump lunges 20 of 25) a target HIGH or more
    -- above him gets the lunge only
    local ix = (d <= FIGHT_BITE and my - ny < HIGH) and 0 or 1
    local ok = pcall(function() cd.selectedAttackIndex = ix end)
    A.atk = { ix = ix, t = t, x = nx, z = nz, d = d, mx = mx, mz = mz, y = ny }
    if my - ny >= HIGH then A.atk.jump = (launch_speeds(0, my - ny)) end
    log(string.format("fight %s: %s at %s (%.1f m)%s; %s", name, ix == 0 and "bite" or "lunge", tostring(tg), d, ok and "" or " (could not ask)",
      face_info(world, id, tg, nx, ny, nz, mx, my, mz)))
  end
  return true
end
