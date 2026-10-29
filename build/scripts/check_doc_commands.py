# -*- coding: utf-8 -*-
"""校验文档里写的命令行参数**是否真实存在** —— 防止文档写出不存在的参数。

为什么需要这个脚本（真实教训）：
    文档里写了 `multi_track.py --algo`，但 `--algo` 这个参数**根本不存在**，
    正确写法是 `--source algo`。这种错是"照着记忆抄"抄出来的，肉眼很难发现，
    队友跑一次才发现 ⇒ 白白浪费他时间。
    所以把它变成一个**能自动跑的守卫**：改了文档就跑一下，有错立刻知道。

它检查两件事：
    1. 命令里提到的 .py 文件是否真的存在
    2. 命令里的每个 --参数 是否在该脚本的 argparse 里定义过

★ 反面例子怎么标（**别靠"忽略某个参数名"这种土办法**）
----------------------------------------------------
文档里需要出现"错误写法"来告诉读者别这么干（比如上面那个 --algo）。
旧版脚本靠"看到 --algo 就跳过"来躲开它 —— 这等于把规则写死在一个参数名上，
换个错参数就又误报了，而且读者也不知道哪句是反例。

现在的规则是**显式标记**：一行里只要带这个 HTML 注释，整行就不参与检查：

    <!-- 反例：下面这行是错的，别照抄 -->

HTML 注释在渲染出来的文档里看不见，但源码里一眼能看到，也好 grep。
也认 `<!-- doc-check: skip -->`。

用法：
    python build/scripts/check_doc_commands.py            # 检查全部 .md
    python build/scripts/check_doc_commands.py --quiet    # 只报错误
    python build/scripts/check_doc_commands.py --self-test # 自检：喂它几段真假命令

退出码：0 = 全部对；1 = 有错（可以直接当 CI 用）。

★ 边界：本脚本**只跑各脚本的 --help**，绝不真正跑评测、不生成任何东西、
   不写仓库里的任何文件 —— 它自己就是个只读的守卫。
"""
from __future__ import print_function

import argparse
import io
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

# 命令头：python [可选 -x 开关] <脚本.py>。脚本路径允许带引号（含空格的中文路径）
CMD_HEAD_RE = re.compile(
    r"""python\s+(?:-[A-Za-z]\s+)*(?:"([^"]+\.py)"|'([^']+\.py)'|([^\s"']+\.py))""")
# 引号可出现在词中（--outdir="我的 数据"）；只有未引用的 shell 分隔符结束命令。
TOKEN_RE = re.compile(r"""(?:"[^"]*"|'[^']*'|[^\s"'`|&;<>]+)+|[`|&;<>]""")
# 参数：--xxx 或 --xxx=值
FLAG_RE = re.compile(r"^--[A-Za-z0-9][A-Za-z0-9_-]*(?:=.*)?$")
# 反面例子标记（HTML 注释，渲染后不可见，源码里好认好查）
NEGATIVE_RE = re.compile(r"<!--[^>]*(?:反例|反面例子|doc-check:\s*skip)[^>]*-->")
# 续行：bash 用 \ 、cmd 用 ^ 、PowerShell 用反引号。
CONTINUE_RE = re.compile(r"[\\^`]\s*$")

# 脚本里定义的参数
ARG_RE = re.compile(r"add_argument\(\s*[\"'](--[A-Za-z0-9_-]+)[\"']")

SKIP_DIRS = {".git", ".Xil", "__pycache__", "build/vivado", "datasets",
             "sim/xsim.dir", ".pytest_cache"}

# 参数来源的三种说明。★ 必须如实区分，不能"靠源码猜的"也说成"依据实际 --help"。
SRC_HELP = "实际 --help"
SRC_GUESS = "源码推断（--help 取不到，可靠性降低）"
SRC_NOARG = "该脚本不用 argparse（没有参数可查）"

# ★★ 安全红线：只对**声明了 argparse** 的脚本跑 --help。
# 仓库里有几个脚本根本没有 argparse（make_figures.py / mmcm_search.py /
# view_sim.py / fix_bat_eol.py），它们的 `xxx.py --help` 会**把 --help 当成普通
# 参数、直接把任务跑一遍** —— 实测 make_figures.py --help 重新生成了插图并覆盖了
# 已归档的 data/golden/fig_error.png，mmcm_search.py --help 写出了 mmcm_result.txt。
# 也就是说：这个"只读守卫"以前每次运行都会**污染仓库**。现在先查源码再决定跑不跑。
HAS_ARGS_RE = re.compile(r"\badd_argument\s*\(")


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

    ★ 只跑 --help：不跑评测、不生成任何东西、不写仓库文件。

    全部解释器都跑不起来时返回 None，交给源码推断兜底（并如实标注降级）。
    """
    for py in candidate_pythons():
        try:
            r = subprocess.run([py, path, "--help"],
                               capture_output=True, text=True, timeout=120,
                               encoding="utf-8", errors="replace",
                               cwd=os.path.dirname(path),
                               env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1",
                                        PYTHONUTF8="1", PYTHONIOENCODING="utf-8"))
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
            return set(re.findall(r"(--[A-Za-z0-9_-]+)", "\n".join(usage)))
    return None


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
    """返回 (参数集, 来源说明)。

    ★ 先读源码看它有没有 argparse：
        · 没有 → **绝不运行它**，直接返回 SRC_NOARG。
          （运行这类脚本的 --help 会把任务真的跑一遍，见 HAS_ARGS_RE 处的说明。）
        · 有   → 优先实际 --help；拿不到才退回源码正则 + 动态函数展开，
                 并**如实标注**来源为 SRC_GUESS。
    """
    try:
        src = io.open(path, encoding="utf-8", errors="replace").read()
    except Exception:
        return None, SRC_NOARG
    if not HAS_ARGS_RE.search(src):
        return None, SRC_NOARG
    from_help = params_from_help(path)
    if from_help:
        return from_help, SRC_HELP
    params = set(ARG_RE.findall(src)) | dynamic_params(path)
    return params, SRC_GUESS


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
    """把文档里写的路径解析成真实文件。处理 Windows 反斜杠 + 裸文件名 + 引号。"""
    rel = rel.replace("\\", "/").strip('"').strip("'")
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


def logical_lines(src):
    """拼接 bash/cmd/PowerShell 续行，保留 Markdown 行内代码的结束边界。

    返回 [(行号, 拼接后的文本)]。反面例子标记按**原始行**判断，所以这里
    同时把参与拼接的所有原始行文本带上。
    """
    raw = src.split("\n")
    out = []
    i = 0

    def continued(line):
        match = CONTINUE_RE.search(line)
        if not match:
            return False
        if match.group().lstrip().startswith("`"):
            # 成对的 Markdown 行内代码、代码围栏不是 PowerShell 续行。
            return line.count("`") % 2 == 1 and not line.lstrip().startswith("```")
        return True

    while i < len(raw):
        start = i
        parts = [raw[i]]
        joined = []
        while continued(raw[i]) and i + 1 < len(raw):
            joined.append(CONTINUE_RE.sub("", raw[i]))
            i += 1
            parts.append(raw[i])
        joined.append(raw[i])
        out.append((start + 1, " ".join(joined), parts))
        i += 1
    return out


def extract_commands(text):
    """从一段文本里抽出 (脚本路径, 参数列表)。**整条命令都解析**，不像旧版
    遇到第一个"非 -- 开头的词"就停止 —— 那正是漏掉 --nonexistent-flag 的原因。
    """
    # HTML 注释是文档说明，不是待运行的命令。替换为空格保持 token 边界。
    text = re.sub(r"<!--.*?-->", lambda m: " " * len(m.group()), text)
    if text.lstrip().startswith("#"):
        return []
    cmds = []
    consumed_until = 0
    for m in CMD_HEAD_RE.finditer(text):
        if m.start() < consumed_until:
            continue              # 前一条命令的引用值/行尾注释内不是另一条命令
        script = m.group(1) or m.group(2) or m.group(3)
        rest = text[m.end():]
        flags = []
        consumed_until = len(text)
        for token in TOKEN_RE.finditer(rest):
            tok = token.group()
            if tok.startswith("#"):
                break             # 行尾注释后的 python 文本也必须忽略
            if tok in "`|&;<>":
                consumed_until = m.end() + token.end()
                break             # shell 边界或 Markdown 行内代码结束
            if FLAG_RE.match(tok):
                flags.append(tok.split("=", 1)[0])
            # 其余 token 是参数值、位置参数或短选项；引号中的 --xxx 也是值。
        cmds.append((script, flags))
    return cmds


def check_file(md, cache, errors, degraded):
    """检查一个 .md，把错误追加到 errors。返回检查到的命令条数。"""
    try:
        src = io.open(md, encoding="utf-8", errors="replace").read()
    except Exception:
        return 0
    try:
        rel_md = os.path.relpath(md, REPO).replace("\\", "/")
    except ValueError:
        rel_md = os.path.basename(md)      # 自检用的临时 md 在仓库外（甚至别的盘）
    n = 0
    for lineno, text, parts in logical_lines(src):
        # ★ 反面例子：整条逻辑行（含续行）都不参与检查
        if any(NEGATIVE_RE.search(p) for p in parts):
            continue
        for raw_script, used in extract_commands(text):
            n += 1
            full = resolve_script(raw_script)
            if full is None:
                errors.append("%s:%d  脚本不存在：%s" % (rel_md, lineno, raw_script))
                continue
            if full not in cache:
                cache[full] = script_params(full)
            params, how = cache[full]
            if how == SRC_NOARG:
                continue          # 这脚本压根没有参数，不查也不算降级
            if how != SRC_HELP:
                degraded.add(os.path.basename(raw_script))
            if not params:
                continue
            for u in used:
                if u not in params:
                    errors.append(
                        "%s:%d  ★ %s **没有**参数 %s\n"
                        "        （该脚本实际支持的参数：%s）"
                        % (rel_md, lineno, os.path.basename(raw_script), u,
                           ", ".join(sorted(params))))
    return n


def self_test():
    """自检：造一个临时 .md（**放在系统临时目录，不进仓库**），喂几段真假命令，
    看检查器的判据是不是真的有区分力。

    四条必测：
      1. 第一条参数拼错      → 必须报错
      2. 后面的参数拼错      → 必须报错（旧版漏的就是这条）
      3. 标了反例标记的错命令 → 必须**不**报错
      4. 中文/空格路径当参数值 → 必须**不**报错
    """
    md = os.path.join(tempfile.mkdtemp(prefix="doccmd_"), "t.md")
    body = "\n".join([
        "# t",
        "",
        "python src/ps/multi_track.py --soruce clean",          # ① 第一个参数就拼错
        "python src/ps/multi_track.py --source clean --nonexistent-flag",  # ② 后面的参数拼错
        "python src/ps/multi_track.py --algo <!-- 反例：正确写法是 --source algo -->",  # ③ 反例
        'python src/ps/algo_lab.py --data-root "<DRIVE>/\我的 数据\\cdnet2014" --set r5',  # ④ 中文+空格路径
        "python src/ps/algo_lab.py --set r5 --seq all \\",
        "    --frames 20 --ref",                                 # ⑤ 续行
        'python src/ps/multi_track.py --outdir "我的 数据" --quoted-bad',
        'python src/ps/multi_track.py --outdir "my data" `',
        '    --powershell-bad',
        '`python src/ps/multi_track.py --source clean` 文档提及 --prose-only',
    ])
    with io.open(md, "w", encoding="utf-8") as fh:
        fh.write(body)

    cache, errors, degraded = {}, [], set()
    check_file(md, cache, errors, degraded)
    joined = "\n".join(errors)
    cases = [
        ("① 第一条参数拼错要能抓到", "--soruce" in joined),
        ("② 后面的参数拼错要能抓到", "--nonexistent-flag" in joined),
        ("③ 标了反例的错命令不能误报", "--algo" not in joined),
        ("④ 中文/空格路径不能误判", "我的" not in joined and "data-root" not in joined),
        ("⑤ 续行里的 --frames/--ref 要能解析到（且不报错）",
         "--frames" not in joined and "--ref" not in joined),
        ("⑥ 合法引号值后接非法参数必须报错", "--quoted-bad" in joined),
        ("⑦ PowerShell 续行非法参数必须报错", "--powershell-bad" in joined),
        ("⑧ 行内代码外的说明不能误报", "--prose-only" not in joined),
    ]
    print("自检（临时 md，不进仓库）：")
    bad = 0
    for name, ok in cases:
        print("   %-44s %s" % (name, "PASS" if ok else "FAIL"))
        bad += (not ok)
    if errors:
        print("\n  捕获到的错误（应为 ①②⑥⑦ 四条）：")
        for e in errors:
            print("    " + e.replace("\n", "\n    "))
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true", help="只输出错误行")
    ap.add_argument("--self-test", action="store_true",
                    help="自检：造几段真假命令验证判据本身")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    cache = {}
    errors = []
    degraded = set()
    checked = 0
    n_md = 0

    for md in repo_files(".md"):
        n_md += 1
        checked += check_file(md, cache, errors, degraded)

    if not args.quiet:
        print("检查了 %d 条命令（来自 %d 个 .md）" % (checked, n_md))
    if degraded:
        # ★ 如实说明降级：不能"靠源码猜的"也宣称"依据实际 --help"
        print("  ★ 降级提示：%d 个脚本的 --help 没跑起来，参数集是**源码推断**来的，"
              "可靠性低于实际 --help：%s"
              % (len(degraded), "、".join(sorted(degraded))))
        print("    常见原因：这个解释器里没装 numpy/opencv，import 阶段就挂了。"
              "设 MOTION_PYTHON 指向装了依赖的那个解释器即可消掉这条。")
    if errors:
        print("")
        print("★ 发现 %d 个问题：" % len(errors))
        for e in errors:
            print("   " + e)
        print("")
        print("修法：跑一下该脚本的 --help，看它到底支持哪些参数，别照记忆抄。")
        print("      （如果那行本来就是要演示错误写法，在行尾加 "
              "<!-- 反例：... --> 就不会再报。）")
        return 1

    if degraded:
        print("✅ 文档里所有命令的参数都对得上"
              "（其中 %d 个脚本依据**源码推断**，非实际 --help）" % len(degraded))
    else:
        print("✅ 文档里所有命令的参数都真实存在（依据：各脚本实际的 --help 输出）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
