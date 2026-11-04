#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
将测试视频输出到板卡 J10，并通过采集卡预览 J11 输出。

用法：
    python live_view_board.py --video "./test.mp4" --shotdir "./captures"
    python live_view_board.py --dev 1 --x 2560 --y 0 --video "./test.mp4"

按 s 保存快照，按 q 退出。
硬件链路：PC HDMI 输出 -> 板卡 J10；板卡 J11 -> USB 采集卡 -> PC。
输出窗口为 1280x720。采集画面在显示前缩放到窗口尺寸。
"""
import argparse
import ctypes
import os
import time

import cv2
import numpy as np

# 默认显示和采集配置；设备号与窗口坐标按本机环境调整。
DEFAULT_VIDEO = "vehicles.mp4"
DEFAULT_DEV = 1                 # UGREEN 采集卡（MSMF 枚举号，可能因插拔变化）
DEFAULT_X, DEFAULT_Y = 2560, 0  # 板子扩展屏 DISPLAY2 左上角
WIN_W, WIN_H = 1280, 720        # 板子 J10 接受的分辨率
DEFAULT_SHOTDIR = "./captures"

LABEL = "Tier1 HDMI r3"


def _pin_window(user32, title, x, y, w, h, popup=False, topmost=False):
    """把 OpenCV 窗口搬到指定位置/大小，可选无边框、置顶。"""
    hwnd = 0
    for _ in range(40):
        hwnd = user32.FindWindowW(None, title)
        if hwnd:
            break
        time.sleep(0.1)
    if not hwnd:
        print("[WARN] 找不到窗口:", title, flush=True)
        return
    if popup:
        user32.SetWindowLongW(hwnd, -16, 0x80000000)  # GWL_STYLE -> WS_POPUP
    SWP_SHOWWINDOW, SWP_NOACTIVATE = 0x0040, 0x0010
    flags = SWP_SHOWWINDOW
    if not popup:
        flags |= SWP_NOACTIVATE
    hwnd_insert_after = -1 if topmost else 0  # -1 = HWND_TOPMOST
    user32.SetWindowPos(hwnd, hwnd_insert_after, x, y, w, h, flags)
    time.sleep(0.25)


def main():
    ap = argparse.ArgumentParser(description="板端实时画面查看")
    ap.add_argument("--dev", type=int, default=DEFAULT_DEV, help="采集卡索引(默认1)")
    ap.add_argument("--x", type=int, default=DEFAULT_X, help="喂视频窗口左上角X")
    ap.add_argument("--y", type=int, default=DEFAULT_Y, help="喂视频窗口左上角Y")
    ap.add_argument("--video", default=DEFAULT_VIDEO, help="喂给板子的测试视频")
    ap.add_argument("--shotdir", default=DEFAULT_SHOTDIR, help="按s存图的目录")
    a = ap.parse_args()

    os.makedirs(a.shotdir, exist_ok=True)
    user32 = ctypes.windll.user32

    # ---- 喂视频窗口：搬到板子扩展屏，无边框铺满 ----
    cv2.namedWindow("feed", cv2.WINDOW_NORMAL)
    cv2.resizeWindow("feed", WIN_W, WIN_H)
    cv2.imshow("feed", np.zeros((WIN_H, WIN_W, 3), np.uint8))
    cv2.waitKey(1)
    _pin_window(user32, "feed", a.x, a.y, WIN_W, WIN_H, popup=True)

    # ---- 采集卡窗口：主屏置顶 ----
    # 标题用英文：OpenCV putText 不支持中文，会把汉字渲染成方块乱码
    title = "BOARD_LIVE (J11 capture) [%s] [s=save q=quit]" % LABEL
    cv2.namedWindow(title, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(title, WIN_W, WIN_H)
    _pin_window(user32, title, 120, 80, WIN_W, WIN_H, topmost=True)

    cap_v = cv2.VideoCapture(a.video)
    if not cap_v.isOpened():
        print("[ERR] 打不开测试视频:", a.video, flush=True)

    cap_c = cv2.VideoCapture(a.dev, cv2.CAP_MSMF)
    if not cap_c.isOpened():
        print("[ERR] 采集卡 dev=%d 打不开。可能：没插 / 索引变了 / 被别的程序独占"
              % a.dev, flush=True)
        print("      用 preview_capture.py 扫一下索引。", flush=True)

    shot = 0
    print("[RUN] s=存图 q=退出", flush=True)
    try:
        while True:
            # 喂视频（循环播放）
            ok, vf = cap_v.read()
            if not ok:
                cap_v.set(cv2.CAP_PROP_POS_FRAMES, 0)
                ok, vf = cap_v.read()
            if ok and vf is not None:
                cv2.imshow("feed", cv2.resize(vf, (WIN_W, WIN_H)))

            # 采集板子输出
            if cap_c.isOpened():
                rc, cf = cap_c.read()
                if rc and cf is not None:
                    # 将采集画面缩放到显示窗口尺寸。
                    cf = cv2.resize(cf, (WIN_W, WIN_H), interpolation=cv2.INTER_LINEAR)
                    cv2.putText(cf, LABEL, (20, 36),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 255, 255), 2)
                    cv2.putText(cf, "[s=save  q=quit]", (20, cf.shape[0] - 20),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)
                    cv2.imshow(title, cf)

            key = cv2.waitKey(1) & 0xFF
            if key == ord("q"):
                break
            if key == ord("s") and cap_c.isOpened():
                rc, cf = cap_c.read()
                if rc and cf is not None:
                    shot += 1
                    p = os.path.join(a.shotdir, "shot_%03d.png" % shot)
                    cv2.imwrite(p, cv2.resize(cf, (WIN_W, WIN_H),
                                              interpolation=cv2.INTER_LINEAR))
                    print("saved", p, flush=True)
    finally:
        cap_v.release()
        if cap_c.isOpened():
            cap_c.release()
        cv2.destroyAllWindows()
        print("quit.", flush=True)


if __name__ == "__main__":
    main()
