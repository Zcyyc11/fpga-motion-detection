# 证据索引（evidence_index.md）

审查者：WorkBuddy（GLM-5.3，系统声明）｜ 日期：2026-10-09 UTC+8 ｜ 受测 SHA：`783cd7c49f474bab711671ed1dc644a0f58386ea`
标记：**[新]**=本次新运行；**[史]**=引用的历史/作者记录（仅核对，不当作本次产出）。

## 1. 版本与远程核验

| # | 命令/方法 | 结果 | 标记 |
|---|---|---|---|
| E01 | `git status; git rev-parse codex/line3-review-20261009` | 分支 HEAD=783cd7c…86ea；工作区干净、无 stash | [新] |
| E02 | `git ls-remote origin` | **未成功**：私有库需交互凭据（"could not read Username"），匿名 API 404，credential fill 挂起 | [新] |
| E03 | 本地缓存远程引用 + reflog | `origin/codex/line3-review-20261009`=783cd7c（reflog: fetch @2026-10-09 20:22:04 +08）；`origin/main`=452075f（@18:59:31）；783cd7c 非 origin/main 祖先；452075f 是审查分支祖先 | [新] |
| E04 | `maintenance_20261009/github_sync.json` | 作者 20:20:48 ls-remote 记录：远程分支=783cd7c、main=452075f、无 PR、未合并 | [史]（与 E03 一致） |
| E05 | `git diff bd10e2e 783cd7c` | 作者受测提交与本次受测提交之间 src/、sim/ 代码零差异（仅文档/证据/新增 verify_runner_live.py） | [新] |

## 2. 干净检出与软件复现（工作目录 `<USER_HOME>\孙伟博\AppData\Local\Temp\ind_review_20261009\clone`）

解释器：`<USER_HOME>\孙伟博\.workbuddy\binaries\python\envs\default\Scripts\python.exe`（3.13.12；numpy 2.5.3、opencv 4.14.0、matplotlib 3.10.x；venv 为本次新建）。

| # | 命令（克隆体根目录，`python -X utf8` 前缀略） | 退出码 | 关键结果 | 原始证据 |
|---|---|---|---|---|
| E06 | `git clone --no-hardlinks <captain_repo> clone && git checkout 783cd7c` | 0 | 602 文件干净检出 | 执行日志 §1 |
| E07 | `src/ps/rtl_golden.py --mode framediff --out-csv … --compare sim/wave/bbox_rtl.csv --report …` | 0 | 与归档 RTL CSV **11/11 帧逐字段一致** | `raw/rtl_golden_framediff_report.txt` |
| E08 | `src/ps/rtl_golden.py --mode bg --out-csv …` | 0 | 12 帧输出正常 | 执行日志 §2 |
| E09 | `src/ps/multi_track.py --source clean --alarm --line-x 640 --outdir …` | 0 | 告警 2 行（43,cross_in;102,cross_in），无离开事件 | `raw/mt_clean.log` |
| E10 | `src/ps/multi_track.py --source algo --alarm --line-x 640 --init-frames 12 --outdir …` | 0 | 输出与仓库 `multi_track_results_algo.csv`、`alarm_events_algo.csv` **CRLF 归一化后逐字节一致** | `raw/mt_algo.log` |
| E11 | `sim/line3/run.py --out <新目录>` | **2** | infrastructure_pass=true；behaviour_failures=[exit_left, reenter_left, exit_right, dwell_non30fps, dwell_consecutive_gap]；clean recall 1.0 / algo 0.885714；protected_files_changed=[] | `raw/line3_run_results.json`、`raw/line3_run_commands.json` |
| E12 | `build/scripts/test_verification_boundaries.py --repo clone --out …` | 0 | **174/174**，repo changed=0 | `raw/boundaries.log` |
| E13 | `build/scripts/test_sim_runner.py --out <tempfile 目录>` | 0 | **46/46** | 执行日志 §5 |
| E14 | `build/scripts/test_data_guard.py --keep` | 0 | **22/22**（含 4 种路径逐帧 md5 一致） | `raw/dataguard4.log` |
| E15 | `build/scripts/check_doc_commands.py` | 0 | 36 命令全部有效 | `raw/doccheck.log` |
| E16 | `sim/line3/check_tools.py --out <tempfile 目录>` | 0 | **18/18** | 执行日志 §6 |
| E17 | `src/ps/cdnet_official.py --set r12 --seq all`（无数据） | 1 | 明确报错"[数据未就绪]"，不产空表 | `raw/cdnet_nodata.log` |
| E18 | `src/ps/algo_lab.py --data-root <DRIVE>/不存在… --list` | 1 | 明确报错路径不存在 | `raw/cdnet_bogus.log` |
| E19 | CDnet 数据集本机搜索（<DRIVE>/ 两级、桌面三级、temporalROI 特征） | — | **未发现数据集**；CDNET_ROOT 未设 → 0.737 复现未执行 | 执行日志 §0 |
| E20 | 归档 CSV 结构审计（E11 内置 cdnet_audit） | — | 6 变体×12 段，无重复/非法行；V43 宏均值 0.7367 | `raw/line3_run_results.json` |

## 3. 真实 RTL 仿真（Vivado 2025.2，`--vivado-settings <DRIVE>/AMD2025.2\2025.2\Vivado\settings64.bat`）

| # | 命令 | 退出码 | 关键结果 | 原始证据 |
|---|---|---|---|---|
| E21 | `build/scripts/run_sim.py --scratch-root <T>\sim_scratch` | 2 | 仿真内容完整（11 条记录帧 0..10、仿真结束标记、x_hits=0）；**子进程退出 0xC0000409** 判失败；产出 CSV 与仓库归档**内容一致** | `raw/run_sim1.log`，完整日志在 `<T>\sim_scratch\run_20261009T124753Z_pnnme44a\` |
| E22 | 同上（第二遍，新 scratch） | 2 | 同样 11 条 + 0xC0000409（可复现） | `raw/run_sim2.log` |
| E23 | 同上（非沙箱运行） | 2 | 同样 11 条 + 0xC0000409（排除沙箱因素） | `raw/run_sim_nosandbox.log` |
| E24 | 排空实验：克隆体 tb 改 `while (vframe <= FRAMES + 1)` 后 run_sim.py | 2（退出码同上） | **12 条记录帧 0..11**，CSV 与作者 `rtl_drained_framediff/expected.csv` **逐字节一致**（帧 11=(100,40)-(127,54) cnt=240）；实验后 tb 已还原 | `raw/run_sim_drained.log` |
| E25 | `build/scripts/verify_runner_live.py --repo clone --out … --ascii-root <DRIVE>/666666/Temp/ind_review_ascii --settings …` | 1 | 7 项真实 Vivado 运行：compile_error/x_state 反例**被正确拒绝**；expect12 **正确失败**（缺帧 11）；4 项路径变体均因 0xC0000409 判失败（作者环境为通过） | `raw/runner_live.log` |

## 4. 故障注入（均在克隆体，原仓库未动；注入后均已还原并 git status 复核干净）

| # | 注入 | 检出情况 | 结论 | 原始证据 |
|---|---|---|---|---|
| E26 | rtl_golden open3 删末列清零（注入 A） | **未检出**（11/11 仍一致，退出 0） | 激励从不贴边 → 边界逻辑盲区（F2-②） | `raw/mutA.log` |
| E27 | rtl_golden THRESH 70→69（注入 A2） | **未检出** | 饱和激励 → 阈值常数盲区（F2-①） | `raw/mutA2.log` |
| E28 | rtl_golden 仅改第 11 帧输出（注入 C） | **未检出** | 归档 CSV 止于帧 10 → 末帧盲区（F2-③/F3） | `raw/mutC.log` |
| E29 | multi_track Tracker 起始 ID 1→5 | 帧 CSV **未检出**；告警 CSV **被检出** | 帧 CSV 无 tid 列（F6）；告警比较器有效 | 执行日志 §7 |

## 5. 证据对应与交付校验

| # | 方法 | 结果 | 标记 |
|---|---|---|---|
| E30 | 归档 vs 重生成 `track_result_algo.mp4` 逐帧哈希 | 不同（H.264 编码噪声）；量化：平均像素差 0.011/255，最差帧 921600 像素中仅 4 个差>32 → 内容等价，**非版本混用** | [新] |
| E31 | `track_result.mp4` vs `track_result_algo.mp4` 逐帧哈希 | **120/120 全等** → 归档"clean"视频即 algo 产物（F5） | [新] |
| E32 | delivery ZIP 全量字节比对（602 文件） | 0 真实内容差异；114 个仅 EOL 差异；ZIP SHA256 与 manifest 一致；CRC 完好 | [新] |
| E33 | 作者 `rtl_default/result.json`、`rtl_default_complete.command.json`、`rtl_drained_framediff/*` | 与我 E21/E24 独立结果一致（默认 11 帧、expect-12 退出 2、排空 12/12） | [史] |
| E34 | `materials/material_corrections_20261008.md` | 18 个编号条目（与"18 条清单"声明相符） | [史]（计数核对） |
| E35 | 清理备份 `../FPGA大赛资料_清理备份_20261009_2004` | 存在，含 bundle/哈希验证；未发现清理丢失必要依赖 | [新]（存在性核对） |

## 6. 受测对象哈希（本次计算）

- 受测提交：`783cd7c49f474bab711671ed1dc644a0f58386ea`
- 输入片段：`data/golden/track_cross.avi` 等由 E11 的 manifest（`raw/line3_run_results.json` 对应 run 目录 `manifest.json`）记录 protected 哈希，前后一致。
- 作者 RTL 源哈希：E33 中 `rtl_drained_framediff/result.json` 的 source_sha256 与我克隆体对应文件一致（diff E05 已证 src/ 零差异）。

## 7. 本次未执行事项（如实声明）

- CDnet 12 段真实数据复跑（缺数据集）。
- GitHub 远程实时 ls-remote / PR 状态查询（无凭据）。
- 板卡下载、串口/网口实物回传、HDMI 目视（无硬件）。
- 综合实现（build_vivado.bat 全构建）与资源/时序复核（非本轮职责范围且耗时长；归档报告仅作 [史] 引用未复核）。
- `sim/line3/run_rtl.py`（作者排空入口）：我以自改 tb 变体（E24）等价验证，未重复跑其脚本。
