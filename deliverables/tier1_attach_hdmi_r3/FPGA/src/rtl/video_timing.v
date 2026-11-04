`timescale 1ns / 1ps
// video_timing：产生行同步、场同步、数据有效信号及有效像素坐标。
// 尺寸和消隐区由参数指定，时钟由外部提供。
// 720p60 对应 74.25 MHz 像素时钟，H/V 同步为正极性（SYNC_POS=1）。
module video_timing #(
    parameter integer H_ACTIVE = 320,
    parameter integer H_FP     = 8,
    parameter integer H_SYNC   = 16,
    parameter integer H_BP     = 16,
    parameter integer V_ACTIVE = 180,
    parameter integer V_FP     = 2,
    parameter integer V_SYNC   = 4,
    parameter integer V_BP     = 4,
    parameter integer SYNC_POS = 0
)(
    input  wire        clk,
    input  wire        rst_n,
    output reg         hs,
    output reg         vs,
    output reg         de,
    output wire [15:0] x,
    output wire [15:0] y,
    output reg         sof          // start of frame：帧内第一个像素那一拍
);

    localparam integer H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
    localparam integer V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

    reg [15:0] hcnt;
    reg [15:0] vcnt;

    // 水平计数
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                    hcnt <= 16'd0;
        else if (hcnt == H_TOTAL - 1)  hcnt <= 16'd0;
        else                           hcnt <= hcnt + 16'd1;
    end

    // 垂直计数（每个行尾进一位）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vcnt <= 16'd0;
        end else if (hcnt == H_TOTAL - 1) begin
            if (vcnt == V_TOTAL - 1) vcnt <= 16'd0;
            else                     vcnt <= vcnt + 16'd1;
        end
    end

    // 同步信号（SYNC_POS=0 低有效 / =1 高有效）
    wire hs_act = (hcnt >= H_ACTIVE + H_FP) && (hcnt < H_ACTIVE + H_FP + H_SYNC);
    wire vs_act = (vcnt >= V_ACTIVE + V_FP) && (vcnt < V_ACTIVE + V_FP + V_SYNC);

    always @(*) begin
        hs = SYNC_POS ?  hs_act : ~hs_act;
        vs = SYNC_POS ?  vs_act : ~vs_act;
    end

    // 数据有效
    always @(*) de = (hcnt < H_ACTIVE) && (vcnt < V_ACTIVE);

    assign x = hcnt;
    assign y = vcnt;

    // 帧起始
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sof <= 1'b0;
        else        sof <= (hcnt == 16'd0) && (vcnt == 16'd0);
    end

endmodule
