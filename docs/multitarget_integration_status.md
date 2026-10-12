# 多目标版集成 · 当前状态与交接说明（线一 → 队友）

> 更新时间：2026-10-12 19:40（本地）
> 分支：`line1/multi-bbox-integration`（从 origin/line2/multi-bbox-gray 拉出）
> 面向读者：徐一夫（线二，接手下一步）、孙伟博（线三）、线一本人

---

## 一句话现状

**多目标版接线的代码已完成并推送到本分支（含 1 处接线 bug 修复 248a6d8）；bit 正在构建（具体阶段以 build/logs/vivado_build.log 为准）；下一步是烧录 + 上板实测。** 单目标版已实测 PASS（main @37c1d2c，红框框住卡车证据在 board/logs/）。

## 已经做完（勿重复）

### 代码改动（已提交 10f9be5，已推送）
| 文件 | 改动 | 说明 |
|---|---|---|
| `src/rtl/overlay_multi.v`（新建） | 多目标 OSD | 双缓冲目标表（≤16 目标）、掩码流帧边界发布、逐像素判断任一目标框边画红、状态灯（绿=检出/灰=空闲）、`b_obj_count` 目标数输出 |
| `src/rtl/md_pipeline.v` | ⑧⑨段重接 | `bbox` → 线二 `multi_bbox` 例化（MIN_CNT 沿用参数）；新增 `f_edge`（检测域 y 回绕）；`overlay` → `overlay_multi`；`b_*` 输出改由 overlay_multi 驱动 |
| `src/rtl/board/board_top.v` | 端口 | 声明并传递 `b_obj_count`（8bit，目标数） |
| `src/rtl/gray_conv.v`（根目录） | 临时移出 | 见下方「坑」 |

### 已确认的事实
- 构建红线纪律：generic 必须**空格分隔**（Vivado 2026.1 只认空格，逗号=坏货）。构建脚本 build_vivado.tcl 已固化。本轮实测日志：`EFFECTIVE_GENERIC=MODE_BG=0 INPUT_SEL=1` ✅
- 当前构建命令：`build_vivado.bat 0 1`（0=帧差算法，1=HDMI 输入）
- 已修复：md_pipeline 中 `t_valid` 重名双驱动（threshold→morph 域 vs multi_bbox→overlay 域），后者改名 `mb_valid`（commit 248a6d8）。**若发现 multi_bbox 输出或 morph 输入异常，先查是否又有同名 wire。**

## 坑（接手必看）

### gray_conv 同名冲突（线二的事，待你拍板）
- 线二新版 `src/rtl/gray_conv.v`（接口：in_de/in_hsync/in_vsync/in_x/in_y/in_rgb → out_*）与原有 `src/rtl/board/gray_conv.v`（接口：vde/x/y/pix_in → o_*）**同名**。
- 构建脚本 glob 同时收录 src/rtl/*.v 与 src/rtl/board/*.v → 两个 gray_conv 进 fileset → 同名模块冲突 → `board_top` 的 u_gray 例化连到接口不匹配的版本 → 综合 12 报错。
- 处理：新版已归档到仓库内 `src/rtl_pending/gray_conv_line2.v`（**不在构建范围**，glob 只扫 src/rtl 与 src/rtl/board）。当前构建用旧版（已上板验证过）。
- **待线二决定**：①新版接进 board_top（同步改 u_gray 例化，删旧版）；②或保留旧版、新版改名备用。**二选一，不能两个都留**（否则下次构建仍炸）。决定后把文件移回 src/rtl 并提交。

## 回传协议现状（队友必读：这是 10/13 上板的卡点）

权威文档：**`docs/uart_json_adapter_spec.md`（线一审定的单一权威版，取代旧草案，已入库）**。核心缺口：
- **顶层没接线**：line2 `board_top.v` 既没例化 `uart_tx`，也没例化 `bbox_snapshot`（grep 已确认为空）→ 现在真板子**既跑不出 UART 报文、也读不到 AXI bbox 快照**。
- 接线职责：`bbox_snapshot.v` 注释写明"顶层接入（md_pipeline 由线一接）"——多目标版已整体转给线二接手，**这条也归徐一夫**（tap 点见 uart_json 文档"待决"节）。
- 接收端：`pc_receiver.py` 还是 JSONL/TCP，吃不了板子数据（frame_id 32bit vs 16bit 对不上、JSON 无 alarm/event 字段）——孙伟博那边要加 pyserial 串口分支。

### overlay_multi 设计要点（徐一夫改这里时先读）
- 双缓冲：shadow 收 multi_bbox 串行输出（t_valid/t_last），掩码流帧边界 f_edge 时整体发布到 active，画框用 active（描述上一帧，与旧 bbox 行为一致，滞后一帧）。
- multi_bbox 输出大像素坐标（I2），表内原样存储，画框比较时 ×2 转像素。
- `b_obj_count` = 上一帧目标数（active 表 n），帧边界更新；`b_valid` = (n != 0)。
- 目标数上限 16（MAX_TARGET 参数），与 multi_bbox MAX_LABEL 对齐；超限时 t_valid 仍写入但 w_idx 可能回绕——当前先保功能，超 16 目标的场景实测时留意。

## 待办（按顺序，别跳）

1. **看构建结果**：`build/logs/vivado_build.log` 尾部。成功→下一步；失败→把日志尾部发群里一起看。
2. **烧录**：Vivado 2026.1 Hardware Manager JTAG batch（脚本已入库：`build/scripts/burn_jtag.tcl`，用法见文件头注释：`vivado -mode batch -source build/scripts/burn_jtag.tcl -tclargs <bit文件名>`），不依赖板子系统。
3. **多目标实测（4 项）**：
   - 多目标检出：画面多个移动物体 → 多个红框（单目标版只有 1 框，这是本版核心差异）
   - 18 分钟回绕：跑满 18 分钟画面不花、背景不重建（P3 修复验证）
   - 换视频：`D:\FPGA\test_videos\` vehicles / market-square / people-walking 三个各放一遍
   - 自动验证：`build/scripts/verify_board.py`（采集卡直读 + 连通域红框检测，证据自动写 `board/logs/`；格式参考 board_test_20261012.md）
4. **线二欠账（勿忘）**：板端发送程序 + 真实报文样本（10-14 交付；回传协议 v0.2 核心已确认，uart_json_adapter_spec.md 相关）。

## 红线纪律（踩过坑，别重蹈）

- generic 传参**必须空格**分隔（逗号=开关没拨=坏货固件，10-11 出过一次）。
- 构建完**必须** grep 日志 `bound to` 确认 MODE_BG / INPUT_SEL 真绑定，再拿去烧。
- 两个 Vivado/豆包窗口**禁止同时碰同一仓库**（互相覆盖会出鬼）。

## 推送状态

- 代码：✅ 已推 `line1/multi-bbox-integration`（10f9be5）
- bit：⏳ 构建中（阶段以日志为准；中途发现 t_valid 重名 bug 已修并重跑），出来后**必须**推（build/bitstream 是 git 跟踪的）
- 实测证据：⏳ 待实测后推
