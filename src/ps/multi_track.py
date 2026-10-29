# -*- coding: utf-8 -*-
"""多目标 + 跟踪 —— 全部按"FPGA 上能实现的形式"写，不用任何库函数走捷径。

与 algo_lab.py 的分工
---------------------
algo_lab 只管到"哪些像素在动"（掩码），输出的是**一个并集框**。
本文件接手后半段：**把掩码拆成若干个目标 → 每个目标一个框 → 跨帧认得谁是谁 → 给出速度与方向**。

★ 为什么不用 cv2.connectedComponents
------------------------------------
因为它跟 FPGA 上要做的事**不是一回事**。硬件上必须走：
    行扫描取游程（run） → 与上一行的游程做区间重叠 → 并查集合并等价标签 → 第二遍汇总统计
这套东西正好落在初级组的考察点「**状态机**」上（我们现在这一项是空的）。
用库函数一行搞定，等于既没验到真逻辑，也丢了分。

★ 分两阶段验，隔离变量
----------------------
阶段 A（本文件默认）：**输入用干净的掩码**（白块=前景），只考"拆分 + 跟踪"的逻辑对不对。
阶段 B（下一步）：把输入换成我们自己那条检测链的输出 —— 那时噪声会进来，是另一个问题。
先把逻辑验对，再把噪声加进来，不然一处不对都说不清是谁的错。

★ 关联（谁是谁）用的是"最近邻 + 距离门限"，故意选最土的办法
----------------------------------------------------
因为它在 FPGA 上就是"几个目标点之间比距离"，几十个比较器就够；卡尔曼/Hungarian 那类搬不进 PL。

用法
----
  python multi_track.py                       # 用 data/golden/track_cross.avi
  python multi_track.py --gate 80 --maxmiss 3
  python multi_track.py --no-video            # 不渲染可视化视频
"""

import argparse
import csv
import os
import sys

import time

import numpy as np
import cv2

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import algo_lab as lab          # 复用它那条**唯一**的检测链
GOLD = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                     "..", "..", "data", "golden"))


# ==========================================================================
# 一、连通域标记 —— 行扫描 + 游程 + 等价表合并（硬件同构）
# ==========================================================================
def label_runs(mask):
    """按行取游程，并与**上一行的游程**做区间重叠判断，用并查集合并标签。

    返回 (labels_img, n_comp, parent)。labels_img 里 0=背景，其余为标签。
    """
    h, w = mask.shape
    labels = np.zeros((h, w), np.int32)
    parent = [0]                     # parent[k] 是标签 k 的代表元（0 号占位）

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[max(ra, rb)] = min(ra, rb)

    prev = []                        # 上一行的游程: (x0, x1, label)
    for y in range(h):
        row = mask[y]
        # 取本行所有游程
        d = np.diff(np.concatenate(([0], row, [0])).astype(np.int8))
        starts = np.nonzero(d == 1)[0]
        ends = np.nonzero(d == -1)[0] - 1
        cur = []
        for x0, x1 in zip(starts, ends):
            lab = None
            # 与上一行有重叠的游程 → 继承其中最小的标签
            for (px0, px1, plab) in prev:
                if px0 <= x1 and x0 <= px1:          # 区间重叠
                    if lab is None:
                        lab = plab
                    else:
                        union(lab, plab)
            if lab is None:                          # 新连通域
                parent.append(len(parent))
                lab = len(parent) - 1
            cur.append((x0, x1, lab))
        # 写回本行
        for (x0, x1, lab) in cur:
            labels[y, x0:x1 + 1] = lab
        prev = cur

    # 第二遍：把所有像素的标签换成代表元
    lut = np.zeros(len(parent), np.int32)
    nxt = 0
    for k in range(1, len(parent)):
        if find(k) == k:
            nxt += 1
            lut[k] = nxt
    for k in range(len(parent)):
        lut[k] = lut[find(k)]
    labels = lut[labels]
    return labels, nxt


def boxes_from_labels(labels, n_comp, min_area=1):
    """由标签图汇总出每个连通域的 bbox / 面积 / 质心（对应硬件上的"每标签累加器"）。"""
    out = []
    for k in range(1, n_comp + 1):
        ys, xs = np.nonzero(labels == k)
        if ys.size < min_area:
            continue
        out.append(dict(
            x0=int(xs.min()), x1=int(xs.max()), y0=int(ys.min()), y1=int(ys.max()),
            area=int(ys.size), cx=float(xs.mean()), cy=float(ys.mean())))
    out.sort(key=lambda b: -b["area"])
    return out


# ==========================================================================
# 二、跟踪 —— 最近邻 + 距离门限 + 丢帧容忍
# ==========================================================================
class Tracker:
    def __init__(self, gate=60.0, max_miss=3, extrapolate=2, vmax=40.0, blob_max=None):
        self.gate = gate          # 关联距离上限（像素）
        self.max_miss = max_miss  # 连续没匹配上几帧后注销
        self.vmax = vmax          # 单帧位移上限（像素/帧）—— 给速度做限幅，挡住质心跳变
        # ★ 外推最多推进几帧（超过就停在原地等）。
        #   为什么不能一直推：被遮挡的目标我们**并不知道**它有没有继续走。
        #   一直按旧速度推，推得越久偏得越多 —— 实测帧 39 时已偏出 50 px，
        #   等它真的出现时反而超出了关联门限（"预测把目标推丢了"）。
        #   推 2 帧覆盖"擦肩而过的瞬间"，之后就地等待、靠门限去接，才是稳的。
        self.extrapolate = extrapolate
        # ★ 粘连块判据：面积超过 blob_max 的块，**不许任何轨迹去认领**。
        #   两个目标擦肩时像素会连成一个块，它的质心在两者之间的某处（偏向大目标一侧）。
        #   谁去认领它，谁就被"拽"到那个错误的质心上 —— 实测受害轨迹此后一直偏 50 px，
        #   等两目标分开时它已接不上真身，只能重起新号（＝断航）。
        #   正确做法是**谁都别要它**：让所有轨迹原地等待，等块裂开再各认各的。
        #   硬件上就是"面积累加器输出 > 阈值 ⇒ 关掉更新使能"，一根线。
        self.blob_max = blob_max
        self.tracks = {}          # id -> dict(cx,cy,vx,vy,miss,age)
        self.next_id = 1
        self.n_switch = 0
        self.n_blob_skip = 0      # 因粘连块而跳过更新的帧数（可观测）

    def update(self, boxes):
        """boxes: 当前帧的框列表。返回 {id: box}。"""
        assigned = {}
        used = set()
        # ★ 先把粘连块挑出来：面积超阈值的框**谁也认领不了**（见 __init__ 的说明）。
        #   注意只对"本来就有多条轨迹在附近"的情况才启用，单目标场景下不该被它误伤 ——
        #   所以判据是"块面积 > blob_max **且** 现有轨迹数 ≥ 2"。
        skip = set()
        if self.blob_max is not None and len(self.tracks) >= 2:
            for i, b in enumerate(boxes):
                if b.get("area", 0) > self.blob_max:
                    skip.add(i)
            if skip:
                self.n_blob_skip += 1
        # 贪心：每个轨迹找最近的未占用框
        for tid, tr in sorted(self.tracks.items()):
            best, bd = None, None
            # 丢帧越多，门限越宽（目标被挡住几帧后本来就会走远）
            gate = self.gate * (1.0 + 0.5 * tr["miss"])
            for i, b in enumerate(boxes):
                if i in used or i in skip:
                    continue
                d = np.hypot(b["cx"] - tr["cx"], b["cy"] - tr["cy"])
                if d <= gate and (bd is None or d < bd):
                    best, bd = i, d
            if best is not None:
                used.add(best)
                b = boxes[best]
                nvx = b["cx"] - tr["cx"]
                nvy = b["cy"] - tr["cy"]
                # ★ 速度限幅：单帧位移不可能无限大。
                #   两个目标合并成一个块时，块的质心在两者之间（甚至更靠大目标一侧），
                #   实测会让速度从 +16 一帧跳到 +44 —— 那是**质心跳变**，不是目标真的加速。
                #   跳变若被当真速度存下来，后面的外推全跟着错。硬件上就是"增量饱和"，
                #   一个比较器 + 一个限幅，和电机控制里限斜率是同一招。
                lim = self.vmax
                nvx = float(np.clip(nvx, -lim, lim))
                nvy = float(np.clip(nvy, -lim, lim))
                tr["vx"], tr["vy"] = nvx, nvy
                tr["cx"], tr["cy"] = b["cx"], b["cy"]
                tr["miss"] = 0
                tr["age"] += 1
                assigned[tid] = b
            else:
                # ★ 丢帧期间**按上次速度外推，但只推前 `extrapolate` 帧**。
                #   为什么必须外推：两个目标重叠时只剩一个框，被挡住的那条轨迹若原地不动，
                #   等目标重新分开时它已经落后 ~200 像素 → 超出关联门限 → 断航、重新起新号。
                #   为什么必须**限次**：遮挡期我们不知道它是否还在走。一直推会越推越偏
                #   （实测继续推 8 帧后偏出 50 px，反而把目标"预测丢了"）。
                #   推 2 帧盖住擦肩的瞬间，之后停在原地靠门限接人 —— 硬件上就是一个计数器。
                #
                # ★★ 关键：如果这一帧**出现了粘连块**，说明"看不见"是遮挡造成的，
                #    不是目标走了 —— 这时**不累加 miss**，只让它原地等。
                #    不这么做的话，一次 9 帧长的擦肩就会把 maxmiss 撑爆（我们只能靠调大
                #    maxmiss 硬扛，而 maxmiss 调大又会让"真的走了"迟迟不注销），
                #    两难。区分"遮挡"与"离开"才是正解，硬件上就是一根 skip 标志线。
                if skip:
                    tr["vx"] *= 0.9
                    tr["vy"] *= 0.9
                    continue
                tr["miss"] += 1
                if tr["miss"] <= self.extrapolate:
                    tr["cx"] += tr["vx"]
                    tr["cy"] += tr["vy"]
                tr["vx"] *= 0.9
                tr["vy"] *= 0.9
        # 没配上的框 → 新轨迹（★ 粘连块除外：它是两个目标的合体，不该起新号）
        for i, b in enumerate(boxes):
            if i not in used and i not in skip:
                tid = self.next_id
                self.next_id += 1
                self.tracks[tid] = dict(cx=b["cx"], cy=b["cy"], vx=0.0, vy=0.0, miss=0, age=1)
                assigned[tid] = b
        # 注销超时轨迹
        for tid in [t for t, tr in self.tracks.items() if tr["miss"] > self.max_miss]:
            del self.tracks[tid]
        return assigned


# ==========================================================================
# 二·五、报警规则 —— 警戒区 + 穿越方向 + 停留计时（应用场景要出的东西）
# ==========================================================================
# ★ 为什么规则单独写、不混进 Tracker
#   跟踪只回答"谁在哪、往哪走"；**告警是业务判断**（这条线以里算闯入、停多久算滞留）。
#   分开写才能换场景不改跟踪：校园周界 / 机房值守 / 消防通道占用，全靠换这个 ROI 和规则。
#
# ★ 硬件同构
#   这里全是整数比较 + 一个计数器：
#     - 区域判定：框心 (cx,cy) 与几个矩形比大小（几个比较器）
#     - 穿越方向：本帧 cx 与前 N 帧保存的 cx 比符号（一个移位寄存器存 N 个历史点）
#     - 停留计时：进区置位 → 每帧 +1 → 出区清零（一个计数器和一根使能线）
#   没有任何乘除，PL 里就是"几个比较器 + 一个小状态机"，正好落在初级组考察点上。

class AlarmRule:
    """周界入侵告警。

    参数
    ----
    line_x   : 警戒线（竖直），跨越它算方向事件。None = 不做方向判定
    inside   : "left" 表示 x < line_x 是"里"（禁入区）；"right" 反之
    zone     : (x0, y0, x1, y1) 重点区域矩形；None = 全画面
    dwell_s  : 目标在 zone 里连续待够多少秒算"滞留"
    fps      : 用于把秒换成帧
    """

    def __init__(self, line_x=None, inside="left", zone=None, dwell_s=3.0, fps=30.0):
        if inside not in ("left", "right"):
            raise ValueError("inside must be left or right")
        if not np.isfinite(fps) or fps <= 0 or not np.isfinite(dwell_s) or dwell_s < 0:
            raise ValueError("fps must be positive and dwell_s nonnegative and finite")
        self.line_x = line_x
        self.inside = inside
        self.zone = zone
        self.fps = float(fps)
        self.dwell_frames = max(1, int(np.ceil(dwell_s * fps)))
        self.state = {}          # tid -> last observed side and continuous dwell
        self.last_frame = None
        self.events = []         # 告警事件流水
        self.n_cross_in = 0
        self.n_cross_out = 0
        self.n_dwell = 0

    def _side(self, cx):
        return "in" if ((cx < self.line_x) == (self.inside == "left")) else "out"

    def update(self, f, assigned, tracks):
        """连续停留只计算相邻帧的实际观测；缺帧或离区后重新计时。

        跨线以相邻的已观测侧别变化为准，速度须与目的侧方向一致。
        缺帧保留侧别，但注销的 ID 不保留状态。线上的点归右侧。
        """
        if self.last_frame is not None and f <= self.last_frame:
            raise ValueError("AlarmRule frames must increase strictly")
        gap = self.last_frame is not None and f != self.last_frame + 1
        self.last_frame = f
        for tid in list(self.state):
            if tid not in tracks and tid not in assigned:
                del self.state[tid]
            elif gap or tid not in assigned:
                self.state[tid]["dwell"] = 0
                self.state[tid]["alarmed"] = False
        new = []
        for tid, b in assigned.items():
            st = self.state.setdefault(
                tid, dict(side=None, dwell=0, alarmed=False))
            # ---- 1. 警戒线穿越方向 ----
            if self.line_x is not None:
                s = self._side(b["cx"])
                if st["side"] is None:
                    st["side"] = s
                elif s != st["side"]:
                    # 状态始终跟随观测；速度为零或方向矛盾时不生成事件。
                    vx = tracks.get(tid, {}).get("vx", 0.0)
                    moving_in = (vx < 0) == (self.inside == "left")
                    st["side"] = s
                    if vx != 0 and moving_in == (s == "in"):
                        if s == "in":
                            self.n_cross_in += 1
                        else:
                            self.n_cross_out += 1
                        new.append(dict(frame=f, tid=tid,
                                        kind="cross_in" if s == "in" else "cross_out",
                                        cx=round(b["cx"], 1), cy=round(b["cy"], 1),
                                        vx=round(vx, 1)))
            # ---- 2. 重点区域停留 ----
            inzone = self.zone is None or (
                self.zone[0] <= b["cx"] <= self.zone[2] and
                self.zone[1] <= b["cy"] <= self.zone[3])
            if inzone:
                st["dwell"] += 1
                if st["dwell"] >= self.dwell_frames and not st["alarmed"]:
                    st["alarmed"] = True
                    self.n_dwell += 1
                    ev = dict(frame=f, tid=tid, kind="dwell",
                              cx=round(b["cx"], 1), cy=round(b["cy"], 1),
                              secs=round(st["dwell"] / self.fps, 6))
                    new.append(ev)
            else:
                st["dwell"] = 0
                st["alarmed"] = False
        for ev in new:
            self.events.append(ev)
        return new


# ==========================================================================
# 三、真值读入 + 评测
# ==========================================================================
def load_truth(path):
    per = {}
    with open(path, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            fr = int(r["frame"])
            per.setdefault(fr, []).append(dict(
                oid=int(r["obj_id"]), cx=float(r["cx"]), cy=float(r["cy"]),
                x=int(r["x"]), y=int(r["y"]), w=int(r["w"]), h=int(r["h"]),
                vx=float(r["vx"]), merged=int(r["merged"])))
    return per


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clip", default=os.path.join(GOLD, "track_cross.avi"))
    ap.add_argument("--gate", type=float, default=80.0)
    ap.add_argument("--maxmiss", type=int, default=5,
                    help="连续没匹配上几帧后注销。有粘连判据兜底，5 是安全的默认；"
                         "调小到 2~3 会在【两目标面积恰好相等、块面积看不出是粘连】的那几帧上断航")
    ap.add_argument("--extrapolate", type=int, default=2,
                    help="丢帧期最多按旧速度外推几帧，超过就停在原地（防止越推越偏）")
    ap.add_argument("--blob-max", type=float, default=22000.0,
                    help="面积超过它的块视为【多目标粘连】，谁也不许认领；0/负数=关闭。"
                         "本考场实测：单目标块 19200/6912，粘连块 24960/25536 ⇒ 22000 正好分得开")
    ap.add_argument("--min-area", type=int, default=200)
    ap.add_argument("--match-dist", type=float, default=60.0, help="评测时框与真值的匹配距离")
    ap.add_argument("--source", default="clean", choices=["clean", "algo"],
                    help="clean=干净掩码（只考逻辑）；algo=换成我们自己的检测链（噪声进来）")
    ap.add_argument("--alpha", type=float, default=1.0/32, help="背景学习率（越大背景跟得越快）")
    ap.add_argument("--init-frames", type=int, default=1,
                    help="初始背景取前 N 帧逐像素最小值；1 = 旧行为（直接拿第 0 帧）")
    ap.add_argument("--min-area-big", type=int, default=20,
                    help="algo 模式下按**大像素**算的最小面积（压缩域）")
    ap.add_argument("--outdir", default=os.path.dirname(os.path.abspath(__file__)))
    ap.add_argument("--no-video", dest="video", action="store_false", default=True)
    # ---- 报警规则（应用场景）----
    ap.add_argument("--alarm", action="store_true", help="打开周界告警规则")
    ap.add_argument("--line-x", type=float, default=None, help="警戒线 x 坐标；不给则取画面中线")
    ap.add_argument("--inside", default="left", choices=["left", "right"],
                    help="警戒线哪一侧算'里'（禁入区）")
    ap.add_argument("--zone", default="", help="重点区域 x0,y0,x1,y1；留空=全画面")
    ap.add_argument("--dwell", type=float, default=3.0, help="停留多少秒算滞留")
    args = ap.parse_args()

    # ★ 产物文件名按检测模式带后缀：clean 保持原名，algo 加 _algo。
    #   不加后缀的话，`--source algo` 会把 clean 版的同名产物直接覆盖，跑一次就没了。
    TAG = "" if args.source == "clean" else "_" + str(args.source)

    # ★ --outdir 指向的目录可能还不存在。**必须先建**：
    #   cv2.VideoWriter 不会自动创建目录，open(..., "w") 也会直接抛
    #   FileNotFoundError —— 表现为"跑完了但产物没出来、退出码 1"，很难查。
    try:
        os.makedirs(args.outdir, exist_ok=True)
    except OSError as e:
        sys.stderr.write("\n[输出目录不可用] %s\n  --outdir=%s\n\n" % (e, args.outdir))
        return 1

    truth = load_truth(os.path.splitext(args.clip)[0] + "_groundtruth.csv")
    cap = cv2.VideoCapture(args.clip)
    if not cap.isOpened():
        print("打不开视频: %s" % args.clip)
        return 1
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    W = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)); H = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    vw = None
    if args.video:
        # ★ 输出名按模式带后缀（clean 用原名，algo 加 _algo）。
        #   否则 `--source algo` 会把 clean 版的产物直接覆盖掉，跑一次就没了。
        vpath = os.path.join(args.outdir, "track_result%s.mp4" % TAG)
        vw = cv2.VideoWriter(vpath, cv2.VideoWriter_fourcc(*"mp4v"), fps, (W, H))

    masks = None
    scale = 1
    fps_chain = None
    if args.source == "algo":
        import algo_lab as lab
        cfg = dict(alpha=args.alpha, alpha_fg=0.0, thresh=70, selective=True,
                   thresh_rel=0.15, thresh_floor=25, rel_on="local",
                   adapt_rel=(0.12, 0.30, 0.05, 0.30), gshift=2, gshift_step=4,
                   open=3, close=3, min_area=40, init_frames=args.init_frames)
        grays = []
        cap2 = cv2.VideoCapture(args.clip)
        while True:
            ok2, fr2 = cap2.read()
            if not ok2:
                break
            grays.append(cv2.cvtColor(fr2, cv2.COLOR_BGR2GRAY))
        cap2.release()
        c2 = [lab.compress2x2(g) for g in grays]
        masks = []
        t0 = time.time()
        lab.frame_metrics(c2, None, 0, cfg, collect=masks)
        # ★ 对齐：collect 收到的是 t = init_frames 起的那几帧，
        #   前面补 None 让下标 = 帧号（不然整体错位，指标会假崩）。
        masks = [None] * int(args.init_frames) + masks
        fps_chain = (len(c2) - 1) / max(1e-6, time.time() - t0)
        scale = 2
        print("检测链（V43 参数）整段 %.1f 帧/秒（纯 Python，仅作基线）" % fps_chain)

    tk = Tracker(gate=args.gate, max_miss=args.maxmiss, extrapolate=args.extrapolate,
                 blob_max=(args.blob_max if args.blob_max > 0 else None))

    # ---- 报警规则装配（警告线默认取画面中线）----
    rule = None
    if args.alarm:
        lx = args.line_x if args.line_x is not None else W / 2.0
        zone = None
        if args.zone.strip():
            zz = [float(v) for v in args.zone.replace("，", ",").split(",")]
            if len(zz) == 4:
                zone = tuple(zz)
        rule = AlarmRule(line_x=lx, inside=args.inside, zone=zone,
                         dwell_s=args.dwell, fps=fps)
        print("报警规则：警戒线 x=%.0f（%s 侧为禁入区）｜重点区 %s｜停留阈值 %.1f 秒"
              % (lx, "左" if args.inside == "left" else "右",
                 zone if zone else "全画面", args.dwell))

    rows = []
    n_gt_tot = n_gt_hit = n_fp = 0
    n_ok_frames = 0
    id_switches = 0
    dir_ok = dir_tot = 0
    track_to_oid = {}          # track id -> 它这辈子主要跟的是哪个真值目标
    oid_to_tids = {}           # 真值目标 -> 曾经跟过它的所有 track id 集合（用来数"断航")
    oid_to_tids_visible = {}   # 同上，但**只统计目标真正可见的帧**（合并帧不算）
    f = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gts = truth.get(f, [])
        merged = bool(gts) and gts[0]["merged"] == 1

        if masks is not None:
            if 0 <= f < len(masks) and masks[f] is not None:
                mask = masks[f]
            else:
                mask = np.zeros((1, 1), np.uint8)
            marea = args.min_area_big
        else:
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            mask = (gray > 128).astype(np.uint8)      # 阶段 A：干净掩码
            marea = args.min_area
        labels, nc = label_runs(mask)
        boxes = boxes_from_labels(labels, nc, min_area=marea)
        if scale != 1:
            for b in boxes:                            # 大像素 -> 原图像素，便于与真值比
                for k in ("x0", "x1", "cx"):
                    b[k] = b[k] * scale + (scale - 1)
                for k in ("y0", "y1", "cy"):
                    b[k] = b[k] * scale + (scale - 1)
                b["area"] = b["area"] * scale * scale
        assigned = tk.update(boxes)
        alarms = rule.update(f, assigned, tk.tracks) if rule is not None else []

        # ---- 评测（重叠帧单独记账，因为"该有几个目标"本身有歧义）----
        if not merged:
            n_ok_frames += 1
            matched_gt = set()
            for tid, b in assigned.items():
                hit = None
                for g in gts:
                    if g["oid"] in matched_gt:
                        continue
                    if np.hypot(b["cx"] - g["cx"], b["cy"] - g["cy"]) <= args.match_dist:
                        hit = g
                        break
                if hit is None:
                    n_fp += 1
                else:
                    matched_gt.add(hit["oid"])
                    # ★ 身份连续性：把这个 tid 记到该真值目标名下。
                    #   最后"每个目标被几个不同的 tid 跟过"减 1 就是断航次数 ——
                    #   光看"tid 会不会换 oid"会漏掉"跟丢了、过几帧又起了个新号"这种最常见的失败。
                    oid_to_tids.setdefault(hit["oid"], set()).add(tid)
                    if not merged:
                        oid_to_tids_visible.setdefault(hit["oid"], set()).add(tid)
                    if tid not in track_to_oid:
                        track_to_oid[tid] = hit["oid"]
                    elif track_to_oid[tid] != hit["oid"]:
                        id_switches += 1
                        track_to_oid[tid] = hit["oid"]
                    # 方向：轨迹速度符号 vs 真值速度符号
                    if abs(tk.tracks[tid]["vx"]) > 1.0:
                        dir_tot += 1
                        if (tk.tracks[tid]["vx"] > 0) == (hit["vx"] > 0):
                            dir_ok += 1
            n_gt_tot += len(gts)
            n_gt_hit += len(matched_gt)

        rows.append([f, len(gts), len(boxes), merged, len(assigned), id_switches])

        if vw is not None:
            vis = frame.copy()
            for g in gts:
                cv2.rectangle(vis, (g["x"], g["y"]), (g["x"] + g["w"] - 1, g["y"] + g["h"] - 1),
                              (90, 200, 90), 1)          # 绿细框 = 真值
            for tid, b in assigned.items():
                cv2.rectangle(vis, (b["x0"], b["y0"]), (b["x1"], b["y1"]), (60, 60, 230), 2)
                cv2.putText(vis, "id%d vx%+.0f" % (tid, tk.tracks[tid]["vx"]),
                            (b["x0"], max(16, b["y0"] - 6)), cv2.FONT_HERSHEY_SIMPLEX, 0.55,
                            (60, 60, 230), 1, cv2.LINE_AA)
            # ---- 报警规则可视化 ----
            if rule is not None:
                if rule.line_x is not None:
                    cv2.line(vis, (int(rule.line_x), 0), (int(rule.line_x), H), (0, 215, 255), 2)
                    cv2.putText(vis, "%s=INSIDE" % rule.inside.upper(),
                                (int(rule.line_x) + 6, 22), cv2.FONT_HERSHEY_SIMPLEX, 0.5,
                                (0, 215, 255), 1, cv2.LINE_AA)
                if rule.zone is not None:
                    zx0, zy0, zx1, zy1 = rule.zone
                    cv2.rectangle(vis, (int(zx0), int(zy0)), (int(zx1), int(zy1)),
                                  (255, 170, 0), 1)
                for tid, st in rule.state.items():
                    if st.get("alarmed"):
                        b = assigned.get(tid)
                        if b:
                            cv2.rectangle(vis, (b["x0"] - 4, b["y0"] - 4),
                                          (b["x1"] + 4, b["y1"] + 4), (0, 0, 255), 2)
                if alarms:
                    labels = {"cross_in": "INTRUSION", "cross_out": "EXIT", "dwell": "DWELL"}
                    txt = " | ".join("%s id%d" % (labels[a["kind"]], a["tid"]) for a in alarms)
                    cv2.putText(vis, "ALARM: " + txt, (12, 54),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2, cv2.LINE_AA)
            cv2.putText(vis, "frame %d  gt=%d  det=%d" % (f, len(gts), len(boxes)),
                        (12, 26), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (20, 20, 20), 1, cv2.LINE_AA)
            vw.write(vis)
        f += 1

    cap.release()
    if vw is not None:
        vw.release()

    track_breaks = sum(max(0, len(s) - 1) for s in oid_to_tids.values())
    # ★ 可见期断航：把"目标被合并遮挡"的那几帧排除后再数。
    #   为什么必须分开报：两目标擦肩而过时物理上只剩一个白块，检测端**不可能**给出两个框，
    #   这时多出来的新号是场景造成的，不该记在跟踪算法头上。
    #   两个数一起看，才既诚实又不冤枉自己。
    track_breaks_vis = sum(max(0, len(s) - 1) for s in oid_to_tids_visible.values())
    print("=" * 74)
    print("多目标 + 跟踪 ｜ 输入 = %s ｜ %s"
          % ("干净掩码（阶段 A：只考逻辑）" if args.source == "clean"
             else "我们自己的检测链 V43（阶段 B：噪声进来了）", os.path.basename(args.clip)))
    print("=" * 74)
    print("帧数              : %d（其中两目标重叠帧 %d，已单列不计入召回）"
          % (f, sum(1 for r in rows if r[3])))
    print("目标检出召回      : %d/%d = %.3f" % (n_gt_hit, n_gt_tot, n_gt_hit / max(1, n_gt_tot)))
    print("误检框            : %d（%.2f 个/帧）" % (n_fp, n_fp / max(1, n_ok_frames)))
    print("身份互换 ID swap  : %d" % id_switches)
    print("★ 断航 track break: %d  ← 真值目标被几个不同 id 跟过（理想=0）；"
          "跟丢再起新号也算，比只看 swap 诚实" % track_breaks)
    print("  其中可见期断航  : %d  ← 排除【两目标合成一个白块】的帧后再数（这个才是算法的锅）"
          % track_breaks_vis)
    print("方向判对          : %d/%d = %.3f" % (dir_ok, dir_tot, dir_ok / max(1, dir_tot)))
    print("最终存活轨迹数    : %d" % len(tk.tracks))

    # ---- 报警规则结果 ----
    if rule is not None:
        print("-" * 74)
        print("报警规则 ｜ 警戒线 x=%.0f（%s 侧禁入）｜停留阈值 %.1f 秒"
              % (rule.line_x, "左" if rule.inside == "left" else "右", args.dwell))
        print("闯入（朝里穿越警戒线） : %d 次" % rule.n_cross_in)
        print("离开（朝外穿越）       : %d 次" % rule.n_cross_out)
        print("滞留超时              : %d 次" % rule.n_dwell)
        if rule.events:
            print("告警流水（前 12 条）:")
            for ev in rule.events[:12]:
                if ev["kind"] in ("cross_in", "cross_out"):
                    print("  帧 %4d  %s  id%-2d  位置(%6.1f,%6.1f)  vx=%+.1f"
                          % (ev["frame"], "闯入" if ev["kind"] == "cross_in" else "离开",
                             ev["tid"], ev["cx"], ev["cy"], ev["vx"]))
                else:
                    print("  帧 %4d  滞留  id%-2d  位置(%6.1f,%6.1f)  已停 %.1f 秒"
                          % (ev["frame"], ev["tid"], ev["cx"], ev["cy"], ev["secs"]))
            if len(rule.events) > 12:
                print("  ...（共 %d 条，全量见 CSV）" % len(rule.events))
        if rule.events:
            evp = os.path.join(args.outdir, "alarm_events%s.csv" % TAG)
            with open(evp, "w", newline="", encoding="utf-8") as fh:
                w = csv.writer(fh)
                w.writerow(["frame", "tid", "kind", "cx", "cy", "detail"])
                for ev in rule.events:
                    detail = ev.get("vx", ev.get("secs", ""))
                    w.writerow([ev["frame"], ev["tid"], ev["kind"], ev["cx"], ev["cy"], detail])
            print("告警流水          : %s" % evp)

    csvp = os.path.join(args.outdir, "multi_track_results%s.csv" % TAG)
    with open(csvp, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["frame", "n_gt", "n_det", "merged", "n_tracks", "id_switches_cum"])
        w.writerows(rows)
    print("逐帧结果          : %s" % csvp)
    if vw is not None:
        print("可视化            : %s（绿细框=真值，红粗框=我们检出的，带 id 与瞬时速度）"
              % os.path.join(args.outdir, "track_result%s.mp4" % TAG))
    return 0


if __name__ == "__main__":
    sys.exit(main())
