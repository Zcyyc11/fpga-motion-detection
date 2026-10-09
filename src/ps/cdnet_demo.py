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
  本脚本直接收**单个序列目录**（含 input/ 与 groundtruth/），不读全局数据根 ——
  想按类别批量扫、算总成绩，请用 algo_lab.py / cdnet_official.py（那边有 --data-root）。

  可在仓库根目录给（Windows 路径含空格要加引号）：
  python src\\ps\\cdnet_demo.py --seq "E:\\我的数据\\cdnet2014\\dynamicBackground\\canoe"
  python src\\ps\\cdnet_demo.py --seq <序列目录> --frames 150 --thresh 25 --kernel 3
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
import cdnet_io as cio           # noqa: E402  唯一的数据读取/校验实现

# ★ 读图与校验**只有 cdnet_io 一份实现**。以前各脚本自己写一份，于是同一个
#   "数据不全"的问题在四个入口上有四种表现：静默算错分 / 填零图 / 跳帧错位 /
#   IndexError。现在一律转过去。
imread = cio.imread
read_roi = cio.read_roi
load_seq = cio.load_seq
DataError = cio.DataError


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
    ap.add_argument("--start", type=int, default=0,
                    help="读取起始帧号(1基)，0=ROI 起点；首帧只作帧差参考，ROI 前不计分")
    ap.add_argument("--frames", type=int, default=0,
                    help="最多读取多少帧（含参考帧和预热），0=读到 ROI 终点；始终截到 ROI 终点")
    ap.add_argument("--thresh", type=int, default=gr.THRESH)
    ap.add_argument("--kernel", type=int, default=gr.KERNEL)
    args = ap.parse_args()
    if args.start < 0 or args.frames < 0:
        ap.error("--start 和 --frames 必须 >= 0")

    seqdir = os.path.abspath(args.seq)
    name = os.path.basename(seqdir)
    try:
        roi = read_roi(seqdir)
        first = args.start if args.start > 0 else roi[0]
        nwarm = max(0, roi[0] - first)
        last = min(roi[1], first + args.frames - 1) if args.frames else roi[1]
        count = last - first + 1
        score_first = max(1, nwarm)
        if count <= score_first:
            raise cio.DataError("没有可计分帧：需要 ROI 内的目标帧及其前一帧；"
                                "请减小 --start 或增加 --frames")
        grays, labels, names = load_seq(seqdir, first, count, nwarm=nwarm)
    except cio.DataError as e:
        sys.stderr.write("\n[数据不可用] %s\n\n" % e)
        return 1
    print("序列     : %s" % name)
    print("目录     : %s" % seqdir)
    print("分辨率   : %d x %d" % (grays[0].shape[1], grays[0].shape[0]))
    print("temporalROI: %d~%d   ->  本次用第 %d ~ %d 帧，共 %d 帧（预热 %d）"
          % (roi[0], roi[1], first, first + len(grays) - 1, len(grays), nwarm))
    print("参数     : thresh=%d  kernel=%d" % (args.thresh, args.kernel))

    lbl = np.unique(np.concatenate([l.ravel() for l in labels]))
    print("真值标签 : %s" % ", ".join(str(int(v)) for v in lbl))
    print()

    rows = []
    score_indices = list(range(score_first, len(grays)))
    for t in score_indices:
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
    good = [i for i in score_indices if labels[i].astype(int).max() >= 255]
    pick = good[len(good) // 2] if good else score_indices[len(score_indices) // 2]
    img = cv2.cvtColor(cio.imread(os.path.join(seqdir, "input", names[pick])),
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
