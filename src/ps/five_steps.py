# -*- coding: utf-8 -*-
"""把「五步链只换第 2 步」画出来 —— 逐级中间图对照。

上排 = 帧差法（参考作品 #1 的算法本体）
下排 = 背景建模（只改第 2 步，其余四步一字不动）

五步：灰度 → 第2步差分 → 阈值 → 形态学去噪 → 质心/包围盒
输出：data/golden/five_steps_framediff_vs_bg.png

用法：
  python five_steps.py --seq canoe --frame 950
  python five_steps.py --seq pedestrians --frame 500
"""

import argparse
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
import cdnet_demo as cd            # noqa: E402
import algo_ab as ab               # noqa: E402
import cdnet_io as cio             # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "..", "data", "golden")


def overlay(bgr, mask, color=(60, 175, 95), amount=0.75):
    out = bgr.copy().astype(np.float32)
    m = mask > 0
    for c in range(3):
        out[:, :, c][m] = (1 - amount) * out[:, :, c][m] + amount * color[c]
    return out.astype(np.uint8)


def main():
    ap = argparse.ArgumentParser()
    ab.lab.add_data_root_arg(ap)     # ← 与其它评测入口同一套解析
    ap.add_argument("--seq", default="canoe",
                    help="pedestrians 或 canoe（★ 需要 CDnet 数据集）")
    ap.add_argument("--frame", type=int, default=0, help="1 基帧号；0=自动挑一个")
    ap.add_argument("--alpha", type=float, default=0.005)
    ap.add_argument("--warmup", type=int, default=100,
                    help="最多预热多少帧（至少 1）；不足时缩短到第 1 帧")
    args = ap.parse_args()
    if args.frame < 0:
        ap.error("--frame 必须 >= 0（0 表示自动选择）")
    if args.warmup < 1:
        ap.error("--warmup 必须 >= 1，帧差法需要目标帧的前一帧")

    # ★ 以前这里写 choices=list(ab.SEQ)，而 ab.SEQ 要等 algo_ab.main() 跑起来才填，
    #   导入期它是**空表** ⇒ argparse 一律报"invalid choice"，退出码 2。
    #   也就是说这条入口从来就没真正跑通过，只是没人发现。
    #   现在改成先解析数据根、再自己校验序列名。
    try:
        root, src = ab.lab.resolve_data_root(args.data_root)
        seqs = ab.resolve_seq_dir(root)
        ab.lab.describe_data_root(root, src)
    except ab.lab.DataRootError as e:
        sys.stderr.write("\n[数据未就绪] %s\n\n" % e)
        return 1
    if args.seq not in seqs:
        sys.stderr.write("\n[数据未就绪] 没有序列 %r，可选：%s\n\n"
                         % (args.seq, "、".join(sorted(seqs))))
        return 1
    seqdir = seqs[args.seq]
    try:
        roi = cio.read_roi(seqdir)
        target = args.frame or (roi[0] + roi[1]) // 2
        if target < 2:
            raise cio.DataError("目标帧必须 >= 2：第 1 帧没有前一帧，无法计算帧差")
        first = max(1, target - args.warmup)
        nwarm = target - first
        # 只有最后一帧是"目标帧"，前面的都是预热帧 —— 预热帧允许没有真值。
        grays, labels, names = cio.load_seq(seqdir, first, nwarm + 1, nwarm=nwarm)
        bgr = cio.imread(os.path.join(seqdir, "input", names[-1]))
    except cio.DataError as e:
        sys.stderr.write("\n[数据不可用] %s\n\n" % e)
        return 1
    n = len(grays) - 1
    g_cur, g_prev = grays[-1], grays[-2]

    c2 = [ab.compress2x2(g) for g in grays]
    bg = c2[0].astype(np.float32)
    for t in range(1, n):
        bg = ab.update_bg(bg, c2[t], args.alpha)

    panels = {}
    for mode in ("framediff", "bgmodel"):
        if mode == "framediff":
            d = ab.step2_framediff(c2[n], c2[n - 1])
        else:
            d = ab.step2_bgmodel(c2[n], bg)
        m3 = ab.step3_threshold(d, ab.THRESH_REF1)
        m4 = ab.step4_denoise(m3, ab.KSIZE)
        m4f = ab.expand2x2(m4)[:g_cur.shape[0], :g_cur.shape[1]]
        cen, box = ab.step5_box(m4f)
        panels[mode] = (np.abs(d), m3, m4, m4f, cen, box)

    fig, axes = plt.subplots(2, 5, figsize=(15.4, 6.4), dpi=130)
    titles = ["① 灰度（第 1 步）", "② 差分（第 2 步）", "③ 阈值（第 3 步）",
              "④ 去噪（第 4 步）", "⑤ 质心 + 包围盒（第 5 步）"]
    row_names = ["帧差法\n（参考作品 #1 的算法本体）", "背景建模\n（只改第 2 步，其余一字不动）"]

    for ri, mode in enumerate(("framediff", "bgmodel")):
        d, m3, m4, m4f, cen, box = panels[mode]
        dn = np.clip(d.astype(np.float32) / max(1, d.max()) * 255, 0, 255).astype(np.uint8)
        imgs = [g_cur, dn, m3 * 255, m4 * 255, None]
        for ci in range(5):
            ax = axes[ri][ci]
            if ci < 4:
                ax.imshow(imgs[ci], cmap="gray" if ci else None)
            else:
                pic = overlay(bgr, m4f)
                if box:
                    cv2.rectangle(pic, (box[0], box[1]), (box[2], box[3]),
                                  (255, 60, 60), 2)
                if cen:
                    cv2.drawMarker(pic, (int(cen[0]), int(cen[1])),
                                   (255, 255, 0), cv2.MARKER_CROSS, 18, 2)
                ax.imshow(cv2.cvtColor(pic, cv2.COLOR_BGR2RGB))
            if ri == 0:
                ax.set_title(titles[ci], fontsize=12)
            ax.set_xticks([]); ax.set_yticks([])
        axes[ri][0].set_ylabel(row_names[ri], fontsize=12.5, labelpad=12)

    fig.suptitle("%s 第 %d 帧 —— 五步链里只有第 2 步不同（背景模型 α=%.3f）"
                 % (args.seq, target, args.alpha), fontsize=14)
    fig.tight_layout()
    p = os.path.abspath(os.path.join(OUT, "five_steps_%s_f%d.png" % (args.seq, target)))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    fig.savefig(p, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print("已写出: %s" % p)
    for mode in ("framediff", "bgmodel"):
        m4f = panels[mode][3]
        print("  %-10s 前景像素 = %6d   质心 = %s   包围盒 = %s"
              % (mode, int(m4f.sum()), panels[mode][4], panels[mode][5]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
