`timescale 1ns / 1ps
// diff_stage：帧差或运行背景差分，输出为组合逻辑。
// 算法基线参考原项目材料中的“参考作品 #1”；增加可选运行背景更新。
// mode_bg=0 时比较当前帧与上一帧，mode_bg=1 时比较当前帧与背景。
// 背景更新步长由 shift_amt 指定，学习率为 1/2^shift_amt。
// init_phase 有效时以当前像素初始化背景。
module diff_stage (
    input  wire [4:0]  shift_amt,      // α = 1/2^shift_amt（来自 regs 0x08）
    input  wire        mode_bg,        // 0 = 帧差（缓存=上一帧），1 = 背景建模
    input  wire        init_phase,       // 1 = 首帧：缓存直接写当前帧（只对 bg 模式有意义）
    input  wire [9:0]  cur,              // 当前帧大像素 I
    input  wire [9:0]  ref_px,           // 缓存读出的旧值（上一帧 或 背景图）
    output wire [10:0] absdiff,          // |I − 缓存|，0..1023
    output wire [9:0]  wr_data           // 写回缓存的值
);

    // 有符号差
    // 注意端口名不能叫 ref —— 那是 SystemVerilog 的关键字，xvlog -sv 会直接报语法错。
    wire signed [12:0] d = $signed({3'b000, cur}) - $signed({3'b000, ref_px});

    // 绝对值
    wire [12:0] ad = d[12] ? (~d + 13'd1) : d;

    // 背景更新 B' = B + (I − B)/2^shift_amt，钳到 0..1023
    wire signed [12:0] inc = d >>> shift_amt;
    wire signed [12:0] nxt = $signed({3'b000, ref_px}) + inc;
    wire        [9:0]  bg_next = (nxt < 13'sd0)     ? 10'd0 :
                                 (nxt > 13'sd1023)  ? 10'd1023 :
                                                      nxt[9:0];

    assign absdiff = ad[10:0];

    // 首帧 = 初始化；帧差模式 = 永远写当前帧
    assign wr_data = (mode_bg && !init_phase) ? bg_next : cur;

endmodule
