-- a fake EMF world for spawn_nodes.lua
local M = {}
local clock = 1000000
os.time = function() return math.floor(clock) end
M.advance = function(s) clock = clock + s end
M.logs = {}
local function enc(v)
  local t = type(v)
  if t == "table" then
    local isarr = #v > 0 or next(v) == nil
    local out = {}
    if isarr and #v > 0 then for _, x in ipairs(v) do out[#out+1] = enc(x) end return "[" .. table.concat(out, ",") .. "]" end
    for k, x in pairs(v) do out[#out+1] = string.format("%q", tostring(k)) .. ":" .. enc(x) end
    table.sort(out) return "{" .. table.concat(out, ",") .. "}"
  elseif t == "string" then return string.format("%q", v)
  elseif t == "nil" then return "null" else return tostring(v) end
end
M.ents = {}   -- id -> { x, y, z, hp, max, faction, account, scale }
M.next_id = 40000
M.notices = {}
M.destroyed = {}
local tmpdir = os.getenv("TMPDIR_SN") or "/tmp/sntest/dir"
os.execute("mkdir -p " .. tmpdir)
emf = {
  dir = tmpdir,
  log = function(s) M.logs[#M.logs+1] = s if os.getenv("SNLOG") then print("LOG " .. s) end end,
  json = { encode = enc, decode = function() return {} end },
  health = function(w, id) local e = M.ents[id] if not e or e.hp == nil then return nil end return e.hp, e.max end,
  spawn = function(w, guid, x, y, z, comps, opts)
    M.next_id = M.next_id + 1
    M.ents[M.next_id] = { x = x, y = y, z = z, hp = M.spawn_hp or 100, max = 100, faction = 10,
      scale = comps and comps.ScaleComponent and comps.ScaleComponent.uniformScale }
    return M.next_id
  end,
  destroy = function(w, id) if M.ents[id] then M.ents[id] = nil M.destroyed[#M.destroyed+1] = id return true end return false end,
  teleport = function() return true end,
  net = { send_to = function(w, pid, ch, text) M.notices[#M.notices+1] = text end, channel = function() return true end, send = function() end },
  session = function() return "s1" end,
  session_token = function() return "tok" end,
  local_player = function() return 999 end,
  send_marker = function() return 1 end,
  unsend_marker = function() end,
  time_of_day = function() return 12 end,
  on_hit = function() end,
  enemy_target = function() return nil end,
  template = function() return "g" end,
}
M.world = {
  is_server = function() return true end,
  position = function(w, id) local e = M.ents[id] if not e then error("no entity") end return e.x, e.y, e.z end,
  account = function(w, id) local e = M.ents[id] return e and e.account end,
  get = function(w, comp, id)
    local e = M.ents[id] if not e then return nil end
    if comp == "Faction" then return { faction = e.faction } end
    if comp == "ScaleComponent" then return e.scale and { uniformScale = e.scale } or nil end
    if comp == "DynamicEnemy01BehaviorState" then return e.ai_state and { state = e.ai_state } or nil end
    if comp == "SelectedTargets" then return e.ai_state and { targets = { { targetEntityId = { id = e.target or 0 } } } } or nil end
    if comp == "DynamicAggro" then
      if not e.ai_state then return nil end
      local t = {} for i = 1, 6 do t[i] = { state = 0, entityId = { id = 0 }, faction = 0, aggro = 0 } end
      if e.knows then t[1] = { state = 3, entityId = { id = e.knows }, faction = 7, aggro = 55 } end
      return { targets = t }
    end
    return nil
  end,
  entities = function(w) local l = {} for id in pairs(M.ents) do l[#l+1] = id end table.sort(l) return l end,
}
local store = {}
M.kit = {
  store = { load = function(n) return store[n] end, save = function(n, d) store[n] = d end },
  setting = function(k, d) return d end, notice = function() end, is_host = function() return false end,
  guard = function(F, fn) return fn end,
}
package.preload["core.admins"] = function() return { is = function() return true end } end
package.preload["core.players"] = function() return { setup = function() end,
  ids = function() local l = {} for id, e in pairs(M.ents) do if e.account then l[#l+1] = id end end table.sort(l) return l end } end
package.preload["core.monsters"] = function() return { { "Undead", "Skeleton", "guid-u1" }, { "Undead", "Skel2", "guid-u2" } } end
package.preload["core.spawn"] = function() return { ground = function() return { add = function() end, tick = function() end } end } end
package.preload["core.threat"] = function() return { alarm = function() return true end, event = function() return true end, line = function() return "" end } end
M.player = function(id, x, y, z) M.ents[id] = { x = x, y = y, z = z, hp = 500, max = 500, faction = 7, account = "acc" .. id } end
M.count = function(pat) local n = 0 for _, l in ipairs(M.logs) do if l:find(pat, 1, true) then n = n + 1 end end return n end
M.last_left = function() local t for _, s in ipairs(M.notices) do local m = s:match('"t":"(Raid on[^"]*)"') if m then t = m end end return t end
return M
