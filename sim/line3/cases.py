"""Small independent behavioural fixtures calling the repository implementation."""
import copy
import json
from pathlib import Path
import sys
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'src/ps'))
import multi_track as mt
from compare import compare, write_csv


def run(out):
    out.mkdir()
    results = []

    def record(name, inputs, expected, actual):
        results.append(dict(case=name, input=inputs, expected=expected, actual=actual,
                            status='PASS' if expected == actual else 'FAIL'))

    for name, rects in [('empty', []), ('single', [(10, 10, 20, 20)]),
                        ('separate', [(10, 10, 20, 20), (50, 40, 60, 50)])]:
        mask = np.zeros((80, 120), np.uint8)
        for x0, y0, x1, y1 in rects:
            mask[y0:y1+1, x0:x1+1] = 1
        np.save(out / (name + '.npy'), mask)
        labels, n = mt.label_runs(mask)
        boxes = mt.boxes_from_labels(labels, n)
        actual = sorted([[b[k] for k in ('x0', 'y0', 'x1', 'y1')] for b in boxes])
        record(name, name + '.npy', sorted([list(r) for r in rects]), actual)

    def box(cx):
        return dict(x0=cx-5, x1=cx+5, y0=10, y1=20, cx=float(cx), cy=15., area=121)

    tracker = mt.Tracker(gate=30, max_miss=2)
    seen = []
    for boxes in [[box(20)], [box(25)], [], [box(35)]]:
        seen.append(sorted(tracker.update(boxes)))
    record('short_occlusion_recovery', 'centres 20,25,missing,35; max_miss=2',
           [[1], [1], [], [1]], seen)

    for name, xs, inside, exp_in, exp_out in [
        ('enter_left', [70, 60, 40, 30], 'left', 1, 0),
        ('exit_left', [30, 40, 60, 70], 'left', 0, 1),
        ('reenter_left', [70, 40, 70, 40], 'left', 2, 1),
        ('enter_right', [30, 40, 60, 70], 'right', 1, 0),
        ('exit_right', [70, 60, 40, 30], 'right', 0, 1)]:
        rule = mt.AlarmRule(line_x=50, inside=inside)
        for frame, x in enumerate(xs):
            rule.update(frame, {1: box(x)}, {1: {'vx': x-xs[max(0, frame-1)]}})
        record(name, dict(centres=xs, line_x=50, inside=inside),
               [exp_in, exp_out], [rule.n_cross_in, rule.n_cross_out])
        expected_events = [dict(frame=f, kind='cross_in' if
                               ((xs[f] < 50) == (inside == 'left')) else 'cross_out')
                           for f in range(1, len(xs)) if (xs[f] < 50) != (xs[f-1] < 50)]
        record(name + '_events', xs, expected_events,
               [{k:e[k] for k in ('frame','kind')} for e in rule.events])
        record(name + '_side', xs, 'in' if ((xs[-1] < 50) == (inside == 'left')) else 'out',
               rule.state[1]['side'])
        (out / (name + '_events.json')).write_text(json.dumps(rule.events, indent=2), encoding='utf-8')

    rule = mt.AlarmRule(zone=(0, 0, 100, 70), dwell_s=1., fps=10.)
    for f in range(10):
        rule.update(f, {1: box(30)}, {1: {'vx': 0}})
    record('dwell_non30fps', '10 observations at 10 fps; threshold 1 second',
           [1, 1.0], [rule.n_dwell, rule.events[0]['secs']])
    rule = mt.AlarmRule(zone=(0, 0, 100, 70), dwell_s=0.1, fps=30.)
    for f in range(5):
        rule.update(f, {} if f == 2 else {1: box(30)}, {1: {'vx': 0}})
    record('dwell_consecutive_gap', 'present,present,missing,present,present; threshold 3 continuous frames',
           0, rule.n_dwell)

    for name, frames in [('skipped_frame_number', [0,1,3,4]), ('consecutive', [0,1,2,3])]:
        rule = mt.AlarmRule(dwell_s=.25, fps=10.)  # ceil(2.5) = 3; None zone is full image
        emitted = []
        for f in frames:
            emitted.extend(rule.update(f, {1:box(30)}, {1:{'vx':0}}))
        record('dwell_' + name, frames, [] if name == 'skipped_frame_number' else [(2,.3)],
               [(e['frame'],e['secs']) for e in emitted])
    rule = mt.AlarmRule(zone=(0,0,50,50), dwell_s=.2, fps=10.)
    for f, x in enumerate([30,30,30,70,30,30]):
        rule.update(f, {1:box(x)}, {1:{'vx':0}})
    record('dwell_rearm_after_exit', 'two visits; one event per continuous visit', [1,5],
           [e['frame'] for e in rule.events])
    for inside in ('left','right'):
        rule = mt.AlarmRule(line_x=50, inside=inside)
        for f, (x,vx) in enumerate([(30,0),(70,-1),(30,0)]):
            rule.update(f, {1:box(x)}, {1:{'vx':vx}})
        record('inconsistent_velocity_' + inside, 'wrong direction then zero speed', [0,0,[]],
               [rule.n_cross_in,rule.n_cross_out,rule.events])
        record('observed_side_' + inside, 'position updates even if direction rejected',
               'in' if inside == 'left' else 'out', rule.state[1]['side'])

    # Exact comparator tests use copies only. Row permutation is deliberately accepted.
    fields = ['frame', 'tid', 'x0', 'kind']
    base = [dict(frame=str(i), tid='1', x0=str(10+i), kind='cross_in') for i in range(4)]
    write_csv(out / 'expected.csv', fields, base)
    mutations = {}
    mutations['reordered'] = list(reversed(base))
    mutations['missing_frame'] = base[:2] + base[3:]
    mutations['duplicate_frame'] = base + [base[2]]
    for name, field, value in [('wrong_box', 'x0', '999'), ('wrong_id', 'tid', '99'),
                               ('wrong_alarm', 'kind', 'dwell'), ('shifted_frame', 'frame', '20')]:
        rows = copy.deepcopy(base)
        rows[2][field] = value
        mutations[name] = rows
    mutations['empty_result'] = []
    for name, rows in mutations.items():
        path = out / (name + '.csv')
        write_csv(path, fields, rows)
        diffs = compare(out / 'expected.csv', path)
        (out / (name + '_diff.json')).write_text(json.dumps(diffs, indent=2), encoding='utf-8')
        detected = bool(diffs)
        record('comparator_' + name, path.name, name != 'reordered', detected)
        if detected and name not in ('empty_result',):
            record('location_' + name, path.name, True,
                   any(d['key'] == ('2',) for d in diffs))
    (out / 'cases.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
    return results
