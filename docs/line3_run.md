<!-- Hallmark · pre-emit critique: P5 H4 E4 S5 R5 V4; scope: factual verification instructions. -->

# 线三运行说明（2026-10-09，阶段交接版）

本轮验证基线为 `ead15e0bf3f71d733915f84b0e8ef948094cfecc`，开发分支为 `feat/line3-verification`。新增内容只在 `sim/line3/`、`report/line3_20261009/` 和线三文档中。没有修改核心算法、冻结接口、参考 CSV、参考视频或原始资料，也没有推送远程。

## 已执行的入口

从 `captain_repo` 根目录，在 PowerShell 中执行。输出目录必须是新目录，不能复用下例已有目录。

```powershell
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
& 'D:\666666\Anaconda\python.exe' -X utf8 sim/line3/run.py --out report/line3_20261009/run_ead15e0_02
```

当前环境为 Python 3.13.5、NumPy 2.1.3、OpenCV 4.13.0、Matplotlib 3.10.0。沿用已有环境，没有升级或降级 base 环境。仓库要求 NumPy 2.2.6、opencv-python 4.12.0.88、Matplotlib 3.10.8、imageio-ffmpeg 0.6.0；本轮不是锁定依赖环境复现。实际解释器、参数、源码与输入 SHA256 见 `report/line3_20261009/run_ead15e0_01/manifest.json`。

`run.py` 依次运行两种整数模型、原跟踪程序、无算法改动的取证包装、严格比较、25 项小测试和存量 CDnet CSV 审计。它把所有命令、退出码和耗时记入 `commands.json`，把控制台原文保存在 `logs/`，总结果写入 `results.json`。

**当前基线返回非零是正确的验收行为**：5 项告警边界测试失败。不能把这些失败从总结果中排除，不能把入口完成等同于全部行为通过。

## 比较口径

- `compare.py` 按指定键精确比较 CSV 的所有列；行顺序可变，重复键、缺行、多行、列结构错误和字段差异均失败。比较的是字段字符串，不自动转换单位、不放宽数值容差。
- 整数硬件模型默认应有第 0–11 帧；本轮归档和新 RTL CSV 都只有第 0–10 帧。报告同时保留“0–10 范围内一致”和“完整模型缺第 11 帧”，不能只报共同帧通过。
- 跟踪取证复用 `multi_track.Tracker`、`AlarmRule` 和现有 `main()`。包装只复制调用结果。已检查原版与包装版的逐帧 CSV、告警 CSV、全部解码视频帧哈希一致。
- 跟踪坐标为原图 1280×720，框端点包含在框内。真值宽高转为 `x+w-1`、`y+h-1`。算法输出仍保留原程序的 `2*x+1` 换算，不擅改它。
- 两目标匹配采用最大匹配数优先、距离和最小次之，中心距离门限固定 60 像素；该穷举方法只用于本合成片段，不能直接扩展到大量目标。匹配不依赖输出顺序。ID 为跟踪编号，不要求与真值 obj_id 数字相同，需跨帧保持映射。
- 15 个 merged 帧从主召回分母排除，但逐帧记录完整保留。algo 前 12 帧为初始化、无检测输出；主召回仍包含这 12 帧可见真值，与仓库历史口径保持一致。
- 方向只统计速度绝对值大于 1 像素/帧的已匹配目标。框误差独立记录，不用中心容差掩盖框大小差异。
- 视频的 ALARM 字样区域通过红像素存在性与当帧事件对照；这只是本黑底合成片段的显示一致性检查，不是通用 OCR 或逐字符验证。
- 运行耗时为本机 PC 软件耗时，不能解释为 FPGA 吞吐量、板端帧率或端到端延迟。

单独比对 CSV：

```powershell
& 'D:\666666\Anaconda\python.exe' -X utf8 sim/line3/compare.py expected.csv actual.csv --keys frame --out new_diff.json
```

无差异返回 0；发现差异或无效输入返回 2。`--out` 已存在时拒绝覆盖。告警表的键使用 `frame,tid,kind`。

## 新 RTL 仿真入口

```powershell
& 'D:\666666\Anaconda\python.exe' -X utf8 sim/line3/run_rtl.py --settings 'D:\AMD2025.2\2025.2\Vivado\settings64.bat' --out 'D:\666666\Temp\line3_xsim_20261009_fd02' --evidence report/line3_20261009/rtl_fd02
```

新目录参数仅为复现示例。该入口复制 11 份 RTL 和原 testbench 到新的英文目录，用实际安装的 settings64.bat 执行 xvlog、xelab、xsim；不调用写死 2026.1 路径的共享启动脚本。没有运行综合、实现、下载或板卡测试。改变模式可用 `--mode bg`，但截至此阶段只执行过 framediff。

首次结果在 `report/line3_20261009/rtl_fd01/`。工具确实运行完成且无 X，但完整 12 帧验收失败，详见 `result.json`。原始 PPM 和仿真构建产物保留在 `D:\666666\Temp\line3_xsim_20261009_fd01`，没有删除。

## 下一阶段工作

先完成新脚本的验收加固和视频关键帧核对，再补官方要求映射、接口及资料问题单、结果台账、报告初稿、队友待补证据和协作记录。完整交接说明位于外层项目根目录 `handoff.md`。本文件不是最终交付完成声明。
