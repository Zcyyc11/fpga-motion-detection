"""Run frozen cdnet_official.main; log metrics without changing detector parameters.

Only storage changes: lazy, cached frame sequences bound RAM usage. A preflight
compares every loaded array and all six metric results with the original loader
for 100 warmup + 30 scored frames in each real sequence. No source edits.
"""
import argparse
import contextlib
import csv
from functools import lru_cache
import gzip
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys
import time
import traceback


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", type=Path, required=True)
    ap.add_argument("--data-root", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=False)
    sys.path.insert(0, str(a.source / "src/ps"))
    import cdnet_official as official
    import algo_lab as lab
    import cdnet_io as cio
    import cv2
    import numpy as np
    from prepare_dataset import SEQUENCES

    def git(*args):
        return subprocess.check_output(["git", "-C", str(a.source), *args], text=True).strip()

    files = {str(p.relative_to(a.source)): sha(p) for p in (a.source / "src/ps").glob("*.py")}
    references = {p.name: sha(p) for p in (a.source / "src/ps").glob("*.csv")}
    meta = {"command_argv": sys.argv, "source": str(a.source), "source_sha": git("rev-parse", "HEAD"),
            "git_status_before": git("status", "--porcelain"), "source_hashes": files,
            "reference_hashes_before": references, "python": sys.version, "platform": platform.platform(),
            "numpy": np.__version__, "opencv": cv2.__version__, "opencv_threads": cv2.getNumThreads(),
            "warmup": lab.DEFAULT_WARMUP, "frames": 0, "set": "r12", "variants": lab.SETS["r12"],
            "loader": "lazy per-frame, LRU 8; original algorithms unchanged", "data_root": str(a.data_root),
            "dataset_verification_sha256": sha(a.data_root.parent / "verification.json"),
            "wrapper_sha256": sha(__file__), "sequence_plans": {}, "completed": [], "loader_equivalence": []}
    if meta["git_status_before"]:
        raise RuntimeError("Frozen source must be clean")

    def save():
        (a.out / "run.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")

    class Frames:
        def __init__(self, seq, first, count, kind):
            self.seq, self.first, self.count, self.kind = seq, first, count, kind
            self.get = lru_cache(maxsize=8)(self.read)

        def __len__(self):
            return self.count

        def __getitem__(self, i):
            if not isinstance(i, int) or not 0 <= i < self.count:
                raise IndexError(i)
            return self.get(i)

        def read(self, i):
            frame = self.first + i
            if self.kind == "label":
                return cio.read_gray(self.seq / "groundtruth" / f"gt{frame:06d}.png")
            img = cio.imread(self.seq / "input" / f"in{frame:06d}.jpg", cv2.IMREAD_COLOR)
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            return lab.compress2x2(gray) if self.kind == "c2" else gray

    original_load = lab.load_cached
    original_metrics = lab.frame_metrics
    current = {}

    def lazy_load(seqdir, warmup=100, frames=0):
        seq = Path(seqdir)
        plan = cio.frame_plan(seq, warmup, frames)
        return (plan["roi"], plan["nwarm"],
                *[Frames(seq, plan["first"], plan["count"], k) for k in ("gray", "c2", "label")])

    started = time.time()
    code = 1
    save()
    with open(a.out / "stdout.log", "x", encoding="utf-8", buffering=1) as stdout, \
         open(a.out / "stderr.log", "x", encoding="utf-8", buffering=1) as stderr, \
         gzip.open(a.out / "per_frame.csv.gz", "wt", encoding="utf-8", newline="") as frame_file:
        writer = csv.writer(frame_file)
        writer.writerow(["sequence", "variant", "frame", "precision", "recall", "f1", "tp", "fp", "fn", "truth_pixels"])
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            try:
                allseq = lab.discover(str(a.data_root))
                if set(allseq) != set(SEQUENCES):
                    raise RuntimeError("Sequence set does not match 12-sequence contract")
                # Verify storage adaptation before accepting any full-run metrics.
                for name in sorted(allseq):
                    eager = original_load(allseq[name], frames=30)
                    lazy = lazy_load(allseq[name], frames=30)
                    assert eager[:2] == lazy[:2]
                    for arrays, view in zip(eager[2:], lazy[2:]):
                        assert len(arrays) == len(view)
                        for i, array in enumerate(arrays):
                            np.testing.assert_array_equal(array, view[i])
                    for label, cfg in lab.SETS["r12"]:
                        assert original_metrics(eager[3], eager[4], eager[1], cfg) == original_metrics(lazy[3], lazy[4], lazy[1], cfg)
                    meta["loader_equivalence"].append({"sequence": name, "loaded_frames": len(eager[3]),
                                                       "scored_frames": 30, "variants": 6, "arrays_and_metrics_exact": True})
                    print("Loader equivalence PASS:", name, flush=True)
                    save()
                del eager, lazy, arrays, view, array

                def observed_load(seqdir, warmup=100, frames=0):
                    name = Path(seqdir).relative_to(a.data_root).as_posix()
                    plan = cio.frame_plan(seqdir, warmup, frames)
                    current.update(name=name, plan=plan)
                    meta["sequence_plans"][name] = plan
                    save()
                    return lazy_load(seqdir, warmup, frames)

                def observed_metrics(c2, labels, nw, cfg, collect=None):
                    rows = original_metrics(c2, labels, nw, cfg, collect)
                    label = next(label for label, candidate in lab.SETS["r12"] if candidate is cfg)
                    plan = current["plan"]
                    start, end = plan["score"]
                    assert len(rows) == end - start + 1
                    for frame, row in zip(range(start, end + 1), rows):
                        writer.writerow([current["name"], label, frame, *row])
                    frame_file.flush()
                    meta["completed"].append({"sequence": current["name"], "variant": label,
                                              "frames": len(rows), "elapsed_seconds": time.time() - started})
                    save()
                    return rows

                lab.load_cached = observed_load
                lab.frame_metrics = observed_metrics
                # main resolves output relative to __file__; imports already finished.
                official.__file__ = str(a.out / "cdnet_official.py")
                sys.argv = [str(a.source / "src/ps/cdnet_official.py"), "--data-root", str(a.data_root), "--set", "r12", "--seq", "all"]
                meta["official_argv"] = sys.argv
                code = official.main()
            except Exception:
                traceback.print_exc()
                code = 1
            finally:
                meta.update(exit_code=code, elapsed_seconds=time.time() - started,
                            git_status_after=git("status", "--porcelain"),
                            reference_hashes_after={p.name: sha(p) for p in (a.source / "src/ps").glob("*.csv")})
                meta["source_hashes_after"] = {str(p.relative_to(a.source)): sha(p) for p in (a.source / "src/ps").glob("*.py")}
                save()
    print(json.dumps({"exit_code": code, "out": str(a.out), "seconds": meta["elapsed_seconds"]}))
    return code


if __name__ == "__main__":
    sys.exit(main())
