# -*- coding: utf-8 -*-
"""只换第 2 步 —— 在 CDnet 真实素材上对照「帧差法」与「背景建模」。

为什么需要它
------------
参考作品 #1（同题目往届）的算法本体是**帧差法**：它缓存的「背景帧」就是
**上一帧**，所谓「背景重建」只是把缓存帧先压缩再展开的省 BRAM 技巧。
所以它的检测质量上限就是帧差法的上限。本脚本把这件事变成数字。

它做什么
--------
五步链：灰度 → 第2步(差分) → 阈值 → 形态学去噪 → 质心/包围盒。
本脚本**只改第 2 步**，其余四步一字不动：

    framediff : |I(t) − I(t−1)|                    ← 参考作品 #1 的算法
    bgmodel   : |I(t) − B(t)|，B ← αI + (1−α)B     ← 唯一的差别

压缩档也照抄 #1 的思路（2×2 累加压缩，640×480 → 320×240），
阈值同样取它硬编码的 70（在 2×2 和域上；≈ 每像素 17.5 灰阶），
这样"改一处"的对照才是干净的。

★ CDnet 评分规矩（与 cdnet_demo.py 一致）
----------------------------------------
只用 temporalROI 区间内的帧计分；真值只取 0(静态)/255(运动)，
50 阴影 / 85 ROI 外 / 170 不确定 一律排除。
背景模型允许用 ROI 之前的帧预热（不计分），否则开局几百帧是在罚初始化。

用法
----
  python algo_ab.py                      # 两个序列都跑
  python algo_ab.py --seq canoe --frames 200
  python algo_ab.py --sweep              # 顺带扫一遍 α
"""

import argparse
import csv
import os
import sys

import numpy as np
import cv2
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "DejaVu Sans"]
plt.rcParams["axes.unicode_minus"] = False

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cdnet_demo as cd          # noqa: E402  复用 ROI 读取 / 指标 的规矩

SEQ = {
    "pedestrians": r"D:\FPGA\datasets\cdnet2014\baseline\pedestrians",
    "canoe": r"D:\FPGA\datasets\cdnet2014\dynamicBackground\canoe",
}

THRESH_REF1 = 70     # 参考作品 #1 里硬编码的阈值（2×2 和域）
KSIZE = 3            # 形态学核边长


# --------------------------------------------------------------------------
# 第 1 步（等价于 #1 的累加压缩 + 灰度）：2×2 求和，640×480 → 320×240，10bit
# --------------------------------------------------------------------------
def compress2x2(gray):
    g = gray.astype(np.uint16)
    h, w = g.shape
    return g[:h - h % 2, :w - w % 2].reshape(h // 2, 2, w // 2, 2).sum(axis=(1, 3))


def expand2x2(m):
    return np.repeat(np.repeat(m, 2, axis=0), 2, axis=1)


# --------------------------------------------------------------------------
# 第 2 步：唯一的差别就在这里
# --------------------------------------------------------------------------
def step2_framediff(cur, prev):
    return cur.astype(np.int32) - prev.astype(np.int32)


def step2_bgmodel(cur, bg):
    return cur.astype(np.int32) - bg.astype(np.int32)


def update_bg(bg, cur, alpha):
    return (alpha * cur.astype(np.float32) + (1.0 - alpha) * bg)


# --------------------------------------------------------------------------
# 第 3~5 步（两个算法共用，一字不动）
# --------------------------------------------------------------------------
def step3_threshold(diff, thresh):
    return (np.abs(diff) > thresh).astype(np.uint8)


def step4_denoise(mask, ksize):
    k = np.ones((ksize, ksize), np.uint8)
    m = cv2.morphologyEx(mask * 255, cv2.MORPH_OPEN, k)
    return (m > 0).astype(np.uint8)


def step5_box(mask, ratio=0.02):
    """质心 + 包围盒：找最大的连通域，返回 (质心, box) 或 (None, None)。"""
    if mask.sum() == 0:
        return None, None
    n, lbl, stats, cents = cv2.connectedComponentsWithStats(mask, 8)
    if n <= 1:
        return None, None
    areas = stats[1:, cv2.CC_STAT_AREA]
    big = int(np.argmax(areas)) + 1
    if areas[big - 1] < mask.size * ratio:
        return None, None
    x, y, w, h = (stats[big, cv2.CC_STAT_LEFT], stats[big, cv2.CC_STAT_TOP],
                  stats[big, cv2.CC_STAT_WIDTH], stats[big, cv2.CC_STAT_HEIGHT])
    return (float(cents[big][0]), float(cents[big][1])), (x, y, x + w, y + h)


# --------------------------------------------------------------------------
def run_seq(seqdir, frames=0, warmup=100, alpha=0.02, ksize=KSIZE):
    name = os.path.basename(seqdir)
    roi = cd.read_roi(seqdir)
    assert roi, "缺 temporalROI.txt：%s" % seqdir
    r0, r1 = roi
    first = max(1, r0 - warmup)
    count = frames if frames > 0 else (r1 - r0 + 1)

    grays, labels, names = cd.load_seq(seqdir, first, count + (r0 - first))
    # 把"预热帧 + 计分帧"切开
    nw = r0 - first
    c2 = [compress2x2(g) for g in grays]

    out = {}
    for mode in ("framediff", "bgmodel"):
        bg = c2[0].astype(np.float32)
        rows = []
        for t in range(1, len(c2)):
            if mode == "framediff":
                d = step2_framediff(c2[t], c2[t - 1])
            else:
                d = step2_bgmodel(c2[t], bg)
            m = step4_denoise(step3_threshold(d, THRESH_REF1), ksize)
            bg = update_bg(bg, c2[t], alpha)
            if t >= nw:
                pred = expand2x2(m)[:labels[t].shape[0], :labels[t].shape[1]]
                if pred.shape != labels[t].shape:
                    pred = np.zeros_like(labels[t])
                rows.append(cd.metrics(labels[t], pred))
        out[mode] = rows
    return name, roi, (first, nw), out


def summarize(rows):
    return tuple(float(np.mean([r[i] for r in rows])) for i in range(3))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seq", default="both", choices=["both", "pedestrians", "canoe"])
    ap.add_argument("--frames", type=int, default=0)
    ap.add_argument("--alpha", type=float, default=0.02)
    ap.add_argument("--sweep", action="store_true")
    args = ap.parse_args()

    targets = list(SEQ) if args.seq == "both" else [args.seq]
    print("阈值 = %d（照抄参考作品 #1 的硬编码值，2×2 和域）｜形态学核 = %d"
          % (THRESH_REF1, KSIZE))
    print()

    summary_rows = []
    for nm in targets:
        name, roi, (first, nw), out = run_seq(SEQ[nm], args.frames, alpha=args.alpha)
        pf, rf, ff = summarize(out["framediff"])
        pb, rb, fb = summarize(out["bgmodel"])
        print("=" * 78)
        print("序列 %s   分辨率 640×480   temporalROI %d~%d   计分 %d 帧（预热 %d 帧）"
              % (name, roi[0], roi[1], len(out["framediff"]), nw))
        print("=" * 78)
        print("  %-26s %9s %9s %9s" % ("", "精确率", "召回率", "F1"))
        print("  %-26s %9.3f %9.3f %9.3f" % ("① 帧差法（#1 的算法）", pf, rf, ff))
        print("  %-26s %9.3f %9.3f %9.3f" % ("② 背景建模（只改第2步）", pb, rb, fb))
        print("  %-26s %9.3f %9.3f %9.3f" % ("差值 ②−①", pb - pf, rb - rf, fb - ff))
        print()
        summary_rows.append((name, pf, rf, ff, pb, rb, fb))

        if args.sweep and nm == targets[0]:
            print("  α 扫描（只改一个数，看它多敏感）:")
            print("     %-8s %9s %9s %9s" % ("α", "精确率", "召回率", "F1"))
            for a in (0.005, 0.01, 0.02, 0.05, 0.1):
                _, _, _, o = run_seq(SEQ[nm], args.frames, alpha=a)
                p, r, f = summarize(o["bgmodel"])
                print("     %-8.3f %9.3f %9.3f %9.3f" % (a, p, r, f))
            print()

    out_csv = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "algo_ab_summary.csv")
    with open(out_csv, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["seq", "fd_prec", "fd_rec", "fd_f1", "bg_prec", "bg_rec", "bg_f1",
                    "thresh", "ksize", "alpha"])
        for r in summary_rows:
            w.writerow([r[0]] + ["%.4f" % x for x in r[1:]] +
                       [THRESH_REF1, KSIZE, args.alpha])
    print("汇总已写出: %s" % out_csv)
    return 0


if __name__ == "__main__":
    sys.exit(main())
