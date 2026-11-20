# (2026-11-17 20:18, owner: safe drop height) a template's FallDamage component (kHash 0xec76db63):
# fallDamageStartDistance, fallDamageLethalDistance. Usage: python3 falldmg.py <client folder> <template guid> [...]
import sys, uuid, struct
G = sys.argv[1]; GUIDS = sys.argv[2:]; sys.argv = [sys.argv[0], G]
exec(open(sys.argv[0].replace("falldmg.py", "kfc.py")).read())
TPL = 0x39768775
want = {uuid.UUID(g).bytes_le: g for g in GUIDS}
for i in range(n):
    gb, t, part = key(i)
    if t == TPL and part == 0 and gb in want:
        r = resource_at(i)
        co, cn = struct.unpack_from("<II", r, 16)
        base = 16 + co
        found = False
        for k in range(cn):
            h, a, b = struct.unpack_from("<III", r, base + k * 12)
            if h == 0xec76db63:
                at = base + k * 12 + 4 + a
                s, l = struct.unpack_from("<ff", r, at)
                print(want[gb], "FallDamage start %.2f m, lethal %.2f m" % (s, l))
                found = True
        if not found: print(want[gb], "no FallDamage component in the template")
