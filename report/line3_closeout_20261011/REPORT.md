<!-- Hallmark pre-emit critique: P5 H5 E4 S5 R5 V4; scope: factual engineering report. -->
# 线三验证与分支交付报告

日期：2026-10-11。受测源码为 `64ac44ee2a27897f674919d6fcb8e4fbbd8dfde8`。本报告记录电脑端验证、现有板级工程的构建结果及未完成事项。分支交付不代表团队 main 已采用，也不代替负责人评审与实机验收。

## 本次解决了什么

1. 恢复 Git 访问。使用本机已经登录的凭据管理器，成功拉取仓库；没有读取或输出密码、令牌。旧匿名探针清空了凭据帮助程序，因此失败不能证明仓库不存在。
2. 补齐未改动原入口的独立复跑。新跑 9 段、54 项，重新核验此前 3 段、18 项；12 段、72 个唯一键及全部 CSV 值与历史参考一致。snowFall 完整 ROI 的 6 个变体退出码为 0，耗时 375.591 秒。输入加载与评分代码没有为省内存而替换。
3. 解决当前 main 与候选的两个脚本冲突。保留候选的隔离运行器、绝对批处理路径调用，以及 main 的路径可移植性改动。新提交同时修正板级 Tcl：原脚本只解析 MODE_BG，没有传给综合 fileset；现在校验 0/1 并设置 generic。
4. 获取并固定 Digilent rgb2dvi 1.4 的源码依赖，独立构建两种背景模式。IP 仓库 SHA 为 `f4613fff005b098065fd5d619a2b88e55720a423`，来源为 [Digilent vivado-library](https://github.com/Digilent/vivado-library)。依赖保存在仓库外，不把第三方源码提交进团队仓库。

## 评分证据与适用范围

| 项目 | 结果 | 证据 |
|---|---|---|
| 未包装原入口，完整序列 | 12 段 × 6 变体，72/72 一致 | [汇总](native_verified_summary.json)、[CSV](native_all72.csv) |
| 先前独立逐帧审计 | 111,498 个帧×变体记录；本次重查 gzip 完整性与行数 | [逐帧文件](prior_evidence/complete_per_frame.csv.gz)、[本次核验](historical_score_file_rechecked.json) |
| V43 历史标签规则均值 | 0.7367178962 | [两套评分汇总](prior_evidence/score_summary.json) |
| V43 按发布 MATLAB 标签公式重算 | 0.7205314165 | 同上；未宣称执行官方 MATLAB 程序或网站认证 |

两套均值都是选定 12 段、7 类的子集结果。历史代码排除了 50/85/170；发布 MATLAB 标签公式把 50 作为负类。原 CSV 中 `official_f1` 是历史列名，不能因此把数值称为官方成绩。traffic 的 ROI 尺寸与视频不一致仍保留为已知限制，没有擅自缩放。原入口每段生成的类别均值也不等于全子集均值，本报告使用完整汇总。

## 合并后软件与 RTL 验证

整合提交的完整回归 **12/12** 通过，运行器 **46/46**、边界 **174/174**，默认 RTL 帧号严格为 **0—11**。回归在 `NoDefaultCurrentDirectoryInExePath=1` 下运行，冻结检出结束时干净。接收端新增语义检查 **15/15** 通过；其数据源是模拟输入，`board_test=false`。见 [整合回归](integrated_regression_summary.json)、[子任务记录](integrated_regression/jobs.json)、[接收端检查](integrated_receiver_extended.json)。

核对了合并前后的数值函数 AST 与 RTL 文件：评分、帧加载的指定关键函数没有变化，RTL 与 `dc9f05f` 逐文件一致。详见 [范围核对](integration_algorithm_scope.json)。这项源码等价检查不冒充在新提交上重新计算全部分数。

原候选包含 bbox 帧首样本保留、16 位计数饱和，以及仿真运行器批处理绝对路径调用。大于 65,535 的计数不再表示精确面积。morph3x3 边缘裁剪与 bbox 计数语义仍需 RTL/算法负责人审阅。

## 布局布线结果

工具：Vivado 2025.2；器件：xc7z020clg400-1；顶层：board_top；外部时钟 125 MHz；像素时钟 74.25 MHz。输入是内部测试图案，顶层包含 HDMI 输出，未接 HDMI 输入。两个模式在新的 ASCII 路径下分别从源码构建；只把运行并行数从 8 改为 2，并移除新建工程的强制覆盖参数，补丁保留于证据目录。

| MODE_BG | 退出码 | WNS(ns) | WHS(ns) | TNS/THS(ns) | LUT | FF | BRAM | DSP |
|---|---:|---:|---:|---|---:|---:|---:|---:|
| 0 | 0 | 0.780 | 0.037 | 0.000 / 0.000 | 10206 | 5981 | 80 | 1 |
| 1 | 0 | 0.733 | 0.098 | 0.000 / 0.000 | 10226 | 5981 | 80 | 1 |

[汇总与 bitstream 哈希](board_verified_summary.json)；[模式 0 诊断](board_mode0/diagnostics/check_timing.rpt)；[模式 1 诊断](board_mode1/diagnostics/check_timing.rpt)。

以上为布局布线后的报告，不是此前的 OOC 综合估计。约束中仍有 7 个无输出延时端口：`hdmi_tx_clk_p`、`hdmi_tx_d_p[0..2]`、`led[1..3]`。LED 与 TMDS 的外部时序需要按各自电路解释，不能套用猜测的延时数字来消除警告。内部无时钟端点和未约束内部端点检查见原始报告。

- 模式 0 的 DRC 报告项：CHECK-3=1, DPIP-1=2, DPOP-1=1, DPOP-2=1, DPOR-1=18, REQP-1839=20, ZPS7-1=1；methodology：DPIR-1=30, LUTAR-1=3, SYNTH-6=40, XDCB-5=1。
- 模式 1 的 DRC 报告项：CHECK-3=1, DPIP-1=2, DPOP-1=1, DPOP-2=1, DPOR-1=18, REQP-1839=20, ZPS7-1=1；methodology：DPIR-1=30, LUTAR-1=3, SYNTH-6=40, XDCB-5=1。

这些数量是报告列出的检查项；REQP-1839 达到了每条规则的显示上限，不能把 20 当作全部实例数。没有擅自压低警告级别、添加虚假例外或修改负责人 RTL。

即便生成 bitstream、受约束路径余量为正，也没有证明上板画面、真实输入、帧率、延迟或长时间稳定性。bitstream 以 SHA256 绑定到本次构建，保存本地，未下载到板卡。

## GitHub 与交付状态

初始只读核验：main 为 `f50d5f0c5958f049ad43e31e916199c75696d0f1`，现有审查分支和 PR #1 head 为 `b4bf9300ac7f499f0c1c72ed3ef28317066f49a5`。main 比审查分支多 2 个提交，审查分支多 14 个提交。整合提交有两个父节点：原候选 `dc9f05f` 和 main `f50d5f0`。

用户已明确授权“github提交到分支就行，跟昨天一样”。交付目标为 `codex/line3-delivery-20261011`；不强推、不修改 main、不修改已有 PR。实际发布提交及核对结果见交付回执。受测源码 SHA 与包含报告的最终发布 SHA 分开记录。

GitHub 应用已连接 PRICELESSymbol，但安装范围只包含该账户，读取 Zcyyc11 仓库及 PR 元数据仍返回 404。Git 代码访问正常；PR draft、正文、评审状态和 API 权限级别未核实。现有 PR 的代码 head 已通过 Git refs 核实，不能据此推断它的开放或草稿状态。

## 尚需完成的事项

| 事项 | 当前证据与下一步 |
|---|---|
| 真实板端回传 | 尚缺双方确认的封包协议、连接参数、发送程序、真实样例和抓包；收到后线三适配接收端并核对帧号、坐标、丢包与画面。 |
| 实机与完整视频链 | 本次只有内部图案到 HDMI 输出的构建；HDMI 输入、运行时参数控制、实测帧率/延迟和稳定性仍需板端支持。 |
| 时序与 DRC 审阅 | 外部输出约束与异步复位/BRAM 警告需硬件负责人判断，不能只看 WNS。线三已提供 routed 报告、checkpoint 位置及诊断。 |
| 负责人评审 | morph3x3 边缘契约、bbox 饱和语义、资源代价和采用版本需他人审阅；没有代签通过。 |
| GitHub 应用授权 | 如需读取和更新现有 PR 元数据，仓库所有者需将目标仓库加入应用授权范围；分支推送使用已经可用的 Git 通道。 |

线三已自行处理访问排障、原入口复跑、冲突整合、构建参数修复、依赖准备、布局布线、软件/RTL 回归、报告和分支交付准备，没有把这些工作归给队友。可转交的详细输入清单见 [队友资料清单](teammate_inputs.md)。

## 失败、原件与证据保护

首次复跑驱动有变量名错误，尚未启动模型即退出；原脚本和错误记录保留，实际执行的是 v2。snowFall 的初始内存估算漏计 uint64 压缩缓存，已补纠正记录；实际进程顺利完成，没有截断帧或替换加载器。Vivado 原日志存在工具输出的非 UTF-8 字节，原始 `.raw` 保留，文本副本将无法解码字节转义；正式中文报告以 UTF-8 校验。

原 captain_repo、Claude 与 Astra 审计目录按逐文件 SHA256 检查。外层队友清单在本任务期间被其他操作移除，另出现硬件连接说明；本任务没有恢复、删除或提交这些外部改动。这里的清单副本从已保存的 `e2a47a3` 提取，来源可查。

本次保护清单覆盖 **11473 个文件**，新增、删除、改动均为 0。见 [散列比较](protected_comparison.json)。
