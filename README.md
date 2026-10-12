<!-- Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4; scope: factual project documentation. -->

# fpga-motion-detection

2026 FPGA竞赛项目，团队GGBOND。当前主线 `main @ c3f7040`（2026-10-12；协议定稿锚点 `f15fbce`），线三交付（codex 分支）、线一 HDMI 输入通路、AXI-Lite 寄存器接口均已合入；分工表修订版见 `docs/team_division_20261011.md`。

**12 段 CDnet 子集的原入口成绩复现已完成，板级顶层两种模式布局布线通过，两版固件为正确配置（自测 INPUT_SEL=0、HDMI 输入 INPUT_SEL=1，WNS 收敛、DRC 干净），回传协议与接口设计已定稿（f15fbce），HDMI 输入版上板实测已 PASS（37c1d2c：强运动检出率 89%、静止误检率 0%、单框确认）。** 未闭合项收窄为：板端回传集成（线二接顶层 `md_pipeline.v`，授权进行中）、全链真回传实测、18 分钟帧号回绕长测、他人评审——不能称为整体验收通过。

| 入口 | 用途 |
| --- | --- |
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

PL实现是自生激励、2×2求和、差分/背景建模、阈值、形态学、包围盒及HDMI输出。仓库的PC多目标跟踪/告警与PL实现属于不同路径。查实际源码判断功能，不能把PC功能自动算进PL。

`src/`是实现；`data/golden/`是合成输入/参考；`sim/line3/`是独立取证和比较工具；`build/scripts/`是构建与验收入口；`board/`和`build/reports/`保留板级资料及历史实现记录；`skill/`为已有经验文档。

report/line3_20261009记录旧线三基线，report/verification_20261009记录后续修复。两者保留历史成功与失败，不回填为新版本结果。旧docs/line3_run.md及verification_fixes_20261009.md已标为历史，请从当前复现说明启动。

已合入 main 的变更（截至 2026-10-12）：hdmi-in 通路组装（b07bc63）、rgb2dvi 打包顺序与帧号回绕修复（df34371/3685507）、构建 generic 参数格式修复（0aff121）、两版 bit 重建为正确配置（b7656a8）、分工表修订（73757f1）、最新 HDMI 构建收编（eda3e2f）、AXI-Lite 从机+桥与 PS 读出（147aea1）、红线整改（纯英文文件名 85f214d、大模型协作交互记录 099d8f0、Vivado generic 技能包 4405e3a）、回传协议与接口设计定稿（f15fbce）、上板实测记录（37c1d2c，PASS）。main 合入不等于整体验收通过。
