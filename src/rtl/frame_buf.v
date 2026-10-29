`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// frame_buf — 一帧「大像素」缓存（10bit x 640x360）
//
// 用途：给「差分」提供参照帧。
//   帧差模式  ：缓存 = 上一帧（写当前帧，读上一帧）
//   背景建模  ：缓存 = 背景图（写更新后的背景，读旧背景）
// 两种模式下本模块行为相同 —— 都是「读旧、写新」，算法差别在上层。
//
// 端口语义（一拍内先读后写，同地址同时读写时读到旧值）：
//   读：re=1 时把 mem[raddr] 送到 dout，dout 在**下一拍**有效
//   写：we=1 时把 din 写入 mem[waddr]，当拍生效
//   => 同一拍给相同的 raddr/waddr，读到的就是「这一格改之前的值」
//
// 资源：640*360*10bit = 2.30 Mbit ≈ 64 块 BRAM36（Zynq-7020 共 140 块）
// -----------------------------------------------------------------------------
module frame_buf #(
    parameter integer DEPTH = 640 * 360,
    parameter integer AW    = 18
)(
    input  wire          clk,
    input  wire          re,
    input  wire [AW-1:0] raddr,
    output reg  [9:0]    dout,
    input  wire          we,
    input  wire [AW-1:0] waddr,
    input  wire [9:0]    din
);

    (* ram_style = "block" *) reg [9:0] mem [0:DEPTH-1];

    // 读在前、写在后：同地址同时读写时综合成 READ_FIRST，读到旧值
    always @(posedge clk) begin
        if (re) dout <= mem[raddr];
        if (we) mem[waddr] <= din;
    end

endmodule
