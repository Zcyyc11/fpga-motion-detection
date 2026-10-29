<!-- Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4; scope: factual repair acceptance. -->

# 修复验收：固定提交回归通过，等待团队审阅

2026-10-10。受测提交为 `4aeaad8dceaab5a53dfdaed975e80c4eff962b02`，分支 `codex/verified-repairs-20261010`。12 个步骤退出码全部为 0，结束时冻结 checkout 无修改或新增文件。最终证据见 [命令与退出码](final_evidence/jobs.json)、[空的工作区状态](final_evidence/checkout_status.txt)。本报告由 Codex 接续实现后整理，属于自动回归与自查，不是人工换手签字。

结论仅覆盖指定合成输入、软件行为和 RTL 仿真。真实 CDnet、板端回传、完整板测、综合资源与时序、模块 owner 审阅仍未完成，因此不能据此合并 main 或宣布整机验收完成。

## 修好了什么

- 告警：进入、离开、重新进入事件与计数对应；观测侧别持续更新，速度为零或矛盾时不发跨线事件。缺观测、跳帧、离区会重置连续停留；使用真实 fps 和向上取整阈值，zone=None 表示全画面；注销目标清理状态。视频和打印支持 EXIT。
- 默认 RTL 仿真：等待全部 12 帧 bbox 结算再结束；CSV 打开失败、未知态或超时会明确失败。严格比较拒绝空表、重复、缺失、额外帧和末帧错误。
- 逐目标核验：保留所有分配及未匹配记录，检查换号、断航、误框、事件时刻及逐帧累计计数。整体重编号允许通过，真正交换、重建和掉检会被检出。
- 贴边 RTL：修复 morph3x3 行首列寄存器与帧首读行数据残留。两级流式有效域为 x=1..W-3、y=1..H-3；模型同步修正末端有效域。10×10 全前景的有效输出是 49 格，旧模型误算 64 格。没有末端排空，不能宣称实现完整对称图像开运算。

未修改 `src/rtl/md_pipeline.v` 或端口接口。morph3x3 是局部功能修复，仍需算法/PL owner 复核其硬件代价。

## 最终回归与证据

全部步骤在冻结的同一提交执行，产物写到 checkout 以外。工作区完整性与子测试结果分别核对。

| 检查 | 实际结果 | 证据 |
| --- | --- | --- |
| 软件边界 | 174/174；changed=0、added=0 | [日志](final_evidence/boundaries.txt) |
| 仿真运行器 | 46/46 | [日志](final_evidence/runner.txt) |
| 取证工具 | 24/24，含两模式软件完整运行与身份反例 | [验收表](final_evidence/tools/acceptance.json) |
| 修复前后 | 9/9；旧五项缺陷再次复现，新行为通过 | [结果](final_evidence/repairs/results.json) |
| 文档命令 | 35 条命令参数核查、8 项解析器自检通过 | [核查](final_evidence/docs.txt)、[自检](final_evidence/docs_self.txt) |
| 默认 RTL 入口 | 完整 0–11 帧、无 X、仿真完成 | [日志](final_evidence/rtl_default.txt) |
| framediff / bg / drain=1 | 各 12 帧，严格全量比较无差异 | [帧差](final_evidence/rtl_fd/result.json)、[背景](final_evidence/rtl_bg/result.json)、[兼容](final_evidence/rtl_compat/result.json) |
| RTL 定向检查 | 7×49 个形态学坐标、6 次阈值判定、384 次回绕像素检查；正确版本通过 | [结果](final_evidence/contracts/results.json) |
| 故障注入 | 阈值 70→69、提前回绕、取消回绕、坐标偏移、回退旧 morph 均触发预期断言；旧模型边界反例也被检出 | [结果和源码副本](final_evidence/contracts/) |
| 数据保护 | 22/22；用于模拟缺失的样本被移存而非删除 | [日志](final_evidence/data_guard.txt)、[移存清单](final_evidence/retained_removed_fixtures/manifest.json) |

默认入口本身只验证仿真与完整帧，不执行 golden 比较；另三条 RTL 路径执行严格比较。xsim 的断言失败可能仍返回 0，定向入口同时检查失败内容和完成标记，编译失败不能当成成功检错。

## 软件视频与尚存局限

[同次软件结果](final_evidence/tools/software_rerun/results.json)与逐目标、逐帧、分配审计 CSV 一起归档。两段视频逐帧解码均为 120 帧、1280×720、30 fps，哈希不同；同模式直接运行与观察器的 CSV、告警和视频一致。视频事件显示帧和 CSV 一致。

| 模式 | 可见目标召回 | 误框 / 换号 / 断航 | 可评估方向正确数 | 视频及明细 |
| --- | --- | --- | --- | --- |
| clean 理想掩码 | 210/210 | 0 / 0 / 0 | 207/208 | [目录](final_evidence/tools/software_rerun/clean/) |
| algo 检测链 | 186/210 | 0 / 0 / 0 | 183/184 | [目录](final_evidence/tools/software_rerun/algo/) |

两模式均为 2 次进入、1 次离开、0 次停留；第 34 帧 cross_out，第 43、102 帧 cross_in。几何真值在第 32 帧离开，合并目标条件下跟踪告警晚 2 帧，不能写成事件零延迟。algo 有 24 个可见目标观测未匹配，两模式各有一次可评估方向错误。这些限制保留在结果中，不以回归通过掩盖。

[视频复核](final_evidence/media_recheck.json)记录完整解码与哈希；[RTL 叠加复核](final_evidence/rtl_overlay_recheck.json)逐帧比较 3 组、共 36 帧图像中的红框与上一帧 bbox，并完整读取掩码图像。原始大体积 PPM 与仿真构建产物留在本机，路径、大小、SHA256、是否随仓库交付见 [全量清单](final_evidence/retained_artifacts.json)。

## 复现和历史证据

在仓库根目录运行，替换为本机实际 Python、Vivado 路径，输出必须是仓库外尚不存在的英文目录：

```powershell
python -X utf8 sim/line3/run_repair_regressions.py --settings <DRIVE>/AMD2025.2/2025.2/Vivado/settings64.bat --out <DRIVE>/666666/Temp/repair_review_new01
```

最终原始产物为 `<DRIVE>/666666/Temp/codex_repair_20261010_final01`，冻结 checkout 位于其下。输出的 jobs.json 必须包含全部 12 项且退出码全为 0，checkout_status.txt 必须为空。最终归档后的提交仅补报告、索引和证据；源代码与受测提交一致。

开发失败仍保留：[contracts01](contracts01/results.json)暴露模型 64/49 差异；[contracts02](contracts02/results.json)暴露旧 RTL 贴边残留；[contracts03](contracts03/results.json)是中间验证，最终以 final_evidence 为准。software_first 的 EXIT 打印 KeyError 已修复，software_second 与旧漏报 cross_out 的参考 CSV 差异仍保留，旧参考未改写。

第一次边界测试虽为 174/174，但完整性退出 1，仍记为失败：[逐项清单](first_integrity_failure.json)。核查为 4 个实时日志变化和 145 个并行输出新增。最终轮将所有产物隔离到 checkout 外，完整性检查通过。

原始 CSV、视频、失败证据与基线备份均保留：[基线备份](backup.json)、[本次文档备份](final_evidence/document_backup.json)。仓库首页提供本报告入口；GitHub 分支与 PR 的最终状态以接续交付记录及 PR 页面为准。

归档后另扫描了本次更新的两份说明；旧命令解析器识别到 0 条目标命令，不作为新回归入口参数已验证的依据，新入口以实际完成运行及 jobs.json 为据：[结果](final_evidence/updated_doc_checks.json)。活动工作区的全目录扫描会读到未入 Git 的旧故障样本，并对 10 个刻意写错的参数报错；[原始输出](final_evidence/working_tree_doc_scan.txt)保留。它们未进入冻结 checkout，未改写为正确命令以掩盖测试反例。
