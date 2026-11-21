# (0.15.363) for the split companion code: every name it reads from its shared environment must be set somewhere in
# it (or be a standard global). Prints the names read but never set: each one would be nil (a bug, as SLOT_NEAR at
# 16:28 on 2026-11-20). Usage: python3 bundle.py && python3 globals_check.py [bundle]
import re, subprocess, sys
b = sys.argv[1] if len(sys.argv) > 1 else '/tmp/companions_bundle.lua'
lst = subprocess.run(['texluac', '-l', '-l', '-p', b], capture_output=True, text=True).stdout
get = set(re.findall(r'GETTABUP\s.*_ENV "([A-Za-z_][A-Za-z0-9_]*)"', lst))
sets = set(re.findall(r'SETTABUP\s.*_ENV "([A-Za-z_][A-Za-z0-9_]*)"', lst))
for l in open(b):
    m = re.match(r'^function ([A-Za-z_][A-Za-z0-9_]*)\s*\(', l)
    if m: sets.add(m.group(1))
    m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*)\s*=[^=]', l)
    if m: sets.update(n.strip() for n in m.group(1).split(','))
std = set('assert collectgarbage coroutine debug dofile emf error getmetatable io ipairs load loadfile math next os package pairs pcall print rawequal rawget rawlen rawset require select setmetatable string table tonumber tostring type utf8 xpcall _G _VERSION'.split())
bad = sorted(get - sets - std)
print('read but never set:', ', '.join(bad) if bad else 'none')
sys.exit(1 if bad else 0)
