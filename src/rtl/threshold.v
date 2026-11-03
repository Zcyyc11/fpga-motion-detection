`timescale 1ns / 1ps
// threshold：对差分绝对值执行严格大于阈值的二值分割。
// thresh 使用 2×2 求和域量纲；以完整 16 位阈值与零扩展差分比较。
// 原项目的默认值 70 参考“参考作品 #1”，当前阈值由输入端口提供。
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
            mask      <= ({5'd0, absdiff} > thresh);
        end
    end

endmodule
