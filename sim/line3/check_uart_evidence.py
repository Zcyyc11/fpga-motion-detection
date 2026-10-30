"""Regression for independently found evidence-link and cleanup failures.

All fixtures are simulated. Never overwrite a previous result directory.
"""
import argparse
import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys

import uart_receiver as receiver
import verify_uart_capture as verifier


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    out = parser.parse_args().out
    out.mkdir(parents=True, exist_ok=False)
    checks = []

    def check(name, fn):
        try:
            fn()
            checks.append(dict(name=name, passed=True))
        except Exception as exc:
            checks.append(dict(name=name, passed=False, error=repr(exc)))

    def require(condition):
        if not condition:
            raise AssertionError("unexpected result")

    def table(path, rows):
        path.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")

    raw = bytes.fromhex("5a341201a1 a53412070a0014001e0028000056 c334120701140025")
    expected = [dict(frame_id=4660, input_frame_ref="SIMULATED independent literal table",
                     targets=[dict(id=7, x1=10, y1=20, x2=30, y2=40, flags=0)],
                     events=[dict(id=7, type=1, center_x=20)])]
    clean = out / "clean"
    receiver.receive([raw], clean, "simulated", save_images=0)
    wanted = out / "expected.jsonl"
    table(wanted, expected)
    check("independent literal reference matches", lambda: require(verifier.verify(clean, wanted)["exit_code"] == 0))

    for kind, fields in (("targets", ["id", "x1", "y1", "x2", "y2", "flags"]),
                         ("events", ["id", "type", "center_x"])):
        for field in fields:
            changed = copy.deepcopy(expected)
            changed[0][kind][0][field] += 1
            ref = out / f"changed_{kind}_{field}.jsonl"
            table(ref, changed)
            check(f"reject changed {kind} {field}", lambda ref=ref: require(verifier.verify(clean, ref)["exit_code"] == 1))
    for name, rows in [("empty", []), ("extra", expected * 2),
                       ("missing_event", [dict(expected[0], events=[])]),
                       ("duplicate_event", [dict(expected[0], events=expected[0]["events"] * 2)]),
                       ("wrong_frame", [dict(expected[0], frame_id=4661)])]:
        ref = out / f"{name}.jsonl"
        table(ref, rows)
        check(f"reject {name}", lambda ref=ref: require(verifier.verify(clean, ref)["exit_code"] == 1))

    def mixed_table():
        mixed = out / "mixed"
        shutil.copytree(clean, mixed)
        records = verifier.load_jsonl(mixed / "frames.jsonl")
        records[0]["targets"][0]["x1"] = 11
        table(mixed / "frames.jsonl", records)
        changed = copy.deepcopy(expected)
        changed[0]["targets"][0]["x1"] = 11
        ref = out / "mixed_expected.jsonl"
        table(ref, changed)
        result = verifier.verify(mixed, ref)
        (out / "mixed_result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
        require(result["exit_code"] == 1 and any("differs from raw" in e for e in result["errors"]))
    check("reject matching wrong frame table and reference against raw", mixed_table)

    def changed_raw():
        capture = out / "changed_raw"
        shutil.copytree(clean, capture)
        (capture / "raw_stream.bin").write_bytes(raw + b"\0")
        require(verifier.verify(capture, wanted)["exit_code"] == 1)
    check("reject changed raw stream", changed_raw)

    def invalid_reference():
        bad = copy.deepcopy(expected)
        del bad[0]["input_frame_ref"]
        ref = out / "no_mapping.jsonl"
        table(ref, bad)
        result = subprocess.run([sys.executable, verifier.__file__, "--capture", str(clean), "--expected", str(ref),
                                 "--out", str(out / "no_mapping_result.json")], capture_output=True, text=True)
        require(result.returncode == 1 and "input_frame_ref" in result.stdout)
    check("CLI rejects absent frame mapping", invalid_reference)

    def close_failure():
        class BrokenClose:
            def __iter__(self):
                yield raw
            def close(self):
                raise OSError("SIMULATED close failure")
        stats = receiver.receive(BrokenClose(), out / "close_failure", "simulated", save_images=0)
        require(stats["exit_code"] == 1 and stats["error_counts"].get("transport_close_error") == 1)
        require((out / "close_failure/summary.json").exists())
        require((out / "close_failure/raw_stream.bin").read_bytes() == raw)
    check("cleanup error still saves summary and raw", close_failure)

    result = dict(board_test=False, input="SIMULATED", checks=checks,
                  passed=sum(c["passed"] for c in checks), total=len(checks))
    result["exit_code"] = int(result["passed"] != result["total"])
    (out / "checks.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    return result["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
