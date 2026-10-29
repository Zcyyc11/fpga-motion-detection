> 历史记录：本文描述当时版本与当时授权，不能作为整合分支的当前状态或执行指令。当前入口为仓库 README、docs/reproduce_line3.md 和 docs/line3_status_20261009.md。旧绝对路径可通过外层维护清单和完整备份追溯。

<!-- Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4; scope: evidence-based repair documentation. -->

# FPGA 验收修复交付说明

2026-10-09。本轮四项软件缺陷和 Vivado 运行器修复已完成本地验证。基线为 452075f727aec0f9ca6fe9404a09ac0de4361795，分支为 fix/verification-boundaries-20261009。修改位于隔离的 captain_fix_20261009。

**本轮通过的是软件边界与运行器检查。默认 RTL 仍只输出帧 0–10 共 11 条记录，要求 12 帧时明确失败。没有完成真实 CDnet 全量评测、板卡实测、综合资源或时序复核。**

## 修复了什么

| 问题 | 修改后的行为 | 回归证据 |
| --- | --- | --- |
| 引号值之后的错误参数漏报 | 完整读取引用值；支持 bash、cmd、PowerShell 续行；区分 shell 分隔符、注释、行内代码，保留反例标记 | 合法引号值后接非法参数，以及引用值、注释中的伪命令 |
| --frames 超过 ROI 越界 | 先截断最后一帧，再统一 first、nwarm、count、score；负值和非整数明确失败 | frames 为 0、少于、等于、大于 ROI，ROI 外有/无真值；核对计分帧集合 |
| five_steps 目标帧与图不一致 | 实际预热为 target-first，读取到请求目标即止 | 真实读取记录确认第 5 帧请求的末帧为 in000005.jpg；覆盖默认/短预热和晚目标 |
| cdnet_demo 把预热计入成绩 | 只统计 ROI 内且有前帧参考的帧，图示从计分范围选择 | 预热有/无真值、超长读取、无可计分帧，核对 CSV 和选图帧号 |
| Vivado 中文文件列表与证据不可靠 | 每次复制必要源码到新目录，使用带引号的 ASCII 相对文件列表，记录来源和本次结果 | 46 项构造回归和 7 项本机 Vivado 正反例检查 |

改动限于相关 Python 文件、仿真 bat 及模板、bat 行尾规则、测试与说明。没有修改 RTL/DUT 或冻结接口。编译错误和 X 反例只注入独立测试副本，修改前文件也保留。

## 参数口径

- algo_lab、cdnet_official、algo_ab 的 --frames 是**最多计分帧数**，0 表示完整 ROI。
- cdnet_demo 的 --frames 保留为**最多读取帧数**，含参考帧与 ROI 前预热；0 表示读到 ROI 终点，超长值会截断。
- cdnet_demo 的 --start 0 从 ROI 起点读取，第一张仅作参考。ROI=3–10 时默认 CSV 为 4–10；--start 1 则为 3–10。
- five_steps 的 --frame 0 保留自动选帧含义；第 1 帧、零/负预热、负目标帧明确失败，避免无前帧参考时错误出图。

## 本机启动命令

以下 PowerShell 命令从修复仓库启动。安装路径只用于本机示例，通用代码不写死路径。

    Set-Location '<DRIVE>/Users\孙伟博\Desktop\FPGA大赛资料\captain_fix_20261009'
    $env:PYTHONUTF8 = '1'
    $env:PYTHONIOENCODING = 'utf-8'
    $env:PYTHONDONTWRITEBYTECODE = '1'
    & '<DRIVE>/666666\Anaconda\python.exe' -X utf8 build/scripts/run_sim.py --vivado-settings '<DRIVE>/AMD2025.2\2025.2\Vivado\settings64.bat' --scratch-root '<DRIVE>/666666\Temp\fpga_sim_runs'

该命令检查仿真流程，每次新建 run_时间_随机后缀 目录，可重复运行，不覆盖旧结果。输出会明确提示帧完整性未检查，也不会声称模型一致性通过。

检查预期的第 0–11 帧：

    & '<DRIVE>/666666\Anaconda\python.exe' -X utf8 build/scripts/run_sim.py --vivado-settings '<DRIVE>/AMD2025.2\2025.2\Vivado\settings64.bat' --scratch-root '<DRIVE>/666666\Temp\fpga_sim_runs' --expect-frames 12

**当前源码下，这条命令应退出 2，并报告缺第 11 帧。** 不要改成预期 11 帧来宣称原本的 12 帧要求通过。--first-frame 可指定预期起点，必须与 --expect-frames 配合。

| 配置项 | 优先级从高到低 |
| --- | --- |
| Vivado settings | --vivado-settings → VIVADO_SETTINGS → XILINX_VIVADO/settings64.bat → 当前 PATH |
| 运行目录的父目录 | --scratch-root → SIM_SCRATCH_ROOT → 系统临时目录下的 fpga_sim |

scratch 必须在源码目录外。settings 不存在、scratch 指向文件、非法 top 等会明确失败。含百分号等 cmd 歧义字符的路径被拒绝；普通中文、英文和空格路径已实测。运行失败仍保留已创建的目录；在目录创建前发现配置错误时，控制台直接说明原因。

每次目录内保留：

- manifest.json：来源目录、Git 状态（若可用）、复制文件 SHA256、命令、settings 路径和哈希、创建时间。
- sim/logs/sim_run.raw：原始输出字节。
- sim/logs/sim_run.log：逐行解码后的 UTF-8 阅读版。
- sim/wave：本次 CSV、PPM 图；其他 Vivado 中间文件也留在本次目录。
- result.json：退出码、工具阶段、结束标记、X 检查、实际 CSV 帧号、完整性差异和产物哈希。

本机 Vivado 2025.2 的路径日志含 GBK，而 testbench 输出为 UTF-8；程序逐行先尝试 UTF-8，失败后严格尝试 GB18030。无法解码的行保留字节转义并使验收失败，不静默丢弃。该策略已覆盖本机日志，不能保证其他版本或系统代码页。

实测中文绝对路径写入 UTF-8 文件列表时，单纯加引号仍失败；相对 ASCII 列表可在中文运行目录完成。当前方案绕开绝对路径编码问题，没有宣称 Vivado 普遍支持任意中文路径。

sim/run_sim.bat 是内部步骤，直接启动退出 13，提示使用 Python 入口，避免覆盖工程旧结果。它由 build/scripts/fix_bat_eol.py 生成，ASCII/CRLF 已检查；.gitattributes 保证后续检出保持 CRLF。修改模板后先备份，再只生成仿真脚本：

    python -X utf8 build/scripts/fix_bat_eol.py --only sim

本轮没有运行完整硬件构建脚本，build_vivado.bat 保持原样。

## 实际验证结果

| 检查 | 结果和口径 |
| --- | --- |
| 四项软件缺陷旧版回归 | 初版 99 项中 49 项失败，四类缺陷均被捕获 |
| 软件最终回归 | 174/174，包含 40 项五入口数据矩阵、帧范围与文档边界 |
| 额外文档误报反例 | 旧解析实现 23/27，修复后 27/27 |
| 队长原数据守卫 | 22/22，断言保留，删除操作改为移存 |
| 四种数据绝对路径 | 4 次运行及 CSV 一致性共 5/5，纯英文根确实位于英文目录 |
| 运行器旧版回归 | 13/35；通过项含原本能检出的失败，22 项暴露缺口 |
| 直接 bat 保护回归 | 中间版 45/46，唯独直接入口保护失败；修复后最终 46/46 |
| 本机 Vivado 最终检查 | 7/7 符合预期：四种路径成功；12 帧不足、编译错误、X 注入三项正确失败 |
| 文档默认检查和自测 | 最终审计重新执行，检查器前后文件集合与哈希不变 |
| 图像 | 软件用例图可解码，已查看第 5 帧五步图、第 7 帧演示图，中文正常；Vivado PPM 另作解码检查 |

软件回归使用 12 帧、16×16 构造数据，验证程序行为，不能用于认定真实精度。运行器 46 项使用可控工具替身，检验真实 Python/bat 入口；RTL 实际执行由独立的 7 项 Vivado 检查证明。7/7 表示正反例符合预期，不表示 7 次仿真均成功。

本机 Python 3.13.5、NumPy 2.1.3、OpenCV 4.13.0、Matplotlib 3.10.0，未升级依赖。软件回归在第一阶段执行；最终审计核对其受测源码哈希未变，因此保留该证据，没有无理由重跑整批。

## 如何复跑

从修复仓库执行，输出路径必须尚不存在且位于仓库外；全部构造文件保留：

    python -X utf8 build/scripts/test_verification_boundaries.py --out ../verification_rerun_new --suite all
    python -X utf8 build/scripts/test_sim_runner.py --out ../runner_rerun_new
    python -X utf8 build/scripts/check_doc_commands.py
    python -X utf8 build/scripts/check_doc_commands.py --self-test

软件回归需要 NumPy、OpenCV、Matplotlib；运行器构造回归需要 Windows/Python，不需要 Vivado。--repo 可指向其他源码目录以复验旧版。

真实 Vivado 检查脚本为外层 repair_20261009_round1/verify_runner_live.py，接受 --repo、--out、--ascii-root、--settings；两个输出根须为新目录，英文根须为完整英文绝对路径。它只对源码副本注入故障。

## 证据和保护

- report/verification_20261009/round1：第一阶段结构化证据。
- report/verification_20261009/runner：运行器回归、真实 Vivado 来源清单、CSV 和原始/解码日志。
- 外层 repair_20261009_round1：完整构造数据、各轮失败及通过日志、源码副本和最终审计；英文 Vivado 测试保留在 <DRIVE>/666666/Temp/fpga_runner_live_20261009_final。
- vivado_probe1/results.json 是早期整份日志解码的失败尝试。正确路径实验见 checkpoint_checks/vivado_decoded.json；最终运行器见 runner_live_final/results.json。
- 开工备份为 captain_before.bundle、baseline_452075f.zip、protected_before.json；本阶段修改前文件位于 runner_before。
- 原 captain_repo 仍在 feat/line3-verification，提交 f6f6036ab44b4604897305d17d58cc71f8e089f7；main 保留 452075f727aec0f9ca6fe9404a09ac0de4361795，旧 main 备份分支也保留。
- 没有删除文件、推送、PR、合并 main 或替用户向队长发送消息。

可直接发给队长的文本见 docs/captain_feedback_20261009.txt。本地验证不能代替他人换手审阅。没有新证据支持确认 0.737、真实 CDnet 全量精度、板上性能、资源或时序，本轮没有对此重新下结论。
