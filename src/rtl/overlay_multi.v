`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// overlay_multi —— 多目标 OSD：把 multi_bbox 的串行目标元数据画回画面。
//
// ★ 为什么需要它：overlay.v 只画一个框（bbox.v 全局并集框）。
//   multi_bbox 每帧输出最多 MAX_TARGET 个目标（串行逐目标一拍），
//   本模块先把它们收进「目标表」，再对每个像素判断是否落在任一目标框边上。
//
// ★ 双缓冲（active / shadow）：
//   - shadow 表：接收 multi_bbox 串行输出（t_valid 写、t_last 收尾）；
//   - 掩码流帧边界（f_edge = 检测域 y 回绕）时整体发布：active ← shadow；
//   - 画框用 active 表（描述**上一帧**结果，与 bbox.v 行为一致，滞后一帧）。
//   为什么要双份：multi_bbox 的结算输出与下一帧掩码处理同拍并行，
//   单份表会出现「正在画的表被新帧覆盖」；双缓冲保证发布是原子的。
//
// ★ 坐标：multi_bbox 输出大像素坐标（I2），表内存原值；
//   画框比较时 ×2 转像素坐标（与 md_pipeline 里旧 overlay 的 <<1 相同）。
//
// ★ 状态灯（与 overlay.v 相同）：左上角 LAMP×LAMP，
//   绿 = 上一帧检测到目标（a_n != 0），暗灰 = 空闲。
//
// ★ 检测结果端口（o_x1..o_obj_count）：帧边界更新、描述上一帧，
//   语义与 bbox.v 的 x1/y1/x2/y2/valid 对齐 —— 首目标坐标 + 目标数，
//   供 LED / BBOX 快照 / 回传协议消费（大像素坐标）。
// -----------------------------------------------------------------------------
module overlay_multi #(
    parameter integer MAX_TARGET = 16,   // 一帧最多目标数（与 multi_bbox MAX_LABEL 对齐）
    parameter integer THICK = 2,         // 边框宽度（像素）
    parameter integer LAMP  = 16,        // 状态灯边长（像素）
    parameter integer LAMP_X = 8,        // 状态灯左上角 x
    parameter integer LAMP_Y = 8         // 状态灯左上角 y
)(
    input  wire        clk,
    input  wire        rst_n,
    // ---- 视频像素流（像素坐标）----
    input  wire        de,
    input  wire [15:0] x,
    input  wire [15:0] y,
    input  wire [7:0]  gray,
    // ---- 掩码流帧边界（检测域 y 回绕 = multi_bbox 结算拍）----
    input  wire        f_edge,
    // ---- multi_bbox 串行目标元数据（大像素坐标）----
    input  wire        t_valid,
    input  wire [15:0] t_x1,
    input  wire [15:0] t_y1,
    input  wire [15:0] t_x2,
    input  wire [15:0] t_y2,
    input  wire [15:0] t_cnt,
    input  wire        t_last,
    // ---- 叠加输出 ----
    output wire [7:0]  r,
    output wire [7:0]  g,
    output wire [7:0]  b,
    // ---- 检测结果（帧边界更新，描述上一帧；大像素坐标；首目标 + 目标数）----
    output reg  [15:0] o_x1,
    output reg  [15:0] o_y1,
    output reg  [15:0] o_x2,
    output reg  [15:0] o_y2,
    output reg  [15:0] o_cnt,
    output reg         o_valid,
    output reg  [7:0]  o_obj_count
);

    localparam IW = $clog2(MAX_TARGET);   // 4（0..15 目标）+ 1 位进位 = 5bit 计数

    // ---------------- 双缓冲目标表 ----------------
    reg [15:0] a_x1 [0:MAX_TARGET-1];
    reg [15:0] a_y1 [0:MAX_TARGET-1];
    reg [15:0] a_x2 [0:MAX_TARGET-1];
    reg [15:0] a_y2 [0:MAX_TARGET-1];
    reg [15:0] a_cnt[0:MAX_TARGET-1];
    reg [IW:0] a_n;                       // active 目标数

    reg [15:0] s_x1 [0:MAX_TARGET-1];
    reg [15:0] s_y1 [0:MAX_TARGET-1];
    reg [15:0] s_x2 [0:MAX_TARGET-1];
    reg [15:0] s_y2 [0:MAX_TARGET-1];
    reg [15:0] s_cnt[0:MAX_TARGET-1];
    reg [IW:0] s_n;                       // shadow 目标数（t_last 时定稿）
    reg [IW:0] w_idx;                     // shadow 写入游标

    integer k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_n <= 0; s_n <= 0; w_idx <= 0;
            for (k = 0; k < MAX_TARGET; k = k + 1) begin
                a_x1[k] <= 16'd0; a_y1[k] <= 16'd0; a_x2[k] <= 16'd0; a_y2[k] <= 16'd0; a_cnt[k] <= 16'd0;
                s_x1[k] <= 16'd0; s_y1[k] <= 16'd0; s_x2[k] <= 16'd0; s_y2[k] <= 16'd0; s_cnt[k] <= 16'd0;
            end
            o_x1 <= 16'd0; o_y1 <= 16'd0; o_x2 <= 16'd0; o_y2 <= 16'd0; o_cnt <= 16'd0;
            o_valid <= 1'b0; o_obj_count <= 8'd0;
        end else begin
            if (f_edge) begin
                // 发布：active ← shadow（非阻塞 RHS 读旧值，同拍 t_valid 写 shadow 新值无冲突）
                a_n <= s_n;
                for (k = 0; k < MAX_TARGET; k = k + 1) begin
                    a_x1[k] <= s_x1[k]; a_y1[k] <= s_y1[k];
                    a_x2[k] <= s_x2[k]; a_y2[k] <= s_y2[k];
                    a_cnt[k] <= s_cnt[k];
                    s_x1[k] <= 16'd0; s_y1[k] <= 16'd0;
                    s_x2[k] <= 16'd0; s_y2[k] <= 16'd0; s_cnt[k] <= 16'd0;
                end
                s_n <= 0; w_idx <= 0;
                // 检测结果端口：帧边界更新（描述上一帧）
                o_x1 <= s_x1[0]; o_y1 <= s_y1[0]; o_x2 <= s_x2[0]; o_y2 <= s_y2[0];
                o_cnt <= s_cnt[0];
                o_valid <= (s_n != 0);
                o_obj_count <= s_n;   // 5bit → 8bit 零扩展
            end else if (t_valid) begin
                s_x1[w_idx] <= t_x1; s_y1[w_idx] <= t_y1;
                s_x2[w_idx] <= t_x2; s_y2[w_idx] <= t_y2;
                s_cnt[w_idx] <= t_cnt;
                w_idx <= w_idx + 1'b1;
                if (t_last) s_n <= w_idx + 1'b1;
            end
        end
    end

    // ---------------- 画框（组合）：任一目标框边 → 红 ----------------
    reg on_box;
    always @* begin
        on_box = 1'b0;
        for (k = 0; k < MAX_TARGET; k = k + 1) begin
            if (k < a_n) begin
                if ((x >= {a_x1[k][14:0], 1'b0}) && (x <= {a_x2[k][14:0], 1'b0}) &&
                    (y >= {a_y1[k][14:0], 1'b0}) && (y <= {a_y2[k][14:0], 1'b0})) begin
                    if ((x < {a_x1[k][14:0], 1'b0} + THICK[15:0]) ||
                        (x + THICK[15:0] > {a_x2[k][14:0], 1'b0}) ||
                        (y < {a_y1[k][14:0], 1'b0} + THICK[15:0]) ||
                        (y + THICK[15:0] > {a_y2[k][14:0], 1'b0}))
                        on_box = 1'b1;
                end
            end
        end
    end

    // ---------------- 状态灯（左上角，绿=检出 / 暗灰=空闲）----------------
    wire on_lamp = (x >= LAMP_X[15:0]) && (x < LAMP_X[15:0] + LAMP[15:0]) &&
                   (y >= LAMP_Y[15:0]) && (y < LAMP_Y[15:0] + LAMP[15:0]);

    assign r = on_box ? 8'hFF : (on_lamp ? (a_n != 0 ? 8'h00 : 8'h28) : gray);
    assign g = on_box ? 8'h00 : (on_lamp ? (a_n != 0 ? 8'hFF : 8'h28) : gray);
    assign b = on_box ? 8'h00 : (on_lamp ? (a_n != 0 ? 8'h00 : 8'h28) : gray);

endmodule
