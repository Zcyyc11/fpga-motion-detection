# -*- coding: utf-8 -*-
"""算法改进实验台 —— 在 CDnet 真实素材上批量试改进，逐帧量分（支持多场景横评）。

与 algo_ab.py 的分工
--------------------
algo_ab.py 只回答一个问题：**"把第 2 步从帧差换成背景建模，值多少分"**（一次对照）。
本脚本回答另一个问题：**"在背景建模之上，每加一处改进，分数动多少，且换场景还灵不灵"**。

全都保持与硬件链路同构（2×2 求和压缩 + 10bit 域 + 形态学），
每一处改进都对应一个**能在 FPGA 上落地的操作**，不做只能在 CPU 上跑的算法。

★★ 本文件是**唯一**的流水线实现（`frame_metrics`）；`cdnet_official.py` 复用同一个函数，
   不许再各抄一份 —— 否则两边口径会悄悄跑偏。

评分规矩与 cdnet_demo.py / algo_ab.py 完全一致：
只计 temporalROI 内、真值为 0(静态)/255(运动) 的像素；50/85/170 一律排除。

用法
----
  python algo_lab.py --list                 # 列出可用序列
  python algo_lab.py --seq all --set core   # 逐帧平均口径
  python algo_lab.py --seq all --set r5 --ref
"""

import argparse
import csv
import os
import sys
import time

import numpy as np
import cv2

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cdnet_demo as cd          # noqa: E402

# ★★ 数据根目录：**刻意不给默认值**。
#   原先这里硬编码 `D:\FPGA\datasets\cdnet2014` —— 换个机器/换个人跑就静默找不到数据，
#   而且"能跑但跑不出结果"最难查。现在按优先级解析，**没配就明确报错**：
#       1) 命令行   --data-root <目录>      （优先级最高）
#       2) 环境变量 CDNET_ROOT
#       3) 都没有   → 报错并说明怎么配（不猜、不静默）
#   数据集约 0.96 GB / 5.2 万个文件，**不进 git**（GitHub 单文件上限 100 MB），只能本地放置。
ENV_DATA_ROOT = "CDNET_ROOT"      # 环境变量名

ALIAS = {                       # 旧名字 -> 类别/序列
    "pedestrians": "baseline/pedestrians",
    "canoe": "dynamicBackground/canoe",
}

THRESH_REF1 = 70      # 参考作品 #1 硬编码阈值（2×2 和域）


class DataRootError(Exception):
    """数据根没配好 / 不存在 / 里没有序列。入口统一 catch 后返回**非零**退出码。"""


def add_data_root_arg(parser):
    """给 argparse 装上 --data-root。所有评测入口共用，避免各写一套。"""
    parser.add_argument(
        "--data-root", default=None,
        help="CDnet2014 数据根目录（指向**含类别目录**的那一级，"
             "里面是 baseline/ badWeather/ ...）。优先级高于环境变量 %s。"
             "支持中文与空格路径（shell 里记得加引号）。" % ENV_DATA_ROOT)
    return parser


def resolve_data_root(explicit=None):
    """解析最终的数据根目录。

    优先级：--data-root > 环境变量 CDNET_ROOT > 报错。
    返回 (绝对路径, 来源说明)。失败一律抛 DataRootError —— 绝不返回一个猜的路径。
    """
    if explicit is not None and str(explicit).strip():
        raw, src = str(explicit).strip(), "命令行 --data-root"
    else:
        raw = os.environ.get(ENV_DATA_ROOT, "").strip()
        src = "环境变量 %s" % ENV_DATA_ROOT if raw else ""

    if not raw:
        raise DataRootError(
            "没有指定 CDnet 数据根目录。**本项目刻意不给默认值**"
            "（这里曾经硬编码某个人的磁盘路径，换机器就静默跑不了）。\n"
            "  二选一：\n"
            "    1) 命令行：    python 本脚本.py --data-root \"D:\\我的数据\\cdnet2014\"\n"
            "    2) 环境变量：  set %s=D:\\我的数据\\cdnet2014\n"
            "  ★ 目录要指向**含类别目录**的那一级，结构应该是：\n"
            "        cdnet2014\\baseline\\highway\\temporalROI.txt\n"
            "                          \\input\\...\n"
            "                          \\groundtruth\\...\n"
            "  数据集约 0.96 GB / 5.2 万个文件，不进 git（GitHub 单文件上限 100 MB）。"
            % ENV_DATA_ROOT)

    # 支持 %VAR% 与 ~，再转绝对路径（相对路径随 cwd 变，最容易踩）
    root = os.path.abspath(os.path.expandvars(os.path.expanduser(raw)))

    if not os.path.isdir(root):
        raise DataRootError(
            "数据根目录不存在：%s\n  （来源：%s）\n"
            "  注意要指向**含类别目录**的那一级，不是它的子目录或上级目录。"
            % (root, src))
    return root, src


def describe_data_root(root, src):
    """按要求把'最终用了哪个目录、来源是什么'打出来。"""
    print("数据根目录：%s" % root)
    print("  来源：%s" % src)


# --------------------------------------------------------------------------
def discover(root):
    """扫出所有可用序列：<类别>/<序列> -> 目录。

    root 由 resolve_data_root() 给出，**刻意不给默认值** —— 免得调用方
    不小心悄悄用了一个猜测的路径。返回空字典表示"目录在但里面没有序列"，
    调用方必须自己判空并报错，不许当成"跑完了，0 条序列"。
    """
    out = {}
    for cat in sorted(os.listdir(root)):
        cpath = os.path.join(root, cat)
        if not os.path.isdir(cpath) or cat.startswith("_"):
            continue
        for seq in sorted(os.listdir(cpath)):
            sp = os.path.join(cpath, seq)
            if os.path.isfile(os.path.join(sp, "temporalROI.txt")):
                out["%s/%s" % (cat, seq)] = sp
    return out


def select_sequences(allseq, want):
    """按 --seq 选目标序列（"all" 或逗号分隔的 类别/序列，旧名走 ALIAS）。

    任何"点名了却不存在的序列"都直接抛错，**不静默跳过**。
    """
    if want == "all":
        return sorted(allseq)
    targets = []
    for raw in [s.strip() for s in want.split(",") if s.strip()]:
        key = ALIAS.get(raw, raw)
        if key not in allseq:
            raise DataRootError(
                "指定的序列不存在：%r\n  可用序列（%d 条）：\n    %s\n"
                "  用 --list 可以随时看这份列表。"
                % (raw, len(allseq), "\n    ".join(sorted(allseq))))
        targets.append(key)
    return targets


def no_sequence_error(root, src):
    """目录在、但里面没有可用序列。返回一个异常对象，交给入口统一报错退出。"""
    return DataRootError(
        "目录存在，但一个可用序列都没扫到：%s\n  （来源：%s）\n"
        "  一个序列要能被认出来，必须满足：\n"
        "      <root>\\<类别>\\<序列>\\temporalROI.txt     ← 这个文件是标志\n"
        "      <root>\\<类别>\\<序列>\\input\\...            ← 帧图\n"
        "      <root>\\<类别>\\<序列>\\groundtruth\\...      ← 真值\n"
        "  常见原因：① 指到了太深一层（应该是含类别目录的那一级）"
        "② 指到了父目录 ③ 数据集没解压完整。\n"
        "  没有数据集时仍可跑的：\n"
        "    · 跟踪与告警   python src/ps/multi_track.py --source algo --alarm --line-x 640\n"
        "    · RTL 仿真     python build/scripts/run_sim.py（需要 Vivado）\n"
        "    · 看已归档的评测结果：src/ps/cdnet_official_results*.csv（不需要数据集）"
        % (root, src))


def precheck_sequences(allseq, targets):
    """★ 跑之前先检查每条序列的**输入与真值**齐不齐。

    为什么必须提前查：
      · 缺 input/ 或 groundtruth/ → 会在跑一半时炸成一大段 Python traceback，
        队友根本看不出"是我数据没下全"；
      · 更隐蔽的是：真值图片读不出来时 cv2.imread 返回 None，旧代码**静默继续**，
        拿着 None 当标签算分 —— 不报错，但分数是错的。
    所以这里一次性把缺什么列清楚，然后抛错退出（退出码非 0）。
    """
    problems = []
    for nm in targets:
        d = allseq[nm]
        miss = []
        if not os.path.isfile(os.path.join(d, "temporalROI.txt")):
            miss.append("temporalROI.txt（缺失）")
        for sub, label in (("input", "input/"), ("groundtruth", "groundtruth/")):
            p = os.path.join(d, sub)
            if not os.path.isdir(p):
                miss.append("%s（缺失）" % label)
            elif not os.listdir(p):
                miss.append("%s（空目录）" % label)
        if miss:
            problems.append((nm, d, miss))
    if not problems:
        return
    lines = ["以下序列的数据不完整，跑不出可信的分数："]
    for nm, d, miss in problems:
        lines.append("  %s" % nm)
        lines.append("      目录：%s" % d)
        lines.append("      缺：%s" % "、".join(miss))
    lines += [
        "",
        "  CDnet2014 每条序列应该是这样的结构：",
        "      <序列>\\temporalROI.txt     ← 帧号区间",
        "              \\input\\*.jpg       ← 输入帧图",
        "              \\groundtruth\\*.png ← 真值图",
        "  多半是数据集没解压完整，或下载时漏了某个类别。",
        "  确认无误可先跑 `python src/ps/algo_lab.py --data-root \"...\" --list` 看看。",
    ]
    raise DataRootError("\n".join(lines))


# --------------------------------------------------------------------------
# 与硬件一致的 2×2 前缀
# --------------------------------------------------------------------------
def compress2x2(gray):
    g = gray.astype(np.uint16)
    h, w = g.shape
    return g[:h - h % 2, :w - w % 2].reshape(h // 2, 2, w // 2, 2).sum(axis=(1, 3))


def expand2x2(m):
    return np.repeat(np.repeat(m, 2, axis=0), 2, axis=1)


# --------------------------------------------------------------------------
# 后处理：全是 FPGA 上能做的（开/闭运算、按面积去小块）
# --------------------------------------------------------------------------
def post_mask(mask, cfg):
    if cfg.get("open", 0):
        k = np.ones((cfg["open"], cfg["open"]), np.uint8)
        mask = cv2.morphologyEx(mask * 255, cv2.MORPH_OPEN, k)
    if cfg.get("close", 0):
        k = np.ones((cfg["close"], cfg["close"]), np.uint8)
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, k)
    mask = (mask > 0).astype(np.uint8)
    thr_area = int(cfg.get("min_area", 0))
    if thr_area <= 0 and cfg.get("min_area_frac", 0.0) > 0:
        thr_area = int(mask.size * cfg["min_area_frac"])
    if thr_area > 0 and mask.any():
        n, lbl, stats, _ = cv2.connectedComponentsWithStats(mask, 8)
        for i in range(1, n):
            if stats[i, cv2.CC_STAT_AREA] < thr_area:
                mask[lbl == i] = 0
    return mask


# --------------------------------------------------------------------------
# ★ 唯一的流水线实现。返回逐帧的 cd.metrics 结果列表（不含预热帧）。
#
# cfg 可选项
#   alpha          背景学习率（背景侧）
#   init_frames    初始背景用**前 N 帧逐像素最小值**（默认 1 ＝ 旧行为：直接拿第 0 帧）。
#                  ★ 为什么要这个：第 0 帧里往往**就含着目标**，直接当背景会把目标“固化”进去，
#                    结果是物体内部永远不算前景、只在本体前后各留一条边带（大而慢的目标尤其明显）。
#                    硬件上“前 N 帧取最小”就是一个比较器 ＋ 一个寄存器，极便宜。
#   alpha_fg       前景侧学习率（>0 才有双速率；=0 表示前景冻结）
#   selective      是否只在"像背景"的像素上更新
#   gate           更新的判定门限（默认 = thresh）
#   thresh         绝对阈值（2×2 和域）
#   thresh_rel     相对阈值（Weber 型对比度）：差值 > thresh_rel × 分母 也算前景（对付暗场景）
#   rel_on         分母取谁：'bg'（默认·旧行为）| 'cur' | 'max'（max(I,B)）| 'local'（当前帧 3×3 均值）
#   thresh_floor   相对阈值的绝对下限（防止分母接近 0 时噪声全过）
#   shadow_ratio   (lo, hi) 灰度比值法阴影抑制
#   blur           对差值图做 k×k 均值平滑
#   gshift         全局运动补偿：在压缩域做 ±R 大像素的位移搜索（1/8 抽样估），
#                  找到使 |cur − roll(bg)| 最小的整帧平移，然后**只按该位移去读背景**。
#                  ★ 硬件同构：估位移用 1/8 抽样的小网格；补偿＝**帧缓存读地址加偏移**，
#                    **零额外存储**（不用第二张图）。这是文献里 cameraJitter 的正解。
#   adapt_rel      (rel_lo, rel_hi, frac_lo, frac_hi)：**按上一帧的前景占比自适应调相对阈值**。
#                  占比低（画面本来就干净/暗）→ 用 rel_lo（更敏感，救夜间）；
#                  占比高（整帧都在动＝镜头抖/大片误检）→ 用 rel_hi（更严，压住抖动噪声）。
#                  ★ 硬件极友好：占比＝包围盒那一路已有的 mask 计数 / 总大像素数，一个除法都不用。
#   hyst           (t_low, iters) 迟滞双阈值：d>thresh 为"强"，d>t_low 为"弱"；
#                  只有与强点连通（3×3 邻域，扩 iters 轮）的弱点才留下。
#                  FPGA 上就是已有的 3×3 窗口 + 两次比较，几乎零成本。
#   open/close/min_area/min_area_frac  形态学与面积滤波
# --------------------------------------------------------------------------
def frame_metrics(c2, labels, nw, cfg, collect=None):
    """collect 不为 None 时，逐帧把**最终掩码**追加进去（给多目标/跟踪当输入）。
    labels 传 None 表示只要掩码、不算分。"""
    init_n = max(1, int(cfg.get("init_frames", 1)))
    if init_n > 1:
        bg = np.minimum.reduce([c2[i].astype(np.float32)
                                for i in range(min(init_n, len(c2)))])
    else:
        bg = c2[0].astype(np.float32)
    a = float(cfg["alpha"])
    a_fg = float(cfg.get("alpha_fg", 0.0))
    thr = int(cfg["thresh"])
    thr_rel = float(cfg.get("thresh_rel", 0.0))
    rel_on = str(cfg.get("rel_on", "bg"))
    adapt = cfg.get("adapt_rel")
    gs = int(cfg.get("gshift", 0))
    gs_step = int(cfg.get("gshift_step", 8))
    prev_frac = 0.0
    thr_floor = int(cfg.get("thresh_floor", 0))
    blur = int(cfg.get("blur", 0))
    sel = bool(cfg.get("selective", False))
    gate = int(cfg.get("gate", thr))
    sr = cfg.get("shadow_ratio")
    hyst = cfg.get("hyst")
    k3 = np.ones((3, 3), np.uint8)
    rows = []
    for t in range(init_n, len(c2)):
        cur = c2[t].astype(np.float32)
        bg_ref = bg
        if gs:
            # 1/8 抽样 + 只比中央区域，代价极小；补偿＝"读背景时加位移"
            st = gs_step
            c_s, b_s = cur[::st, ::st], bg[::st, ::st]
            h, w = c_s.shape
            core = (slice(gs, h - gs), slice(gs, w - gs))
            best, bs = None, (0, 0)
            for dy in range(-gs, gs + 1):
                for dx in range(-gs, gs + 1):
                    sh = np.roll(np.roll(b_s, dy, axis=0), dx, axis=1)[core]
                    sad = float(np.abs(c_s[core] - sh).mean())
                    if best is None or sad < best:
                        best, bs = sad, (dy, dx)
            if bs != (0, 0):
                bg_ref = np.roll(np.roll(bg, bs[0], axis=0), bs[1], axis=1)
        d = np.abs(cur - bg_ref)
        if blur:
            d = cv2.blur(d, (blur, blur))
        if adapt:
            lo, hi, flo, fhi = adapt
            if prev_frac >= fhi:
                thr_rel = hi
            elif prev_frac <= flo:
                thr_rel = lo
            else:
                thr_rel = lo + (hi - lo) * (prev_frac - flo) / (fhi - flo)
        if thr_rel > 0:
            # 分母可选：背景值（旧）/ 当前帧 / max(I,B) / 当前帧 3×3 均值（全都能在硬件上出）
            if rel_on == "cur":
                base = cur
            elif rel_on == "max":
                base = np.maximum(cur, bg)
            elif rel_on == "local":
                base = cv2.blur(cur, (3, 3))
            elif rel_on == "local5":
                base = cv2.blur(cur, (5, 5))
            else:
                base = bg
            limit = np.maximum(thr_floor, thr_rel * base)
            m = (d > limit).astype(np.uint8)
        else:
            m = (d > thr).astype(np.uint8)
        if hyst:
            t_low, iters = hyst
            weak = (d > t_low).astype(np.uint8)
            for _ in range(max(1, int(iters))):
                m = ((cv2.dilate(m, k3) > 0) & (weak > 0)).astype(np.uint8)
        if sr:
            lo, hi = sr
            m[(m > 0) & (cur > lo * bg) & (cur < hi * bg)] = 0
        frac = float(m.mean()) if m.size else 0.0
        m = post_mask(m, cfg)
        if collect is not None:
            collect.append(m)
        prev_frac = frac
        if sel:
            upd = d <= gate
            bg[upd] = a * cur[upd] + (1.0 - a) * bg[upd]
            if a_fg > 0:
                fg = ~upd
                bg[fg] = a_fg * cur[fg] + (1.0 - a_fg) * bg[fg]
        else:
            bg = a * cur + (1.0 - a) * bg
        if t >= nw and labels is not None:
            pred = expand2x2(m)[:labels[t].shape[0], :labels[t].shape[1]]
            if pred.shape != labels[t].shape:
                pred = np.zeros_like(labels[t])
            rows.append(cd.metrics(labels[t], pred))
    return rows


def run_bg(c2, labels, nw, cfg):
    """逐帧平均口径的 (精确率, 召回率, F1)。"""
    rows = frame_metrics(c2, labels, nw, cfg)
    if not rows:
        return np.array([float("nan")] * 3)
    return np.array([r[:3] for r in rows]).mean(axis=0)


def score_official(rows):
    """官方口径：整段 TP/FP/FN 累加后算一次 → (P, R, F1)。"""
    if not rows:
        return 0.0, 0.0, 0.0
    tp = sum(r[3] for r in rows)
    fp = sum(r[4] for r in rows)
    fn = sum(r[5] for r in rows)
    p = tp / float(tp + fp) if (tp + fp) else 0.0
    r_ = tp / float(tp + fn) if (tp + fn) else 0.0
    f1 = 2 * p * r_ / (p + r_) if (p + r_) else 0.0
    return p, r_, f1


def run_opencv_ref(grays, labels, nw, kind):
    if kind == "MOG2":
        sub = cv2.createBackgroundSubtractorMOG2(history=500, varThreshold=16,
                                                 detectShadows=False)
    else:
        sub = cv2.createBackgroundSubtractorKNN(history=500, dist2Threshold=400.0,
                                                detectShadows=False)
    rows = []
    for t in range(len(grays)):
        m = sub.apply(grays[t])
        if t >= nw:
            rows.append(cd.metrics(labels[t], (m > 0).astype(np.uint8)))
    return np.array([r[:3] for r in rows]).mean(axis=0) if rows else np.array([0.0] * 3)


# --------------------------------------------------------------------------
# 变体库
V0 = ("V0 现役 α.02 thr70 open3", dict(alpha=0.02, thresh=70, open=3))
V1 = ("V1 只调 α→.005", dict(alpha=0.005, thresh=70, open=3))
V2 = ("V2 V1+选择性更新", dict(alpha=0.005, thresh=70, open=3, selective=True))
V3 = ("V3 V1+闭运算+去小块", dict(alpha=0.005, thresh=70, open=3, close=3, min_area=40))
V4 = ("V4 V2+V3", dict(alpha=0.005, thresh=70, open=3, close=3, min_area=40, selective=True))
V5 = ("V5 V4+差分平滑(3×3)",
      dict(alpha=0.005, thresh=70, open=3, close=3, min_area=40, selective=True, blur=3))
V7 = ("V7 V4+双速率α(背1/64·前1/1024)",
      dict(alpha=1.0 / 64, alpha_fg=1.0 / 1024, thresh=70, open=3, close=3,
           min_area=40, selective=True))
V8 = ("V8 V4+阴影抑制(比值0.55~0.98)",
      dict(alpha=0.005, thresh=70, open=3, close=3, min_area=40, selective=True,
           shadow_ratio=(0.55, 0.98)))
V9 = ("V9 V4+面积按比例(1e-3)",
      dict(alpha=0.005, thresh=70, open=3, close=3, min_area_frac=1e-3, selective=True))


def _dual(a_bg, a_fg, **kw):
    """双速率背景：背景侧 α=a_bg（学得快）、前景侧 α=a_fg（学得慢/冻结）。"""
    c = dict(alpha=a_bg, alpha_fg=a_fg, thresh=70, open=3, close=3,
             min_area=40, selective=True)
    c.update(kw)
    return c


V7A = ("V7a 双速率(背1/32·前1/1024)", _dual(1.0 / 32, 1.0 / 1024))
V7B = ("V7b 双速率(背1/128·前1/2048)", _dual(1.0 / 128, 1.0 / 2048))
V7C = ("V7c 双速率(背1/64·前1/4096)", _dual(1.0 / 64, 1.0 / 4096))
V8A = ("V8a 阴影闸门(0.75~0.95)", _dual(1.0 / 64, 1.0 / 1024, shadow_ratio=(0.75, 0.95)))
V8B = ("V8b 阴影闸门(0.60~0.90)", _dual(1.0 / 64, 1.0 / 1024, shadow_ratio=(0.60, 0.90)))
V10 = ("V10 快背景+冻结前景(1/64·0)", _dual(1.0 / 64, 0.0))
V11 = ("V11 α.02+选择性更新+闭+去小块",
       dict(alpha=0.02, thresh=70, open=3, close=3, min_area=40, selective=True))
V12 = ("V12 快背景1/32+冻结前景 ★现冠军", _dual(1.0 / 32, 0.0))

# 第五轮：专打夜间（暗场景固定阈值过高 → 召回崩）
V13 = ("V13 V12+绝对阈值降到40", _dual(1.0 / 32, 0.0, thresh=40))
V14 = ("V14 V12+相对阈值20%(底30)", _dual(1.0 / 32, 0.0, thresh_rel=0.20, thresh_floor=30))
V15 = ("V15 V12+相对阈值35%(底30)", _dual(1.0 / 32, 0.0, thresh_rel=0.35, thresh_floor=30))
V16 = ("V16 V12+相对阈值20%(底15)", _dual(1.0 / 32, 0.0, thresh_rel=0.20, thresh_floor=15))
V17 = ("V17 V12+相对阈值50%(底25)", _dual(1.0 / 32, 0.0, thresh_rel=0.50, thresh_floor=25))

# 第六轮：迟滞双阈值 —— 打"单一固定阈值通吃不了"这个真瓶颈
#   高阈值（thresh）决定"哪里肯定是动的"→ 保精度；
#   低阈值（t_low）配合 3×3 连通性把弱目标连回来 → 补召回。
#   对应硬件：已有 3×3 形态学窗口 + 一个比较器 + 一轮膨胀，几乎零面积代价。
V18 = ("V18 V12+迟滞(高70低40×1)", _dual(1.0 / 32, 0.0, hyst=(40, 1)))
V19 = ("V19 V12+迟滞(高70低30×1)", _dual(1.0 / 32, 0.0, hyst=(30, 1)))
V20 = ("V20 V12+迟滞(高70低40×2)", _dual(1.0 / 32, 0.0, hyst=(40, 2)))
V21 = ("V21 V12+迟滞(高60低35×1)", _dual(1.0 / 32, 0.0, thresh=60, hyst=(35, 1)))
V22 = ("V22 V12+迟滞(高50低30×1)", _dual(1.0 / 32, 0.0, thresh=50, hyst=(30, 1)))
V23 = ("V23 V12+迟滞(高70低50×1)", _dual(1.0 / 32, 0.0, hyst=(50, 1)))

# 第七轮：夜间的正解 —— 把"绝对差值"换成"归一化对比度"（Weber）
#   文献（Pan et al. 2021, PeerJ CS）指出夜间目标与背景的**绝对差**极小，必须用比值；
#   分母取谁有三种做法，全部只用已有资源可算：
#     bg   = 背景值（第 5 轮已试）
#     cur  = 当前帧（严格 Weber |I-B|/max(I,T)）
#     local= 当前帧 3×3 均值（局部自适应，硬件上复用 morph3x3 的行缓存即可）
V24 = ("V24 V12+Weber(cur)/20% 底30", _dual(1.0 / 32, 0.0, thresh_rel=0.20, thresh_floor=30, rel_on="cur"))
V25 = ("V25 V12+Weber(max(I,B))/20% 底30", _dual(1.0 / 32, 0.0, thresh_rel=0.20, thresh_floor=30, rel_on="max"))
V26 = ("V26 V12+局部相对(3×3均值)/20% 底30", _dual(1.0 / 32, 0.0, thresh_rel=0.20, thresh_floor=30, rel_on="local"))
V27 = ("V27 V12+局部相对(3×3均值)/10% 底20", _dual(1.0 / 32, 0.0, thresh_rel=0.10, thresh_floor=20, rel_on="local"))
V28 = ("V28 V26+阴影闸门(0.60~0.95)", _dual(1.0 / 32, 0.0, thresh_rel=0.15, thresh_floor=25,
                                         rel_on="local", shadow_ratio=(0.60, 0.95)))
V29 = ("V29 V12+局部相对(3x3均值)/15% 底25", _dual(1.0 / 32, 0.0, thresh_rel=0.15, thresh_floor=25,
                                                rel_on="local"))

# 第八轮：沿 V29（局部相对阈值）继续 —— 扫比例 + 抗抖动
V30 = ("V30 V12+局部8% 底20", _dual(1.0 / 32, 0.0, thresh_rel=0.08, thresh_floor=20, rel_on="local"))
V31 = ("V31 V12+局部10% 底20", _dual(1.0 / 32, 0.0, thresh_rel=0.10, thresh_floor=20, rel_on="local"))
V32 = ("V32 V12+局部12% 底22", _dual(1.0 / 32, 0.0, thresh_rel=0.12, thresh_floor=22, rel_on="local"))
V33 = ("V33 V12+局部18% 底28", _dual(1.0 / 32, 0.0, thresh_rel=0.18, thresh_floor=28, rel_on="local"))
V34 = ("V34 V12+局部25% 底35", _dual(1.0 / 32, 0.0, thresh_rel=0.25, thresh_floor=35, rel_on="local"))
V35 = ("V35 V29+差值3x3平滑(抗抖)", _dual(1.0 / 32, 0.0, thresh_rel=0.15, thresh_floor=25,
                                       rel_on="local", blur=3))
V36 = ("V36 V12+局部5x5均值/15% 底25", _dual(1.0 / 32, 0.0, thresh_rel=0.15, thresh_floor=25,
                                          rel_on="local5"))

# 第九轮：**场景自适应** —— 第八轮发现"局部相对阈值"的比例是"镜头抖 vs 夜间"的旋钮：
#   比例小（8~10%）→ 夜间好、抖动差；比例大（18~25%）→ 抖动好、夜间与其它类下滑。
#   既然没有一个固定值通吃，就**按上一帧的前景占比自动调**（占比高＝整帧在动＝抖动帧 → 收紧）。
#   硬件：占比 = 包围盒那一路已有的 mask 计数 / 总大像素数，**零额外资源**。
V37 = ("V37 V12+自适应局部阈值(10%~25%)",
       _dual(1.0 / 32, 0.0, thresh_rel=0.15, thresh_floor=25, rel_on="local",
             adapt_rel=(0.10, 0.25, 0.05, 0.25)))
V38 = ("V38 V12+自适应局部阈值(12%~30%)",
       _dual(1.0 / 32, 0.0, thresh_rel=0.15, thresh_floor=25, rel_on="local",
             adapt_rel=(0.12, 0.30, 0.05, 0.30)))

# 第十轮：**全局运动补偿** —— 参数线已到平台期，改打结构性手段。
#   镜头抖/杆子被风吹晃时，整帧在平移；老的"逐像素"差分把每条边缘都点亮成前景。
#   做法：先在压缩域估出整帧平移（1/8 抽样小网格搜索），**补偿时只改背景的读取位移**。
V39 = ("V39 V29+全局补偿 R2", _dual(1.0 / 32, 0.0, thresh_rel=0.15, thresh_floor=25,
                                 rel_on="local", gshift=2))
V40 = ("V40 V38+全局补偿 R2", _dual(1.0 / 32, 0.0, thresh_rel=0.15, thresh_floor=25,
                                 rel_on="local", adapt_rel=(0.12, 0.30, 0.05, 0.30), gshift=2))
V41 = ("V41 V38+全局补偿 R4", _dual(1.0 / 32, 0.0, thresh_rel=0.15, thresh_floor=25,
                                 rel_on="local", adapt_rel=(0.12, 0.30, 0.05, 0.30), gshift=4))

# 第十一轮：细化全局补偿
V42 = ("V42 V38+全局补偿 R1", _dual(1.0 / 32, 0.0, thresh_rel=0.15, thresh_floor=25,
                                 rel_on="local", adapt_rel=(0.12, 0.30, 0.05, 0.30), gshift=1))
V43 = ("V43 V38+全局补偿 R2/抽样4", _dual(1.0 / 32, 0.0, thresh_rel=0.15, thresh_floor=25,
                                     rel_on="local", adapt_rel=(0.12, 0.30, 0.05, 0.30),
                                     gshift=2, gshift_step=4))
V44 = ("V44 V38+全局补偿 R3", _dual(1.0 / 32, 0.0, thresh_rel=0.15, thresh_floor=25,
                                 rel_on="local", adapt_rel=(0.12, 0.30, 0.05, 0.30), gshift=3))

# 第十二轮：**初始背景策略** —— 由合成考场暴露出来的真问题
#   旧做法 = 直接拿第 0 帧当背景。可第 0 帧里往往**就含着目标** → 目标被"固化"进背景 →
#   物体内部永远不算前景，只在本体前后各留一条边带（大而慢的目标尤其明显）。
#   修法 = 初始背景取**前 N 帧逐像素最小值**（硬件：一个比较器 + 一个寄存器）。
#   在合成跟踪考场上：误检 1.58/帧 → 0，断航 7 → 0，存活轨迹 4 → 2（正确）。
V45 = ("V45 V43+初始背景取前6帧最小", _dual(1.0 / 32, 0.0, thresh_rel=0.15, thresh_floor=25,
                                     rel_on="local", adapt_rel=(0.12, 0.30, 0.05, 0.30),
                                     gshift=2, gshift_step=4, init_frames=6))
V46 = ("V46 V43+初始背景取前12帧最小", _dual(1.0 / 32, 0.0, thresh_rel=0.15, thresh_floor=25,
                                      rel_on="local", adapt_rel=(0.12, 0.30, 0.05, 0.30),
                                      gshift=2, gshift_step=4, init_frames=12))
V47 = ("V47 V43+初始背景取前20帧最小", _dual(1.0 / 32, 0.0, thresh_rel=0.15, thresh_floor=25,
                                      rel_on="local", adapt_rel=(0.12, 0.30, 0.05, 0.30),
                                      gshift=2, gshift_step=4, init_frames=20))

SETS = {
    "core": [V0, V1, V4],
    "full": [V0, V1, V2, V3, V4, V5],
    "r2": [V0, V4, V7, V8, V9],
    "r3": [V0, V7, V7A, V7B, V7C, V8A, V8B],
    "r4": [V0, V4, V7, V10, V11, V12],
    "r5": [V0, V4, V12, V13, V14, V15, V16, V17],
    "r6": [V0, V12, V18, V19, V20, V21, V22, V23],
    "r7": [V0, V12, V24, V25, V26, V27, V28, V29],
    "r7b": [V0, V12, V28, V29],
    "r8": [V0, V12, V29, V30, V31, V32, V33, V34, V35, V36],
    "r9": [V0, V12, V29, V33, V36, V37, V38],
    "r10": [V0, V12, V38, V39, V40, V41],
    "r11": [V0, V12, V40, V42, V43, V44],
    "r11b": [V0, V12, V40, V43],
    "r12": [V0, V12, V43, V45, V46, V47],
}

DEFAULT_SET = "r5"


def load_cached(seqdir, warmup=100, frames=0):
    """frames = 计分帧数（不含预热）；0 = 整段 ROI。"""
    roi = cd.read_roi(seqdir)
    assert roi, "缺 temporalROI.txt: %s" % seqdir
    r0, r1 = roi
    first = max(1, r0 - warmup)
    nw = r0 - first
    count = (frames + nw) if frames > 0 else (r1 - first + 1)
    grays, labels, _ = cd.load_seq(seqdir, first, count)
    nw = min(nw, max(0, len(grays) - 1))
    c2 = [compress2x2(g) for g in grays]
    return roi, nw, grays, c2, labels


def main():
    ap = argparse.ArgumentParser(
        description="算法改进实验台（逐帧平均口径）｜ 需要 CDnet2014 数据集")
    add_data_root_arg(ap)          # ← --data-root，优先级高于环境变量 CDNET_ROOT
    ap.add_argument("--seq", default="all",
                    help="all 或用逗号分隔 类别/序列（也接受旧名 pedestrians/canoe）")
    ap.add_argument("--set", default=DEFAULT_SET, choices=sorted(SETS))
    ap.add_argument("--frames", type=int, default=0)
    ap.add_argument("--ref", action="store_true")
    ap.add_argument("--list", action="store_true", help="只列出可用序列")
    args = ap.parse_args()

    # ---- 数据根目录：解析失败就明确报错退出，绝不静默跑一个"0 条序列"的空表 ----
    try:
        root, src = resolve_data_root(args.data_root)
        allseq = discover(root)
        if not allseq:
            raise no_sequence_error(root, src)
        describe_data_root(root, src)
        if args.list:
            print("可用序列 (%d)：" % len(allseq))
            for k in sorted(allseq):
                print("   ", k)
            return 0
        targets = select_sequences(allseq, args.seq)
        precheck_sequences(allseq, targets)
    except DataRootError as e:
        sys.stderr.write("\n[数据未就绪] %s\n\n" % e)
        return 1

    variants = SETS[args.set]
    print("=" * 92)
    print("算法改进实验台（逐帧平均口径）｜ 2×2 压缩域 ｜ 真值排除 50/85/170 ｜ 变体集 = %s"
          % args.set)
    print("选中序列 %d 条：%s" % (len(targets), ", ".join(targets)))
    print("=" * 92)
    sys.stdout.flush()

    table = {}
    rows_out = []
    for nm in targets:
        t0 = time.time()
        roi, nw, grays, c2, labels = load_cached(allseq[nm], frames=args.frames)
        print("\n### %s  (ROI %d~%d, 计分 %d 帧, 预热 %d)" % (nm, roi[0], roi[1], len(c2) - nw, nw))
        print("  %-34s %9s %9s %9s" % ("变体", "精确率", "召回率", "F1"))
        print("  " + "-" * 66)
        sys.stdout.flush()
        for label, cfg in variants:
            p, r, f = run_bg(c2, labels, nw, cfg)
            print("  %-34s %9.3f %9.3f %9.3f" % (label, p, r, f))
            sys.stdout.flush()
            rows_out.append([nm, label, "%.4f" % p, "%.4f" % r, "%.4f" % f])
            table.setdefault(label, {})[nm] = f
        if args.ref:
            for kind in ("MOG2", "KNN"):
                p, r, f = run_opencv_ref(grays, labels, nw, kind)
                print("  %-34s %9.3f %9.3f %9.3f" % ("[CPU参照] OpenCV " + kind, p, r, f))
                rows_out.append([nm, "REF OpenCV %s" % kind, "%.4f" % p, "%.4f" % r, "%.4f" % f])
                table.setdefault("REF OpenCV " + kind, {})[nm] = f
        print("  (耗时 %.1f s)" % (time.time() - t0))
        sys.stdout.flush()

    print("\n" + "=" * 92)
    print("跨场景汇总（逐帧平均 F1）")
    print("=" * 92)
    seqs = targets
    print("  %-32s %s %9s"
          % ("变体", " ".join("%8s" % s.split("/")[-1][:8] for s in seqs), "平均"))
    for label in [v[0] for v in variants] + (["REF OpenCV MOG2", "REF OpenCV KNN"] if args.ref else []):
        vals = [table.get(label, {}).get(s) for s in seqs]
        good = [v for v in vals if v is not None and not np.isnan(v)]
        avg = sum(good) / len(good) if good else float("nan")
        print("  %-32s %s %9.3f"
              % (label, " ".join(("%8.3f" % v) if (v is not None and not np.isnan(v)) else "       -"
                                 for v in vals), avg))

    csvp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "algo_lab_results.csv")
    with open(csvp, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["seq", "variant", "precision", "recall", "f1"])
        w.writerows(rows_out)
    print("\n结果已写出: %s" % csvp)
    return 0


if __name__ == "__main__":
    sys.exit(main())
