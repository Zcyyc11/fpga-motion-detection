`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// overlay —— 把检测结果画回画面上（OSD）。
//
// 这是「必须能看见」那一半：光有包围盒坐标是一串数字，只有画到 HDMI 上，
// 人和评委才能一眼看出「框住的就是那个在动的东西」。
//
// 画两样东西：
//   1) 包围盒边框：红色，边宽 THICK 像素，只画在框上（框内不填充，保住画面内容）
//   2) 左上角状态灯 LAMP×LAMP：
//        绿 = 本帧检测到目标（cnt 过了面积门限）
//        灰 = 没检测到
//      它的作用是**故障排查**：如果 HDMI 有画面但框不出现，
//      看灯就知道是「算法没检出」还是「叠加逻辑坏了」——把两类故障分开。
//
// 输入坐标是**像素坐标**（0..H_ACTIVE-1），而包围盒来自大像素域，
// 所以上层要先把 bbox 坐标 <<1 再送进来（见 md_pipeline.v）。
// 阈值/差分/形态学全在灰度域做，所以叠加只改 R/G/B 三通道的显示值，不回流。
// -----------------------------------------------------------------------------
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
