import sys, uuid, collections
sys.argv = [sys.argv[0], sys.argv[1]]
exec(open(sys.argv[0].replace("find.py", "kfc.py")).read())
g = uuid.UUID("d5d05217-52dc-467a-9192-26b4f661d8d9")
cands = {"bytes": g.bytes, "bytes_le": g.bytes_le}
for i in range(n):
    gb, t, part = key(i)
    for nm, c in cands.items():
        if gb == c: print("found", nm, i, hex(t), part, len(resource_at(i)))
types = collections.Counter(key(i)[1] for i in range(n))
print("resources", n, "types", len(types))
