#!/usr/bin/env python3
"""(0.15.384) Makes flamekit/core/monster_names.lua from monster_prints.txt (the console's flamekit.monprints on the
local server). Each line: template guid, group, FlameKit name, boss, "animationGraph|retargetData|arsenal|maxHealth".
The arsenal names a kind (shared arsenals get the words their kinds share); the animation graph names the species,
for monsters FlameKit's list does not have.

  python3 tools/gamedata/make_monster_names.py tools/gamedata/monster_prints.txt flamekit/core/monster_names.lua
"""
import re
import sys

PREFIX = {"Vukah": "Vukah", "Scavengers": "Scavenger", "Shroud": "Shroud", "Undead": "Undead", "Beasts": "",
          "Drak": "", "Ancients": "Ancient"}


def clean(group, name):
    words = []
    for w in name.replace("(cave)", "").split():
        if re.fullmatch(r"v?\d+|Gen\d+", w):
            continue
        if not re.fullmatch(r"T\d+", w):  # a tier (T3) stays; a variant number (Melee01) goes
            w = re.sub(r"(?<=[A-Za-z])\d+$", "", w)
        if w and (not words or words[-1].lower() != w.lower()):
            words.append(w)
    p = PREFIX.get(group, group)
    if p and (not words or words[0].lower() != p.lower()):
        words.insert(0, p)
    return words


def shared(lists):
    out = []
    for ws in zip(*lists):
        if all(w.lower() == ws[0].lower() for w in ws):
            out.append(ws[0])
        else:
            break
    return out


def main(src, dst):
    by = {"arsenal": {}, "graph": {}}
    for line in open(src, encoding="utf-8"):
        f = line.rstrip("\n").split("\t")
        if len(f) < 5 or "|" not in f[4]:
            continue
        graph, _, arsenal, _ = f[4].split("|")
        words = clean(f[1], f[2])
        for key, v in (("arsenal", arsenal), ("graph", graph)):
            if v and v != "-" and not v.startswith("00000000-"):
                by[key].setdefault(v, []).append(words)
    names = {}
    for key, groups in by.items():
        names[key] = {}
        for v, lists in groups.items():
            w = shared(lists) if len(lists) > 1 else lists[0]
            prefix_only = len(w) <= 1 and len(lists[0]) > 1
            if key == "arsenal" and (not w or prefix_only):
                w = lists[0]
            # a species name is only kept when it says more than the group word
            if key == "graph" and len(w) < 2 and len(lists) > 1:
                continue
            names[key][v] = " ".join(w)
    with open(dst, "w", encoding="utf-8", newline="\n") as o:
        o.write("-- core/monster_names.lua (0.15.384): made by tools/gamedata/make_monster_names.py from monster_prints.txt\n")
        o.write("-- (the console's flamekit.monprints): a monster's name from its template's arsenal (the kind) or its\n")
        o.write("-- animation graph (the species, for kinds core/monsters.lua does not have). Do not edit by hand.\n")
        o.write("return {\n")
        for key in ("arsenal", "graph"):
            o.write("  %s = {\n" % key)
            for v in sorted(names[key]):
                o.write('    ["%s"] = "%s",\n' % (v, names[key][v].replace('"', "")))
            o.write("  },\n")
        o.write("}\n")
    print("arsenal names %d, species names %d" % (len(names["arsenal"]), len(names["graph"])))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
