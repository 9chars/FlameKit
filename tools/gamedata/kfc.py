# Reads the game's resource list (enshrouded.kfc + .kfc_resources), the same layout as FlameKit's item_icons.hpp.
import struct, subprocess, sys, os, uuid
G = sys.argv[1]
d = open(os.path.join(G, "enshrouded.kfc"), "rb").read()
u32 = lambda b, o: struct.unpack_from("<I", b, o)[0]
def place(i):
    f = 16 + i * 8
    return f + u32(d, f), u32(d, f + 4)
res_keys, n = place(10); res_vals, _ = place(11); ch_at, ch_n = place(15)
chunks = [struct.unpack_from("<5I", d, ch_at + i * 20) for i in range(ch_n)]
RES = open(os.path.join(G, "enshrouded.kfc_resources"), "rb")
cache = {}
def unpack(c):
    if c in cache: return cache[c]
    off, size, comp, start, nbytes = chunks[c]
    RES.seek(off); packed = RES.read(comp)
    out = subprocess.run(["zstd", "-d", "-c"], input=packed, capture_output=True).stdout
    if len(cache) > 4: cache.clear()
    cache[c] = out
    return out
def resource_at(i):
    at, nb = struct.unpack_from("<II", d, res_vals + i * 8)
    out = b""
    for c, (off, size, comp, start, nbytes) in enumerate(chunks):
        lo, hi = max(at, start), min(at + nb, start + nbytes)
        if lo >= hi: continue
        out += unpack(c)[lo - start:hi - start]
    return out
def key(i):
    k = d[res_keys + i * 32: res_keys + i * 32 + 32]
    return k[:16], u32(k, 16), u32(k, 20)
