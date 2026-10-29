"""Recheck external feedback without changing the source or deleting artifacts."""
import argparse
import concurrent.futures
import csv
from datetime import datetime, timezone, timedelta
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import zipfile

ap = argparse.ArgumentParser()
ap.add_argument('--clone', type=Path, required=True)
ap.add_argument('--workspace', type=Path, required=True)
ap.add_argument('--out', type=Path, required=True)
ap.add_argument('--scratch', type=Path, required=True)
a = ap.parse_args()
repo, workspace, out, scratch = [p.resolve() for p in (a.clone, a.workspace, a.out, a.scratch)]
out.mkdir(parents=True, exist_ok=False)
scratch.mkdir(parents=True, exist_ok=False)
env = dict(os.environ, PYTHONUTF8='1', PYTHONIOENCODING='utf-8', PYTHONDONTWRITEBYTECODE='1', GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='never')
sys.dont_write_bytecode = True
sys.path.insert(0, str(repo/'src/ps'))
import numpy as np
import cv2

def save(name, value):
    (out/name).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def sha(data):
    return hashlib.sha256(data).hexdigest()

def command(name, args, timeout=420):
    start = datetime.now(timezone(timedelta(hours=8))).isoformat()
    tick = time.monotonic()
    with (out/(name+'.log')).open('xb') as f:
        try:
            p = subprocess.run([str(x) for x in args], cwd=repo, env=env, stdout=f, stderr=subprocess.STDOUT, timeout=timeout)
            rc = p.returncode
        except subprocess.TimeoutExpired:
            rc = 'timeout'
    result = dict(argv=[str(x) for x in args], cwd=str(repo), started=start, seconds=round(time.monotonic()-tick, 3), returncode=rc)
    save(name+'.command.json', result)
    print(name, rc, flush=True)
    return result

def py(name, *args):
    return command(name, [sys.executable, '-X', 'utf8', *args])

def software():
    return py('line3', 'sim/line3/run.py', '--out', out/'line3')

def rtl():
    settings = '<DRIVE>/AMD2025.2/2025.2/Vivado/settings64.bat'
    results = [py('rtl_default', 'build/scripts/run_sim.py', '--vivado-settings', settings, '--scratch-root', scratch/'default', '--expect-frames', '12')]
    for mode in ('framediff', 'bg'):
        results.append(py('rtl_drained_'+mode, 'sim/line3/run_rtl.py', '--settings', settings, '--out', scratch/('drained_'+mode), '--evidence', out/('rtl_drained_'+mode), '--mode', mode, '--drain-frames', '1'))
    return results

def suites():
    results = []
    for name, args in [
        ('boundaries', ['build/scripts/test_verification_boundaries.py', '--repo', repo, '--out', out/'boundaries']),
        ('runner', ['build/scripts/test_sim_runner.py', '--repo', repo, '--out', out/'runner']),
        ('tools', ['sim/line3/check_tools.py', '--out', out/'tools']),
        ('data_guard', ['build/scripts/test_data_guard.py', '--tmpdir', out/'data_guard', '--keep']),
        ('doc_commands', ['build/scripts/check_doc_commands.py'])]:
        results.append(py(name, *args))
    return results

def load_model(source):
    ns = {'__name__': 'feedback_mutation', '__file__': str(repo/'src/ps/rtl_golden.py')}
    exec(compile(source, '<isolated_model>', 'exec'), ns)
    return ns

def audits():
    source = (repo/'src/ps/rtl_golden.py').read_text(encoding='utf-8')
    base = load_model(source)
    baseline = base['run']()[1]
    mutants = {'threshold69': source.replace('THRESH = 70', 'THRESH = 69'),
               'no_last_column': source.replace('    d[:, -1] = False', '    # last column clearing omitted'),
               'last_frame': source.replace('    return p, rows', '    rows[-1] = (rows[-1][0], 0, 65535, 65535, 0, 0, 0)\n    return p, rows')}
    mutations = {}
    for name, changed in mutants.items():
        assert changed != source
        path = out/(name+'.py')
        path.write_text(changed, encoding='utf-8')
        rc = py('mutation_'+name, path, '--compare', repo/'sim/wave/bbox_rtl.csv', '--out-csv', out/(name+'.csv'))
        rows = load_model(changed)['run']()[1]
        mutations[name] = dict(command=rc, changed_frames=[i for i,(x,y) in enumerate(zip(baseline,rows)) if x != y], output_last_frame=rows[-1])
    # Positive controls establish that these are actual behavioural mutations.
    near = np.array([69,70,71])
    mutations['threshold_positive_control'] = dict(input=near.tolist(), base=base['mask_of'](near).tolist(), mutated=load_model(mutants['threshold69'])['mask_of'](near).tolist())
    edge = np.ones((10,10), dtype=bool)
    mutations['edge_positive_control'] = dict(base_last_column=int(base['open3'](edge)[:,-1].sum()), mutated_last_column=int(load_model(mutants['no_last_column'])['open3'](edge)[:,-1].sum()))
    save('mutations.json', mutations)
    # F6: preserve source location semantics without writing into src/ps.
    mt = repo/'src/ps/multi_track.py'
    wrapper = 'from pathlib import Path\nsource=Path('+repr(str(mt))+').read_text(encoding="utf-8")\nsource=source.replace("self.next_id = 1", "self.next_id = 5")\nexec(compile(source, '+repr(str(mt))+', "exec"), {"__name__":"__main__", "__file__":'+repr(str(mt))+'})\n'
    (out/'id_mutation.py').write_text(wrapper, encoding='utf-8')
    py('id_mutation', out/'id_mutation.py', '--source', 'algo', '--init-frames', '12', '--alarm', '--line-x', '640', '--no-video', '--outdir', out/'id_mutation')
    comparisons = {}
    for name in ('multi_track_results_algo.csv', 'alarm_events_algo.csv'):
        lhs = list(csv.reader(io.StringIO((repo/'src/ps'/name).read_text(encoding='utf-8'))))
        rhs = list(csv.reader(io.StringIO((out/'id_mutation'/name).read_text(encoding='utf-8'))))
        comparisons[name] = dict(equal=lhs==rhs, reference=lhs[:4], mutated=rhs[:4])
    save('id_comparison.json', comparisons)
    # F5: byte hashes and full decoding, not just metadata.
    videos = [repo/'src/ps/track_result.mp4', repo/'src/ps/track_result_algo.mp4']
    caps = [cv2.VideoCapture(str(p)) for p in videos]
    n = same = 0
    while True:
        pairs = [c.read() for c in caps]
        if not all(ok for ok, frame in pairs):
            endings = [bool(ok) for ok,frame in pairs]
            break
        n += 1
        same += int(np.array_equal(pairs[0][1],pairs[1][1]))
    for cap in caps:
        cap.release()
    save('video_comparison.json', dict(files=[str(x) for x in videos], sha256=[sha(p.read_bytes()) for p in videos], paired_frames=n, equal_frames=same, end_read_success=endings))
    # F9: compare the delivered zip with a fresh checkout and a fresh Git archive.
    zpath = workspace/'delivery/line3_review_783cd7c.zip'
    fresh = subprocess.check_output(['git','archive','--format=zip','783cd7c'], cwd=repo)
    with zipfile.ZipFile(zpath) as z, zipfile.ZipFile(io.BytesIO(fresh)) as gz:
        names = [n for n in z.namelist() if not n.endswith('/')]
        exact, eol, other, gitdiff = [], [], [], []
        for name in names:
            zb, cb = z.read(name), (repo/name).read_bytes()
            if zb == cb: exact.append(name)
            elif zb.replace(b'\r\n',b'\n') == cb.replace(b'\r\n',b'\n'): eol.append(name)
            else: other.append(name)
            if zb != gz.read(name): gitdiff.append(name)
        save('delivery_comparison.json', dict(file_count=len(names), sha256=sha(zpath.read_bytes()), crc_bad_entry=z.testzip(), exact=len(exact), eol_only=eol, content_differences=other, fresh_archive_differences=gitdiff))
    # The isolated clone's origin is local; resolve the live repo's GitHub URL.
    remote_url = subprocess.check_output(['git','-C',str(workspace/'captain_repo'),'remote','get-url','origin']).decode().strip()
    command('remote_refs', ['git','ls-remote',remote_url,'refs/heads/main','refs/heads/codex/line3-review-20261009'], timeout=45)
    return {'completed':True}

tracked = subprocess.check_output(['git','ls-files','-z'], cwd=repo).decode('utf-8').split('\0')
before = {n:sha((repo/n).read_bytes()) for n in tracked if n}
save('environment.json', dict(started=datetime.now(timezone(timedelta(hours=8))).isoformat(), repo=str(repo), python=sys.executable, version=sys.version, numpy=np.__version__, opencv=cv2.__version__, head=subprocess.check_output(['git','rev-parse','HEAD'], cwd=repo).decode().strip(), source_hashes=before))
results = {}
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    jobs = {pool.submit(fn):name for name,fn in [('software',software),('rtl',rtl),('suites',suites),('audits',audits)]}
    for future in concurrent.futures.as_completed(jobs):
        name = jobs[future]
        try: results[name] = future.result()
        except Exception as exc: results[name] = {'error':repr(exc)}
        save('job_results.json', results)
after = {n:sha((repo/n).read_bytes()) for n in before}
save('source_integrity.json', dict(changed=[n for n in before if before[n]!=after[n]], tracked_files=len(before)))
print(json.dumps(results,ensure_ascii=False), flush=True)
