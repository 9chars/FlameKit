-- core/wake.lua (0.15.562, owner 2026-11-28 07:47 "yes do #1": FlameKit brings itself back when EMF paused it).
-- FlameKit Native rewrites core/wake_mark.lua (required below) on a dedicated server when FlameKit's script has stopped (EMF's 250 ms rule or its
-- memory limit pause a Lua mod "until one of its files changes"): changing a file of the mod and then "lua.reload" in
-- emf\commands.txt make EMF load FlameKit again at once. wake_mark.lua is required only so that EMF counts it among the
-- mod's own files.
pcall(require, "core.wake_mark")
-- "flamekit.stall" (the console or emf\commands.txt only, not players): runs 300 ms to make EMF pause FlameKit on purpose,
-- to test the waking.
pcall(emf.command, "stall", "test: makes EMF pause FlameKit (runs 300 ms) so FlameKit Native's waking can be tried", function()
  emf.log("[flamekit] stall: running 300 ms on purpose (a test of the waking)")
  local t = os.clock()
  while os.clock() - t < 0.3 do end
end)
return {}
