<!-- Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4; scope: factual project documentation. -->

# fpga-motion-detection

**作品名称**：基于FPGA的运动目标检测
**赛事**：全国大学生嵌入式芯片与系统设计竞赛 2026 · FPGA创新设计赛道（AMD）· 3.3 自主选题 · 初级组
**目标器件**：`XC7Z020-1CLG400C`　**开发板**：PYNQ-Z2（Zynq-7000 SoC，双核 Cortex-A9 + 可编程逻辑）
**工具版本**：Vivado / Vitis 2026.1　**作品须在真实硬件上跑通，本仓库的 board/logs 与 evidence/ 为板端实测输出**

---

## ⚠ 分支说明（2026-11-01 起）

**本仓库只有 `main` 是有效分支。** 其余均为历史存档，**请勿从这些分支拉代码**。

| 分支 | 用途 | 负责人 |
|---|---|---|
| **`main`** | **唯一交付版**：含全部已验证代码与文档 | 全员合并目标 |
| `line1/work` | 线一工作区（通路 / 架构 / 顶层 / 量化 / 材料 / 验收） | 线一 |
| `line2/work` | 线二工作区（算法链） | 徐一夫 |
| `line3/work` | 线三工作区（RTL / 综合 / bit / 烧录） | 孙伟博 |
| 其余 11 个 | 📦 历史存档，独有内容已全部并入 `main` | — |

**约定**

1. 各自在 `lineN/work` 上开发，做完通知合并到 `main`；**不要直接推 `main`**。
2. 拉代码：`git checkout main && git pull`；要开发再切自己的分支。
3. **`main` 在 2026-10-30 做过一次 force push 重建历史**，旧分支与 `main` 已无共同祖先，`git merge` 会失败。**以 `main` 为准，不要试图合并旧分支。**

---

2026 FPGA竞赛项目，团队GGBOND。当前主线 `main`（2026-10-12），**多目标+UART 回传全链已并线**（`0a778c8` 顶层接线 / `2505417` 线一收尾 / `9f7173a` 线三接收端三笔合并），线三交付（codex 分支）、线一 HDMI 输入通路、AXI-Lite 寄存器接口均已合入；分工表修订版见 `docs/team_division_20261011.md`。

**12 段 CDnet 子集的原入口成绩复现已完成，板级顶层两种模式布局布线通过，两版固件为正确配置（自测 INPUT_SEL=0、HDMI 输入 INPUT_SEL=1，WNS 收敛、DRC 干净），回传协议与接口设计已定稿（f15fbce），HDMI 输入版上板实测已 PASS（37c1d2c：强运动检出率 89%、静止误检率 0%、单框确认）。** 未闭合项收窄为：多目标 bit 构建与上板实测、全链真回传实测（UART 接收端已就绪 `sim/line3/uart_receiver.py`；甲通路默认 INCLUDE_PS=0 关闭，需另出 INCLUDE_PS=1 版）、18 分钟帧号回绕长测、他人评审——不能称为整体验收通过。

| 入口 | 用途 |
| --- | --- |
| [线三 UART 接收与样本验收](docs/line3_uart_receiver.md) | 正式三包串口/原始流接收、画框/告警、精确对照；真实板端联调待样本 |
| [2026-10-12 UART 交付报告](report/line3_uart_20261012/README.md) | 模拟验证、独立复核问题与修复、证据边界和队友输入 |
| [2026-10-11 当前交付](report/line3_closeout_20261011/README.md) | 原入口 72 项核验、整合回归、板级布局布线与剩余缺口 |
| [2026-10-10 修复最终验收](report/repair_20261010/README.md) | 12 步回归通过、软件视频与真实 RTL 证据、尚未完成的硬件门槛 |
| [2026-10-09 职责核对（历史）](docs/line3_status_20261009.md) | 对照原始职责，说明已完成与未完成 |
| [复现说明](docs/reproduce_line3.md) | 从新输出目录运行，避免覆盖参考结果 |
| [独立检验委托](docs/independent_review.md) | 给另一AI自行建立判据，不预定结论 |
| [可复制提示词](docs/independent_review_prompt.md) | 新会话直接使用 |
| [本轮新证据](report/line3_review_20261009/README.md) | 命令、退出码、数据、仿真和来源哈希 |
| [线三报告初稿](report/line3_20261009/report_draft.md) | 历史九章初稿，缺项须补证后才能定稿 |
| [原始分工](docs/review_inputs/team_division_20261008.txt) | 原DOCX逐段提取，完成声明仍须验证 |
| [回传协议与接口设计（定稿）](docs/protocol_and_interface_requirements.md) | UART 三包（0x5A/0xA5/0xC3）+ AXI 寄存器表，10/12 定稿生效（f15fbce） |
| [上板实测记录](board/logs/board_test_20261012.md) | HDMI 输入版 PASS：强运动检出 89%、静止误检 0%、单框确认（37c1d2c） |

PL实现是自生激励、2×2求和、差分/背景建模、阈值、形态学、多目标包围盒（multi_bbox）、跟踪/告警（track/alarm）、UART 回传及HDMI输出。原 PC 侧多目标跟踪/告警已于 2026-10-12 搬进 PL（multi_bbox/track/alarm 已接顶层）；查实际源码判断功能。

`src/`是实现；`data/golden/`是合成输入/参考；`sim/line3/`是独立取证和比较工具；`build/scripts/`是构建与验收入口；`board/`和`build/reports/`保留板级资料及历史实现记录；`skill/`为已有经验文档。

report/line3_20261009记录旧线三基线，report/verification_20261009记录后续修复。两者保留历史成功与失败，不回填为新版本结果。旧docs/line3_run.md及verification_fixes_20261009.md已标为历史，请从当前复现说明启动。

已合入 main 的变更（截至 2026-10-12）：hdmi-in 通路组装（b07bc63）、rgb2dvi 打包顺序与帧号回绕修复（df34371/3685507）、构建 generic 参数格式修复（0aff121）、两版 bit 重建为正确配置（b7656a8）、分工表修订（73757f1）、最新 HDMI 构建收编（eda3e2f）、AXI-Lite 从机+桥与 PS 读出（147aea1）、红线整改（纯英文文件名 85f214d、大模型协作交互记录 099d8f0、Vivado generic 技能包 4405e3a）、回传协议与接口设计定稿（f15fbce）、上板实测记录（37c1d2c，PASS）、多目标+回传全链并线（顶层接线 0a778c8、线一收尾 2505417、线三接收端 9f7173a）。main 合入不等于整体验收通过。
