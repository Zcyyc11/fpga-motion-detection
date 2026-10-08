# -*- coding: utf-8 -*-
"""生成"真值逐帧已知"的**多目标**合成片段 —— 给「多目标 + 跟踪 + 越界判定」当考场。

为什么要另起一个文件，而不改 make_test_clip.py
------------------------------------------------
`make_test_clip.py` 是**单目标**片段，它的 SHA256 写在 `synth_720p_clipinfo.txt` 里，
而 RTL 仿真（xsim）的 11/11 逐字段一致这条证据**挂在它身上**。
⇒ **动它 = 毁掉已有证据。** 所以跟踪考场另开一份，两者互不干扰。

与单目标版的三个关键差别
------------------------
1. **两个目标**（大小不同、速度不同）→ 逼出"连通域要分得开、跟踪要认得人"。
2. **边界反弹，不是回绕**：单目标版用回绕（右到头跳回左边）是为了让目标永不出画；
   但对跟踪来说，"跳回"＝目标瞬移，跟踪器**合理地**会跟丢，考场就不公平。
   改用**反弹**（到边界原速反向）→ 目标**永远在画面内、轨迹连续**，才考得准。
3. **真值带目标身份**：逐帧给出每个目标的 id / 框 / 质心 / 速度，
   以及 `merged` 标志（两框在那一帧是否重叠）—— 重叠帧的"该有几个目标"本身有歧义，
   评测时必须能把这部分单独拎出来，不能混进总分。

输出
----
  track_cross.avi              无损母版（FFV1）
  track_cross_groundtruth.csv  逐帧真值：frame,obj_id,cx,cy,x,y,w,h,vx,merged
  track_cross_clipinfo.txt     生成参数 + SHA256（供核验"是同一份输入"）
  track_cross_view.mp4         H.264 可观看版（只给人眼看）

用法
----
  python make_track_clip.py
  python make_track_clip.py --frames 180 --name track_cross_long
"""

import argparse
import csv
import hashlib
import os
import sys

import numpy as np
import cv2

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_test_clip as mtc      # 复用编码器/转码器，**不重写第二份**

W, H = 1280, 720
FPS = 30
N_FRAMES = 120

# (id, 宽, 高, 起始左边缘 x, 顶边 y, 每帧水平位移 vx)
# ★ 两个目标必须落在**同一垂直带**里（y 区间相交），否则永远不会交叉 —— 交叉才是跟踪的经典难题。
OBJS = [
    (0, 160, 120,   60, 300,  16),
    (1,  96,  72, 1100, 320, -12),
]


def step(x, vx, w):
    """到边界反弹：目标永远在画面内，轨迹连续（跟踪友好）。"""
    nx = x + vx
    if nx < 0:
        vx = -vx
        nx = -nx
    elif nx + w > W:
        vx = -vx
        nx = 2 * (W - w) - nx
    return nx, vx


def main():
    ap = argparse.ArgumentParser(description="生成多目标跟踪考场（真值已知）")
    ap.add_argument("--outdir", default=os.path.dirname(os.path.abspath(__file__)))
    ap.add_argument("--frames", type=int, default=N_FRAMES)
    ap.add_argument("--name", default="track_cross")
    ap.add_argument("--view", dest="view", action="store_true", default=True)
    ap.add_argument("--no-view", dest="view", action="store_false")
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    base = os.path.join(args.outdir, args.name)
    vw, vpath, vtag = mtc.open_writer(base, FPS, (W, H))
    print("编码器: %s   ->  %s" % (vtag, vpath))

    state = [[o[0], o[3], o[4], o[2], o[1], o[5]] for o in OBJS]   # id,x,y,h,w,vx
    rows = []
    n_merged = 0
    for i in range(args.frames):
        img = np.zeros((H, W, 3), np.uint8)
        # 先各自画在自己的掩码上，质心按掩码求（每个目标的客观属性，与检测算法无关）
        boxes = []
        for s in state:
            oid, x, y, h, w, vx = s
            m = np.zeros((H, W), np.uint8)
            cv2.rectangle(m, (int(x), int(y)), (int(x + w - 1), int(y + h - 1)), 255, -1)
            img[m > 0] = (255, 255, 255)
            ys, xs = np.nonzero(m)
            boxes.append((oid, float(xs.mean()), float(ys.mean()), int(x), int(y), int(w), int(h), int(vx), m))

        # ★ 重叠判定必须看"**白色像素是否真的连成一块**"，不能只看"两个矩形框是否相交"。
        #   两种判法会给出不同答案，而且错得双向：
        #     - 帧 32：大框(160 宽)的边扫过小框，矩形相交，但像素**没连**（连通域仍是 2）
        #              → 用矩形会误判成 merged，把"能分开" 冤枉成"分不开"。
        #     - 帧 114：两目标正朝两边挪开，矩形交叠不多，但像素**已经连成一块**（连通域 1）
        #              → 用矩形会漏判，把"分不开" 谎报成"能分开"。
        #   所以用连通域数直接判 —— 这跟检测端"能不能拆成两个目标"是同一件事。
        #   注意：这里故意**不用** cv2.connectedComponents 之外的库函数，判据只有"数出几块"。
        ncomp = cv2.connectedComponents((img[:, :, 0] > 128).astype(np.uint8))[0] - 1
        merged = 1 if ncomp < len(boxes) else 0
        n_merged += merged

        for oid, cx, cy, x, y, w, h, vx, _m in boxes:
            rows.append((i, oid, cx, cy, x, y, w, h, vx, merged))

        vw.write(img)
        for s in state:
            s[1], s[5] = step(s[1], s[5], s[4])    # s = [id, x, y, h, w, vx]
            s[1] = round(s[1], 6)
    vw.release()

    truth = base + "_groundtruth.csv"
    with open(truth, "w", newline="", encoding="utf-8") as f:
        wcsv = csv.writer(f)
        wcsv.writerow(["frame", "obj_id", "cx", "cy", "x", "y", "w", "h", "vx", "merged"])
        for r in rows:
            wcsv.writerow(["%d" % r[0], "%d" % r[1], "%.2f" % r[2], "%.2f" % r[3],
                           r[4], r[5], r[6], r[7], r[8], r[9]])

    h = hashlib.sha256()
    with open(vpath, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)

    info = base + "_clipinfo.txt"
    with open(info, "w", encoding="utf-8") as f:
        f.write("多目标跟踪考场 — 生成参数与校验\n")
        f.write("=" * 56 + "\n")
        f.write("分辨率   : %d x %d @ %d fps\n" % (W, H, FPS))
        f.write("帧数     : %d  (时长 %.2f s)\n" % (args.frames, args.frames / float(FPS)))
        f.write("目标     : %d 个纯白矩形，黑底（大小/速度都不同）\n" % len(OBJS))
        for o in OBJS:
            f.write("           id=%d  %dx%d  起始x=%d y=%d  每帧位移 %+d px\n"
                    % (o[0], o[1], o[2], o[3], o[4], o[5]))
        f.write("边界     : **反弹**（不是回绕）—— 目标永不出画、轨迹连续，跟踪才考得准\n")
        f.write("重叠帧   : %d / %d 帧两框相交（真值里用 merged=1 标出，评测时须单独拎出）\n"
                % (n_merged, args.frames))
        f.write("编码     : %s\n" % vtag)
        f.write("-" * 56 + "\n")
        f.write("视频文件 : %s\n" % os.path.basename(vpath))
        f.write("文件大小 : %d bytes (%.1f KB)\n" % (os.path.getsize(vpath), os.path.getsize(vpath) / 1024.0))
        f.write("SHA256   : %s\n" % h.hexdigest())
        f.write("真值文件 : %s\n" % os.path.basename(truth))
        f.write("-" * 56 + "\n")
        f.write("复现命令 : python make_track_clip.py --frames %d\n" % args.frames)
        f.write("说明     : 真值 cx/cy 由该目标**自己的掩码**求重心得到 —— 是图像的客观属性，\n")
        f.write("           与任何检测/跟踪算法无关，可直接当误差基准。\n")

    print("真值  : %s  (%d 行 = %d 帧 x %d 目标)" % (truth, len(rows), args.frames, len(OBJS)))
    print("说明  : %s" % info)
    print("重叠帧: %d（真值已标 merged=1）" % n_merged)
    if args.view:
        vout = mtc.write_view_mp4(vpath, base + "_view.mp4")
        if vout:
            print("可观看: %s" % vout)
    print("视频  : %d bytes  sha256=%s" % (os.path.getsize(vpath), h.hexdigest()[:16] + "..."))
    return 0


if __name__ == "__main__":
    sys.exit(main())
