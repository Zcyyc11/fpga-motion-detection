"""Independently aggregate per-frame evidence and compare every reference CSV key."""
import argparse
from collections import defaultdict
import csv
import gzip
import hashlib
import json
import math
from pathlib import Path
import statistics
import sys

from prepare_dataset import SEQUENCES


def read_csv(path):
    with open(path, encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    result = {(r["seq"], r["variant"]): r for r in rows}
    if len(result) != len(rows):
        raise ValueError("duplicate CSV key")
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", type=Path, required=True)
    ap.add_argument("--reference", type=Path, required=True)
    a = ap.parse_args()
    out = a.run / "comparison"
    out.mkdir(exist_ok=False)
    meta = json.loads((a.run / "run.json").read_text(encoding="utf-8"))
    ref = read_csv(a.reference)
    actual = read_csv(a.run / "cdnet_official_results_r12.csv")
    variants = [v[0] for v in meta["variants"]]
    expected_keys = {(s, v) for s in SEQUENCES for v in variants}
    if set(ref) != expected_keys or set(actual) != expected_keys:
        raise ValueError("CSV key set differs from exact 12 x 6 matrix")
    counts = defaultdict(lambda: {"frames": set(), "tp": 0, "fp": 0, "fn": 0, "f1": []})
    with gzip.open(a.run / "per_frame.csv.gz", "rt", encoding="utf-8", newline="") as f:
        for r in csv.DictReader(f):
            key = (r["sequence"], r["variant"])
            if key not in expected_keys:
                raise ValueError("extra per-frame key")
            d = counts[key]
            frame = int(r["frame"])
            if frame in d["frames"]:
                raise ValueError("duplicate frame")
            d["frames"].add(frame)
            tp, fp, fn = (int(r[k]) for k in ("tp", "fp", "fn"))
            if min(tp, fp, fn) < 0 or tp + fn != int(r["truth_pixels"]):
                raise ValueError("inconsistent confusion counts")
            p = tp / (tp + fp) if tp + fp else 0.0
            rec = tp / (tp + fn) if tp + fn else 0.0
            f1 = 2 * tp / (2 * tp + fp + fn) if 2 * tp + fp + fn else 0.0
            if not all(math.isclose(float(r[k]), v, abs_tol=1e-12) for k, v in (("precision", p), ("recall", rec), ("f1", f1))):
                raise ValueError("per-frame rates disagree with counts")
            for k, value in (("tp", tp), ("fp", fp), ("fn", fn)):
                d[k] += value
            d["f1"].append(f1)
    if set(counts) != expected_keys:
        raise ValueError("missing per-frame key")
    differences = []
    cats = defaultdict(lambda: defaultdict(list))
    ref_cats = defaultdict(lambda: defaultdict(list))
    with open(out / "all_72_rows.csv", "x", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["sequence", "variant", "frames", "tp", "fp", "fn", "official_f1_full", "actual_4dp", "reference_4dp", "delta_4dp", "perframe_matches"])
        for key in sorted(expected_keys):
            seq, variant = key
            d = counts[key]
            _, first, last = SEQUENCES[seq]
            if d["frames"] != set(range(first, last + 1)):
                raise ValueError("frame coverage mismatch: " + seq)
            tp, fp, fn = (d[k] for k in ("tp", "fp", "fn"))
            f1 = 2 * tp / (2 * tp + fp + fn) if 2 * tp + fp + fn else 0.0
            pf = statistics.mean(d["f1"])
            if format(f1, ".4f") != actual[key]["official_f1"] or format(pf, ".4f") != actual[key]["perframe_f1"]:
                raise ValueError("CSV does not equal independently aggregated frames")
            delta = float(actual[key]["official_f1"]) - float(ref[key]["official_f1"])
            pf_match = actual[key]["perframe_f1"] == ref[key]["perframe_f1"]
            if delta or not pf_match:
                differences.append({"seq": seq, "variant": variant, "official_delta": delta, "perframe_matches": pf_match})
            cats[variant][seq.split("/")[0]].append(f1)
            ref_cats[variant][seq.split("/")[0]].append(float(ref[key]["official_f1"]))
            w.writerow([seq, variant, len(d["frames"]), tp, fp, fn, f1, actual[key]["official_f1"], ref[key]["official_f1"], delta, pf_match])
    totals = {}
    with open(out / "category_summary.csv", "x", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["variant", "category", "sequences", "actual_full_precision_mean", "reference_rounded_mean"])
        for variant in variants:
            for cat in sorted(cats[variant]):
                w.writerow([variant, cat, len(cats[variant][cat]), statistics.mean(cats[variant][cat]), statistics.mean(ref_cats[variant][cat])])
            totals[variant] = {"actual_full_precision": statistics.mean(map(statistics.mean, cats[variant].values())),
                               "reference_from_4dp": statistics.mean(map(statistics.mean, ref_cats[variant].values()))}
    protected = (meta["source_hashes"] == meta["source_hashes_after"] and
                 meta["reference_hashes_before"] == meta["reference_hashes_after"] and not meta["git_status_after"])
    summary = {"status": "PASS" if not differences and protected and meta["exit_code"] == 0 else "DIFFERENT_OR_FAILED",
               "rows": len(expected_keys), "sequences": 12, "categories": 7, "variants": 6,
               "scored_frames_per_variant": sum(x[2] - x[1] + 1 for x in SEQUENCES.values()),
               "per_frame_rows": sum(len(d["frames"]) for d in counts.values()),
               "csv_matches_reference_all_4dp_fields": not differences, "differences": differences,
               "source_and_references_unchanged": protected, "totals": totals,
               "reference_sha256": hashlib.sha256(a.reference.read_bytes()).hexdigest()}
    (out / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    return 0 if summary["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
