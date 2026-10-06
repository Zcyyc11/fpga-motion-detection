# -*- coding: utf-8 -*-
"""跑 RTL 仿真（包装 sim/run_sim.bat），并**按日志内容**判断成败。

为什么不能看退出码：
  xsim.bat 无论引擎是否成功启动都返回 0。第一版就是只看退出码，
  结果"引擎失败"被当成"跑成功了"——差一点就拿着一个没跑的仿真去写报告。
  → 判据改成：日志里出现"仿真结束"标记 + 不出现 ERROR。

用法：
  python build/scripts/run_sim.py
  python build/scripts/run_sim.py --top tb_md_pipeline
"""
import argparse
import glob
import io
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SIM = os.path.join(ROOT, "sim")
LOGS = os.path.join(SIM, "logs")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", default="tb_md_pipeline")
    args = ap.parse_args()
    top = args.top
    snap = "sim_" + top

    os.makedirs(LOGS, exist_ok=True)

    rtl = sorted(glob.glob(os.path.join(ROOT, "src", "rtl", "*.v")))
    tb = os.path.join(SIM, "tb", top + ".v")
    if not rtl or not os.path.exists(tb):
        print("缺文件：rtl=%d tb=%s" % (len(rtl), tb))
        return 1

    fl = os.path.join(SIM, "files.f")
    with io.open(fl, "w", encoding="utf-8") as f:
        # 只用绝对路径列文件；本工程没有 `include，所以不写 +incdir+
        # （xvlog 的 -f 文件列表不认 +incdir+，要加包含目录得用命令行 -i）
        for p in rtl:
            f.write(p.replace("\\", "/") + "\n")
        f.write(tb.replace("\\", "/") + "\n")

    print("RTL %d 个：" % len(rtl))
    for p in rtl:
        print("   " + os.path.basename(p))
    print("仿真台：%s" % os.path.basename(tb))

    runlog = os.path.join(LOGS, "sim_run.log")
    cmd = '"%s" %s %s "%s"' % (os.path.join(SIM, "run_sim.bat"), top, snap, fl)
    with io.open(runlog, "w", encoding="utf-8", errors="replace") as lf:
        subprocess.run(cmd, cwd=SIM, shell=True, stdout=lf, stderr=subprocess.STDOUT)

    txt = io.open(runlog, encoding="utf-8", errors="replace").read()
    errs = [l for l in txt.splitlines() if re.match(r"^\s*(ERROR|FATAL)", l)]
    ok_done = "仿真结束" in txt
    x_bad = "X 检查：掩码流出现" in txt
    engine_bad = "engine failed to start" in txt

    print("")
    print("日志：%s" % runlog)
    if engine_bad:
        print("!! 仿真引擎没启动起来（缺环境）——确认 run_sim.bat 里 call settings64.bat 还在")
    if errs:
        print("!! 有 %d 条 ERROR：" % len(errs))
        for l in errs[:8]:
            print("   " + l.strip()[:200])
    if x_bad:
        print("!! 掩码流里出现未知态（X），流水线有未初始化路径")
    print("跑完标记：%s" % ("有" if ok_done else "没有"))

    # 打印逐帧结果，便于直接跟前一次比对
    for l in txt.splitlines():
        if "第 " in l and "帧检测" in l:
            print("   " + l.strip())

    return 0 if (ok_done and not errs and not engine_bad and not x_bad) else 2


if __name__ == "__main__":
    sys.exit(main())
