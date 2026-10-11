"""Observe existing Tracker/AlarmRule calls without changing their algorithms."""
import copy
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'src/ps'))
import multi_track as mt


def main():
    if '--outdir' not in sys.argv:
        raise SystemExit('Explicit new --outdir is required')
    dest = Path(sys.argv[sys.argv.index('--outdir') + 1]).resolve()
    if dest.exists():
        raise SystemExit('Refusing existing output directory: ' + str(dest))
    frames, alarm_frames = [], []
    original_tracker, original_rule = mt.Tracker, mt.AlarmRule

    class ObservedTracker(original_tracker):
        def update(self, boxes):
            assigned = super().update(boxes)
            frames.append(dict(frame=len(frames), boxes=copy.deepcopy(boxes),
                               assigned=copy.deepcopy(assigned), tracks=copy.deepcopy(self.tracks)))
            return assigned

    class ObservedAlarm(original_rule):
        def update(self, frame, assigned, tracks):
            events = super().update(frame, assigned, tracks)
            alarm_frames.append(dict(frame=frame, events=copy.deepcopy(events),
                                     cross_in=self.n_cross_in, cross_out=self.n_cross_out,
                                     dwell=self.n_dwell))
            return events

    mt.Tracker, mt.AlarmRule = ObservedTracker, ObservedAlarm
    try:
        rc = mt.main()
        dest.mkdir(parents=True, exist_ok=True)
        def scalar(value):
            if hasattr(value, 'item'):
                return value.item()
            raise TypeError(type(value).__name__)
        (dest / 'observations.json').write_text(json.dumps(
            dict(frames=frames, alarms=alarm_frames), ensure_ascii=False, indent=2,
            default=scalar), encoding='utf-8')
        return rc
    finally:
        mt.Tracker, mt.AlarmRule = original_tracker, original_rule


if __name__ == '__main__':
    raise SystemExit(main())
