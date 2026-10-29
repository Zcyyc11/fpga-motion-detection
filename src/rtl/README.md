# src/rtl/ — 自研 RTL

**分层**：
- `*.v`（本目录）＝**设备无关的算法流水线**，仿真与综合都用
- `board/*.v`（子目录）＝**板级外壳**（时钟、IO），只综合不仿真
  （它实例化 MMCME2_BASE / BUFG / rgb2dvi 这些只在 Vivado 工程流程里存在的原语与 IP，
   xsim 直接编译会因缺库报错，所以必须分层）

**命名约定**：小写 + 下划线。每个模块的头部注释写清「它在整机里是哪一环、为什么需要它」。

## 模块清单（与代码同步维护）

| 文件 | 五步链位置 | 功能 |
|---|---|---|
| `video_timing.v` | ① 时序 | 产生 hs/vs/de 与像素坐标 x,y；`SYNC_POS` 决定同步极性（720p 用 1=正极性） |
| `pattern_gen.v` | ② 激励 | 复刻 `data/golden/make_test_clip.py` 的合成片段（黑底白矩形、每帧右移 DX） |
| `downsample2x2.v` | ③ 压缩 | 8bit 像素 2×2 **求和** → 10bit 大像素（640×360×10bit ≈ 64 块 BRAM36，720p 整帧放不下 BRAM 的解法） |
| `frame_buf.v` | ④ 缓存 | 1 张「大像素图」；帧差模式存上一帧、背景模式存背景图，两者行为相同（读旧写新） |
| `diff_stage.v` | ⑤ **差分** | `|I − 缓存|`；**唯一与参考作品 #1 不同的一步**。背景模式另算 `B ← B + (I−B)/2^SHIFT` |
| `threshold.v` | ⑥ 阈值 | `absdiff > 70`（照抄 #1 硬编码值，**2×2 和域**，≈单像素 17.5 灰阶） |
| `morph_open.v` | ⑦ 形态学 | 开运算 = 腐蚀 → 膨胀（两级 `morph3x3` 串联） |
| `morph3x3.v` | ⑦ 形态学 | 3×3 单步腐蚀/膨胀；零扩展、居中锚点、每帧独立 |
| `bbox.v` | ⑧ 包围盒 | 全局并集框 x1/y1/x2/y2 + 面积门限（**历史单框实现，顶层已由 multi_bbox 替代**） |
| `multi_bbox.v` | ⑧+ 多目标 | **线二**：游程 + 并查集的多目标连通域，每目标一个框（I3 格式逐个输出）；**已接顶层**（md_pipeline L244），仿真见 `sim/tb/tb_multi_bbox.v` |
| `overlay_multi.v` | ⑨' 多框叠加 | **线一**：双缓冲目标表（≤16 目标）逐像素画多框 + 状态灯 + `b_obj_count`；已接顶层（md_pipeline L260） |
| `bbox_snapshot.v` | 寄存器 | **线二**：bbox 快照 + 帧号同拍锁存 + 四段握手 CDC（像素钟→AXI 钟，防撕裂）；**INCLUDE_PS=1 时生效**（0 时被综合优化掉） |
| `gray_conv.v` | ②' 灰度 | 实际文件在 **`board/gray_conv.v`**（线一，BT.601 77/150/29 组合逻辑，已上板验证）；线二新版（两级流水）存 `src/rtl_pending/gray_conv_line2.v` 备用，**不在构建 glob 内**，勿与 board 版同名共存 |
| `track.v` | ⑩ 跟踪 | **线二**：帧间贪心最近邻匹配 + 跨帧持续 id + dwell 停留计数；输入/输出均为 I3 目标流，`frame_tick`（vsync）驱动，零目标帧也须给 tick，仿真见 `sim/tb/tb_track_alarm.v` |
| `alarm.v` | ⑪ 告警 | **线二**：越界（中心穿越 LINE_X，穿越优先）+ 停留（dwell 达 DWELL）告警事件流，LINE_X/DWELL 为运行时参数（接 `regs.v` 寄存器堆） |
| `regs.v` | 寄存器 | **线二**：I4 寄存器堆落地——THRESH/THRESH_REL/ALPHA_SHIFT/LINE_X/DWELL/ENABLE 可写、STATUS 只读；PS 总线极瘦（en/we/addr/wdata/rdata），挂 AXI-Lite 只改外壳 |
| `uart_tx.v` | 回传 | **线二**：板→PC UART 发送（115200 8N1），协议 v0.2：帧头包 0x5A + 目标包 0xA5 + 事件包 0xC3，小端累加和校验；一帧滞后发射（commit 水位保证头包先于目标包）。**板测验收接收端统一用 `sim/line3/uart_receiver.py`（线三严格版）；`src/ps/uart_recv.py` 仅最小参考** |
| `overlay.v` | ⑨ 叠加 | 把包围盒画回画面（红框）+ 左上角状态灯（绿=检出） |
| `md_pipeline.v` | 整机 | 把①~⑨串成一条流水线，输出视频 + 包围盒 + 掩码探针 |

## 板级（`board/`）

| 文件 | 功能 |
|---|---|
| `board_top.v` | 板级顶层：HDMI 输入（dvi2rgb@J10）→ `hdmi_in_ctrl` → `gray_conv` → `md_pipeline`（含 multi_bbox/track/alarm/uart_tx）→ `rgb2dvi` → HDMI J11；自测模式走 pattern_gen；`uart_txd` → PMOD A ja[0]（Y18） |
| `clock_74m25.v` | MMCME2_BASE 参数：`M=37.125 / Dv=4 / D0=15.625` → 像素时钟**精确** 74.25 MHz（VCO 1160.16 MHz）。参数由 `build/scripts/mmcm_search.py` 解出，不是估的 |
| `clock_200m.v` | dvi2rgb RefClk 200 MHz |
| `hdmi_in_ctrl.v` | HDMI 输入控制：补 x/y 坐标、帧首 sof、无信号黑屏兜底（**已实现并上板**） |
| `gray_conv.v` | RGB24→8bit 灰度（BT.601 组合逻辑，已上板验证） |

## 与「计划版模块名」的对应（避免有人拿旧清单找不到文件）

| 旧计划名 | 实际文件 |
|---|---|
| `timing_ctrl.v` | `video_timing.v` |
| `hdmi_in_ctrl.v` | **已实现** —— `src/rtl/board/hdmi_in_ctrl.v`，HDMI 输入通路已上板（`37c1d2c` 实测 PASS） |
| `gray_conv.v` | **已实现** —— `src/rtl/board/gray_conv.v`（构建用）+ `src/rtl_pending/gray_conv_line2.v`（线二新版备用） |
| `frame_buffer.v` | `frame_buf.v` + `downsample2x2.v`（压缩与缓存拆成两个模块） |
| `frame_diff.v` | `diff_stage.v`（帧差与背景建模共用，靠 `MODE_BG` 切换） |
| `thresh_bin.v` | `threshold.v` |
| `morph_erode.v` / `morph_dilate.v` | `morph3x3.v`（一个模块两种模式）+ `morph_open.v` |
| `centroid.v` | **未实现**，当前只要包围盒，不要质心 |
| `bbox_overlay.v` | `overlay.v` |
