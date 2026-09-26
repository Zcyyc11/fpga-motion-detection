# -*- coding: utf-8 -*-
"""PS 侧黄金参考：同一段视频跑"软件版"运动目标检测，逐帧输出质心坐标。

定位（重要）
------------
本文件是【对照标尺】，不是作品实现。作品的功能主体在 `src/rtl/`。
正式比对应当在【板卡 PS 端】用 PYNQ 镜像自带的 numpy / opencv 跑本脚本，
与 PL 流水线在**同一块板、同一段输入、同一分辨率**下对照；
在 PC 上跑只作开发期验证与偏差量化。

算法链（与 PL 端保持一致）
--------------------------
灰度 → 帧间差分 → 阈值分割 → 形态学开运算 → 连通域 → 外接框中心

★ 三种差分模式 —— 本脚本的核心价值是把"帧差法的质心偏多少"量化出来
------------------------------------------------------------------
运动物体每帧位移 d 像素时，帧差得到的是**两条宽约 d 的边缘细带**
（"新覆盖区"与"已腾空区"），而不是物体本身。由此产生一个系统性偏差：

  framediff    |I(t) - I(t-1)|                基线。取合并外接框中心，
                                              结果恒偏 **-d/2** 像素（滞后于物体）。
                                              只需 1 个帧缓存。
  gap2         |I(t+1) - I(t-1)|              无偏。落后 d 与超前 d 对称抵消，
                                              外接框中心正好等于 t 时刻真实中心。
                                              代价：需要 2 个帧缓存（DDR 带宽 / 容量翻倍）。
  compensated  framediff + 用细带宽度估 d      无偏且**不需要额外帧缓存**，纯算术补偿。
               再按运动方向补 ±d/2            方向由有符号差分判定，左右移都适用。

三种模式的取舍直接对应评分项"性能与资源优化"：
gap2 准但要翻倍帧缓存，compensated 同样准但只多几次加减法。

用法
----
  python golden_ref.py --clip <视频> --truth <真值csv> --out-csv <输出csv>
  默认路径按仓库结构自动解析（脚本位于 src/ps/）。
"""

import argparse
import csv
import os
import sys

import numpy as np
import cv2

THRESH = 25     # 二值化阈值
KERNEL = 3      # 形态学核边长；★ 必须 < 每帧位移量，否则细带被腐蚀掉（详见 data/README.md「纪律」）

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))


# --------------------------------------------------------------------------
# 基础算子
# --------------------------------------------------------------------------
def to_gray(frame):
    return cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)


def motion_mask(g_a, g_b, thresh, ksize):
    """|g_a - g_b| → 阈值 → 形态学开运算（去孤立噪点，保住真实细带）。"""
    d = cv2.absdiff(g_a, g_b)
    _, b = cv2.threshold(d, thresh, 255, cv2.THRESH_BINARY)
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (ksize, ksize))
    return cv2.morphologyEx(b, cv2.MORPH_OPEN, k)


def bbox_center(x, y, w, h):
    """区域占用像素索引 x..x+w-1，其重心即 x+(w-1)/2 —— 与像素均值定义一致。"""
    return (x + (w - 1) / 2.0, y + (h - 1) / 2.0)


def analyze(mask, g_prev, g_cur, thresh):
    """从一个运动掩码里取出合并外接框、细带宽度、以及运动方向。"""
    cnts, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not cnts:
        return None
    x, y, w, h = cv2.boundingRect(np.vstack(cnts))
    widths = [cv2.boundingRect(c)[2] for c in cnts]

    # 方向：有符号差分。"新覆盖区"重心在"已腾空区"右侧 → 物体向右移。
    sd = g_cur.astype(np.int16) - g_prev.astype(np.int16)
    nm, om = sd > thresh, sd < -thresh
    sign = 0.0
    if nm.any() and om.any():
        sign = 1.0 if np.nonzero(nm)[1].mean() > np.nonzero(om)[1].mean() else -1.0

    return dict(x=x, y=y, w=w, h=h, n=len(cnts), widths=sorted(widths),
                d_est=(float(min(widths)) if len(widths) >= 2 else 0.0), sign=sign)


# --------------------------------------------------------------------------
# 三种模式
# --------------------------------------------------------------------------
def run_framediff(grays, thresh, ksize):
    out = {}
    for t in range(1, len(grays)):
        a = analyze(motion_mask(grays[t - 1], grays[t], thresh, ksize),
                    grays[t - 1], grays[t], thresh)
        if a:
            out[t] = bbox_center(a["x"], a["y"], a["w"], a["h"])
    return out


def run_gap2(grays, thresh, ksize):
    out = {}
    for t in range(1, len(grays) - 1):
        a = analyze(motion_mask(grays[t - 1], grays[t + 1], thresh, ksize),
                    grays[t - 1], grays[t + 1], thresh)
        if a:
            out[t] = bbox_center(a["x"], a["y"], a["w"], a["h"])
    return out


def run_compensated(grays, thresh, ksize):
    out = {}
    for t in range(1, len(grays)):
        a = analyze(motion_mask(grays[t - 1], grays[t], thresh, ksize),
                    grays[t - 1], grays[t], thresh)
        if not a:
            continue
        cx, cy = bbox_center(a["x"], a["y"], a["w"], a["h"])
        out[t] = (cx + a["sign"] * a["d_est"] / 2.0, cy)
    return out


MODES = [
    ("framediff", run_framediff, 1, "基线：|I(t)-I(t-1)|，恒偏 -d/2"),
    ("gap2", run_gap2, 2, "|I(t+1)-I(t-1)|，无偏，帧缓存翻倍"),
    ("compensated", run_compensated, 1, "1 帧差分 + 细带宽度补偿，无额外缓存"),
]


# --------------------------------------------------------------------------
def read_truth(path):
    truth = {}
    with open(path, "r", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            truth[int(row["frame"])] = (float(row["cx"]), float(row["cy"]))
    return truth


def read_clip(path):
    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        raise RuntimeError("打不开视频: %s" % path)
    grays = []
    while True:
        ok, f = cap.read()
        if not ok:
            break
        grays.append(to_gray(f))
    cap.release()
    return grays


def main():
    ap = argparse.ArgumentParser(description="PS 侧黄金参考（含三路差分对照）")
    ap.add_argument("--clip", default=os.path.join(ROOT, "data", "golden", "synth_720p.avi"))
    ap.add_argument("--truth", default=os.path.join(ROOT, "data", "golden",
                                                    "synth_720p_groundtruth.csv"))
    ap.add_argument("--out-csv", default=os.path.join(ROOT, "data", "golden",
                                                      "synth_720p_golden.csv"))
    ap.add_argument("--thresh", type=int, default=THRESH)
    ap.add_argument("--kernel", type=int, default=KERNEL)
    args = ap.parse_args()

    for p in (args.clip, args.truth):
        if not os.path.exists(p):
            print("找不到输入: %s" % p)
            print("请先运行 data/golden/make_test_clip.py 生成测试片段。")
            return 1

    grays = read_clip(args.clip)
    truth = read_truth(args.truth)
    print("输入视频 : %s" % os.path.basename(args.clip))
    print("分辨率   : %d x %d  帧数 %d" % (grays[0].shape[1], grays[0].shape[0], len(grays)))
    print("参数     : thresh=%d  kernel=%d" % (args.thresh, args.kernel))
    print()

    results = {}
    for name, fn, nbuf, desc in MODES:
        results[name] = fn(grays, args.thresh, args.kernel)

    n = len(grays)
    common = set(range(1, n - 1))
    for name in results:
        common &= set(results[name].keys())
    common = sorted(common)

    print("=" * 84)
    print("偏差对照（对全部三种模式都有效的共同帧区间：第 %d ~ %d 帧，共 %d 帧）"
          % (common[0], common[-1], len(common)))
    print("=" * 84)
    print("  %-13s %8s %8s %8s %8s  %s" %
          ("模式", "平均|Δx|", "最大|Δx|", "平均|Δy|", "最大|Δy|", "帧缓存"))
    print("  " + "-" * 80)
    summary = {}
    for name, fn, nbuf, desc in MODES:
        ex = [abs(results[name][t][0] - truth[t][0]) for t in common if t in truth]
        ey = [abs(results[name][t][1] - truth[t][1]) for t in common if t in truth]
        if not ex:
            continue
        summary[name] = (np.mean(ex), np.max(ex), np.mean(ey), np.max(ey), nbuf)
        print("  %-13s %8.2f %8.2f %8.2f %8.2f  %d" % (name, np.mean(ex), np.max(ex),
                                                        np.mean(ey), np.max(ey), nbuf))
    print()
    for name, fn, nbuf, desc in MODES:
        print("  %-13s %s" % (name, desc))

    print()
    print("=" * 84)
    print("逐帧抽样（第 1/2/3 帧 与 最后 2 帧）")
    print("=" * 84)
    sample = common[:3] + common[-2:]
    print("  %5s %22s %14s %14s %14s" % ("帧", "真值(cx,cy)", "framediff", "gap2", "compensated"))
    for t in sample:
        if t not in truth:
            continue
        cells = []
        for name, fn, nbuf, desc in MODES:
            c = results[name].get(t)
            cells.append("(%.1f,%.1f)" % c if c else "  --  ")
        print("  %5d (%8.1f,%8.1f) %14s %14s %14s"
              % (t, truth[t][0], truth[t][1], cells[0], cells[1], cells[2]))

    with open(args.out_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["frame", "cx_truth", "cy_truth"] +
                   [c for name, _, _, _ in MODES for c in ("cx_" + name, "cy_" + name)])
        for t in sorted(set(common) | {k for r in results.values() for k in r}):
            row = ["%d" % t]
            tv = truth.get(t)
            row += ["%.2f" % tv[0], "%.2f" % tv[1]] if tv else ["", ""]
            for name, _, _, _ in MODES:
                c = results[name].get(t)
                row += ["%.2f" % c[0], "%.2f" % c[1]] if c else ["", ""]
            w.writerow(row)
    print()
    print("逐帧结果已写出: %s" % args.out_csv)
    return 0


if __name__ == "__main__":
    sys.exit(main())
