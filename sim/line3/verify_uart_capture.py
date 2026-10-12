"""Compare a decoded capture against an independently supplied exact JSONL table.

This checks reported values, not whether packets or reference came from hardware.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys


def load_jsonl(path):
    with Path(path).open(encoding="utf-8-sig") as stream:
        return [json.loads(line) for line in stream if line.strip()]


def canonical(record, reference=False):
    fid = record["frame_id"]
    if type(fid) is not int or not 0 <= fid <= 65535:
        raise ValueError("invalid frame_id")
    targets = record["targets"]
    events = record["events"]
    if not isinstance(targets, list) or not isinstance(events, list) or len(targets) > 16:
        raise ValueError("targets/events must be arrays; targets maximum 16")
    boxes = []
    for t in targets:
        fields = [t[k] for k in ("id", "x1", "y1", "x2", "y2", "flags")]
        if any(type(v) is not int for v in fields):
            raise ValueError("target fields must be integers")
        tid, x1, y1, x2, y2, flags = fields
        if not (0 <= tid <= 255 and 0 <= x1 <= x2 < 640 and 0 <= y1 <= y2 < 360 and 0 <= flags <= 255):
            raise ValueError("invalid target")
        boxes.append(tuple(fields))
    if len({b[0] for b in boxes}) != len(boxes):
        raise ValueError("duplicate target id")
    alarms = []
    for e in events:
        fields = [e[k] for k in ("id", "type", "center_x")]
        if any(type(v) is not int for v in fields):
            raise ValueError("event fields must be integers")
        if not (0 <= fields[0] <= 255 and fields[1] in (1, 2) and 0 <= fields[2] < 640):
            raise ValueError("invalid event")
        alarms.append(tuple(fields))
    if reference:
        # A mapping string is necessary evidence context, not proof of correspondence.
        if not isinstance(record.get("input_frame_ref"), str) or not record["input_frame_ref"].strip():
            raise ValueError("reference requires input_frame_ref (video/image and frame mapping)")
    return {"frame_id": fid, "targets": sorted(boxes), "events": sorted(alarms)}


def verify(capture, expected):
    capture, expected = Path(capture), Path(expected)
    summary = json.loads((capture / "summary.json").read_text(encoding="utf-8"))
    errors = []
    if summary.get("exit_code") != 0 or summary.get("errors") != 0:
        errors.append("capture did not finish cleanly")
    digest = hashlib.file_digest((capture / "raw_stream.bin").open("rb"), "sha256").hexdigest()
    if digest != summary.get("raw_sha256"):
        errors.append("raw stream hash mismatch")
    actual_records = load_jsonl(capture / "frames.jsonl")
    references = load_jsonl(expected)
    if not actual_records or not references:
        errors.append("empty frame/reference table")
    if len(actual_records) != len(references) or len(actual_records) != summary.get("frames"):
        errors.append("frame count mismatch")
    for index, (actual, wanted) in enumerate(zip(actual_records, references), 1):
        if actual.get("sequence") != index or actual.get("valid") is not True:
            errors.append(f"frame {index}: invalid sequence or rejected capture frame")
        if canonical(actual) != canonical(wanted, reference=True):
            errors.append(f"frame {index}: frame id / targets / events differ")
    return {"exit_code": int(bool(errors)), "errors": errors, "compared_frames": min(len(actual_records), len(references)),
            "actual_frames": len(actual_records), "reference_frames": len(references),
            "raw_sha256": digest, "reference_sha256": hashlib.sha256(expected.read_bytes()).hexdigest(),
            "board_test": False, "scope": "exact table comparison; hardware origin and video alignment require independent evidence"}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--capture", type=Path, required=True)
    ap.add_argument("--expected", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True, help="new result JSON file")
    args = ap.parse_args()
    try:
        result = verify(args.capture, args.expected)
    except Exception as exc:
        result = {"exit_code": 1, "board_test": False, "errors": [f"{type(exc).__name__}: {exc}"]}
    with args.out.open("x", encoding="utf-8") as output:
        json.dump(result, output, ensure_ascii=False, indent=2)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return result["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
