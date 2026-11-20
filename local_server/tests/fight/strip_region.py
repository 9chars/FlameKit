import sys
src=open(sys.argv[1],encoding='utf-8').read().split('\n')
a,b=int(sys.argv[2]),int(sys.argv[3])  # 1-indexed inclusive region
def code_part(ln):
    # return line without trailing comment (string-aware)
    i=0;n=len(ln);q=None
    while i<n:
        ch=ln[i]
        if q:
            if ch=='\\': i+=2; continue
            if ch==q: q=None
        else:
            if ch in '"\'': q=ch
            elif ln.startswith('--',i): return ln[:i].rstrip()
        i+=1
    return ln
out=[]
for idx,ln in enumerate(src, start=1):
    if a<=idx<=b:
        if ln.strip().startswith('--'): continue
        out.append(code_part(ln))
    else: out.append(ln)
open(sys.argv[4],'w',encoding='utf-8').write('\n'.join(out))
