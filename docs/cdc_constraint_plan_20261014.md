# CDC 约束审计与方案（2026-10-14）

> 状态：**方案已定，未落地**。落地前置条件：本轮分阶段构建收工 → 在综合后设计上跑
> `report_clock_interaction` + `report_methodology` 验证本文件第 3 节的拓扑判断 →
> 定稿 `board/pynq_z2_cdc.xdc` → 加入 build_vivado.tcl 的 constrs_1 → 下一轮 impl 对比计时。
> 目的：给 route 阶段减负（消除对不可收敛的跨时钟域路径的无用分析），压缩 impl 时间。

## 1. 为什么做（依据）

- 本仓 xdc 现状（2026-10-14 grep 实证）：只有两个 `create_clock`（sys_clk 8ns /
  hdmi_rx_clk_p 13.468ns），**零** `set_false_path` / `set_clock_groups` /
  `set_max_delay` / `set_input_delay` / `set_output_delay`。
- 社区实测案例：补 CDC 约束后需收敛路径减约四成，编译时间显著下降（有 1-2h → 十几分钟案例）；
  AMD 官方文章（adaptivesupport 794116）给出 clock interaction 报告判读与约束四场景。
- 本项目时钟域多（125M 系统 / 74.25M 像素 / 200M RefClk / rgb2dvi 内部 5x 串行），
  不声明异步关系，工具会按同步路径分析跨域路径——那些路径物理上跨得远、逻辑埋得深，
  本就不可收敛，工具反复"救"它们就是在烧时间。

## 2. 设计时钟拓扑（读 board_top.v 全文实证，2026-10-14）

| 时钟 | 来源 | 驱动对象（INPUT_SEL=1） |
|---|---|---|
| sys_clk 125MHz | 板载 H16 | rst_cnt 上电计数、clock_74m25 MMCM、clock_200m MMCM |
| clk_200m 200MHz | clock_200m MMCM | dvi2rgb 的 RefClk（IDELAYCTRL 参考 + DDC I2C 逻辑） |
| pixel_clk_rx 74.25MHz | dvi2rgb TMDS 时钟恢复 | **整条视频数据链**：hdmi_in_ctrl / gray_conv / md_pipeline（含 uart_tx）/ rgb2dvi PixelClk / por 复位 / 心跳 LED |
| rgb2dvi 串行时钟 5x | rgb2dvi 内部 MMCM | IP 内部 OSERDESE3（OOC 综合，顶层不可见） |

**关键结论：INPUT_SEL=1 下用户数据链是单时钟域（74.25MHz）**，board_top 头注释
明确记录这是刻意设计（避免两个 74.25 混用）。所以 CDC 约束不涉及任何"屏蔽真实
数据路径"的风险场景（社区翻车案例都是无脑 false_path 屏蔽了真有握手数据的路径）。

## 3. 跨时钟域路径清单与处置

| # | 路径 | 性质 | 处置 |
|---|---|---|---|
| 1 | sys_clk(125M) → pixel_clk_rx(74.25M) | mmcm_rst 到两颗 MMCM 的输入缓冲；rst_n 实际由 PixelClk 域的 por/locked_sel 生成（pLocked 文档明确"断言同步于 PixelClk"），**不构成数据流** | `set_clock_groups -asynchronous` 一组解决 |
| 2 | clk_200m(200M) ↔ pixel_clk_rx | DDC I2C 在 dvi2rgb IP 内部，RefClk 域；IP 为 OOC 综合，跨域由 IP 内部处理 | clk_200m 补 `create_clock`（顶层现在完全没约束它），跨域关系随 IP 边界，验证后决定是否显式异步组 |
| 3 | pixel_clk_rx → rgb2dvi 串行时钟 | IP 内部 MMCM 生成，OOC 已综合，顶层 xdc 拿不到该时钟 | 不动（OOC 边界由 IP dcp 保证） |
| 4 | PixelClk 域内 uart_tx 波特率路径（74.25M/115200≈644.5 分频） | 域内多周期路径，非 CDC | 可选：`set_multicycle_path`（清报告噪声，省少量分析时间）——低优先级 |
| 5 | clk_pix(74.25 MMCM) | INPUT_SEL=1 时 clk_pipe 参数化退化为直连 pixel_clk_rx，clk_pix 无负载（MMCM 整体被优化或空转） | 无需约束 |

## 4. xdc 草稿（待第 1 节验证步骤通过后定稿）

```tcl
# ---- CDC / 时钟交互约束（草稿 v1，2026-10-14，未经 report_clock_interaction 验证）----
# 200MHz RefClk：dvi2rgb 规格要求，供 IDELAYCTRL 参考与 DDC。
create_clock -name clk_200m -period 5.0 [get_ports clk_200m]  ;# 位置以综合后实际 net 名为准，验证时校正

# 125M 系统域与 74.25M 像素域异步：两者间无用户数据流（见审计第 3 节路径 1）。
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk_pin] \
    -group [get_clocks pixel_clk_rx_rep]   ;# pixel_clk_rx 的实际时钟名以 report_clocks 为准（dvi2rgb 输出的恢复时钟，可能不带 rep）

# uart 波特率生成路径为域内多周期（74.25M/115200），二周期松弛（可选，低优先级）：
# set_multicycle_path 2 -setup  -from [get_cells -hier *uart_tx*] -to [get_cells -hier *uart_tx*]
# set_multicycle_path 1 -hold   -from [get_cells -hier *uart_tx*] -to [get_cells -hier *uart_tx*]
```

注：`get_ports clk_200m` / 时钟名必须以综合后 `report_clocks` 实际输出校正——本文件所有
`get_clocks` 参数在验证步骤中逐条核对后才允许进工程。宁保守勿错禁（错禁一条真实路径
比不约束更糟，社区有因此调试两周的案例）。

## 5. 验证与落地流程（构建收工后执行）

1. 本轮构建收工拿到 bit 后，`open_run impl_1`，跑：
   - `report_clock_interaction`（看 Clock Pair Classification / Inter-Clock Constraints 列，
     官方判据：Timed (unsafe) / No Common Period → 应作异步处理）
   - `report_methodology`（看 TIMING-6/7/8/13 类 CDC 违令）
   - `report_clocks`（拿真实时钟名，校正第 4 节草稿）
2. 拓扑与本文一致 → 定稿 `board/pynq_z2_cdc.xdc`，build_vivado.tcl 的 constrs_1 加入该文件
3. 跑一轮 impl（分阶段任务 `build_vivado.bat 0 1 impl`，工程复用不重建），与本轮 impl 计时对比
4. 结果记入本文档；若 impl 时间降幅 >20%，此 xdc 成为标准配置；若无变化，记录结论并回滚

## 6. 其他构建加速手段（本日调研结论，另见 docs/improvement_checklist_20261014.md）

- 已落地：8 线程（日志实证 maximum of 7 processes）、工程复用（跳过 IP 生成）、
  RuntimeOptimized 指令、分阶段 + checkpoint 续跑、任务计划程序脱离会话防连坐
- 待评估：WSL2/Linux 构建环境（社区实测同工程快 20-55%，比赛密集迭代期启用）、
  正式增量编译（impl 收敛后小改只重改动块，官方 UG904）
- 明确排除：IDR（官方明示 3.5-5 倍编译时间，是时序收敛手段非提速手段）；
  >8 线程（多来源实测负优化）
