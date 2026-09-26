# -*- coding: utf-8 -*-
"""生成"真值已知"的合成测试片段 —— 黄金参考与 RTL 仿真共用同一份输入。

为什么需要它
------------
帧差法算出来的"运动区域质心"到底准不准，靠肉眼是看不出来的。必须有一份
**物体真实位置逐帧已知**的视频，才能把误差量化成像素数写进报告。
这份片段同时是两件事的地基：
  1) PC/PS 端黄金参考的输入 —— 量化算法本身的偏差
  2) RTL 仿真（xsim）的激励     —— 手里没有板子也能验证流水线

设计（全部确定性，无随机数）
----------------------------
黑色背景 720p，一个纯白矩形从左向右匀速平移，每帧位移恒定。
720p 是我们的锁定分辨率；位移量默认 16 px/帧，是为了让帧差得到的
"边缘细带"明显宽于形态学核 —— 铁律：**核边长必须 < 每帧位移**，否则细带被腐蚀掉，
一帧都检测不到（详见 data/README.md「纪律」）。

输出
----
  synth_720p.avi / .mp4        视频本体（优先无损 FFV1；不可用则退化 mp4v）
  synth_720p_groundtruth.csv   逐帧真值：frame, cx, cy, x, y, w, h
                               （质心直接由白色像素求均值得到 —— 无坐标约定歧义）
  synth_720p_clipinfo.txt      生成参数 + 视频 SHA256，供他人核验"是同一份输入"

用法
----
  python make_test_clip.py                    # 用默认参数生成
  python make_test_clip.py --dx 8 --frames 90 # 换参数做对照实验
"""

import argparse
import csv
import hashlib
import os
import sys

import numpy as np
import cv2

# ---------------- 默认参数（改动请同步重生成 clipinfo）----------------
W, H = 1280, 720          # 分辨率：锁定 720p
FPS = 30
N_FRAMES = 60
OBJ_W, OBJ_H = 160, 120   # 运动目标尺寸（像素）
Y0 = 300                  # 目标顶边 y（垂直不动，只做水平平移）
X0 = 60                   # 起始左边缘 x
DX = 16                   # 每帧水平位移（像素/帧）


def open_writer(base_path, fps, size):
    """优先无损 FFV1（.avi），退化到有损 mp4v（.mp4）。"""
    for ext, tag in ((".avi", "FFV1"), (".mp4", "mp4v")):
        path = base_path + ext
        vw = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*tag), fps, size)
        if vw.isOpened():
            return vw, path, tag
        vw.release()
    raise RuntimeError("找不到可用的视频编码器（FFV1 / mp4v 都打不开）")


def main():
    ap = argparse.ArgumentParser(description="生成真值已知的合成测试片段")
    ap.add_argument("--outdir", default=os.path.dirname(os.path.abspath(__file__)))
    ap.add_argument("--frames", type=int, default=N_FRAMES)
    ap.add_argument("--dx", type=int, default=DX)
    ap.add_argument("--name", default="synth_720p")
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    n, dx = args.frames, args.dx

    # 边界自检：别让目标跑出画面
    last_x = X0 + dx * (n - 1)
    if last_x + OBJ_W > W:
        print("!! 参数越界：末帧目标右边缘 %d > 画面宽 %d，请减小 --dx 或 --frames"
              % (last_x + OBJ_W, W))
        return 1

    base = os.path.join(args.outdir, args.name)
    vw, vpath, vtag = open_writer(base, FPS, (W, H))
    print("编码器: %s   ->  %s" % (vtag, vpath))

    rows = []
    for i in range(n):
        img = np.zeros((H, W, 3), np.uint8)
        x = X0 + dx * i
        # 用 (x, y) ~ (x+OBJ_W-1, y+OBJ_H-1)，使白色区域恰好是 OBJ_W x OBJ_H 个像素
        cv2.rectangle(img, (x, Y0), (x + OBJ_W - 1, Y0 + OBJ_H - 1), (255, 255, 255), -1)
        vw.write(img)

        # 真值 = 白色像素的重心（直接由图像算出，避免任何坐标约定歧义）
        ys, xs = np.nonzero(img[:, :, 0])
        rows.append((i, xs.mean(), ys.mean(), x, Y0, OBJ_W, OBJ_H))
    vw.release()

    truth = base + "_groundtruth.csv"
    with open(truth, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["frame", "cx", "cy", "x", "y", "w", "h"])
        for r in rows:
            w.writerow(["%d" % r[0], "%.2f" % r[1], "%.2f" % r[2],
                        r[3], r[4], r[5], r[6]])

    h = hashlib.sha256()
    with open(vpath, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    vbytes = os.path.getsize(vpath)

    info = base + "_clipinfo.txt"
    with open(info, "w", encoding="utf-8") as f:
        f.write("合成测试片段 — 生成参数与校验\n")
        f.write("=" * 52 + "\n")
        f.write("分辨率      : %d x %d @ %d fps\n" % (W, H, FPS))
        f.write("帧数        : %d  (时长 %.2f s)\n" % (n, n / float(FPS)))
        f.write("目标        : 纯白矩形 %d x %d px，黑底\n" % (OBJ_W, OBJ_H))
        f.write("运动        : 水平匀速，每帧位移 %d px（垂直不动）\n" % dx)
        f.write("起始位置    : 左边缘 x=%d, 顶边 y=%d\n" % (X0, Y0))
        f.write("编码        : %s\n" % vtag)
        f.write("-" * 52 + "\n")
        f.write("视频文件    : %s\n" % os.path.basename(vpath))
        f.write("文件大小    : %d bytes (%.1f KB)\n" % (vbytes, vbytes / 1024.0))
        f.write("SHA256      : %s\n" % h.hexdigest())
        f.write("真值文件    : %s\n" % os.path.basename(truth))
        f.write("-" * 52 + "\n")
        f.write("复现命令    : python make_test_clip.py --frames %d --dx %d\n" % (n, dx))
        f.write("说明        : 真值 cx/cy 由白色像素求重心得到，是图像的客观属性，\n")
        f.write("              与任何检测算法无关，因此可以直接当作误差基准。\n")

    print("真值  : %s  (%d 行)" % (truth, len(rows)))
    print("说明  : %s" % info)
    print("视频  : %d bytes (%.1f KB)  sha256=%s"
          % (vbytes, vbytes / 1024.0, h.hexdigest()[:16] + "..."))
    print("校验  : 第 0 帧中心 (%.1f, %.1f)   末帧中心 (%.1f, %.1f)"
          % (rows[0][1], rows[0][2], rows[-1][1], rows[-1][2]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
