`timescale 1ns / 1ps
// morph_open：串联两级 3×3 二值滤波。
// FILTER_MODE=0 为先腐蚀后膨胀的开运算；FILTER_MODE=1 为两级多数滤波。
// 每级按有效样本推进，并输出对应窗口中心坐标。
module morph_open #(
    parameter integer W = 640,
    parameter integer FILTER_MODE = 0 // 0=legacy opening; 1=two majority stages
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [15:0] in_x,
    input  wire [15:0] in_y,
    input  wire        in_mask,
    output wire        o_valid,
    output wire [15:0] o_x,
    output wire [15:0] o_y,
    output wire        o_mask
);

    // 第 1 级：腐蚀
    wire        e_valid;
    wire [15:0] e_x, e_y;
    wire        e_mask;

    morph3x3 #(.W(W), .OP(FILTER_MODE==1 ? 2 : 0)) u_erode (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_x(in_x), .in_y(in_y), .in_mask(in_mask),
        .out_valid(e_valid), .out_x(e_x), .out_y(e_y), .out_mask(e_mask)
    );

    // 第 2 级：膨胀
    morph3x3 #(.W(W), .OP(FILTER_MODE==1 ? 2 : 1)) u_dilate (
        .clk(clk), .rst_n(rst_n),
        .in_valid(e_valid), .in_x(e_x), .in_y(e_y), .in_mask(e_mask),
        .out_valid(o_valid), .out_x(o_x), .out_y(o_y), .out_mask(o_mask)
    );

endmodule
