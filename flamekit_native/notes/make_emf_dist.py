# Dev (0.15.454): builds an EMF channel folder (emf-dist-test or emf-dist) that FlameKit's updater keeps players' EMF up
# to date from (flamekit_native/src/emf_update.hpp).
# Usage: python3 make_emf_dist.py <repository folder> <emf-dist-test | emf-dist> <EMF release package folder> [<previous package>]
#   the package folder is the unzipped EMF-<version>.zip (with game\dinput8.dll and game\emf\...)
#   (owner 2026-11-22 19:24: "I agree about comparing EMF's installer script against previous versions") with the
#   previous package (the EMF the channel had), it prints what changed in EMF's installer (install.ps1, emf_common.ps1,
#   uninstall.ps1, install.cmd): FlameKit's update only copies files, so anything new the installer does (a Vulkan
#   layer, a Windows setting, a chain with another loader) must be read before the update goes out. Also the files the
#   new EMF no longer ships (the update leaves them on players' PCs).
# The folder gets: files/<path> (dinput8.dll and EMF's files in emf/, without EMF's example mods: of emf/mods only the
# Lua host emf/mods/lua), emf.txt ("emf <version>", then "<size> <sha256> <path>" per file) and, from the sign step,
# emf.sig. The version is the FileVersion of emf_core.dll, the same number the updater compares with the player's.
# Sign it like update.txt: copy emf.txt to restart_helper\signing\update.txt, ask the helper for "sign", and copy the
# update.sig it makes to <channel>\emf.sig. Then: python3 tools/check_sig.py <channel> emf.txt emf.sig
# EMF is MIT licensed; emf_content.dll (EML's content builder) is GPL-3.0-or-later: its source is EMF's own release
# (https://github.com/matenm/emf-enshrouded/releases); the licence files go along in files/emf/licenses/.
import hashlib, os, re, shutil, sys

repo, channel, package = sys.argv[1:4]
previous = sys.argv[4] if len(sys.argv) > 4 else None
assert channel in ('emf-dist-test', 'emf-dist'), 'the channel is emf-dist-test or emf-dist'
game = os.path.join(package, 'game')
core = os.path.join(game, 'emf', 'emf_core.dll')
assert os.path.isfile(core), 'no game/emf/emf_core.dll in ' + package

def file_version(path):
    # the FileVersion text of a PE file's version resource (UTF-16, "FileVersion\0" then padding, then the value)
    data = open(path, 'rb').read()
    key = 'FileVersion'.encode('utf-16le') + b'\0\0'
    at = data.find(key)
    assert at >= 0, 'no FileVersion in ' + path
    at += len(key)
    while at % 4: at += 1  # the value starts on a 32-bit boundary
    end = data.find(b'\0\0', at)
    while (end - at) % 2: end = data.find(b'\0\0', end + 1)
    return data[at:end].decode('utf-16le').strip()

def allowed(rel):  # the same rule as emf_update::allowed
    low = rel.lower()
    if low == 'dinput8.dll': return True
    if not low.startswith('emf/') or low.startswith('emf/config/') or low.startswith('emf/flamekit'): return False
    if low.startswith('emf/mods'): return low.startswith('emf/mods/lua/')
    return re.fullmatch(r'[A-Za-z0-9_./-]+', rel) is not None and '..' not in rel

version = file_version(core)
assert re.fullmatch(r'[0-9.]+', version), 'odd version ' + version
out = os.path.join(repo, channel)
if os.path.isdir(out): shutil.rmtree(out)
files = []
for root, dirs, names in os.walk(game):
    dirs.sort()
    for name in sorted(names):
        rel = os.path.relpath(os.path.join(root, name), game).replace(os.sep, '/')
        if rel.lower().startswith('emf/mods') and not rel.lower().startswith('emf/mods/lua/'): continue  # example mods
        assert allowed(rel), 'a file the updater would refuse: ' + rel
        files.append(rel)
lic = os.path.join(package, 'licenses')
dest_files = os.path.join(out, 'files')
for rel in files:
    os.makedirs(os.path.dirname(os.path.join(dest_files, rel)), exist_ok=True)
    shutil.copyfile(os.path.join(game, rel), os.path.join(dest_files, rel))
if os.path.isdir(lic):  # the licences of EMF and what it carries, installed next to EMF
    for name in sorted(os.listdir(lic)):
        rel = 'emf/licenses/' + name
        os.makedirs(os.path.join(dest_files, 'emf', 'licenses'), exist_ok=True)
        shutil.copyfile(os.path.join(lic, name), os.path.join(dest_files, rel))
        files.append(rel)
files.sort()
assert len(files) <= 128, 'more than 128 files'
lines = ['emf ' + version]
for rel in files:
    b = open(os.path.join(dest_files, rel), 'rb').read()
    assert len(b) <= 16 << 20, 'over 16 MB: ' + rel
    lines.append(f'{len(b)} {hashlib.sha256(b).hexdigest()} {rel}')
open(os.path.join(out, 'emf.txt'), 'w', newline='\n').write('\n'.join(lines) + '\n')
print(channel, 'EMF', version, len(files), 'files,', sum(os.path.getsize(os.path.join(dest_files, r)) for r in files) // 1024, 'KB')

if previous:  # what EMF's installer does differently now, and what is gone
    import difflib
    print('--- compared with', previous)
    for rel in ('install.ps1', 'uninstall.ps1', 'emf_common.ps1', 'install.cmd', 'uninstall.cmd'):
        a, b = os.path.join(previous, rel), os.path.join(package, rel)
        old = open(a, encoding='utf-8', errors='replace').read().splitlines() if os.path.isfile(a) else []
        new = open(b, encoding='utf-8', errors='replace').read().splitlines() if os.path.isfile(b) else []
        diff = list(difflib.unified_diff(old, new, 'old/' + rel, 'new/' + rel, n=1, lineterm=''))
        print(f'{rel}: ' + ('unchanged' if not diff else f'{sum(1 for d in diff if d[:1] in "+-") - 2} line(s) changed'))
        for d in diff: print('   ' + d)
    old_game = os.path.join(previous, 'game')
    gone = []
    for root, dirs, names in os.walk(old_game):
        for name in names:
            rel = os.path.relpath(os.path.join(root, name), old_game).replace(os.sep, '/')
            if rel.lower().startswith('emf/mods') and not rel.lower().startswith('emf/mods/lua/'): continue
            if allowed(rel) and rel not in files: gone.append(rel)
    print('no longer shipped (left on players\' PCs):', ', '.join(sorted(gone)) or 'none')
