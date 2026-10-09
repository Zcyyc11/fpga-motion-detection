# -*- coding: utf-8 -*-
"""Frame/CLI regressions. All fixtures, copies and logs are retained in --out.

Run against any checkout with --repo. A fresh --out is required; no deletions.
The worker observes real image loads and metrics calls without changing results.
"""
import argparse
from collections import Counter
import csv
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import time

import cv2
import numpy as np

ENTRIES = dict(official='cdnet_official', lab='algo_lab', ab='algo_ab',
               demo='cdnet_demo', five='five_steps')
ENV = dict(os.environ, PYTHONUTF8='1', PYTHONIOENCODING='utf-8',
           PYTHONDONTWRITEBYTECODE='1', MOTION_PYTHON=sys.executable)
ENV.pop('CDNET_ROOT', None)


def save(path, obj):
    Path(path).write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding='utf-8')


def hashes(root):
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob('*') if p.is_file() and '.git' not in p.parts}


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_seq(sd, gt_all=False, last=12):
    (sd / 'input').mkdir(parents=True)
    (sd / 'groundtruth').mkdir()
    (sd / 'temporalROI.txt').write_text('3 10\n', encoding='utf-8')
    rng = np.random.RandomState(20261008)
    for i in range(1, last + 1):
        gray = rng.randint(0, 255, (16, 16), dtype=np.uint8)
        ok, buf = cv2.imencode('.jpg', np.stack([gray] * 3, axis=2))
        assert ok
        (sd / 'input' / ('in%06d.jpg' % i)).write_bytes(buf.tobytes())
        if gt_all or 3 <= i <= 10:
            truth = np.zeros((16, 16), np.uint8)
            truth[4:10, 4:10] = 255 if i % 2 else 0
            ok, buf = cv2.imencode('.png', truth)
            assert ok
            (sd / 'groundtruth' / ('gt%06d.png' % i)).write_bytes(buf.tobytes())


def worker(case, entry, args):
    os.chdir(case)
    sys.path.insert(0, str(case / 'src' / 'ps'))
    import cdnet_io as cio
    trace = dict(loads=[], scores=[], reads=[])
    refs, identities = [], {}
    old_load, old_read = cio.load_seq, cio.imread

    def read(path, *a, **kw):
        trace['reads'].append(str(path))
        return old_read(path, *a, **kw)

    def seq(seqdir, first, count, nwarm=0):
        result = old_load(seqdir, first, count, nwarm)
        refs.append(result)
        frames = [cio.frame_no(n) for n in result[2]]
        trace['loads'].append(dict(seq=Path(seqdir).name, first=first, count=count,
                                   nwarm=nwarm, frames=frames))
        for fr, label in zip(frames, result[1]):
            identities[id(label)] = (Path(seqdir).name, fr)
        return result

    def profile(frame, event, arg):
        if event == 'return' and frame.f_code.co_name == 'metrics':
            label = frame.f_locals.get('label')
            if id(label) in identities:
                name, number = identities[id(label)]
                trace['scores'].append(dict(seq=name, frame=number,
                    caller=frame.f_back.f_code.co_name, metrics=list(arg)))

    cio.imread, cio.load_seq = read, seq
    sys.argv = [ENTRIES[entry] + '.py'] + args
    rc = 0
    try:
        sys.setprofile(profile)
        runpy.run_path(str(case / 'src' / 'ps' / sys.argv[0]), run_name='__main__')
    except SystemExit as e:
        rc = e.code or 0
    finally:
        sys.setprofile(None)
        save(case / 'trace.json', trace)
    return rc


class Suite:
    def __init__(self, repo, out):
        self.repo, self.out = repo, out
        out.mkdir(parents=True, exist_ok=False)
        self.results = []

    def record(self, name, fn):
        try:
            detail = fn()
            row = dict(name=name, passed=True, detail=detail)
        except Exception as exc:
            row = dict(name=name, passed=False, error=str(exc), error_type=type(exc).__name__)
        self.results.append(row)
        save(self.out / 'results.json', self.results)
        print(('PASS ' if row['passed'] else 'FAIL ') + name +
              (': ' + row.get('error', '') if not row['passed'] else ''), flush=True)

    def case(self, name, gt_all=False, last=12):
        case = self.out / name
        (case / 'src' / 'ps').mkdir(parents=True)
        for p in (self.repo / 'src' / 'ps').glob('*.py'):
            shutil.copy2(p, case / 'src' / 'ps' / p.name)
        for rel in ['baseline/pedestrians', 'dynamicBackground/canoe']:
            make_seq(case / 'data' / rel, gt_all, last)
        return case

    def run(self, case, entry, extra=()):
        data = case / 'data'
        if entry == 'demo':
            args = ['--seq', str(data / 'baseline' / 'pedestrians')]
        elif entry == 'five':
            args = ['--data-root', str(data), '--seq', 'pedestrians']
        elif entry == 'ab':
            args = ['--data-root', str(data), '--seq', 'both']
        else:
            args = ['--data-root', str(data), '--seq', 'all', '--set', 'r5']
        command = [sys.executable, '-X', 'utf8', str(Path(__file__).resolve()),
                   '--worker', str(case), entry, *args, *map(str, extra)]
        started = time.monotonic()
        proc = subprocess.run(command, env=ENV, capture_output=True, timeout=180)
        text = proc.stdout.decode('utf-8') + '\n--- stderr ---\n' + proc.stderr.decode('utf-8')
        (case / 'run.log').write_text(text, encoding='utf-8')
        save(case / 'command.json', dict(command=command, rc=proc.returncode,
                                       seconds=time.monotonic() - started))
        trace = json.loads((case / 'trace.json').read_text(encoding='utf-8'))
        return proc.returncode, text, trace

    @staticmethod
    def products(case):
        return sorted(p for p in case.rglob('*') if p.suffix == '.csv' or
                      p.name.startswith(('five_steps_', 'cdnet_demo_fig')))

    @staticmethod
    def failed_cleanly(rc, text, case):
        assert rc != 0, 'invalid request returned success'
        assert 'Traceback (most recent call last)' not in text, text[-1000:]
        assert '[数据' in text or 'error:' in text, text[-1000:]
        assert not Suite.products(case), 'failed run produced scores/images'

    @staticmethod
    def check_scores(trace, expected, seqs=('pedestrians', 'canoe')):
        detail = {}
        for seq in seqs:
            frames = [x['frame'] for x in trace['scores'] if x['seq'] == seq]
            assert set(frames) == set(expected), (seq, frames, expected)
            counts = Counter(frames)
            assert len(set(counts.values())) == 1, counts
            repeats = next(iter(counts.values()))
            assert frames == expected * repeats, (frames, expected)
            detail[seq] = dict(frames=expected, repetitions=repeats)
        return detail

    def roi(self):
        cio = load('cio_plan', self.repo / 'src/ps/cdnet_io.py')
        plan_case = self.out / 'plan_fixture'
        make_seq(plan_case)
        for warmup in [0, 1, 100, -1, 0.5]:
            for frames in [0, 3, 8, 10, -1, 0.5]:
                def check(warmup=warmup, frames=frames):
                    if warmup < 0 or frames < 0 or isinstance(warmup, float) or isinstance(frames, float):
                        try:
                            cio.frame_plan(str(plan_case), warmup, frames)
                        except cio.DataError:
                            return 'clear DataError'
                        raise AssertionError('invalid value silently accepted')
                    plan = cio.frame_plan(str(plan_case), warmup, frames)
                    first = max(1, 3 - warmup)
                    last = min(10, 3 + frames - 1) if frames else 10
                    assert plan == dict(roi=(3, 10), first=first, nwarm=3-first,
                                        count=last-first+1, score=(3, last)), plan
                    return plan
                self.record('plan_w%s_f%s' % (warmup, frames), check)
        for entry in ['official', 'lab', 'ab']:
            for n in [0, 3, 8, 10, -1]:
                for gt in [False, True]:
                    name = 'roi_%s_%d_gt%d' % (entry, n, gt)
                    def check(entry=entry, n=n, gt=gt, name=name):
                        case = self.case(name, gt)
                        rc, text, trace = self.run(case, entry, ['--frames', n])
                        if n < 0:
                            self.failed_cleanly(rc, text, case)
                            return dict(rc=rc)
                        assert rc == 0, text[-1500:]
                        expected = list(range(3, 3 + (min(n, 8) if n else 8)))
                        for row in trace['loads']:
                            assert row['frames'] == list(range(1, expected[-1] + 1)), row
                            assert row['nwarm'] == 2, row
                        return self.check_scores(trace, expected)
                    self.record(name, check)
            for n in [0, 3, 8, 10]:
                def equal(entry=entry, n=n):
                    traces = [json.loads((self.out / ('roi_%s_%d_gt%d' % (entry, n, gt)) /
                                          'trace.json').read_text(encoding='utf-8')) for gt in [0, 1]]
                    assert traces[0]['scores'] == traces[1]['scores'], 'outside-ROI GT changed scores'
                self.record('roi_gt_independence_%s_%d' % (entry, n), equal)

    def five(self):
        cases = [('early_long', 5, 9, True), ('early_default', 5, None, True),
                 ('early_short', 5, 2, True), ('late', 10, 4, True),
                 ('first', 1, 9, False), ('zero_warmup', 5, 0, False),
                 ('negative_frame', -1, 2, False), ('negative_warmup', 5, -1, False),
                 ('auto', 0, None, True)]
        for tag, target, warmup, valid in cases:
            def check(tag=tag, target=target, warmup=warmup, valid=valid):
                case = self.case('five_' + tag)
                args = ['--frame', target] + ([] if warmup is None else ['--warmup', warmup])
                rc, text, trace = self.run(case, 'five', args)
                if not valid:
                    self.failed_cleanly(rc, text, case)
                    return dict(rc=rc)
                assert rc == 0, text[-1500:]
                actual = target or 6
                first = max(1, actual - (100 if warmup is None else warmup))
                assert trace['loads'][0]['frames'] == list(range(first, actual + 1)), trace['loads']
                assert trace['loads'][0]['nwarm'] == actual - first, trace['loads']
                assert Path(trace['reads'][-1]).name == 'in%06d.jpg' % actual, trace['reads'][-1]
                images = list(case.rglob('five_steps_*.png'))
                assert len(images) == 1 and images[0].name.endswith('_f%d.png' % actual), images
                img = cv2.imdecode(np.frombuffer(images[0].read_bytes(), np.uint8), cv2.IMREAD_COLOR)
                assert img is not None and min(img.shape[:2]) > 500, 'bad image'
                assert 'Glyph' not in text, 'missing font glyphs'
                return dict(target=actual, last_read=trace['reads'][-1], image=str(images[0]), shape=img.shape)
            self.record('five_' + tag, check)

    def demo(self):
        def short_input():
            case = self.case('demo_short_input', last=4)
            rc, text, trace = self.run(case, 'demo', ['--start', 1])
            self.failed_cleanly(rc, text, case)
            assert '第 5 帧' in text, text
        self.record('demo_short_input', short_input)
        for start, count, expected in [(1, 0, list(range(3, 11))), (0, 0, list(range(4, 11))),
                (1, 5, [3, 4, 5]), (1, 20, list(range(3, 11))), (8, 20, [9, 10]),
                (1, 2, []), (10, 0, []), (11, 0, []), (-1, 0, []), (1, -1, [])]:
            for gt in [False, True]:
                name = 'demo_s%d_n%d_gt%d' % (start, count, gt)
                def check(start=start, count=count, expected=expected, gt=gt, name=name):
                    case = self.case(name, gt)
                    rc, text, trace = self.run(case, 'demo', ['--start', start, '--frames', count])
                    if not expected:
                        self.failed_cleanly(rc, text, case)
                        return dict(rc=rc)
                    assert rc == 0, text[-1500:]
                    csvpath = next(case.rglob('cdnet_demo_metrics.csv'))
                    with csvpath.open(encoding='utf-8') as stream:
                        rows = list(csv.DictReader(stream))
                    actual = [int(r['frame']) for r in rows]
                    assert actual == expected, (actual, expected)
                    assert [r['frame'] for r in trace['scores'][:-1]] == expected, trace['scores']
                    assert trace['scores'][-1]['frame'] in expected, trace['scores'][-1]
                    assert trace['loads'][0]['frames'][-1] <= 10, trace['loads']
                    img = cv2.imdecode(np.frombuffer(next(case.rglob('cdnet_demo_fig.png')).read_bytes(), np.uint8), 1)
                    assert img is not None and 'Glyph' not in text, 'invalid image/font'
                    return dict(frames=actual, plot_frame=trace['scores'][-1]['frame'])
                self.record(name, check)
            if expected:
                def equal(start=start, count=count):
                    data = [next((self.out / ('demo_s%d_n%d_gt%d' % (start, count, gt))).rglob('*.csv')).read_bytes() for gt in [0, 1]]
                    assert data[0] == data[1], 'warmup GT changed CSV'
                self.record('demo_gt_independence_s%d_n%d' % (start, count), equal)

    def docs(self):
        checker = load('doc_checker', self.repo / 'build/scripts/check_doc_commands.py')
        cache = {}
        cases = [
            ('quoted', 'python src/ps/multi_track.py --outdir "my data" --nonexistent-flag', 1),
            ('unicode', 'python src/ps/multi_track.py --outdir "我的 数据" --nonexistent-flag', 1),
            ('single', "python src/ps/multi_track.py --outdir '我的 数据' --nonexistent-flag", 1),
            ('equals', 'python src/ps/multi_track.py --outdir="我的 数据" --nonexistent-flag', 1),
            ('legal', 'python src/ps/multi_track.py --outdir "我的 数据" --source clean', 0),
            ('quoted_flag_value', 'python src/ps/multi_track.py --outdir "--nonexistent-flag" --source clean', 0),
            ('comment', 'python src/ps/multi_track.py --source clean # --nonexistent-flag', 0),
            ('html_comment', 'python src/ps/multi_track.py --source clean <!-- --nonexistent-flag -->', 0),
            ('quoted_comment', 'python src/ps/multi_track.py --outdir "# folder;" --nonexistent-flag', 1),
            ('pipeline', 'python src/ps/multi_track.py --source clean|other --nonexistent-flag', 0),
            ('redirect', 'python src/ps/multi_track.py --source clean>log --nonexistent-flag', 0),
            ('semicolon', 'python src/ps/multi_track.py --source clean;other --nonexistent-flag', 0),
            ('two_commands', 'python src/ps/multi_track.py --source clean && python src/ps/algo_lab.py --nonexistent-flag', 1),
            ('inline', '`python src/ps/multi_track.py --outdir "my data" --nonexistent-flag`', 1),
            ('inline_prose', '`python src/ps/multi_track.py --source clean` then mention --nonexistent-flag', 0),
            ('negative', 'python src/ps/multi_track.py --nonexistent-flag <!-- 反例：故意写错 -->', 0),
            ('negative_skip', 'python src/ps/multi_track.py --nonexistent-flag <!-- doc-check: skip -->', 0),
            ('quoted_command', 'python src/ps/multi_track.py --outdir "python missing.py --bad" --source clean', 0),
            ('comment_command', 'python src/ps/multi_track.py --source clean # python missing.py --bad', 0),
            ('comment_only', '# python missing.py --bad', 0),
            ('html_command', '<!-- python missing.py --bad -->', 0),
        ]
        for symbol, tag in [('`', 'powershell'), ('\\', 'bash'), ('^', 'cmd')]:
            cases.extend([(tag, 'python src/ps/multi_track.py --outdir "我的 数据" ' + symbol + '\n --nonexistent-flag', 1),
                (tag + '_legal', 'python src/ps/multi_track.py --source ' + symbol + '\n clean', 0)])
        for name, body, count in cases:
            def check(name=name, body=body, count=count):
                p = self.out / ('doc_' + name + '.md')
                p.write_text(body + '\n', encoding='utf-8')
                errors, degraded = [], set()
                checker.check_file(str(p), cache, errors, degraded)
                assert len(errors) == count, errors
                assert not degraded, degraded
                return dict(errors=errors)
            self.record('doc_' + name, check)

    def matrix(self):
        kinds = ['valid', 'missing_input', 'bad_input', 'header_only',
                 'missing_truth', 'bad_truth', 'wrong_size', 'warmup_no_truth']
        for entry in ENTRIES:
            for kind in kinds:
                name = 'matrix_%s_%s' % (entry, kind)
                def check(entry=entry, kind=kind, name=name):
                    case = self.case(name, kind != 'warmup_no_truth')
                    for rel in ['baseline/pedestrians', 'dynamicBackground/canoe']:
                        sd = case / 'data' / rel
                        inp, gt = sd / 'input/in000005.jpg', sd / 'groundtruth/gt000005.png'
                        p = inp if kind in ['missing_input', 'bad_input', 'header_only'] else gt
                        if kind not in ['valid', 'warmup_no_truth']:
                            p.rename(p.with_suffix(p.suffix + '.saved'))
                            if kind in ['bad_input', 'header_only', 'bad_truth']:
                                p.write_bytes((b'\xff\xd8\xff\xe0' if kind == 'header_only' else b'') + b'broken image' * 10)
                            if kind == 'wrong_size':
                                ok, buf = cv2.imencode('.png', np.zeros((8, 8), np.uint8))
                                assert ok
                                p.write_bytes(buf.tobytes())
                    args = ['--frame', 5, '--warmup', 4] if entry == 'five' else []
                    rc, text, trace = self.run(case, entry, args)
                    if kind not in ['valid', 'warmup_no_truth']:
                        self.failed_cleanly(rc, text, case)
                        assert '第 5 帧' in text, text[-1500:]
                    else:
                        assert rc == 0, text[-1500:]
                        assert self.products(case), 'no output'
                        if entry in ['official', 'lab', 'ab']:
                            self.check_scores(trace, list(range(3, 11)))
                        elif entry == 'five':
                            assert trace['loads'][0]['frames'][-1] == 5, trace['loads']
                        else:
                            with next(case.rglob('*.csv')).open(encoding='utf-8') as stream:
                                assert [int(r['frame']) for r in csv.DictReader(stream)] == list(range(4, 11))
                    return dict(rc=rc, products=[str(p.relative_to(case)) for p in self.products(case)])
                self.record(name, check)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--worker':
        return worker(Path(sys.argv[2]), sys.argv[3], sys.argv[4:])
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[2])
    ap.add_argument('--out', type=Path, required=True, help='New evidence directory; retained')
    ap.add_argument('--suite', choices=['boundaries', 'matrix', 'docs', 'all'], default='all')
    args = ap.parse_args()
    repo, out = args.repo.resolve(), args.out.resolve()
    if out.is_relative_to(repo):
        ap.error('--out must be outside the tested checkout')
    before = hashes(repo)
    suite = Suite(repo, out)
    if args.suite in ['boundaries', 'all']:
        suite.roi(); suite.five(); suite.demo()
    if args.suite in ['docs', 'boundaries', 'all']:
        suite.docs()
    if args.suite in ['matrix', 'all']:
        suite.matrix()
    after = hashes(repo)
    integrity = dict(changed=[k for k, v in before.items() if after.get(k) != v],
                     added=sorted(set(after) - set(before)), before=before, after=after)
    save(out / 'integrity.json', integrity)
    passed = sum(r['passed'] for r in suite.results)
    print('%d/%d passed; repo changed=%d added=%d' %
          (passed, len(suite.results), len(integrity['changed']), len(integrity['added'])))
    return 0 if passed == len(suite.results) and before == after else 1


if __name__ == '__main__':
    sys.exit(main())
