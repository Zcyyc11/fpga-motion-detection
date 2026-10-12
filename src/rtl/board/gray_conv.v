`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// gray_conv —— 24bit RGB → 8bit 灰度（HDMI 输入通路的一步）
//
// 灰度公式不是拍的，是标准：ITU-R BT.601 亮度方程
//     Y = 0.299 R + 0.587 G + 0.114 B
// 整数化（避免浮点，FPGA 全定点）：
//     Y = (77 R + 150 G + 29 B) >> 8
// 系数核对：77/256=0.3008  150/256=0.5859  29/256=0.1133  误差 < 0.002
//
// ★ 打包陷阱：dvi2rgb 的 vid_pData 是 **RBG** 打包，不是 RGB！
//   官方文档 5 章端口表原文："Video pixel data packed as RBG."
//     [23:16] = R，[15:8] = B，[7:0] = G
//   所以 G 在低 8 位、B 在中间 8 位 —— 接反了灰度会明显偏色（这版看不出，
//   但背景建模的 α 更新会吃掉错误信息）。这里按 RBG 解包，写进注释防误改。
//
// 流水线风格：输入打 1 拍输出，o_* 与 gray 严格同拍（下游 downsample2x2
// 需要 vde/x/y/pixel 同拍，和 pattern_gen 的输出语义一致）。
// -----------------------------------------------------------------------------
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
