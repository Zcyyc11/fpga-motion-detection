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
//
// ★ 2026-10-12 线二接入改动：THRESH 由编译期参数改为**运行时输入端口**
//   （阈值来自 regs 寄存器堆 0x00，PS 运行时可改，见接口冻结表 I4 与
//   docs/line2_integration_guide.md §1.3）。仅实例化方（md_pipeline）与 tb_contracts 需要
//   同步改动；比较语义不变。输入 16 位，实际与 absdiff（11 位）比较取低 10 位。
// -----------------------------------------------------------------------------
module threshold (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] thresh,        // 运行时阈值（2×2 和域；来自 regs 0x00）
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
            mask      <= (absdiff > thresh[10:0]);
        end
    end

endmodule
