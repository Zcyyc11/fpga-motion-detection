# r3 更新的来源与验证

日期：2026-11-03。对应独立交付目录 `deliverables/tier1_attach_hdmi_r3/`。

## 版本身份

| 项目 | 核实值 |
| --- | --- |
| 原始硬件包 | FPGA_Tier1_AttachZ2_HDMI_r3_digitfix.zip |
| 原包 SHA-256 | `13c055ed738360acbbbb460a91110ce0d8cc4396bdf77905c6c2d939a0168e94` |
| 整理提交包 | FPGA_All_Code_r3.rar，105 文件 |
| 提交包 SHA-256 | `32a263d8819c16b0737cacae5964ea0268bcf8f13c72f65b77e06aa3c871df06` |
| r3 bit SHA-256 | `c3c3a16c91e31a8044704aa959cbbbcf55844f9e3aa4e343b5abe8c246c8e8c8` |

105 个文件从已核验整理包逐字节复制，清单见 [manifest.json](manifest.json)。
目录另加 Git 属性/忽略规则以保持字节一致并排除后续生成缓存，不改变原交付代码。
原 ZIP 根 manifest.json 仍写 r2 版本、r2 bit 和时序，本次未将其作为 r3 清单。
原文件保留在本地来源目录；此处新清单显式说明这一差异。

## 原 r3 物理构建证据（2026-11-02）

- 工具为 Vivado 2026.1；[gate.json](imported/r3_build/gate.json)：WNS +0.107 ns、WHS +0.013 ns、阻断 DRC=0，passed=true。
- [时序报告](imported/r3_build/reports/impl_timing_summary.rpt)、[资源报告](imported/r3_build/reports/impl_utilization.rpt)已保留。
- [DRC](imported/r3_build/reports/impl_drc.rpt)有 26 项已报告 Warning，REQP-1839 达到报告上限；不能称 DRC clean。
- [CDC](imported/r3_build/reports/impl_cdc.rpt)含 Critical，汇总 2 unsafe、3 unknown；不能称 CDC clean。
- 构建报告的原命令路径仍包含 r2 文件夹名；本次采用的是 `build/r3_fix_digits` 下的 r3 报告，不用旧根 reports 的 r2 时序。
- 原包 README 记载 JTAG startup HIGH；本次未取得独立烧录日志或完整实板验收证据。`board_verified=false`。

## 源码整理时已有的验证（2026-11-03）

[独立复核](imported/submission_checks/independent_review.md)核对：27 RTL 逻辑 token 等价、2 XDC 有效行相同、54 第三方文件逐字节保留、63 IP 文件引用完整。
[工程创建记录](imported/submission_checks/project_verification.json)为 Vivado 2025.2 创建工程返回 0，保留两条 ILA board-value Critical Warning；并非该版本重新完成 r3 bit 构建。
7 个 Python 语法及 4 个视频工具 `--help` 已通过；RAR 解压的 105 文件和内置 104 条校验清单已核对。
历史数字输入仿真仅验证数字接口，接收 IP 和时钟使用替代模型。

## 本次 GitHub 同步

本次验证记录为 [verification.json](verification.json)，检查复制字节、Git 暂存内容、Python 语法、视频工具 `--help`、UTF-8 和文档链接。
没有重新综合实现、没有重新生成 bit，也没有新增 GUI 播放、采集卡或实板测试。
旧工程的板测与评分不移作 r3 证据；算法代理评测亦不构成新的效果提升承诺。

下一步由持板方用上述 r3 bit，记录烧录身份、720p60 输入、车辆框/外设显示、断线重锁、重复上电和至少 10 分钟稳定性。
团队换手评审及合并仍遵守仓库协作规范。
