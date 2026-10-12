<!-- Hallmark pre-emit critique: P5 H5 E4 S5 R5 V4 -->
# 2026-10-11 线三交付入口

先读 [正式报告](REPORT.md)，再按 [复现说明](REPRODUCE.md) 查看具体命令与证据范围。

| 内容 | 入口 |
|---|---|
| 原入口完整 72 项结果 | [CSV](native_all72.csv)、[比较结果](native_verified_summary.json) |
| 整合后的软件与 RTL 回归 | [汇总](integrated_regression_summary.json) |
| 两种模式的板级布局布线 | [汇总](board_verified_summary.json)、[模式 0](board_mode0/impl_timing_summary.rpt)、[模式 1](board_mode1/impl_timing_summary.rpt) |
| 历史与 MATLAB 标签两套评分 | [评分汇总](prior_evidence/score_summary.json) |
| 完整逐帧审计档案 | [111,498 行 gzip](prior_evidence/complete_per_frame.csv.gz) |
| 外部资料请求 | [队友清单](teammate_inputs.md) |
| 文件来源和验证 | [交付清单](delivery_manifest.json)、[保护范围](protected_comparison.json) |

受测源码是 `64ac44ee2a27897f674919d6fcb8e4fbbd8dfde8`；分支发布还包含本目录报告与证据。布局布线覆盖内部图案到 HDMI 输出，仍有外部输出约束与 DRC 警告；没有实机通过记录。

发布目标是 `codex/line3-delivery-20261011`。实际远端 SHA 以发布回执为准；此文件本身不充当推送成功证明。main 与现有 PR 没有在本任务中修改。
