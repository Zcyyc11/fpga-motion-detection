`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// morph3x3 —— 3×3 形态学**单步**（OP=0 腐蚀 AND / OP=1 膨胀 OR）
//
// 为什么单独做一级、再串一级（见 morph_open.v）：
//   开运算 = 先腐蚀后膨胀，本来就是两个独立算子；拆成两级方便报告里逐级对照波形。
//
// 输入是**大像素域**的 1bit 掩码流（每帧 BW×BH 个样本，按光栅序，x 递增）。
// 注意样本之间有空洞（一个大像素要 2 个像素时钟才出一个），所以所有延迟都用
// **样本有效信号 in_valid 作为推进使能**，不是用时钟 —— 否则列延迟会错位。
//
// 3×3 窗口 = 3 行 × 每行连续 3 列 (x-2, x-1, x)：
//   · 当前行：三级移位 d2/d1/in_mask
//   · 上两行：从**行缓冲**按列读到同列值，再用同样的两级移位得到 x-1/x-2
//   · 行缓冲用 3 个相位轮转，写当前行、读 y-1 / y-2 行
//
// ★★ 行相位怎么轮转 —— 这里踩过一个真坑，记下来免得重犯：
//   第一版用「in_x == W-1」判断一行结束来轮转相位。这对第一级（腐蚀）成立，
//   但第二级（膨胀）的输入是腐蚀的输出，x 范围是 1..BW-2，**永远等不到 W-1**，
//   于是相位一次都不轮转、行缓冲全部写进同一个相位 → 膨胀的垂直方向静默失效，
//   结果就是"水平膨胀对了、垂直没膨胀"（掩码高度少 2 行）。
//   因为它不会报错、只是数字偏小，最容易蒙混过关。
//   → 改成**看输入坐标自己换行**（in_y 与上一个样本不同就是新的一行），
//     与 x 的范围彻底解耦。同时对行相位之外的读取加了**有效标志 rv**，
//     保证"还没写过的行"读出来是 0（零扩展），不会漏 X 到下游。
//
// ★ 行相位必须在该行**第一个像素之前**就位，所以用组合的 ph_cur 同时驱动
//   本次写地址与本次读地址；只把 ph 寄存器在换行那一拍更新（非阻塞），
//   这样同一行内所有像素都落在同一个相位上。
//
// ★ 边界约定：窗口外一律当 0（零扩展），并且**每帧独立**（换帧时行缓冲作废）。
//   这不是 OpenCV 的默认边界，是我们的**自定义约定**，
//   PC 端参考模型 src/ps/rtl_golden.py 必须做同样的事才严格可比。
//
// ★ 输出位置：窗口 (x-2..x)×(y-2..y) 的中心是 (x-1, y-1)，所以
//   out_x = in_x−1、out_y = in_y−1，且只在 in_x≥2 且 in_y≥2 时有效。
//   这样才是**居中**的 3×3，和 cv2 的锚点定义对齐。
//   推论：输出域是 x∈[1,BW-2]、y∈[1,BH-2]。
// -----------------------------------------------------------------------------
module morph3x3 #(
    parameter integer W  = 640,      // 一行的大像素个数 BW
    parameter integer OP = 0         // 0 = 腐蚀(AND)，1 = 膨胀(OR)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [15:0] in_x,
    input  wire [15:0] in_y,
    input  wire        in_mask,
    output reg         out_valid,
    output reg  [15:0] out_x,
    output reg  [15:0] out_y,
    output reg         out_mask
);

    // ---- 行缓冲：3 相位轮转；rv 记录各相位是否已经写过（换帧作废）----
    reg       mem [0:2][0:W-1];
    reg [1:0] ph;
    reg [2:0] rv;
    reg [15:0] py;
    reg seen_sample;

    wire row_start = in_valid && (!seen_sample || (in_y != py));
    wire new_frame = row_start && seen_sample && (in_y < py);

    // 本行的相位（在换行那一拍就组合地换成新值，保证该行第一个像素写对位置）
    wire [1:0] ph_cur = !seen_sample ? 2'd0 :
                       row_start ? ((ph == 2'd2) ? 2'd0 : (ph + 2'd1)) : ph;

    wire [1:0] phm1 = (ph_cur == 2'd0) ? 2'd2 : (ph_cur - 2'd1);   // y-1 行
    wire [1:0] phm2 = (ph_cur == 2'd2) ? 2'd0 : (ph_cur + 2'd1);   // y-2 行

    wire r1 = !new_frame && rv[phm1] ? mem[phm1][in_x] : 1'b0;
    wire r2 = !new_frame && rv[phm2] ? mem[phm2][in_x] : 1'b0;

    // ---- 每行的两级列延迟 ----
    reg d1, d2;                     // 当前行：x-1, x-2
    reg a1, a2;                     // y-1 行：x-1, x-2
    reg b1, b2;                     // y-2 行：x-1, x-2

    wire v_cur = OP ? (d2 | d1 | in_mask) : (d2 & d1 & in_mask);
    wire v_p1  = OP ? (a2 | a1 | r1)      : (a2 & a1 & r1);
    wire v_p2  = OP ? (b2 | b1 | r2)      : (b2 & b1 & r2);
    wire res   = OP ? (v_cur | v_p1 | v_p2) : (v_cur & v_p1 & v_p2);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ph <= 2'd0;  rv <= 3'b000;  py <= 16'd0;
            seen_sample <= 1'b0;
            d1 <= 1'b0;  d2 <= 1'b0;
            a1 <= 1'b0;  a2 <= 1'b0;
            b1 <= 1'b0;  b2 <= 1'b0;
            out_valid <= 1'b0;
            out_mask  <= 1'b0;
            out_x     <= 16'd0;
            out_y     <= 16'd0;
        end else begin
            out_valid <= 1'b0;
            if (in_valid) begin
                seen_sample <= 1'b1;
                // 写当前行（用组合后的相位，保证该行首像素也落在正确相位）
                mem[ph_cur][in_x] <= in_mask;

                if (row_start) begin
                    py <= in_y;
                    ph <= ph_cur;
                    if (new_frame) rv <= 3'b000;      // 换帧：行缓冲作废（帧外当 0）
                    rv[ph_cur] <= 1'b1;               // 本相位开始有数据
                end

                // 列延迟（按样本推进）
                // 每行首将缺失的左邻样本置零。第二级从 x=1 开始，
                // 不清零会把上一行末列带入下一行 x=1 的窗口。
                d2 <= row_start ? 1'b0 : d1;  d1 <= in_mask;
                a2 <= row_start ? 1'b0 : a1;  a1 <= r1;
                b2 <= row_start ? 1'b0 : b1;  b1 <= r2;

                if ((in_x >= 16'd2) && (in_y >= 16'd2)) begin
                    out_mask  <= res;
                    out_x     <= in_x;
                    out_y     <= in_y - 16'd1;
                    out_valid <= 1'b1;
                end
            end
        end
    end

endmodule
