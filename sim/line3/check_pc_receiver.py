"""Protocol rejection matrix + real loopback TCP process test. Retains all evidence."""
import argparse
import copy
import json
from pathlib import Path
import subprocess
import sys

import cv2
import numpy as np

import pc_receiver as rx
from pc_receiver_simulate import frame


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, required=True)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=False)
    results = []

    def check(name, test):
        try:
            test()
            results.append({"name": name, "pass": True})
        except Exception as e:
            results.append({"name": name, "pass": False, "error": repr(e)})

    def must_reject(raw):
        try:
            rx.parse_frame(raw)
        except rx.ProtocolError:
            return
        raise AssertionError("invalid frame accepted")

    good = frame(1)
    check("valid packet exact roundtrip", lambda: equal(rx.parse_frame(json.dumps(good).encode()), good))
    check("invalid UTF8", lambda: must_reject(b"\xff"))
    check("duplicate JSON keys", lambda: must_reject(b'{"version":1,"version":1}'))
    check("truncated JSON", lambda: must_reject(b'{"version":'))
    mutations = {
        "wrong source": lambda f: f.update(source="board-unverified"),
        "bool frame ID": lambda f: f.update(frame_id=True),
        "negative frame ID": lambda f: f.update(frame_id=-1),
        "wrong dimensions": lambda f: f.update(width=1280),
        "coordinate overflow": lambda f: f["targets"][0].update(x2=640),
        "negative coordinates": lambda f: f["targets"][0].update(x1=-1),
        "inverted box": lambda f: f["targets"][0].update(x1=100),
        "duplicate target IDs": lambda f: f["targets"][1].update(id=1),
        "invalid id width": lambda f: f["targets"][0].update(id=256),
        "numeric valid": lambda f: f["targets"][0].update(valid=1),
        "unknown field": lambda f: f.update(extra=1),
        "missing field": lambda f: f.pop("targets"),
    }
    for name, mutate in mutations.items():
        obj = copy.deepcopy(good)
        mutate(obj)
        check(name, lambda obj=obj: must_reject(json.dumps(obj).encode()))

    def split_boundaries():
        raw = json.dumps(good).encode() + b"\r\n"
        for split in range(len(raw) + 1):
            lines = rx.Lines()
            equal(lines.feed(raw[:split]) + lines.feed(raw[split:]), [(raw[:-2], None)])
            equal(lines.finish(), [])
    check("every two-chunk split boundary including CRLF", split_boundaries)

    def oversize():
        lines = rx.Lines()
        events = lines.feed(b"x" * (rx.MAX_LINE + 100))
        equal(events, [])
        equal(len(lines.pending), 0)
        equal(lines.feed(b"\n{}\n"), [(None, "oversized line"), (b"{}", None)])
    check("oversize bound and resynchronization", oversize)

    def negative_stream():
        packets = [frame(0), frame(2), frame(2), frame(1), frame(3)]
        data = b"".join((json.dumps(f) + "\n").encode() for f in packets) + b"{"
        stats = rx.receive([data], a.out / "negative_stream")
        equal((stats["accepted"], stats["rejected"], stats["missing_frames"], stats["exit_code"]), (3, 3, 1, 1))
    check("gaps duplicates out-of-order and truncated EOF fail", negative_stream)
    check("empty stream fails", lambda: equal(rx.receive([], a.out / "empty")["exit_code"], 1))

    def geometry():
        f = frame(0)
        f["targets"] = [{"id": 255, "valid": True, "x1": 630, "y1": 350, "x2": 639, "y2": 359}]
        img = rx.render(f)
        equal(img.shape, (768, 1280, 3))
        equal(tuple(img[767, 1279]), (90, 210, 120))
        f["targets"][0]["valid"] = False
        equal(tuple(rx.render(f)[767, 1279]), (28, 25, 23))
    check("inclusive x2 mapping and valid false", geometry)

    def limits():
        data = b"".join((json.dumps(frame(i)) + "\n").encode() for i in range(3))
        stats = rx.receive([data], a.out / "frame_limit", max_frames=2)
        equal((stats["accepted"], stats["exit_code"], stats["transport_error"]), (2, 1, "frame limit exceeded"))
        stats = rx.receive([data], a.out / "byte_limit", max_bytes=4)
        equal((stats["bytes_saved"], stats["exit_code"]), (0, 1))
    check("disk growth bounded by frame and byte limits", limits)

    def loopback():
        here = Path(__file__).parent
        command = [sys.executable, "-X", "utf8", str(here / "pc_receiver.py"), "--listen", "--port", "0",
                   "--out", str(a.out / "loopback"), "--timeout", "20"]
        with open(a.out / "receiver.stderr.log", "x", encoding="utf-8") as err:
            p = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=err, text=True, encoding="utf-8")
            first = p.stdout.readline()
            if not first.startswith("LISTENING "):
                raise AssertionError("receiver failed to listen: " + first)
            port = int(first.split()[1].split(":")[-1])
            sender_command = [sys.executable, "-X", "utf8", str(here / "pc_receiver_simulate.py"),
                              "--port", str(port), "--frames", "60", "--record", str(a.out / "sent.jsonl")]
            sent = subprocess.run(sender_command, capture_output=True, text=True, encoding="utf-8", timeout=30)
            rest, _ = p.communicate(timeout=30)
        (a.out / "receiver.stdout.log").write_text(first + rest, encoding="utf-8")
        (a.out / "sender.stdout.log").write_text(sent.stdout, encoding="utf-8")
        (a.out / "sender.stderr.log").write_text(sent.stderr, encoding="utf-8")
        (a.out / "commands.json").write_text(json.dumps({"receiver": command, "sender": sender_command,
            "receiver_exit": p.returncode, "sender_exit": sent.returncode}, indent=2), encoding="utf-8")
        equal((p.returncode, sent.returncode), (0, 0))
        stats = json.loads((a.out / "loopback/summary.json").read_text())
        equal((stats["accepted"], stats["rejected"], stats["missing_frames"]), (60, 0, 0))
        equal((a.out / "loopback/raw_stream.bin").read_bytes(), (a.out / "sent.jsonl").read_bytes())
        records = [json.loads(x) for x in (a.out / "loopback/accepted.jsonl").read_text().splitlines()]
        equal(records, [frame(i) for i in range(60)])
        pictures = sorted((a.out / "loopback").glob("frame_*.png"))
        equal(len(pictures), 60)
        for i, picture in enumerate(pictures):
            img = cv2.imdecode(np.frombuffer(picture.read_bytes(), np.uint8), cv2.IMREAD_COLOR)
            equal(img.shape, (768, 1280, 3))
            if i % 15:
                x = frame(i)["targets"][0]["x1"] * 2
                equal(tuple(img[228, x]), (90, 210, 120))
    check("separate-process real TCP 60 frames and decoded output", loopback)
    summary = {"tests": results, "passed": sum(t["pass"] for t in results), "total": len(results), "board_test": False}
    (a.out / "tests.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0 if summary["passed"] == summary["total"] else 1


def equal(actual, expected):
    if actual != expected:
        raise AssertionError(f"{actual!r} != {expected!r}")


if __name__ == "__main__":
    sys.exit(main())
