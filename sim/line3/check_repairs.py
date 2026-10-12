"""Alarm and full-frame comparison regressions. All artifacts are retained."""
import argparse
import csv
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

import cases
import rtl_golden as golden

ROOT = Path(__file__).resolve().parents[2]
BASELINE = '08b944790b629546a584ade37e77818535f72c57'


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out', type=Path, required=True)
    a = ap.parse_args()
    out = a.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    results = []

    def record(name, expected, actual):
        results.append(dict(case=name, expected=expected, actual=actual, passed=expected == actual))

    # Re-run the SAME new behavioural tests on an immutable pre-repair module.
    raw = subprocess.check_output(['git','show',BASELINE+':src/ps/multi_track.py'], cwd=ROOT)
    old_path = out / 'multi_track_before.py'
    old_path.write_bytes(raw)
    spec = importlib.util.spec_from_file_location('alarm_before', old_path)
    old = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(old)
    current = cases.mt
    try:
        cases.mt = old
        before = cases.run(out/'before')
    finally:
        cases.mt = current
    failed_before = [r['case'] for r in before if r['status'] == 'FAIL']
    record('baseline_five_failures_reproduced', True,
           {'exit_left','reenter_left','exit_right','dwell_non30fps','dwell_consecutive_gap'} <= set(failed_before))
    after = cases.run(out/'after')
    record('all_behaviour_cases_after', [], [r['case'] for r in after if r['status'] == 'FAIL'])

    _, rows = golden.run()
    fields = ['frame','b_valid','b_x1','b_y1','b_x2','b_y2','b_cnt']
    samples = dict(valid=rows, reordered=rows[::-1], missing_last=rows[:-1], empty=[],
                   duplicate=rows+[rows[3]], extra=rows+[(12,*rows[-1][1:])],
                   corrupt_last=rows[:-1]+[(11,0,65535,65535,0,0,0)])
    for name, sample in samples.items():
        path = out / (name+'.csv')
        with path.open('w', encoding='utf-8', newline='') as stream:
            writer = csv.writer(stream)
            writer.writerow(fields)
            writer.writerows(sample)
        p = subprocess.run([sys.executable,'-X','utf8',str(ROOT/'src/ps/rtl_golden.py'),
                            '--compare',str(path)],capture_output=True)
        (out/(name+'.txt')).write_bytes(p.stdout+p.stderr)
        record('compare_'+name, 0 if name in ('valid','reordered') else 2, p.returncode)
    (out/'results.json').write_text(json.dumps(dict(baseline=BASELINE, failed_before=failed_before,
                                                  results=results),indent=2),encoding='utf-8')
    print(json.dumps(dict(tests=len(results), passed=sum(r['passed'] for r in results))))
    return 0 if all(r['passed'] for r in results) else 2


if __name__ == '__main__':
    raise SystemExit(main())
