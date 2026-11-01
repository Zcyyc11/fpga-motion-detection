> 历史记录：本文描述当时版本与当时授权，不能作为整合分支的当前状态或执行指令。当前入口为仓库 README、docs/reproduce_line3.md 和 docs/line3_status_20261009.md。旧绝对路径可通过外层维护清单和完整备份追溯。

<!-- Hallmark · pre-emit critique: P5 H4 E4 S5 R5 V4; scope: factual verification instructions. -->

# 线三运行说明（2026-10-09，离线交付版）

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
- 整数硬件模型默认应有第 0–11 帧；归档和原参数新 RTL CSV 只有第 0–10 帧，完整验收失败。后续仅增加 testbench 排空时长，两模式均完整 12 帧通过。不能把扩展结果回填成原参数已通过。
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
& 'D:\666666\Anaconda\python.exe' -X utf8 sim/line3/run_rtl.py --settings 'D:\AMD2025.2\2025.2\Vivado\settings64.bat' --out 'D:\666666\Temp\line3_xsim_reproduce_fd01' --evidence report/line3_reproduce/rtl_fd01 --drain-frames 1
```

新目录参数仅为复现示例。该入口复制 11 份 RTL 和原 testbench 到新的英文目录，用实际安装的 settings64.bat 执行 xvlog、xelab、xsim；不调用写死 2026.1 路径的共享启动脚本。没有运行综合、实现、下载或板卡测试。改变模式用 `--mode bg` 并换新输出目录。

`--drain-frames 1` 仅把 testbench 的 FRAMES 由12调13，让最后一次 bbox 结算有足够收尾时间，模型期望仍为0–11，不改任何源码。默认0保留原台行为。最终 framediff 在 `rtl_fd03/`、bg在 `rtl_bg01/` 均完整12行、全字段一致、x_hits=0；各自wave/保存12张输出及12张掩码PPM。结果只覆盖320×180小尺寸合成激励。

首次结果在 `report/line3_20261009/rtl_fd01/`。工具确实运行完成且无 X，但完整 12 帧验收失败，详见 `result.json`。原始 PPM 和仿真构建产物保留在 `D:\666666\Temp\line3_xsim_20261009_fd01`，没有删除。

## 工具验收与媒体检查

```powershell
& 'D:\666666\Anaconda\python.exe' -X utf8 sim/line3/check_tools.py --out report/line3_reproduce/tools01
& 'D:\666666\Anaconda\python.exe' -X utf8 sim/line3/inspect_media.py --out report/line3_reproduce/media01 --wave 'D:\666666\Temp\line3_xsim_reproduce_fd01/wave'
```

check_tools本轮18项通过；其中完整软件入口因为5项真实告警FAIL返回2，工具测试正确识别这个返回码。check_tools固定针对ead15e0已知反例；算法修复后应另建版本并审查期望，不能机械要求仍有5项失败。

inspect_media复用原read_ppm/red_box_bounds函数，不运行会覆盖旧结果的view_sim.main。红框范围采用0px容差，帧k对应CSV k−1行×2。两模式各12图通过；掩码只核验数量、编号、可解析尺寸，没有逐像素比较。软件拼图固定读取run_ead15e0_01，不能用它冒称检查其他版本视频。

run_rtl遇timeout会留部分证据并失败，但不保证后代进程已经退出；本轮未触发该路径。首次扩展在沙箱内编译失败，获准在沙箱外相同入口成功；失败日志仍保留于rtl_fd02。读证据时不要把该目录或只有两张拼图的media_02视为通过。

## 交付入口

阅读 [线三交付索引](../report/line3_20261009/README.md)，其中链接问题单、官方要求映射、结果台账、九章初稿、队友证据清单及协作记录。正式CDnet复跑、整机上板性能和其他成员换手验均未完成，不属于本轮离线交付的完成声明。
