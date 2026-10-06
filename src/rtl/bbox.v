`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// bbox —— 五步链的第 5 步：包围盒。
//
// 做法就是参考作品 #1 那四个比较器：帧内扫一遍掩码，记录
//   x_min / x_max / y_min / y_max 和 命中像素数
// 全部只跟同一个量比较，没有乘除、没有连通域标记 —— 这是它能上 FPGA 的原因。
//
// ★ 和 cv2.connectedComponentsWithStats 的差别（报告要写清楚）：
//   我们是**全局并集包围盒**（所有运动像素合成一个框），
//   cv2 是**最大连通域**的框。单目标场景（合成片段 1 个矩形）两者完全等价；
//   多目标场景并集框会把两个目标框在一起 —— 这是已知取舍，不是 bug。
//
// ★ 有效判据（面积门限）：命中像素数 >= MIN_CNT 才算「检测到」。
//   为什么需要：3×3 开运算之后，能幸存的连通块最小是 3×3 = 9 个大像素，
//   所以门限设在 64 ≈ 7 倍最小幸存面积 —— 足够挡掉零散残留，又远小于
//   真实运动面积（合成片段约 1200+ 个大像素），不会误杀真目标。
//   ⚠️ CDnet 那边的口径是「2% 画面面积」（algo_ab.py 的 ratio=0.02），
//      是**另一套口径**，别混写；这里用小绝对门限是因为目标占比低得多。
//
// ★ 帧边界检测：不用外部帧同步信号，而是**看输入坐标自己回绕**
//   （in_y 比上一个样本的 y 小 = 新的一帧开始了）。
//   这样不必去数「流水线到底延迟了几拍」，改流水线深度也不会破坏它。
//   代价：只在掩码流上有效（掩码流每帧都连续，天然满足）。
//
// 输出在**帧边界更新一次**：x1/y1/x2/y2/cnt 描述的是**上一帧**的结果，
// 所以显示上会滞后一帧 —— 这是正常的，帧内结果没法提前知道。
// 坐标为**大像素坐标**（0..BW-1 / 0..BH-1）。转成像素坐标要 ×2。
// -----------------------------------------------------------------------------
module bbox #(
    parameter integer MIN_CNT = 64
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [15:0] in_x,
    input  wire [15:0] in_y,
    input  wire        in_mask,
    output reg  [15:0] x1,
    output reg  [15:0] y1,
    output reg  [15:0] x2,
    output reg  [15:0] y2,
    output reg  [15:0] cnt,
    output reg         valid
);

    localparam [15:0] BIG = 16'hFFFF;

    reg [15:0] mnx, mny, mxx, mxy, n;
    reg [15:0] py;                                  // 上一个有效样本的 y

    wire new_frame = in_valid && (in_y < py);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mnx <= BIG; mny <= BIG; mxx <= 16'd0; mxy <= 16'd0; n <= 16'd0;
            x1 <= 16'd0; y1 <= 16'd0; x2 <= 16'd0; y2 <= 16'd0;
            cnt <= 16'd0; valid <= 1'b0;
            py  <= BIG;
        end else begin
            py <= in_valid ? in_y : py;

            if (new_frame) begin
                // 结算上一帧
                x1 <= mnx; y1 <= mny; x2 <= mxx; y2 <= mxy;
                cnt   <= n;
                valid <= (n >= MIN_CNT[15:0]) && (mnx <= mxx) && (mny <= mxy);
                // 复位累加器
                mnx <= BIG; mny <= BIG; mxx <= 16'd0; mxy <= 16'd0; n <= 16'd0;
            end else if (in_valid && in_mask) begin
                if (in_x < mnx) mnx <= in_x;
                if (in_x > mxx) mxx <= in_x;
                if (in_y < mny) mny <= in_y;
                if (in_y > mxy) mxy <= in_y;
                n <= n + 16'd1;
            end
        end
    end

endmodule
