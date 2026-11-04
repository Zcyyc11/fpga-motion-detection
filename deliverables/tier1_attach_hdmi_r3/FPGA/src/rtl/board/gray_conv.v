`timescale 1ns / 1ps
// gray_conv：将 dvi2rgb 的 24 位 RBG 数据转换为 8 位灰度。
// 采用 ITU-R BT.601 亮度系数的整数近似：Y=(77R+150G+29B)>>8。
// 按 Digilent dvi2rgb 端口定义解包：[23:16]=R、[15:8]=B、[7:0]=G。
// 灰度、坐标和有效信号同步寄存一拍。
module gray_conv (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vde,          // 上游整理后的数据有效（hdmi_in_ctrl 输出）
    input  wire [15:0] x,
    input  wire [15:0] y,
    input  wire [23:0] pix_in,       // RBG 打包：[23:16]=R [15:8]=B [7:0]=G
    output reg         o_vde,
    output reg  [15:0] o_x,
    output reg  [15:0] o_y,
    output reg  [7:0]  gray
);

    // 16bit 和：77*255 + 150*255 + 29*255 = 65280 < 65536，无溢出
    wire [15:0] sum =
         16'd77  * {8'd0, pix_in[23:16]}   // R
       + 16'd150 * {8'd0, pix_in[7:0]}     // G（低 8 位！）
       + 16'd29  * {8'd0, pix_in[15:8]};   // B（中间 8 位！）

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_vde <= 1'b0;
            o_x   <= 16'd0;
            o_y   <= 16'd0;
            gray  <= 8'd0;
        end else begin
            o_vde <= vde;
            o_x   <= x;
            o_y   <= y;
            gray  <= sum[15:8];
        end
    end

endmodule
