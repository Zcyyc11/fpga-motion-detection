`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// gray_conv —— 线二任务：灰度转换模块（接 HDMI 输入要用）
//
// 作用：HDMI 摄像头画面（I1 视频流总线，RGB888）进来后转成 8bit 灰度，
//   再交给 downsample2x2 做 2×2 求和压缩。此前仓库没有这个模块
//   （旧的 gray.v 已于 2026-10-06 移出，见 src/rtl/README.md 对应表），
//   接 HDMI 输入时由本模块补位。
//
// 公式：BT.601 整数近似（文档口径「不难」）：
//   gray = (77*R + 150*G + 29*B) >> 8
//   系数和 = 256，右移 8 位即可；最大值 255*256 = 65280 < 2^16，不会溢出。
//   与浮点 0.299/0.587/0.114 的最大偏差 < 1 个灰阶，检测场景完全够用。
//
// 时序：两级流水（乘加一级、截位一级），de/hsync/vsync/x/y 用同深度的
//   打拍链对齐 —— 下游拿到的 gray 与坐标是同一拍的，不用自己补延迟。
//
// 注意：本模块是**纯 RGB→灰度**，不关心同步时序本身；
//   输入側的时序对齐（dvi2rgb → 本模块）由线一的 HDMI 输入侧负责。
// -----------------------------------------------------------------------------
module gray_conv (
    input  wire        clk,
    input  wire        rst_n,
    // I1 视频流总线输入（RGB888）
    input  wire        in_de,
    input  wire        in_hsync,
    input  wire        in_vsync,
    input  wire [15:0] in_x,
    input  wire [15:0] in_y,
    input  wire [23:0] in_rgb,       // R[23:16] / G[15:8] / B[7:0]
    // 灰度输出（与输入同频率的流，流水线延迟固定 2 拍）
    output reg         out_de,
    output reg         out_hsync,
    output reg         out_vsync,
    output reg  [15:0] out_x,
    output reg  [15:0] out_y,
    output reg  [7:0]  out_gray
);

    // ---- 第 1 拍：乘加 ----
    reg         s1_de, s1_hsync, s1_vsync;
    reg  [15:0] s1_x, s1_y;
    reg  [15:0] s1_sum;               // 77R + 150G + 29B，最大 65280

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_de <= 1'b0; s1_hsync <= 1'b0; s1_vsync <= 1'b0;
            s1_x <= 16'd0; s1_y <= 16'd0; s1_sum <= 16'd0;
        end else begin
            s1_de    <= in_de;
            s1_hsync <= in_hsync;
            s1_vsync <= in_vsync;
            s1_x     <= in_x;
            s1_y     <= in_y;
            s1_sum   <= in_rgb[23:16] * 16'd77
                      + in_rgb[15:8]  * 16'd150
                      + in_rgb[7:0]   * 16'd29;
        end
    end

    // ---- 第 2 拍：截位输出 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_de <= 1'b0; out_hsync <= 1'b0; out_vsync <= 1'b0;
            out_x <= 16'd0; out_y <= 16'd0; out_gray <= 8'd0;
        end else begin
            out_de    <= s1_de;
            out_hsync <= s1_hsync;
            out_vsync <= s1_vsync;
            out_x     <= s1_x;
            out_y     <= s1_y;
            out_gray  <= s1_sum[15:8];   // >> 8
        end
    end

endmodule
