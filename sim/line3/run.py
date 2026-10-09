"""Reproduce and audit line-three software evidence without overwriting references."""
import argparse
import csv
import hashlib
import itertools
import json
import math
import os
from pathlib import Path
import platform
import subprocess
import sys
import time
from datetime import datetime, timezone, timedelta
import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'src/ps'))
import multi_track as mt
from compare import compare, read_csv, write_csv
import cases


def dump(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT).decode('utf-8').strip()


def protected():
    # Every baseline-tracked file, including source, references and build reports.
    files = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', '-z', 'HEAD'], cwd=ROOT)
    return {name: sha(ROOT / name) for name in files.decode('utf-8').split('\0') if name}


def execute(name, args, out, commands):
    start = time.perf_counter()
    command = [sys.executable, '-X', 'utf8', *[str(a) for a in args]]
    env = dict(os.environ, PYTHONUTF8='1', PYTHONIOENCODING='utf-8')
    proc = subprocess.run(command, cwd=ROOT, capture_output=True, env=env, timeout=180)
    log = (proc.stdout + proc.stderr).decode('utf-8', errors='replace')
    (out / 'logs' / (name + '.txt')).write_text(log.replace('\r\n', '\n'), encoding='utf-8', newline='\n')
    commands.append(dict(name=name, argv=command, cwd=str(ROOT), exit_code=proc.returncode,
                         seconds=round(time.perf_counter()-start, 3), log='logs/' + name + '.txt'))
    if proc.returncode:
        raise RuntimeError(name + ' failed; see log')
    print(name + ' completed', flush=True)


def video_check(path, observations=None, sheet=None):
    cap = cv2.VideoCapture(str(path))
    if not cap.isOpened():
        raise ValueError('Unreadable video: ' + str(path))
    fps = cap.get(cv2.CAP_PROP_FPS)
    count, sizes, bad_event_frames, hashes, snapshots = 0, set(), [], [], []
    keyframes = [20, 33, 42, 68, 95, 114]
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        sizes.add((frame.shape[1], frame.shape[0]))
        hashes.append(hashlib.sha256(frame.tobytes()).hexdigest())
        if observations is not None:
            roi = frame[32:64, 10:630]
            red = (roi[:, :, 2] > 150) & (roi[:, :, 1] < 100) & (roi[:, :, 0] < 100)
            actual = int(np.count_nonzero(red)) > 30
            expected = bool(observations['alarms'][count]['events']) if count < len(observations['alarms']) else None
            if actual != expected:
                bad_event_frames.append(count)
        if count in keyframes and sheet:
            small = cv2.resize(frame, (640, 360))
            cv2.rectangle(small, (0, 332), (230, 359), (230, 230, 230), -1)
            cv2.putText(small, 'decoded frame %d' % count, (8, 353), cv2.FONT_HERSHEY_SIMPLEX,
                        .55, (0, 0, 0), 1, cv2.LINE_AA)
            snapshots.append(small)
        count += 1
    cap.release()
    if sheet and len(snapshots) == 6:
        image = np.vstack([np.hstack(snapshots[i:i+2]) for i in (0, 2, 4)])
        ok, encoded = cv2.imencode('.png', image)
        if not ok:
            raise ValueError('PNG encode failed')
        encoded.tofile(str(sheet))
    return dict(decoded_frames=count, fps=fps, sizes=sorted(sizes),
                event_display_mismatch_frames=bad_event_frames, frame_hashes=hashes)


def match_targets(pred, truth, tolerance=60.):
    # Exhaustive maximum-cardinality, then minimum-distance assignment for this two-object clip.
    best = (0, float('inf'), [])
    for n in range(min(len(pred), len(truth)) + 1):
        for pi in itertools.combinations(range(len(pred)), n):
            for gi in itertools.permutations(range(len(truth)), n):
                distances = [math.hypot(pred[p][1]['cx']-truth[g]['cx'], pred[p][1]['cy']-truth[g]['cy'])
                             for p, g in zip(pi, gi)]
                if all(d <= tolerance for d in distances):
                    if n > best[0] or (n == best[0] and sum(distances) < best[1]):
                        best = (n, sum(distances), list(zip(pi, gi, distances)))
    return best[2]


def validate_observations(obs, truth, width=1280, height=720):
    """Reject incomplete/misaligned observations before computing clip metrics."""
    expected = list(range(120))
    if sorted(truth) != expected:
        raise ValueError('Truth must cover frames 0..119 exactly')
    for name in ('frames', 'alarms'):
        if [r['frame'] for r in obs[name]] != expected:
            raise ValueError(name + ' must cover frames 0..119 once, in order')
    for row in obs['frames']:
        for b in row['boxes'] + list(row['assigned'].values()):
            values = [b[k] for k in ('x0', 'y0', 'x1', 'y1', 'cx', 'cy')]
            if not all(math.isfinite(v) for v in values):
                raise ValueError('Non-finite coordinate at frame ' + str(row['frame']))
            if not (0 <= b['x0'] <= b['cx'] <= b['x1'] < width and
                    0 <= b['y0'] <= b['cy'] <= b['y1'] < height):
                raise ValueError('Invalid box at frame ' + str(row['frame']))
        if not set(row['assigned']) <= set(row['tracks']):
            raise ValueError('Assigned ID missing from tracks')
    for row in obs['alarms']:
        if any(e['frame'] != row['frame'] for e in row['events']):
            raise ValueError('Event frame does not match observation')


def tracking_audit(obs, truth, out):
    validate_observations(obs, truth)
    frame_rows, target_rows, transitions = [], [], []
    hits = total = fp = switches = dir_ok = dir_total = 0
    tid_to_oid, oid_to_tids, previous_side = {}, {}, {}
    for data in obs['frames']:
        f = data['frame']
        gts = truth[f]
        merged = bool(gts[0]['merged'])
        pred = sorted(data['assigned'].items())
        matched = match_targets(pred, gts)
        for gt in gts:
            oid, side = gt['oid'], gt['cx'] < 640
            if oid in previous_side and previous_side[oid] != side:
                transitions.append(dict(frame=f, oid=oid, kind='cross_in' if side else 'cross_out',
                                        cx=gt['cx'], merged=merged))
            previous_side[oid] = side
        if not merged:
            total += len(gts)
            hits += len(matched)
            fp += len(pred)-len(matched)
        for pi, gi, distance in matched:
            tid, b = pred[pi]
            gt = gts[gi]
            error = max(abs(b['x0']-gt['x']), abs(b['y0']-gt['y']),
                        abs(b['x1']-(gt['x']+gt['w']-1)), abs(b['y1']-(gt['y']+gt['h']-1)))
            vx = data['tracks'][tid]['vx']
            if not merged:
                if tid in tid_to_oid and tid_to_oid[tid] != gt['oid']:
                    switches += 1
                tid_to_oid[tid] = gt['oid']
                oid_to_tids.setdefault(gt['oid'], set()).add(tid)
                if abs(vx) > 1:
                    dir_total += 1
                    dir_ok += int((vx > 0) == (gt['vx'] > 0))
            target_rows.append(dict(frame=f, tid=tid, oid=gt['oid'], merged=merged,
                                    cx_error=round(distance, 6), bbox_max_error=error,
                                    vx=vx, truth_vx=gt['vx'], **{k: b[k] for k in ('x0','y0','x1','y1')}))
        frame_rows.append(dict(frame=f, merged=merged, n_truth=len(gts), n_detected=len(data['boxes']),
                               n_assigned=len(pred), matched=len(matched),
                               tids=';'.join(tid for tid, _ in pred), live_ids=';'.join(sorted(data['tracks'])),
                               missing_truth_ids=';'.join(str(gt['oid']) for i,gt in enumerate(gts)
                                                         if i not in {g for _,g,_ in matched})))
    write_csv(out / 'frame_audit.csv', list(frame_rows[0]), frame_rows)
    write_csv(out / 'target_audit.csv', list(target_rows[0]), target_rows)
    write_csv(out / 'truth_crossings.csv', list(transitions[0]), transitions)
    return dict(frames=len(frame_rows), merged_frames=sum(r['merged'] for r in frame_rows),
                matched_visible=hits, truth_visible=total, recall=hits/max(1,total), false_boxes=fp,
                id_switches=switches, track_breaks=sum(max(0,len(v)-1) for v in oid_to_tids.values()),
                direction_correct=dir_ok, direction_total=dir_total, truth_crossings=transitions,
                actual_events=[event for row in obs['alarms'] for event in row['events']],
                final_alarm_counts={k:obs['alarms'][-1][k] for k in ('cross_in','cross_out','dwell')},
                maximum_visible_bbox_error=max(r['bbox_max_error'] for r in target_rows if not r['merged']))


def cdnet_audit(out):
    tables = []
    for path in sorted((ROOT / 'src/ps').glob('cdnet_official_results*.csv')):
        fields, rows = read_csv(path)
        seen, dup, invalid, groups = set(), [], [], {}
        for line, r in enumerate(rows, 2):
            key = (r['seq'], r['variant'])
            if key in seen:
                dup.append(line)
            seen.add(key)
            score = float(r['official_f1'])
            if not math.isfinite(score) or not 0 <= score <= 1:
                invalid.append(line)
            groups.setdefault(r['variant'], {}).setdefault(r['seq'].split('/')[0], []).append(score)
        for variant, cats in groups.items():
            means = {cat:sum(values)/len(values) for cat,values in cats.items()}
            tables.append(dict(file=path.name, variant=variant, sequences=sum(map(len,cats.values())),
                               categories=len(cats), category_macro_f1=sum(means.values())/len(means),
                               category_means=means, duplicate_rows=dup, invalid_rows=invalid,
                               sha256=sha(path), raw_counts_available=False))
    dump(out / 'cdnet_audit.json', tables)
    return tables


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True, help='Must not exist; never overwrites')
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    (out/'logs').mkdir()
    before = protected()
    manifest = dict(date=datetime.now(timezone(timedelta(hours=8))).isoformat(), cwd=str(ROOT),
                    head=git('rev-parse','HEAD'), branch=git('branch','--show-current'),
                    remote=git('remote','get-url','origin'), python=sys.executable,
                    python_version=sys.version, platform=platform.platform(),
                    numpy=np.__version__, opencv=cv2.__version__,
                    requirements=(ROOT/'src/ps/requirements.txt').read_text(encoding='utf-8'),
                    protected_sha256_before=before,
                    runner_sha256={p.name:sha(p) for p in Path(__file__).parent.glob('*.py')})
    dump(out/'manifest.json', manifest)
    commands, result = [], {}
    try:
        for script in ('rtl_golden','multi_track'):
            execute('help_'+script, ['src/ps/'+script+'.py','--help'], out, commands)
        for mode in ('framediff','bg'):
            execute('model_'+mode, ['src/ps/rtl_golden.py','--mode',mode,'--out-csv',out/(mode+'.csv')],out,commands)
        # Archive comparison is explicitly scoped to the archive's documented 0..10 rows.
        fields, rows = read_csv(out/'framediff.csv')
        write_csv(out/'archive_expected_0_10.csv', fields, [r for r in rows if int(r['frame']) <= 10])
        result['archive_0_10_diff'] = compare(out/'archive_expected_0_10.csv',ROOT/'sim/wave/bbox_rtl.csv')
        result['archive_full_model_diff'] = compare(out/'framediff.csv',ROOT/'sim/wave/bbox_rtl.csv')
        truth = mt.load_truth(ROOT/'data/golden/track_cross_groundtruth.csv')
        for mode in ('clean','algo'):
            common = ['--source',mode,'--alarm','--line-x','640']
            if mode == 'algo':
                common += ['--init-frames','12']
            execute(mode, ['src/ps/multi_track.py',*common,'--outdir',out/mode],out,commands)
            execute(mode+'_observed', ['sim/line3/observe.py',*common,'--outdir',out/(mode+'_observed')],out,commands)
            suffix = '' if mode == 'clean' else '_algo'
            obs = json.loads((out/(mode+'_observed')/'observations.json').read_text(encoding='utf-8'))
            mr = tracking_audit(obs,truth,out/mode)
            mr['observer_csv_diffs'] = compare(out/mode/('multi_track_results'+suffix+'.csv'),
                                               out/(mode+'_observed')/('multi_track_results'+suffix+'.csv'))
            mr['observer_alarm_diffs'] = compare(out/mode/('alarm_events'+suffix+'.csv'),
                                                 out/(mode+'_observed')/('alarm_events'+suffix+'.csv'),('frame','tid','kind'))
            video = video_check(out/mode/('track_result'+suffix+'.mp4'), obs, out/mode/'keyframes.png')
            observed_video = video_check(out/(mode+'_observed')/('track_result'+suffix+'.mp4'))
            mr['observer_video_equal'] = video['frame_hashes'] == observed_video['frame_hashes']
            mr['video'] = {k:v for k,v in video.items() if k != 'frame_hashes'}
            if mode == 'algo':
                mr['reference_frame_diffs'] = compare(ROOT/'src/ps/multi_track_results_algo.csv',out/mode/'multi_track_results_algo.csv')
                mr['reference_alarm_diffs'] = compare(ROOT/'src/ps/alarm_events_algo.csv',out/mode/'alarm_events_algo.csv',('frame','tid','kind'))
            result[mode] = mr
        result['cases'] = cases.run(out/'cases')
        result['cdnet_archive_audit'] = cdnet_audit(out)
        result['completed'] = True
    except Exception as exc:
        result['execution_error'] = repr(exc)
        raise
    finally:
        after = {name:sha(ROOT/name) for name in before}
        result['protected_files_changed'] = [name for name in before if before[name] != after[name]]
        dump(out/'commands.json',commands)
        dump(out/'results.json',result)
    # Behaviour failures are intentionally nonzero; they are not silently accepted as expected failures.
    failed = [r['case'] for r in result['cases'] if r['status']=='FAIL']
    checks = [not result['protected_files_changed'], not result['archive_0_10_diff']]
    for mode in ('clean','algo'):
        r = result[mode]
        checks.extend([not r['observer_csv_diffs'],not r['observer_alarm_diffs'],r['observer_video_equal'],
                       r['video']['decoded_frames']==120, r['video']['sizes']==[(1280,720)],
                       not r['video']['event_display_mismatch_frames']])
    checks.extend([not result['algo']['reference_frame_diffs'], not result['algo']['reference_alarm_diffs']])
    print(json.dumps(dict(behaviour_failures=failed, infrastructure_pass=all(checks)), ensure_ascii=False))
    return 2 if failed or not all(checks) else 0


if __name__ == '__main__':
    raise SystemExit(main())
