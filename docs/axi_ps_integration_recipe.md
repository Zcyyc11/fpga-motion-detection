# PS 接入施工配方（线一 · 甲通路下一步 · §5.3 最小验证工程落地）

> 本文是 `axi_min_verify_plan.md` 的**可执行下一步**：把 Zynq PS + AXI 互连接进工程，
> 让 `axi_lite_slave` 能被 PS 经 MMIO 访问。当前 main 是纯 PL（无 PS/无 .hwh），本文给出
> 最低风险做法 + 可直接跑的 Tcl 片段 + 坑位预警。
> 状态：线一已写好桥+tb+计划，本文是把"桥"真正挂上 PS 的施工单。需 Vivado 环境（本机 xsim 不可用，PS 集成更需 Vivado + 许可）。

---

## 1. 为什么用"最小 BD"而不是纯 RTL 手搓 PS7

`processing_system7` 有 DDR、FIXED_IO(MIO) 等几十个端口，纯 RTL 工程里手搓这些外部端口
等于把 BD 重写一遍且更易错。§5.3 要的是"先证明 PS↔PL AXI 路径通"，所以**最小 BD 只装
PS7 + AXI Interconnect + axi_lite_slave**，算法流水线（board_top）暂不进 BD——正好守住
`build_vivado.tcl`"算法流水线不套 BD"的初衷。路径通了再决定 board_top 是否也挂进来。

## 2. 步骤（Vivado 里）

1. **建 BD**：`Create Block Design` → `design_1`。
2. **加 PS7（PYNQ-Z2 预设）**：
   ```
   create_ip -name processing_system7 -vendor xilinx.com -library ip \
             -version 5.5 -module_name processing_system7_0
   set_property -dict [list CONFIG.PCW_BOARD_PRESET {PYNQ-Z2} \
                          CONFIG.PCW_USE_M_AXI_GP0 {1} \
                          CONFIG.PCW_M_AXI_GP0_FREQMHZ {100} \
                          CONFIG.PCW_USE_DDR {1} \
                          CONFIG.PCW_UART1_PERIPHERAL {MIO48} ] \
            [get_ips processing_system7_0]
   generate_target all [get_ips processing_system7_0]
   ```
   > 预设 `PYNQ-Z2` 一次性把 DDR/MIO/ENET0/QSPI/TF 配对，别逐项手填（手填漏一项就 BOOT 不起来）。
3. **加 AXI Interconnect（1 主 1 从）**：
   ```
   create_ip -name axi_interconnect -vendor xilinx.com -library ip \
             -version 2.1 -module_name axi_interconnect_0
   set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1}] \
            [get_ips axi_interconnect_0]
   generate_target all [get_ips axi_interconnect_0]
   ```
4. **加 axi_lite_slave**：把 `src/rtl/board/axi_lite_slave.v` 作为 RTL 模块加进 BD
   （Add Module / 或先 `create_ip` 包成 IP）。其瘦总线（ps_en/ps_we/ps_addr/ps_wdata/ps_rdata）
   暂时接一个**测试寄存器堆**（THRESH 可写 + 只读计数），证明路径；之后换成 `regs.v`（线二加宽 ps_addr 后）。
5. **连线**：PS7 `M_AXI_GP0` → Interconnect `S00_AXI`；Interconnect `M00_AXI` → `axi_lite_slave` `S_AXI`。
   跑 `Connection Automation`（Vivado 自动补时钟/FCLK_RESET）。
6. **分配地址**：`Address Editor` 给 `axi_lite_slave` 分配基址（如 `0x43C00000`，4K），
   这就是 `mmio_readout.py` 里 `BASE` 的真值（从 .hwh 读）。
7. **出交付物**：`Generate Block Design` → `Create HDL Wrapper` → 综合实现 →
   `write_bitstream board_top_axi.bit` + **`write_hwdef`/导出 `.hwh`**（供 Jupyter `Overlay` + MMIO）。

## 3. 坑位预警（提前写死，省得现场踩）

- **PYNQ-Z2 预设必须选对**：选成通用 Zynq-7000 会导致 DDR 时序/引脚不对，板子不 BOOT。
- **FCLK 频率**：GP0 默认 100 MHz，axi_lite_slave 跑这个钟（与像素钟 74.25 MHz 是两套钟，
  CDC 由线二在 bbox 快照锁存处做，见伟博硬要求②）。
- **.hwh 必须有**：纯 PL bit 走 JTAG 能跑，但 PS 的 MMIO 必须 `Overlay('.hwh')` 配对，否则
  Python 不知道寄存器在哪。构建脚本要加一步出 .hwh（命名 `board_top_axi.hwh` 与纯 PL 版区分）。
- **时序**：加 PS+互连后资源/时序会变，按 `build_vivado.tcl` 的 WNS<0 判失败门重跑。

## 4. 判据（§5.3 "路线成立"）

Jupyter 里 `Overlay('board_top_axi.bit')` → `MMIO(BASE,0x1000).write(0,0x1234).read(0)==0x1234`
→ PS↔PL AXI 路径通。再接 `regs.v`（线二）后即可读 bbox 快照。

## 5. 文件依赖

- 输入：`src/rtl/board/axi_lite_slave.v`（已写）、`docs/axi_min_verify_plan.md`（已写）
- 待线二：`regs.v` 加宽 `ps_addr[5:0]` + 补 `BBOX_*` 快照寄存器（见 `line2_reminder.md`）
- 输出：`board_top_axi.bit` + `board_top_axi.hwh` + 更新 `build/scripts/build_vivado.tcl`
