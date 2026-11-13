-- core/hub.lua: the FlameKit panel, one window with a tab per feature.
--
-- EMF draws the window beside the game's open bag (place "right"). A feature gives its rows with panel(world) and
-- gets its clicks with click(world, key, right_click); the hub puts "f<n>:" in front of the keys so two features can
-- use the same key.

local hub = { open = false, tab = 1, WIDTH = 46 }  -- WIDTH: the panel's width in text heights

local kit
local ID = "hub"
local ticks = 0         -- steps of the window's world since the mod loaded
local closed_tick = -1000
local last_sig = ""
local KEY_FIELDS = { "button", "row", "slot", "key" }

-- The features that have a tab right now.
local function tabs()
  local list = {}
  for _, f in ipairs(kit.features) do
    if f.panel and kit.enabled(f) then list[#list + 1] = f end
  end
  return list
end

local function adopt(row, prefix)
  local r = {}
  for k, v in pairs(row) do r[k] = v end
  for _, field in ipairs(KEY_FIELDS) do
    if type(r[field]) == "string" then r[field] = prefix .. r[field] end
  end
  return r
end

-- The minimap's own window would lie over the panel: while the panel is open, "1" is written into panel_open.dat
-- twice a second (the minimap's DLL hides while that file is fresh), and "0" when it closes.
local function tell_minimap(open)
  local f = io.open(emf.dir .. "\\panel_open.dat", "w")
  if f then
    f:write(open and "1" or "0")
    f:close()
  end
end

local function build(world)
  local rows = {}
  local list = tabs()
  if hub.tab > #list then hub.tab = 1 end
  if #list == 0 then
    rows[1] = { text = "No feature is switched on. Switch one on in the Mods tab (the key under Esc, then Ctrl+Tab)." }
  else
    if #list > 1 then
      for i, f in ipairs(list) do
        -- the tabs in blue, the open one brighter, so they read as tabs and not as the feature's own buttons
        rows[#rows + 1] = { button = "tab:" .. i, text = f.title, same_line = i > 1, selected = i == hub.tab,
                            color = i == hub.tab and "#9fd2ff" or "#4f9fe8" }
      end
      rows[#rows + 1] = { separator = true }
    end
    local f = list[hub.tab]
    local own = kit.call(f, "panel", world)
    if type(own) == "table" then
      for _, row in ipairs(own) do
        if #rows >= 250 then break end  -- EMF draws at most 256 rows
        rows[#rows + 1] = adopt(row, "f" .. hub.tab .. ":")
      end
    else
      rows[#rows + 1] = { text = f.title .. " has nothing to show." }
    end
  end
  local place, key = emf.setting("hub_place"), emf.setting("hub_key")
  if place ~= "left" and place ~= "centre" then place = "right" end
  if type(key) ~= "string" then key = "" end
  local f = list[hub.tab]
  -- one window for the whole kit: its title is the kit's name, version and author, whatever tab is open
  local title = string.format("%s v%s", kit.name, kit.version)
  if kit.author ~= "" then title = title .. " by " .. kit.author end
  return { title = title, width = hub.WIDTH, place = place, close_key = key, rows = rows }
end

-- What the window shows, as one text: it is only sent again when this changes.
local function signature(def)
  local parts = {}
  for i, r in ipairs(def.rows) do
    parts[i] = table.concat({
      tostring(r.button or r.row or r.slot or ""), tostring(r.text or r.heading or ""), tostring(r.count or ""),
      r.selected and "s" or "", r.disabled and "d" or "", tostring(r.color or ""),
    }, "|")
  end
  return table.concat(parts, "\n")
end

local function refresh(world)
  local def = build(world)
  last_sig = signature(def)
  if not emf.window_update(ID, def) then hub.open = false end
end

local function on_event(world, ev)
  if ev.kind == "closed" then
    hub.open = false
    closed_tick = ticks
    tell_minimap(false)
    return
  end
  local key = ev.key or ""
  local tab = key:match("^tab:(%d+)$")
  if tab then
    hub.tab = tonumber(tab)
  else
    local n, own = key:match("^f(%d+):(.+)$")
    local f = n and tabs()[tonumber(n)]
    if f then kit.call(f, "click", world, own, ev.kind == "right_click") end
  end
  refresh(world)
end

function hub.show(world)
  if hub.open then return true end
  local def = build(world)
  last_sig = signature(def)
  hub.open = emf.window(ID, def, on_event)
  if hub.open then tell_minimap(true) end
  if not hub.open then emf.notify(kit.name .. ": the panel cannot open now (another window or wheel is open).") end
  return hub.open
end

function hub.toggle(world)
  if hub.open then
    emf.window_close(ID)
  elseif ticks - closed_tick > 20 then  -- the same key press that just closed it does not open it again
    hub.show(world)
  end
end

function hub.setup(k)
  kit = k
  emf.on_key("hub_key", function(world)
    hub.toggle(world)
  end)
  emf.command("panel", ": open the " .. kit.name .. " panel", function(world)
    hub.show(world)
  end)
end

-- While the window is open, look twice a second whether what it shows changed (you looted something, a setting moved).
function hub.tick(world)
  local mine = kit.is_host() and world:is_server() or (not kit.is_host() and world:is_client())
  if not mine then return end
  ticks = ticks + 1
  if not hub.open or ticks % 30 ~= 0 then return end
  tell_minimap(true)
  local def = build(world)
  local sig = signature(def)
  if sig ~= last_sig then
    last_sig = sig
    if not emf.window_update(ID, def) then hub.open = false end
  end
end

return hub
