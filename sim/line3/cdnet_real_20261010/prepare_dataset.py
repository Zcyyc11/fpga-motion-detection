"""Extract only the team's 12 sequences, never overwrite, verify saved bytes and decode."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import csv
import hashlib
import json
from pathlib import Path, PurePosixPath
import time
import zipfile
import zlib

import cv2
import numpy as np

SEQUENCES = {
    "badWeather/snowFall": (6500, 800, 6500),
    "baseline/highway": (1700, 470, 1700),
    "baseline/office": (2050, 570, 2050),
    "baseline/pedestrians": (1099, 300, 1099),
    "cameraJitter/badminton": (1150, 800, 1150),
    "cameraJitter/traffic": (1570, 900, 1570),
    "dynamicBackground/canoe": (1189, 800, 1189),
    "dynamicBackground/fountain02": (1499, 500, 1499),
    "intermittentObjectMotion/streetLight": (3200, 175, 3200),
    "nightVideos/busyBoulvard": (2760, 730, 2760),
    "shadow/busStation": (1250, 300, 1250),
    "shadow/peopleInShade": (1199, 250, 1199),
}


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(8 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zip", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--resume-verify", action="store_true", help="Verify existing bytes without overwriting them")
    ap.add_argument("--workers", type=int, default=8)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=a.resume_verify)
    root = a.out.resolve()
    started = time.time()
    result = {"archive": str(a.zip.resolve()), "archive_bytes": a.zip.stat().st_size,
              "archive_sha256": sha(a.zip), "destination": str(root), "sequences": {}}
    print("Archive SHA256:", result["archive_sha256"], flush=True)
    manifest = root / (f"file_manifest_resumed_{time.time_ns()}.csv" if a.resume_verify else "file_manifest.csv")
    with zipfile.ZipFile(a.zip) as z, open(manifest, "x", newline="", encoding="utf-8") as f, ThreadPoolExecutor(max_workers=a.workers) as pool:
        writer = csv.writer(f)
        writer.writerow(["member", "bytes", "crc32", "sha256", "decoded_shape"])
        for seq, (count, r0, r1) in SEQUENCES.items():
            prefix = "dataset/" + seq + "/"
            names = [f"input/in{i:06d}.jpg" for i in range(1, count + 1)]
            names += [f"groundtruth/gt{i:06d}.png" for i in range(1, count + 1)]
            names += ["temporalROI.txt", "ROI.bmp"]
            shape = None
            roi_shape = None
            total = 0
            def extract_one(name):
                member = prefix + name
                info = z.getinfo(member)
                parts = PurePosixPath(member).parts
                if ".." in parts or PurePosixPath(member).is_absolute() or "\\" in member or ":" in member:
                    raise ValueError("Unsafe ZIP member: " + member)
                # Create only the validated relative parent first, then resolve it.
                # Avoid resolving a path while a sibling thread creates its parent.
                candidate = root.joinpath(*parts)
                candidate.parent.mkdir(parents=True, exist_ok=True)
                target = candidate.resolve()
                if root not in target.parents:
                    raise ValueError(f"ZIP destination escaped root: {member!r} => {target!s}; root={root!s}")
                raw = z.read(info)  # zipfile validates CRC
                target.parent.mkdir(parents=True, exist_ok=True)
                if not (a.resume_verify and target.exists()):
                    with open(target, "xb") as dest:
                        dest.write(raw)
                saved = target.read_bytes()
                digest = hashlib.sha256(saved).hexdigest()
                if saved != raw or len(saved) != info.file_size or zlib.crc32(saved) != info.CRC:
                    raise ValueError("Saved bytes mismatch: " + member)
                decoded = ""
                if target.suffix in (".jpg", ".png", ".bmp"):
                    img = cv2.imdecode(np.frombuffer(saved, np.uint8), cv2.IMREAD_GRAYSCALE)
                    if img is None:
                        raise ValueError("Cannot decode: " + member)
                    decoded = "x".join(map(str, img.shape))
                else:
                    if tuple(map(int, saved.decode("utf-8").split())) != (r0, r1):
                        raise ValueError("Temporal ROI mismatch: " + member)
                return [member, len(saved), f"{info.CRC:08x}", digest, decoded]
            for row in pool.map(extract_one, names):
                if row[0].endswith("/ROI.bmp"):
                    roi_shape = row[4]
                elif row[4]:
                    if shape is None:
                        shape = row[4]
                    if row[4] != shape:
                        raise ValueError("Shape mismatch: " + row[0])
                writer.writerow(row)
                total += row[1]
            result["sequences"][seq] = {"input": count, "groundtruth": count,
                "temporal_roi": [r0, r1], "shape": shape, "roi_shape": roi_shape,
                "roi_shape_matches_frames": roi_shape == shape, "files": len(names), "bytes": total,
                "all_saved_bytes_verified": True, "all_images_decoded": True}
            f.flush()
            print(f"{len(result['sequences'])}/12 verified: {seq}, {len(names)} files", flush=True)
    result.update(status="PASS", elapsed_seconds=time.time() - started,
                  manifest=str(manifest), manifest_sha256=sha(manifest), workers=a.workers,
                  resume_verify=a.resume_verify)
    (root / "verification.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps({"status": "PASS", "seconds": result["elapsed_seconds"]}), flush=True)


if __name__ == "__main__":
    main()
