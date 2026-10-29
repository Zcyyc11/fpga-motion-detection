# -*- coding: utf-8 -*-
"""CDnet 数据的**读取与校验** —— 所有评测入口共用的唯一一份实现。

为什么单独一个文件
------------------
以前"读图"和"查数据齐不齐"散在各个脚本里，各写各的，于是同一个问题
在三个入口上有三种表现：algo_lab 静默算错分、cdnet_demo 填零图、
five_steps 直接 IndexError。队友用中文路径跑，又在第四处炸出来。

本文件把这两件事收敛成一份，其它脚本只能调它，不许自己写一份规则。

它负责三件事
------------
1. **Unicode 安全的读图** —— Windows 上 `cv2.imread` 遇到非 ASCII 路径会
   静默返回 None（实测：纯英文 ✓、带空格 ✓、含中文 ✗、中文+空格 ✗）。
   改成"Python 打开文件读字节 + cv2.imdecode"，四种路径全通。
2. **帧号计划** —— 预热区间与计分区间怎么切，只有这一处定义。
3. **严格校验** —— 缺帧、坏帧、真值缺失/损坏/尺寸不符，一律抛 DataError，
   **绝不填零、绝不跳帧**。

★ 关于"预热帧要不要真值"
------------------------
CDnet 官方只对 temporalROI 区间内标注真值，区间外**不保证有真值图**。
（本机这份拷贝恰好把 gt 补齐到了全部帧，但不能依赖这点 —— 换一份数据就没了。）
所以规则是：
    计分帧（帧号 >= ROI 起点）→ 真值**必须**存在、能解码、尺寸与输入一致
    预热帧（帧号 <  ROI 起点）→ 真值**可有可无**；没有就填全零占位，
                                 且不参与计分；有但读不出来 → 照样报错
"""

import os
import re
from numbers import Integral

import cv2
import numpy as np


class DataError(Exception):
    """数据不可用：缺文件、读不出来、尺寸对不上。入口 catch 后**非零退出**。

    ★ 这个异常是"数据有问题"，不是"程序有 bug"。看到它就该去补数据，
      而不是去改算法参数 —— 后者只会让分数错得更隐蔽。
    """


# --------------------------------------------------------------------------
# 1. Unicode 安全的读图
# --------------------------------------------------------------------------
def imread(path, flags=cv2.IMREAD_COLOR):
    """读一张图，读不出来就抛 DataError（**绝不返回 None 让调用方猜**）。

    为什么不用 cv2.imread：
        它在 Windows 上对非 ASCII 路径静默失败（返回 None 而不报错），
        于是"数据路径有中文"会一路退化成"算法效果不好"，排查方向全错。
        实测四种路径：
            纯英文 ✓ ｜ 带空格 ✓ ｜ 含中文 ✗ ｜ 中文+空格 ✗
    为什么用 open + imdecode：
        Python 自己的 open() 用宽字符 API，中文/空格/emoji 都能开；
        拿到字节后交给 cv2.imdecode 解码，绕开 cv2 的路径处理。
        （同理，写图也不能用 cv2.imwrite，见 imwrite。）
    """
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError as e:
        raise DataError("打不开文件：%s\n      原因：%s" % (path, e))
    if not raw:
        raise DataError("文件是空的（0 字节）：%s" % path)
    img = cv2.imdecode(np.frombuffer(raw, dtype=np.uint8), flags)
    if img is None:
        raise DataError(
            "图片解码失败（文件损坏、后缀与实际格式不符、或被截断）：%s\n"
            "      文件大小 %d 字节。" % (path, len(raw)))
    return img


def imwrite(path, img):
    """写图，同样绕开 cv2.imwrite 的非 ASCII 路径问题。返回实际文件路径。"""
    ext = os.path.splitext(path)[1] or ".png"
    ok, buf = cv2.imencode(ext, img)
    if not ok:
        raise DataError("图片编码失败：%s" % path)
    with open(path, "wb") as fh:
        fh.write(buf.tobytes())
    return path


def read_gray(path):
    """按灰度读一张图，带严格报错。"""
    img = imread(path, cv2.IMREAD_GRAYSCALE)
    if img.ndim != 2:
        raise DataError("期望是单通道灰度图，实际读到 %d 通道：%s" % (img.ndim, path))
    return img


# --------------------------------------------------------------------------
# 2. 帧号计划
# --------------------------------------------------------------------------
NUM_RE = re.compile(r"(\d+)")


def read_roi(seqdir):
    """读 temporalROI.txt -> (起始帧, 结束帧)，1 基；缺失或格式不对抛 DataError。"""
    p = os.path.join(seqdir, "temporalROI.txt")
    if not os.path.isfile(p):
        raise DataError("缺 temporalROI.txt（没有它就无法确定计分区间）：%s" % p)
    try:
        txt = open(p, encoding="utf-8", errors="replace").read().split()
    except OSError as e:
        raise DataError("读不了 temporalROI.txt：%s\n      原因：%s" % (p, e))
    if len(txt) < 2:
        raise DataError("temporalROI.txt 里应该有起止两个帧号，实际读到 %r：%s"
                        % (" ".join(txt), p))
    try:
        r0, r1 = int(txt[0]), int(txt[1])
    except ValueError:
        raise DataError("temporalROI.txt 里的帧号不是整数，实际读到 %r：%s"
                        % (" ".join(txt), p))
    if r0 < 1 or r1 < r0:
        raise DataError("temporalROI.txt 的区间不合理（%d~%d），应该是 1 <= 起 <= 止：%s"
                        % (r0, r1, p))
    return r0, r1


def frame_no(name):
    """从文件名里取帧号（in000305.jpg / gt000305.png -> 305）。取不到返回 None。"""
    m = NUM_RE.search(name)
    return int(m.group(1)) if m else None


# 常见图片格式的文件头。快速预检靠它**低成本地**抓出"截断/乱码"文件：
# 读全部内容解码一遍太慢（实测 900 帧 21.8 s），而读前几个字节几乎不要钱。
MAGIC = {
    ".jpg": (b"\xff\xd8",),
    ".jpeg": (b"\xff\xd8",),
    ".png": (b"\x89PNG\r\n\x1a\n",),
    ".bmp": (b"BM",),
}


def check_file_head(path):
    """返回 None 表示文件头正常；否则返回一句人话说明（用于快速预检）。"""
    try:
        if os.path.getsize(path) == 0:
            return "文件 0 字节"
        with open(path, "rb") as fh:
            head = fh.read(8)
    except OSError as e:
        return "打不开：%s" % e
    ext = os.path.splitext(path)[1].lower()
    want = MAGIC.get(ext)
    if want and not any(head.startswith(w) for w in want):
        return ("文件头不对（前 8 字节是 %s），不像一个%s文件 —— "
                "多半是下载/解压中断留下的残件" % (head.hex(), ext))
    return None


def index_frames(d, exts):
    """把目录里的图片按帧号建索引 -> {帧号: 文件名}。重名帧号取排序后第一个。"""
    if not os.path.isdir(d):
        raise DataError("目录不存在：%s" % d)
    out = {}
    for name in sorted(os.listdir(d)):
        if not os.path.isfile(os.path.join(d, name)):
            continue
        if exts and os.path.splitext(name)[1].lower() not in exts:
            continue
        n = frame_no(name)
        if n is None:
            continue
        out.setdefault(n, name)
    return out


def frame_plan(seqdir, warmup=100, frames=0):
    """算出本次运行要用哪些帧 —— **唯一**的切分规则，所有入口共用。

    返回 dict：
        roi     (起, 止)      temporalROI，1 基
        first   本次读的第一帧（1 基）
        nwarm   开头有多少帧是**预热**（不计分）
        count   一共读多少帧（含预热）
        score   (第一帧计分帧号, 最后一帧计分帧号) 的闭区间

    frames = 0 使用完整 ROI；frames > 0 最多跑前 frames 个计分帧，
    始终截到 ROI 终点。warmup / frames 必须是非负整数。
    """
    for name, value in (("warmup", warmup), ("frames", frames)):
        if not isinstance(value, Integral) or value < 0:
            raise DataError("%s 必须是非负整数，实际为 %r" % (name, value))
    roi = read_roi(seqdir)
    r0, r1 = roi
    first = max(1, r0 - int(warmup))
    nwarm = r0 - first
    last = min(r1, r0 + int(frames) - 1) if frames else r1
    count = last - first + 1
    return {"roi": roi, "first": first, "nwarm": nwarm, "count": count,
            "score": (r0, last)}


# --------------------------------------------------------------------------
# 3. 严格校验
# --------------------------------------------------------------------------
def _fmt_problems(seqdir, problems):
    lines = ["序列 %s 的数据不完整，跑出来的分数不可信：" % seqdir]
    for kind, fr, path, why in problems:
        lines.append("    [%s] 第 %d 帧" % (kind, fr))
        lines.append("        文件：%s" % path)
        lines.append("        原因：%s" % why)
    lines += [
        "",
        "  CDnet2014 每条序列应该是这样的结构：",
        "      <序列>\\temporalROI.txt     <- 计分区间（1 基帧号）",
        "              \\input\\in%06d.jpg  <- 输入帧图，帧号连续",
        "              \\groundtruth\\gt%06d.png <- 计分帧的真值",
        "  多半是数据集没解压完整、下载时漏了文件，或解压中断留下了半截文件。",
        "  先跑 `python src/ps/algo_lab.py --data-root \"...\" --list` 看看扫到几条序列。",
    ]
    return "\n".join(lines)


def validate_sequence(seqdir, warmup=100, frames=0, decode=False, max_report=8):
    """按"这次实际要用的帧"检查一条序列，有问题抛 DataError。

    ★ 与旧版的区别（旧版只查"目录存在且非空"，所以下列情况全都漏过去）：
        · groundtruth 目录非空，但**少一张**真值图      -> 现在能抓到
        · 真值图**损坏**（能列出来，解码是 None）        -> 现在能抓到
        · 输入图损坏                                    -> 现在能抓到（旧版静默跳帧）

    参数
        decode    False（默认）= 快速档：查文件存在 + 非空 + 文件头是否像个正常图片。
                                实测 900 帧只要 0.3 s，能抓出"缺文件 / 0 字节 /
                                下载中断的残件"这些真实故障。
                  True          = 严格档：逐帧真解码 + 查尺寸是否一致。
                                实测 900 帧 21.8 s（慢 70 倍），适合下完数据后
                                一次性确认没有坏文件（命令行 --strict-data-check）。
                  ★ 不管哪一档，"真值能不能解码、尺寸对不对"在 load_seq 真正读取
                    那一遍都会再查一次，不会静默放过。
        max_report 最多列几条明细（避免几千帧刷屏）

    返回帧号计划 dict（供调用方接着 load_seq）。
    """
    plan = frame_plan(seqdir, warmup, frames)
    first, nwarm, count = plan["first"], plan["nwarm"], plan["count"]

    inp_dir = os.path.join(seqdir, "input")
    gt_dir = os.path.join(seqdir, "groundtruth")
    for d, label in ((inp_dir, "input/"), (gt_dir, "groundtruth/")):
        if not os.path.isdir(d):
            raise DataError(_fmt_problems(
                seqdir, [("目录缺失", 0, d, "序列里应该有 %s 这个子目录" % label)]))

    in_idx = index_frames(inp_dir, {".jpg", ".jpeg", ".png", ".bmp"})
    gt_idx = index_frames(gt_dir, {".png", ".jpg", ".jpeg", ".bmp"})
    if not in_idx:
        raise DataError(_fmt_problems(
            seqdir, [("目录为空", 0, inp_dir, "input/ 里没有找到任何带帧号的图片")]))

    problems = []
    ref_shape = None
    for i in range(count):
        fr = first + i
        scoring = (i >= nwarm)

        iname = in_idx.get(fr)
        if iname is None:
            problems.append(("输入缺失", fr, os.path.join(inp_dir, "in%06d.jpg" % fr),
                             "本次运行需要第 %d 帧，input/ 里没有这一帧"
                             "（input 现有帧号 %d~%d）"
                             % (fr, min(in_idx), max(in_idx))))
            continue
        ipath = os.path.join(inp_dir, iname)

        gname = gt_idx.get(fr)
        gpath = os.path.join(gt_dir, gname) if gname else \
            os.path.join(gt_dir, "gt%06d.png" % fr)
        if gname is None and scoring:
            problems.append(("真值缺失", fr, gpath,
                             "这是**计分帧**，真值必须存在；groundtruth 现有帧号 %s"
                             % ("%d~%d" % (min(gt_idx), max(gt_idx)) if gt_idx else "（空）")))
            continue

        if not decode:
            # 快速档：不解码，只查"存在 + 非空 + 文件头像个正常图片"。
            # ★ 能抓出绝大多数真实故障（文件缺失、0 字节、下载中断的残件），
            #   而逐帧真解码要慢 70 倍（实测 900 帧 21.8 s vs 0.3 s）。
            #   真正"能解码、尺寸匹配"的判定放在 load_seq 那一遍 —— 那边是
            #   一次性严格读取，读到哪帧有问题就报哪帧，一样不会静默放过。
            why = check_file_head(ipath)
            if why:
                problems.append(("输入损坏", fr, ipath, why))
                continue
            if gname is not None:
                why = check_file_head(gpath)
                if why:
                    problems.append(("真值损坏", fr, gpath, why))
                    continue
            continue

        try:
            img = imread(ipath, cv2.IMREAD_COLOR)
        except DataError as e:
            problems.append(("输入损坏", fr, ipath, str(e).split("\n")[0]))
            continue
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        if ref_shape is None:
            ref_shape = gray.shape
        elif gray.shape != ref_shape:
            problems.append(("输入尺寸不一致", fr, ipath,
                             "本帧 %dx%d，与首帧 %dx%d 不一样"
                             % (gray.shape[1], gray.shape[0],
                                ref_shape[1], ref_shape[0])))
            continue

        if gname is not None:
            try:
                gt = read_gray(gpath)
            except DataError as e:
                problems.append(("真值损坏", fr, gpath, str(e).split("\n")[0]))
                continue
            if gt.shape != gray.shape:
                kind = "真值尺寸不符" if scoring else "预热真值尺寸不符"
                problems.append((kind, fr, gpath,
                                 "真值 %dx%d，输入 %dx%d —— 两者必须同尺寸才能逐像素比"
                                 % (gt.shape[1], gt.shape[0],
                                    gray.shape[1], gray.shape[0])))

    if problems:
        shown = problems[:max_report]
        msg = _fmt_problems(seqdir, shown)
        if len(problems) > len(shown):
            msg += ("\n  （另有 %d 处同类问题未列出，修完上面这些再跑一次会继续报）"
                    % (len(problems) - len(shown)))
        raise DataError(msg)
    return plan


# --------------------------------------------------------------------------
# 4. 严格加载
# --------------------------------------------------------------------------
def load_seq(seqdir, first, count, nwarm=0):
    """严格读入 [first, first+count-1] 这些帧。

    返回 (灰度帧 list, 真值 list, 输入文件名 list)。

    ★ 与旧版的区别：
        旧版：输入读不出来 -> `continue` **静默跳帧**（后面的帧整体前移，
              帧号与真值错位，分数悄悄变错）；真值读不出来 -> `np.zeros_like`
              **填一张全背景图**（等于告诉算法"这帧没有目标"，召回率被吃掉）。
        新版：两者都抛 DataError，并在报错里写清序列、帧号、文件路径、原因。

    真值规则（与 validate_sequence 一致）：
        计分帧（索引 >= nwarm）必须有真值；
        预热帧真值缺失是允许的 —— CDnet 官方本就只标注 ROI 区间内，
        缺了就填全零占位（不参与计分），但会打印一句说明。
    """
    inp_dir = os.path.join(seqdir, "input")
    gt_dir = os.path.join(seqdir, "groundtruth")
    in_idx = index_frames(inp_dir, {".jpg", ".jpeg", ".png", ".bmp"})
    gt_idx = index_frames(gt_dir, {".png", ".jpg", ".jpeg", ".bmp"})

    grays, labels, names, missing_gt = [], [], [], []
    ref_shape = None
    for i in range(count):
        fr = first + i
        scoring = (i >= nwarm)

        iname = in_idx.get(fr)
        if iname is None:
            raise DataError(
                "序列 %s 第 %d 帧：input/ 里没有这一帧（现有帧号 %s）。\n"
                "  期望文件：%s\n"
                "  ★ 不跳帧继续跑 —— 跳帧会让后面的帧号与真值错位，分数是错的。"
                % (seqdir, fr,
                   "%d~%d" % (min(in_idx), max(in_idx)) if in_idx else "（空）",
                   os.path.join(inp_dir, "in%06d.jpg" % fr)))
        ipath = os.path.join(inp_dir, iname)
        try:
            img = imread(ipath, cv2.IMREAD_COLOR)
        except DataError as e:
            raise DataError(
                "序列 %s 第 %d 帧：输入帧读不出来 —— %s\n"
                "  ★ 不跳帧继续跑 —— 少一帧就会让后面的帧号整体错位。"
                % (seqdir, fr, e))
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        if ref_shape is None:
            ref_shape = gray.shape
        elif gray.shape != ref_shape:
            raise DataError(
                "序列 %s 第 %d 帧：输入尺寸 %dx%d 与首帧 %dx%d 不一致 —— %s"
                % (seqdir, fr, gray.shape[1], gray.shape[0],
                   ref_shape[1], ref_shape[0], ipath))

        gname = gt_idx.get(fr)
        if gname is None:
            if scoring:
                raise DataError(
                    "序列 %s 第 %d 帧：这是**计分帧**但没有真值图。\n"
                    "  期望文件：%s\n"
                    "  真值目录：%s（现有 %d 张）\n"
                    "  ★ 不用全零图顶替 —— 那等于告诉算法\"这帧没有目标\"，"
                    "召回率会被悄悄吃掉，且没有任何报错。"
                    % (seqdir, fr, os.path.join(gt_dir, "gt%06d.png" % fr),
                       gt_dir, len(gt_idx)))
            missing_gt.append(fr)
            labels.append(np.zeros_like(gray))
        else:
            gpath = os.path.join(gt_dir, gname)
            try:
                gt = read_gray(gpath)
            except DataError as e:
                raise DataError(
                    "序列 %s 第 %d 帧：真值图读不出来 —— %s\n"
                    "  ★ 不填全零 —— 损坏的真值会让这一帧的分数完全不可信。"
                    % (seqdir, fr, e))
            if gt.shape != gray.shape:
                raise DataError(
                    "序列 %s 第 %d 帧：真值 %dx%d 与输入 %dx%d 尺寸不符 —— %s\n"
                    "  ★ 逐像素比对要求两者同尺寸，不能靠裁剪蒙过去。"
                    % (seqdir, fr, gt.shape[1], gt.shape[0],
                       gray.shape[1], gray.shape[0], gpath))
            labels.append(gt)

        grays.append(gray)
        names.append(iname)

    if not grays:
        raise DataError("序列 %s：一帧都没读进来（要第 %d~%d 帧）"
                        % (seqdir, first, first + count - 1))
    if missing_gt:
        print("  （说明：第 %s 帧是预热帧，官方本就不保证有真值，已用全零占位且不参与计分）"
              % ("、".join(str(x) for x in missing_gt[:6])
                 + ("…" if len(missing_gt) > 6 else "")))
    return grays, labels, names
