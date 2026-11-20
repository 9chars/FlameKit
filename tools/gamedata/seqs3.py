import sys, uuid, struct, collections, re
G = sys.argv[1]; sys.argv = [sys.argv[0], G]
exec(open(sys.argv[0].replace("seqs3.py", "kfc.py")).read())
def fnv(b):
    h = 0x811c9dc5
    for x in b: h = ((h ^ x) * 0x01000193) & 0xffffffff
    return h
SEQ = 0x9fd4a561
rows = []
for i in range(n):
    gb, t, part = key(i)
    if t != SEQ or part != 0: continue
    r = resource_at(i)
    m = re.search(rb"[A-Za-z][A-Za-z0-9_]{5,}", r[16:])
    name = m.group(0).decode() if m else "?"
    rows.append((name, hex(fnv(gb)), len(r)))
rows.sort()
for name, h, ln in rows:
    if re.search(r"wolf|hound|howl|dog", name, re.I): print(f"{h:>11}  {ln:6d}  {name}")
print("all sequences", len(rows))
open(sys.argv[0].replace("seqs3.py","seqnames.tsv"), "w").write("".join(f"{h}\t{ln}\t{nm}\n" for nm, h, ln in rows))
