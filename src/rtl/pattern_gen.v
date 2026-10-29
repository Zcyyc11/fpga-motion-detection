`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// pattern_gen — 复刻 PC 端 make_test_clip.py 的合成片段，作为 RTL 仿真的激励
//
// 规则（与 make_test_clip.py / src/ps/rtl_golden.py 逐条对齐，改一端必须同步改另一端）：
//   黑底 + 纯白矩形，矩形尺寸 OBJ_W x OBJ_H，垂直不动，每帧水平右移 DX 像素。
//   第 i 帧左边缘的移动公式：x = (x + DX + OBJ_W > H_ACTIVE) ? X0 : x + DX
//   （第 0 帧左边缘 = X0，顶边 = Y0）
//
// ★ 回绕（三端统一定义，别处不许另写一套）：
//     只要"再走一步"不会让矩形右边缘越出画面，就往前走一步；否则左边缘回到 X0。
//     于是矩形**永远完整留在画面内**，可以无限跑下去。
//   为什么必须回绕：板上是连续跑的，不回绕的话白块 1.3 s 就走出画面，
//   之后一整分钟黑屏 —— 演示和"连续检出"都无从谈起。
//   原始程序中矩形覆盖 [x, x+OBJ_W-1] x [Y0, Y0+OBJ_H-1]，共 OBJ_W*OBJ_H 个白像素。
//
// 输出全部**寄存一拍**（vde/pixel/x_o/y_o 同拍对齐），下游按同一节拍处理。
// -----------------------------------------------------------------------------
module pattern_gen #(
    parameter integer H_ACTIVE = 1280,
    parameter integer V_ACTIVE = 720,
    parameter integer OBJ_W    = 160,
    parameter integer OBJ_H    = 120,
    parameter integer X0       = 60,
    parameter integer Y0       = 300,
    parameter integer DX       = 16
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sof,          // 来自 video_timing：帧首像素那一拍
    input  wire        de,           // 来自 video_timing
    input  wire [15:0] x,
    input  wire [15:0] y,
    output reg         vde,          // 数据有效（与 pixel/x_o/y_o 对齐）
    output reg  [15:0] x_o,
    output reg  [15:0] y_o,
    output reg  [7:0]  pixel,
    output reg  [15:0] frame_idx
);

    localparam [15:0] OBJ_W16 = OBJ_W[15:0];
    localparam [15:0] OBJ_H16 = OBJ_H[15:0];
    localparam [15:0] X0_16    = X0[15:0];
    localparam [15:0] Y0_16    = Y0[15:0];
    localparam [15:0] DX16     = DX[15:0];
    // 最右可用左边缘：矩形右边缘最多贴到画面右边（X_MAX16 + OBJ_W == H_ACTIVE）
    localparam [15:0] X_MAX16  = (H_ACTIVE - OBJ_W);

    reg [15:0] obj_x;
    // 已过首帧标志：16 位 frame_idx @60fps ≈ 18.2 分钟回绕到 0，
    // 若用 frame_idx==0 摆初始位置，回绕瞬间物体会跳回起点重跑一遍。
    // 只有复位后第一个 sof 才允许初始化 obj_x，此后回绕不再影响位置。
    reg obj_init_done;

    // ---- 帧号与目标左边缘：每帧首推进 ----
    // 第 0 帧 obj_x = X0；此后每帧 +DX，走不动了就回绕到 X0（见文件头"回绕"）。
    // 用累加实现，避免乘法。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_idx     <= 16'd0;
            obj_x         <= X0_16;
            obj_init_done <= 1'b0;
        end else if (sof) begin
            frame_idx <= frame_idx + 16'd1;
            if (!obj_init_done)
                obj_x <= X0_16;                    // 复位后第 0 帧
            else if ((obj_x + DX16) > X_MAX16)
                obj_x <= X0_16;                    // 再走一步就越界 → 回绕到左侧
            else
                obj_x <= (obj_x + DX16);
            obj_init_done <= 1'b1;
        end
    end

    // ---- 是否落在矩形内（组合判断，与注册输出同拍）----
    wire in_x = (x >= obj_x) && (x < (obj_x + OBJ_W16));
    wire in_y = (y >= Y0_16) && (y < (Y0_16 + OBJ_H16));
    wire is_obj = de && in_x && in_y;

    // ---- 寄存输出，保持 vde/pixel/x_o/y_o 同步 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vde   <= 1'b0;
            x_o   <= 16'd0;
            y_o   <= 16'd0;
            pixel <= 8'd0;
        end else begin
            vde   <= de;
            x_o   <= x;
            y_o   <= y;
            pixel <= is_obj ? 8'd255 : 8'd0;
        end
    end

endmodule
