<!-- Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4; scope: factual project documentation. -->

# 从干净代码复现线三

本说明是工具用法，不是独立审查判据。审查者先读independent_review.md并建立自己的计划。

检出审查分支，记录完整SHA。依赖见src/ps/requirements.txt；本轮使用已有环境，没有修改系统或base依赖。新的机器可在仓库外建立虚拟环境，再按requirements安装。Vivado仅RTL步骤需要；命令中的安装路径应换成当地真实路径。

以下PowerShell命令从仓库根执行，输出始终在仓库外的新目录。保存每步实际退出码和日志；非零不能略过。

```powershell
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONDONTWRITEBYTECODE = '1'
$runId = (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N').Substring(0,8)
$evidenceRoot = Join-Path (Split-Path (Get-Location).Path -Parent) ('line3_rerun_' + $runId)
New-Item -ItemType Directory -Path $evidenceRoot | Out-Null
python -X utf8 build/scripts/test_verification_boundaries.py --out "$evidenceRoot/software" --suite all
python -X utf8 build/scripts/test_sim_runner.py --out "$evidenceRoot/runner"
python -X utf8 sim/line3/run.py --out "$evidenceRoot/tracking"
python -X utf8 build/scripts/check_doc_commands.py
python -X utf8 build/scripts/check_doc_commands.py --self-test
```

软件回归测试程序参数和异常处理；运行器回归使用工具替身；tracking才是当前PC合成片段与行为取证。修复版 tracking 应退出 0，并保留 results.json、commands.json、逐帧及逐目标关联表。check_tools.py 要求告警行为通过，并检出身份交换、重建和掉检；整体重编号不算身份错误。check_repairs.py 会再次运行旧提交的最小失败反例，然后验证修复结果。verify_delivery.py 只核验旧 ead15e0 交付，不用于本修复版验收。

## 实际RTL

在上述会话中设置真实Vivado位置，要求完整帧集合的示例如下。期望集合来源需要先核对testbench与模型；不要按观察到的输出反推验收数量。

```powershell
$vivadoSettings = '<VIVADO_2025_2>\2025.2\Vivado\settings64.bat'
python -X utf8 build/scripts/run_sim.py --vivado-settings "$vivadoSettings" --scratch-root "$evidenceRoot/rtl_default" --expect-frames 12
```

默认 testbench 已按结果计数自动收尾。独立适配器仍要求新的纯英文绝对路径；以下路径只适用于本机：

```powershell
$asciiScratch = '<TMP>/Temp/line3_rerun_' + $runId
python -X utf8 sim/line3/run_rtl.py --settings "$vivadoSettings" --out "$asciiScratch/fd" --evidence "$evidenceRoot/rtl_fd" --mode framediff
python -X utf8 sim/line3/run_rtl.py --settings "$vivadoSettings" --out "$asciiScratch/bg" --evidence "$evidenceRoot/rtl_bg" --mode bg
```

旧 `--drain-frames 1` 作为兼容参数保留，0 和 1 均收集 12 帧，不再把 FRAMES 改成 13。结果内保存源文件哈希、命令、真实日志、完整 CSV 差异和 PPM。这是 320×180 合成仿真，不代表 720p 全链或板测。

定向验证另用 `sim/line3/check_rtl_contracts.py --settings <settings64.bat> --out <新英文目录>`，覆盖差值 69/70/71、四边贴边、帧间切换和实际回绕，同时在独立副本注入错误。用 `--help` 查看参数。

原完整7例真实运行器检查已移入build/scripts/verify_runner_live.py，原脚本字节保持一致；用其--help查看参数。它会在隔离副本中故意制造编译错误和X状态，不能直接按子运行成功数量解释结果。

## 数据与产物纪律

真实CDnet输入必须另行提供；仓库CSV和构造数据不等于真实数据集。使用cdnet相关入口前阅读--help及输出路径，在隔离源码/数据副本运行，避免覆盖归档成绩。板端回传未确认协议，不提供虚构的板端复现步骤。

新视频应逐帧解码，检查CSV、事件和图像的帧/坐标对应关系；新结果不能用旧inspect_media.py固定读取的历史视频替代。旧复核输出见 report/line3_review_20261009/；当前修复证据、备份和失败记录见 [修复报告](../report/repair_20261010/README.md)。
