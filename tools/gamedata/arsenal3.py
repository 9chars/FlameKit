import sys, uuid, struct
G = sys.argv[1]; sys.argv = [sys.argv[0], G]
exec(open(sys.argv[0].replace("arsenal3.py", "kfc.py")).read())
REG = 0xf67d6fc3
ARS = open("/tmp/arsenal_guid", "rb").read()
def fnv1a(b):
    h = 0x811c9dc5
    for x in b: h = ((h ^ x) * 0x1000193) & 0xffffffff
    return h
for i in range(n):
    gb, t, part = key(i)
    if t != REG: continue
    r = resource_at(i)
    def arr(at):
        o, c = struct.unpack_from("<II", r, at)
        return at + o, c
    a0, ac = arr(0)
    print("registry size", len(r), "arsenals", ac)
    for j in range(ac):
        e = a0 + j * 32
        if r[e:e+16] != ARS: continue
        at, cnt = arr(e + 16)
        print("hound arsenal at", e, "attacks", cnt)
        for k in range(cnt):
            d = at + k * 156
            seq = r[d+16:d+32]
            exe = r[d+16+68:d+16+84]
            print("RAW", k, " ".join("%g" % struct.unpack_from("<f", r, d+q)[0] if abs(struct.unpack_from("<f", r, d+q)[0])<1e6 and struct.unpack_from("<f", r, d+q)[0]!=0 else ("0" if struct.unpack_from("<I", r, d+q)[0]==0 else "%08x" % struct.unpack_from("<I", r, d+q)[0]) for q in range(0,156,4)))
            print(" attack %d: guid %s seq %s (fnv %08x) exec %s minR %.2f maxR %.2f chance %.2f" % (k, uuid.UUID(bytes_le=r[d:d+16]),
                uuid.UUID(bytes_le=seq), fnv1a(seq), uuid.UUID(bytes_le=exe),
                struct.unpack_from("<f", r, d+16+32)[0], struct.unpack_from("<f", r, d+16+36)[0], struct.unpack_from("<f", r, d+16+20)[0]))
