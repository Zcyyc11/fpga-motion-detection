"""UART v0.2 (f15fbce): pure streaming decoder and bounded frame assembler."""
import struct

LENGTHS = {0x5A: 5, 0xA5: 14, 0xC3: 8}
PROTOCOL = "uart-v0.2-f15fbce"


def decode(raw):
    """Decode one checksum-verified packet; FLAGS is opaque, not a valid bit."""
    magic = raw[0]
    frame_id = int.from_bytes(raw[1:3], "little")
    p = {"frame_id": frame_id, "raw_hex": raw.hex()}
    if magic == 0x5A:
        if raw[3] > 16:
            raise ValueError("object_count_out_of_range")
        p.update(kind="header", count=raw[3])
    elif magic == 0xA5:
        x1, y1, x2, y2 = struct.unpack_from("<HHHH", raw, 4)
        if not (0 <= x1 <= x2 < 640 and 0 <= y1 <= y2 < 360):
            raise ValueError("invalid_box")
        p.update(kind="target", id=raw[3], x1=x1, y1=y1, x2=x2, y2=y2,
                 flags=raw[12])
    else:
        cx = int.from_bytes(raw[5:7], "little")
        if raw[4] not in (1, 2) or cx >= 640:
            raise ValueError("invalid_event")
        p.update(kind="event", id=raw[3], type=raw[4], center_x=cx,
                 name={1: "crossing", 2: "dwell"}[raw[4]])
    return p


class Decoder:
    """Keeps at most 13 trailing bytes between calls. Errors retain byte offsets."""
    def __init__(self, on_packet, on_error):
        self.buffer = bytearray()
        self.offset = 0
        self.on_packet = on_packet
        self.on_error = on_error

    def _discard(self, count, reason):
        raw = bytes(self.buffer[:count])
        self.on_error({"reason": reason, "offset": self.offset,
                       "length": count, "raw_hex": raw[:32].hex()})
        del self.buffer[:count]
        self.offset += count

    def feed(self, chunk=b"", final=False):
        self.buffer.extend(chunk)
        while self.buffer:
            length = LENGTHS.get(self.buffer[0])
            if length is None:
                end = next((i for i, b in enumerate(self.buffer) if b in LENGTHS), len(self.buffer))
                self._discard(end, "noise")
                continue
            if len(self.buffer) < length:
                if not final:
                    break
                self._discard(1, "truncated_packet")
                continue
            raw = bytes(self.buffer[:length])
            if sum(raw[:-1]) & 255 != raw[-1]:
                self._discard(1, "checksum")
                continue
            try:
                packet = decode(raw)
            except ValueError as error:
                self._discard(length, str(error))
                continue
            packet["offset"] = self.offset
            del self.buffer[:length]
            self.offset += length
            self.on_packet(packet)


class Frames:
    """Frame-header boundaries; events can arrive after the last target."""
    def __init__(self, on_frame, on_event, on_error):
        self.on_frame, self.on_event, self.on_error = on_frame, on_event, on_error
        self.current = None
        self.previous = None
        self.sequence = 0
        self.missing_frames = 0
        self.wraps = 0

    def error(self, error):
        if self.current is not None:
            # Store bounded reason set, full detail belongs in errors.jsonl.
            reason = error["reason"]
            if reason not in self.current["problems"]:
                self.current["problems"].append(reason)
        self.on_error(error)

    def finish(self, boundary="end_of_capture"):
        if self.current is None:
            return
        frame = self.current
        if len(frame["targets"]) != frame["expected_count"]:
            self.error({"reason": "target_count_mismatch", "frame_id": frame["frame_id"],
                        "expected": frame["expected_count"], "actual": len(frame["targets"])})
        frame["boundary"] = boundary
        # No event count exists in v0.2: even a header boundary cannot prove no
        # event was silently lost before transmission. Never certify completeness.
        frame["events_complete"] = False
        frame["next_header_seen"] = boundary == "next_header"
        frame["valid"] = not frame["problems"]
        self.current = None
        self.on_frame(frame)

    def accept(self, packet):
        fid = packet["frame_id"]
        if packet["kind"] == "header":
            self.finish("next_header")
            self.sequence += 1
            self.current = {"sequence": self.sequence, "frame_id": fid,
                            "expected_count": packet["count"], "targets": [],
                            "events": [], "problems": []}
            if self.previous is not None:
                delta = (fid - self.previous) & 0xFFFF
                if delta == 0 or delta >= 0x8000:
                    self.error({"reason": "duplicate_frame" if delta == 0 else "backward_frame_or_reset",
                                "previous": self.previous, "frame_id": fid})
                    return
                if delta > 1:
                    self.missing_frames += delta - 1
                    self.error({"reason": "missing_frames", "count": delta - 1,
                                "previous": self.previous, "frame_id": fid})
                if fid < self.previous:
                    self.wraps += 1
            self.previous = fid
            return
        if self.current is None or fid != self.current["frame_id"]:
            self.error({"reason": "orphan_packet", "kind": packet["kind"], "frame_id": fid})
            return
        if packet["kind"] == "event":
            self.on_event(packet)
            # Bounded per-frame detail; the full event log is streamed separately.
            if len(self.current["events"]) < 256:
                self.current["events"].append(packet)
            else:
                self.error({"reason": "events_per_frame_limit", "frame_id": fid})
            return
        targets = self.current["targets"]
        if any(p["id"] == packet["id"] for p in targets):
            self.error({"reason": "duplicate_target_id", "frame_id": fid, "id": packet["id"]})
        elif len(targets) >= self.current["expected_count"]:
            self.error({"reason": "excess_target", "frame_id": fid, "id": packet["id"]})
        else:
            targets.append(packet)
            if packet["flags"]:
                self.error({"reason": "undefined_flags", "frame_id": fid, "flags": packet["flags"]})
