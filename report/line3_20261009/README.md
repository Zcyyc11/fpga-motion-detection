> 历史记录：本文描述当时版本与当时授权，不能作为整合分支的当前状态或执行指令。当前入口为仓库 README、docs/reproduce_line3.md 和 docs/line3_status_20261009.md。旧绝对路径可通过外层维护清单和完整备份追溯。

<!-- Hallmark · pre-emit critique: P5 H4 E4 S5 R5 V4; scope: delivery navigation and honest status. -->

# 线三离线验证交付

日期2026-10-09。固定算法基线ead15e0，开发分支feat/line3-verification。本轮能独立完成的测试、PC显示检查、资料审计和报告初稿已整理；整机上板与真实CDnet仍待外部证据。

## 先看这几份

- [运行说明](../../docs/line3_run.md)：环境、参数、命令、返回码及比较口径。
- [结果台账](results_ledger.md)：哪些是本轮实测、哪些是历史数据，失败与范围限制。
- [问题单](issues.md)：接口、资料和算法反例，含来源行号与建议owner。
- [官方要求映射](requirements.md)：提交物、证据和当前缺口。
- [九章报告初稿](report_draft.md)：可继续补证据的正文及功能框图。
- [队友待补清单](team_evidence.md)：上板、性能、算法修复与换手验的具体材料。
- [真实协作记录](llm_record.md)：实际提示词/回答节选、自我纠错与验证结果。
- [严格比对技能补充](../../skill/line3_strict_evidence/README.md)：复用范围、用法和失效条件。

## 关键结果

软件clean召回210/210，algo186/210；两个120帧视频完整，误检/换号/断航为0。25项小用例仍有5项告警FAIL，统一入口返回2。工具18项验收通过。

原RTL台缺第11帧；只扩展排空参数后，framediff/bg均12/12逐字段一致、无X，红框输出各12图精确通过。没有改核心算法、冻结接口或原testbench。CDnet0.737仅为历史CSV的12段/7类宏均值审计；本轮没有板卡实测、综合实现或CDnet真实复跑。

## 证据目录

| 目录 | 内容 |
|---|---|
| `run_ead15e0_01/` | 首轮完整软件结果、源文件哈希、命令日志、25项用例与CDnet存量审计 |
| `tool_acceptance_02/` | 18项工具验收及修改后的软件完整重跑 |
| `rtl_fd01/` | 原台新仿真，完整帧集FAIL |
| `rtl_fd02/` | 沙箱编译失败，完整记录保留 |
| `rtl_fd03/`、`rtl_bg01/` | 扩展排空后的两模式新仿真、CSV、日志和原PPM |
| `media_03/` | 告警邻帧拼图、方向不一致样本与离开计数时刻 |
| `media_fd03/`、`media_bg01/` | 两模式精确红框检查与完整帧集合 |
| `media_02/` | 不完整尝试，仅拼图，后续查RTL失败目录时异常退出 |

原 `milestone_01.md`、`inspection_notes.md` 仅代表第一轮时点，后续结论以本索引和台账为准。所有失败和中间记录保留，不覆写历史。
