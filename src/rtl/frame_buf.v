`timescale 1ns / 1ps
// frame_buf：参数化单帧存储，为差分提供上一帧或旧背景值。
// re 有效时在时钟沿读取，we 有效时写入；同地址同拍读写返回旧值。
// 默认配置为 640×360×10 位，实际宽度由 DW 参数指定。
module frame_buf #(
    parameter integer DEPTH = 640 * 360,
    parameter integer AW    = 18,
    parameter integer DW = 10
)(
    input  wire          clk,
    input  wire          re,
    input  wire [AW-1:0] raddr,
    output reg  [DW-1:0]    dout,
    input  wire          we,
    input  wire [AW-1:0] waddr,
    input  wire [DW-1:0]    din
);

    (* ram_style = "block" *) reg [DW-1:0] mem [0:DEPTH-1];

    // 读在前、写在后：同地址同时读写时综合成 READ_FIRST，读到旧值
    always @(posedge clk) begin
        if (re) dout <= mem[raddr];
        if (we) mem[waddr] <= din;
    end

endmodule
