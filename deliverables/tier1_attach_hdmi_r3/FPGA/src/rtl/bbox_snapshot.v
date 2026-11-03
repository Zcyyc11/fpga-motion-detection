`timescale 1ns / 1ps
// bbox_snapshot：目标结果及所属帧号的跨时钟快照。
// 像素时钟域锁存一组结果，通过请求/应答握手传递到 AXI 时钟域。
// 握手完成前保持源数据不变；控制信号使用两级同步器。
// 告警事件按帧锁存，并与目标快照一起传递。
module bbox_snapshot #(
    parameter integer ALARM_CLEAR_DELAY = 128, // legacy standalone clients
    parameter integer EXPLICIT_ALARM_CLEAR = 0
)(
    // 像素钟域
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
    input  wire        i_alarm_clear,    // Tracker window start, independent of publication
    // AXI 钟域
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

    // 像素钟域：帧级粘存 + 快照锁存

    reg        alarm_frame;      // 「本帧发生过告警」粘存
    reg [31:0] alarm_clr_cnt;    // 清除延迟计数
    reg        alarm_clr_armed;  // 锁存拍后启动清除窗口

    always @(posedge clk_px or negedge rst_n_px) begin
        if (!rst_n_px) begin
            alarm_frame     <= 1'b0;
            alarm_clr_cnt   <= 32'd0;
            alarm_clr_armed <= 1'b0;
        end else if(EXPLICIT_ALARM_CLEAR)begin
            // Even rejected/unpublished windows must not leak alarm to the next.
            if(i_alarm_clear)alarm_frame<=1'b0;
            else if(i_alarm_pulse)alarm_frame<=1'b1;
            alarm_clr_armed<=0;alarm_clr_cnt<=0;
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
    reg         ack;         // AXI 钟域：ack 跟随同步后的 req（声明须先于使用，xvlog 要求）

    // ack 的两级同步（AXI 钟 → 像素钟）
    (* ASYNC_REG = "TRUE" *) reg [1:0] ack_sync_ff;
    wire      idle = (req == ack_sync_ff[1]);   // 上次握手完成才可改数据

    always @(posedge clk_px or negedge rst_n_px) begin
        if (!rst_n_px) begin
            snap_hold <= 118'd0;
            req       <= 1'b0;
            ack_sync_ff <= 2'b00;
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

    // AXI 钟域：同步 + 整组采样

    (* ASYNC_REG = "TRUE" *) reg [1:0] req_sync_ff;   // req 的两级同步

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
