import sys, uuid, struct, collections
G = sys.argv[1]; sys.argv = [sys.argv[0], G]
exec(open(sys.argv[0].replace("seqs.py", "kfc.py")).read())
def fnv(b):
    h = 0x811c9dc5
    for x in b: h = ((h ^ x) * 0x01000193) & 0xffffffff
    return h
KNOWN = {0x63FE3237: "bite", 0xC34733A8: "lunge", 0xE80706FC: "jump"}
byguid = collections.defaultdict(list)
for i in range(n):
    gb, t, part = key(i)
    byguid[gb].append((i, t, part))
print("resources", n)
want = uuid.UUID("18eefd30-da1d-49f5-a6d8-7da8f2d01f43").bytes_le
tpl = [i for (i, t, p) in byguid[want] if t == 0x39768775 and p == 0][0]
def refs(blob):
    out = []
    for o in range(0, len(blob) - 15):
        g = blob[o:o + 16]
        if g in byguid: out.append((o, g))
    return out
# which form of hashing gives the known ids? try on every guid referenced (2 levels)
seen = {}
frontier = [(want, 0, "template")]
while frontier:
    g, lvl, via = frontier.pop()
    if g in seen or lvl > 3: continue
    seen[g] = (lvl, via)
    for (i, t, p) in byguid[g]:
        if p != 0: continue
        try: blob = resource_at(i)
        except Exception: continue
        if len(blob) > 3000000: continue
        for o, g2 in refs(blob):
            if g2 not in seen: frontier.append((g2, lvl + 1, str(uuid.UUID(bytes_le=g))[:8]))
print("referenced resources", len(seen))
forms = {"le": lambda g: g, "be": lambda g: uuid.UUID(bytes_le=g).bytes, "str": lambda g: str(uuid.UUID(bytes_le=g)).encode(),
         "STR": lambda g: str(uuid.UUID(bytes_le=g)).upper().encode()}
hits = collections.Counter()
for g in seen:
    for nm, f in forms.items():
        h = fnv(f(g))
        if h in KNOWN: hits[nm] += 1; print("match", KNOWN[h], nm, uuid.UUID(bytes_le=g), "types", [hex(t) for (_, t, _) in byguid[g]], "level", seen[g])
print(hits)
import pickle; pickle.dump({"seen": seen}, open(sys.argv[0].replace("seqs.py", "seen.pkl"), "wb"))
