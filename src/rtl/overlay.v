`timescale 1ns / 1ps
// overlay：在灰度视频上叠加单目标红色边框和左上角状态指示。
// 输入包围盒使用原图像素坐标；THICK 为边框宽度。
// LAMP×LAMP 状态区以绿色表示有效目标、灰色表示无目标。
module overlay #(
    parameter integer THICK = 2,        // 边框宽度（像素）
    parameter integer LAMP  = 16,       // 状态灯边长（像素）
    parameter integer LAMP_X = 8,       // 状态灯左上角 x
    parameter integer LAMP_Y = 8        // 状态灯左上角 y
)(
    input  wire        de,
    input  wire [15:0] x,
    input  wire [15:0] y,
    input  wire [7:0]  gray,            // 原始灰度（或 R=G=B 的彩转灰结果）
    input  wire [15:0] bx1,             // 包围盒，像素坐标
    input  wire [15:0] by1,
    input  wire [15:0] bx2,
    input  wire [15:0] by2,
    input  wire        bvalid,          // 上一帧是否有有效目标
    output wire [7:0]  r,
    output wire [7:0]  g,
    output wire [7:0]  b
);

    wire in_win = (x >= bx1) && (x <= bx2) && (y >= by1) && (y <= by2);

    wire ex1 = in_win && (x <  bx1 + THICK[15:0]);
    wire ex2 = in_win && (x + THICK[15:0] > bx2);
    wire ey1 = in_win && (y <  by1 + THICK[15:0]);
    wire ey2 = in_win && (y + THICK[15:0] > by2);

    wire on_box = bvalid && (ex1 || ex2 || ey1 || ey2);

    wire on_lamp = (x >= LAMP_X[15:0]) && (x < LAMP_X[15:0] + LAMP[15:0]) &&
                   (y >= LAMP_Y[15:0]) && (y < LAMP_Y[15:0] + LAMP[15:0]);

    // 边框红 / 状态灯（绿=检出，暗灰=空闲）/ 其余透传灰度
    assign r = on_box  ? 8'hFF : (on_lamp ? (bvalid ? 8'h00 : 8'h28) : gray);
    assign g = on_box  ? 8'h00 : (on_lamp ? (bvalid ? 8'hFF : 8'h28) : gray);
    assign b = on_box  ? 8'h00 : (on_lamp ? (bvalid ? 8'h00 : 8'h28) : gray);

endmodule
