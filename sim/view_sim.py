# -*- coding: utf-8 -*-
"""把仿真导出的 PPM 变成能看的东西，并顺手做一次**程序化体检**。

为什么不是"导出来看一眼就行"
-----------------------------
仿真导出的画面（frame_*.ppm）和掩码（mask_*.ppm）是给人眼看的，
但"框画在了哪"这件事本身可以量出来 —— 于是这里做两件事：
  1) **体检**：从画面里把红色边框的实际像素位置找出来，和 bbox_rtl.csv
     里那一帧的包围盒（×2 转像素坐标）逐个比对。
     对不上就说明"叠加"这级画错了，而不是"看起来差不多"就算了。
  2) **出图/出片**：拼一张对比图（上排=输出画面，下排=运动掩码），
     再合成一段 H.264 MP4。
     ★ H.264 而不是 FFV1：Windows 自带播放器不认 FFV1（报 0xc00d5212）。

用法
----
  python sim/view_sim.py
"""

import io
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np

SIM = os.path.dirname(os.path.abspath(__file__))
WAVE = os.path.join(SIM, "wave")
HERE = SIM


def read_ppm(path):
    """读 P6 二进制 PPM。返回 (h, w, 3) uint8。

    ★ 自己解析而不是用 cv2.imread：cv2 对 PPM 的编码细节（换行/空白）比较挑，
      这里格式是我们自己 $fwrite 出来的，直接按定义解析最稳。
    """
    with open(path, "rb") as f:
        data = f.read()
    if not data.startswith(b"P6"):
        raise ValueError("不是 P6 PPM: %s" % path)
    fields, pos = [], 2
    while len(fields) < 3:
        while pos < len(data) and data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b"#":
            while data[pos:pos + 1] != b"\n":
                pos += 1
            continue
        s = pos
        while pos < len(data) and not data[pos:pos + 1].isspace():
            pos += 1
        fields.append(int(data[s:pos]))
    pos += 1                                   # 单个空白分隔符
    w, h, _mx = fields
    buf = np.frombuffer(data[pos:pos + w * h * 3], dtype=np.uint8)
    if buf.size != w * h * 3:
        raise ValueError("PPM 数据长度不符: %s" % path)
    return buf.reshape(h, w, 3)


def read_bbox_csv(path):
    out = {}
    with io.open(path, encoding="utf-8") as f:
        hdr = f.readline().strip().split(",")
        for line in f:
            if not line.strip():
                continue
            v = [int(x) for x in line.strip().split(",")]
            out[v[0]] = dict(zip(hdr, v))
    return out


def red_box_bounds(img):
    """找出画面里红色边框的实际像素范围。红 = R 高、G/B 低。"""
    m = (img[:, :, 0] > 200) & (img[:, :, 1] < 60) & (img[:, :, 2] < 60)
    ys, xs = np.nonzero(m)
    if xs.size == 0:
        return None, int(xs.size)
    return (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())), int(xs.size)


def main():
    frames = sorted([f for f in os.listdir(WAVE) if f.startswith("frame_") and f.endswith(".ppm")],
                    key=lambda s: int(s.split("_")[1].split(".")[0]))
    masks = sorted([f for f in os.listdir(WAVE) if f.startswith("mask_") and f.endswith(".ppm")],
                   key=lambda s: int(s.split("_")[1].split(".")[0]))
    if not frames:
        print("wave/ 里没有 frame_*.ppm，先跑 python build/scripts/run_sim.py")
        return 1

    bb = read_bbox_csv(os.path.join(WAVE, "bbox_rtl.csv"))
    w = read_ppm(os.path.join(WAVE, frames[0])).shape[1]
    print("读到 %d 张画面、%d 张掩码，画面宽 %d" % (len(frames), len(masks), w))

    # ---------------- 体检：画面里的红框 vs CSV 里的包围盒 ----------------
    # ★ 注意是 **上一帧** 的包围盒：显示用的是"最新一次结算结果"，而结算发生在
    #   本帧掩码流的帧首，所以本帧画面里画的是 CSV 里 frame = k-1 的那一行。
    #   这一点写错就会得到"整体差 16 像素"的假故障。
    print("")
    print("=" * 78)
    print("叠加体检：画面中红框的实际像素范围  vs  bbox_rtl.csv 第 k-1 行（×2 转像素）")
    print("=" * 78)
    print("  %4s %-24s %-24s %s" % ("帧", "红框实测(px)", "CSV 期望(px)", "结论"))
    nbad = 0
    for name in frames:
        k = int(name.split("_")[1].split(".")[0])
        img = read_ppm(os.path.join(WAVE, name))
        got, nred = red_box_bounds(img)
        row = bb.get(k - 1)
        if row is None:
            print("  %4d %-24s %-24s %s" % (k, str(got), "（无上一帧）", "OK" if got is None else "!! 不该有框"))
            if got is not None:
                nbad += 1
            continue
        if not row["b_valid"]:
            ok = got is None
            nbad += 0 if ok else 1
            print("  %4d %-24s %-24s %s" % (k, str(got), "无目标", "OK" if ok else "!! CSV 说无目标，画面却有红框"))
            continue
        exp = (row["b_x1"] * 2, row["b_y1"] * 2, row["b_x2"] * 2, row["b_y2"] * 2)
        if got is None:
            nbad += 1
            print("  %4d %-24s %-24s !! 期望有框，画面里找不到红像素" % (k, "无", str(exp)))
            continue
        # 红框画在包围盒外沿，最后一列/行可能因坐标取整差 1 像素
        d = max(abs(a - b) for a, b in zip(got, exp))
        ok = d <= 2
        nbad += 0 if ok else 1
        print("  %4d %-24s %-24s %s" % (k, str(got), str(exp), "OK" if ok else "!! 偏差 %d px" % d))
    print("  体检结论：%s（%d/%d 帧吻合）"
          % ("通过" if nbad == 0 else "有 %d 帧不吻合" % nbad, len(frames) - nbad, len(frames)))

    # ---------------- 出图：上排画面、下排掩码 ----------------
    try:
        import cv2
    except Exception as e:
        print("没装 opencv，跳过出图：%s" % e)
        return 0

    scale = 2
    panels = []
    for name in frames:
        k = int(name.split("_")[1].split(".")[0])
        a = read_ppm(os.path.join(WAVE, name))
        mpath = os.path.join(WAVE, "mask_%d.ppm" % k)
        b = read_ppm(mpath) if os.path.exists(mpath) else np.zeros((a.shape[0] // 2, a.shape[1] // 2, 3), np.uint8)
        b = cv2.resize(b, (a.shape[1], a.shape[0]), interpolation=cv2.INTER_NEAREST)
        row = np.hstack([a, np.full((a.shape[0], 8, 3), 60, np.uint8), b])
        row = cv2.resize(row, None, fx=scale, fy=scale, interpolation=cv2.INTER_NEAREST)

        label = "frame %d" % k
        v = bb.get(k, {}).get("b_valid", -1)
        txt = "%s   bbox_valid=%d" % (label, v)
        cv2.rectangle(row, (0, 0), (row.shape[1] - 1, 26), (0, 0, 0), -1)
        cv2.putText(row, txt, (6, 19), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1, cv2.LINE_AA)
        panels.append(row)

    montage = np.vstack(panels)
    png = os.path.join(WAVE, "sim_montage.png")
    cv2.imwrite(png, montage)
    print("")
    print("对比图: %s  (%d x %d)" % (png, montage.shape[1], montage.shape[0]))
    print("        上排=流水线输出画面（红框=检测结果）  下排=3×3 开运算后的运动掩码")

    # ---------------- 出片：H.264 MP4 ----------------
    tmp = tempfile.mkdtemp(prefix="simmp4_")
    try:
        for i, _p in enumerate(panels):
            cv2.imwrite(os.path.join(tmp, "f%03d.png" % i), panels[i])
        mp4 = os.path.join(WAVE, "sim_demo.mp4")
        try:
            import imageio_ffmpeg
            ff = imageio_ffmpeg.get_ffmpeg_exe()
        except Exception:
            ff = shutil.which("ffmpeg")
        if ff:
            cmd = [ff, "-y", "-hide_banner", "-loglevel", "error",
                   "-framerate", "4", "-i", os.path.join(tmp, "f%03d.png"),
                   "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20",
                   "-movflags", "+faststart", mp4]
            r = subprocess.run(cmd, capture_output=True)
            if r.returncode == 0 and os.path.exists(mp4):
                print("演示视频: %s  (%.1f KB, H.264 —— Windows 自带播放器可直接打开)"
                      % (mp4, os.path.getsize(mp4) / 1024.0))
            else:
                print("ffmpeg 转码失败，仅保留 PNG 序列")
        else:
            print("没找到 ffmpeg，跳过视频（PNG 已生成）")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    return 0 if nbad == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
