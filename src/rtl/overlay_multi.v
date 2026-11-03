`timescale 1ns / 1ps
// overlay_multi：接收串行目标元数据并叠加多个边框。
// shadow 表接收一批目标，t_done 标记批次完成（包括空批）。
// 图像帧首 f_edge 将完整批次发布到 active 表，帧内保持显示结果稳定。
// 大像素闭区间 [x1,x2] 映射为原图闭区间 [2*x1,2*x2+1]，y 同理。
// 结果端口提供当前显示批次的首目标坐标、计数及目标总数。
module overlay_multi #(
    parameter integer MAX_TARGET = 16,   // 一帧最多目标数（与 multi_bbox MAX_LABEL 对齐）
    parameter integer THICK = 2,         // 边框宽度（像素）
    parameter integer LAMP  = 16,        // 状态灯边长（像素）
    parameter integer LAMP_X = 8,        // 状态灯左上角 x
    parameter integer LAMP_Y = 8         // 状态灯左上角 y
)(
    input  wire        clk,
    input  wire        rst_n,
    // 视频像素流（像素坐标）
    input  wire        de,
    input  wire [15:0] x,
    input  wire [15:0] y,
    input  wire [7:0]  gray,
    // 图像帧首；只发布已经完成的 shadow，未完成时保持 active
    input  wire        f_edge,
    // multi_bbox 串行目标元数据（大像素坐标）
    input  wire        t_valid,
    input  wire [15:0] t_x1,
    input  wire [15:0] t_y1,
    input  wire [15:0] t_x2,
    input  wire [15:0] t_y2,
    input  wire [15:0] t_cnt,
    input  wire        t_last,
    input  wire        t_done,           // Explicit completion, including empty batches
    // 叠加输出
    output wire [7:0]  r,
    output wire [7:0]  g,
    output wire [7:0]  b,
    // 检测结果（帧边界更新，描述上一帧；大像素坐标；首目标 + 目标数）
    output reg  [15:0] o_x1,
    output reg  [15:0] o_y1,
    output reg  [15:0] o_x2,
    output reg  [15:0] o_y2,
    output reg  [15:0] o_cnt,
    output reg         o_valid,
    output reg  [7:0]  o_obj_count,
    output reg         o_published
);

    localparam IW = $clog2(MAX_TARGET);   // 4（0..15 目标）+ 1 位进位 = 5bit 计数

    // 双缓冲目标表
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
    reg [IW:0] s_n;                       // shadow 目标数（t_done 时定稿）
    reg [IW:0] w_idx;                     // shadow 写入游标
    reg s_ready;

    integer k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_n <= 0; s_n <= 0; w_idx <= 0;s_ready<=0;o_published<=0;
            for (k = 0; k < MAX_TARGET; k = k + 1) begin
                a_x1[k] <= 16'd0; a_y1[k] <= 16'd0; a_x2[k] <= 16'd0; a_y2[k] <= 16'd0; a_cnt[k] <= 16'd0;
                s_x1[k] <= 16'd0; s_y1[k] <= 16'd0; s_x2[k] <= 16'd0; s_y2[k] <= 16'd0; s_cnt[k] <= 16'd0;
            end
            o_x1 <= 16'd0; o_y1 <= 16'd0; o_x2 <= 16'd0; o_y2 <= 16'd0; o_cnt <= 16'd0;
            o_valid <= 1'b0; o_obj_count <= 8'd0;
        end else begin
            o_published<=0;
            if (f_edge && s_ready) begin
                // 发布：active ← shadow（非阻塞 RHS 读旧值，同拍 t_valid 写 shadow 新值无冲突）
                a_n <= s_n;
                for (k = 0; k < MAX_TARGET; k = k + 1) begin
                    a_x1[k] <= s_x1[k]; a_y1[k] <= s_y1[k];
                    a_x2[k] <= s_x2[k]; a_y2[k] <= s_y2[k];
                    a_cnt[k] <= s_cnt[k];
                end
                s_ready<=0;o_published<=1;
                // 检测结果端口：帧边界更新（描述上一帧）
                o_x1 <= s_n ? s_x1[0] : 0; o_y1 <= s_n ? s_y1[0] : 0;
                o_x2 <= s_n ? s_x2[0] : 0; o_y2 <= s_n ? s_y2[0] : 0;
                o_cnt <= s_n ? s_cnt[0] : 0;
                o_valid <= (s_n != 0);
                o_obj_count <= s_n;   // 5bit → 8bit 零扩展
            end
            if (t_valid && w_idx < MAX_TARGET) begin
                // If another batch arrives before publication, discard readiness
                // of the old batch. Never publish a partially overwritten table.
                s_ready<=0;
                s_x1[w_idx] <= t_x1; s_y1[w_idx] <= t_y1;
                s_x2[w_idx] <= t_x2; s_y2[w_idx] <= t_y2;
                s_cnt[w_idx] <= t_cnt;
                w_idx <= w_idx + 1'b1;
                if (t_last) s_n <= w_idx + 1'b1;
            end
            if(t_done)begin
                s_n<=t_valid ? w_idx+1'b1 : w_idx;s_ready<=1;w_idx<=0;
            end
        end
    end

    // 画框（组合）：任一目标框边 → 红
    reg on_box;
    always @* begin
        on_box = 1'b0;
        for (k = 0; k < MAX_TARGET; k = k + 1) begin
            if (k < a_n) begin
                if ((x >= {a_x1[k][14:0], 1'b0}) && (x <= {a_x2[k][14:0], 1'b1}) &&
                    (y >= {a_y1[k][14:0], 1'b0}) && (y <= {a_y2[k][14:0], 1'b1})) begin
                    if ((x < {a_x1[k][14:0], 1'b0} + THICK[15:0]) ||
                        (x + THICK[15:0] > {a_x2[k][14:0], 1'b1}) ||
                        (y < {a_y1[k][14:0], 1'b0} + THICK[15:0]) ||
                        (y + THICK[15:0] > {a_y2[k][14:0], 1'b1}))
                        on_box = 1'b1;
                end
            end
        end
    end

    // 状态灯（左上角，绿=检出 / 暗灰=空闲）
    wire on_lamp = (x >= LAMP_X[15:0]) && (x < LAMP_X[15:0] + LAMP[15:0]) &&
                   (y >= LAMP_Y[15:0]) && (y < LAMP_Y[15:0] + LAMP[15:0]);

    assign r = on_box ? 8'hFF : (on_lamp ? (a_n != 0 ? 8'h00 : 8'h28) : gray);
    assign g = on_box ? 8'h00 : (on_lamp ? (a_n != 0 ? 8'hFF : 8'h28) : gray);
    assign b = on_box ? 8'h00 : (on_lamp ? (a_n != 0 ? 8'h00 : 8'h28) : gray);

endmodule
