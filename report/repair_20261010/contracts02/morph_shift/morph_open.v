`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// morph_open —— 五步链的第 4 步：形态学**开运算** = 先腐蚀后膨胀。
//
// 作用：去掉孤立噪点，但保住真实的运动细带。
//   腐蚀（AND）把比核小的亮块整片抹掉 —— 孤立 1 个像素的噪点、细线全没；
//   膨胀（OR）再用同样的核把留下来的东西长回来 —— 所以真实细带尺寸不变。
//   先腐蚀后膨胀 = 开运算；反过来（先膨胀后腐蚀）是闭运算，会把噪点粘起来，不合用。
//
// ★★ 铁律（写进报告）：核边长必须**小于每帧位移**。
//   帧差得到的两条细带宽度 ≈ 每帧位移 d。核一旦 ≥ d，细带在腐蚀那一步就被
//   整条抹掉，一帧都检不出来。合成片段 d = 16 像素 = 8 个大像素，
//   核 3×3（大像素域）= 6 像素 < 16 像素 ✅
//
// 两级串联，级间不需要额外的有效信号处理：morph3x3 自己会按 in_valid 推进，
// 并且自带输出坐标（in_x−1, in_y−1），坐标会自动跟着级联累计偏移。
// -----------------------------------------------------------------------------
module morph_open #(
    parameter integer W = 640
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

    morph3x3 #(.W(W), .OP(0)) u_erode (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_x(in_x), .in_y(in_y), .in_mask(in_mask),
        .out_valid(e_valid), .out_x(e_x), .out_y(e_y), .out_mask(e_mask)
    );

    // 第 2 级：膨胀
    morph3x3 #(.W(W), .OP(1)) u_dilate (
        .clk(clk), .rst_n(rst_n),
        .in_valid(e_valid), .in_x(e_x), .in_y(e_y), .in_mask(e_mask),
        .out_valid(o_valid), .out_x(o_x), .out_y(o_y), .out_mask(o_mask)
    );

endmodule
