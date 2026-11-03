`timescale 1ns / 1ps
// pattern_gen：生成黑底白色矩形的测试视频。
// 矩形为 OBJ_W×OBJ_H，首帧位置为 (X0,Y0)，每帧向右移动 DX 像素。
// 下一步将越过右边界时回到 X0；输出像素、坐标和有效信号同步寄存。
// 运动规则与 PC 端 make_test_clip.py 和 rtl_golden.py 参考模型对应。
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

    // 帧号与目标左边缘：每帧首推进
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

    // 是否落在矩形内（组合判断，与注册输出同拍）
    wire in_x = (x >= obj_x) && (x < (obj_x + OBJ_W16));
    wire in_y = (y >= Y0_16) && (y < (Y0_16 + OBJ_H16));
    wire is_obj = de && in_x && in_y;

    // 寄存输出，保持 vde/pixel/x_o/y_o 同步
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
