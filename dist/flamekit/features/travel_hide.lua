-- features/travel_hide: FlameKit's UI hides during a fast travel's loading screen (0.15.281).
--
-- (owner 2026-11-18 13:57: "a lot of the UI elements don't disappear during zoning to a different area ... the mini
-- map does attempt to disappear, but it disappears a little too late ... It just looks goofy to the player"; 14:13
-- "there's a short animation, maybe about 3.5 seconds before the screen goes dark"; 14:16 "build it")
--
-- Measured on the local server (2026-11-18 14:06-14:12, four fast travels): the player's travel request
-- (PlayerInput.fromClient.teleportAction, its versionData changes) reaches the server 4.2-4.3 s before the teleport
-- (TeleportCount goes up); the game's "ready for gameplay" flag (PlayerInput.fromClientIsReadyForGameplay) goes false
-- around the teleport and true again when the player's game has loaded (5.9-8.3 s later).
--
-- The server (where the world is hosted) watches every player: HIDE_AFTER after the request, or at the teleport if
-- that comes first, it sends "1" on channel flamekit/travel to that player's game; when his game reports ready again
-- after the teleport, "0". The player's game keeps it in kit.travelling; core/kit.lua writes "travel 1" into
-- ui_hud.dat and the DLL hides all of FlameKit's UI (like build mode). A picked travel cannot be cancelled (owner
-- 15:20); nothing stays hidden longer than LONGEST.
-- (0.15.283, owner 14:39, Rule 0n: no fallbacks) this is the only fast travel hide: the DLL's old minimap rule
-- (TeleportCount, hidden until the player moved) is removed.

local F = { id = "travel_hide", title = "Travel" }

local kit
local CHANNEL = "travel"
-- (0.15.284, owner 15:20: "the UI seems to act correctly with the zoning, you could probably wait 2 seconds longer
-- before taking the UI off") HIDE_AFTER 3.3 s -> 5.3 s. The teleport comes about 4.2 s after the request, so a teleport
-- no longer hides the UI by itself when the request was seen: it waits for HIDE_AFTER too. (A teleport without a
-- request seen still hides at once.)
-- (0.15.284, owner 15:20: "at that point you cant cancel it and theres no need to wait or listen for a cancelled
-- teleport") the 7 s cancel rule is removed: once the request comes the travel happens, and the UI stays hidden until
-- the player's game has loaded. LONGEST only keeps the UI from staying hidden for good if a signal never comes.
local HIDE_AFTER, LONGEST = 318, 3600  -- ticks (60 a second): 5.3 s, 60 s
local state = {}  -- player entity -> { ver, cnt, req_t, hiding, hid_t, tp, unready }

local function set_here(on)
  if kit.travelling ~= on then
    kit.travelling = on
    kit.debug("info", "travel: FlameKit's UI %s", on and "hidden (fast travel)" or "shown again")
  end
end

local function send(world, pid, on)
  local me = emf.local_player()
  if me and me ~= 0 and pid == me then
    set_here(on)  -- the host's own game is right here
  else
    pcall(emf.net.send_to, world, pid, CHANNEL, on and "1" or "0")
  end
end

local function read(world, pid)
  local okv, ver = pcall(function() return world:get("PlayerInput", pid).fromClient.teleportAction.versionData end)
  local okc, cnt = pcall(function() return world:get("TeleportCount", pid).counter end)
  local okr, ready = pcall(function() return world:get("PlayerInput", pid).fromClientIsReadyForGameplay end)
  return okv and tonumber(ver) or nil, okc and tonumber(cnt) or nil, okr and ready
end

function F.tick(world)
  if not world:is_server() then return end
  local t = world:tick()
  local seen = {}
  for _, pid in ipairs(require("core.players").ids(world)) do
    seen[pid] = true
    local st = state[pid]
    local ver, cnt, ready = read(world, pid)
    if not st then
      state[pid] = { ver = ver, cnt = cnt }
    else
      if ver and st.ver and ver ~= st.ver then st.req_t = t end
      st.ver = ver or st.ver
      local hide_now = false
      if cnt and st.cnt and cnt ~= st.cnt then
        st.tp = true
        st.tp_t = t
        if not st.req_t then hide_now = true end  -- no request seen: hide at the teleport
      end
      st.cnt = cnt or st.cnt
      -- the game may go "not ready" (loading) before the hide now (the teleport comes first): noted from the teleport on
      if st.tp and ready == false then st.unready = true end
      if st.req_t and t - st.req_t >= HIDE_AFTER then hide_now = true end
      if hide_now and not st.hiding then
        st.hiding, st.hid_t = true, t
        send(world, pid, true)
        emf.log(string.format("travel: player %s travels: FlameKit's UI hidden (%s; teleport %s)", tostring(pid),
          st.req_t and string.format("%.1f s after the request", (t - st.req_t) / 60) or "at the teleport, no request seen",
          st.tp_t and (st.req_t and string.format("%.1f s after the request", (st.tp_t - st.req_t) / 60) or "now")
            or "not yet"))
      end
      if st.hiding then
        if ready == false then st.unready = true end
        local done = st.tp and st.unready and ready == true
        local too_long = t - st.hid_t > LONGEST
        if done or too_long then
          send(world, pid, false)
          emf.log(string.format("travel: player %s: FlameKit's UI shown again (%s, after %.1f s)", tostring(pid),
            done and "loaded" or "60 s, no load seen", (t - st.hid_t) / 60))
          state[pid] = { ver = st.ver, cnt = st.cnt }
        end
      end
    end
  end
  for pid in pairs(state) do
    if not seen[pid] then state[pid] = nil end
  end
end

function F.setup(k)
  kit = k
  kit.travelling = false
  require("core.players").setup(k)
  local ok = emf.net.channel(CHANNEL, {
    version = 1, to = "players", max = 8, per_10s = 30,
    on_player = kit.guard(F, function(world, from, data) set_here(data == "1") end, "the fast travel signal from the server"),
  })
  if not ok then emf.log("the channel flamekit/travel was refused: FlameKit's UI does not hide during fast travel") end
end

return F
