# -*- coding: utf-8 -*-
"""RTL 硬件模型参考 —— 与 `src/rtl/` 逐位对齐的纯 Python 实现。

为什么需要它（和 golden_ref.py 的分工）
---------------------------------------
`golden_ref.py` 是**算法**参考：全分辨率 720p、阈值 25、cv2 椭圆核，
用来量化「帧差法的质心偏多少」这类算法属性。
本文件是**硬件模型**参考：2×2 和域、阈值 70、3×3 方核、**零扩展边界**，
一步一步照抄 RTL 的整数运算，用来回答一个不同的问题：
    「仿真跑出来的那些数，是不是真的算对了？」
两者口径不同，数字不会相同，**不能互相替代，也不要混着引用**。

它复刻的是 RTL 的这条链（每个函数对应一个 .v 文件）：
    pattern_gen     → make_frame()         合成激励，逐条对齐 make_test_clip.py
    downsample2x2   → compress2x2()        2×2 求和，8bit → 10bit
    diff_stage      → diff()               帧差 或 |I−B|（背景模式另算更新）
    threshold       → mask_of()            absdiff > 70
    morph_open      → open3()              3×3 腐蚀 → 3×3 膨胀
    bbox            → bbox_of()            x1/y1/x2/y2 + 面积门限

★ 五个必须与 RTL 严格一致、且都真踩过的地方
-------------------------------------------------
1) **宽高别搞反**：参数照 RTL 取名 W=320（横向）、H=180（纵向），
   而 numpy 的数组是 (行=纵向, 列=横向) → 必须 np.zeros((H, W))。
   第一版写成 np.zeros((W, H)) 把画面转置了，物体一超出 180 列就被切片
   悄悄裁掉 —— 结果是"前 6 帧对得上、第 7 帧起模型丢掉一条带"，
   看着像 RTL 有问题，其实是模型错的。所以下面加了 frame 自检。
2) **2×2 是求和不是平均**：用 .sum()，值域 0..1020，
   所以阈值 70 是「和域」阈值，等于单像素 17.5 灰阶。
   写成 .mean() 量纲差 4 倍，阈值就不是一回事了。
3) **形态学是零扩展、居中锚点**，且 RTL 的输出域是 x∈[1,BW-2]、y∈[1,BH-2]
   （窗口中心比右下角少 1，首行/首列/末行/末列不产出）。
   膨胀之后必须把这一圈清零，否则末行/末列会多出 RTL 根本没有的像素。
4) **bbox 是全局并集框 + 面积门限**（不是 cv2 的最大连通域）。
   单目标时两者等价，多目标时不等价 —— 已知取舍。

用法
----
  python rtl_golden.py                                   # 默认参数（与 tb 一致）
  python rtl_golden.py --mode bg --alpha-shift 6         # 背景建模版
  python rtl_golden.py --compare sim/wave/bbox_rtl.csv --report sim/logs/model_vs_rtl.txt
"""

import argparse
import csv
import io
import os
import sys

import numpy as np

# ---------------- 默认参数（必须与 sim/tb/tb_md_pipeline.v 保持一致）----------------
#   w  = H_ACTIVE（横向像素数）
#   h  = V_ACTIVE（纵向像素数）
DEF = dict(w=320, h=180, obj_w=40, obj_h=30, x0=40, y0=80, dx=16, frames=12)
THRESH = 70            # 2×2 和域阈值（照抄参考作品 #1 的硬编码值）
MIN_CNT = 64           # 包围盒面积门限（大像素个数）

_LOG = []


def out(s=""):
    _LOG.append(s)
    print(s)


# --------------------------------------------------------------------------
# 激励：复刻 src/rtl/pattern_gen.v ← make_test_clip.py
# --------------------------------------------------------------------------
def obj_x_at(t, w, obj_w, x0, dx):
    """第 t 帧目标左边缘 —— 与 pattern_gen.v 同一套回绕规则。

    x = (x + dx + obj_w > w) ? x0 : x + dx   （第 0 帧 = x0）
    两边都照这一行写，才不会出现"RTL 在绕、模型不绕"这种静默分叉。
    """
    x = x0
    for _ in range(t):
        nx = x + dx
        x = x0 if (nx + obj_w > w) else nx
    return x


def make_frame(t, w, h, obj_w, obj_h, x0, y0, dx):
    """第 t 帧：黑底 + 纯白矩形，左边缘见 obj_x_at()，顶边固定 y0。

    ★ 数组是 (行=纵向 h, 列=横向 w) —— 与 RTL 的 (x=横向, y=纵向) 互为转置，
      写反了不会报错，只会静默裁掉超出部分，务必靠下面的自检兜住。
    ★ 矩形覆盖 [x, x+obj_w-1] × [y0, y0+obj_h-1]，即**恰好** obj_w×obj_h 个白像素，
      与 make_test_clip.py 里 cv2.rectangle 的约定一致（差 1 像素真值重心也差）。
    """
    img = np.zeros((h, w), np.uint8)
    x = obj_x_at(t, w, obj_w, x0, dx)
    img[y0:y0 + obj_h, x:x + obj_w] = 255
    return img


def selfcheck_frames(p):
    """激励自检：位置、尺寸、以及回绕有没有把目标留在画面内。

    这一道不是为了好看 —— 上面「宽高写反」那个 bug 就是被它挡住的。
    与 make_test_clip.py 的边界自检同一个道理：物体一旦出画，
    模型和 RTL 会各自"合理地"给出不同结果，无从判断谁对。
    回绕规则保证了不出画，于是这里查两件事：
      (a) 白像素个数恒为 obj_w*obj_h —— 说明矩形没被画面裁掉；
      (b) 本段有没有真的回绕 —— 没回绕是正常的（帧数还没跑到右边界），
          回绕是给板上连续运行兜底的。
    """
    msgs = []
    for t in (0, p['frames'] - 1):
        f = make_frame(t, p['w'], p['h'], p['obj_w'], p['obj_h'], p['x0'], p['y0'], p['dx'])
        ys, xs = np.nonzero(f)
        ex = (obj_x_at(t, p['w'], p['obj_w'], p['x0'], p['dx']), p['y0'])
        got = (int(xs.min()), int(ys.min()))
        cnt = int(xs.size)
        ok_pos = (got == ex)
        ok_cnt = (cnt == p['obj_w'] * p['obj_h'])
        msgs.append("  第 %2d 帧: 白像素 %5d 个(应为 %d)  左上角 (%d,%d)(应为 %d,%d)  %s"
                    % (t, cnt, p['obj_w'] * p['obj_h'], got[0], got[1], ex[0], ex[1],
                       "OK" if (ok_pos and ok_cnt) else "!! 不符"))
    xs_all = [obj_x_at(t, p['w'], p['obj_w'], p['x0'], p['dx']) for t in range(p['frames'])]
    over = [t for t, x in enumerate(xs_all) if x + p['obj_w'] > p['w']]
    if over:
        msgs.append("!! 第 %s 帧矩形右边缘越出画面：模型与 RTL 的比较失去意义" % over[:5])
    else:
        msgs.append("  回绕检查: %d 帧内目标未出画（最右左边缘 %d，右边缘 %d ≤ 画面宽 %d）"
                    % (p['frames'], max(xs_all), max(xs_all) + p['obj_w'], p['w']))
    wrap = [t for t in range(1, p['frames']) if xs_all[t] < xs_all[t - 1]]
    if wrap:
        msgs.append("  回绕发生: 第 %s 帧左边缘回到 X0=%d" % (wrap[:6], p['x0']))
    else:
        msgs.append("  本段未回绕（走到第 %d 列）：正常，回绕是给板上连续运行兜底的"
                    % max(xs_all))
    return msgs


# --------------------------------------------------------------------------
# 第 1 步：2×2 求和压缩  ← downsample2x2.v
# --------------------------------------------------------------------------
def compress2x2(gray):
    g = gray.astype(np.uint16)
    h, w = g.shape
    return g[:h - h % 2, :w - w % 2].reshape(h // 2, 2, w // 2, 2).sum(axis=(1, 3))


# --------------------------------------------------------------------------
# 第 2 步：差分  ← diff_stage.v
# --------------------------------------------------------------------------
def diff(cur, ref):
    """RTL 里就是有符号减法取绝对值，这里保持整数。"""
    return cur.astype(np.int32) - ref.astype(np.int32)


def bg_update(bg, cur, shift):
    """B' = B + (I − B) >> shift，钳到 0..1023 —— 与 diff_stage.v 的移位近似一致。

    ★ 用整数移位而不是 alpha*cur+(1-alpha)*bg 的浮点式：
      RTL 里没有浮点，浮点式在硬件上根本不存在。参考模型若用浮点，
      两边会因为舍入方式不同而对不上，那种"对不上"是模型写错，不是 RTL 错。
    """
    d = cur.astype(np.int32) - bg.astype(np.int32)
    inc = d >> shift                      # Python 的 >> 对负数是算术右移，与 Verilog >>> 同义
    nxt = bg.astype(np.int32) + inc
    return np.clip(nxt, 0, 1023).astype(np.uint16)


# --------------------------------------------------------------------------
# 第 3 步：阈值  ← threshold.v
# --------------------------------------------------------------------------
def mask_of(d, thresh=THRESH):
    return np.abs(d) > thresh             # 严格大于，与 RTL 的 > 一致


# --------------------------------------------------------------------------
# 第 4 步：形态学开运算  ← morph3x3.v + morph_open.v
# --------------------------------------------------------------------------
def _win(m, op):
    """3×3 居中窗口，**零扩展**。op='and' 腐蚀 / op='or' 膨胀。"""
    h, w = m.shape
    p = np.zeros((h + 2, w + 2), bool)       # 零扩展 = 窗口外当 0
    p[1:-1, 1:-1] = m
    o = np.ones((h, w), bool) if op == 'and' else np.zeros((h, w), bool)
    for dy in range(3):
        for dx in range(3):
            if op == 'and':
                o &= p[dy:dy + h, dx:dx + w]
            else:
                o |= p[dy:dy + h, dx:dx + w]
    return o


def open3(m):
    """开运算 = 腐蚀 → 膨胀。

    ★ 末行/末列必须清零：RTL 的输出域是 x∈[1,BW-2]、y∈[1,BH-2]，
      窗口中心比右下角少 1，末行/末列根本不产出（下游当 0 看）。
      而这里的零扩展会让膨胀在末行/末列"借"到真实像素，
      多出 RTL 没有的 1 —— 不清零就永远差一圈。
    """
    e = _win(m, 'and')
    e[0, :] = False
    e[-1, :] = False
    e[:, 0] = False
    e[:, -1] = False
    d = _win(e, 'or')
    d[0, :] = False
    d[-1, :] = False
    d[:, 0] = False
    d[:, -1] = False
    return d


# --------------------------------------------------------------------------
# 第 5 步：包围盒  ← bbox.v
# --------------------------------------------------------------------------
def bbox_of(m, min_cnt=MIN_CNT):
    """全局并集框 + 面积门限。返回 (valid, x1, y1, x2, y2, cnt)。"""
    ys, xs = np.nonzero(m)
    cnt = int(xs.size)
    if cnt == 0:
        return 0, 65535, 65535, 0, 0, 0
    x1, x2 = int(xs.min()), int(xs.max())
    y1, y2 = int(ys.min()), int(ys.max())
    return (1 if cnt >= min_cnt else 0), x1, y1, x2, y2, cnt


# --------------------------------------------------------------------------
# 主流程
# --------------------------------------------------------------------------
def run(mode='framediff', alpha_shift=6, n_frames=None, **kw):
    p = dict(DEF)
    p.update(kw)
    n = n_frames if n_frames else p['frames']

    frames = [compress2x2(make_frame(t, p['w'], p['h'], p['obj_w'],
                                     p['obj_h'], p['x0'], p['y0'], p['dx']))
              for t in range(n)]

    rows = [None] * n
    bg = frames[0].copy()                  # 背景初始化 = 第 0 帧（对应 RTL 的 init_phase）
    rows[0] = (0, 0, 65535, 65535, 0, 0, 0)
    for t in range(1, n):
        d = diff(frames[t], bg) if mode == 'bg' else diff(frames[t], frames[t - 1])
        v, x1, y1, x2, y2, c = bbox_of(open3(mask_of(d)))
        rows[t] = (t, v, x1, y1, x2, y2, c)
        if mode == 'bg':
            bg = bg_update(bg, frames[t], alpha_shift)
    return p, rows


def load_rtl_csv(path):
    res = {}
    with io.open(path, encoding='utf-8') as f:
        for r in csv.DictReader(f):
            res[int(r['frame'])] = tuple(int(r[k]) for k in
                                         ('b_valid', 'b_x1', 'b_y1', 'b_x2', 'b_y2', 'b_cnt'))
    return res


def main():
    ap = argparse.ArgumentParser(description="RTL 硬件模型参考")
    ap.add_argument('--mode', default='framediff', choices=['framediff', 'bg'])
    ap.add_argument('--alpha-shift', type=int, default=6)
    ap.add_argument('--out-csv', default='')
    ap.add_argument('--compare', default='', help='RTL 仿真导出的 bbox csv，逐帧对比')
    ap.add_argument('--report', default='', help='把本报告另存一份（UTF-8）')
    args = ap.parse_args()

    p, rows = run(mode=args.mode, alpha_shift=args.alpha_shift)

    out("RTL 硬件模型参考  " + ", ".join("%s=%s" % kv for kv in sorted(p.items())))
    out("模式: %s%s   阈值=%d（2×2 和域，≈单像素 %.1f 灰阶）  面积门限=%d"
        % (args.mode, "  α=1/2^%d" % args.alpha_shift if args.mode == 'bg' else '',
           THRESH, THRESH / 4.0, MIN_CNT))
    out("")
    out("激励自检：")
    for m in selfcheck_frames(p):
        out(m)
    out("")
    out("  %5s %6s %s %8s" % ("帧", "valid", "包围盒(x1,y1)-(x2,y2)  [大像素坐标]", "cnt"))
    for r in rows:
        out("  %5d %6d (%5d,%5d)-(%5d,%5d) %8d" % (r[0], r[1], r[2], r[3], r[4], r[5], r[6]))

    if args.out_csv:
        with io.open(args.out_csv, 'w', newline='', encoding='utf-8') as f:
            w = csv.writer(f)
            w.writerow(['frame', 'b_valid', 'b_x1', 'b_y1', 'b_x2', 'b_y2', 'b_cnt'])
            for r in rows:
                w.writerow(r)
        out("")
        out("已写出: %s" % args.out_csv)

    rc = 0
    if args.compare:
        if not os.path.exists(args.compare):
            out("!! 找不到 RTL 结果: %s" % args.compare)
            rc = 1
        else:
            rtl = load_rtl_csv(args.compare)
            mine = {r[0]: r[1:] for r in rows}
            common = sorted(set(rtl) & set(mine))
            bad = [t for t in common if rtl[t] != mine[t]]
            out("")
            out("=" * 74)
            out("与 RTL 仿真逐帧对比（%s）" % os.path.basename(args.compare))
            out("=" * 74)
            out("  共同帧 %d 个，完全一致 %d 个，不一致 %d 个"
                % (len(common), len(common) - len(bad), len(bad)))
            if bad:
                out("  不一致的帧（RTL / 模型 两边都列出来，便于判断是谁错）：")
                for t in bad[:20]:
                    out("    帧 %-4d RTL=%s  模型=%s" % (t, rtl[t], mine[t]))
                rc = 2
            else:
                out("  ✅ 逐帧逐字段完全一致 —— RTL 的整数运算与模型逐位对齐")

    if args.report:
        d = os.path.dirname(args.report)
        if d and not os.path.isdir(d):
            os.makedirs(d)
        with io.open(args.report, 'w', encoding='utf-8') as f:
            f.write("\n".join(_LOG) + "\n")
        print("报告已写出: %s" % args.report)

    return rc


if __name__ == '__main__':
    sys.exit(main())
