`timescale 1ns / 1ps
// downsample2x2：将 8 位像素流按 2×2 求和，输出 10 位大像素。
// 求和方法沿用原项目参考作品及 PC 端 compress2x2 参考模型，最大值为 1020。
// 在奇数行、奇数列输出完整块；数据、坐标和有效信号同步寄存。
// 行缓冲采用组合读及独立同步写进程，以支持 distributed RAM 推断。
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
    // 组合读对应 distributed RAM；数组写使用独立同步进程。
    (* ram_style = "distributed" *) reg [7:0] line_buf [0:H_ACTIVE-1];

    wire [7:0] above    = line_buf[x[15:0]];              // 上一行同列
    wire [9:0] col_sum  = {2'b00, pixel} + {2'b00, above}; // 本行+上一行

    reg [9:0] even_sum;   // 偶数列的 col_sum 暂存

    // 行缓冲写入使用同步复位门控，避免异步复位影响 RAM 推断。
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
