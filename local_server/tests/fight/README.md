# Companion fight / heal tests (fake world)

Small stand-alone worlds that load `features/npc_probe.lua` with a stand-in for the game and the C++ server probe,
and print the log lines a run produces. Written while building the attack sequence and healing (2026-11-18/19).
Each takes the npc_probe file as its first argument, then `key=value` options.

Run with texlua (Lua 5.3), from this folder:

    texlua seqtest4.lua ../../features/npc_probe.lua [block=200] [from=TICK] [wall=5] [objhit=999] [inject=TICK] [fastuntil=TICK]
    texlua seqtest5.lua ../../features/npc_probe.lua high=1          # a monster 1 m above him (jump attacks)
    texlua seqtest7.lua ../../features/npc_probe.lua                  # a part with no health next to him
    texlua healtest.lua ../../features/npc_probe.lua mode=Healing|Passive|Aggressive hurt=1000 phurt=1500 [onlyhit=999]

- `fighttest.lua`, `doortest.lua`, `watchtest.lua`, `armortest*.lua`: the first fight steps (targets, doors and
  mushrooms that are not monsters, the health/defence logging, armour).
- `seqtest*.lua`: the attack sequence (the ray stand-in `block=`, a wall `wall=`, hits on objects `objhit=`/`inject=`,
  fast monsters `fastuntil=`, Passive mid-fight `passiveat=`, Defensive `defensive onlyhit=`).
- `healtest*.lua`: healing (emf.attribute / attribute_add / spawn stand-ins; the C++ stand-in answers the shout).
- `harness.lua`: an older old-vs-new differential runner (the current one is `../drive_harness.lua`).
- `syn.lua`: the syntax check used before every install (`texlua syn.lua <file>`).
- The `.py` files: one-off helpers used while splitting and commenting npc_probe.lua (2026-11-18 cleanup).
