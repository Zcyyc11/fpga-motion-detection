"""正式 UART v0.2 接收/原始报文重放。坐标画布，不是同步视频或实机认证。"""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
import time

from uart_protocol import Decoder, Frames, PROTOCOL

HEADER = 80


def render(frame, source):
    import cv2
    import numpy as np
    canvas = np.full((720 + HEADER, 1280, 3), (28, 25, 23), np.uint8)
    for target in frame["targets"]:
        p1 = (2 * target["x1"], HEADER + 2 * target["y1"])
        p2 = (2 * target["x2"] + 1, HEADER + 2 * target["y2"] + 1)
        color = (90, 210, 120)
        cv2.rectangle(canvas, p1, p2, color, 2)
        cv2.putText(canvas, f"ID {target['id']}", (min(p1[0], 1170), max(HEADER + 18, p1[1] - 5)),
                    cv2.FONT_HERSHEY_SIMPLEX, .55, color, 1)
    banner = "SIMULATED INPUT - NOT A BOARD TEST" if source == "simulated" else "UNVERIFIED INPUT - BOARD ORIGIN NOT VERIFIED"
    status = "CHECK ERRORS" if frame.get("problems") else "COORDINATE CANVAS - NOT VIDEO"
    cv2.putText(canvas, f"{banner} | frame {frame['frame_id']}", (12, 22),
                cv2.FONT_HERSHEY_SIMPLEX, .58, (245, 245, 245), 1)
    events = "; ".join(f"{e['name'].upper()} ID {e['id']} X {e['center_x']}" for e in frame["events"][-3:])
    cv2.putText(canvas, events or "No received alarm events", (12, 47),
                cv2.FONT_HERSHEY_SIMPLEX, .55, (70, 170, 255) if events else (180, 180, 180), 1)
    cv2.putText(canvas, f"{status} | targets {len(frame['targets'])}/{frame['expected_count']}", (12, 70),
                cv2.FONT_HERSHEY_SIMPLEX, .5, (200, 200, 200), 1)
    return canvas


def serial_chunks(port, duration=60.0, idle_timeout=5.0, factory=None):
    """No reconnect/reset: each connection has a distinct output directory."""
    if factory is None:
        import serial
        factory = serial.Serial
    with factory(port=port, baudrate=115200, bytesize=8, parity="N", stopbits=1,
                 timeout=.1, xonxoff=False, rtscts=False, dsrdtr=False) as device:
        start = last = time.monotonic()
        while time.monotonic() - start < duration:
            data = device.read(max(1, min(device.in_waiting, 4096)))
            if data:
                last = time.monotonic()
                yield data
            elif time.monotonic() - last >= idle_timeout:
                raise TimeoutError("serial idle timeout; no automatic reconnect")


def file_chunks(path):
    with Path(path).open("rb") as stream:
        yield from iter(lambda: stream.read(4096), b"")


def receive(chunks, out, source="board-unverified", show=False, save_images=100,
            max_frames=10000, max_bytes=16 * 1024 * 1024, metadata=None):
    if source not in ("simulated", "board-unverified"):
        raise ValueError("invalid source")
    if max_frames < 1 or max_bytes < 1 or save_images < 0:
        raise ValueError("limits must be positive (image limit may be zero)")
    if show or save_images:
        import cv2  # Fail before creating capture directory if dependency is missing.
    out = Path(out)
    out.mkdir(parents=True, exist_ok=False)
    stats = dict(protocol=PROTOCOL, started_utc=datetime.now(timezone.utc).isoformat(),
                 source=source, board_test=False, video_synchronized=False,
                 bytes_saved=0, packets=0, frames=0, valid_frames=0, events=0, images=0,
                 max_frames=max_frames, max_bytes=max_bytes, save_images=save_images,
                 metadata=metadata or {}, errors=0, transport_error=None,
                 last_frame_event_completeness="unverifiable: no end packet or event count")
    digest = hashlib.sha256()
    counts = Counter()
    # Exclusive creation protects all previous runs; JSONL is streamed, not accumulated.
    with (out / "raw_stream.bin").open("xb") as raw, \
         (out / "packets.jsonl").open("x", encoding="utf-8") as packets, \
         (out / "frames.jsonl").open("x", encoding="utf-8") as frames, \
         (out / "events.jsonl").open("x", encoding="utf-8") as events, \
         (out / "errors.jsonl").open("x", encoding="utf-8") as errors:

        def write(handle, obj):
            handle.write(json.dumps(obj, ensure_ascii=False) + "\n")

        def error(detail):
            counts[detail["reason"]] += 1
            stats["errors"] += 1
            write(errors, detail)

        def display(frame):
            cv2.imshow("UART v0.2 - coordinate canvas", render(frame, source))
            if cv2.waitKey(1) & 255 == 27:
                raise KeyboardInterrupt("display stopped with Esc")

        def frame_ready(frame):
            frame["source"] = source
            stats["frames"] += 1
            stats["valid_frames"] += int(frame["valid"])
            write(frames, frame)
            if stats["images"] < save_images:
                ok, data = cv2.imencode(".png", render(frame, source))
                if not ok:
                    raise OSError("PNG encoding failed")
                with (out / f"frame_{frame['sequence']:06d}_{frame['frame_id']:05d}.png").open("xb") as image:
                    image.write(data.tobytes())
                stats["images"] += 1
            if show:
                display(frame)

        def event_ready(event):
            stats["events"] += 1
            write(events, event)
            events.flush()
            print(f"ALARM frame={event['frame_id']} ID={event['id']} {event['name']} X={event['center_x']}", flush=True)

        assembler = Frames(frame_ready, event_ready, error)

        def packet_ready(packet):
            stats["packets"] += 1
            write(packets, packet)
            # Stop before opening an unbounded new frame; pending previous frame is finalized below.
            if packet["kind"] == "header" and assembler.sequence >= max_frames:
                raise RuntimeError("frame limit reached; capture stopped")
            assembler.accept(packet)
            if show and packet["kind"] == "event" and assembler.current is not None:
                display(assembler.current)

        decoder = Decoder(packet_ready, assembler.error)
        try:
            for chunk in chunks:
                if not isinstance(chunk, bytes):
                    raise TypeError("transport must yield bytes")
                remaining = max_bytes - stats["bytes_saved"]
                kept = chunk[:remaining]
                raw.write(kept)
                digest.update(kept)
                stats["bytes_saved"] += len(kept)
                decoder.feed(kept)
                if len(chunk) > remaining:
                    raise RuntimeError("byte limit reached; excess input not saved")
        except (Exception, KeyboardInterrupt) as exc:
            stats["transport_error"] = f"{type(exc).__name__}: {exc}"
            assembler.error({"reason": "transport_or_processing_error", "detail": stats["transport_error"]})
        finally:
            try:
                # If processing stopped mid-chunk, do not continue parsing unsafely.
                if not stats["transport_error"]:
                    decoder.feed(final=True)
                assembler.finish()
            except (Exception, KeyboardInterrupt) as exc:
                stats["transport_error"] = stats["transport_error"] or f"{type(exc).__name__}: {exc}"
                error({"reason": "finalization_error", "detail": str(exc)})
            cleanup = []
            if show:
                cleanup.append(("display_close_error", cv2.destroyAllWindows))
            close = getattr(chunks, "close", None)
            if close:
                cleanup.append(("transport_close_error", close))
            for reason, action in cleanup:
                try:
                    action()
                except (Exception, KeyboardInterrupt) as exc:
                    stats["transport_error"] = stats["transport_error"] or f"{type(exc).__name__}: {exc}"
                    error({"reason": reason, "detail": str(exc)})
    stats.update(missing_frames=assembler.missing_frames, frame_wraps=assembler.wraps,
                 error_counts=dict(counts), raw_sha256=digest.hexdigest(),
                 finished_utc=datetime.now(timezone.utc).isoformat())
    stats["exit_code"] = 0 if stats["valid_frames"] and not stats["errors"] else 1
    (out / "summary.json").write_text(json.dumps(stats, ensure_ascii=False, indent=2), encoding="utf-8")
    return stats


def positive(value):
    import math
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError("must be a finite positive number")
    return number


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--file", type=Path, help="原始二进制报文文件")
    mode.add_argument("--port", help="实际串口，例如 COM7；不自动猜测板卡")
    mode.add_argument("--list-ports", action="store_true")
    ap.add_argument("--out", type=Path, help="必须是尚不存在的目录")
    ap.add_argument("--source", choices=["simulated", "board-unverified"], default="board-unverified")
    ap.add_argument("--duration", type=positive, default=60.0)
    ap.add_argument("--idle-timeout", type=positive, default=5.0)
    ap.add_argument("--show", action="store_true")
    ap.add_argument("--save-images", type=int, default=100)
    ap.add_argument("--max-frames", type=int, default=10000)
    ap.add_argument("--max-bytes", type=int, default=16 * 1024 * 1024)
    ap.add_argument("--metadata", type=Path, help="板卡/固件/样本对应说明 JSON；只保留，不认证来源")
    args = ap.parse_args()
    try:
        if args.list_ports:
            from serial.tools import list_ports
            print(json.dumps([{"port": p.device, "description": p.description, "hwid": p.hwid}
                              for p in list_ports.comports()], ensure_ascii=False, indent=2))
            return 0
        if args.out is None:
            ap.error("--out is required for capture/replay")
        metadata = json.loads(args.metadata.read_text(encoding="utf-8-sig")) if args.metadata else {}
        if not isinstance(metadata, dict):
            raise ValueError("metadata must be a JSON object")
        metadata = {"supplied": metadata, "transport": "serial" if args.port else "file",
                    "input": args.port or str(args.file), "baud": 115200 if args.port else None,
                    "duration": args.duration if args.port else None}
        chunks = serial_chunks(args.port, args.duration, args.idle_timeout) if args.port else file_chunks(args.file)
        result = receive(chunks, args.out, args.source, args.show, args.save_images,
                         args.max_frames, args.max_bytes, metadata)
        print(json.dumps(result, ensure_ascii=False))
        return result["exit_code"]
    except (Exception, KeyboardInterrupt) as exc:
        print(f"ERROR: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
