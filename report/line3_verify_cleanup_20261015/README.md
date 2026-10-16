# 线三验证补强与互验结果 · 第二轮（2026-10-15）

日期：2026-10-15。执行者：Codex；需求由线一（主城要）转达。人工签字待孙伟博与线二确认，本记录不代签。

本轮为 16 目标版两个 RTL 修复（multi_bbox FIFO 256→512、哨兵撞码标签扩 5 位）落地后的复跑弧线，
外加一次测试台假阴性定性。**未修改产品 RTL**；被测版本与夹具哈希全部记录在各轮 `source_manifest.json`。

## 固定版本与结论

- 被测 RTL：`--ref` 逐轮记录（e47dd6cb / 4f1cc619 / 37c08fb，见下表）；测试夹具（tb）由运行器同目录取当前版本。
- Vivado 2026.1（settings64.bat 实际路径 D:/AMDDesignTools/2026.1/Vivado/settings64.bat）；
  本轮是 RTL 仿真，无综合、布局布线、bit 或板上验证。
- **验收基线 = 37c08fb + 修复后 tb（flush 4096）**：full16 / label_full / bridge / reuse / overflow 全 PASS。
- 仍 FAIL 未修（10-13 首轮已记录，本轮未触及）：wrap（track id 回绕首现误报）、axi_channels（AXI 分拍写丢失）。

## 复跑弧线（按时间序，全部证据在 evidence/ 各轮目录）

| 轮次（目录） | RTL | tb 哈希 | full16 | label_full | 其余 |
|---|---|---|---|---|---|
| arc1_1025 | e47dd6cb（16 目标切换，两修复均未入） | fd310147… | FAIL | FAIL | overflow PASS |
| arc2_1020 | e47dd6cb | fd310147… | — | — | bridge / reuse PASS |
| arc3_1040 | 4f1cc619（FIFO 512 已入，哨兵未入） | fd310147… | FAIL | FAIL | bridge / reuse PASS |
| run_1100 | 37c08fb（两修复均入） | fd310147…（旧，flush 256） | FAIL | FAIL | bridge / reuse / overflow PASS |
| run_1110 | 37c08fb（**与 1100 同一 RTL**） | 31fd4e57…（新，flush 4096） | **PASS** | **PASS** | — |

## 假阴性定性（受比实验，铁证）

run_1100 与 run_1110 的 `source_manifest.json` 全量对比：**唯一差异文件是
`sim/line3/verify_cleanup/tb_multi_bbox_limits.v`**（fd310147164f… → 31fd4e57d00f…），
RTL 与其余文件一字节未动。同一 RTL、仅换 tb，full16 / label_full 由 FAIL 翻 PASS
→ **旧 tb 的 flush 窗口（256）太小，长帧仿真收尾前数据被截，产生假阴性 FAIL**；
tb 修复见提交 99f0129（flush 256→4096）。

**诚实的边界**（防止过度解读）：
- 该受比实验只证明"37c08fb + 旧 tb 必然假阴性"，**不能**反推哨兵修复不需要
  （arc3_1040→run_1100 之间 RTL 变了，不存在"4f1cc61 + 新 tb"的受比运行）。
- arc1/arc3 轮的 FAIL 同样使用旧 tb，同样不能单独归因为 RTL 缺陷；
  两个 RTL 修复的必要性以代码级分析（哨兵 4'hF 撞 id15、FIFO 净欠 ~304 拍）为准，
  最终以 run_1110 全 PASS 收口。
- 运行目录名的时间段标签取自调试过程记录；xsim 控制台内部时间（10-15 18:30-18:31）为权威运行时间。

## 可复跑入口

在仓库根目录（Python + Vivado，输出必须是新的 ASCII 目录）：

```powershell
python -X utf8 sim/line3/verify_cleanup/run_verify_cleanup.py --repo . --ref <SHA> --out D:/line3_verify_new --settings D:/AMDDesignTools/2026.1/Vivado/settings64.bat
```

最小单项：`--jobs full16` / `--jobs label_full` / `--jobs wrap` / `--jobs cfg` / `--jobs axi_channels`。
候选版本用 `--ref <固定SHA>` 选择；每次保存测试文件哈希，便于同台比较。
首轮（10-13）证据在 `../line3_verify_cleanup_20261013/evidence/`；失败证据未被覆盖，两轮原始文件均保留。

完整源快照（含各轮 source/ 与 xsim 中间产物）在本地 ZIP：
`D:\FPGA\line3_verify16_snapshots_20261015.zip`（未入库，按既有惯例仓库只保留小体积证据）。

## 互验与后续门槛

| 项目 | 本轮结论 | 人工确认 |
|---|---|---|
| 16 目标满配功能（full16/label_full/bridge/reuse/overflow） | 37c08fb + 修复后 tb 全 PASS | 孙伟博/线二待独立复跑签字 |
| tb 假阴性 | 受比实验坐实（1100 vs 1110 仅 tb 不同） | 已记录，无需签字 |
| wrap（ID 回绕误报） | FAIL，未修（A1） | 线二拍板修法后复跑 |
| axi_channels（分拍写丢失） | FAIL，未修 | 修复后保留同用例复跑 |
| LUT<26600、place/route、generic 绑定 | 本轮未验证 | 以综合报告为准 |
| 实机报文、18 分钟回绕、视频对应 | 本轮未验证 | 线一/线二提供板端材料 |

本轮未向群聊或队友发送消息。
