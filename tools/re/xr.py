import re,sys,bisect
lines=open('/tmp/re/srv.asm').read().splitlines()
pat=re.compile(r'^\s+(14[0-9a-f]{7}):\t(.*)$')
addrs=[];ins=[];starts=[];prev=True
for l in lines:
    m=pat.match(l)
    if not m: continue
    a=int(m.group(1),16); t=m.group(2)
    if t.startswith('int3'): prev=True; continue
    if prev: starts.append(a); prev=False
    addrs.append(a); ins.append(t)
import pickle; pickle.dump((addrs,ins,starts),open('/tmp/re/idx.pkl','wb'))
