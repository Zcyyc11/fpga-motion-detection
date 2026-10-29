<!-- Hallmark pre-emit critique: P5 H5 E4 S5 R5 V4 -->
# 复现入口与版本

受测源码：`64ac44ee2a27897f674919d6fcb8e4fbbd8dfde8`。后续发布提交新增报告与证据，代码差异需以 Git 核对。不要在原证据目录重复执行会覆盖 CSV 的命令；下面所有输出目录必须是尚不存在的新目录。

## 本机环境

| 项目 | 本次使用 |
|---|---|
| Python | `<DRIVE>/666666/Anaconda/python.exe`；实际命令使用 UTF-8 和禁止 pyc 写入选项 |
| Vivado | `<DRIVE>/AMD2025.2/2025.2/Vivado`，2025.2 |
| 数据 | `<DRIVE>/cdnet2014_line3_20261010_1700/dataset`，选定 12 段 |
| 整合检出 | `<DRIVE>/line3_closeout_20261011_1000_work/integration` |
| HDL IP | `<DRIVE>/line3_closeout_20261011_1000_work/vivado-library`，SHA `f4613fff005b098065fd5d619a2b88e55720a423` |
| 原入口副本 | `<DRIVE>/line3_closeout_20261011_1000_work/native_v2` |
| 板级副本 | `<DRIVE>/line3_closeout_20261011_1000_work/board_integrated_mode0`、`board_integrated_mode1` |

这些是本次机器的实际位置，换机器应填写自己的路径。详细命令、工作目录、退出码与耗时见 `commands/*.json`。大体量 Vivado 工程与 checkpoint 保存在本地工作目录，未上传 GitHub。

## 原入口评分

本次实际使用 `native_reruns_v2.py`，它只复制原始 `.py` 文件、逐一直接启动 `cdnet_official.py`，没有替换数据加载器或评分函数。每个副本开始时没有旧 CSV，因此新结果不会与旧归档混淆。随后比较完整 6 个变体键及两个分数字符串。v3 仅纠正资源门槛估算，保留为后续复现参考，不能算本次重新执行。

在新的源码副本中，完整单段调用形如：

```powershell
& '<Python完整路径>' -I -B -X utf8 '<新副本>/src/ps/cdnet_official.py' --data-root '<数据目录>' --set r12 --seq badWeather/snowFall
```

snowFall 的原始 eager loader 约占 8 GB 私有内存；本次单独运行它，完成后才启动 Vivado。不要用 `--frames` 截短却称为完整原入口复跑。它的输出列 `official_f1` 仍使用项目历史标签语义，详见报告。

## 软件和 RTL 回归

从受测 SHA 的干净检出启动：

```powershell
$env:NoDefaultCurrentDirectoryInExePath = '1'
& '<Python完整路径>' -I -B -X utf8 '<仓库>/sim/line3/run_repair_regressions.py' --out '<新的ASCII输出目录>' --settings '<Vivado>/settings64.bat'
& '<Python完整路径>' -I -B -X utf8 '<仓库>/sim/line3/check_pc_receiver_extended.py' --out '<另一个新输出目录>'
```

回归入口会冻结 SHA，使用隔离副本，将需要模拟删除的测试夹具移到保留目录。本次没有删除原数据或历史结果。

## 板级构建

本次实际使用 `board_build_v2.py`，按 Git SHA 提取 RTL、XDC、Tcl 到全新 ASCII 目录。只把 jobs 从 8 降为 2，并取消 `create_project -force`；逐模式补丁、输入清单与依赖 SHA 已保留。它直接调用 Vivado 的 Tcl，不调用含递归清理语句的旧 `build_vivado.bat`。

复现时先准备新的源码副本和上述固定 SHA 的 Digilent 库，确认 `build/vivado` 尚不存在，再设置 `MOTION_IP_REPO` 为 IP 库根目录。进入该副本，执行 Vivado batch，指定 `build/scripts/build_vivado.tcl`，`-tclargs 0` 或 `-tclargs 1`。两个模式使用两个独立副本。实际命令可逐字查阅 `commands/board_integrated_mode0.json` 与 `commands/board_integrated_mode1.json`，仅替换本机路径。

检查 `EFFECTIVE_GENERIC=MODE_BG=0/1`、最终退出码、bitstream SHA256、实现报告、路由状态、未约束路径、DRC 和 methodology。不要仅以产生 `.bit` 或 WNS 为正认定整板通过。`board_diagnostics_v2.py` 对 routed checkpoint 再生成一轮只读诊断；命令及报告同样保留。

## 历史证据与失败

`prior_evidence/` 是上轮审计结果的逐字副本；本轮只重查文件完整性，没有把它标成新跑的 111,498 帧。当前新增原入口结果与它分别列出。v1 复跑驱动的变量名错误、v2 内存估算纠正及工具原始日志均保留。`.raw` 是原字节，`.txt` 是 UTF-8 文本，无法解码的工具字节被明确转义。
