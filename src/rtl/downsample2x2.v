`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// downsample2x2 — 把 8bit 像素流按 2x2 求和压成 10bit「大像素」
//
// 为什么要压缩（对照参考作品与 PC 端 algo_ab.py）：
//   720p 灰度整帧 = 1280*720*8bit = 7.37 Mbit，片上 BRAM36 只有 140 块
//   （约 5.04 Mbit），一帧都存不下。按 2x2 求和 → 640x360x10bit = 2.30 Mbit，
//   约 64 块 BRAM36，放得下。
//   与 PC 端算法严格一致：compress2x2 = reshape(...).sum(axis=(1,3))，是**求和**
//   不是平均，所以 10bit（最大 4*255 = 1020）。
//
// 时序：一拍完成 —— 用组合读行缓冲拿「上一行同列」的像素，同拍写回当前行。
//       输出 valid / big_x / big_y / big_pixel 全部寄存一拍，四者严格对齐。
//
// 注意：只有 y 为奇数时才是 2x2 块的「下沿」（此时行缓冲里是上一行=块的上沿）；
//       x 为偶数列先暂存 col_sum，下一个奇数列才合成完整大像素。
//
// ★ 2026-10-16 修复（build16）：行缓冲的数组写为什么必须在独立 always 里
//   16 目标版全量综合 runme.log 实锤：line_buf（1280x8bit=10240 位）被 Vivado
//   拒绝映射 RAM，Synth 8-4767「Trying to implement RAM 'line_buf_reg' in
//   registers」整坨溶解成寄存器，日志给的原因 "RAM is sensitive to
//   asynchronous reset signal"；伴随 Synth 8-7137（Set/reset 同优先级，
//   有仿真失配风险）。
//   根因：数组写原来和输出寄存器复位同在 always @(posedge clk or negedge
//   rst_n) 里 —— 进程敏感表带异步复位，Vivado 的 RAM 推断模板直接不匹配。
//   修法：数组写拆进独立 always @(posedge clk)，用 if (rst_n && vde) 同步
//   门控。同步使用 rst_n ≠ 对异步复位敏感，模板重新匹配，line_buf 回到
//   distributed RAM（LUTRAM）而不是 10240 个寄存器位。
//   语义可证等价：原代码的数组写只发生在 rst_n=1（else 分支）且 vde=1 时，
//   与 if (rst_n && vde) 条件完全相同，同为 posedge clk 上的非阻塞赋值。
// -----------------------------------------------------------------------------
module downsample2x2 #(
    parameter integer H_ACTIVE = 1280
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vde,          // 数据有效
    input  wire [15:0] x,
    input  wire [15:0] y,
    input  wire [7:0]  pixel,
    output reg         valid,        // 大像素有效
    output reg  [15:0] big_x,        // 大像素列号 0..H_ACTIVE/2-1
    output reg  [15:0] big_y,        // 大像素行号 0..V_ACTIVE/2-1
    output reg  [9:0]  big_pixel     // 2x2 求和，0..1020
);

    // 行缓冲：存上一行像素。组合读 + 同拍写 => 读到的是写之前的旧值（上一行）。
    // 保留 distributed：组合读推不了 BRAM，LUTRAM 是对的归宿（10240 位，
    // 约 640 个 LUT，相对 53200 的预算微不足道）。
    // ★ 数组写在下方独立同步 always 里，别并回异步复位进程——并回去就是
    //   Synth 8-4767 整坨溶解成 10240 个寄存器（2026-10-16 实测踩坑）。
    (* ram_style = "distributed" *) reg [7:0] line_buf [0:H_ACTIVE-1];

    wire [7:0] above    = line_buf[x[15:0]];              // 上一行同列
    wire [9:0] col_sum  = {2'b00, pixel} + {2'b00, above}; // 本行+上一行

    reg [9:0] even_sum;   // 偶数列的 col_sum 暂存

    // 行缓冲写：独立同步进程（2026-10-16 修复，原因见文件头 ★）。
    // rst_n 同步使用 ≠ 对异步复位敏感，Vivado 的 RAM 推断模板才肯匹配；
    // 并回下面的异步复位进程，整坨 line_buf 会按 Synth 8-4767 溶解成寄存器。
    // 与原语义严格等价：原来这个写只发生在 rst_n=1 的 else 分支且 vde=1 时。
    always @(posedge clk) begin
        if (rst_n && vde) begin
            line_buf[x[15:0]] <= pixel;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid     <= 1'b0;
            even_sum  <= 10'd0;
            big_pixel <= 10'd0;
            big_x     <= 16'd0;
            big_y     <= 16'd0;
        end else begin
            valid <= 1'b0;

            if (vde) begin
                if (y[0]) begin                    // 奇数行：块的下沿，才是完整 2x2
                    if (!x[0]) begin
                        even_sum <= col_sum;       // 偶数列：把两行和先存起来
                    end else begin
                        big_pixel <= even_sum + col_sum;  // 奇数列：凑满 4 个像素
                        big_x     <= x >> 1;
                        big_y     <= y >> 1;
                        valid     <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
