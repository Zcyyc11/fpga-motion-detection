"""Acceptance tests for line3 tools, using disposable NEW evidence directories."""
import argparse
import copy
import json
from pathlib import Path
import subprocess
import sys
import run
from compare import write_csv


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out', type=Path, required=True)
    a = ap.parse_args()
    out = a.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    root = run.ROOT
    old = root / 'report/line3_20261009/run_ead15e0_01'
    results = []

    def record(name, expected, actual):
        results.append(dict(case=name, expected=expected, actual=actual, passed=expected == actual))

    def cli(name, args, expected):
        p = subprocess.run([sys.executable, '-X', 'utf8', *map(str, args)], cwd=root,
                           capture_output=True, timeout=180)
        (out / (name + '.log')).write_bytes(p.stdout + p.stderr)
        record(name, expected, p.returncode)

    fields = ['frame', 'x']
    write_csv(out/'expected.csv', fields, [{'frame':0,'x':1},{'frame':1,'x':2}])
    write_csv(out/'missing.csv', fields, [{'frame':0,'x':1}])
    cli('equal', ['sim/line3/compare.py',out/'expected.csv',out/'expected.csv','--out',out/'equal.json'], 0)
    cli('missing', ['sim/line3/compare.py',out/'expected.csv',out/'missing.csv','--out',out/'missing.json'], 2)
    cli('refuse_compare_overwrite', ['sim/line3/compare.py',out/'expected.csv',out/'missing.csv','--out',out/'equal.json'], 2)
    record('equal_evidence_preserved', [], json.loads((out/'equal.json').read_text()))
    cli('refuse_runner_overwrite', ['sim/line3/run.py','--out',out], 1)
    cli('refuse_observer_overwrite', ['sim/line3/observe.py','--outdir',out], 1)
    (out/'malformed.csv').write_text('frame,x\n0\n', encoding='utf-8')
    cli('malformed', ['sim/line3/compare.py',out/'expected.csv',out/'malformed.csv','--out',out/'malformed.json'], 2)
    truth = run.mt.load_truth(root/'data/golden/track_cross_groundtruth.csv')
    obs = json.loads((old/'clean_observed/observations.json').read_text(encoding='utf-8'))
    run.validate_observations(obs, truth)
    record('valid_observations', True, True)
    for name in ['missing_frame','duplicate_frame','out_of_range','nan','inverted','alarm_frame']:
        bad = copy.deepcopy(obs)
        if name == 'missing_frame':
            bad['frames'].pop(2)
        elif name == 'duplicate_frame':
            bad['frames'][2]['frame'] = 1
        elif name == 'out_of_range':
            bad['frames'][20]['boxes'][0]['x1'] = 1280
        elif name == 'nan':
            bad['frames'][20]['boxes'][0]['cx'] = float('nan')
        elif name == 'inverted':
            bad['frames'][20]['boxes'][0]['x0'] = 1279
        else:
            bad['alarms'][43]['events'][0]['frame'] = 42
        try:
            run.validate_observations(bad, truth)
            rejected = False
        except ValueError:
            rejected = True
        record('reject_' + name, True, rejected)
    cli('full_runner_exit', ['sim/line3/run.py','--out',out/'software_rerun'], 0)
    result = json.loads((out/'software_rerun/results.json').read_text(encoding='utf-8'))
    record('behaviour_failures', [],
           [r['case'] for r in result['cases'] if r['status']=='FAIL'])
    record('protected_files', [], result['protected_files_changed'])
    fresh = json.loads((out/'software_rerun/clean_observed/observations.json').read_text(encoding='utf-8'))
    for mutation in ('renumber', 'swap', 'recreate', 'drop'):
        bad = copy.deepcopy(fresh)
        for row in bad['frames']:
            if mutation == 'renumber' or row['frame'] >= 80:
                if mutation == 'drop':
                    row['assigned'] = {}
                    row['boxes'] = []
                else:
                    def remap(tid):
                        return str(3-int(tid)) if mutation == 'swap' else str(int(tid)+10)
                    row['assigned'] = {remap(t):v for t,v in row['assigned'].items()}
                    row['tracks'] = {remap(t):v for t,v in row['tracks'].items()}
        dest = out / ('identity_' + mutation)
        dest.mkdir()
        metrics = run.tracking_audit(bad, truth, dest)
        (dest/'metrics.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8')
        record('identity_' + mutation, mutation == 'renumber', run.clip_acceptance(metrics,'clean'))
        if mutation == 'swap':
            record('identity_swap_metric', True, metrics['id_switches'] > 0)
        if mutation == 'recreate':
            record('identity_recreate_metric', True, metrics['track_breaks'] > 0)
    record('log_line_endings', False, any(b'\r\r\n' in p.read_bytes() for p in (out/'software_rerun/logs').glob('*.txt')))
    (out/'acceptance.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    print(json.dumps(dict(tests=len(results), passed=sum(r['passed'] for r in results))))
    return 0 if all(r['passed'] for r in results) else 2


if __name__ == '__main__':
    raise SystemExit(main())
