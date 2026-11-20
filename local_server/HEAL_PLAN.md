# Healing mode — proposal (2026-11-19 19:2x, for the owner to go over; nothing built)

Owner 2026-11-18 20:09 (the design): "Healing is like passive mode, campanion never attacks, but has the added
responsibility of watching their player, keeping him healed up and tries to stay out of the combat."
Owner 2026-11-19 19:25: "yeah write it up, as for how much mana and how much heals... im not sure. I only have 483 mana
at level 50, but im not spec'd as a mage. I would give him 800 mana and see how that works? how would a heal animation
work with him? nothing for him I would imagine?"

## What the game gives us (log 2026-11-19 19:21)

- The hound: **no Mana, no mana regeneration, no health recharge, no healing modifier**; only health (3680) and
  stamina (335). He never heals himself: after the 19:16 fight he stayed at 2443/3680.
- The player: Mana (483), ManaRegeneration, HealthRecharge, HealingMod (x1.15), stamina.
- FlameKit can heal any body with health: `emf.attribute_add(world, id, "health", n)` goes through the game's own
  attribute code and stops at the maximum (the same call Invincible mode uses to keep the player's mana full). It is
  not a hit: no hit reaction, no aggro.
- So the hound's mana is **ours**: a number FlameKit keeps for him (saved in the roster like his fight mode).

## The proposal

1. **His mana:** 800 (owner 19:25). It refills over time: **10 a second** (empty to full in 80 s), in every mode.
2. **Healing you (Healing mode only):** when your health is **below 60 %** and you are within his **20 m** circle, he
   heals you for **25 % of your maximum health**, costing **200 mana**: 4 heals from full, then one every 20 s from
   the refill. At least **4 s** between heals.
3. **Healing himself (Healing mode only, after you):** when he is below 60 % and you are not, he heals himself the
   same way (25 % of his maximum, 200 mana).
4. **Otherwise he behaves as in Passive:** follows you, never attacks. ("Stays out of the combat": keeping a
   distance from monsters is a later step, if the following alone puts him in harm's way.)
5. **What you see:** he has no heal animation (only the bite and the lunge are known; see below). Proposed instead:
   he turns to face you as he heals, a notice on your screen ("N1 heals you +920 — mana 600/800"), and your health
   bar rising. The log has every heal.
6. **The numbers live in one place** (the top of the Healing code), to change after play: mana 800, refill 10/s,
   heal below 60 %, heal 25 %, cost 200, 4 s between heals.

## The animation question

Nothing for him that we know of: his known moves are the bite (0x63FE3237) and the lunge (0xC34733A8). The hound may
have more in its game data (a howl, a growl, an idle trick), but they were never searched; that is the later item
"search the hound's game data for more attacks". If one turns up, it could play as his "cast" when he heals. Until
then: the turn toward you plus the notice.

## Build order (one step per test round)

1. His mana pool and its refill, logged (no healing yet).
2. Healing you in Healing mode, with the notice.
3. Healing himself.
4. Later: a real "cast" move if one is found; keeping away from monsters if needed.

## Open questions for the owner

- The heal numbers above (25 % / 200 mana / below 60 % / 4 s / refill 10 a second): fine to start with?
- Should he also heal himself **outside** Healing mode, slowly between fights (he never recovers otherwise)?
- The notice on every heal: wanted, or too chatty?
