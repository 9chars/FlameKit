import sys, uuid, struct, collections, re
G = sys.argv[1]; sys.argv = [sys.argv[0], G]
exec(open(sys.argv[0].replace("seqs2.py", "kfc.py")).read())
def fnv(b):
    h = 0x811c9dc5
    for x in b: h = ((h ^ x) * 0x01000193) & 0xffffffff
    return h
KNOWN = {0x63FE3237: "bite", 0xC34733A8: "lunge", 0xE80706FC: "jump"}
SEQ = 0x9fd4a561
idx = [i for i in range(n) if key(i)[1] == SEQ and key(i)[2] == 0]
print("sequences", len(idx))
for i in idx:
    g = key(i)[0]; h = fnv(g)
    if h in KNOWN:
        r = resource_at(i)
        names = re.findall(rb"[A-Za-z0-9_]{6,}", r)
        print(KNOWN[h], hex(h), uuid.UUID(bytes_le=g), "len", len(r), "strings", [x.decode() for x in names[:12]])
        print("   head", r[:64].hex(" "))
