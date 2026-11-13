# Dev: builds a channel folder (dist-test or dist) that players' games update from (web_update.hpp).
# Usage: python3 make_dist.py <repository folder> <channel folder name> <built flamekit_native.dll> <its mod.json>
# The folder mirrors emf\mods: flamekit/<the Lua part>, flamekit_native/<the DLL and its mod.json>, and update.txt:
# the version, then "<size> <hash> <path>" per file.
import os, sys, json, shutil
repo, channel, dll, dll_json = sys.argv[1:5]
out = os.path.join(repo, channel)
def fnv(b):
    h = 2166136261
    for c in b: h = ((h ^ c) * 16777619) & 0xffffffff
    return h
if os.path.isdir(out): shutil.rmtree(out)
shutil.copytree(os.path.join(repo, 'flamekit'), os.path.join(out, 'flamekit'))
os.makedirs(os.path.join(out, 'flamekit_native'))
shutil.copyfile(dll, os.path.join(out, 'flamekit_native', 'flamekit_native.dll'))
shutil.copyfile(dll_json, os.path.join(out, 'flamekit_native', 'mod.json'))
version = json.load(open(os.path.join(out, 'flamekit', 'mod.json'), encoding='utf-8-sig'))['version']
assert version == json.load(open(dll_json, encoding='utf-8-sig'))['version'], 'the two parts have different versions'
lines = [version]
for root, dirs, files in os.walk(out):
    dirs.sort()
    for name in sorted(files):
        if name == 'update.txt' and root == out: continue
        full = os.path.join(root, name)
        rel = os.path.relpath(full, out).replace(os.sep, '/')
        b = open(full, 'rb').read()
        lines.append(f'{len(b)} {fnv(b):08x} {rel}')
open(os.path.join(out, 'update.txt'), 'w', newline='\n').write('\n'.join(lines) + '\n')
print(channel, version, len(lines) - 1, 'files')
