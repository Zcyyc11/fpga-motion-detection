"""Targeted audit-feedback regressions. All sources and serial faults are SIMULATED."""
import argparse
from contextlib import redirect_stderr, redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
from unittest.mock import patch

import uart_receiver as receiver
import verify_uart_capture as verifier
from check_uart_receiver import assembled, header, require


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", type=Path, required=True)
    out = ap.parse_args().out
    out.mkdir(parents=True, exist_ok=False)
    checks = []

    def check(name, fn):
        try:
            fn()
            checks.append(dict(name=name, passed=True))
        except Exception as exc:
            checks.append(dict(name=name, passed=False, error=repr(exc)))

    def run_cli(name, *args):
        p = subprocess.run([sys.executable, receiver.__file__, "--out", str(out / name),
                            "--save-images", "0", *map(str, args)],
                           capture_output=True, text=True, encoding="utf-8")
        (out / f"{name}_stdout.txt").write_text(p.stdout, encoding="utf-8")
        (out / f"{name}_stderr.txt").write_text(p.stderr, encoding="utf-8")
        return p

    def bad_stream(name, size, limit):
        capture = out / name
        noise = b"\xa5" * size
        stats = receiver.receive((noise[i:i+4096] for i in range(0, size, 4096)),
                                 capture, "simulated", save_images=0, max_error_details=limit)
        require(stats["errors"] == size and stats["exit_code"] == 1, stats)
        require(stats["error_counts"] == {"checksum": size-13, "truncated_packet": 13}, stats)
        require(stats["error_details_written"] == min(limit, size), stats)
        require(stats["error_details_suppressed"] == max(0, size-limit), stats)
        require(len((capture / "errors.jsonl").read_text().splitlines()) == min(limit, size))
        require((capture / "raw_stream.bin").read_bytes() == noise)
        require(stats["raw_sha256"] == hashlib.sha256(noise).hexdigest())
        require((capture / "errors.jsonl").stat().st_size < max(1, limit * 100))
    check("256 KiB checksum noise bounded to default details; exact full counts", lambda: bad_stream(
        "noise_default", 262144, receiver.DEFAULT_MAX_ERROR_DETAILS))
    for size, limit in [(31, 32), (32, 32), (33, 32), (33, 0)]:
        check(f"detail boundary size={size} limit={limit}", lambda size=size, limit=limit:
              bad_stream(f"noise_{size}_{limit}", size, limit))

    def late_errors():
        stats = receiver.receive([b"\xa5"*100, header(500)+header(499)+header(500)],
                                 out / "late_errors", "simulated", save_images=0, max_error_details=1)
        require(stats["error_counts"].get("backward_frame_or_reset") == 1, stats)
        require(stats["error_counts"].get("duplicate_frame") == 1, stats)
        require(stats["error_details_suppressed"] == stats["errors"]-1 and stats["exit_code"] == 1)
    check("new error types after detail cap still counted", late_errors)

    reference = out / "expected.jsonl"
    reference.write_text(json.dumps(dict(frame_id=500, targets=[], events=[],
                                        input_frame_ref="SIMULATED independent header"))+"\n", encoding="utf-8")
    for source in ["simulated", "board-unverified"]:
        def provenance(source=source):
            capture = out / source
            metadata = {"supplied": {"operator": "模拟操作人", "board": "声明不认证"}}
            receiver.receive([header(500)], capture, source, save_images=0, metadata=metadata)
            result = verifier.verify(capture, reference)
            require(result["exit_code"] == 0 and result["source"] == source)
            require(result["source_verified"] is False and result["board_test"] is False)
            require(result["capture_metadata"] == metadata)
            require(result["summary_sha256"] == hashlib.sha256((capture / "summary.json").read_bytes()).hexdigest())
            require(("SIMULATED" if source == "simulated" else "UNVERIFIED") in result["source_label"])
            (out / f"detached_{source}.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        check(f"detached comparison carries {source} declarations and summary hash", provenance)

    def failed_reference():
        missing = out / "missing_reference.jsonl"
        result = verifier.verify(out / "simulated", missing)
        require(result["exit_code"] == 1 and result["source"] == "simulated")
        require(result["summary_sha256"] and result["board_test"] is False)
        (out / "failed_comparison.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    check("comparison failure retains simulated provenance", failed_reference)

    for mode in ["missing_source", "invalid_summary", "absent_capture"]:
        def missing_provenance(mode=mode):
            capture = out / mode
            if mode != "absent_capture":
                shutil.copytree(out / "simulated", capture)
                summary = capture / "summary.json"
                if mode == "invalid_summary":
                    summary.write_text("not json", encoding="utf-8")
                else:
                    obj = json.loads(summary.read_text(encoding="utf-8"))
                    del obj["source"]
                    summary.write_text(json.dumps(obj), encoding="utf-8")
            result = verifier.verify(capture, reference)
            require(result["source"] == "unknown" and "UNVERIFIED" in result["source_label"])
            require(result["board_test"] is False and result["source_verified"] is False)
            require(result["exit_code"] == (0 if mode == "missing_source" else 1))
        check(f"{mode} stays explicitly unverified", missing_provenance)

    for name, path in [("file_missing", out / "not_present.bin"), ("file_directory", out)]:
        def open_failure(name=name, path=path):
            result = run_cli(name, "--file", path)
            require(result.returncode == 2 and "ERROR:" in result.stderr)
            require(not (out / name).exists())
        check(f"{name} actually fails open with exit 2 and no capture directory", open_failure)

    def serial_cli(name, factory):
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch("serial.Serial", factory), patch.object(sys, "argv", [receiver.__file__,
                   "--port", "SIMULATED", "--out", str(out/name), "--save-images", "0"]), \
                redirect_stdout(stdout), redirect_stderr(stderr):
            code = receiver.main()
        (out/f"{name}_stdout.txt").write_text(stdout.getvalue(), encoding="utf-8")
        (out/f"{name}_stderr.txt").write_text(stderr.getvalue(), encoding="utf-8")
        return code, stderr.getvalue()

    def serial_open_failure():
        def factory(**kw):
            raise OSError("SIMULATED unavailable serial port")
        code, diagnostic = serial_cli("serial_open_failure", factory)
        require(code == 2 and "unavailable serial port" in diagnostic)
        require(not (out/"serial_open_failure").exists())
    check("serial actual opener failure exit 2 without directory", serial_open_failure)

    class FaultDevice:
        in_waiting = 5
        def __init__(self, first_read=False, close_error=False):
            self.first_read, self.close_error = first_read, close_error
            self.reads = self.closes = 0
        def read(self, count):
            self.reads += 1
            if self.first_read or self.reads > 1:
                raise OSError("SIMULATED disconnected after open")
            return header(500)
        def close(self):
            self.closes += 1
            if self.close_error:
                raise OSError("SIMULATED close failure")

    for first, close in [(True, False), (False, False), (False, True)]:
        def capture_failure(first=first, close=close):
            name = f"read_failure_{first}_{close}"
            device = FaultDevice(first, close)
            code, _ = serial_cli(name, lambda **kw: device)
            stats = json.loads((out/name/"summary.json").read_text())
            require(code == 1 and stats["exit_code"] == 1 and device.closes == 1, stats)
            require(stats["error_counts"].get("transport_or_processing_error") == 1, stats)
            require(stats["error_counts"].get("transport_close_error", 0) == int(close), stats)
            require((out/name/"raw_stream.bin").read_bytes() == (b"" if first else header(500)))
        check(f"opened serial read failure first={first}, close_error={close} preserves evidence", capture_failure)

    def close_only():
        device = FaultDevice(close_error=True)
        source = receiver.serial_chunks("SIMULATED", factory=lambda **kw: device)
        with patch.object(receiver.time, "monotonic", side_effect=[0, 0, 0, 100]):
            stats = receiver.receive(source, out/"close_only", "simulated", save_images=0)
        require(stats["exit_code"] == 1 and stats["valid_frames"] == 1, stats)
        require(stats["error_counts"] == {"transport_close_error": 1}, stats)
        require(device.closes == 1)
    check("close failure after otherwise clean acquisition yields exit 1", close_only)

    def setup_cleanup():
        device = FaultDevice()
        source = receiver.serial_chunks("SIMULATED", factory=lambda **kw: device)
        blocker = out/"parent_is_file"
        blocker.write_text("preserve", encoding="utf-8")
        try:
            receiver.receive(source, blocker/"capture", save_images=0)
        except OSError:
            require(device.closes == 1 and device.reads == 0)
            require(blocker.read_text() == "preserve")
            return
        raise AssertionError("setup should fail")
    check("output setup failure closes opened source without reading", setup_cleanup)

    def strict_sequence():
        data = assembled(b"".join(header(f) for f in [500, 499, 500, 501]))
        require([f["valid"] for f in data["frames"]] == [True, False, False, True])
        require([e["reason"] for e in data["errors"]] == ["backward_frame_or_reset", "duplicate_frame"])
        reset = assembled(b"".join(header(f) for f in [500, 0, 1, 499, 500, 501]))
        require([f["valid"] for f in reset["frames"]] == [True, False, False, False, False, True])
        require(not assembled(header(0)+header(1))["errors"])
    check("reset ambiguity and backward then duplicate remain strict; new session starts clean", strict_sequence)

    def collision():
        # Two payload changes cancel in the frozen additive checksum.
        old = bytes.fromhex("a503000564003200780046000001")
        changed = bytes.fromhex("a503000565003100780046000001")
        original = assembled(header(3, 1)+old)
        altered = assembled(header(3, 1)+changed)
        require(not original["errors"] and not altered["errors"])
        require(original["frames"][0]["targets"][0]["x1"] == 100)
        require(altered["frames"][0]["targets"][0]["x1"] == 101)
    check("checksum collision remains an explicit protocol limitation", collision)

    result = dict(board_test=False, input="SIMULATED", checks=checks,
                  passed=sum(c["passed"] for c in checks), total=len(checks),
                  source_sha256={name: hashlib.sha256((Path(__file__).parent/name).read_bytes()).hexdigest()
                                 for name in ["uart_receiver.py", "uart_protocol.py", "verify_uart_capture.py", "check_uart_type1.py"]})
    result["exit_code"] = int(result["passed"] != result["total"])
    (out/"checks.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return result["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
