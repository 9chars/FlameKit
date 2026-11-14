-- features/_template.lua: copy this file to start a new feature. It is not loaded until main.lua lists it.
--
-- 1. Copy it to features/my_feature.lua and change the id and title below.
-- 2. Add "features.my_feature" to the list in main.lua.
-- 3. Add its settings to mod.json under their own "group" (start the keys with a short prefix: "mf_...").
-- Everything in a feature is optional except id and title. core/kit.lua explains each part.

local F = { id = "my_feature", title = "My Feature", enabled_setting = "mf_enabled" }

local kit

-- Once, while the mod loads. Ask for events, keys and commands here, wrapped in kit.guard so they stop while the
-- feature is switched off and an error in one feature leaves the others running.
function F.setup(k)
  kit = k
  -- emf.on_event("PickupEvent", kit.guard(F, function(world, e) ... end, "PickupEvent"), "server")
  -- emf.on_key("mf_key", kit.guard(F, function(world) ... end, "the key"))
  -- emf.command("my_feature", ": what it does", kit.guard(F, function(world, args) emf.reply("hi") end, "the command"))
  -- local saved = kit.store.load("my_feature", {})   and   kit.store.save("my_feature", saved)
end

-- Every step of a world you host: change the game here.
function F.tick(world)
end

-- Its tab in FlameKit's window (F4): rows as core/kit.lua describes them. Keys only need to be unique inside this feature.
function F.panel(world)
  return {
    { heading = "My Feature" },
    { button = "hello", text = "Say hello" },
  }
end

function F.click(world, key, right_click)
  if key == "hello" then kit.note("Hello from My Feature") end
end

return F
