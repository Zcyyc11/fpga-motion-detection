"""PC-only JSONL/TCP receiver proposal. No board protocol has been agreed.

Frames render on a coordinate canvas, not synchronized camera images.
Even a packet labelled 'board-unverified' is not proof of a board test.
"""
import argparse
import json
from pathlib import Path
import socket
import sys

import cv2
import numpy as np

MAX_LINE = 65536
HEADER = 48


class ProtocolError(ValueError):
    pass


def integer(value, low, high, name):
    if type(value) is not int or not low <= value <= high:
        raise ProtocolError(f"{name} must be integer in [{low}, {high}]")
    return value


def unique_keys(pairs):
    result = {}
    for k, v in pairs:
        if k in result:
            raise ProtocolError("duplicate JSON key: " + k)
        result[k] = v
    return result


def parse_frame(raw, expected_source="simulated"):
    if len(raw) > MAX_LINE:
        raise ProtocolError("oversized line")
    try:
        obj = json.loads(raw.decode("utf-8"), object_pairs_hook=unique_keys)
    except (UnicodeError, ValueError, RecursionError) as e:
        raise ProtocolError(str(e)) from e
    required = {"version", "source", "frame_id", "width", "height", "coordinate_space", "targets"}
    if not isinstance(obj, dict) or set(obj) != required:
        raise ProtocolError("frame fields do not match version 1 proposal")
    integer(obj["version"], 1, 1, "version")
    if obj["source"] != expected_source or expected_source not in ("simulated", "board-unverified"):
        raise ProtocolError("source mismatch")
    integer(obj["frame_id"], 0, 2**32 - 1, "frame_id")
    if obj["coordinate_space"] != "i3-2x" or obj["width"] != 640 or obj["height"] != 360:
        raise ProtocolError("proposal requires I3 640x360 coordinate canvas")
    integer(obj["width"], 640, 640, "width")
    integer(obj["height"], 360, 360, "height")
    if not isinstance(obj["targets"], list) or len(obj["targets"]) > 256:
        raise ProtocolError("targets must be list with at most 256 entries")
    seen = set()
    for target in obj["targets"]:
        if not isinstance(target, dict) or set(target) != {"id", "valid", "x1", "y1", "x2", "y2"}:
            raise ProtocolError("target fields mismatch")
        tid = integer(target["id"], 0, 255, "id")
        if tid in seen:
            raise ProtocolError("duplicate target id")
        seen.add(tid)
        if type(target["valid"]) is not bool:
            raise ProtocolError("valid must be boolean")
        for field, high in (("x1", 639), ("x2", 639), ("y1", 359), ("y2", 359)):
            integer(target[field], 0, high, field)
        if target["x1"] > target["x2"] or target["y1"] > target["y2"]:
            raise ProtocolError("inverted box")
    return obj


class Lines:
    """Bound memory while resynchronizing after oversized or malformed records."""
    def __init__(self):
        self.pending = bytearray()
        self.dropping = False

    def feed(self, chunk):
        events = []
        # Byte iteration keeps the maximum buffer bound true for arbitrary chunk sizes.
        for byte in chunk:
            if byte == 10:
                if self.dropping:
                    events.append((None, "oversized line"))
                else:
                    events.append((bytes(self.pending).rstrip(b"\r"), None))
                self.pending.clear()
                self.dropping = False
            elif not self.dropping:
                self.pending.append(byte)
                if len(self.pending) > MAX_LINE:
                    self.pending.clear()
                    self.dropping = True
        return events

    def finish(self):
        return [(None, "truncated stream (missing newline)")] if self.pending or self.dropping else []


def render(frame):
    canvas = np.full((720 + HEADER, 1280, 3), (28, 25, 23), np.uint8)
    for target in frame["targets"]:
        if not target["valid"]:
            continue
        # Proposal defines inclusive endpoints: one I3 pixel is a 2x2 display block.
        p1 = (target["x1"] * 2, target["y1"] * 2 + HEADER)
        p2 = (target["x2"] * 2 + 1, target["y2"] * 2 + 1 + HEADER)
        cv2.rectangle(canvas, p1, p2, (90, 210, 120), 2)
        cv2.putText(canvas, f"ID {target['id']}", (min(p1[0], 1190), max(HEADER + 18, p1[1] - 6)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, (90, 210, 120), 1)
    banner = "SIMULATED INPUT | NOT A BOARD TEST" if frame["source"] == "simulated" else "UNVERIFIED PACKETS | NOT BOARD EVIDENCE"
    cv2.rectangle(canvas, (0, 0), (1279, 30), (28, 25, 23), -1)
    cv2.putText(canvas, f"{banner} | frame {frame['frame_id']}", (12, 22),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, (240, 240, 240), 1)
    return canvas


def receive(chunks, out, expected_source="simulated", show=False, max_frames=1000, max_bytes=64 * 1024 * 1024):
    if max_frames < 1 or max_bytes < 1:
        raise ValueError("receive limits must be positive")
    out = Path(out)
    out.mkdir(parents=True, exist_ok=False)
    stats = {"accepted": 0, "rejected": 0, "missing_frames": 0, "last_frame": None,
             "expected_source": expected_source, "board_test": False,
             "protocol_status": "proposal-not-agreed", "canvas": "blank coordinate canvas, not source video",
             "max_frames": max_frames, "max_bytes": max_bytes, "bytes_saved": 0}
    lines = Lines()
    failure = None
    with open(out / "raw_stream.bin", "xb") as rawfile, \
         open(out / "accepted.jsonl", "x", encoding="utf-8") as accepted, \
         open(out / "rejected.jsonl", "x", encoding="utf-8") as rejected:
        def event(raw, error):
            try:
                if error:
                    raise ProtocolError(error)
                frame = parse_frame(raw, expected_source)
                if stats["accepted"] >= max_frames:
                    raise RuntimeError("frame limit exceeded")
                previous = stats["last_frame"]
                if previous is not None and frame["frame_id"] <= previous:
                    raise ProtocolError("duplicate or out-of-order frame")
                if previous is not None:
                    stats["missing_frames"] += frame["frame_id"] - previous - 1
                canvas = render(frame)
                ok, encoded = cv2.imencode(".png", canvas)
                if not ok:
                    raise RuntimeError("PNG encoding failed")
                with open(out / f"frame_{frame['frame_id']:010d}.png", "xb") as image:
                    image.write(encoded.tobytes())
                accepted.write(json.dumps(frame, ensure_ascii=False) + "\n")
                stats["accepted"] += 1
                stats["last_frame"] = frame["frame_id"]
                if show:
                    cv2.imshow("PC receiver - protocol proposal", canvas)
                    cv2.waitKey(1)
            except ProtocolError as e:
                stats["rejected"] += 1
                rejected.write(json.dumps({"reason": str(e), "raw_hex": raw.hex() if raw is not None else None}) + "\n")
        try:
            for chunk in chunks:
                if stats["bytes_saved"] + len(chunk) > max_bytes:
                    raise RuntimeError("byte limit exceeded; excess chunk not saved")
                rawfile.write(chunk)
                stats["bytes_saved"] += len(chunk)
                for raw, error in lines.feed(chunk):
                    event(raw, error)
        except Exception as e:
            failure = str(e)
        finally:
            for raw, error in lines.finish():
                event(raw, error)
            if show:
                cv2.destroyAllWindows()
    stats["transport_error"] = failure
    stats["exit_code"] = 0 if stats["accepted"] and not (stats["rejected"] or failure or stats["missing_frames"]) else 1
    (out / "summary.json").write_text(json.dumps(stats, indent=2), encoding="utf-8")
    return stats


def tcp_chunks(host, port, timeout):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
        server.settimeout(timeout)
        server.bind((host, port))
        server.listen(1)
        print(f"LISTENING {host}:{server.getsockname()[1]} (proposal, one connection)", flush=True)
        conn, _ = server.accept()
        with conn:
            conn.settimeout(timeout)
            while True:
                chunk = conn.recv(8192)
                if not chunk:
                    break
                yield chunk


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument("--file", type=Path)
    group.add_argument("--listen", action="store_true")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--timeout", type=float, default=15)
    ap.add_argument("--source", choices=["simulated", "board-unverified"], default="simulated")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--show", action="store_true")
    ap.add_argument("--max-frames", type=int, default=1000)
    ap.add_argument("--max-bytes", type=int, default=64 * 1024 * 1024)
    args = ap.parse_args()
    if args.file:
        with args.file.open("rb") as f:
            stats = receive(iter(lambda: f.read(8192), b""), args.out, args.source, args.show, args.max_frames, args.max_bytes)
    else:
        stats = receive(tcp_chunks(args.host, args.port, args.timeout), args.out, args.source, args.show, args.max_frames, args.max_bytes)
    print(json.dumps(stats))
    return stats["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
