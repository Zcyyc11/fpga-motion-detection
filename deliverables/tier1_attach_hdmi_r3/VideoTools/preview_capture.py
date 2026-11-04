# -*- coding: utf-8 -*-
"""采集卡实时预览 —— 把板子 J11 的输出显示在 PC 屏幕上，便于肉眼核对。

用法：
    python preview_capture.py --label "Tier1 HDMI r3"
    python preview_capture.py --label "Tier1 HDMI r3" --device 1
按 Q 或 ESC 退出。
"""
import argparse
import sys
import time

import cv2


def find_capture_device(max_dev=4):
    """自动探测采集卡：返回 (device_index, backend, frame)。设备号会随插拔重新枚举，不能写死。"""
    for dev in range(max_dev):
        for be, _name in ((cv2.CAP_MSMF, "MSMF"), (cv2.CAP_DSHOW, "DSHOW")):
            cap = cv2.VideoCapture(dev, be)
            if not cap.isOpened():
                cap.release()
                continue
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
            cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
            ok, f = cap.read()
            if ok and f is not None:
                cap.release()
                return dev, be, f
            cap.release()
    return None, None, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", default="", help="左上角显示的版本标注")
    ap.add_argument("--device", type=int, default=-1,
                    help="采集卡设备号；-1 = 自动探测（默认）")
    ap.add_argument("--w", type=int, default=960)
    ap.add_argument("--h", type=int, default=540)
    ap.add_argument("--full", action="store_true", help="按原始 1280x720 显示")
    args = ap.parse_args()

    dev = args.device
    be = cv2.CAP_MSMF
    if dev < 0:
        dev, be, _probe = find_capture_device()
        if dev is None:
            print("FAIL 没探测到任何可出画面的采集设备（0~3 都试过了）")
            return 1
        print("自动探测到设备 %d" % dev)

    cap = cv2.VideoCapture(dev, be)
    if not cap.isOpened():
        print("FAIL 打不开采集卡设备", dev)
        return 1
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))

    win = "CAPTURE PREVIEW"
    cv2.namedWindow(win, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(win, args.w, args.h)
    cv2.moveWindow(win, 60, 60)

    print("预览中，设备 %d，标注：%s" % (dev, args.label or "(无)"))
    print("按 Q / ESC 退出")

    fails = 0
    n = 0
    t0 = time.time()
    try:
        while True:
            ok, f = cap.read()
            if not ok or f is None:
                fails += 1
                if fails % 30 == 1:
                    print("  无画面（第 %d 次）——板子可能没有输出" % fails)
                if fails > 150:
                    print("连续 150 次读不到帧，停止预览")
                    break
                time.sleep(0.03)
                continue
            fails = 0
            n += 1
            if not args.full and (f.shape[1] != args.w or f.shape[0] != args.h):
                f = cv2.resize(f, (args.w, args.h))
            if args.label:
                cv2.rectangle(f, (0, 0), (min(460, f.shape[1]), 34), (30, 30, 30), -1)
                cv2.putText(f, args.label, (10, 24), cv2.FONT_HERSHEY_SIMPLEX,
                            0.66, (60, 220, 60), 2, cv2.LINE_AA)
            if n % 30 == 0:
                fps = n / max(time.time() - t0, 0.001)
                cv2.putText(f, "%.1f fps" % fps, (f.shape[1] - 110, 24),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1, cv2.LINE_AA)
            cv2.imshow(win, f)
            k = cv2.waitKey(1) & 0xFF
            if k in (27, ord('q'), ord('Q')):
                break
            if cv2.getWindowProperty(win, cv2.WND_PROP_VISIBLE) < 1:
                break
    finally:
        cap.release()
        cv2.destroyAllWindows()
    print("结束，共显示 %d 帧" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
