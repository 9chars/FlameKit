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
-- ui_hud.dat and the DLL hides all of FlameKit's UI (like build mode). A travel that never comes (cancelled) shows
-- the UI again CANCEL_AFTER the request; nothing stays hidden longer than LONGEST.
-- (0.15.283, owner 14:39, Rule 0n: no fallbacks) this is the only fast travel hide: the DLL's old minimap rule
-- (TeleportCount, hidden until the player moved) is removed.

local F = { id = "travel_hide", title = "Travel" }

local kit
local CHANNEL = "travel"
local HIDE_AFTER, CANCEL_AFTER, LONGEST = 198, 420, 3600  -- ticks (60 a second): 3.3 s, 7 s, 60 s
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
        hide_now = true
      end
      st.cnt = cnt or st.cnt
      if st.req_t and t - st.req_t >= HIDE_AFTER then hide_now = true end
      if hide_now and not st.hiding then
        st.hiding, st.hid_t, st.unready = true, t, false
        send(world, pid, true)
        emf.log(string.format("travel: player %s travels: FlameKit's UI hidden (%s)", tostring(pid),
          st.tp and "teleported" or "3.3 s after the request"))
      end
      if st.hiding then
        if ready == false then st.unready = true end
        local done = st.tp and st.unready and ready == true
        local cancelled = not st.tp and st.req_t and t - st.req_t > CANCEL_AFTER
        local too_long = t - st.hid_t > LONGEST
        if done or cancelled or too_long then
          send(world, pid, false)
          emf.log(string.format("travel: player %s: FlameKit's UI shown again (%s, after %.1f s)", tostring(pid),
            done and "loaded" or (cancelled and "no teleport came" or "60 s"), (t - st.hid_t) / 60))
          state[pid] = { ver = st.ver, cnt = st.cnt }
        end
      elseif st.req_t and not st.tp and t - st.req_t > CANCEL_AFTER then
        st.req_t = nil
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
