`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// regs —— 线二任务：参数控制寄存器堆（接口冻结表 I4 的 RTL 落地）
//
// 作用：PS 侧（Python）运行时读写阈值/警戒线/学习率等参数，PL 侧流水线
//   拿到的是普通线网 —— 改参数不用重新烧板。这是清单里"参数控制实现状态"
//   从「映射已冻结、实现未完成」变成「已实现」的这一步。
//
// 寄存器映射（与 docs/接口冻结表.md I4 严格一致，地址 4 字节对齐，小端）：
//   0x00 THRESH      16  复位 70   绝对阈值（和域）
//   0x04 THRESH_REL  16  复位 15   相对阈值百分比
//   0x08 ALPHA_SHIFT  5  复位 5    背景学习率 = 1/2^SHIFT
//   0x0C LINE_X      11  复位 640  警戒线 X（大像素域）
//   0x10 DWELL       16  复位 90   停留告警帧数
//   0x14 ENABLE       1  复位 0    1=背景建模 0=帧差法
//   0x18 STATUS      32  只读      目标数/告警标志/帧计数（由流水线驱动）
//
// PS 总线故意做得很瘦（en/we/addr/wdata/rdata）——将来无论挂 AXI-Lite
// 还是 GPIO 翻译层，都只改外面一层壳，本模块不动。
// 写在第 1 拍生效；读为寄存输出（第 2 拍有效），综合时序友好。
// -----------------------------------------------------------------------------
module regs (
    input  wire        clk,
    input  wire        rst_n,
    // PS 侧简单总线
    input  wire        ps_en,        // 1 = 本次访问有效
    input  wire        ps_we,        // 1 = 写，0 = 读
    input  wire [4:0]  ps_addr,      // 字节地址（0x00..0x18）
    input  wire [31:0] ps_wdata,
    output reg  [31:0] ps_rdata,     // 读寄存输出（ps_en&!we 后 1 拍有效）
    // 流水线参数输出（随时更新，随写随生效）
    output reg  [15:0] o_thresh,
    output reg  [15:0] o_thresh_rel,
    output reg  [4:0]  o_alpha_shift,
    output reg  [10:0] o_line_x,
    output reg  [15:0] o_dwell,
    output reg         o_enable,
    // 只读状态（流水线侧驱动）
    input  wire [31:0] i_status
);

    // 读译码函数（Verilog-2001 不支持 case 表达式）
    function [31:0] rd_decode(input [4:0] a);
        case (a)
            5'h00: rd_decode = {16'd0, o_thresh};
            5'h04: rd_decode = {16'd0, o_thresh_rel};
            5'h08: rd_decode = {27'd0, o_alpha_shift};
            5'h0C: rd_decode = {21'd0, o_line_x};
            5'h10: rd_decode = {16'd0, o_dwell};
            5'h14: rd_decode = {31'd0, o_enable};
            5'h18: rd_decode = i_status;
            default: rd_decode = 32'd0;
        endcase
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_thresh      <= 16'd70;
            o_thresh_rel  <= 16'd15;
            o_alpha_shift <= 5'd5;
            o_line_x      <= 11'd640;
            o_dwell       <= 16'd90;
            o_enable      <= 1'b0;
            ps_rdata      <= 32'd0;
        end else begin
            if (ps_en && ps_we) begin
                case (ps_addr)
                    5'h00: o_thresh      <= ps_wdata[15:0];
                    5'h04: o_thresh_rel  <= ps_wdata[15:0];
                    5'h08: o_alpha_shift <= ps_wdata[4:0];
                    5'h0C: o_line_x      <= ps_wdata[10:0];
                    5'h10: o_dwell       <= ps_wdata[15:0];
                    5'h14: o_enable      <= ps_wdata[0];
                    default: ;           // STATUS 只读，写忽略
                endcase
            end
            // 读：寄存输出
            ps_rdata <= (ps_en && !ps_we) ? rd_decode(ps_addr) : 32'd0;
        end
    end

endmodule
