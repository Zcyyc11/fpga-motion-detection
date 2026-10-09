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

软件回归测试程序参数和异常处理；运行器回归使用工具替身；tracking才是当前PC合成片段与行为取证。已有算法问题会让tracking返回非零，必须读它的results.json和commands.json，不要改期望使其通过。check_tools.py固定包含旧基线的行为断言，verify_delivery.py固定核验旧ead15e0文件，均不适合作为任意新版本的全项目验收结论。

## 实际RTL

在上述会话中设置真实Vivado位置，要求完整帧集合的示例如下。期望集合来源需要先核对testbench与模型；不要按观察到的输出反推验收数量。

```powershell
$vivadoSettings = 'D:\AMD2025.2\2025.2\Vivado\settings64.bat'
python -X utf8 build/scripts/run_sim.py --vivado-settings "$vivadoSettings" --scratch-root "$evidenceRoot/rtl_default" --expect-frames 12
```

默认testbench与延长排空的实验要分开保存。旧线三独立适配器支持后者；scratch必须是新的纯英文绝对路径，以下路径只适用于本机：

```powershell
$asciiScratch = 'D:/666666/Temp/line3_rerun_' + $runId
python -X utf8 sim/line3/run_rtl.py --settings "$vivadoSettings" --out "$asciiScratch/fd" --evidence "$evidenceRoot/rtl_fd" --mode framediff --drain-frames 1
python -X utf8 sim/line3/run_rtl.py --settings "$vivadoSettings" --out "$asciiScratch/bg" --evidence "$evidenceRoot/rtl_bg" --mode bg --drain-frames 1
```

这个参数只增加testbench收尾，不代表默认工程通过，也不代表720p视频全链或板测。结果内保存源文件哈希、命令、真实日志、完整CSV差异和PPM。

原完整7例真实运行器检查已移入build/scripts/verify_runner_live.py，原脚本字节保持一致；用其--help查看参数。它会在隔离副本中故意制造编译错误和X状态，不能直接按子运行成功数量解释结果。

## 数据与产物纪律

真实CDnet输入必须另行提供；仓库CSV和构造数据不等于真实数据集。使用cdnet相关入口前阅读--help及输出路径，在隔离源码/数据副本运行，避免覆盖归档成绩。板端回传未确认协议，不提供虚构的板端复现步骤。

新视频应逐帧解码，检查CSV、事件和图像的帧/坐标对应关系；新结果不能用旧inspect_media.py固定读取的历史视频替代。本轮原始命令和完整输出见report/line3_review_20261009/commands.json及同目录日志。
