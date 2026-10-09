# 验收边界修复：第一阶段

2026-10-09。基线 `452075f727aec0f9ca6fe9404a09ac0de4361795`，修复分支 `fix/verification-boundaries-20261009`。四项软件缺陷已修复；Vivado 运行器仍待第二阶段处理，本文件不代表整项任务交付完成。

## 改动与行为

| 问题 | 当前行为 |
| --- | --- |
| 引号路径后面的非法参数被漏报 | 完整读取引用值；支持 bash、cmd、PowerShell 续行；区分 shell 分隔符、注释和 Markdown 行内代码。引用值中的命令文字不作为第二条命令检查。 |
| `--frames` 超过 ROI 越界 | `frame_plan` 先确定 ROI 内最后一帧，再统一计算读取数量；0 为完整 ROI，正数为最多计分帧数；负值和非整数明确失败。 |
| 五步图标注目标帧与实际帧不一致 | 实际预热数量为 `target-first`；读取到目标帧为止。第 1 帧、零/负预热、负目标帧明确失败；目标 0 保留自动选择含义。 |
| 演示把预热帧计入成绩 | CSV 与图示只选 ROI 内且有前帧参考的计分帧；没有可计分帧时明确失败，不生成错误成绩。 |

`cdnet_demo --frames` 为保持兼容，仍表示最多读取帧数，包含参考帧和 ROI 前预热帧；0 表示读到 ROI 终点。它与 algo_lab、cdnet_official、algo_ab 的“最多计分帧数”不同。`--start 0` 从 ROI 起点读取，第一张只作参考；例如 ROI=3–10 时默认计分 4–10，`--start 1` 计分 3–10。显式超长读取始终截到 ROI 终点。

## 回归方式

在仓库根目录，使用已装 NumPy、OpenCV、Matplotlib 的 Python，输出路径必须在仓库外且尚不存在：

```powershell
python -X utf8 build/scripts/test_verification_boundaries.py --out ../new_verification_run --suite all
python -X utf8 build/scripts/check_doc_commands.py
python -X utf8 build/scripts/check_doc_commands.py --self-test
```

测试为每项新建源码副本与 12 帧、16×16 的构造数据。通过真实 `load_seq` 与 `metrics` 调用记录帧号和结果，不改变算法输出；缺文件通过移存模拟，全部数据保留，不删除文件。可用 `--repo` 指向旧版验证测试确实失败。

第一轮旧版 99 项中 49 项失败；修复版同组加五入口矩阵 139/139 通过。额外加入四项文档误报反例后，旧解析实现 23/27、修复后 27/27。最终扩展回归结果以 `report/verification_20261009/round1/green_final.json` 为准。

原 22 项数据守卫在源码副本中完整通过；删除调用改为移存，断言未削弱。四种真实绝对路径包含 `D:/666666/Temp/fpga_fix_paths_20261009_r1/uni/plain`，纯英文路径不在中文用户目录内；4 次运行及 CSV 一致性共 5 项通过。图像已解码；实际查看第 5 帧五步图、第 7 帧演示图，中文正常。

## Vivado 实验与未完成项

同一源码、Vivado 2025.2 的新实验：UTF-8 中文绝对路径文件列表，无论是否加引号，均在 xvlog 失败；ASCII 相对文件列表可在中文目录完成仿真。GBK 中文绝对文件列表也可完成，但依赖本机代码页，不宜据此声明通用支持。英文带空格路径在引用后完成。

Vivado 工具的路径文本含 GBK，testbench 的中文输出为 UTF-8；整份日志按一种编码读取会误判。保留了原始字节及逐行解码的 UTF-8 视图。所有成功实验 CSV 均为 0–10 共 11 条，`x_hits=0`；没有修改 DUT，也没有解决或宣称解决 12 帧完整性问题。

下一阶段必须实现可配置、每次独立、保留来源与日志的运行方案，并测试无效配置、编译失败、引擎未启动和 X 状态。`run_sim.py`、bat 及模板本阶段未改。

## 证据范围

完整新证据保留在外层项目 `repair_20261009_round1/`；精简结构化证据位于本仓库 `report/verification_20261009/round1/`。原 captain_repo、原 main、线三分支和历史验证目录未改；开工 Git bundle、源码 ZIP、原 handoff 备份及逐文件哈希均保留。未推送、未创建 PR、未合并 main、未发送队长消息。

这些是软件边界与构造数据结果，没有重新验证真实 CDnet 精度、0.737、板卡性能、综合资源或时序。最终仍需换手审阅。
