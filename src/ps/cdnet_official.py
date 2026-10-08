# -*- coding: utf-8 -*-
"""用 CDnet 官方口径打分 —— 与论文可比的那把尺子。

为什么要单独一个文件
--------------------
`algo_lab.py` 报的是 **逐帧平均 F1**（先把每一帧算一个分、再对帧求平均）。
CDnet 官方（以及几乎所有论文）用的是 **整段汇总**：把整个 ROI 区间的
TP / FP / FN 先各自累加，再算一次 P / R / F1；然后**每个类别取类内平均**，
**总成绩取各类别平均**。

两者同名不同尺：逐帧平均会被"真值里几乎没目标的帧"严重拉低。
**本文件用官方口径重算，让我们的数字能和论文放一起比。**

用法
----
  python cdnet_official.py                # 全部序列 × 四档代表变体
  python cdnet_official.py --seq all
"""

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cdnet_demo as cd          # noqa: E402
import algo_lab as lab           # noqa: E402  复用**唯一**的流水线 frame_metrics


def score(rows):
    """返回 (逐帧平均 F1, 官方汇总口径的 P/R/F1)。"""
    if not rows:
        return 0.0, (0.0, 0.0, 0.0)
    pf = float(np.mean([r[2] for r in rows]))
    tp = sum(r[3] for r in rows)
    fp = sum(r[4] for r in rows)
    fn = sum(r[5] for r in rows)
    p = tp / float(tp + fp) if (tp + fp) else 0.0
    r_ = tp / float(tp + fn) if (tp + fn) else 0.0
    f1 = 2 * p * r_ / (p + r_) if (p + r_) else 0.0
    return pf, (p, r_, f1)


CANDS = [lab.V0, lab.V4, lab.V7, lab.V10, lab.V11, lab.V12]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seq", default="all")
    ap.add_argument("--frames", type=int, default=0)
    ap.add_argument("--set", default="", help="用 algo_lab 里的变体集名（如 r5）；默认用 CANDS")
    args = ap.parse_args()

    cands = lab.SETS[args.set] if args.set else CANDS
    allseq = lab.discover()
    if not allseq:
        # ★ 别静默输出一张空表 —— 那会让队友以为是算法坏了，其实是数据没到位
        lab.print_no_data_hint()
        return 1
    keys = sorted(allseq) if args.seq == "all" else \
        [lab.ALIAS.get(s.strip(), s.strip()) for s in args.seq.split(",") if s.strip()]

    print("=" * 98)
    print("CDnet 官方口径（整段汇总 + 类别平均）｜ ★ = 该序列在官方口径下的最佳变体")
    print("=" * 98)
    per_cat = {}          # label -> {cat: [f1...]}
    rows_csv = []
    for nm in keys:
        cat = nm.split("/")[0]
        roi, nw, grays, c2, labels = lab.load_cached(allseq[nm], frames=args.frames)
        print("\n### %s  (ROI %d~%d, 计分 %d 帧)" % (nm, roi[0], roi[1], len(c2) - nw))
        print("  %-32s %10s | %9s %9s %9s" % ("变体", "逐帧平均F1", "P(汇总)", "R(汇总)", "F1(汇总)"))
        print("  " + "-" * 78)
        best = None
        for label, cfg in cands:
            pf, (p, r_, f1) = score(lab.frame_metrics(c2, labels, nw, cfg))
            if best is None or f1 > best[1]:
                best = (label, f1)
            print("  %-32s %10.3f | %9.3f %9.3f %9.3f" % (label, pf, p, r_, f1))
            per_cat.setdefault(label, {}).setdefault(cat, []).append(f1)
            rows_csv.append([nm, label, "%.4f" % pf, "%.4f" % f1])
        print("  → 官方口径最佳: %s (%.3f)" % (best[0], best[1]))
        sys.stdout.flush()

    print("\n" + "=" * 98)
    print("★ 总成绩（官方口径 = 先按类别平均，再对类别平均）")
    print("=" * 98)
    cats = sorted({c for d in per_cat.values() for c in d})
    print("  %-32s %s %9s" % ("变体", " ".join("%10s" % c[:10] for c in cats), "总成绩"))
    for label, _ in cands:
        d = per_cat.get(label, {})
        catvals = [float(np.mean(d[c])) for c in cats if c in d]
        tot = float(np.mean(catvals)) if catvals else 0.0
        print("  %-32s %s %9.3f"
              % (label, " ".join(("%10.3f" % float(np.mean(d[c]))) if c in d else "         -"
                                 for c in cats), tot))

    suffix = ("_" + args.set) if args.set else ""
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "cdnet_official_results%s.csv" % suffix)
    with open(out, "w", newline="", encoding="utf-8") as f:
        f.write("seq,variant,perframe_f1,official_f1\n")
        for r in rows_csv:
            f.write(",".join(r) + "\n")
    print("\n结果已写出: %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
