# HDMI 输出黑屏问题定位报告（2026-10-19）

> 问题：16 目标重构版候选 bit 上板，采集卡全黑、电脑读不到 EDID。
> 结论：**源码无罪，根因是候选 bit 的构建环境与已验证环境不一致**。
> 证据链：A/B 对照 + 静态六连排除 + 本机同环境重建复现，全部实测可查。

## 1. 现象

- 候选包 bit（`board_top.bit`，SHA256 `67BBE9A1…793AF3`，RTL 冻结 02fce44，源码 34f18d9）JTAG 烧录成功。
- 采集卡（UGREEN 25854）能打开、能协商 1280×720 YUY2、5 帧全读到，但**首帧平均亮度 0.0（全黑）**。
- Windows 显示器列表里板子 EDID 存档 "Generic Monitor (DGL 720P CEA)" 状态 **Unknown**（读不到 EDID）；Win+P 选"仅第二屏幕"自动弹回。
- 同环境下旧 bit（`board_top_hdmiin.bit`，SHA256 `9F506BEF4132…`，10-12 实测 PASS 版）一切正常：亮度 129.1、红框+实时画面。

## 2. 排除过程（从最便宜的证据开始）

| # | 检查项 | 方法 | 结果 |
|---|---|---|---|
| 1 | 电脑侧/软件环境 | motion venv（cv2 4.12.0，10-12 原班环境）复跑探测脚本 | 同样全黑 → 软件侧洗清 |
| 2 | 采集卡/USB 链路 | 设备枚举、格式协商、帧读取 | 全通 → 采集卡洗清 |
| 3 | **A/B 对照** | 同电脑、同采集卡、同线、同环境，只换 bit | 新版 0.0 全黑 / 旧版 129.1 出画面 → **差异锁定在 bit** |
| 4 | RTL 全量对比 | 新旧源码逐文件 SHA256 | 仅 5 文件不同（alarm/axi_lite_slave/multi_bbox/track/uart_tx）；**视频进出链路（board_top/hdmi_in_ctrl/md_pipeline/overlay/downsample2x2/gray_conv）逐字节相同** |
| 5 | EDID 配置 | 新旧 `create_dvi2rgb.tcl` 对比 | 一字不差（kEmulateDDC=true、kEdidFileName=dgl_720p_cea.data 等） |
| 6 | 顶层例化 | 新旧 `board_top.v` 逐字节对比 | 完全相同（dvi2rgb_0 例化一致；aPixelClkLckd 悬空为新旧共有状态，非回归点） |
| 7 | 时钟约束 | 新旧 `impl_clock_interaction.rpt` 对比 | 逐行一致，PixelClk 均 Clean |
| 8 | DRC | 新版 `impl_drc.rpt` | 65 项全 Warning，零 Error/Critical，无 HDMI/DDC/引脚类问题 |
| 9 | 资源 | 新旧 `impl_utilization.rpt` | LUT 12798→17475；**LUT as Memory 24→288（+264≈16.5kbit，疑 track 重构将 sf_reg 数组移入分布式 RAM，建议线二自查上电行为）**；BRAM 80→85.5 |

## 3. 判决实验（本机同环境重建）

用候选包**同款源码（34f18d9）**，在**旧 bit 的同款环境**（Vivado 2026.1 + 本机 IP 仓库 `<WORKSPACE>\libs\vivado-library`）重建：

- 构建产物：`<WORKSPACE>\rebuild_20261019\build\bitstream\board_top.bit`
- 构建结果：WNS(setup) +0.237ns / WHS(hold) +0.013ns，0 Errors、0 Critical Warnings
- 上板实测：**亮度 27.6，实时画面正常，输入输出链路全通**

## 4. 三方对照（同电脑/同采集卡/同线/同软件环境）

| bit | 构建环境 | 探测亮度 |
|---|---|---|
| 候选包原版 bit | 线三机器：Vivado **2025.2** + IP 仓库 `<LINE3_WORK>/vivado-library` | **0.0 全黑** |
| 本机重建 bit | 本机：Vivado **2026.1** + IP 仓库 `<WORKSPACE>\libs\vivado-library` | **27.6 画面正常** |
| 旧验证 bit（10-12） | 本机：同左 | 129.1 |

## 5. 根因与修复指引

**根因**：同一份源码，在候选包的构建环境（Vivado 2025.2 + 线三机器的 IP 仓库快照）下生成的 bit，其 HDMI 输入侧行为与已验证环境（2026.1 + 本机 IP 仓库）不一致——电脑读不到 EDID（DGL 720P CEA 状态 Unknown）→ 不按 720p 首选时序输出 → 整条链黑屏。静态报告（RTL/时钟/DRC）全部一致，**差异在生成产物的运行时行为**，EDID/DDC 类初始化数据是最可能的中招点。

**修复（二选一）**：

1. 线三改用 **Vivado 2026.1** 构建，并确保 IP 仓库与本机 `<WORKSPACE>\libs\vivado-library` 为同一快照（建议直接拷贝该目录使用），重建后重测；
2. 或直接采用本机重建产物（同源码 34f18d9，构建日志见 `<WORKSPACE>\output\rebuild_console.txt`），其 WNS +0.237ns、资源与时序均过闸。

**教训固化**：仿真过 ≠ 能上板；静态报告一致 ≠ 生成产物行为一致。新版 bit 首次上板必须与旧验证版做 A/B 对照。

## 6. 证据文件索引（本机可查）

- 探测日志（含新旧两次结果）：`<WORKSPACE>\output\cap_probe.log`
- 新旧首帧图：`<WORKSPACE>\output\probe_dev0_DSHOW_f0.png`（覆盖保存，以 log 时间戳区分）
- A/B 烧录日志：`<WORKSPACE>\output\burn_ab.log`、`burn_ab2.log`
- 本机重建构建日志：`<WORKSPACE>\output\rebuild_console.txt`
- 静态对比：`<WORKSPACE>\output\rtl_diff.txt`、`boardtop_ip_diff.txt`、`edid_bit_compare.txt`
- 重建工程：`<WORKSPACE>\rebuild_20261019\`（可用 `<WORKSPACE>\output\ila_probe.tcl` 插探针深挖）
- 硬件扫描：`<WORKSPACE>\output\hw_scan.txt`

## 7. 当前状态

- 板子上现烧本机重建 bit（16 目标版，功能链路已通），可继续进行六场景验收采集。
- 待办：线三确认并修复构建环境后交付正式版；仓库 private→public（截止 2026-11-04 18:00 前必须）。
