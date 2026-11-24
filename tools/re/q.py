import pickle,bisect,re,sys
addrs,ins,starts=pickle.load(open('/tmp/re/idx.pkl','rb'))
def func_of(a):
    i=bisect.bisect_right(starts,a)-1; return starts[i]
def callers(f):
    t=f'0x{f:x}'
    return sorted(set(func_of(addrs[i]) for i,x in enumerate(ins) if (x.startswith('call') or x.startswith('jmp')) and x.split()[-1]==t))
if __name__=='__main__':
    for a in sys.argv[1:]:
        f=int(a,16); print(a,'in func',hex(func_of(f)),'callers',[hex(c) for c in callers(func_of(f))])
