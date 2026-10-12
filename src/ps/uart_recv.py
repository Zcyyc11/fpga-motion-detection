# -*- coding: utf-8 -*-
"""uart_recv.py —— 板→PC 回传接收端参考实现（协议 v0.2）

对应 RTL：src/rtl/uart_tx.v（协议：帧头包 0x5A / 目标包 0xA5 / 事件包 0xC3）。
用途：
  1) 给线三当解析参考（字段/字节序/校验的权威样例）；
  2) 接真实板子时画框可视化：python src/ps/uart_recv.py --port COM5
  3) 接口联调期无板子时，回放文本报文：python src/ps/uart_recv.py --replay 报文.txt

协议要点（与《回传协议草案.md》一致，小端，字节累加和）：
  帧头包 0x5A（5B）：MAGIC, FRAME_L, FRAME_H, OBJ_CNT, CHK
  目标包 0xA5（14B）：MAGIC, FRAME_L, FRAME_H, ID, X1L,X1H,Y1L,Y1H,
                      X2L,X2H,Y2L,Y2H, FLAGS, CHK
  事件包 0xC3（8B） ：MAGIC, FRAME_L, FRAME_H, ID, TYPE, CX_L, CX_H, CHK
坐标：大像素域 640×360，右下角含端点；转 1280×720 原图 ×2。
异常：校验失败丢包等下一个 MAGIC；串口断开重连自动恢复。
"""
import argparse
import struct
import sys

MAGIC_HDR, MAGIC_TGT, MAGIC_EVT = 0x5A, 0xA5, 0xC3
PKT_LEN = {MAGIC_HDR: 5, MAGIC_TGT: 14, MAGIC_EVT: 8}

# 目标包字段布局（MAGIC 之后 13 字节）：frame H/J、id、x1/y1/x2/y2 各 H、flags、chk
TGT_FMT = "<HB4HB"           # 不含 magic 与 chk：2+1+8+1 = 12 字节 + chk
EVT_FMT = "<HBBH"            # frame H、id B、type B、cx H = 6 字节 + chk
HDR_FMT = "<HB"              # frame H、cnt B = 3 字节 + chk


def parse_stream(bytes_iter, on_frame, on_target, on_event, stats):
    """从任意字节流里按 MAGIC 重同步并拆包。"""
    buf = b""
    for chunk in bytes_iter:
        buf += chunk
        while True:
            # 找一个合法 MAGIC
            while buf and buf[0] not in PKT_LEN:
                buf = buf[1:]
                stats["resync"] += 1
            if len(buf) < 2 or buf[0] not in PKT_LEN:
                break
            plen = PKT_LEN[buf[0]]
            if len(buf) < plen:
                break
            pkt, buf = buf[:plen], buf[plen:]
            if sum(pkt[:-1]) & 0xFF != pkt[-1]:
                stats["bad_chk"] += 1
                continue                      # 丢包，等下一个 MAGIC
            magic = pkt[0]
            body, chk = pkt[1:-1], pkt[-1]
            if magic == MAGIC_HDR:
                frame, cnt = struct.unpack(HDR_FMT, body)
                stats["frames"] += 1
                on_frame(frame, cnt)
            elif magic == MAGIC_TGT:
                frame, tid, x1, y1, x2, y2, flags = struct.unpack(TGT_FMT, body)
                stats["targets"] += 1
                on_target(frame, tid, x1, y1, x2, y2, flags)
            else:
                frame, tid, etype, cx = struct.unpack(EVT_FMT, body)
                stats["events"] += 1
                on_event(frame, tid, etype, cx)


def main():
    ap = argparse.ArgumentParser(description="FPGA 回传接收端（协议 v0.2）")
    ap.add_argument("--port", default=None, help="串口名，如 COM5 / /dev/ttyUSB1")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--replay", default=None, help="从文本文件回放十六进制报文（空格分隔）")
    ap.add_argument("--frames", type=int, default=0, help="收满 N 帧后退出（0=不限）")
    args = ap.parse_args()

    if not args.port and not args.replay:
        ap.error("需要 --port 或 --replay 之一")

    cur_frame = {"n": None, "targets": []}
    last_drawn = {"frame": -1}

    def on_frame(frame, cnt):
        # 上一帧还有没画完的（正常不会：帧头包之间应画完），补画
        if cur_frame["n"] is not None and cur_frame["targets"]:
            draw(cur_frame["n"], cur_frame["targets"])
        cur_frame["n"] = frame
        cur_frame["targets"] = []
        print("[frame %5d] 宣告 %d 个目标" % (frame, cnt))
        if args.frames and frame >= args.frames:
            print("已达 --frames 上限，退出。统计：%s" % stats)
            sys.exit(0)

    def on_target(frame, tid, x1, y1, x2, y2, flags):
        print("  目标 id=%-3d box=(%4d,%4d)-(%4d,%4d) 大像素  flags=0x%02X"
              % (tid, x1, y1, x2, y2, flags))
        if frame == cur_frame["n"]:
            cur_frame["targets"].append((tid, x1, y1, x2, y2))

    def on_event(frame, tid, etype, cx):
        name = {1: "越界", 2: "停留"}.get(etype, "type=%d" % etype)
        print("  ★ 告警 [%s] id=%d cx=%d (frame %d)" % (name, tid, cx, frame))

    def draw(frame, targets):
        """有 opencv 时在 1280×720 黑底上画框预览；没有则跳过。"""
        try:
            import cv2
            import numpy as np
        except ImportError:
            return
        img = np.zeros((720, 1280, 3), dtype=np.uint8)
        for tid, x1, y1, x2, y2 in targets:
            cv2.rectangle(img, (x1 * 2, y1 * 2), ((x2 + 1) * 2, (y2 + 1) * 2),
                          (0, 0, 255), 2)
            cv2.putText(img, "id=%d" % tid, (x1 * 2, max(12, y1 * 2 - 4)),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 255, 0), 1)
        cv2.imshow("uart_recv frame %d" % frame, img)
        cv2.waitKey(1)

    stats = {"frames": 0, "targets": 0, "events": 0,
             "bad_chk": 0, "resync": 0}

    if args.replay:
        hexstr = open(args.replay, "r").read().split()
        data = bytes(int(h, 16) for h in hexstr)
        parse_stream(iter([data]), on_frame, on_target, on_event, stats)
    else:
        import serial                       # pip install pyserial
        ser = serial.Serial(args.port, args.baud, timeout=1)
        print("已打开 %s @%d" % (args.port, args.baud))
        try:
            while True:
                parse_stream(iter([ser.read(256)]),
                             on_frame, on_target, on_event, stats)
        except KeyboardInterrupt:
            pass
        finally:
            ser.close()

    print("统计：%s" % stats)


if __name__ == "__main__":
    main()
