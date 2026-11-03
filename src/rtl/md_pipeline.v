`timescale 1ns/1ps
// Attach-Z2 内部测试图案的兼容封装。
// 实例化 tier1_md_pipeline，关闭 PS/AXI 接口，保留视频及检测结果输出。
module md_pipeline #(
    parameter integer H_ACTIVE = 1280,
    parameter integer V_ACTIVE = 720,
    parameter integer H_FP = 110,
    parameter integer H_SYNC = 40,
    parameter integer H_BP = 220,
    parameter integer V_FP = 5,
    parameter integer V_SYNC = 5,
    parameter integer V_BP = 20,
    parameter integer SYNC_POS = 1,
    parameter integer OBJ_W = 160,
    parameter integer OBJ_H = 120,
    parameter integer X0 = 60,
    parameter integer Y0 = 300,
    parameter integer DX = 16,
    parameter integer THRESH = 100,
    parameter integer SHIFT = 6,
    parameter integer MODE_BG = 1,
    parameter integer MIN_CNT = 64,
    parameter integer BG_FRAC_BITS = 4,
    parameter integer BG_FG_SHIFT = 10,
    parameter integer FILTER_MODE = 1
)(
    input wire clk,
    input wire rst_n,
    output wire vde,
    output wire [15:0] vx,
    output wire [15:0] vy,
    output wire vhs,
    output wire vvs,
    output wire [7:0] vr,
    output wire [7:0] vg,
    output wire [7:0] vb,
    output wire [15:0] b_x1,
    output wire [15:0] b_y1,
    output wire [15:0] b_x2,
    output wire [15:0] b_y2,
    output wire [15:0] b_cnt,
    output wire b_valid,
    output wire [7:0] b_obj_count,
    output wire m_valid,
    output wire [15:0] m_x,
    output wire [15:0] m_y,
    output wire m_bit,
    output wire [15:0] frame_idx
);
    wire uart_txd_unused;
    wire uart_drop_unused;
    wire alarm_evt_unused;
    wire [31:0] ps_rdata_unused;

    tier1_md_pipeline #(
        .H_ACTIVE(H_ACTIVE), .V_ACTIVE(V_ACTIVE),
        .H_FP(H_FP), .H_SYNC(H_SYNC), .H_BP(H_BP),
        .V_FP(V_FP), .V_SYNC(V_SYNC), .V_BP(V_BP),
        .SYNC_POS(SYNC_POS),
        .OBJ_W(OBJ_W), .OBJ_H(OBJ_H), .X0(X0), .Y0(Y0), .DX(DX),
        .THRESH(THRESH), .SHIFT(SHIFT), .MODE_BG(MODE_BG),
        .MIN_CNT(MIN_CNT), .INPUT_SEL(0), .INCLUDE_PS(0),
        .BG_FRAC_BITS(BG_FRAC_BITS), .BG_FG_SHIFT(BG_FG_SHIFT),
        .FILTER_MODE(FILTER_MODE)
    ) u_tier1 (
        .clk(clk), .rst_n(rst_n),
        .rx_de(1'b0), .rx_hs(1'b0), .rx_vs(1'b0), .rx_sof(1'b0),
        .rx_x(16'd0), .rx_y(16'd0), .rx_gray(8'd0),
        .vde(vde), .vx(vx), .vy(vy), .vhs(vhs), .vvs(vvs),
        .vr(vr), .vg(vg), .vb(vb),
        .b_x1(b_x1), .b_y1(b_y1), .b_x2(b_x2), .b_y2(b_y2),
        .b_cnt(b_cnt), .b_valid(b_valid), .b_obj_count(b_obj_count),
        .m_valid(m_valid), .m_x(m_x), .m_y(m_y), .m_bit(m_bit),
        .frame_idx(frame_idx),
        .uart_txd(uart_txd_unused), .uart_drop(uart_drop_unused),
        .alarm_evt(alarm_evt_unused),
        .clk_axi(clk), .rst_n_axi(rst_n), .ps_en(1'b0), .ps_we(1'b0),
        .ps_addr(6'd0), .ps_wdata(32'd0), .ps_rdata(ps_rdata_unused)
    );
endmodule
