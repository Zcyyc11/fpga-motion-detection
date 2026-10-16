# 全工程同款 bug 审计报告（2026-10-15 晚）

背景：multi_bbox 今天实测踩了两个坑（哨兵撞码、FIFO 吐吞不足）。按这两类对 src/rtl 全部 27 个文件做定向扫描。结论：**新发现 2 个真问题、3 条良性备注**，其余文件干净。

## 新发现（需处理）

### A1. track.v id_next 8 位回绕 vs alarm.v 注释撒谎（严重度：高·长跑必现）
- 位置：track.v:143 `tr_id[tr_n] = id_next; id_next = id_next + 8'd1`
- 事实：id 空间 8 位（alarm.v:20 MAX_ID=256 注明），id_next 发满 255 后**回绕复用**。
- 后果：alarm.v:15 注释声称"轨迹死亡后 id 不复用，不会串档"——**注释是假的**。id 回绕后，新轨迹撞上 alarm 里 seen[id]=1 的旧记忆 + 陈旧 prev_cx → 可能凭空报越界 / 漏报停留。
- 触发估算：每秒出现 5 个新轨迹 → **约 51 秒烧完 255 个 id**。实机演示跑几分钟必然进入回绕区。
- 修法归属：track/alarm 属线二（徐一夫）+ 涉 I3 接口冻结（id 宽度）。候选：① tr_id 扩 16 位（动 I3，需共决）② alarm 加"超时遗忘"（只动 alarm.v）③ 比赛演示限时规避（文档声明）。**本次未改码，等线二拍板。**

### A2. uart_tx @720p60 + 16 目标满配 = 系统性丢包（严重度：中·满配演示必现）
- 算账：1280×720@60Hz，UART 115200-8N1 → 每帧预算 192 字节；16 目标载荷 = 帧头 5B + 16×14B = 229B（还没算事件包）。
- 后果：**每帧净欠 ~37B，256B FIFO 约 6 帧灌满，之后帧帧丢包**。drop 有粘存进 STATUS（不算静默），但"16 目标满配回传必丢"未在文档声明为已知限制。
- 附带：drop 丢弃发生在包中间 → **撕包**（半个 0xA5 包进流），PC 端按 MAGIC 重同步有脏数据风险。
- 修法候选：① 波特率提 921600（BAUD_DIV 参数现成，PC 端同步改）② 数据通路限 30fps ③ 文档声明限制。改动小，但同样属线二/线三接口约定（协议 §4）。

## 良性备注（不用改，写下来防以后误判）

- track.v:110 `c_hit 8'hFF 哨兵`：存的是轨迹**下标**（0..15），永远撞不到 255 → **安全**（与 multi_bbox 撞码同形但不同病，因为容量远小于 2^位宽-1）。
- track.v:137/158 `tr_seen/tr_miss 16'hFFFF 饱和`：dwell 到 65535 帧冻结（30fps 下 ~36 分钟）→ 仅显示值停摆，无逻辑危害。
- bbox.v:79 `n 饱和 16'hFFFF`：单帧 >65535 大像素才触发（全屏运动边缘场景），cnt 显示不准但 valid 判定正确 → 良性。
- overlay_multi.v:114 `w_idx 无越界守卫`：上游 multi_bbox/track 都封顶 16，写不越界；但链路脆弱（将来谁改了上游限制就会静默越界写），建议以后加一行守卫。
- bbox.v:52 首样本误判 new_frame：复位后首帧结算一次空框（valid=0），无害。

## 扫过没问题的

multi_bbox（今日已修 2 处）、bbox、diff_stage、threshold、morph3x3、morph_open、downsample2x2、frame_buf、video_timing、pattern_gen、gray_conv、hdmi_in_ctrl、clock_74m25、clock_200m、regs、axi_lite_slave、board_top（rst_cnt 4'hF 用满 16 态、无撞码）、bbox_snapshot（ack 已修）、overlay（单目标版）、md_pipeline 编排层。

## 处置建议

A1/A2 都不动综合链主数据通路，不阻塞当前构建与 bit；建议 16-bit 出片验收后，由线二拍板修法、线三补台（id 回绕压测 / 高波特率回传测试），再进下一轮 bit。比赛材料里"已知限制"一节必须写 A2（不写就是注释撒谎同罪）。
