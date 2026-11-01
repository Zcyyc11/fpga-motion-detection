# UART↔JSON 适配器与回传对齐 · 单一最优版本 v1.0

> 本文件 = 线一审计后的**单一权威版**，取代先前 `uart_json_adapter_spec.md` 草稿中已过时的表述。
> 协议细节以 `docs/protocol_and_interface_requirements.md`（回传协议与接口定稿 §4）为准；
> 本文件聚焦四件事：**已验证事实 / 未闭环缺口 / UART→JSON 适配器 / 仍待决问题**。
> 所有结论核到 2026-10-12 实际代码，非凭提交信息：
> 线二 `line2/multi-bbox-gray@3e51dbd`、main `@f15fbce`、伟博 `codex/line3-delivery-20261011@f0eca20`。

---

## 一、已验证 DONE（核代码坐实）

| 项 | 归属 | 证据 |
|---|---|---|
| `bbox_snapshot.v` 帧快照 + CDC | 线二 | 帧边界 `i_latch` 把 `bbox+frame_idx+obj_count+alarm` 同拍锁 118bit `snap_bus`；四段握手 CDC（req toggle + 双向两 FF 同步 + `snap_hold` 保持 + AXI 侧 `update` 整组采样）→ **伟博硬要求①② 满足** |
| `regs.v` ps_addr 加宽 + BBOX 寄存器 | 线二 | `ps_addr` 已 `[5:0]`；`0x1C–0x34` BBOX_X1/Y1/X2/Y2/CNT/VALID/FRAME；STATUS bit0=b_valid、bit1=告警粘存(方案A)、bit30:16=frame_idx 镜像 |
| 回传协议双通道定案 | 线一定稿 | UART 管"推"（实时事件/目标），AXI 管"拉"（快照查询），数据同源；**非二选一** |
| UART v0.2 三包协议 | 线一定稿 | 帧头 `0x5A`(5B) / 目标 `0xA5`(14B) / 事件 `0xC3`(8B)；115200-8N1 小端累加和；事件 TYPE 1=越界 2=停留、CX=中心X(16b) |

---

## 二、未闭环缺口（真正的卡点，勿被提交信息误导）

**1. 顶层接线：已并入 main（2026-10-12），但甲通路默认关闭**
- 线二 `uart-wiring@0a778c8` 已把 `uart_tx`（`md_pipeline.v` L338 `u_utx`）/`bbox_snapshot`（L399 `u_snap`）接进顶层并引出 `uart_txd`（XDC PIN Y18，PMOD A ja[0]），`tb_md_pipeline_uart` 13 项 PASS；已随 `0a778c8` 并入 main。
- **但默认 `INCLUDE_PS=0`**：`regs`/`bbox_snapshot` 会被综合优化掉 → **UART（乙）生效，AXI 快照（甲/I4）默认不生效**。要开甲通路须改 `INCLUDE_PS=1`，重跑 `tb_md_pipeline_uart`/`tb_regs` 并重建 bit（`line2/top-integration@15e8e21` 即 INCLUDE_PS=1 版，可参考、未合并）。

**2. 伟博接收端：严格版已交并并入 main（2026-10-12）**
- `sim/line3/uart_receiver.py`（`9f7173a`，已并入 main）直接吃三包二进制：16 位帧号、事件独立 `events.jsonl`、来源标注/负例/退出码语义/原始流留档——**原待决①（按 16 位）与②（事件落点）就此闭环**。
- 板测验收统一用它；`pc_receiver.py`（JSONL/TCP 历史模拟）与 `src/ps/uart_recv.py`（最小参考）均不作为验收依据。

**3. 冻结表 I4 未跟上**
- `interface_freeze_table.md` 仍只到 `STATUS 0x18`，未列 BBOX `0x1C–0x34`、未写 STATUS bit1。
- 定稿已声明、regs 已实现，但**权威契约没同步**。线二合 main 时须按冻结表流程"一份提交里同时改 冻结表 + RTL + tb"，且先群内确认。

---

## 三、UART → 伟博 JSON 适配器映射（有效，对齐定稿 §4.2）

线二线协议（小端，字节累加和 CHK）：
- 帧头 `0x5A`: MAGIC, FRAME_L, FRAME_H, OBJ_CNT, CHK
- 目标 `0xA5`: MAGIC, FRAME_L, FRAME_H, ID, X1L,X1H, Y1L,Y1H, X2L,X2H, Y2L,Y2H, FLAGS, CHK
- 事件 `0xC3`: MAGIC, FRAME_L, FRAME_H, ID, TYPE, CX_L, CX_H, CHK

→ 伟博 JSONL（固定字段）：`{"version":1,"source":"board-unverified","frame_id":N,"width":640,"height":360,"coordinate_space":"i3-2x","targets":[{"id":ID,"valid":true,"x1":X1,"y1":Y1,"x2":X2,"y2":Y2}]}`

| 伟博字段 | 来源 | 状态 |
|---|---|---|
| `frame_id` | FRAME（16 位） | ⚠️ 待决①（伟博要 32 位） |
| `width/height/coordinate_space` | 固定 640/360/i3-2x | ✅ 坐标即大像素域，直接对应不×2 |
| `targets[]` | 同帧全部 `0xA5` 包 | ✅ valid 恒 true；无目标帧=OBJ_CNT=0→空列表 |
| `id/x1/y1/x2/y2` | 包内字段，16 位小端解包 | ✅ |
| 事件 `0xC3` | 无对应字段 | ⚠️ 待决② |

适配器逻辑（伟博/线二 `uart_recv.py` 实现）：pyserial 115200-8N1 → 按 MAGIC 分流收齐 → 校验 CHK 坏包丢弃 → 按 FRAME 分组，收齐 OBJ_CNT 个目标包后输出一行 JSONL（伟博 `check_pc_receiver` 可直接消费）。

---

## 四、待决清单（2026-10-12 全部闭环）

**以下已闭环，不用再问**：Q3 valid 位（FLAGS=0 + OBJ_CNT=0 已覆盖空帧语义）、Q4 坐标域（定稿确认 640×360）、Q5 事件 CX（定稿=中心 X）、Q8 规格（定稿 §4.2 即权威规格）、Q9/Q10 机制（定稿双通道，非"UART 替代 AXI"二选一）。

**待决① 帧号位宽（原 Q2/Q7）：已闭环**——线三接收端按 **16 位**实现（65535→0 回绕接受），线二维持 16 位，两端一致。

**待决② 事件 0xC3 落点（原 Q6）：已闭环**——线三接收端落 `events.jsonl`（独立事件日志、按帧关联）。

**待决③ 顶层接线 tap 点（原 Q1）：已闭环**——`0a778c8` 已接线（`u_utx` L338 / `u_snap` L399，`uart_txd`→PMOD A ja[0]=PIN Y18，115200/BAUD_DIV=645）。

**附带（线一）**：已完成——并线 docs 提交已补 `interface_freeze_table.md`（BBOX 0x1C–0x34 + STATUS 位表）。

---

## 五、下一步（按影响力排序）

1. **线一/线二**：用并线后的 main 重出 bit（`build_vivado.bat 0 1`，generic 空格分隔）→ 10/13 上板出真实报文 + 抓帧样本；如需甲通路，另出 INCLUDE_PS=1 版并重跑 tb。
2. **线二**：盯 bit 出来后烧录（`build/scripts/burn_jtag.tcl`），grep 日志确认 `bound to` 真绑定。
3. **伟博**：用 `sim/line3/uart_receiver.py` 收真实报文，按 `docs/line3_uart_receiver.md` 的对照流程核（10/14 样本）。
4. **线一**：已完成（冻结表补齐、接收端定唯一权威、接口文档对齐）。
