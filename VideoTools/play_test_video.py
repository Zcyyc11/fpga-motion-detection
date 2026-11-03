# -*- coding: utf-8 -*-
"""把测试视频送到板子屏（x=2560, y=0, 1280x720），给板子 J10 当信号源。

用法：
    python play_test_video.py                    # 默认 vehicles.mp4
    python play_test_video.py --video people-walking.mp4
    python play_test_video.py --x 2560 --y 0
按 ESC 或关窗口结束。
"""
import argparse
import ctypes
import os
import sys
import time

from ctypes import wintypes

# 在 import cv2 之前声明 DPI 感知。
#   注意：shcore.SetProcessDpiAwareness 失败时返回 HRESULT 而不抛异常，
#   所以 try/except 抓不住；这里直接调老 API SetProcessDPIAware()，再校验一次。
def _enable_dpi_aware():
    u = ctypes.windll.user32
    try:
        u.SetProcessDPIAware()
    except Exception:
        pass
    hdc = u.GetDC(0)
    dpi = ctypes.windll.gdi32.GetDeviceCaps(hdc, 88)
    u.ReleaseDC(0, hdc)
    return dpi


_DPI = _enable_dpi_aware()

import cv2

VIDEO_DIR = "."
BOARD_SCREEN_XY = (2560, 0)


def find_board_screen():
    """返回非主屏那块显示器的物理坐标 (x, y, w, h)。找不到返回 None。"""
    u = ctypes.windll.user32

    class RECT(ctypes.Structure):
        _fields_ = [("left", ctypes.c_long), ("top", ctypes.c_long),
                    ("right", ctypes.c_long), ("bottom", ctypes.c_long)]

    class MONITORINFO(ctypes.Structure):
        _fields_ = [("cbSize", ctypes.c_ulong), ("rcMonitor", RECT),
                    ("rcWork", RECT), ("dwFlags", ctypes.c_ulong)]

    found = []
    PROC = ctypes.WINFUNCTYPE(ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong,
                              ctypes.POINTER(RECT), ctypes.c_double)

    def cb(hMon, hdc, lprc, data):
        mi = MONITORINFO()
        mi.cbSize = ctypes.sizeof(MONITORINFO)
        u.GetMonitorInfoW(hMon, ctypes.byref(mi))
        r = mi.rcMonitor
        found.append((r.left, r.top, r.right - r.left, r.bottom - r.top,
                      bool(mi.dwFlags & 1)))
        return 1

    u.EnumDisplayMonitors(0, 0, PROC(cb), 0)
    for (x, y, w, h, prim) in found:
        if not prim:
            return (x, y, w, h)
    return None


def place_window(win_title, tx, ty, tw, th, tries=3):
    """把窗口放到物理像素 (tx,ty,tw,th)。不看 DPI 设置，直接设一次→量回来→按比例修正。"""
    u = ctypes.windll.user32
    u.SetProcessDPIAware()
    hwnd = u.FindWindowW(None, win_title)
    if not hwnd:
        return False, (tx, ty, tw, th)
    GWL_STYLE = -16
    WS_CAPTION = 0x00C00000
    WS_THICKFRAME = 0x00040000
    WS_SYSMENU = 0x00080000
    style = u.GetWindowLongW(hwnd, GWL_STYLE)
    u.SetWindowLongW(hwnd, GWL_STYLE,
                     style & ~(WS_CAPTION | WS_THICKFRAME | WS_SYSMENU))
    HWND_TOPMOST = -1
    SWP_SHOWWINDOW = 0x0040
    SWP_FRAMECHANGED = 0x0020

    x, y, w, h = tx, ty, tw, th
    for _ in range(tries):
        u.SetWindowPos(hwnd, HWND_TOPMOST, x, y, w, h,
                       SWP_SHOWWINDOW | SWP_FRAMECHANGED)
        r = wintypes.RECT()
        u.GetWindowRect(hwnd, ctypes.byref(r))
        ax, ay = r.left, r.top
        aw, ah = r.right - r.left, r.bottom - r.top
        if abs(ax - tx) <= 2 and abs(ay - ty) <= 2 and abs(aw - tw) <= 4 and abs(ah - th) <= 4:
            return True, (ax, ay, aw, ah)
        k = (aw / w) if w else 1.0        # 实测缩放比
        if k <= 0:
            break
        x, y = int(round(tx / k)), int(round(ty / k))
        w, h = int(round(tw / k)), int(round(th / k))
    r = wintypes.RECT()
    u.GetWindowRect(hwnd, ctypes.byref(r))
    return False, (r.left, r.top, r.right - r.left, r.bottom - r.top)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--video", default="vehicles.mp4")
    ap.add_argument("--x", type=int, default=None, help="默认自动找非主屏")
    ap.add_argument("--y", type=int, default=None)
    ap.add_argument("--w", type=int, default=1280)
    ap.add_argument("--h", type=int, default=720)
    ap.add_argument("--fps", type=float, default=30.0)
    args = ap.parse_args()

    if args.x is None or args.y is None:
        scr = find_board_screen()
        if scr is None:
            print("WARN 没找到第二个显示器，用 (0,0)")
            args.x, args.y = 0, 0
        else:
            args.x, args.y, args.w, args.h = scr
            print("自动定位副屏: (%d,%d) %dx%d" % (args.x, args.y, args.w, args.h))

    path = args.video if os.path.isabs(args.video) else os.path.join(VIDEO_DIR, args.video)
    if not os.path.isfile(path):
        print("FAIL 找不到视频:", path)
        return 1

    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        print("FAIL 打不开视频:", path)
        return 1

    win = "BOARD_HDMI_SOURCE"
    cv2.namedWindow(win, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(win, args.w, args.h)
    cv2.moveWindow(win, args.x, args.y)
    cv2.imshow(win, cap.read()[1] if cap.isOpened() else None)
    cv2.waitKey(1)
    time.sleep(0.2)
    ok_place, actual = place_window(win, args.x, args.y, args.w, args.h)
    print("播放中：%s" % os.path.basename(path))
    print("目标物理 (%d,%d) %dx%d  →  实测 (%d,%d) %dx%d  %s"
          % (args.x, args.y, args.w, args.h,
             actual[0], actual[1], actual[2], actual[3],
             "OK" if ok_place else "FAIL 未对齐"))
    cap.set(cv2.CAP_PROP_POS_FRAMES, 0)

    interval = 1.0 / max(args.fps, 1.0)
    n = 0
    try:
        while True:
            t0 = time.time()
            ok, f = cap.read()
            if not ok:
                cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                continue
            n += 1
            if f.shape[1] != args.w or f.shape[0] != args.h:
                f = cv2.resize(f, (args.w, args.h))
            cv2.imshow(win, f)
            if n % 60 == 0:
                print("  已播 %d 帧" % n)
            if cv2.waitKey(1) & 0xFF == 27:
                break
            dt = time.time() - t0
            if dt < interval:
                time.sleep(interval - dt)
            if cv2.getWindowProperty(win, cv2.WND_PROP_VISIBLE) < 1:
                break
    finally:
        cap.release()
        cv2.destroyAllWindows()
    print("结束，共播 %d 帧" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
