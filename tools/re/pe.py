import struct,sys,re
EXE='/mnt/user-data/uploads/EnshroudedServer/enshrouded_server.exe'
data=open(EXE,'rb').read()
pe=struct.unpack_from('<I',data,0x3c)[0]
nsec=struct.unpack_from('<H',data,pe+6)[0]; opt=struct.unpack_from('<H',data,pe+20)[0]
base=struct.unpack_from('<Q',data,pe+24+24)[0]
secs=[]
off=pe+24+opt
for i in range(nsec):
    name=data[off:off+8].rstrip(b'\0').decode(); vsz,va,rsz,ra=struct.unpack_from('<IIII',data,off+8)
    secs.append((name,base+va,vsz,ra,rsz)); off+=40
def va2off(v):
    for n,va,vsz,ra,rsz in secs:
        if va<=v<va+max(vsz,rsz): return ra+(v-va)
def off2va(o):
    for n,va,vsz,ra,rsz in secs:
        if ra<=o<ra+rsz: return va+(o-ra)
def q(v): return struct.unpack_from('<Q',data,va2off(v))[0]
def u32(v): return struct.unpack_from('<I',data,va2off(v))[0]
def cstr(v,n=80):
    o=va2off(v); e=data.find(b'\0',o,o+n); return data[o:e].decode('latin1')
def find_ptrs(target):
    pat=struct.pack('<Q',target); res=[]; i=data.find(pat)
    while i!=-1: res.append(off2va(i)); i=data.find(pat,i+1)
    return res
def find_str(s):
    res=[]; pat=s.encode()+b'\0'; i=data.find(pat)
    while i!=-1:
        if i==0 or data[i-1]==0: res.append(off2va(i))
        i=data.find(pat,i+1)
    return res
