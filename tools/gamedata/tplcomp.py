# (2026-11-17 23:26, the hound's jump) dump one template component: python3 tplcomp.py <client> <template guid> <comp hash hex>
import sys, uuid, struct
G = sys.argv[1]; TPL_GUID_ARG = sys.argv[2]; COMP_HASH_ARG = int(sys.argv[3], 16); sys.argv = [sys.argv[0], G]
exec(open(sys.argv[0].replace("tplcomp.py", "kfc.py")).read())
TPL = 0x39768775
want = uuid.UUID(TPL_GUID_ARG).bytes_le
for i in range(n):
    gb, t, part = key(i)
    if t == TPL and part == 0 and gb == want:
        r = resource_at(i)
        co, cn = struct.unpack_from("<II", r, 16)
        base = 16 + co
        hs = []
        for k in range(cn):
            h, a, b = struct.unpack_from("<III", r, base + k * 12)
            hs.append(h)
            if h == COMP_HASH_ARG:
                at = base + k * 12 + 4 + a
                blob = r[at:at+b]
                print("size", b, "hex", blob.hex())
        print("components:", " ".join("%08x" % h for h in hs))
