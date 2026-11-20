# (2026-11-17, owner: the dog's bite) the skeleton hound's attacks from the game data: template -> EnemyArsenalReference
# (an arsenal GUID) -> EnemyArsenalRegistryResource -> attacks -> description.actionSequence (an ActorSequence GUID).
import sys, uuid, struct
G = sys.argv[1]; sys.argv = [sys.argv[0], G]
exec(open(sys.argv[0].replace("arsenal.py", "kfc.py")).read())
TPL, REG = 0x39768775, 0xf67d6fc3
HOUND = uuid.UUID("18eefd30-da1d-49f5-a6d8-7da8f2d01f43").bytes_le
types = {}
for i in range(n):
    gb, t, part = key(i)
    types[t] = types.get(t, 0) + 1
print("resource types with REG:", types.get(REG), "templates:", types.get(TPL))
# the hound's template
for i in range(n):
    gb, t, part = key(i)
    if t == TPL and part == 0 and gb == HOUND:
        r = resource_at(i)
        co, cn = struct.unpack_from("<II", r, 16)
        base = 16 + co
        for k in range(cn):
            h, a, b = struct.unpack_from("<III", r, base + k * 12)
            if h == 0x4545a21e:
                at = base + k * 12 + 4 + a
                print("arsenal ref comp at", at, "size", b, "bytes", r[at:at+16].hex(), "->", uuid.UUID(bytes_le=r[at:at+16]))
                ARS = r[at:at+16]
        break
open("/tmp/arsenal_guid", "wb").write(ARS)
