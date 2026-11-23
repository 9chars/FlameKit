# Dev (0.15.462, owner 2026-11-22 20:30 "build a new clean install package in case someone new wants it"): builds the
# players' install package FlameKit-<version>.zip from what the updaters hand out, so a new player starts on exactly the
# FlameKit and EMF of a channel.
# Usage: python3 tools/release/make_package.py <repository> <dist | dist-test> <emf-dist | emf-dist-test> <EMF package> <out folder>
#   <EMF package>: the unzipped EMF-<version>.zip (its README.txt and LICENSE.txt go in as EMF-README.txt, EMF-LICENSE.txt)
# The zip: FlameKit-<v>/ README.txt (this folder's, {version} and {emf_version} filled in), EMF-README.txt,
# EMF-LICENSE.txt, install.cmd, install.ps1 (EMF's installer with Remove-OldFlameKit, this folder), uninstall.cmd,
# uninstall.ps1, emf_common.ps1 (EMF's own, this folder), licenses/ (EMF's), game/ (dinput8.dll and emf/: EMF's files
# from the EMF channel, emf/mods/flamekit and emf/mods/flamekit_native from the FlameKit channel).
# Check before a release that EMF's install.ps1 / emf_common.ps1 / uninstall.ps1 did not change (make_emf_dist.py with
# the previous package prints it): this folder's copies are EMF 0.6.6's (equal to 0.6.19's) plus Remove-OldFlameKit.
import json, os, sys, zipfile

repo, channel, emf_channel, emf_pkg, out = sys.argv[1:6]
here = os.path.dirname(os.path.abspath(__file__))
version = json.load(open(os.path.join(repo, channel, 'flamekit', 'mod.json'), encoding='utf-8-sig'))['version']
emf_version = open(os.path.join(repo, emf_channel, 'emf.txt')).readline().split()[1]
root = f'FlameKit-{version}/'
os.makedirs(out, exist_ok=True)
path = os.path.join(out, f'FlameKit-{version}.zip')
n = 0
with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
    def add(src, name):
        global n
        z.write(src, root + name)
        n += 1
    readme = open(os.path.join(here, 'README.txt'), encoding='utf-8').read().replace('{version}', version).replace('{emf_version}', emf_version)
    z.writestr(root + 'README.txt', readme.replace('\n', '\r\n'))
    add(os.path.join(emf_pkg, 'README.txt'), 'EMF-README.txt')
    add(os.path.join(emf_pkg, 'LICENSE.txt'), 'EMF-LICENSE.txt')
    for name in ('install.cmd', 'install.ps1', 'uninstall.cmd', 'uninstall.ps1', 'emf_common.ps1'):
        add(os.path.join(here, name), name)
    files = os.path.join(repo, emf_channel, 'files')
    for line in open(os.path.join(repo, emf_channel, 'emf.txt')).read().splitlines()[1:]:
        rel = line.split(' ', 2)[2]
        add(os.path.join(files, rel), 'game/' + rel)
        if rel.startswith('emf/licenses/'): add(os.path.join(files, rel), 'licenses/' + rel[len('emf/licenses/'):])
    for line in open(os.path.join(repo, channel, 'update.txt')).read().splitlines()[1:]:
        rel = line.split(' ', 2)[2]
        add(os.path.join(repo, channel, rel), 'game/emf/mods/' + rel)
print(f'{path}: FlameKit {version}, EMF {emf_version}, {n} files, {os.path.getsize(path) // 1024} KB')
