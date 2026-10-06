# -*- coding: utf-8 -*-
"""在 CDnet 真实素材上跑帧差法，与人工真值逐像素比对 —— 看它到底崩成什么样。

为什么需要它
------------
合成片段只能验证"几何偏差"（我们自己造的，知道答案）。真实场景里的失效模式
（动态背景误检、慢速目标漏检、物体内部空洞）只有真实素材能暴露，
而且有逐像素真值 → 可以把"看着不行"变成可写进报告的数字。

★ CDnet 评分规矩（必须遵守，否则数字不可比）
--------------------------------------------
1. **只用 temporalROI 区间内的帧**（同目录 `temporalROI.txt` 给起止帧号，1 基）。
   区间外是开机预热/收尾，画面还没动，算进去等于刷分。
2. 真值标签共 5 种：0 静态 / 50 硬阴影 / 85 ROI 外 / 170 未知运动(半透明、运动模糊)
   / 255 运动。
   **只有"0 静态"与"255 运动"两种像素参与计分**；50/85/170 一律排除
   —— 阴影和"说不清"的像素不该拿来罚算法。

用法
----
  python cdnet_demo.py --seq <序列目录>
  python cdnet_demo.py --seq D:\\FPGA\\datasets\\cdnet2014\\dynamicBackground\\canoe
  python cdnet_demo.py --seq <序列目录> --frames 150 --thresh 25 --kernel 3
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
import golden_ref as gr          # noqa: E402


def read_roi(seqdir):
    """读 temporalROI.txt -> (起始帧, 结束帧)，1 基；没有则 None。"""
    p = os.path.join(seqdir, "temporalROI.txt")
    if not os.path.exists(p):
        return None
    txt = open(p).read().split()
    if len(txt) < 2:
        return None
    return int(txt[0]), int(txt[1])


def load_seq(seqdir, first, count):
    """读 input/*.jpg 与 groundtruth/*.png。first 为 1 基帧号，返回 (灰帧, 标签图, 文件名)。"""
    inp = os.path.join(seqdir, "input")
    names = sorted(os.listdir(inp))
    if not names:
        raise RuntimeError("input 目录为空: %s" % inp)
    sel = names[first - 1: first - 1 + count]
    grays, labels = [], []
    for n in sel:
        img = cv2.imread(os.path.join(inp, n))
        if img is None:
            continue
        grays.append(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY))
        gp = os.path.join(seqdir, "groundtruth",
                          n.replace("in", "gt").rsplit(".", 1)[0] + ".png")
        t = cv2.imread(gp, cv2.IMREAD_GRAYSCALE)
        labels.append(t if t is not None else np.zeros_like(grays[-1]))
    return grays, labels, sel


def metrics(label, pred):
    """按 CDnet 规矩算指标：只统计标签 0 与 255 的像素。"""
    valid = (label == 0) | (label >= 255)
    truth = label >= 255
    p = (pred > 0) & valid
    tp = int((p & truth).sum())
    fp = int((p & ~truth).sum())
    fn = int((~p & truth).sum())
    prec = tp / float(tp + fp) if (tp + fp) else 0.0
    rec = tp / float(tp + fn) if (tp + fn) else 0.0
    f1 = 2 * prec * rec / (prec + rec) if (prec + rec) else 0.0
    return prec, rec, f1, tp, fp, fn, int(truth.sum())


def main():
    ap = argparse.ArgumentParser(description="在 CDnet 真实素材上跑帧差法并比对真值")
    ap.add_argument("--seq", required=True, help="序列目录（含 input/ 与 groundtruth/）")
    ap.add_argument("--start", type=int, default=0, help="起始帧号(1基)，默认用 temporalROI 起点")
    ap.add_argument("--frames", type=int, default=0, help="处理多少帧，0=整个 ROI")
    ap.add_argument("--thresh", type=int, default=gr.THRESH)
    ap.add_argument("--kernel", type=int, default=gr.KERNEL)
    args = ap.parse_args()

    seqdir = os.path.abspath(args.seq)
    name = os.path.basename(seqdir)
    roi = read_roi(seqdir)
    first = args.start if args.start > 0 else (roi[0] if roi else 1)
    count = args.frames if args.frames > 0 else (roi[1] - first + 1 if roi else 150)

    grays, labels, names = load_seq(seqdir, first, count)
    print("序列     : %s" % name)
    print("目录     : %s" % seqdir)
    print("分辨率   : %d x %d" % (grays[0].shape[1], grays[0].shape[0]))
    print("temporalROI: %s   ->  本次用第 %d ~ %d 帧，共 %d 帧"
          % ("%d~%d" % roi if roi else "(文件缺失)", first, first + len(grays) - 1, len(grays)))
    print("参数     : thresh=%d  kernel=%d" % (args.thresh, args.kernel))

    lbl = np.unique(np.concatenate([l.ravel() for l in labels]))
    print("真值标签 : %s" % ", ".join(str(int(v)) for v in lbl))
    print()

    rows = []
    for t in range(1, len(grays)):
        pred = gr.motion_mask(grays[t - 1], grays[t], args.thresh, args.kernel)
        m = metrics(labels[t], pred)
        rows.append((first + t, m))

    print("=" * 78)
    print("帧差法 vs 人工真值")
    print("=" * 78)
    print("  %-16s %9s %9s %9s" % ("指标", "平均", "最差", "最好"))
    for tag, idx in (("精确率 precision", 0), ("召回率 recall", 1), ("F1", 2)):
        v = [r[1][idx] for r in rows]
        print("  %-16s %9.3f %9.3f %9.3f" % (tag, np.mean(v), np.min(v), np.max(v)))
    fps = [r[1][4] for r in rows]
    fns = [r[1][5] for r in rows]
    trs = [r[1][6] for r in rows]
    print("  %-16s %9.0f %9.0f %9.0f" % ("误检像素数", np.mean(fps), np.min(fps), np.max(fps)))
    print("  %-16s %9.0f %9.0f %9.0f" % ("漏检像素数", np.mean(fns), np.min(fns), np.max(fns)))
    print("  %-16s %9.0f %9.0f %9.0f" % ("真值运动像素", np.mean(trs), np.min(trs), np.max(trs)))

    # --------- 对比图：挑一个真值里确实有运动的帧 ---------
    good = [i for i in range(1, len(grays)) if labels[i].astype(int).max() >= 255]
    pick = good[len(good) // 2] if good else len(grays) // 2
    img = cv2.cvtColor(cv2.imread(os.path.join(seqdir, "input", names[pick])),
                       cv2.COLOR_BGR2RGB)
    label = labels[pick]
    pred = gr.motion_mask(grays[pick - 1], grays[pick], args.thresh, args.kernel)
    valid = (label == 0) | (label >= 255)
    p = (pred > 0) & valid
    truth = label >= 255
    tp = p & truth
    fp = p & ~truth
    fn = (~p) & truth

    def tint(base, mask, color, amount=0.7):
        out = base.copy()
        m = mask > 0
        for c in range(3):
            ch = out[:, :, c]
            ch[m] = ((1 - amount) * ch[m] + amount * color[c]).astype(np.uint8)
        return out

    fig, axes = plt.subplots(1, 3, figsize=(11.6, 3.2), dpi=140)
    axes[0].imshow(img)
    axes[0].set_title("① 真实画面（第 %d 帧）" % (first + pick), fontsize=12)
    t2 = img.copy()
    t2 = tint(t2, label == 50, np.array([80, 130, 240]), 0.55)
    t2 = tint(t2, label == 170, np.array([200, 170, 60]), 0.45)
    t2 = tint(t2, truth, np.array([220, 60, 60]), 0.75)
    axes[1].imshow(t2)
    axes[1].set_title("② 正确答案", fontsize=12)
    p2 = img.copy()
    p2 = tint(p2, tp, np.array([60, 175, 95]), 0.7)
    p2 = tint(p2, fp, np.array([230, 40, 40]), 0.65)
    p2 = tint(p2, fn, np.array([235, 195, 40]), 0.6)
    axes[2].imshow(p2)
    prec, rec, f1 = metrics(label, pred)[:3]
    axes[2].set_title("③ 帧差法结果", fontsize=12)
    for ax in axes:
        ax.set_xticks([]); ax.set_yticks([])
    fig.suptitle("%s —— 本帧 精确率 %.2f / 召回率 %.2f / F1 %.2f" % (name, prec, rec, f1),
                 fontsize=13)
    fig.text(0.5, -0.04,
             "② 红=运动(计分)  蓝=硬阴影(不计分)  黄=不确定运动(不计分)　｜　"
             "③ 绿=命中  红=误检  黄=漏检",
             ha="center", fontsize=10.5, color="#444441")
    fig.tight_layout()
    figp = os.path.join(seqdir, "cdnet_demo_fig.png")
    fig.savefig(figp, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print("\n对比图已写出: %s" % figp)

    csvp = os.path.join(seqdir, "cdnet_demo_metrics.csv")
    with open(csvp, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["frame", "precision", "recall", "f1", "tp", "fp", "fn", "truth_px"])
        for fr, m in rows:
            w.writerow(["%d" % fr] + ["%.4f" % x for x in m[:3]] + ["%d" % x for x in m[3:]])
    print("逐帧指标已写出: %s" % csvp)
    return 0


if __name__ == "__main__":
    sys.exit(main())
