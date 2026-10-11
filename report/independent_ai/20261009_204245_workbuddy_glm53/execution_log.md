# 实际执行日志（execution_log.md）

时间均为 2026-10-09 UTC+8。Shell：Git Bash。`$PY` = `C:\Users\孙伟博\.workbuddy\binaries\python\envs\default\Scripts\python.exe`。
临时工作目录 `$T` = `C:\Users\孙伟博\AppData\Local\Temp\ind_review_20261009`（仓库外，全部运行产物保留于此）。

## §0 准备（20:28–20:44）

- 读委托/模板/分工/计划/协作规范/README/入门（接触顺序见 feedback.md）。
- `git status` → 分支 codex/line3-review-20261009，干净；`git rev-parse` → 783cd7c…86ea；`git fetch` 卡死（SIGTERM）；`git ls-remote` → `fatal: could not read Username`（exit 124/128）；匿名 GitHub API → 404；凭据填充挂起。结论：无凭据，用缓存引用。
- 建 venv：`python -m venv …envs\default`；`pip install numpy opencv-python`（初装到 cv2 5.0.0，超 requirements 区间）→ 降级 `opencv-python>=4.10,<5`（得 4.14.0）→ 补 `matplotlib>=3.8,<4`。
- CDnet 搜索：`find /d/ -maxdepth 2/4` 与桌面 maxdepth 3（*cdnet*、*cdnet2014*、*changedetection*、*temporalROI*）→ 0 命中；`echo $CDNET_ROOT` 空。
- 20:42 写 `review_plan.md`（判据先行固定）。

## §1 干净检出（20:45）

`mkdir -p $T && git clone --no-hardlinks "C:\Users\孙伟博\Desktop\FPGA大赛资料\captain_repo" $T/clone` → exit 0（602 文件）；
`git checkout -q 783cd7c…` → HEAD 一致、`git status` 干净。

## §2 软件复现（20:46–20:55）

| 时间 | 命令（$T/clone 下） | exit |
|---|---|---|
| 20:46 | `$PY -X utf8 src/ps/rtl_golden.py --mode framediff --out-csv $T\out\framediff.csv --compare sim/wave/bbox_rtl.csv --report $T\out\rtl_golden_framediff_report.txt` | 0（共同帧 11，全一致） |
| 20:47 | `$PY -X utf8 src/ps/rtl_golden.py --mode bg --out-csv $T\out\bg.csv` | 0 |
| 20:47 | `$PY -X utf8 src/ps/multi_track.py --source clean --alarm --line-x 640 --outdir $T\out\out_clean` | 首跑 1（缺 matplotlib）→ 装后 0 |
| 20:48 | `$PY -X utf8 src/ps/multi_track.py --source algo --alarm --line-x 640 --init-frames 12 --outdir $T\out\out_algo` | 0 |
| 20:48 | `cmp` 四组参考 CSV：字节级不同 → `tr -d '\r'` 归一化后**全部一致**（我机写出 CRLF，归档 LF） | — |
| 20:48 | `cat src/ps/alarm_events_algo.csv` → 仅 2 行 cross_in；入门.md"2 闯入+1 离开"不符（F4） | — |

## §3 线三取证器（20:47–20:49）

`$PY -X utf8 sim/line3/run.py --out $T\out\line3_run` → **exit 2**；
stdout 尾行：`{"behaviour_failures": ["exit_left","reenter_left","exit_right","dwell_non30fps","dwell_consecutive_gap"], "infrastructure_pass": true}`。
results.json 要点：clean recall 1.0 / id_switches 0 / track_breaks 0；algo recall 0.885714；archive_0_10_diff=[]；archive_full_model_diff 仅帧 11；cdnet 归档审计自洽；protected_files_changed=[]。

## §4 真实 RTL 仿真（20:48–21:10）

| 时间 | 命令 | exit | 结果 |
|---|---|---|---|
| 20:48 | `run_sim.py --vivado-settings D:\AMD2025.2\2025.2\Vivado\settings64.bat --scratch-root $T\sim_scratch` | 2 | 内容完整（11 条、结束标记、x_hits=0）；子进程 0xC0000409 |
| 20:49 | 同上，`sim_scratch2` | 2 | 同上（复现） |
| 20:49 | 归一化 cmp：我产出 CSV vs 仓库 `sim/wave/bbox_rtl.csv` | — | **内容一致** |
| 21:08 | 排空实验：`sed` 改克隆体 tb `while (vframe <= FRAMES + 1)` → `run_sim.py --scratch-root $T\sim_scratch3`；比对其 CSV 与作者 expected.csv | 2 | **12 条帧 0..11，逐字节一致**；tb 还原，`git status` 干净 |
| 21:19 | `verify_runner_live.py --repo $T/clone --out $T\out\rl3 --ascii-root D:/666666/Temp/ind_review_ascii --settings …` | 1 | compile_error/x_state 正确拒绝；expect12 正确失败；4 项路径变体均 0xC0000409 |
| 21:20 | `run_sim.py`（非沙箱，`D:/666666/Temp/ind_review_nosandbox`） | 2 | 仍 0xC0000409 → 非沙箱因素 |

## §5 测试套件（20:52–21:05）

| 命令 | exit | 结果 |
|---|---|---|
| `test_verification_boundaries.py --repo $T/clone --out $T\out\boundaries` | 0 | 174/174 |
| `check_doc_commands.py` | 0 | 36 命令有效 |
| `test_data_guard.py --tmpdir …` | 1（FileExistsError，沙箱预建目录假象）→ `--keep` 默认随机目录 | 0 | 22/22 |
| `test_sim_runner.py --out <tempfile>` | 0 | 46/46 |
| `sim/line3/check_tools.py --out <tempfile>` | 0 | 18/18 |
| `cdnet_official.py --set r12 --seq all`（无数据） | 1 | 明确报错不产空表 |
| `algo_lab.py --data-root C:/不存在… --list` | 1 | 明确报错 |

## §6 故障注入（20:50–21:00，克隆体）

注入 A（删 open3 末列清零）→ compare exit 0 未检出；注入 A2（THRESH 69）→ exit 0 未检出；注入 C（仅改第 11 帧）→ exit 0 未检出；注入 B（next_id 5）→ 帧 CSV 未检出、告警 CSV 检出。每次注入后 `cp` 还原并 `git status` 复核干净。

## §7 证据对应（21:00–21:10）

- 视频哈希四组比对（E30/E31）；差异量化（均值 0.011/255）。
- ZIP 全量 602 文件比对（E32）：0 真实差异，114 EOL-only。
- 作者证据抽查：rtl_default/result.json、rtl_default_complete.command.json、rtl_drained_framediff（result/console/CSV diff）；results_ledger、issues.md 与我数据逐点一致。
- `maintenance_20261009/github_sync.json`、`clean_checkout_audit.json`、清理备份目录存在性核对。

## §8 报告落盘（21:15–22:10）

21:15 `first_round_notes.md`（读作者汇总前）；21:16–21:35 读作者汇总与历史文档；22:00 `feedback.md`；22:05 `evidence_index.md`；22:10 本日志与 `handoff_workbuddy_review.md`（项目根，会话交接用）。

## 失败与异常如实记录

- 两次 `--tmpdir/--out` 指定已存在目录导致测试 exit 1（FileExistsError）：查明为沙箱按命令行预建目录所致，非测试脚本缺陷；改用 tempfile 后全过。
- xsim 退出 0xC0000409：4 次独立复现（沙箱/非沙箱/中英文路径），内容完整正确；作者环境 rc=0；根因未定位。
- `git ls-remote` 不可用（无凭据）；GitHub 实时状态未复核。
