> ⚠️ **本文档的治本要求与验收标准已由 `docs/handoff_code_fixes_20261013.md`（双审融合版）取代并扩充；任务状态以 `team_tasklist_20261013.md` 为准。本文件仅存档。**

# 线二 multi_bbox 治本交接记录（2026-10-13）

> 本文档由线一（Zcyyc11）整理，作为 multi_bbox 资源爆炸问题的正式交接与协作证据。
> 归属说明：multi_bbox.v 在 git 记录中由 Zcyyc11 账号于 2026-10-11 11:08 提交并推送（feat(line2)）；
> 徐一夫（GitHub 账号 XIF123）未直接提交过该文件。代码实际作者以本人确认为准，本文不推定。

## 一、事实：构建必炸，多目标 bit 至今未产出

- multi_bbox 首次进入真实综合（2026-10-12 晚，RuntimeOptimized 策略）即超限：
  - Slice LUTs：**96,997 / 53,200（182.33%）**
  - 器件：xc7z020clg400-1（上限 53,200）
- 实现阶段 DRC 失败（place_design failed），bitstream 无法生成。
- 旧单目标版基线：10,605 LUT（19.93%），对照充分。

## 二、根因（经层级耗量分析证实）

- multi_bbox 为 16 标签并查集 + 16×16 游程全并联匹配，**阻塞赋值区一拍内完成查根/合并/更新**。
- 16 级动态索引 mux 链 + 16×16 全并联 → 综合后组合网络爆炸。
- 层级报告：multi_bbox 83,286 LUT（占全部 96,997 的 86%）；morph_open 7,366；gray_conv 2,778；downsample2x2 2,759；overlay_multi 769。
- 该模块此前仅做过仿真，从未进过真实综合，故未暴露。

## 三、要求（线二认账，动手治本）

- **目标**：算法改流水化（分步算，避免 16 路并行 + 一拍完成），回到 16 目标能力，且 LUT 占用压到 50% 以下。
- 原则上不改接口（遵守接口冻结表），只改内部实现。
- 改完须重新仿真 + 重新构建验证。
- 时间：多目标 bit 不出，上板（计划 10/13）与交报文（10/14）均被卡住，需明确完成时间。

## 四、顺带未交清单（线二）

1. 板端发送程序
2. 真实报文样本
3. 回传协议确认稿
（三批清单此前已列出，等待中）

## 五、验证路径（供治本后使用）

- 构建：`build_vivado.bat 0 1`（HDMI 输入帧差版），可设 `SYNTH_DIRECTIVE=RuntimeOptimized` 加速综合（见 build_vivado.tcl 开关）。
- 红线：综合后必须 grep "bound to" 验证 MODE_BG=0 INPUT_SEL=1 真绑定（坏 bit 教训）。
- 上板：`burn_jtag.tcl` 烧录；`verify_board.py` 自动视觉验证（采集卡 UGREEN 25854，1280x720）。
- 测试视频：`<WORKSPACE>\test_videos\`（vehicles / people-walking / market-square）。
