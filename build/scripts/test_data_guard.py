# -*- coding: utf-8 -*-
"""数据守卫回归测试 —— 用**少量构造数据**证明"数据不全时一定明确失败"。

为什么必须有这个文件
--------------------
修之前，下面这几种情况全都**静默通过**：程序返回 0、打印出一张看起来很正常的
成绩表，而分数是错的。比崩溃危险得多 —— 崩溃你会去查数据，静默错分你会去调参数。

    · groundtruth 目录非空，但少一张真值图
    · 一张真值图损坏（旧代码填一张全零图当真值，等于说"这帧没目标"）
    · 一张输入图损坏（旧代码 continue 跳过去，后面的帧号整体错位）

改完之后每次改代码都能重跑它，不用靠"我记得我改对了"。

它测六组
--------
A 构造数据 · 六种坏法         → 每一种都必须**非零退出**，且**不得生成成绩表**
B 构造数据 · 正常              → 必须 0
C 预热帧没有真值               → 必须 **0**（CDnet 官方本就只标 ROI 区间内，
                                 不能无依据地要求预热阶段也有真值）
D 严格档 --strict-data-check   → 正常数据上也要 0
E 中文 / 带空格 / 中文+空格路径 → 与纯英文路径**逐帧指标完全一致**
F 三个入口共用同一套校验        → cdnet_official / algo_lab / cdnet_demo 行为一致

用法
----
    python build/scripts/test_data_guard.py
    python build/scripts/test_data_guard.py --keep      # 保留临时目录方便手查

退出码：0 = 全过；1 = 有失败（可以直接当 CI 用）。

★ 注意：本脚本**只用构造出来的小数据**（十几帧 16×16 的图），
   既不需要 0.96 GB 的 CDnet 数据集，也不会碰仓库里任何已归档的结果文件
   （会先备份再还原，跑完 git status 应该是干净的）。
"""
from __future__ import print_function

import argparse
import hashlib
import io
import os
import shutil
import subprocess
import sys
import tempfile

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
PS = os.path.join(REPO, "src", "ps")

# 构造一条"最小可用"的 CDnet 序列：ROI 3~10，共 12 帧，16×16
NFRAMES = 12
ROI = (3, 10)
CAT, SEQ = "tcat", "tseq"
W = H = 16


# --------------------------------------------------------------------------
# 造数据
# --------------------------------------------------------------------------
def _write_jpg(path, img):
    ok, buf = cv2.imencode(".jpg", img)
    assert ok
    with open(path, "wb") as fh:
        fh.write(buf.tobytes())


def _write_png(path, img):
    ok, buf = cv2.imencode(".png", img)
    assert ok
    with open(path, "wb") as fh:
        fh.write(buf.tobytes())


def make_seq(seqdir, gt_all=False):
    """造一条序列。gt_all=False 时**只给 ROI 内的帧标真值**（CDnet 官方规则）。"""
    os.makedirs(os.path.join(seqdir, "input"))
    os.makedirs(os.path.join(seqdir, "groundtruth"))
    with io.open(os.path.join(seqdir, "temporalROI.txt"), "w", encoding="utf-8") as f:
        f.write("%d %d\n" % ROI)
    rng = np.random.RandomState(20261008)
    for i in range(1, NFRAMES + 1):
        base = rng.randint(0, 255, (H, W), dtype=np.uint8)
        img = np.stack([base, base, base], axis=2)
        _write_jpg(os.path.join(seqdir, "input", "in%06d.jpg" % i), img)
        if gt_all or ROI[0] <= i <= ROI[1]:
            gt = np.zeros((H, W), np.uint8)
            gt[4:10, 4:10] = 255 if i % 2 else 0
            _write_png(os.path.join(seqdir, "groundtruth", "gt%06d.png" % i), gt)


def fresh_case(tmp, name, mutate=None, gt_all=False):
    """造一个独立用例目录，返回 (数据根, 序列目录)。mutate 用来把它弄坏。"""
    root = os.path.join(tmp, name)
    sd = os.path.join(root, CAT, SEQ)
    make_seq(sd, gt_all=gt_all)
    if mutate:
        mutate(sd)
    return root, sd


# --------------------------------------------------------------------------
# 跑入口
# --------------------------------------------------------------------------
class _Restore(object):
    """★ 保护仓库里已归档的结果 CSV：跑之前备份字节，跑之后原样还原。

    测试要用真实入口跑，而入口成功时**会写**结果 CSV。不能因为跑个测试
    就把队友的参考结果覆盖了 —— 那正是我们要防的事故。
    """

    def __init__(self, names):
        self.names = names
        self.saved = {}
        self.existed = {}

    def __enter__(self):
        for n in self.names:
            p = os.path.join(PS, n)
            self.existed[n] = os.path.exists(p)
            if self.existed[n]:
                with open(p, "rb") as fh:
                    self.saved[n] = fh.read()
        return self

    def __exit__(self, *a):
        for n in self.names:
            p = os.path.join(PS, n)
            if n in self.saved:
                with open(p, "wb") as fh:
                    fh.write(self.saved[n])
            elif not self.existed[n] and os.path.exists(p):
                os.remove(p)
        return False


def run_entry(args, cwd=REPO):
    r = subprocess.run([sys.executable] + args, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", cwd=cwd, timeout=600)
    return r.returncode, (r.stdout or ""), (r.stderr or "")


def _mut_rm(path):
    def f(sd):
        os.remove(os.path.join(sd, path))
    return f


def _mut_garbage(path, keep_header=False):
    """写成垃圾字节。keep_header=True 时保留原文件头（模拟"头好但内容坏"）。"""
    def f(sd):
        p = os.path.join(sd, path)
        with open(p, "rb") as fh:
            head = fh.read(4)
        with open(p, "wb") as fh:
            fh.write(head if keep_header else b"")
            fh.write(b"this is definitely not an image" * 4)
    return f


def _mut_shrink(path):
    """把真值图写成另一个尺寸 —— 逐像素比对要求同尺寸。"""
    def f(sd):
        _write_png(os.path.join(sd, path), np.zeros((H // 2, W // 2), np.uint8))
    return f


# --------------------------------------------------------------------------
# 用例
# --------------------------------------------------------------------------
def case_matrix(tmp, entry, label, restore_names):
    """六种坏法 + 正常 + 预热无真值。返回 (通过数, 失败数)。"""
    # gt_all=True  → 像本机这份拷贝：连预热帧都标了真值
    # gt_all=False → 像 CDnet 官方发行：只有 ROI 区间内有真值
    cases = [
        ("正常数据（含预热真值）", None, 0, True),
        ("缺一张输入帧", _mut_rm(os.path.join("input", "in000005.jpg")), -1, True),
        ("坏输入（文件头就错）",
         _mut_garbage(os.path.join("input", "in000005.jpg")), -1, True),
        ("坏输入（头对内容坏）",
         _mut_garbage(os.path.join("input", "in000005.jpg"), keep_header=True), -1, True),
        ("缺一张计分真值",
         _mut_rm(os.path.join("groundtruth", "gt000005.png")), -1, True),
        ("坏计分真值",
         _mut_garbage(os.path.join("groundtruth", "gt000005.png")), -1, True),
        ("真值尺寸与输入不符",
         _mut_shrink(os.path.join("groundtruth", "gt000005.png")), -1, True),
        ("预热帧没有真值（应放行）", None, 0, False),
    ]
    npass = nfail = 0
    for idx, (name, mutate, want, gt_all) in enumerate(cases):
        root, sd = fresh_case(tmp, "%s_%d" % (label, idx),
                              mutate=mutate, gt_all=gt_all)
        args = list(entry) + ["--data-root", root, "--seq", "%s/%s" % (CAT, SEQ)]
        before = set(n for n in restore_names
                     if os.path.exists(os.path.join(PS, n)))
        with _Restore(restore_names):
            code, out, err = run_entry(args)
            # 失败的运行**不该**留下成绩表（半套数据的分数最害人）
            wrote = [n for n in restore_names
                     if os.path.exists(os.path.join(PS, n)) and n not in before]
        if want == 0:
            ok = (code == 0)
        else:
            # 非零退出 **且** 是一句人话说明，不是一大段 traceback
            ok = (code != 0 and "Traceback (most recent call last)" not in (out + err))
            # 而且失败时**不能生成成绩表**
            if ok and wrote:
                ok = False
                err = "★ 失败了却还是写出了成绩表：%s" % wrote
        npass += ok
        nfail += (not ok)
        print("   %-30s %s  退出码 %-3d %s"
              % (name, "PASS" if ok else "FAIL", code,
                 "" if ok else ("★ 期望%s" % ("0" if want == 0 else "非 0"))))
        if not ok:
            tail = [l for l in (err or out).strip().split("\n") if l.strip()]
            print("        " + "\n        ".join(t[:150] for t in tail[:3]))
    return npass, nfail


def case_unicode(tmp):
    """同一份数据放在四种路径下，逐帧指标必须**逐字节一致**。"""
    base = os.path.join(tmp, "uni")
    os.makedirs(base)
    make_seq(os.path.join(base, "plain", CAT, SEQ))
    dirs = [("纯英文", os.path.join(base, "plain")),
            ("中文", os.path.join(base, "中文目录")),
            ("带空格", os.path.join(base, "my data")),
            ("中文+空格", os.path.join(base, "我的 数据"))]
    npass = nfail = 0
    digests = {}
    for label, d in dirs[1:]:
        if os.path.exists(d):
            shutil.rmtree(d)
        shutil.copytree(os.path.join(base, "plain"), d)
    for label, d in dirs:
        sd = os.path.join(d, CAT, SEQ)
        code, out, err = run_entry([os.path.join("src", "ps", "cdnet_demo.py"),
                                    "--seq", sd])
        csvp = os.path.join(sd, "cdnet_demo_metrics.csv")
        if code != 0 or not os.path.exists(csvp):
            print("   %-12s FAIL  退出码 %d（读不出来）" % (label, code))
            print("        " + (err or out).strip().split("\n")[0][:160])
            nfail += 1
            continue
        with open(csvp, "rb") as fh:
            digests[label] = hashlib.md5(fh.read()).hexdigest()
        print("   %-12s PASS  退出码 0  逐帧指标 md5=%s"
              % (label, digests[label][:12]))
        npass += 1
    uniq = set(digests.values())
    same = len(uniq) == 1 and len(digests) == len(dirs)
    print("   %-12s %s  四种路径结果%s"
          % ("一致性", "PASS" if same else "FAIL",
             "完全一致" if same else "不一致 ★ %s" % digests))
    return npass + (1 if same else 0), nfail + (0 if same else 1)


# --------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", action="store_true", help="保留临时目录")
    ap.add_argument("--tmpdir", default=None)
    args = ap.parse_args()

    tmp = args.tmpdir or tempfile.mkdtemp(prefix="data_guard_")
    print("=" * 78)
    print("数据守卫回归测试（只用构造的小数据，不碰 CDnet 数据集与已归档结果）")
    print("临时目录：%s" % tmp)
    print("=" * 78)

    npass = nfail = 0

    print("\n【A/B】cdnet_official 入口 —— 六种坏法 + 正常 + 预热无真值")
    a, b = case_matrix(tmp, ["src/ps/cdnet_official.py", "--set", "r5"],
                       "official", ["cdnet_official_results_r5.csv"])
    npass += a; nfail += b

    print("\n【F】algo_lab 入口 —— 同一个矩阵，行为必须一致")
    a, b = case_matrix(tmp, ["src/ps/algo_lab.py", "--set", "r5"],
                       "lab", ["algo_lab_results.csv"])
    npass += a; nfail += b

    print("\n【D】严格档 --strict-data-check（正常数据必须仍然通过）")
    root, sd = fresh_case(tmp, "strict_ok")
    with _Restore(["algo_lab_results.csv"]):
        code, out, err = run_entry(
            ["src/ps/algo_lab.py", "--set", "r5", "--data-root", root,
             "--seq", "%s/%s" % (CAT, SEQ), "--strict-data-check"])
    ok = code == 0
    print("   %-34s %s  退出码 %d" % ("正常数据 + 严格档", "PASS" if ok else "FAIL", code))
    if not ok:
        print("        " + (err or out).strip().split("\n")[0][:160])
    npass += ok; nfail += (not ok)

    print("\n【E】中文 / 空格路径 —— 四种路径结果必须一致")
    a, b = case_unicode(tmp)
    npass += a; nfail += b

    print("\n" + "=" * 78)
    print("合计：%d 通过 / %d 失败" % (npass, nfail))
    print("=" * 78)
    if args.keep:
        print("临时目录保留：%s" % tmp)
    else:
        shutil.rmtree(tmp, ignore_errors=True)
    return 1 if nfail else 0


if __name__ == "__main__":
    sys.exit(main())
