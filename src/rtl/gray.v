`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// gray —— 五步链的第 1 步：彩色转灰度（只在 HDMI 输入通路上用）。
//
// 为什么必须有这一步：PC 端参考实现是 cv2.cvtColor(frame, COLOR_BGR2GRAY)，
// 后面所有算子都工作在单通道 8bit 上。HDMI 进来的是 R/G/B 三路 8bit，
// 不在同一口径上就没法做「同一段输入、同一分辨率」的对照。
//
// 系数用整数近似（BT.601）：Y ≈ (77·R + 150·G + 29·B) / 256
//   三个乘数都是小常数，综合成移位加法器，不需要 DSP。
//   除以 256 = 右移 8 位，不用除法器。
//   cv2 实际用的是定点系数 0.299/0.587/0.114 的 15bit 版本，
//   两者最大差 1 个灰阶 —— 报告里作为「量化误差」写出来，别写成零误差。
//
// 内部合成图案（pattern_gen）输出的是 R=G=B，走本模块结果不变，
// 所以自测模式下这条通路的误差为零。
// -----------------------------------------------------------------------------
module gray (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       in_valid,
    input  wire [7:0] r,
    input  wire [7:0] g,
    input  wire [7:0] b,
    output reg        out_valid,
    output reg  [7:0] y
);

    wire [15:0] sum = r * 16'd77 + g * 16'd150 + b * 16'd29;   // 最大 255*256=65280

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            y         <= 8'd0;
        end else begin
            out_valid <= in_valid;
            y         <= sum[15:8];
        end
    end

endmodule
