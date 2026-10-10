"""Send explicitly simulated target packets; this is not board output."""
import argparse
import json
from pathlib import Path
import socket


def frame(number):
    targets = [] if number % 15 == 0 else [
        {"id": 1, "valid": True, "x1": 30 + number * 3, "y1": 90, "x2": 60 + number * 3, "y2": 160},
        {"id": 2, "valid": True, "x1": 580 - number * 3, "y1": 180, "x2": 620 - number * 3, "y2": 250},
    ]
    return {"version": 1, "source": "simulated", "frame_id": number, "width": 640, "height": 360,
            "coordinate_space": "i3-2x", "targets": targets}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--frames", type=int, default=60)
    ap.add_argument("--record", type=Path, required=True)
    a = ap.parse_args()
    if not 1 <= a.frames <= 120:
        ap.error("--frames must be 1..120 for this fixed synthetic trajectory")
    raw = b"".join((json.dumps(frame(i)) + "\n").encode("utf-8") for i in range(a.frames))
    a.record.parent.mkdir(parents=True, exist_ok=True)
    with a.record.open("xb") as f:
        f.write(raw)
    with socket.create_connection((a.host, a.port), timeout=15) as s:
        # Deliberately split JSON records across TCP sends.
        for start in range(0, len(raw), 37):
            s.sendall(raw[start:start + 37])
    print(f"SIMULATED: sent {a.frames} frames, {len(raw)} bytes")


if __name__ == "__main__":
    main()
