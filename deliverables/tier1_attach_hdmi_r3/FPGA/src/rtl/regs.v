`timescale 1ns / 1ps
//
// regs：参数控制及检测快照寄存器
//
// PS 侧运行时读写阈值、警戒线和学习率等参数。
//
// 寄存器映射（字节地址，4 字节对齐，小端；0x1C 起为检测快照）：
// 0x00 THRESH      16  复位 70   绝对阈值（和域）        读写
// 0x04 THRESH_REL  16  复位 15   相对阈值百分比          读写
// 0x08 ALPHA_SHIFT  5  复位 5    背景学习率 = 1/2^SHIFT  读写
// 0x0C LINE_X      11  复位 640  警戒线 X（大像素域）    读写
// 0x10 DWELL       16  复位 90   停留告警帧数            读写
// 0x14 ENABLE       1  复位 0    1=背景建模 0=帧差法     读写
// 0x18 STATUS      32  只读      见下方位分配
// 0x1C BBOX_X1     16  只读      包围盒左上 X（大像素域，帧快照）
// 0x20 BBOX_Y1     16  只读      左上 Y
// 0x24 BBOX_X2     16  只读      右下 X
// 0x28 BBOX_Y2     16  只读      右下 Y
// 0x2C BBOX_CNT    16  只读      前景像素计数（16 位饱和）
// 0x30 BBOX_VALID   1  只读      快照所属帧有目标
// 0x34 BBOX_FRAME  16  只读      快照所属帧号（与快照同拍锁存）
//
// STATUS 位分配：
// bit0    = b_valid    快照所属帧有目标（bbox_snapshot 副本）
// bit1    = alarm      快照所属帧内发生过告警（帧级粘存，
// 帧边界随快照刷新；事件本身是单拍脉冲，
// 直接接 PS 轮询读不到）
// bit7:2  = 保留
// bit15:8 = obj_count  快照所属帧目标数
// bit30:16= frame_idx 低 15 位镜像（16 位 @60fps 约 18.2 分钟回绕）
// bit31   = UART 丢包粘存位（i_uart_drop 置位，PS 写 STATUS 清除）
//
// ps_addr 为 6 位字节地址，覆盖 0x00..0x34。
//
// 快照来源：bbox_snapshot.v 在像素钟域帧边界连同 frame_idx 一起锁存并经
// 四段握手 CDC 送入 AXI 钟域稳定副本 —— 本模块只读副本，无跨钟逻辑。
// 寄存器接口为 en/we/addr/wdata/rdata，AXI 协议由上层桥接模块处理。
// 写在第 1 拍生效；读为寄存输出（第 2 拍有效），综合时序友好。
//
module regs (
    input  wire        clk,           // AXI 钟域
    input  wire        rst_n,
    // PS 侧简单总线（axi_lite_slave 驱动）
    input  wire        ps_en,        // 1 = 本次访问有效
    input  wire        ps_we,        // 1 = 写，0 = 读
    input  wire [5:0]  ps_addr,      // 字节地址（0x00..0x34）
    input  wire [31:0] ps_wdata,
    output reg  [31:0] ps_rdata,     // 读寄存输出（ps_en&!we 后 1 拍有效）
    // 流水线参数输出（随时更新，随写随生效）
    output reg  [15:0] o_thresh,
    output reg  [15:0] o_thresh_rel,
    output reg  [4:0]  o_alpha_shift,
    output reg  [10:0] o_line_x,
    output reg  [15:0] o_dwell,
    output reg         o_enable,
    // bbox 快照（bbox_snapshot.v 的 AXI 钟域稳定副本，整帧一致）
    input  wire [15:0] i_snap_x1, i_snap_y1, i_snap_x2, i_snap_y2, i_snap_cnt,
    input  wire        i_snap_valid,
    input  wire [15:0] i_snap_frame,
    input  wire [7:0]  i_snap_obj_count,
    input  wire        i_snap_b_valid,
    input  wire        i_snap_alarm,
    // UART 丢包标志（uart_tx.drop，粘存进 STATUS bit31）
    input  wire        i_uart_drop
);

    reg uart_drop_sticky;   // FIFO 满发生过一次即置位，PS 写 STATUS 清除

    // STATUS 拼装（位分配见文件头）：1+15+8+6+1+1 = 32 bit
    wire [31:0] status_val = {uart_drop_sticky,        // 31
                              i_snap_frame[14:0],      // 30:16
                              i_snap_obj_count,        // 15:8
                              6'd0,                    // 7:2 保留
                              i_snap_alarm,            // bit1
                              i_snap_b_valid};         // bit0

    // 读译码函数（Verilog-2001 不支持 case 表达式）
    function [31:0] rd_decode(input [5:0] a);
        case (a)
            6'h00: rd_decode = {16'd0, o_thresh};
            6'h04: rd_decode = {16'd0, o_thresh_rel};
            6'h08: rd_decode = {27'd0, o_alpha_shift};
            6'h0C: rd_decode = {21'd0, o_line_x};
            6'h10: rd_decode = {16'd0, o_dwell};
            6'h14: rd_decode = {31'd0, o_enable};
            6'h18: rd_decode = status_val;
            6'h1C: rd_decode = {16'd0, i_snap_x1};
            6'h20: rd_decode = {16'd0, i_snap_y1};
            6'h24: rd_decode = {16'd0, i_snap_x2};
            6'h28: rd_decode = {16'd0, i_snap_y2};
            6'h2C: rd_decode = {16'd0, i_snap_cnt};
            6'h30: rd_decode = {31'd0, i_snap_valid};
            6'h34: rd_decode = {16'd0, i_snap_frame};
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
                    6'h00: o_thresh      <= ps_wdata[15:0];
                    6'h04: o_thresh_rel  <= ps_wdata[15:0];
                    6'h08: o_alpha_shift <= ps_wdata[4:0];
                    6'h0C: o_line_x      <= ps_wdata[10:0];
                    6'h10: o_dwell       <= ps_wdata[15:0];
                    6'h14: o_enable      <= ps_wdata[0];
                    default: ;           // 其余只读
                endcase
            end
            // 读：寄存输出
            ps_rdata <= (ps_en && !ps_we) ? rd_decode(ps_addr) : 32'd0;
        end
    end

    // 丢包粘存：uart_tx 报过一次 FIFO 满就记住，直到 PS 主动清除
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                          uart_drop_sticky <= 1'b0;
        else if (ps_en && ps_we && ps_addr == 6'h18) uart_drop_sticky <= 1'b0;
        else if (i_uart_drop)                uart_drop_sticky <= 1'b1;
    end

endmodule
