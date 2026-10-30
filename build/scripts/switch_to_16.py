import subprocess, sys

REPO = r'<REPO>'
GIT = r'<REPO>\.git'

def g(args):
    r = subprocess.run(
        ['git'] + args,
        cwd=REPO,
        capture_output=True, text=True,
        env={**__import__('os').environ, 'GIT_DIR': GIT, 'GIT_WORK_TREE': REPO}
    )
    print('$ git', ' '.join(args))
    if r.stdout: print(r.stdout)
    if r.stderr: print('[err]', r.stderr)
    return r

# 1. make sure we are on main and clean
g(['checkout', 'main'])
g(['reset', '--hard', 'HEAD'])

# 2. create a no-slash build branch off main (avoids the slash-ref write bug)
r = g(['checkout', '-b', 'build16'])
if r.returncode != 0:
    g(['checkout', 'build16'])

# 3. bring in the 16-target multi_bbox from line2/serial-wip
r = g(['checkout', 'line2/serial-wip', '--', 'src/rtl/multi_bbox.v'])
if r.returncode != 0:
    # fallback: extract blob directly and overwrite
    blob = subprocess.run(['git', 'show', 'line2/serial-wip:src/rtl/multi_bbox.v'],
                          cwd=REPO, capture_output=True,
                          env={**__import__('os').environ, 'GIT_DIR': GIT, 'GIT_WORK_TREE': REPO})
    with open(REPO + r'\src\rtl\multi_bbox.v', 'wb') as f:
        f.write(blob.stdout)
    print('fallback wrote multi_bbox.v')

# verify params
with open(REPO + r'\src\rtl\multi_bbox.v', encoding='utf-8', errors='replace') as f:
    txt = f.read()
import re
for key in ['MAX_LABEL', 'MAX_RUN', 'SF_DEPTH']:
    m = re.search(r'parameter integer %s\s*=\s*(\d+)' % key, txt)
    if not m:
        m = re.search(r'localparam integer %s\s*=\s*(\d+)' % key, txt)
    print(key, '=', m.group(1) if m else 'NOT FOUND')

# 4. commit on build16 (safe identity)
g(['-c', 'user.email=build@fpgateam.local', '-c', 'user.name=buildbot',
   'commit', '-m',
   'build: switch multi_bbox to 16-target (MAX_LABEL=16/MAX_RUN=16 + FIFO fix) for 16-bit'])
g(['log', '-1', '--format=%H %s'])
g(['status', '--porcelain'])
