import ctypes
import sys
import os
import time
import datetime
import numpy as np

try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
except Exception:
    ctypes.windll.user32.SetProcessDPIAware()

import cv2  # noqa: E402

video = sys.argv[1] if len(sys.argv) > 1 else "D:/FPGA/test_videos/vehicles.mp4"
duration = float(sys.argv[2]) if len(sys.argv) > 2 else 45.0
scene = sys.argv[3] if len(sys.argv) > 3 else "scene"
dev = int(sys.argv[4]) if len(sys.argv) > 4 else 1
x = int(sys.argv[5]) if len(sys.argv) > 5 else 2560
y = int(sys.argv[6]) if len(sys.argv) > 6 else 0

W, H = 1280, 720
NAME = "acceptance_feed"
outdir = r"D:\FPGA\output\evidence\%s" % scene
os.makedirs(outdir, exist_ok=True)

user32 = ctypes.windll.user32
GWL_STYLE = -16
STRIP = 0x00C00000 | 0x00040000 | 0x00020000 | 0x00010000 | 0x00080000
SWP_SHOWWINDOW = 0x0040
SWP_FRAMECHANGED = 0x0020
SWP_NOSIZE = 0x0001
HWND_TOPMOST = -1


class RECT(ctypes.Structure):
    _fields_ = [("left", ctypes.c_long), ("top", ctypes.c_long),
                ("right", ctypes.c_long), ("bottom", ctypes.c_long)]


def outer(hwnd):
    r = RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(r))
    return r.left, r.top, r.right - r.left, r.bottom - r.top


cap_v = cv2.VideoCapture(video)
if not cap_v.isOpened():
    print("VIDEO_OPEN_FAILED " + video, flush=True)
    sys.exit(1)

cv2.namedWindow(NAME, cv2.WINDOW_NORMAL)
cv2.resizeWindow(NAME, W, H)
cv2.imshow(NAME, np.zeros((H, W, 3), np.uint8))
cv2.waitKey(1)

hwnd = 0
for _ in range(40):
    hwnd = user32.FindWindowW(None, NAME)
    if hwnd:
        break
    time.sleep(0.1)

if hwnd:
    st = user32.GetWindowLongW(hwnd, GWL_STYLE)
    user32.SetWindowLongW(hwnd, GWL_STYLE, st & ~STRIP)
    _, _, ow, oh = outer(hwnd)
    dw, dh = ow - W, oh - H
    cw, ch = W - dw, H - dh
    cv2.resizeWindow(NAME, cw, ch)
    user32.MoveWindow(hwnd, x, y, W, H, True)
    time.sleep(0.3)
    lx, ly, lw, lh = outer(hwnd)
    print("window: (%d,%d) %dx%d target %dx%d %s"
          % (lx, ly, lw, lh, W, H, "OK" if (lx, ly, lw, lh) == (x, y, W, H) else "MISMATCH"), flush=True)
else:
    print("!! window not found, continuing anyway", flush=True)
    cw, ch = W, H

cap_c = cv2.VideoCapture(dev, cv2.CAP_MSMF)
if not cap_c.isOpened():
    print("CAM_OPEN_FAILED dev=%d MSMF (camera app holding it?)" % dev, flush=True)
    cap_v.release()
    cv2.destroyAllWindows()
    sys.exit(1)

gw = int(cap_c.get(cv2.CAP_PROP_FRAME_WIDTH))
gh = int(cap_c.get(cv2.CAP_PROP_FRAME_HEIGHT))
print("cam: dev=%d %dx%d (MSMF)" % (dev, gw, gh), flush=True)

frames = []
bright = []
diffs = []
reds = []
colors = []
best_red = None
best_red_n = -1
prev = None
t0 = time.time()
while time.time() - t0 < duration:
    ok, vf = cap_v.read()
    if not ok:
        cap_v.set(cv2.CAP_PROP_POS_FRAMES, 0)
        ok, vf = cap_v.read()
    if ok and vf is not None:
        fh, fw = vf.shape[:2]
        sc = min(cw / fw, ch / fh)
        nw, nh = int(fw * sc), int(fh * sc)
        vf = cv2.resize(vf, (nw, nh))
        canvas = np.zeros((ch, cw, 3), np.uint8)
        canvas[(ch - nh) // 2:(ch - nh) // 2 + nh,
               (cw - nw) // 2:(cw - nw) // 2 + nw] = vf
        cv2.imshow(NAME, canvas)
    key = cv2.waitKey(1)
    if key == 27:
        break
    rc, cf = cap_c.read()
    if rc and cf is not None:
        frames.append(cf)
        g = cv2.cvtColor(cf, cv2.COLOR_BGR2GRAY)
        bright.append(g.mean())
        if prev is not None:
            diffs.append(cv2.absdiff(g, prev).mean())
        prev = g
        b16 = cf[:, :, 0].astype(np.int16)
        g16 = cf[:, :, 1].astype(np.int16)
        r16 = cf[:, :, 2].astype(np.int16)
        redm = (r16 > 90) & ((r16 - g16) > 40) & ((r16 - b16) > 40)
        rn = int(redm.sum())
        reds.append(rn)
        spread = np.maximum(np.maximum(np.abs(r16 - g16), np.abs(r16 - b16)),
                            np.abs(g16 - b16))
        colors.append(int((spread > 40).sum()))
        if rn > best_red_n:
            best_red_n = rn
            best_red = cf.copy()
    else:
        time.sleep(0.005)

cap_c.release()
cap_v.release()
cv2.destroyAllWindows()

n = len(frames)
if n == 0:
    print("NO_FRAMES (device opened but produced nothing)", flush=True)
    sys.exit(1)

elapsed = time.time() - t0
for tag, idx in [("first", 0), ("mid", n // 2), ("last", n - 1)]:
    cv2.imwrite(os.path.join(outdir, "%s_%s.png" % (scene, tag)), frames[idx])

lit = sum(1 for b in bright if b >= 20.0)
avg_b = sum(bright) / n
avg_d = sum(diffs) / len(diffs) if diffs else 0.0
max_d = max(diffs) if diffs else 0.0
red_frames = sum(1 for x in reds if x > 0)
red_max = max(reds) if reds else 0
color_max = max(colors) if colors else 0
color_frames = sum(1 for x in colors if x > 0)
if best_red is not None and best_red_n > 0:
    cv2.imwrite(os.path.join(outdir, "%s_best_red_n%d.png" % (scene, best_red_n)), best_red)
lines = [
    "scene: %s" % scene,
    "video: %s" % video,
    "device: %d (MSMF)" % dev,
    "negotiated: %dx%d" % (gw, gh),
    "duration: %.0fs" % duration,
    "frames: %d" % n,
    "fps: %.1f" % (n / elapsed),
    "brightness avg: %.1f" % avg_b,
    "lit frames (>=20): %d / %d (%.0f%%)" % (lit, n, 100.0 * lit / n),
    "motion avg diff: %.2f max: %.2f" % (avg_d, max_d),
    "verdict: %s" % ("MOVING" if avg_d >= 1.0 else "STATIC"),
    "red frames: %d / %d (%.0f%%) max_red_px: %d" % (red_frames, n, 100.0 * red_frames / n, red_max),
    "color frames(px>40): %d / %d max_color_px: %d" % (color_frames, n, color_max),
    "captured at: %s" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
]
txt = "\n".join(lines)
with open(os.path.join(outdir, "summary.txt"), "w", encoding="utf-8") as fp:
    fp.write(txt + "\n")
print(txt, flush=True)
print("saved to " + outdir, flush=True)
