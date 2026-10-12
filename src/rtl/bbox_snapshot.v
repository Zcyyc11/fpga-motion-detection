`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// bbox_snapshot —— bbox 快照寄存器组 + 像素钟 → AXI 钟 CDC（10/13 交付核心件）
//
// 解决两个问题（线三硬要求①②，见 docs/line1_uart_field_table_draft.md）：
//   ① 快照必须「连同所属帧号一起锁存」：bbox.v 在帧边界更新 x1..valid，但不锁
//      帧号；本模块在 i_latch 拍把 bbox 输出与 i_frame_idx 同拍锁成一组快照，
//      PS 侧读到的 (BBOX_*, BBOX_FRAME) 永远是同一帧的，不存在撕裂组合。
//   ② 跨时钟读必须「整帧快照一致」：像素钟域锁存 → 四段握手 CDC → AXI 钟域
//      稳定副本。像素钟域只在「上次握手完成」（req==ack 同步回）后才允许
//      下一次锁存改数据，因此 AXI 侧采样期间数据必然整帧不变；
//      跨钟控制线全部两级同步器打两拍。
//
// STATUS 帧级粘存（方案 A，线一已确认）：
//   i_alarm_pulse 是 alarm.v 的单拍事件脉冲——PS 轮询 MMIO 读不到。
//   本模块在像素钟域维护 alarm_frame：「帧内任一告警」粘存，i_latch 后延迟
//   ALARM_CLEAR_DELAY 拍清零（窗口须覆盖 frame_tick 后 track→alarm 的发出
//   时序；74MHz 下 128 拍 < 2µs，远小于帧周期，安全）。粘存值随快照一起
//   过钟，PS 读 STATUS bit1 = 「快照所属帧内是否发生过告警」，
//   与 BBOX_FRAME 同源，可交叉校验。
//
// 顶层接入（md_pipeline 由线一接，见 docs/line2_integration_guide.md）：
//   i_x1..i_valid ← bbox.v 同名输出；i_latch ← 掩码流 y 回绕拍（与 bbox.v
//   帧边界同判据 in_y<in_py，由顶层生成）；i_frame_idx ← md_pipeline.frame_idx；
//   i_obj_count ← multi_bbox 帧结算目标数；clk_axi ← AXI-Lite 时钟。
// -----------------------------------------------------------------------------
module bbox_snapshot #(
    parameter integer ALARM_CLEAR_DELAY = 128  // 告警粘存清除延迟（像素钟拍）
)(
    // ---- 像素钟域 ----
    input  wire        clk_px,
    input  wire        rst_n_px,
    // bbox.v 输出（帧边界更新一次，描述上一帧）
    input  wire [15:0] i_x1, i_y1, i_x2, i_y2, i_cnt,
    input  wire        i_valid,
    // 同拍锁进的帧号 / 目标数 / 告警
    input  wire [15:0] i_frame_idx,
    input  wire [7:0]  i_obj_count,
    input  wire        i_alarm_pulse,    // alarm.v 事件脉冲（单拍）
    // 快照锁存拍：帧边界 1 拍脉冲（顶层生成，与 bbox 帧边界同判据）
    input  wire        i_latch,
    // ---- AXI 钟域 ----
    input  wire        clk_axi,
    input  wire        rst_n_axi,
    // 稳定副本（AXI 钟域，帧内任意多拍读值不变）
    output reg  [15:0] o_x1, o_y1, o_x2, o_y2, o_cnt,
    output reg         o_valid,
    output reg  [15:0] o_frame,
    output reg  [7:0]  o_obj_count,
    output reg         o_b_valid,
    output reg         o_alarm
);

    // ================ 像素钟域：帧级粘存 + 快照锁存 ================

    reg        alarm_frame;      // 「本帧发生过告警」粘存
    reg [31:0] alarm_clr_cnt;    // 清除延迟计数
    reg        alarm_clr_armed;  // 锁存拍后启动清除窗口

    always @(posedge clk_px or negedge rst_n_px) begin
        if (!rst_n_px) begin
            alarm_frame     <= 1'b0;
            alarm_clr_cnt   <= 32'd0;
            alarm_clr_armed <= 1'b0;
        end else begin
            if (i_alarm_pulse)
                alarm_frame <= 1'b1;
            // 锁存拍：粘存值本拍已进锁存总线；随后启动清除窗口，
            // 窗口足够 track/alarm 输出在本帧边界后发完
            if (i_latch) begin
                alarm_clr_armed <= 1'b1;
                alarm_clr_cnt   <= 32'd0;
            end else if (alarm_clr_armed) begin
                if (alarm_clr_cnt >= ALARM_CLEAR_DELAY - 1) begin
                    alarm_frame     <= 1'b0;
                    alarm_clr_armed <= 1'b0;
                end else
                    alarm_clr_cnt <= alarm_clr_cnt + 32'd1;
            end
        end
    end

    // 快照总线（118 bit，与 AXI 侧解包顺序严格一致）
    wire [117:0] snap_bus = {i_x1, i_y1, i_x2, i_y2, i_cnt, i_valid,
                             i_frame_idx, i_obj_count,
                             i_valid /* b_valid 与单框链同源 */,
                             alarm_frame};

    reg [117:0] snap_hold;   // 握手期间保持不变的快照
    reg         req;         // toggle 请求

    // ack 的两级同步（AXI 钟 → 像素钟）
    reg [1:0] ack_sync_ff;
    wire      idle = (req == ack_sync_ff[1]);   // 上次握手完成才可改数据

    always @(posedge clk_px or negedge rst_n_px) begin
        if (!rst_n_px) begin
            snap_hold <= 118'd0;
            req       <= 1'b0;
        end else begin
            ack_sync_ff <= {ack_sync_ff[0], ack};
            if (i_latch && idle) begin
                snap_hold <= snap_bus;
                req       <= ~req;             // 请求 AXI 侧取数
            end
            // i_latch 到来但握手未完成：本次快照不更新（30/60fps 下握手仅
            // 几个 AXI 钟，实际不会发生；真发生也只是副本多留一帧旧数据）
        end
    end

    // ================ AXI 钟域：同步 + 整组采样 ================

    reg [1:0] req_sync_ff;   // req 的两级同步
    reg       ack;           // ack 跟随同步后的 req

    always @(posedge clk_axi or negedge rst_n_axi)
        if (!rst_n_axi) req_sync_ff <= 2'b00;
        else            req_sync_ff <= {req_sync_ff[0], req};

    always @(posedge clk_axi or negedge rst_n_axi)
        if (!rst_n_axi) ack <= 1'b0;
        else            ack <= req_sync_ff[1];

    // req 同步值 != ack → req 刚翻转，数据在 snap_hold 中已稳定，整组采样
    wire update = (req_sync_ff[1] != ack);

    always @(posedge clk_axi or negedge rst_n_axi) begin
        if (!rst_n_axi) begin
            o_x1 <= 16'd0; o_y1 <= 16'd0; o_x2 <= 16'd0; o_y2 <= 16'd0;
            o_cnt <= 16'd0; o_valid <= 1'b0; o_frame <= 16'd0;
            o_obj_count <= 8'd0; o_b_valid <= 1'b0; o_alarm <= 1'b0;
        end else if (update) begin
            {o_x1, o_y1, o_x2, o_y2, o_cnt, o_valid,
             o_frame, o_obj_count, o_b_valid, o_alarm} <= snap_hold;
        end
    end

endmodule
