`timescale 1ns / 1ps
// bbox：统计一帧全部前景像素的并集包围盒。
// 比较器求极值的实现参考原项目材料中的“参考作品 #1”。
// 命中像素数达到 MIN_CNT 时结果有效；不进行连通域分离。
// in_y 回绕触发上一帧结果发布。输入和输出均使用 2×2 大像素坐标。
module bbox #(
    parameter integer MIN_CNT = 64
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [15:0] in_x,
    input  wire [15:0] in_y,
    input  wire        in_mask,
    output reg  [15:0] x1,
    output reg  [15:0] y1,
    output reg  [15:0] x2,
    output reg  [15:0] y2,
    output reg  [15:0] cnt,
    output reg         valid
);

    localparam [15:0] BIG = 16'hFFFF;

    reg [15:0] mnx, mny, mxx, mxy, n;
    reg [15:0] py;                                  // 上一个有效样本的 y

    wire new_frame = in_valid && (in_y < py);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mnx <= BIG; mny <= BIG; mxx <= 16'd0; mxy <= 16'd0; n <= 16'd0;
            x1 <= 16'd0; y1 <= 16'd0; x2 <= 16'd0; y2 <= 16'd0;
            cnt <= 16'd0; valid <= 1'b0;
            py  <= BIG;
        end else begin
            py <= in_valid ? in_y : py;

            if (new_frame) begin
                // 结算上一帧
                x1 <= mnx; y1 <= mny; x2 <= mxx; y2 <= mxy;
                cnt   <= n;
                valid <= (n >= MIN_CNT[15:0]) && (mnx <= mxx) && (mny <= mxy);
                // 复位累加器
                // Retain the first sample of the new frame while publishing the old one.
                mnx <= in_mask ? in_x : BIG; mny <= in_mask ? in_y : BIG;
                mxx <= in_mask ? in_x : 16'd0; mxy <= in_mask ? in_y : 16'd0;
                n <= in_mask ? 16'd1 : 16'd0;
            end else if (in_valid && in_mask) begin
                if (in_x < mnx) mnx <= in_x;
                if (in_x > mxx) mxx <= in_x;
                if (in_y < mny) mny <= in_y;
                if (in_y > mxy) mxy <= in_y;
                // Saturate the published 16-bit count; wrapping can suppress valid targets.
                if (n != 16'hFFFF) n <= n + 16'd1;
            end
        end
    end

endmodule
