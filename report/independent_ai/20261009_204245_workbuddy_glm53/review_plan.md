# 独立审查计划（review_plan.md）

- 审查者：WorkBuddy（底层模型 GLM，Z.ai；版本号按系统声明为 GLM-5.3，无法独立验证）
- 计划落笔时间：2026-10-09 20:42:45 +0800（此时**尚未**运行任何复现命令，**尚未**读取作者汇总类文档）
- 受测版本：仓库 `<DRIVE>/Users\孙伟博\Desktop\FPGA大赛资料\captain_repo`，
  分支 `codex/line3-review-20261009`，提交 `783cd7c49f474bab711671ed1dc644a0f58386ea`（工作区干净，git diff HEAD 为空）

## 0. 已读材料与接触顺序声明（防"先看答案"）

已读（需求来源与协作规范，允许）：
- `docs/independent_review.md`（审查委托）
- `docs/independent_review_report_template.md`（空白模板）
- `docs/review_inputs/team_division_20261008.txt`（分工原文）
- `docs/review_inputs/team_plan_20261008.txt`（计划原文）
- `CONTRIBUTING.md`（协作规范）
- `README.md`、`docs/getting_started.md`（导航性质文档。注意：README 首页含作者自述结论
  「线三离线交付已有证据，但原始职责没有全部完成」，我已不可避免接触到该声明；
  本计划不受其引导，所有结论以我自己的执行为准）
- 代码通读：`src/ps/rtl_golden.py`、`src/ps/cdnet_official.py`、`sim/line3/run.py`、`sim/line3/cases.py`
  （其余脚本在执行中按需阅读）

计划**第一轮判断之后**才读的作者汇总（清单先固定，防止临时挑选）：
`docs/line3_status_20261009.md`、`docs/line3_run.md`、`docs/reproduce_line3.md`、
`docs/captain_feedback_20261009.txt`、`docs/verification_fixes_20261009.md`、
`report/line3_20261009/*.md`（README/issues/milestone/results_ledger/report_draft/team_evidence/inspection_notes/requirements/llm_record）、
`report/line3_review_20261009/README.md`。
本轮**不读** `docs/independent_review_prompt.md`（委托方写给我之外 AI 的提示词，非证据）。

## 1. 需求来源（判据的唯一依据）

分工原文（team_division_20261008.txt）线三职责，逐条抄录为验收对象：

| # | 职责（原文） | 交付（原文） |
| --- | --- | --- |
| D1 | ★ 独立复核：在自己机器上复现报出来的数字（跑 algo_lab.py、cdnet_official.py） | 复现记录（第一周完成标志：自己跑出的 CSV 跟仓库里的一致；CDnet 官方口径 0.737） |
| D2 | 非 HDMI 验证通路：把结果从板子回传到电脑（串口/网口），用 Python 把框画出来 | （归入"复现记录+报告初稿+纠错清单"总交付；第一周完成标志含跑通仿真或构建） |
| D3 | 材料纠错（已开始，18 条清单） | 纠错清单 |
| D4 | 测试表格汇总 + 报告初稿 | 复现记录 + 报告初稿 + 纠错清单 |

背景约束（分工原文第三节）：线三由"只想用一台电脑"的成员执行；D2 设计目的即"看不到 HDMI 也能验证"。

## 2. 我的验收判据（先行固定）

### D1 独立复核
- J1.1 CDnet 官方口径 0.737（V43，12 段/7 类）**必须由我在本机用真实 CDnet 数据重跑**才能记"已完成复核"。
  若数据缺失 → "无法判断（缺数据）"，且要求作者说明数据下落。
- J1.2 不依赖 CDnet 的复核对象（rtl_golden 两种模式、multi_track 两种 source、
  与仓库参考 CSV 的一致性）必须逐字节/逐帧核对，且我必须亲自重跑。
- J1.3 仓库中作为"参考答案"的 CSV 与再生成命令必须可对应；凡"名不副实"的参考文件
  （文档已自曝 multi_track_results.csv 与 _algo 相同）按发现记录。

### D2 非 HDMI 验证通路
- J2.1 判"已完成"需要：板端把包围盒坐标经串口/网口回传的**实物或真实运行证据**，
  加上电脑侧画框代码。只有纯 Python 画框/视频叠加而无论何板端回传证据 → 最多"部分完成"。
- J2.2 代码层面检查：是否存在串口/网口读取坐标并画框的实现；其测试是软件仿真还是真实回传。
- J2.3 RTL 仿真证据（xsim 波形/CSV）与 Python 模型一致性必须我能重跑或核验原始日志。

### D3 材料纠错
- J3.1 纠错清单存在、可追溯（指出原文件与错误点）、数量级与"18 条"声明可对上。

### D4 测试表格汇总 + 报告初稿
- J4.1 报告初稿存在且覆盖线三职责范围；表格汇总真实对应已跑测试。
- J4.2 报告/表格中的数字与原始日志/CSV 一致（抽查处）。

### 通用
- J5.1 干净检出（新目录、固定 SHA）后 B 路命令全部能跑，不覆盖参考结果。
- J5.2 既有测试能发现错误：用**隔离副本中的故障注入**（改源码副本、不改仓库）验证
  至少 3 类注入会被检出；同时找出既有测试**检不出**的错误类别。
- J5.3 证据链：日志/CSV/视频/报告描述同一次运行（抽查命令 json 的 argv、时间、退出码）。
- J5.4 清理是否丢失必要内容：对照 report/line3_20261009（旧基线）与 report/verification_20261009、
  report/line3_review_20261009，检查"只留结论不留证据"或"参考文件被覆盖"的情况。
- J5.5 GitHub 同步：本地已提交 / 远程分支存在 / 远程含该提交 / main 已合并 / 他人审核，五项分别判定。
  本环境无 GitHub 凭据（git ls-remote 需交互输入用户名、匿名 API 404），
  只能以本地缓存的 origin/* 引用（最后 fetch 于 2026-10-09 20:22:04 +0800）为证，并如实标注不可复核。

## 3. 计划执行的检查

1. 干净检出：`git clone <本地对象库> <临时目录>` 并 `checkout 783cd7c`（网络不可用，从本地对象库克隆；
   克隆体不带工作区污染，等效干净检出；SHA 与缓存远程引用一致）。
2. 在克隆体运行：rtl_golden 两种模式、multi_track clean/algo、sim/line3/run.py 全量取证器。
3. 与原仓库参考文件逐字节比对（framediff.csv vs sim/wave/bbox_rtl.csv 0..10 帧；
   algo 输出 vs multi_track_results_algo.csv / alarm_events_algo.csv）。
4. RTL 仿真：用本机 Vivado 2025.2（与推荐 2026.1 不同，记录差异）跑 build/scripts/run_sim.py。
5. CDnet：数据不在本机（已搜 <DRIVE>/ 与桌面，未发现）→ 尝试作者文档指路的复现入口，如不可得则记未执行。
6. 故障注入（在克隆体）：分别改 multi_track 阈值/坐标、rtl_golden 边界、compare 容差，
   验证 sim/line3 测试是否报警。
7. 证据对应抽查 + 视频可解码抽查（cv2 逐帧哈希、尺寸、事件帧红框）。
8. 汇总第一轮判断 → 然后才读第 0 节列出的作者汇总 → 写 feedback.md。

## 4. 已知限制（先行声明）

- 无 GitHub 凭据：远程 refs 不能实时复核。
- 无 CDnet 数据（若后续找不到）：D1 的 0.737 复现记"未执行，缺数据"。
- 无板卡/串口硬件：D2 的实物回传只能查证据与代码，不能实测。
- Vivado 为 2025.2 非推荐 2026.1：仿真结果如与历史日志有差，先怀疑版本差。
- 我不看图像内容的"人眼确认"，视频检查用 cv2 解码 + 像素统计，结论限于可编程验证范围。
