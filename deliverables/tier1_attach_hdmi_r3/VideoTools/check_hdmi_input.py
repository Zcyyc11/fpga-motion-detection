#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
检查 HDMI 采集设备的分辨率、平均亮度与帧间差异。

用法：
    python check_hdmi_input.py
    python check_hdmi_input.py --device 1 --thresh 100
    python check_hdmi_input.py --preview

默认检查 1280x720、平均亮度大于 100、帧间差异大于 0.1。
这些指标用于排查输入异常；暗场景或静态视频也可能触发提示。
退出码：0 表示检查通过，1 表示需要检查输入或采集配置。
"""
import argparse
import sys
import time

try:
    import cv2
    import numpy as np
except ImportError:
    print("FAIL: 没装 opencv-python / numpy")
    print("      请运行：python -m pip install -r requirements.txt")
    sys.exit(1)

# 预览窗口坐标；应与实际显示器布局一致。
BOARD_SCREEN_XY = (2560, 0)


def open_capture(dev, w, h, api_pref):
    backends = []
    if api_pref:
        backends = [api_pref]
    else:
        backends = [cv2.CAP_MSMF, cv2.CAP_DSHOW, cv2.CAP_ANY]

    for be in backends:
        cap = cv2.VideoCapture(dev, be)
        if not cap.isOpened():
            cap.release()
            continue
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, w)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, h)
        cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
        ok, frame = cap.read()
        if ok and frame is not None:
            return cap, frame, be
        cap.release()
    return None, None, None


def backend_name(be):
    m = {
        cv2.CAP_MSMF: "MSMF",
        cv2.CAP_DSHOW: "DirectShow",
        cv2.CAP_ANY: "ANY",
    }
    return m.get(be, str(be))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", type=int, default=1, help="采集卡设备号，默认 1")
    ap.add_argument("--width", type=int, default=1280)
    ap.add_argument("--height", type=int, default=720)
    ap.add_argument("--frames", type=int, default=10, help="采样帧数")
    ap.add_argument("--thresh", type=float, default=100.0, help="亮度阈值")
    ap.add_argument("--preview", action="store_true", help="开预览窗（摆到板子屏位置）")
    args = ap.parse_args()

    print("=" * 56)
    print("HDMI 输入信号自检")
    print("=" * 56)

    cap, frame, be = open_capture(args.device, args.width, args.height, None)
    if cap is None:
        print("FAIL  打不开采集卡设备 %d" % args.device)
        print()
        print("排障顺序：")
        print("  1. Windows「相机」App 会把采集卡独占，先关掉它（报 0xC00D3704 就是这个原因）")
        print("  2. 换设备号试：--device 0 / --device 2")
        print("  3. 换 USB 口，避免经过 Hub")
        return 1

    print("OK    采集卡已打开（后端 %s）" % backend_name(be))
    h, w = frame.shape[:2]
    res_ok = (w == args.width and h == args.height)
    print("%s  分辨率 %dx%d（期望 %dx%d）" % ("OK   " if res_ok else "WARN ",
                                              w, h, args.width, args.height))

    if args.preview:
        cv2.namedWindow("HDMI INPUT", cv2.WINDOW_NORMAL)
        cv2.resizeWindow("HDMI INPUT", args.width, args.height)
        cv2.moveWindow("HDMI INPUT", BOARD_SCREEN_XY[0], BOARD_SCREEN_XY[1])
        cv2.imshow("HDMI INPUT", frame)
        cv2.waitKey(1)

    brightness = []
    diffs = []
    prev = None
    last_frame = frame
    for _ in range(args.frames):
        ok, f = cap.read()
        if not ok or f is None:
            continue
        last_frame = f
        g = cv2.cvtColor(f, cv2.COLOR_BGR2GRAY) if f.ndim == 3 else f
        brightness.append(float(g.mean()))
        if prev is not None:
            diffs.append(float(np.abs(g.astype(np.int16) - prev.astype(np.int16)).mean()))
        prev = g
        if args.preview:
            cv2.imshow("HDMI INPUT", f)
            if cv2.waitKey(30) & 0xFF == 27:
                break
    cap.release()
    if args.preview:
        cv2.destroyAllWindows()

    if not brightness:
        print("FAIL  一帧都读不到")
        return 1

    avg_b = sum(brightness) / len(brightness)
    b_min, b_max = min(brightness), max(brightness)
    avg_d = sum(diffs) / len(diffs) if diffs else 0.0

    print("%s  平均亮度 %.1f（阈值 %.0f，区间 %.1f~%.1f）" % (
        "OK   " if avg_b > args.thresh else "FAIL ", avg_b, args.thresh, b_min, b_max))
    print("%s  帧间差异 %.3f（>0.1 说明画面是活的）" % (
        "OK   " if avg_d > 0.1 else "WARN ", avg_d))

    # 桌面特征检测：Windows 任务栏在底部约 4%~6%，浅色主题下接近全白
    if last_frame is not None:
        hh = last_frame.shape[0]
        bar = last_frame[int(hh * 0.955):, :]
        bar_b = (float(cv2.cvtColor(bar, cv2.COLOR_BGR2GRAY).mean())
                 if bar.ndim == 3 else float(bar.mean()))
        desktop_like = (bar_b > 200) and (avg_d < 0.1)
        print("%s  底部任务栏区亮度 %.1f%s" % (
            "WARN " if desktop_like else "OK   ", bar_b,
            "  ← 疑似 Windows 桌面！" if desktop_like else ""))
    else:
        desktop_like = False

    print("-" * 56)
    problems = []
    if not res_ok:
        problems.append("分辨率不是 %dx%d —— 检查 Windows 显示设置里 DISPLAY2 的分辨率" % (args.width, args.height))
    if desktop_like:
        problems.append("抓到的是 PC 桌面，不是板子输出 —— 采集卡的 HDMI 输入线接到 PC 上了")
        problems.append("   正确链路：PC HDMI OUT → 板子 J10 → 板子处理 → 板子 J11 → 采集卡 → 本机 USB")
        problems.append("   即：采集卡的输入必须来自【板子 J11】，不能直连电脑")
    if avg_b <= args.thresh:
        problems.append("画面是黑的 —— PC 的 HDMI 输出没接通（DISPLAY2 active/attached 为 False？）")
        problems.append("           查：Win+P 选「扩展」→ 显示器 2 → %dx%d → 拖到 x=%d" % (
            args.width, args.height, BOARD_SCREEN_XY[0]))
        problems.append("           再查：板子 LED0 是否常亮（不亮 = dvi2rgb 没锁定）")
        problems.append("           再查：网线插了吗？RJ45 没 link 时 125MHz 时钟不来 → 黑屏")
    if avg_d <= 0.1 and not desktop_like:
        problems.append("画面静止 —— 可能 PC 没在播放视频，或画面卡住")

    if problems:
        print("结论：NOT READY，别往下测")
        for p in problems:
            print("  - " + p)
        return 1

    print("结论：READY —— 输入信号正常，可以开始上板验证")
    return 0


if __name__ == "__main__":
    sys.exit(main())
