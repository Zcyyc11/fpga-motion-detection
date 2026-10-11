<!-- Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4; scope: factual project documentation. -->

# fpga-motion-detection

2026 FPGA竞赛项目，团队GGBOND。当前交付分支 `codex/line3-delivery-20261011` 整合 main 路径修改、线三候选修复及新的验证证据；main 仍由队长管理。

**12 段 CDnet 子集的原入口成绩复现已完成，现有板级顶层的两种模式已完成布局布线。** 外部输出约束、DRC 警告、真实回传、HDMI 输入、板测与他人评审仍未闭合，不能称为整体验收通过。

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

PL实现是自生激励、2×2求和、差分/背景建模、阈值、形态学、包围盒及HDMI输出。仓库的PC多目标跟踪/告警与PL实现属于不同路径。查实际源码判断功能，不能把PC功能自动算进PL。

`src/`是实现；`data/golden/`是合成输入/参考；`sim/line3/`是独立取证和比较工具；`build/scripts/`是构建与验收入口；`board/`和`build/reports/`保留板级资料及历史实现记录；`skill/`为已有经验文档。

report/line3_20261009记录旧线三基线，report/verification_20261009记录后续修复。两者保留历史成功与失败，不回填为新版本结果。旧docs/line3_run.md及verification_fixes_20261009.md已标为历史，请从当前复现说明启动。

本次未修改 md_pipeline 顶层或冻结接口；已完成受测 SHA 的两种背景模式板级综合与布局布线。尚未下载到板卡或实测。分支发布不等于 main 已合并或团队审核通过。
