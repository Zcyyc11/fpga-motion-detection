"""Independent byte fixtures and acceptance checks; all inputs are SIMULATED.

No fixture encoder is imported from the receiver. Output paths must be new;
failures and generated captures are retained for inspection.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys

import uart_receiver as receiver
from uart_protocol import Decoder, Frames


def checksum(body):
    return body + bytes([sum(body) % 256])


def header(frame, count=0):
    return checksum(struct.pack("<BHB", 0x5A, frame, count))


def target(frame, identity=7, box=(10, 20, 30, 40), flags=0):
    return checksum(struct.pack("<BHBHHHHB", 0xA5, frame, identity, *box, flags))


def event(frame, identity=7, kind=1, x=20):
    return checksum(struct.pack("<BHBBH", 0xC3, frame, identity, kind, x))


def assembled(raw, step=4096):
    frames, events, errors, packets = [], [], [], []
    assembler = Frames(frames.append, events.append, errors.append)
    def accept(p):
        packets.append(p)
        assembler.accept(p)
    decoder = Decoder(accept, assembler.error)
    for i in range(0, len(raw), step):
        decoder.feed(raw[i:i + step])
    decoder.feed(final=True)
    assembler.finish()
    return dict(frames=frames, events=events, errors=errors, packets=packets,
                missing=assembler.missing_frames, wraps=assembler.wraps)


def require(condition, detail="assertion failed"):
    if not condition:
        raise AssertionError(detail)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    results = []
    def check(name, fn):
        try:
            fn()
            results.append({"name": name, "pass": True})
        except Exception as exc:
            results.append({"name": name, "pass": False, "error": repr(exc)})

    # Fixed, manually auditable bytes pin byte order and checksum independently.
    def golden():
        raw = bytes.fromhex("5a341201a1 a53412070a0014001e0028000056 c334120701140025")
        data = assembled(raw, 1)
        require(not data["errors"], data)
        f = data["frames"][0]
        require(f["frame_id"] == 0x1234 and f["targets"][0]["x2"] == 30)
        require(f["targets"][0]["flags"] == 0 and f["events"][0]["name"] == "crossing")
    check("fixed little-endian golden bytes", golden)

    raw = header(65534) + header(65535, 1) + target(65535) + event(65535) + header(0, 16)
    raw += b"".join(target(0, i, (i, i, 100 + i, 100 + i)) for i in range(16))
    raw += event(0, 3, 2, 99) + header(1)
    (args.out / "simulated.bin").write_bytes(raw)
    expected = assembled(raw)
    check("zero single sixteen targets and events", lambda: require(
        not expected["errors"] and [len(f["targets"]) for f in expected["frames"]] == [0, 1, 16, 0]
        and len(expected["events"]) == 2 and expected["wraps"] == 1, expected))
    for step in [1, 2, 3, 4, 5, 7, 13, 14, 19, 4096]:
        check(f"fragmentation {step}", lambda step=step: require(assembled(raw, step) == expected))

    def bad(name, stream, reason):
        def verify():
            data = assembled(stream, 3)
            require(any(e["reason"] == reason for e in data["errors"]), data)
        check(name, verify)
    bad("checksum", header(2, 1) + target(2)[:-1] + b"\xff" + header(3), "checksum")
    bad("noise", b"\x00\xff\x11" + header(2), "noise")
    bad("truncated target", header(2, 1) + target(2)[:8], "truncated_packet")
    bad("truncated header containing valid shorter packet", b"\xa5" + header(3), "truncated_packet")
    bad("count seventeen", header(1, 17), "object_count_out_of_range")
    bad("missing target", header(1, 2) + target(1) + header(2), "target_count_mismatch")
    bad("extra target", header(1) + target(1), "excess_target")
    bad("duplicate ID", header(1, 2) + target(1) * 2, "duplicate_target_id")
    bad("orphan target", target(1), "orphan_packet")
    bad("wrong target frame", header(1, 1) + target(2), "orphan_packet")
    bad("orphan event", event(1), "orphan_packet")
    bad("duplicate frame", header(1) * 2, "duplicate_frame")
    bad("backward frame", header(9) + header(8), "backward_frame_or_reset")
    bad("missing frames", header(1) + header(4), "missing_frames")
    bad("ambiguous large jump", header(0) + header(32768), "backward_frame_or_reset")
    bad("unknown FLAGS retained and flagged", header(1, 1) + target(1, flags=4), "undefined_flags")
    bad("x overflow", header(1, 1) + target(1, box=(1, 2, 640, 3)), "invalid_box")
    bad("y overflow", header(1, 1) + target(1, box=(1, 2, 3, 360)), "invalid_box")
    bad("inverted box", header(1, 1) + target(1, box=(20, 2, 3, 4)), "invalid_box")
    bad("unknown event type", header(1) + event(1, kind=3), "invalid_event")
    bad("event center overflow", header(1) + event(1, x=640), "invalid_event")
    bad("per-frame event bound", header(1) + event(1) * 257, "events_per_frame_limit")

    def recover():
        data = assembled(header(1, 1) + target(1)[:-1] + b"\x00" + header(2, 1) + target(2))
        require(data["frames"][-1]["valid"] and data["frames"][-1]["frame_id"] == 2, data)
    check("bad packet resynchronization", recover)
    check("MAGIC in valid payload", lambda: require(not assembled(
        header(0xA55A, 1) + target(0xA55A, 0xC3, (90, 90, 165, 195)))['errors']))
    def instant_event():
        seen = []
        a = Frames(lambda _: None, seen.append, lambda _: None)
        d = Decoder(a.accept, a.error)
        d.feed(header(1) + event(1))
        require(len(seen) == 1 and a.current is not None)
    check("event emitted before next header", instant_event)

    def end_to_end():
        out = args.out / "replay"
        stats = receiver.receive(receiver.file_chunks(args.out / "simulated.bin"), out,
                                 "simulated", save_images=4)
        require(stats["exit_code"] == 0 and stats["frames"] == 4 and stats["events"] == 2, stats)
        require((out / "raw_stream.bin").read_bytes() == raw)
        require(stats["raw_sha256"] == hashlib.sha256(raw).hexdigest())
        require(stats["board_test"] is False and stats["video_synchronized"] is False)
        import cv2
        import numpy as np
        files = sorted(out.glob("frame_*.png"))
        require(len(files) == 4)
        for p in files:
            image = cv2.imdecode(np.fromfile(p, dtype=np.uint8), cv2.IMREAD_COLOR)
            require(image is not None and image.shape == (800, 1280, 3))
        records = [json.loads(s) for s in (out / "frames.jsonl").read_text(encoding="utf-8").splitlines()]
        require(records[-1]["events_complete"] is False)
        require(records[2]["events"][0]["type"] == 2)
    check("replay raw hash images frame and event logs", end_to_end)

    def corner_geometry():
        data = assembled(header(2, 2) + target(2, 1, (0, 0, 0, 0)) + target(2, 2, (639, 359, 639, 359)))
        image = receiver.render(data["frames"][0], "simulated")
        require(tuple(image[receiver.HEADER, 0]) == (90, 210, 120))
        require(tuple(image[-1, -1]) == (90, 210, 120))
    check("inclusive extreme corner coordinates", corner_geometry)

    def failure_run(name, chunks, **kwargs):
        stats = receiver.receive(chunks, args.out / name, "simulated", save_images=0, **kwargs)
        require(stats["exit_code"] != 0, stats)
        require((args.out / name / "summary.json").exists())
        return stats
    check("empty stream fails", lambda: failure_run("empty", []))
    check("byte bound preserves prefix", lambda: require(failure_run("byte_limit", [raw], max_bytes=7)["bytes_saved"] == 7))
    check("frame bound", lambda: failure_run("frame_limit", [raw], max_frames=2))
    def broken():
        yield header(1, 1) + target(1)
        raise OSError("simulated cable disconnect")
    check("disconnect retains capture and failure", lambda: failure_run("disconnect", broken()))
    def interrupted():
        yield header(1)
        raise KeyboardInterrupt("simulated Ctrl+C")
    check("Ctrl+C retains capture and failure", lambda: failure_run("interrupted", interrupted()))
    def overwrite():
        before = (args.out / "replay/summary.json").read_bytes()
        try:
            receiver.receive([raw], args.out / "replay", save_images=0)
        except FileExistsError:
            require((args.out / "replay/summary.json").read_bytes() == before)
            return
        raise AssertionError("existing output overwritten")
    check("existing output protected", overwrite)

    def serial_loop():
        import serial
        device = serial.serial_for_url("loop://", baudrate=115200, timeout=.01)
        device.write(raw)
        observed = {}
        def factory(**options):
            observed.update(options)
            return device
        stats = receiver.receive(receiver.serial_chunks("loop://", .05, .2, factory),
                                 args.out / "serial_loop", "simulated", save_images=0)
        require(stats["exit_code"] == 0 and stats["raw_sha256"] == hashlib.sha256(raw).hexdigest(), stats)
        require(observed["baudrate"] == 115200 and observed["parity"] == "N" and observed["stopbits"] == 1)
        require(not observed["xonxoff"] and not observed["rtscts"] and not device.is_open)
    check("actual pyserial loopback simulated transport", serial_loop)
    def serial_idle():
        import serial
        def factory(**options):
            return serial.serial_for_url("loop://", timeout=.005)
        failure_run("serial_idle", receiver.serial_chunks("loop://", .1, .02, factory))
    check("serial idle timeout", serial_idle)

    def cli():
        p = subprocess.run([sys.executable, str(Path(receiver.__file__)), "--file", str(args.out / "simulated.bin"),
                            "--out", str(args.out / "cli"), "--source", "simulated", "--save-images", "0"],
                           capture_output=True, text=True, encoding="utf-8")
        (args.out / "cli_stdout.txt").write_text(p.stdout, encoding="utf-8")
        (args.out / "cli_stderr.txt").write_text(p.stderr, encoding="utf-8")
        require(p.returncode == 0, p.stderr)
    check("CLI file replay", cli)
    summary = {"board_test": False, "input": "SIMULATED", "checks": results,
               "passed": sum(r["pass"] for r in results), "total": len(results)}
    summary["exit_code"] = int(summary["passed"] != summary["total"])
    (args.out / "checks.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return summary["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
