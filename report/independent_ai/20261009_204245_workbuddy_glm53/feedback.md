# 独立 AI 反馈报告（feedback.md）

> 本报告由实际执行产生。模板原件：`docs/independent_review_report_template.md`。
> 审查计划：`review_plan.md`；第一轮预登记判断：`first_round_notes.md`；证据索引：`evidence_index.md`；执行日志：`execution_log.md`；原始产物：`raw/`。

## 身份与受测版本

- **AI 产品名称**：WorkBuddy（腾讯 CodeBuddy 桌面智能体产品）
- **模型名称/版本及确认来源**：系统声明为 GLM-5.3（Z.ai）。该信息来自宿主环境注入的会话标识，**我无法独立验证精确小版本**；除此之外模型版本按"未知"对待。本报告不冒用 OpenAI Codex、GPT 或任何其他模型身份。
- **执行日期、时间及时区**：2026-10-09，20:28–22:05，UTC+8（北京时间）
- **是否独立新会话**：是。本审查在独立新会话中执行，与原作者（OpenAI Codex）的会话无共享上下文。
- **已接触的作者结论或历史材料**（按接触顺序）：
  1. 先读：`docs/independent_review.md`、空白模板、分工/计划原文、`CONTRIBUTING.md`、`README.md`、`docs/getting_started.md`、源码（rtl_golden.py、cdnet_official.py、sim/line3/*、build/scripts/* 等）。
  2. 诚实披露：`README.md` 首页含作者声明"线三离线交付已有证据，但原始职责没有全部完成"，我在导航时不可避免读到；`docs/getting_started.md` 含若干结果口径说明。我的第一轮判断（`first_round_notes.md`，21:15 落笔）在此之后、**读作者汇总之前**完成并先行存档。
  3. 第一轮完成后才读：`docs/line3_status_20261009.md`、`docs/reproduce_line3.md`、`docs/captain_feedback_20261009.txt`、`docs/verification_fixes_20261009.md`、`report/line3_review_20261009/README.md`、`report/line3_20261009/*.md`（issues/report_draft/team_evidence/results_ledger）、工作区 `handoff.md`、`maintenance_20261009/*.json`、`delivery/manifest.json`。
  4. 未读：`docs/independent_review_prompt.md`（委托方给"另一 AI"的提示词，非证据）。
- **仓库、分支、完整 Git SHA、工作区差异**：
  本地 `<USER_HOME>\孙伟博\Desktop\FPGA大赛资料\captain_repo`，分支 `codex/line3-review-20261009`，
  **受测 SHA = `783cd7c49f474bab711671ed1dc644a0f58386ea`**，`git diff HEAD` 为空、无 stash。
  干净检出为 `git clone --no-hardlinks` 到仓库外 `<USER_HOME>\孙伟博\AppData\Local\Temp\ind_review_20261009\clone` 后 checkout 该 SHA（602 文件）。
  注意：作者自报"受测整合提交 bd10e2e"；我核对 `git diff bd10e2e 783cd7c` 仅含文档/证据/新增 verify_runner_live.py，**src/ 与 sim/ 代码零差异**，两者对本次复现等价。
- **操作系统、解释器、依赖、仿真工具**：Windows（win32）；托管 Python 3.13.12 新建 venv（numpy 2.5.3、opencv-python 4.14.0、matplotlib 3.10.x，均符合 `src/ps/requirements.txt` 区间）；Git for Windows；Vivado 2025.2（`<DRIVE>/AMD2025.2\2025.2\Vivado`，与推荐 2026.1 不同，已注意版本差）。
- **可执行与不可执行的范围及原因**：
  - 可执行：B 路全部命令、线三取证器、全部 Python 测试套件、真实 xsim 仿真、故障注入、证据比对、交付包校验。
  - **不可执行①：CDnet 真实数据复现**——本机无 CDnet2014 数据集（已搜 <DRIVE>/ 全部两级、桌面三级、temporalROI 特征文件，均无；环境变量 CDNET_ROOT 未设）。0.737 复现**未执行**，缺数据集。
  - **不可执行②：GitHub 远程实时核验**——仓库私有，本环境无凭据（`git ls-remote` 需交互用户名、匿名 API 404、`git credential fill` 挂起）。远程状态以本地缓存 `origin/*` 引用（最后一次成功 fetch 2026-10-09 20:22:04 +0800）为准，实时性不可复核。
  - **不可执行③：板卡/串口实物**——无硬件，D2 实物回传只能审代码与证据。
  - 环境异常声明：我会话中 xsim 每次在**完整产出正确结果后**以 0xC0000409 退出（沙箱内、非沙箱、纯英文路径均复现，共 4 次独立运行）；作者会话（PowerShell+Anaconda Python）rc=0。根因未定位，**不影响任何 CSV/日志内容**，但导致 run_sim.py 判"子进程非零退出"。

## 自定判据与执行范围

见 `review_plan.md`（20:42 落笔，未改动判据）。判据 J1.1–J5.5 全部按原样执行，无判据变更、无样本删除、无真值调整。故障注入只在仓库外克隆体进行，原仓库未被修改（`git status` 干净；取证器 `protected_files_changed=[]` 复核）。

## 逐项职责判断

| 原始职责及出处 | 本次实际执行/检查 | 证据路径 | 判定 | 限制 |
| --- | --- | --- | --- | --- |
| D1 ★独立复核：复现报出的数字（algo_lab/cdnet_official，分工原文第三节；第一周标志"自己跑出的 CSV 与仓库一致"） | ① CDnet 0.737：数据集缺失，**未执行**，归档 CSV 仅做结构审计（6 变体×12 段，无重复/非法行，V43 宏均值 0.7367 与声明一致）；② 不依赖 CDnet 的复核全部亲跑：rtl_golden 两模式、multi_track 两模式与仓库参考 CSV 内容一致（仅换行符差异）、真实 xsim 复跑归档 RTL CSV 一致 | `raw/line3_run_results.json`、`raw/rtl_golden_framediff_report.txt`、`raw/run_sim1.log` | **部分完成**（不依赖数据的部分独立复核通过；核心成绩 0.737 无法复核） | 缺 CDnet 数据集；归档 CSV 无逐帧 TP/FP/FN 原始计数，来源不可重推导 |
| D2 非 HDMI 验证通路：板端结果回传（串口/网口）+ 电脑画框 | 全仓检索 serial/uart/socket/pyserial/115200：**无任何板端回传实现**（唯一命中是 rgb2dvi 无关注释）；`board/logs`、`board/overlay` 为空。存在的只有电脑侧观察（observe.py）与画框视频，二者功能验证通过（事件帧红框与 CSV 对应、120 帧完整） | Grep 检索记录、`raw/line3_run_results.json`（video 节） | **部分完成**（电脑画框/观察已实现并验证；板端回传通路未实现、无实物证据） | 无板卡；协议未定义 |
| D3 材料纠错（18 条清单） | 核对 `materials/material_corrections_20261008.md`：18 个编号条目，分类清晰、含依据；本轮追加 `report/line3_20261009/issues.md` 20 条（I01-I05/D01-D05/B01-B05/T01-T05），抽查 B01-B03 与我独立发现一致、D01（CEC 引脚反向）与 XDC 原文一致 | 上述两文件、`sim/tb`、`board/pynq-z2_v1.0_official.xdc` | **已完成（本轮）** | 纠错"提出"不等于"已修"；接口类问题仍待 owner 决议 |
| D4 测试表格汇总 + 报告初稿 | `report/line3_20261009/report_draft.md`（九章初稿）与 `results_ledger.md` 存在；抽查台账 12 行关键数字，与我独立复现值全部一致（0.885714、5 FAIL、RTL 11/12 与排空 12/12、V43≈0.737 存量口径） | `raw/line3_run_results.json` 对照两文件 | **已完成初稿**；定稿条件（真实数据/板测/换手验）未满足 | 初稿非终稿，作者自己亦如此声明 |
| 通用：干净检出可复现 | 克隆体 783cd7c 全命令复跑成功（结果同上）；参考结果未被覆盖（取证器前后哈希核对通过） | `execution_log.md` | **可复现（离线部分）** | CDnet/板测/远程核验除外 |
| 通用：GitHub 同步 | 见下文专节 | `evidence_index.md` §Git | 分支已推送、含受测提交、main 未合并、无 PR/无他人审核 | 实时复核缺凭据 |

## 发现

> 分级：A=影响成绩/声明真实性；B=产品功能缺陷；C=证据/测试覆盖缺口；D=文档不一致；E=环境/流程注意项。

### F1【B】AlarmRule 告警逻辑三处实锤缺陷（作者已列 issues.md B01-B03，我独立复现确认）
- 位置：`src/ps/multi_track.py` AlarmRule.update（约 270–311 行）。
- 需求依据：分工原文"跟踪+越界告警…指标全绿"；入门.md"告警只在越过线时响"。
- 复现：`python -X utf8 sim/line3/run.py --out <新目录>`（干净检出，退出码 2），`results.json` 中 `cases` 5 项 FAIL：
  1. **cross_out 永远不触发**（exit_left/exit_right/reenter_left 期望 1 次离开事件，实际 0；代码只在 `moving_in` 为真时更新 side 并计事件）。
  2. **dwell 秒数按硬编码 30fps 折算**（10fps 构造下 1.0s 报 0.3s；输出处除以 30 而非 self.fps）。
  3. **滞留计数遇缺帧不清零**（present,present,missing,present,present 仍报警，与"连续"语义不符）。
- 影响：越界告警是计划第 10 项的核心功能；"2 次闯入+1 次离开"的预期行为当前**不成立**（实际两种模式都只有 2 次 cross_in、无离开）。作者如实记录且未修复 → 状态为"已知未修缺陷"。
- 是否独立复现：是（我首次运行即在未读 issues.md 前得到同样 5 FAIL，见 `first_round_notes.md`）。

### F2【C】RTL↔模型"逐位一致"证据的鉴别力存在三处盲区（作者未明确列出，本次新发现）
- 依据与复现（均在克隆体故障注入后运行 `rtl_golden.py --compare sim/wave/bbox_rtl.csv`）：
  1. **阈值常数不可鉴别**：激励是纯黑白饱和块（2×2 和域值仅 0/1020），把 `THRESH=70` 改为 69 后比较仍"11/11 完全一致"（注入 A2，退出码 0）。即"逐位一致"对阈值取值没有约束力，任何 0<T<1020 都通过。
  2. **边界清零逻辑不可鉴别**：删除 open3 末列清零（注入 A）后比较仍全一致——激励物体从不触及画面边缘。
  3. **第 11 帧不被默认证据覆盖**：仅改最后一帧输出（注入 C）后比较仍通过——归档 `sim/wave/bbox_rtl.csv` 只有帧 0..10。
- 影响：当前证据能证明的是"几何/包围盒/面积门限/回绕规则在 11 帧饱和激励下逐位一致"，**不能**证明阈值常数、边界处理、末帧行为的正确性。作者的 drained 变体（以及我的独立复刻）补上了帧 11，但①②两个盲区仍存在。
- 建议：激励增加灰度过渡与贴边目标，或在 testbench 中对 THRESH 边界值做定向断言。

### F3【C】归档 RTL CSV 与默认 testbench 只覆盖 11/12 帧（作者 T01 已列，我独立确认并复刻了排空实验）
- 机制：tb 在"下一帧掩码边界"才 poke 上一帧 bbox；默认收尾只留 1 帧，帧 11 的 poke 永不发生；`run_sim.py --expect-frames 12` 明确退出 2（作者与我的运行一致）。
- 我的独立补证：克隆体把 tb 等待改为 `FRAMES+1` 后重跑 xsim，得 12 行 CSV 与模型 12 帧输出**逐字节一致**（含帧 11=(100,40)-(127,54) cnt=240）。
- 影响：不构成"假通过"（作者用退出 2 显式暴露），但仓库默认归档证据 `sim/wave/bbox_rtl.csv`（11 行）与 `sim/logs/model_vs_rtl.txt` 的"完全一致"声明实际只覆盖 11 帧，引用时必须带此限定（作者台账已带）。

### F4【D】入门.md 的告警预期描述与实际产物矛盾
- `docs/getting_started.md` 4.4 称 alarm_events\*.csv "应该只有 3 行左右（2 次闯入 + 1 次离开）"。实际仓库归档与我的复跑均为 **2 行、全部 cross_in、无离开事件**（与 F1 的 cross_out 缺陷互为因果）。
- 影响：照文档自查的队友会把"缺离开事件"当成自己跑错。建议把该行改为描述当前实际行为并注明已知缺陷。

### F5【D】归档"clean"视频实为 algo 产物（作者已自曝 CSV 同问题，我补视频侧证据）
- `src/ps/track_result.mp4` 与 `src/ps/track_result_algo.mp4` 逐帧哈希完全一致（120/120 帧全等）。入门.md 已声明 CSV 名不副实并给出自行重跑指引，视频同理。归档视频与我重生成视频内容等价（平均像素差 0.011/255，纯编码噪声），**不存在证据混用**。
- 影响：低（已披露）；真正的 clean 归档物仍需按文档命令重跑获得。

### F6【C】multi_track 逐帧结果 CSV 无 tid 列，ID 级错误对帧级比较不可见
- 注入实验：把 Tracker 起始 ID 1→5，`multi_track_results_algo.csv` 与参考一致（不报警），`alarm_events_algo.csv` 被检出差异。
- 影响：frame CSV 比较不能单独作为跟踪正确性证据；现有 run.py 已同时比较告警 CSV，风险被覆盖，属提示项。

### F7【A→判定：不构成】CDnet 0.737 无法复核，但无伪造迹象
- 归档 CSV 内部自洽（无重复行、分数全在 [0,1]、变体/序列结构完整）；作者明确标注"存量审计、非本轮复跑"，未把 0.737 写成本轮复现。
- 不能确认项：0.737 是否来自所述 12 段真实数据的真实运行——缺数据集与逐帧原始计数，**本审查无法背书**。

### F8【E】本会话 xsim 退出码异常（0xC0000409）
- 4 次独立运行（沙箱/非沙箱/中英文路径）均为"内容完整正确 + 进程退出崩溃"；作者会话 rc=0。run_sim.py 正确地将之判为失败而非通过。建议作者在 PowerShell+Anaconda 环境复核；若那边正常，按会话环境记录即可，勿改判据。

### F9【D】交付 manifest 的"字节一致"声明精度
- `delivery/manifest.json` 称 ZIP 与干净检出逐字节一致；实测 602 文件中 114 个仅换行符不同（git archive 的 LF blob vs 工作区 CRLF），**真实内容差异为 0**。声明内容等价成立，"字节一致"措辞不严格（manifest 自身另有 EOL 说明，属小瑕疵）。

## 对作者结论的核对

| 作者结论（出处） | 我的核对 | 判定 |
| --- | --- | --- |
| CDnet 复核"未完成"，0.737 非本轮复现（line3_status） | 我无法复现（缺数据）；归档审计自洽；未发现作者把它写成已复现 | **认可** |
| 非 HDMI 验证"部分完成"，无板端回传证据（line3_status） | 我全仓检索确认无回传实现；电脑侧画框/观察验证通过 | **认可** |
| 5 项告警行为失败，保留退出 2（line3_status/台账） | 我独立复现同样 5 项，失败细节一致 | **认可** |
| RTL 默认 11 帧、expect-12 失败；排空两模式 12/12（line3_status/台账） | 我亲跑默认仿真得 11 行；独立复刻排空得 12/12 逐字节一致 | **认可** |
| 174/174、46/46、18/18、文档命令检查通过 | 我在干净检出分别重跑：174/174、46/46、18/18、PASS（36 命令）；另跑 22/22 数据守卫 | **认可**（数量真实，但均为"测试通过"，不等于产品行为全对——作者自己亦如此限定） |
| clean 210/210、algo 186/210=0.885714（台账） | 我的复跑：recall 1.0 与 0.885714，误检/换号/断航均 0 | **认可** |
| 交付 ZIP=602 文件、与干净检出一致 | 我校验：602 文件 0 真实差异（114 个仅 EOL）、SHA256 与 manifest 一致、CRC 完好 | **认可**（措辞见 F9） |
| GitHub：分支已推送同 SHA、main 未合并、无 PR、无他人审核 | 我的缓存远程引用独立复核一致；实时复核缺凭据 | **认可（截至 2026-10-09 20:22 +08）** |
| "另一 AI 尚未独立审查"（handoff） | 本报告即为该审查；此前不存在 | **认可** |
| 作者未提及 | F2（饱和激励致阈值/边界不可鉴别）、F4（入门.md 告警预期与实际矛盾）、F5（clean 视频=algo 视频）、F6（帧 CSV 无 tid） | **本次新发现** |

共因错误风险声明：rtl_golden 模型与 RTL 由同一团队按同一设计意图编写，二者一致不证明设计正确（只证明实现互相吻合）；CDnet 归档 CSV 的生成环境与本次无共享，但缺乏原始数据时无法排除历史口径漂移。既有测试的可能漏检面：F2 列出的三处盲区 + 帧 CSV 无 tid（F6）。

## 清理、复现和 GitHub

- **干净检出复现**：从本地对象库克隆 783cd7c 到仓库外，B 路全部命令、三套测试套件、取证器、真实 xsim 均可复跑；仓库参考结果未被覆盖（取证器前后哈希核对）。**离线部分可从干净检出复现；含 CDnet/板测的完整复现不可行（缺数据/硬件）。**
- **清理是否丢失必要内容**：清理前备份 `../FPGA大赛资料_清理备份_20261009_2004` 存在（含 bundle 与哈希验证文件）；`archive/`、`delivery/` 清单与实物一致；仓库内未缺 B 路所需输入（合成素材、参考 CSV、testbench、脚本齐全）。handoff 明确"retired_originals 仍保留、26648 旧文件未永久删除"。**未发现清理丢失必要依赖。**
- **GitHub 实际同步范围**（五项分别判定）：
  | 项 | 判定 | 依据 |
  | --- | --- | --- |
  | 本地已提交 | 是 | 本地分支 HEAD=783cd7c |
  | 远程分支存在 | 是（截至 20:22 缓存） | `origin/codex/line3-review-20261009` reflog "fetch origin: storing head" @20:22:04；作者 20:20 ls-remote 记录（maintenance_20261009/github_sync.json）同 SHA |
  | 远程含受测提交 | 是（同上） | 缓存引用=783cd7c |
  | main 已合并 | **否** | `origin/main`=452075f；783cd7c 非其祖先 |
  | 他人已审核 | **否** | 无 PR；换手验未发生；本报告为首次独立审查 |
  - 实时复核不可行（无凭据），以上为截至 2026-10-09 20:22 +08 的状态；不存在"只提交未推送"或"把只推分支说成已合并"的情况。

## 给原 Codex 的反馈（需处理/解释事项）

1. **F1 告警缺陷修复后需回归**：cross_out 方向判定、dwell 的 fps 来源、缺帧清零语义（遮挡期间语义需团队先决议）。修复后跑 `sim/line3/run.py` 应回到退出 0，且 5 项 FAIL 解除；注意修复 PR 需他人换手验，你不能自签。
2. **F2 证据盲区**：建议给合成激励加灰度过渡与贴边/出画目标，使阈值与边界行为对比较敏感；或在 tb 增加 THRESH 边界值断言。在此之前，"逐位一致"的引用范围应限定为"几何/包围盒/回绕，11+1 帧，饱和激励"。
3. **F4/F5 文档修订**：入门.md 的告警预期行改为描述实际行为并链接 issues.md；clean 视频与 CSV 的名实问题可在你计划的"自行重跑"指引中一并说明视频同源。
4. **F3**：若团队接受，把默认 tb 收尾改为按掩码边界计数排空（你已有 drained 入口），使默认归档 CSV 天然 12 行；否则在 sim/README 固定注明"归档 CSV 少最后一帧"。
5. **F8**：请在你会话（PowerShell+Anaconda Python）重跑一次 `run_sim.py` 确认 rc=0；若复现 0xC0000409 则是机器级问题需另查。
6. **F7（0.737）**：请数据 owner 提供 12 段数据路径+帧清单后，由非作者机器复跑 `cdnet_official.py --set r12` 并保留逐帧 TP/FP/FN；在此之前任何"0.737 已复核"表述都不成立。
7. 本报告不能确认的结论：0.737 真实性、远程 refs 的实时状态、板端一切行为、xsim 退出码根因。

## 证据索引

见 `evidence_index.md`（命令、退出码、原始日志、哈希、路径；区分本次新运行与引用历史记录）。
