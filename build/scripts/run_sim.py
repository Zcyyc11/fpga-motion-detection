# -*- coding: utf-8 -*-
"""跑 RTL 仿真（包装 sim/run_sim.bat），并**按日志内容**判断成败。

为什么不能只看退出码：
  xsim.bat 无论引擎是否成功启动都返回 0。第一版就是只看退出码，
  结果"引擎失败"被当成"跑成功了"——差一点就拿着一个没跑的仿真去写报告。
  → 判据改成：日志里出现"仿真结束"标记 + 不出现 ERROR。

Vivado 装在哪（★ 不要再写死路径）
--------------------------------
  sim/run_sim.bat 里**没有**任何硬编码路径，按这个优先级找 Vivado：
    1) --vivado-settings <settings64.bat 的完整路径>   ← 本脚本的参数
    2) 环境变量 VIVADO_SETTINGS                        ← 同上
    3) 环境变量 XILINX_VIVADO                          ← 安装目录
    4) 都没设 → 假设当前 shell 已经有 Vivado 环境
  找不到就**明确报错并打印怎么配**，绝不静默跳过初始化。
  永久性配置（不用每次设）：
    cmd         setx VIVADO_SETTINGS "D:\\AMDDesignTools\\2026.1\\Vivado\\settings64.bat"
    PowerShell  [Environment]::SetEnvironmentVariable('VIVADO_SETTINGS','...','User')

用法：
  python build/scripts/run_sim.py
  python build/scripts/run_sim.py --top tb_md_pipeline
  python build/scripts/run_sim.py --vivado-settings "D:\\...\\settings64.bat"
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
    ap.add_argument("--vivado-settings", default=None,
                    help="settings64.bat 的完整路径。不给就依次用环境变量 "
                         "VIVADO_SETTINGS / XILINX_VIVADO；都没有就假设当前 "
                         "shell 已经有 Vivado 环境（找不到会明确报错并教怎么配）。")
    args = ap.parse_args()
    top = args.top
    snap = "sim_" + top

    env = dict(os.environ)
    if args.vivado_settings:
        env["VIVADO_SETTINGS"] = os.path.abspath(args.vivado_settings)
    src = ("命令行 --vivado-settings" if args.vivado_settings
           else ("环境变量 VIVADO_SETTINGS" if env.get("VIVADO_SETTINGS")
                 else ("环境变量 XILINX_VIVADO" if env.get("XILINX_VIVADO")
                       else "都没有设 → 假设当前 shell 已经有 Vivado 环境")))
    print("Vivado 环境来源：%s" % src)

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
        r = subprocess.run(cmd, cwd=SIM, shell=True, stdout=lf,
                           stderr=subprocess.STDOUT, env=env)
    rc = r.returncode

    txt = io.open(runlog, encoding="utf-8", errors="replace").read()

    # ★ 环境没起来就别往下判了 —— 这时候"日志里没有 ERROR"只是因为压根没跑。
    #   run_sim.bat 的 10/11/12 就是这三档，日志里已经写了怎么配，原样转出来。
    if rc in (10, 11, 12):
        print("")
        print("!! 仿真没跑起来：Vivado 环境没配好（run_sim.bat 退出码 %d）" % rc)
        for l in txt.splitlines():
            if l.strip():
                print("   " + l.rstrip())
        return rc

    errs = [l for l in txt.splitlines() if re.match(r"^\s*(ERROR|FATAL)", l)]
    ok_done = "仿真结束" in txt
    x_bad = "X 检查：掩码流出现" in txt
    engine_bad = "engine failed to start" in txt

    print("")
    print("日志：%s" % runlog)
    if engine_bad:
        print("!! 仿真引擎没启动起来（缺 DLL = 环境没加载）—— 配好 VIVADO_SETTINGS 再跑；")
        print("   本脚本支持 --vivado-settings，或设环境变量 VIVADO_SETTINGS / XILINX_VIVADO。")
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
