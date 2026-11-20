import sys, uuid, struct
G, OUT = sys.argv[1], sys.argv[2]; sys.argv = [sys.argv[0], G]
exec(open(sys.argv[0].replace("list2.py", "kfc.py")).read())
T = 0x39768775
H = {"enemy": (0x52487b01, 0x1f9efdb6), "boss": (0x9475619e,), "faction": (0xa1f30f21, 0x87f8093b),
     "wildlife": (0x5409de31, 0xb42d8a33), "npc": (0xac7a6d7b, 0x48a5cb57), "tame": (0x1399e0ba,)}
rows, probe = [], None
for i in range(n):
    gb, t, part = key(i)
    if t != T or part != 0: continue
    r = resource_at(i)
    if len(r) < 24: continue
    no, nl = struct.unpack_from("<II", r, 0)
    name = r[no:no + nl].decode("utf-8", "replace")
    co, cn = struct.unpack_from("<II", r, 16)
    base = 16 + co
    comps = {}
    for k in range(cn):
        if base + k * 12 + 12 > len(r): break
        h, a, b = struct.unpack_from("<III", r, base + k * 12)
        comps[h] = (a, b, base + k * 12)
    if name == "Enemy_Vukah_Melee": probe = (r, comps)
    has = {k: any(h in comps for h in v) for k, v in H.items()}
    fv = -1
    if 0xa1f30f21 in comps:
        a, b, at = comps[0xa1f30f21]
        if at + 4 + a < len(r): fv = r[at + 4 + a]
    has["fv"] = fv
    fac = ""
    for h in H["faction"]:
        if h in comps:
            a, b, at = comps[h]
            for cand in (at + 4 + a, 16 + co + a, a):  # where its data is: tried below with the probe
                pass
    rows.append((name, str(uuid.UUID(bytes_le=gb)), has))
r, comps = probe
a, b, at = comps[0xa1f30f21]
print("vukah faction tries", r[at + 4 + a] if at+4+a < len(r) else None, r[a], r[16 + co + a] if 16+co+a < len(r) else None)
print("vukah components", len(comps))
for h in list(H["enemy"]) + list(H["faction"]):
    print(hex(h), comps.get(h))
print("first entries", [(hex(h), v[:2]) for h, v in list(comps.items())[:6]])
with open(OUT, "w") as f:
    f.write("name,guid,enemy_ai,boss,faction,wildlife,npc,tame\n")
    for name, g, h in sorted(rows):
        f.write("%s,%s,%d,%d,%d,%d,%d,%d\n" % (name, g, h["enemy"], h["boss"], h["fv"], h["wildlife"], h["npc"], h["tame"]))
print("rows", len(rows), "enemy_ai", sum(1 for x in rows if x[2]["enemy"]))
