import sys, uuid
G = sys.argv[1]; sys.argv = [sys.argv[0], G]
exec(open(sys.argv[0].replace("look.py", "kfc.py")).read())
T = 0x39768775
idx = [i for i in range(n) if key(i)[1] == T and key(i)[2] == 0]
print("templates", len(idx))
g = uuid.UUID("d5d05217-52dc-467a-9192-26b4f661d8d9").bytes_le
i = [i for i in idx if key(i)[0] == g][0]
r = resource_at(i)
p = r.find(b"Enemy_Vukah_Melee")
print("name at", p, "len", len(r))
print(r[:96].hex(" "))
print(r[max(0,p-32):p+40])
