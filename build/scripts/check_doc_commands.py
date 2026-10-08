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
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

# 匹配文档里的命令行：python 某个.py 后面跟一堆参数
CMD_RE = re.compile(r"python\s+([A-Za-z0-9_./\\-]+\.py)((?:\s+--?[A-Za-z0-9_-]+)*)")
# 匹配脚本里定义的参数
ARG_RE = re.compile(r"add_argument\(\s*[\"'](--[A-Za-z0-9_-]+)[\"']")

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


def script_params(path):
    """读脚本源码，抽出它定义的全部 --参数。"""
    try:
        src = io.open(path, encoding="utf-8", errors="replace").read()
    except Exception:
        return None
    return set(ARG_RE.findall(src))


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
                params = cache[full]
                if params is None:
                    continue

                # 该脚本完全没定义参数 → 命令行参数无从谈起，跳过（多半是 demo 脚本）
                if not params:
                    continue

                for u in used:
                    if u not in params:
                        errors.append(
                            "%s:%d  ★ %s **没有**参数 %s\n"
                            "        （该脚本定义的参数：%s）"
                            % (rel_md, i, os.path.basename(raw_script), u,
                               ", ".join(sorted(params)))
                        )

    print("检查了 %d 条命令（来自 %d 个 .md）" % (checked, len(repo_files(".md"))))
    if errors:
        print("")
        print("★ 发现 %d 个问题：" % len(errors))
        for e in errors:
            print("   " + e)
        print("")
        print("修法：打开对应脚本，看它 argparse 里的真实参数名，别照记忆抄。")
        return 1

    print("✅ 文档里所有命令的参数都真实存在")
    return 0


if __name__ == "__main__":
    sys.exit(main())