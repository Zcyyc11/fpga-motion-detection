# 多目标版集成 · 当前状态（已并入 main）

> 更新：2026-10-12 21:10（线一审定；并线后全量重写，旧版"构建中/顶层没接线"等过时描述已删）
> 面向：徐一夫（线二）、孙伟博（线三）、线一
> 权威依据：main 合并链 `47a8c11`（线二顶层接线）→ `b9277c1`（线一收尾）→ `f9e07df`（线三接收端），全部核实际代码

---

## 一句话现状

**多目标 + UART 回传全链已并入 main；bit 尚未产出；甲通路（AXI 快照/I4）默认 INCLUDE_PS=0 关闭。** 单目标版上板实测 PASS（37c1d2c）仍然有效。

## 已完成（勿重复）

| 项 | 状态 | 证据 |
|---|---|---|
| multi_bbox/track/alarm/regs/uart_tx/bbox_snapshot/overlay_multi RTL | ✅ 并入 main | 合并 `47a8c11`（自 0a778c8） |
| 顶层接线：md_pipeline `u_utx`(L338)/`u_snap`(L399)，board_top `.uart_txd`(L211) | ✅ 并入 main | `0a778c8` |
| XDC：`uart_txd` → PIN Y18（PMOD A ja[0]） | ✅ 并入 main | `board/pynq_z2_hdmi_out.xdc` |
| `tb_md_pipeline_uart` 13 项 PASS（INCLUDE_PS=0） | ✅ | `sim/logs/tb_md_pipeline_uart_20261012.log` |
| 线三 UART v0.2 接收端 + 顶层联合仿真（**板测验收唯一权威**） | ✅ 并入 main | `f9e07df`（自 9f7173a） |
| gray_conv 同名冲突拍板 | ✅ 选②：构建用旧版 `src/rtl/board/gray_conv.v`，线二新版存 `src/rtl_pending/gray_conv_line2.v`（不在构建 glob 内） | 交棒声明 `2505417` |
| 接收端二选一定案 | ✅ 验收用 `sim/line3/uart_receiver.py`；`src/ps/uart_recv.py` 只作最小参考 | 并线 docs 提交 |

## 已知边界（真话，接手必读）

- **INCLUDE_PS=0（当前默认）**：`regs`/`bbox_snapshot` 被综合优化掉 → **UART（乙）生效，AXI 快照/参数运行时控制（甲/I4）默认不生效**。要开甲通路：改 `INCLUDE_PS=1` → 重跑 `tb_md_pipeline_uart`/`tb_regs` → 重建 bit。`line2/top-integration@15e8e21` 就是 INCLUDE_PS=1 版，可参考；**该分支未合并，勿再合**（防双份例化）。
- **bit 未产出**：19:28 启动的那次构建是**并线前的 line1 版（没有 UART）**，且仍在跑。**旧纪律"构建阶段以 build/logs/vivado_build.log 为准"作废**——实测进程在跑、日志不涨。新判据：bit 文件时间戳 + vivado 进程存在。
- 下一次构建必须从**并线后的 main** 出（`build_vivado.bat 0 1`，generic 空格分隔）。

## 待办（按顺序，别跳）

1. 处理 19:28 的旧构建（等它结束或直接终止，别让两个 Vivado 同时碰仓库）。
2. 从并线后 main 重出 bit → grep 日志确认 `MODE_BG/INPUT_SEL bound to` 真绑定。
3. 烧录（`build/scripts/burn_jtag.tcl`）→ 4 项实测：多目标多框检出 / 18 分钟回绕 / 换视频（vehicles、market-square、people-walking）/ `verify_board.py` 自动取证到 `board/logs/`。
4. USB-UART：PMOD A ja[0]（Y18）→ USB 转串口 → PC，用 `sim/line3/uart_receiver.py` 收真实报文；10/14 交零/单/多目标样本 + 帧号对照表。
5. （可选，10/14 后）INCLUDE_PS=1 版重验甲通路，兑现 I4 全表。

## 红线纪律（不变）

- generic 传参**空格**分隔（逗号=坏货固件）；构建完必 grep `bound to`；两个 Vivado/豆包窗口**禁止**同时碰同一仓库。
