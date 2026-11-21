# (0.15.362) the split companion code (features/companions/*.lua, in features/companions.lua's PARTS order) as ONE file
# for the test harnesses, which load a single file: python3 bundle.py [out]  (default /tmp/companions_bundle.lua).
# The parts share one environment in the game, so running them one after the other in one chunk is the same.
import os, re, sys
here = os.path.dirname(os.path.abspath(__file__))
feat = os.path.join(here, '..', '..', 'flamekit', 'features')  # (0.15.368) in the release now
loader = open(os.path.join(feat, 'companions.lua')).read()
parts = re.findall(r'^\s*"(\d\d_[a-z_]+)",', loader, re.M)
out = sys.argv[1] if len(sys.argv) > 1 else '/tmp/companions_bundle.lua'
open(out, 'w').write('\n'.join(open(os.path.join(feat, 'companions', p + '.lua')).read() for p in parts))
print(out, len(parts), 'parts')
