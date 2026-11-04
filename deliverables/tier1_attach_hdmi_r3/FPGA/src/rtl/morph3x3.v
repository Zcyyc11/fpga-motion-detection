`timescale 1ns / 1ps
// morph3x3：流式 3×3 二值滤波。
// OP=0 为腐蚀，OP=1 为膨胀，OP=2 为至少 5/9 票的多数滤波。
// 窗口仅随 in_valid 推进；以 in_y 变化轮转行缓冲，相位在行首组合更新。
// 换帧使旧行数据失效，缺失邻域取零。
// 当 in_x>=2 且 in_y>=2 时输出窗口中心坐标 (in_x-1,in_y-1)。
module morph3x3 #(
    parameter integer W  = 640,      // 一行的大像素个数 BW
    parameter integer OP = 0         // 0=erode, 1=dilate, 2=majority (at least 5/9)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [15:0] in_x,
    input  wire [15:0] in_y,
    input  wire        in_mask,
    output reg         out_valid,
    output reg  [15:0] out_x,
    output reg  [15:0] out_y,
    output reg         out_mask
);

    // 行缓冲：3 相位轮转；rv 记录各相位是否已经写过（换帧作废）
    reg       mem [0:2][0:W-1];
    reg [1:0] ph;
    reg [2:0] rv;
    reg [15:0] py;
    reg seen_sample;

    wire row_start = in_valid && (!seen_sample || (in_y != py));
    wire new_frame = row_start && seen_sample && (in_y < py);

    // 本行的相位（在换行那一拍就组合地换成新值，保证该行第一个像素写对位置）
    wire [1:0] ph_cur = !seen_sample ? 2'd0 :
                       row_start ? ((ph == 2'd2) ? 2'd0 : (ph + 2'd1)) : ph;

    wire [1:0] phm1 = (ph_cur == 2'd0) ? 2'd2 : (ph_cur - 2'd1);   // y-1 行
    wire [1:0] phm2 = (ph_cur == 2'd2) ? 2'd0 : (ph_cur + 2'd1);   // y-2 行

    wire r1 = !new_frame && rv[phm1] ? mem[phm1][in_x] : 1'b0;
    wire r2 = !new_frame && rv[phm2] ? mem[phm2][in_x] : 1'b0;

    // 每行的两级列延迟
    reg d1, d2;                     // 当前行：x-1, x-2
    reg a1, a2;                     // y-1 行：x-1, x-2
    reg b1, b2;                     // y-2 行：x-1, x-2

    wire v_cur = OP ? (d2 | d1 | in_mask) : (d2 & d1 & in_mask);
    wire v_p1  = OP ? (a2 | a1 | r1)      : (a2 & a1 & r1);
    wire v_p2  = OP ? (b2 | b1 | r2)      : (b2 & b1 & r2);
    wire [3:0] votes = {3'b0,d2}+{3'b0,d1}+{3'b0,in_mask}
                     +{3'b0,a2}+{3'b0,a1}+{3'b0,r1}
                     +{3'b0,b2}+{3'b0,b1}+{3'b0,r2};
    wire res   = (OP==2) ? (votes>=4'd5) :
                 (OP==1) ? (v_cur | v_p1 | v_p2) : (v_cur & v_p1 & v_p2);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ph <= 2'd0;  rv <= 3'b000;  py <= 16'd0;
            seen_sample <= 1'b0;
            d1 <= 1'b0;  d2 <= 1'b0;
            a1 <= 1'b0;  a2 <= 1'b0;
            b1 <= 1'b0;  b2 <= 1'b0;
            out_valid <= 1'b0;
            out_mask  <= 1'b0;
            out_x     <= 16'd0;
            out_y     <= 16'd0;
        end else begin
            out_valid <= 1'b0;
            if (in_valid) begin
                seen_sample <= 1'b1;
                // 写当前行（用组合后的相位，保证该行首像素也落在正确相位）
                mem[ph_cur][in_x] <= in_mask;

                if (row_start) begin
                    py <= in_y;
                    ph <= ph_cur;
                    if (new_frame) rv <= 3'b000;      // 换帧：行缓冲作废（帧外当 0）
                    rv[ph_cur] <= 1'b1;               // 本相位开始有数据
                end

                // 列延迟（按样本推进）
                // 每行首将缺失的左邻样本置零。第二级从 x=1 开始，
                // 不清零会把上一行末列带入下一行 x=1 的窗口。
                d2 <= row_start ? 1'b0 : d1;  d1 <= in_mask;
                a2 <= row_start ? 1'b0 : a1;  a1 <= r1;
                b2 <= row_start ? 1'b0 : b1;  b1 <= r2;

                if ((in_x >= 16'd2) && (in_y >= 16'd2)) begin
                    out_mask  <= res;
                    out_x     <= in_x - 16'd1;
                    out_y     <= in_y - 16'd1;
                    out_valid <= 1'b1;
                end
            end
        end
    end

endmodule
