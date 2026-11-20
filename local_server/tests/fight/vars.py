import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
# strip comments and strings
def strip(code):
    code = re.sub(r'--\[\[.*?\]\]', ' ', code, flags=re.S)
    out=[]; i=0; n=len(code)
    while i<n:
        ch=code[i]
        if code.startswith('--',i):
            j=code.find('\n',i); i = n if j<0 else j; continue
        if ch in '"\'':
            q=ch; i+=1
            while i<n and code[i]!=q:
                if code[i]=='\\': i+=1
                i+=1
            i+=1; out.append(' "" '); continue
        out.append(ch); i+=1
    return ''.join(out)
c = strip(s)
lines = c.split('\n')
# file-level locals
filelocals=set()
for ln in lines:
    m=re.match(r'local function (\w+)',ln)
    if m: filelocals.add(m.group(1))
    m=re.match(r'local ([\w ,]+)=',ln)
    if m: filelocals|=set(x.strip() for x in m.group(1).split(','))
    m=re.match(r'local (\w+)\s*$',ln)
    if m: filelocals.add(m.group(1))
known=set('math string table pcall tostring tonumber ipairs pairs type require emf error select next setmetatable getmetatable rawget rawset os io unpack print assert true false nil and or not end then do if else elseif for while in function local return break repeat until goto self'.split())
# parts
for m in re.finditer(r'\nlocal function (drive_\w+|face|hold_at|health|edge_off|launch_speeds|launch|report_blockers)\((.*?)\)\n(.*?)\nend\n', c, re.S):
    name, params, body = m.group(1), m.group(2), m.group(3)
    declared=set(p.strip() for p in params.split(',') if p.strip())
    for d in re.findall(r'local\s+function\s+(\w+)', body): declared.add(d)
    for d in re.findall(r'local\s+([\w\s,]+?)(?:=|\n|$)', body):
        declared|=set(x.strip() for x in d.split(',') if x.strip())
    for d in re.findall(r'for\s+([\w\s,]+?)\s+(?:=|in)', body):
        declared|=set(x.strip() for x in d.split(','))
    for d in re.findall(r'function\s*\(([^)]*)\)', body):
        declared|=set(x.strip() for x in d.split(',') if x.strip())
    used=set()
    for tok in re.finditer(r'(?<![\.\:\w])([A-Za-z_]\w*)', body):
        used.add(tok.group(1))
    # remove field names after '.' handled by lookbehind; remove table constructor keys "x ="
    keys=set(re.findall(r'[\{,]\s*(\w+)\s*=(?!=)', body))
    bad = sorted(u for u in used - declared - filelocals - known - keys)
    # declared-but-unused prologue vars
    unused = sorted(d for d in declared if len(re.findall(r'(?<![\.\:\w])'+d+r'\b', body))<=1 and d!='_')
    print(name, 'UNDECLARED:', bad, '| UNUSED:', unused)
