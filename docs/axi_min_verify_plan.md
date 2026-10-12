# AXI 最小验证工程方案（线一 · 甲通路 · 技术方案 §5.3）

> 定位：把"甲 = 轻量 AXI-Lite 寄存器读出（I4 兑现）"从零落地。当前 main 的 bit 是**纯 PL**
> （build_vivado.tcl 明确"不建 Block Design"，无 PS / 无 AXI / 无 MMIO），所以甲要从零把
> Zynq PS + AXI 互连接进工程。本方案是线一（通路线/架构线）的施工路线。
> 配套：src/rtl/board/axi_lite_slave.v（已写）、sim/tb/tb_axi_lite_slave.v（已写）、
>       src/ps/mmio_readout.py（已写）。

---

## 1. 目标与路线判据（§5.3）

- **最小验证工程 = PS + AXI 从机，读写通 → 路线成立**，再进 board_top；不碰视频流水线逻辑。
- 判据（tb 或 Jupyter 都行）：PS 写 `THRESH` → 读回一致；读 `BBOX_*` 快照与帧号配对。
- 完成后**重跑时序**（build 脚本已有时序门，WNS<0 直接判失败）。

## 2. 当前状态（已核实际代码）

- `board_top.v`：纯 PL 顶层（125M→MMCM、HDMI 进/出、LED），**无 PS 端口、无 AXI 从机**。
- `build_vivado.tcl`：纯 RTL 工程，`top=board_top`，器件 xc7z020clg400-1，**无 BD、无 PS7 IP**。
- `regs.v`（在 `line2/multi-bbox-gray` 分支）：参数控制寄存器堆，接口是瘦总线
  `ps_en/ps_we/ps_addr[4:0]/ps_wdata[31:0]/ps_rdata[31:0]`；**bbox 快照寄存器尚未写**。
- 构建产物只有 `.bit`，无 `.hwh/.xsa`（无 PS）。

## 3. 集成步骤（引入 PS，但尽量守住"算法流水线不套 BD"的初衷）

1. **加 PS7 + AXI Interconnect IP**：在 `build_vivado.tcl` 里 `create_ip -name processing_system7`
   配置 MIO（ENET0/USB/UART/QSPI/TF）、DDR（PS 侧 1GB）、使能 **M_AXI_GP0**（PS→PL AXI 主口）、
   配 FCLK（如 100 MHz 给 AXI 从机）。`create_ip -name axi_interconnect`（1 主 1 从）。
   > 注：PS7 的 DDR/MIO 配置通常需要一份 PS 配置（.xsa）。纯 RTL 工程里配 PS7 可用
   > `set_property` 逐项设，或引一份最小 PS 配置 tcl。这一步是甲的最大工程量，线一负责。
2. **挂 axi_lite_slave**：`axi_interconnect` 从端 → `axi_lite_slave`（已写），其瘦总线接
   `regs`（线二）。最小验证阶段可先接一个"测试寄存器堆"（THRESH 可写 + 只读计数），
   证明路径后再换成 `regs.v`。
3. **clock**：AXI 从机与 regs 跑 FCLK（PS 钟）；流水线（md_pipeline）跑像素钟。
   **CDC（像素钟↔FCLK 整帧快照一致）由线二在快照锁存处做（伟博硬要求②），本桥不管。**
4. **出交付物**：`write_bitstream` + `write_hwdef`/导出 `.hwh`（供 Jupyter `Overlay` + MMIO）。
   脚本加一步出 `.hwh`，命名 `board_top_axi.bit` / `board_top_axi.hwh` 与纯 PL 版区分。

## 4. 发现并要修的代码 bug（已核 regs.v）

- **`regs.v` 的 `ps_addr` 是 `[4:0]`，只能编到 0x1C**；草案里 BBOX 寄存器在 `0x20..0x34`
  会超宽 → **线二须把 `regs.ps_addr` 加宽到 `[5:0]`**。`axi_lite_slave` 已按 6 位字节地址
  输出（`awaddr[5:0]`），对接加宽后的 regs 直接可用。这是"声称与代码不符"类，先记下来。

## 5. 互验门（写的不自签）

- `axi_lite_slave.v` + `tb_axi_lite_slave.v`：线二或线三跑 xsim，全 PASS 才签字（写的人=线一，不自签）。
  **已真跑通（Vivado 2026.1 xsim，2026-10-12）：4/4 PASS（写回一致 / 第二口写回 / 只读计数单调 / 连续不错位）。**
  真实根因修法：① ps_en/ps_we/ps_addr 原被两个 always 块**双驱动**→ 合并为单块统一驱动；② 读 1 拍延迟→ master 改 `while(!rvalid)` 真握手。
- PS 侧 `mmio_readout.py`：线三（伟博）上板跑，确认 CSV 与抓帧/bit 哈希/源码 SHA 配对。
- 改接口前按《接口冻结表》流程群内确认。

## 6. 文件清单（本次新增）

| 文件 | 作用 | 状态 |
|---|---|---|
| `src/rtl/board/axi_lite_slave.v` | AXI-Lite 从机→瘦总线桥 | 已写，xsim 4/4 PASS（2026-10-12 真跑通） |
| `sim/tb/tb_axi_lite_slave.v` | 协议翻译验证台 | 已写，xsim 4/4 PASS，待线二/线三另跑签字 |
| `src/ps/mmio_readout.py` | Jupyter MMIO 读 bbox/写 THRESH | 已写，待 PS 构建 |
| `docs/axi_min_verify_plan.md` | 本方案 | 已写 |
| `docs/board_runbook.md` | 乙路径抓帧 run-book | 已写 |
| `docs/line1_uart_field_table_draft.md` | bbox 快照 + STATUS 位分配 | 已写，待线二对齐 |

## 7. 下一步

- **线一**：跑通 tb（或交线二跑）→ 出 PS 集成构建 tcl → 出 `board_top_axi.bit/.hwh`。
- **线二**：加宽 `regs.ps_addr[5:0]` + 补 `BBOX_*` 快照寄存器（帧边界锁帧号 + CDC）。
- **线三**：上板跑 `mmio_readout.py` 出 CSV，与抓帧配对交评审。
