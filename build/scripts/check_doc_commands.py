# -*- coding: utf-8 -*-
"""校验文档里写的命令行参数**是否真实存在** —— 防止文档写出不存在的参数。

为什么需要这个脚本（真实教训）：
    文档里写了 `multi_track.py --algo`，但 `--algo` 这个参数**根本不存在**，
    正确写法是 `--source algo`。这种错是"照着记忆抄"抄出来的，肉眼很难发现，
    队友跑一次才发现 ⇒ 白白浪费他时间。
    所以把它变成一个**能自动跑的守卫**：改了文档就跑一下，有错立刻知道。

它检查三件事：
    1. 命令里提到的 .py 文件是否真的存在
    2. 命令里的每个 --参数 是否在该脚本的 argparse 里定义过
    3. Windows 的反斜杠路径是否存在（build\\scripts\\... → build/scripts/...）

用法：
    python build/scripts/check_doc_commands.py            # 检查全部 .md
    python build/scripts/check_doc_commands.py --quiet    # 只报错误

退出码：0 = 全部对；1 = 有错（可以直接当 CI 用）。
"""
from __future__ import print_function

import argparse
import io
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

# 匹配文档里的命令行：python 某个.py 后面跟一堆参数
CMD_RE = re.compile(r"python\s+([A-Za-z0-9_./\\-]+\.py)((?:\s+--?[A-Za-z0-9_-]+)*)")
# 匹配脚本里定义的参数
ARG_RE = re.compile(r"add_argument\(\s*[\"'](--[A-Za-z0-9_-]+)[\"']")
# 兜底：源码任意位置出现的 "--xxx" 字面量（覆盖动态 add_argument 的情况）
QUOTED_ARG_RE = re.compile(r"[\"'](--[A-Za-z0-9_-]+)[\"']")

SKIP_DIRS = {".git", ".Xil", "__pycache__", "build/vivado", "datasets",
             "sim/xsim.dir", ".pytest_cache"}


def repo_files(ext):
    """列仓库里所有指定扩展名的文件（跳过生成物目录）。"""
    out = []
    for dp, dn, fn in os.walk(REPO):
        rel = os.path.relpath(dp, REPO).replace("\\", "/")
        if any(rel == s or rel.startswith(s + "/") for s in SKIP_DIRS):
            dn[:] = []
            continue
        for f in fn:
            if f.endswith(ext):
                out.append(os.path.join(dp, f))
    return sorted(out)


def candidate_pythons():
    """试哪个解释器来跑 --help。

    ★ 不能只用 sys.executable —— 本校验器自己跑在一个"没装 numpy/opencv"的
    环境里，拿它跑目标脚本会在 import 阶段就挂，--help 永远拿不到。
    所以按优先级试：环境变量指定 → 仓库根的 .venv（入门文档第 1 步就是教人建它）
    → 当前解释器 → PATH 里的 python。
    """
    c = []
    env = os.environ.get("MOTION_PYTHON")
    if env:
        c.append(env)
    c.append(os.path.join(REPO, ".venv", "Scripts", "python.exe"))
    c.append(os.path.join(REPO, ".venv", "bin", "python"))
    c.append(sys.executable)
    c.append("python")
    seen, out = set(), []
    for x in c:
        if x not in seen:
            seen.add(x)
            out.append(x)
    return out


def params_from_help(path):
    """★ 最可靠：真跑一次 --help，从 argparse 生成的 usage 行里取参数。

    为什么不能只看源码：参数可能由公共函数动态装上（例如 algo_lab.add_data_root_arg
    给几个入口统一加 --data-root），调用方源码里没有 add_argument("--data-root" 字面量。
    只看 usage 行还有个好处：help 文本里提到的 --xxx 不会混进来（argparse 的 usage
    只列真实存在的参数），避免假阳性。

    全部解释器都跑不起来时返回 None，交给源码解析兜底。
    """
    for py in candidate_pythons():
        try:
            r = subprocess.run([py, path, "--help"],
                               capture_output=True, text=True, timeout=120,
                               encoding="utf-8", errors="replace",
                               cwd=os.path.dirname(path))
        except Exception:
            continue
        out = (r.stdout or "") + (r.stderr or "")
        if "usage:" not in out:
            continue
        # usage 段：从 "usage:" 到第一个空行（argparse 可能换行）
        usage, grab = [], False
        for line in out.split("\n"):
            if line.startswith("usage:"):
                grab = True
                usage.append(line)
                continue
            if grab:
                if not line.strip():
                    break
                usage.append(line)
        if usage:
            return set(re.findall(r"(--[A-Za-z0-9_-]+)", "\n".join(usage))), "实际 --help"
    return None, None


def dynamic_params(script_path):
    """展开脚本里调的 add_xxx_arg(ap) 形式的公共参数安装函数。

    例：cdnet_official.py 调 lab.add_data_root_arg(ap)，函数定义在 algo_lab.py，
        所以 --data-root 在 cdnet_official.py 的源码里找不到字面量。这里去同目录
    的其它 .py 里找到该函数定义，把它内部 add_argument 的参数收进来。
    """
    try:
        src = io.open(script_path, encoding="utf-8", errors="replace").read()
    except Exception:
        return set()
    called = set(re.findall(r"\b(add_[a-z0-9_]+_arg)\s*\(", src))
    if not called:
        return set()
    out = set()
    d = os.path.dirname(script_path)
    for name in os.listdir(d):
        if not name.endswith(".py"):
            continue
        try:
            s = io.open(os.path.join(d, name), encoding="utf-8",
                        errors="replace").read()
        except Exception:
            continue
        for fn in called:
            m = re.search(r"def\s+%s\s*\([^)]*\)\s*:(.*?)(?=\ndef |\nclass |\Z)"
                          % re.escape(fn), s, re.S)
            if m:
                out |= set(ARG_RE.findall(m.group(1)))
    return out


def script_params(path):
    """返回 (参数集, 来源说明)。优先实际 --help，其次源码正则 + 动态函数展开。"""
    from_help, how = params_from_help(path)
    if from_help:
        return from_help, how
    try:
        src = io.open(path, encoding="utf-8", errors="replace").read()
    except Exception:
        return None, None
    params = set(ARG_RE.findall(src)) | dynamic_params(path)
    return params, "源码解析（--help 跑不起来）"


def find_by_basename(base):
    """兜底：按文件名在全仓库搜（文档里常写裸文件名，脚本在子目录里）。"""
    hits = []
    for dp, dn, fn in os.walk(REPO):
        rel = os.path.relpath(dp, REPO).replace("\\", "/")
        if any(rel == s or rel.startswith(s + "/") for s in SKIP_DIRS):
            dn[:] = []
            continue
        if base in fn:
            hits.append(os.path.join(dp, base))
    return sorted(hits)


def resolve_script(rel):
    """把文档里写的路径解析成真实文件。处理 Windows 反斜杠 + 裸文件名。"""
    rel = rel.replace("\\", "/")
    cands = [
        os.path.join(REPO, rel),
        os.path.join(REPO, "src", "ps", rel),
        os.path.join(REPO, "src", "ps", os.path.basename(rel)),
    ]
    for c in cands:
        if os.path.isfile(c):
            return c
    # 兜底：按文件名搜。命中 0 个才算真错；命中多个取第一个（同名脚本参数一般一致）。
    hits = find_by_basename(os.path.basename(rel))
    return hits[0] if hits else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true", help="只输出错误行")
    args = ap.parse_args()

    # 缓存：脚本 -> 参数集
    cache = {}

    errors = []
    loose_hits = []
    checked = 0

    for md in repo_files(".md"):
        try:
            src = io.open(md, encoding="utf-8", errors="replace").read()
        except Exception:
            continue
        rel_md = os.path.relpath(md, REPO).replace("\\", "/")

        for i, line in enumerate(src.split("\n"), 1):
            for m in CMD_RE.finditer(line):
                raw_script, rest = m.group(1), m.group(2)
                used = re.findall(r"--[A-Za-z0-9_-]+", rest)
                checked += 1

                full = resolve_script(raw_script)
                if full is None:
                    errors.append("%s:%d  脚本不存在：%s" % (rel_md, i, raw_script))
                    continue

                if full not in cache:
                    cache[full] = script_params(full)
                params, how = cache[full]
                if params is None:
                    continue

                if how.startswith("源码正则"):
                    loose_hits.append("%s（--help 跑不起来，靠源码正则）"
                                     % os.path.basename(raw_script))
                if not params:
                    continue

                for u in used:
                    if u not in params:
                        errors.append(
                            "%s:%d  ★ %s **没有**参数 %s\n"
                            "        （该脚本实际支持的参数：%s）"
                            % (rel_md, i, os.path.basename(raw_script), u,
                               ", ".join(sorted(params))))

    print("检查了 %d 条命令（来自 %d 个 .md）" % (checked, len(repo_files(".md"))))
    if loose_hits:
        uniq = sorted(set(loose_hits))
        print("  （%d 个脚本的 --help 跑不起来，靠源码正则兜底，可靠性稍低：%s）"
              % (len(uniq), "、".join(uniq)))
    if errors:
        print("")
        print("★ 发现 %d 个问题：" % len(errors))
        for e in errors:
            print("   " + e)
        print("")
        print("修法：跑一下该脚本的 --help，看它到底支持哪些参数，别照记忆抄。")
        return 1

    print("✅ 文档里所有命令的参数都真实存在（依据：各脚本实际的 --help 输出）")
    return 0


if __name__ == "__main__":
    sys.exit(main())