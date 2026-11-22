# tools/lua_tokens.py <a.lua> <b.lua>: exit 0 when both files have the same Lua tokens (comments and whitespace
# ignored; strings, long strings and numbers compared as written). Used by tools/comments_only.sh.
import re,sys
# The tokens of Lua source s, without comments and whitespace.
def toks(s):
    i=0;n=len(s);out=[]
    lb=re.compile(r'\[(=*)\[')
    while i<n:
        c=s[i]
        if c in ' \t\r\n': i+=1; continue
        if s.startswith('--',i):
            m=lb.match(s,i+2)
            if m:
                close=']'+m.group(1)+']'; j=s.find(close,m.end()); i=n if j<0 else j+len(close)
            else:
                j=s.find('\n',i); i=n if j<0 else j
            continue
        m=lb.match(s,i)
        if m:
            close=']'+m.group(1)+']'; j=s.find(close,m.end()); j=n if j<0 else j+len(close); out.append(s[i:j]); i=j; continue
        if c in '"\'':
            j=i+1
            while j<n and s[j]!=c:
                j+= 2 if s[j]=='\\' else 1
            out.append(s[i:j+1]); i=j+1; continue
        m=re.compile(r'[A-Za-z_]\w*|0[xX][0-9a-fA-F.]+(?:[pP][+-]?\d+)?|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?|\.\.\.|\.\.|==|~=|<=|>=|<<|>>|//|::|\S').match(s,i)
        out.append(m.group()); i=m.end()
    return out
a=toks(open(sys.argv[1],encoding='utf-8',errors='surrogateescape').read()); b=toks(open(sys.argv[2],encoding='utf-8',errors='surrogateescape').read())
sys.exit(0 if a==b else 1)
