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

**1. 顶层没接线（最关键，10/13 上板卡这）**
- line2 `board_top.v` **既未例化 `uart_tx`、也未例化 `bbox_snapshot`**（已 grep 确认为空）。
- 后果：现在真板上**既跑不出 UART 报文，也读不到 AXI bbox 快照**。
- 线二 `bbox_snapshot.v` 注释明确"顶层接入（md_pipeline 由线一接）"→ **接线是线一的活**，需线二给 tap 点（见待决③）。

**2. 伟博接收端还吃不了板子数据**
- `pc_receiver.py` 仍是 JSONL/TCP，首行自注"No board protocol has been agreed"。
- `frame_id` 硬校验 `[0, 2^32-1]`（32 位），与线二 16 位帧号**对不上**（见待决①）。
- JSON schema 无 `alarm/event` 字段，`0xC3` 事件无处安放（见待决②）。
- 需伟博加 pyserial 串口分支 + 决定事件落点；其提案已预留"串口先补适配"。

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

## 四、仍待决（原 11 问 → 收敛为 3 个 + 1 附带）

**以下已闭环，不用再问**：Q3 valid 位（FLAGS=0 + OBJ_CNT=0 已覆盖空帧语义）、Q4 坐标域（定稿确认 640×360）、Q5 事件 CX（定稿=中心 X）、Q8 规格（定稿 §4.2 即权威规格）、Q9/Q10 机制（定稿双通道，非"UART 替代 AXI"二选一）。

**待决① 帧号位宽（原 Q2/Q7）**
线二 `frame_num`/`BBOX_FRAME` 均 16 位回绕；伟博 `pc_receiver.py` 硬校验 32 位 `frame_id`。
建议：线二把帧号扩到 32 位（板端代价小，省得伟博写回绕解释），或伟博按 16 位解释。→ **需线二 + 伟博拍板。**

**待决② 事件 0xC3 落点（原 Q6）**
伟博 JSON 无 alarm 字段。选：加 `alarms:[{id,type,center_x}]` 数组，还是单落 `alarm_events.jsonl`？→ **需伟博定。**

**待决③ 顶层接线 tap 点（原 Q1）**
线一 10/13 前把 `uart_tx` + `bbox_snapshot` 接进 `board_top/md_pipeline`；需线二确认：
`i_latch` 生成判据、`i_frame_idx` 来源（`md_pipeline.frame_idx`）、`i_obj_count` 取 multi_bbox 帧结算、PMOD 引脚、波特率(115200)。→ **线一主责接线，线二给 tap。**

**附带（线一，群确认后）**：合线二分支时更新 `interface_freeze_table.md`，补 BBOX `0x1C–0x34` + STATUS bit1。

---

## 五、下一步（按影响力排序）

1. **线一**：接线（uart_tx + bbox_snapshot 进 board_top）→ 重出 bit → 10/13 上板出真实报文 + 抓帧样本。
2. **线二**：确认接线 tap 点 + PMOD + 帧号是否扩 32 位。
3. **伟博**：接收端加 UART 串口分支 + 定事件落点。
4. **线一**：合线二分支时同步冻结表（补 BBOX 0x1C）。
