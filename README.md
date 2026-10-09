<!-- Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4; scope: factual project documentation. -->

# fpga-motion-detection

2026 FPGA竞赛项目，团队GGBOND。当前分支 `codex/line3-review-20261009` 汇集线三独立验证、后续软件/仿真运行器修复及审查材料。main仍由队长管理；遵守 [协作规范](CONTRIBUTING.md)。

**线三离线交付已有证据，但原始职责没有全部完成。** 真实CDnet成绩复现、板端结果回传实物验证、完整板测和他人换手验均不能据此宣布通过。

| 入口 | 用途 |
| --- | --- |
| [当前状态与缺口](docs/line3_status_20261009.md) | 对照原始职责，说明已完成与未完成 |
| [复现说明](docs/reproduce_line3.md) | 从新输出目录运行，避免覆盖参考结果 |
| [独立检验委托](docs/independent_review.md) | 给另一AI自行建立判据，不预定结论 |
| [可复制提示词](docs/independent_review_prompt.md) | 新会话直接使用 |
| [本轮新证据](report/line3_review_20261009/README.md) | 命令、退出码、数据、仿真和来源哈希 |
| [线三报告初稿](report/line3_20261009/report_draft.md) | 历史九章初稿，缺项须补证后才能定稿 |
| [原始分工](docs/review_inputs/team_division_20261008.txt) | 原DOCX逐段提取，完成声明仍须验证 |

PL实现是自生激励、2×2求和、差分/背景建模、阈值、形态学、包围盒及HDMI输出。仓库的PC多目标跟踪/告警与PL实现属于不同路径。查实际源码判断功能，不能把PC功能自动算进PL。

`src/`是实现；`data/golden/`是合成输入/参考；`sim/line3/`是独立取证和比较工具；`build/scripts/`是构建与验收入口；`board/`和`build/reports/`保留板级资料及历史实现记录；`skill/`为已有经验文档。

report/line3_20261009记录旧线三基线，report/verification_20261009记录后续修复。两者保留历史成功与失败，不回填为新版本结果。旧docs/line3_run.md及verification_fixes_20261009.md已标为历史，请从当前复现说明启动。

本分支本轮没有修改src/rtl/md_pipeline.v或冻结接口，没有做新综合、板卡下载或板测。提交到审查分支不等于main已合并或团队审核通过。
