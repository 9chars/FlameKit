import sys, re
def strip(code):
    out=[]; i=0; n=len(code)
    while i<n:
        if code.startswith('--[[',i):
            j=code.find(']]',i); i=j+2; continue
        if code.startswith('--',i):
            j=code.find('\n',i); i = n if j<0 else j; continue
        ch=code[i]
        if ch in '"\'':
            q=ch; j=i+1
            while j<n and code[j]!=q:
                if code[j]=='\\': j+=1
                j+=1
            out.append(code[i:j+1]); i=j+1; continue
        out.append(ch); i+=1
    toks = re.findall(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|\d+\.?\d*(?:[eE][-+]?\d+)?|\w+|==|~=|<=|>=|\.\.|::|<<|>>|//|\S', ''.join(out))
    return toks
a=strip(open(sys.argv[1],encoding='utf-8').read()); b=strip(open(sys.argv[2],encoding='utf-8').read())
if a==b: print("CODE IDENTICAL (%d tokens)" % len(a))
else:
    i=0
    while i<min(len(a),len(b)) and a[i]==b[i]: i+=1
    print("CODE DIFFERS at token", i, a[max(0,i-15):i+10], b[max(0,i-15):i+10])
