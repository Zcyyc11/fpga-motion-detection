`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// threshold —— 五步链的第 3 步：阈值分割。
//
// 阈值 70 不是我们拍的，是**照抄参考作品 #1 硬编码的那个值**，
// 目的是让「只换第 2 步」的对照尽量干净（详见 src/ps/algo_ab.py 注释）。
// ★ 注意量纲：这个 70 作用在 **2×2 和域** 上，不是 0..255 的灰阶，
//   ≈ 单像素 17.5 个灰阶。换成灰阶口径要除以 4，报告里别混写。
//
// 判断用严格大于（与 numpy 的 `np.abs(diff) > thresh` 一致）。
// -----------------------------------------------------------------------------
module threshold #(
    parameter integer THRESH = 69
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [10:0] absdiff,
    output reg         out_valid,
    output reg         mask
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            mask      <= 1'b0;
        end else begin
            out_valid <= in_valid;
            mask      <= (absdiff > THRESH[10:0]);
        end
    end

endmodule
