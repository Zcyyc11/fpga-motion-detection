# Skill 4 · 资源与时序数据自动采集并生成报告表

## 适用范围

- **什么条件下能用**：任何 Vivado 工程，且能**批处理**（`-mode batch`）跑通综合与实现；
  面向"**可复现构建脚本 + 资源/时序报告**"这一对交付物。
- **解决什么问题**：把"点 GUI 看报告、手抄数字"变成"**一条命令跑完，七份报告自动落到固定位置，
  时序不收敛就自动判失败**"。既满足官方的可复现要求，也避免没收敛的 bit 悄悄流到上板那一步。

## 使用方法

```bat
build\scripts\build_vivado.bat 0        :: 参数 MODE_BG：0=帧差(v1) / 1=背景建模(v2)
```

脚本做四件事：建工程 → 引入 IP → 加 RTL/约束 → 综合实现出 bit，并在末尾自动采集报告。

| 产物 | 位置 |
|---|---|
| 7 份报告 | `build/reports/`：`synth_utilization` / `synth_timing_summary` / `synth_clocks` / `impl_utilization` / `impl_timing_summary` / `impl_clock_interaction` / `impl_drc` |
| bitstream | `build/bitstream/board_top.bit`（从 `.runs/impl_1/` **拷贝**出来，不留在会被清掉的工作目录） |
| 时序门 | 脚本末尾读 WNS/WHS，**任一为负 → `exit 1`** |

**判读顺序（照这个顺序看，不要跳）**：

1. `impl_timing_summary.rpt` → 看 `Design Timing Summary` 的 **WNS / WHS / TNS / THS 失败端点数**
2. `impl_utilization.rpt` → LUT / Register / Block RAM / DSP
3. `impl_drc.rpt` → 有没有 **ERROR**（Warning 分类看待）

- **关键参数说明**：
  - `MODE_BG`：0 = 帧差法，1 = 背景建模，同一份源码两种模式
  - **IP 仓库路径取环境变量 `MOTION_IP_REPO`**，脚本内不硬编码绝对路径 → 换机器只改环境变量
  - 工程路径与用户名**不能含中文**（Vivado 限制），故工程建在非中文路径下

## 已验证的效果

- **测试环境**：Vivado 2026.1（win64）/ 器件 `xc7z020clg400-1`（PYNQ-Z2 上的 XC7Z020-1CLG400C）
- **结果（v2，含激励回绕修复，18:02 exit 0）**：
  | 指标 | 实测 |
  |---|---|
  | 时序（**impl**） | **WNS = +0.695 ns / WHS = +0.076 ns，0 失败端点**，报告原文 "All user specified timing constraints are met." |
  | Slice LUT | 10237 / 53200 = 19.24% |
  | Slice Register | 5979 / 106400 = 5.62% |
  | Block RAM Tile | 80 / 140 = **57.14%** |
  | DSP | 1 / 220 = 0.45% |
  | DRC | **44 条 Warning、0 Error** |
  | 耗时 | 首轮整条 tcl **29 分 46 秒**（综合 9m15s，峰值内存 2.27 GB）；**第二轮只 14 分钟**（IP 综合有缓存） |
- **证据文件**：`build/reports/` 七份 + `build/bitstream/board_top.bit`；`build/logs/` 构建主日志

## 从哪些失败或观察中总结得出

1. **现象**：脚本跑 10 分钟日志一个字没长，进程还活着 —— 只占 **15 MB** 内存、
   窗口标题 **`OLEChannelWnd`**、CPU 时间**十分钟一动不动**。
   **原因**：Vivado 自己的 `file delete -force` 碰到残留文件句柄时**弹出一个隐藏的模态对话框**，
   batch 模式没人能点 → 永久等待。
   **结论**：① 工程目录清理**交给外层 `.bat` 的原生 `rmdir /s /q`**，Vivado 里一行删除都不留
   （对照实验：同一棵目录树 OS 原生删只要 ~2 秒）；
   ② 通用判据 —— **"进程活着但 CPU 时间不动"＝假死**，用两次间隔采样 `tasklist /v` 看 CPU 时间即可一眼认出；
   ③ **别让 EDA 工具在 batch 模式下做可能弹窗的操作**（删除/覆盖/许可证提示）。
2. **现象**：脚本刚开始就退出，抛 `ERROR [Common 17-53] No open project`。
   **原因**：batch 模式下此刻没有打开的工程，而 `close_project` 会抛 ERROR，
   **`catch` 也拦不住**，直接终止 Vivado。
   **结论**：batch 脚本里**不要调 `close_project`**。
3. **现象**：bitstream 生成完却"找不到"了。
   **原因**：`write_bitstream` 的产物默认落在 `.runs/impl_1/`，而该目录
   **下次构建开头就被 rmdir 清掉**，而且在 `.gitignore` 里。
   **结论**：tcl 末尾**自动 `file copy` 到一个不会被清掉的交付目录**（`build/bitstream/`），
   并在 `.gitignore` 里用 `!build/bitstream/**` 显式放行。
4. **★ 现象**：`synth_timing_summary.rpt` 报 **WHS = −0.466、8 个 hold 失败端点**，
   报告写着 **"Timing constraints are not met"**；但同一次构建最终 exit 0、impl 报告是 **"+0.076"**。
   **原因**：那些失败端点全在**跨 IP 内部时钟域的路径**上（`clk_pix_raw → PixelClkIO`，
   即 HDMI 发送 IP 内部时钟生成到 OSERDES 复位端）—— 综合阶段没有真实布线延迟，估计偏悲观，
   布局布线后自然收敛。
   **结论**：**判时序只认 `impl_timing_summary.rpt`**（看 `Design State : Routed`）；
   时序门**必须放在实现之后**读，不能放在综合之后 —— 否则会把一个其实已收敛的设计误判成失败。
5. **现象**：构建里连着报两类 ERROR，一次一条。
   **原因**：① 清理由 Vivado 做（见第 1 条）② IP 端口名写错（见技能包第 5 项第 7 条）。
   **结论**：**把"能自动判失败的东西"全部交给脚本** —— 综合失败、实现失败、bit 不存在、时序不收敛，
   四条各自 `exit 1` 并打印对应日志路径。这样跑完一次就知道要不要往下走，不必人肉翻日志。

## 失效条件

- **层次化 / Block Design 流程**下报告文件名与路径不同，本脚本面向"**纯 RTL + 少量 IP**"，需改写。
- **若设计本来就有真实的 hold 违规**（不是 IP 内部跨域），实现阶段同样会报负 WHS；
  此时**不能**用"综合的负值是实现前的悲观估计"去解释 —— 必须看 impl 报告的**失败端点数**是否为 0。
- **没有把 `settings64.bat` 先 call 起来**时，`xsim` 会以 `0xC0000135` 失败（缺 DLL）；
  本脚本管的是综合实现，仿真入口 `sim/run_sim.bat` 须自己先 call。
- **已知未覆盖的边界**：未采集功耗报告；未涉及多时钟域自定义约束
  （本设计尚未接入 HDMI 输入，输入侧时钟域未纳入）。
