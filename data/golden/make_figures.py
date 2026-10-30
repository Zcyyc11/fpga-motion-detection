# -*- coding: utf-8 -*-
"""把黄金参考的结论画成图 —— 让"偏差 8 像素"肉眼可见，而不是只给一个数。

产出三张图（都放在本目录）：
  fig_overlay.png  单个帧的局部放大：真值框、两条帧差细带、三种模式各自算出的中心
  fig_error.png    逐帧偏差曲线：framediff 恒定 -8 像素，gap2 / compensated 压在 0
  fig_strip.png    时序条带：同一竖直带按时间从上到下排列，直接看出"每帧右移 16 像素"

复用 src/ps/golden_ref.py 的算子（import 而不重写），保证图与结论出自同一套代码。
"""

import csv
import os
import sys

import numpy as np
import cv2
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "DejaVu Sans"]
plt.rcParams["axes.unicode_minus"] = False

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "src", "ps"))
import golden_ref as gr          # noqa: E402

CLIP = os.path.join(HERE, "synth_720p.avi")
TRUTH = os.path.join(HERE, "synth_720p_groundtruth.csv")

C_TRUTH = "#2E7D32"    # 真值
C_VAC = "#1565C0"      # 已腾空细带
C_NEW = "#EF9F27"      # 新覆盖细带
C_BAD = "#C62828"      # 基线（有偏）
C_GOOD = "#00838F"     # 改进（无偏）


def load_all():
    grays = gr.read_clip(CLIP)
    boxes = {}
    with open(TRUTH, "r", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            boxes[int(r["frame"])] = (float(r["x"]), float(r["y"]),
                                      float(r["w"]), float(r["h"]),
                                      float(r["cx"]), float(r["cy"]))
    res = {
        "framediff": gr.run_framediff(grays, gr.THRESH, gr.KERNEL),
        "gap2": gr.run_gap2(grays, gr.THRESH, gr.KERNEL),
        "compensated": gr.run_compensated(grays, gr.THRESH, gr.KERNEL),
    }
    return grays, boxes, res


def fig_overlay(grays, boxes, res, t):
    """局部放大：把"两条细带"和"三个中心"画在一起。"""
    g_prev, g_cur = grays[t - 1], grays[t]
    mask = gr.motion_mask(g_prev, g_cur, gr.THRESH, gr.KERNEL)

    sd = g_cur.astype(np.int16) - g_prev.astype(np.int16)
    vac = (mask > 0) & (sd < -gr.THRESH)     # 物体曾经占据、现已腾空
    new = (mask > 0) & (sd > gr.THRESH)      # 物体新覆盖

    x, y, w, h, cx_t, cy_t = boxes[t]
    fd = res["framediff"][t]
    cp = res["compensated"][t]

    fig, ax = plt.subplots(figsize=(7.6, 5.0), dpi=140)
    ax.imshow(g_cur, cmap="gray", vmin=0, vmax=255)

    rgba = np.zeros((g_cur.shape[0], g_cur.shape[1], 4), np.uint8)
    rgba[vac] = matplotlib.colors.to_rgba(C_VAC, 0.85)
    rgba[new] = matplotlib.colors.to_rgba(C_NEW, 0.85)
    ax.imshow(rgba)

    ax.add_patch(Rectangle((x, y), w - 1, h - 1, fill=False, edgecolor=C_TRUTH,
                           lw=1.6, ls="--", label="物体真实位置（真值）"))
    ax.plot([cx_t], [cy_t], marker="+", ms=16, mew=2.4, color=C_TRUTH)
    ax.plot([fd[0]], [fd[1]], marker="x", ms=12, mew=2.6, color=C_BAD,
            label="framediff 算出的中心（偏左 8 px）")
    ax.plot([cp[0]], [cp[1]], marker="o", ms=11, mfc="none", mew=2.4, color=C_GOOD,
            label="compensated 算出的中心（与真值重合）")

    ax.annotate("", xy=(cx_t, cy_t - 34), xytext=(fd[0], cy_t - 34),
                arrowprops=dict(arrowstyle="<->", color=C_BAD, lw=1.6))
    ax.text((cx_t + fd[0]) / 2.0, cy_t - 42, "偏 8 px = d/2", color=C_BAD,
            ha="center", va="bottom", fontsize=11)

    ax.text(0.5, -0.24, "蓝色 = 物体曾经占据、现已腾空　橙色 = 物体新覆盖",
            transform=ax.transAxes, ha="center", fontsize=11, color="#444441")
    ax.text(0.5, -0.34, "帧差得到的是这两条细带，不是物体本身 —— 取它们合并外接框的中心，自然就滞后了",
            transform=ax.transAxes, ha="center", fontsize=11, color="#444441")

    ax.set_xlim(x - 70, x + w + 70)
    ax.set_ylim(y + h + 45, y - 45)
    ax.set_title("第 %d 帧（放大）：为什么基线会偏 8 像素" % t, fontsize=13)
    ax.set_xticks([]); ax.set_yticks([])
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.08), ncol=3,
              fontsize=9.5, frameon=False)
    fig.tight_layout()
    p = os.path.join(HERE, "fig_overlay.png")
    fig.savefig(p, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    return p


def fig_error(boxes, res):
    """逐帧偏差曲线。"""
    n = len(boxes)
    frames = [t for t in range(1, n - 1)
              if all(t in res[m] for m in res) and t in boxes]
    fig, ax = plt.subplots(figsize=(7.6, 3.8), dpi=140)

    styles = [("framediff", C_BAD, "-", "o", "framediff（基线）"),
              ("gap2", "#6A1B9A", "--", "s", "gap2（\u007cI(t+1)−I(t−1)\u007c）"),
              ("compensated", C_GOOD, "-", "^", "compensated（1 帧差分 + 补偿）")]
    for key, color, ls, mk, label in styles:
        dy = [res[key][t][0] - boxes[t][4] for t in frames]
        ax.plot(frames, dy, ls, color=color, lw=1.8, marker=mk, ms=4.5,
                mfc="none", label=label)

    ax.axhline(0, color="#B4B2A9", lw=0.8)
    ax.axhline(-8, color=C_BAD, lw=0.8, ls=":")
    ax.text(frames[-1], -8, "  −8 px  (= d/2, d=16)", color=C_BAD,
            va="center", ha="left", fontsize=10)
    ax.set_xlabel("帧号", fontsize=11)
    ax.set_ylabel("外接框中心 x 方向偏差（像素）", fontsize=11)
    ax.set_title("逐帧偏差：基线恒定偏 −8 像素，两种改法都压在 0", fontsize=13)
    ax.set_ylim(-11, 3)
    ax.set_xlim(frames[0] - 1, frames[-1] + 14)
    ax.legend(fontsize=9.5, frameon=False, loc="lower right")
    ax.grid(alpha=0.18)
    fig.tight_layout()
    p = os.path.join(HERE, "fig_error.png")
    fig.savefig(p, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    return p


def fig_strip(grays, boxes):
    """时序条带：取一条水平带，按时间从上到下排列。"""
    ys, ye = 292, 428          # 竖直截取范围（覆盖物体高度）
    picks = [0, 12, 24, 36, 48, 59]
    band_h = ye - ys
    canvas = np.zeros((band_h * len(picks), grays[0].shape[1]), np.uint8)
    for i, t in enumerate(picks):
        canvas[i * band_h:(i + 1) * band_h] = grays[t][ys:ye]

    fig, ax = plt.subplots(figsize=(7.6, 4.0), dpi=140)
    ax.imshow(canvas, cmap="gray", vmin=0, vmax=255)
    for i, t in enumerate(picks):
        x, y, w, h, cx_t, cy_t = boxes[t]
        yy = i * band_h + (y - ys)
        ax.add_patch(Rectangle((x, yy), w - 1, h - 1, fill=False,
                               edgecolor=C_TRUTH, lw=1.0, ls="--"))
        ax.text(-8, i * band_h + band_h / 2.0, "第 %d 帧" % t, color="#2C2C2A",
                ha="right", va="center", fontsize=10)
    ax.set_title("测试片段时序条带：每帧右移 16 像素（虚线 = 真值框）", fontsize=13)
    ax.set_xticks([]); ax.set_yticks([])
    ax.set_xlim(-95, canvas.shape[1])
    fig.tight_layout()
    p = os.path.join(HERE, "fig_strip.png")
    fig.savefig(p, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    return p


def main():
    grays, boxes, res = load_all()
    print("载入：%d 帧, %d x %d" % (len(grays), grays[0].shape[1], grays[0].shape[0]))
    for p in (fig_overlay(grays, boxes, res, 20),
              fig_error(boxes, res),
              fig_strip(grays, boxes)):
        print("  已生成 %s  (%d KB)" % (os.path.basename(p), os.path.getsize(p) // 1024))
    return 0


if __name__ == "__main__":
    sys.exit(main())
