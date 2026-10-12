`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// diff_stage —— 五步链的第 2 步：差分。这是与参考作品 #1 唯一不同的一步。
//
//   帧差模式 (mode_bg=0)：缓存里存的是**上一帧**，差分 = |I(t) − I(t−1)|
//   背景建模 (mode_bg=1)：缓存里存的是**背景图 B**，差分 = |I(t) − B(t)|
//                        并顺手算出背景更新 B' = B + (I − B)/2^SHIFT
//
// 为什么存的东西一样多还是要换：
//   帧差只能拿到「新覆盖区」和「已腾空区」两条细带 —— 物体内部永远检不出来，
//   所以召回率天生低（CDnet 实测 F1 .171 / .028）。背景图是「一张不动的参照」，
//   静止和慢速目标也能和它拉开差距（F1 .560 / .357）。
//   两种做法都只缓存 1 张图，多出来的只是一个乘加 —— 存储代价≈0。
//
// ★ SHIFT 是 α 的位移近似：α = 1/2^SHIFT。用移位代替乘法，省掉 DSP。
//   取多少必须用数据定：CDnet 上 α 扫描 0.005→F1 .735 / 0.01→.717 / 0.02→.560
//   → 越小越好，但太小（|I−B| < 2^SHIFT 时增量为 0）背景就追不上缓慢的光照变化。
//   默认 SHIFT=6（α≈1/64）。
//
// ★ 首帧初始化：背景建模必须让 B 从 I(0) 起步（对应 algo_ab.py 里 bg = c2[0]），
//   否则开局整幅画面都是前景。init_phase=1 时缓存直接写当前帧。
//
// 端口时序（wr_data 是**组合**输出，供同拍写入缓存）：
//   本模块在「cur/ref 同时有效」那一拍组合算出 absdiff 与 wr_data；
//   上层把 absdiff 寄存一拍、把 wr_data 寄存一拍后写到**同一地址**。
//   因为读发生在写之前两拍，读到的必然是改之前的值 —— 不依赖 READ_FIRST 语义。
//
// ★ 2026-10-12 线二接入改动：SHIFT 由编译期参数改为**运行时输入端口**
//   （学习率来自 regs 寄存器堆 0x08，PS 运行时可改，见接口冻结表 I4 与
//   docs/line2_integration_guide.md §1.3）。移位量运行时可变综合为桶形移位器，无 DSP。
// -----------------------------------------------------------------------------
module diff_stage (
    input  wire [4:0]  shift_amt,      // α = 1/2^shift_amt（来自 regs 0x08）
    input  wire        mode_bg,        // 0 = 帧差（缓存=上一帧），1 = 背景建模
    input  wire        init_phase,       // 1 = 首帧：缓存直接写当前帧（只对 bg 模式有意义）
    input  wire [9:0]  cur,              // 当前帧大像素 I
    input  wire [9:0]  ref_px,           // 缓存读出的旧值（上一帧 或 背景图）
    output wire [10:0] absdiff,          // |I − 缓存|，0..1023
    output wire [9:0]  wr_data           // 写回缓存的值
);

    // ---- 有符号差 ----
    // 注意端口名不能叫 ref —— 那是 SystemVerilog 的关键字，xvlog -sv 会直接报语法错。
    wire signed [12:0] d = $signed({3'b000, cur}) - $signed({3'b000, ref_px});

    // ---- 绝对值 ----
    wire [12:0] ad = d[12] ? (~d + 13'd1) : d;

    // ---- 背景更新 B' = B + (I − B)/2^shift_amt，钳到 0..1023 ----
    wire signed [12:0] inc = d >>> shift_amt;
    wire signed [12:0] nxt = $signed({3'b000, ref_px}) + inc;
    wire        [9:0]  bg_next = (nxt < 13'sd0)     ? 10'd0 :
                                 (nxt > 13'sd1023)  ? 10'd1023 :
                                                      nxt[9:0];

    assign absdiff = ad[10:0];

    // 首帧 = 初始化；帧差模式 = 永远写当前帧
    assign wr_data = (mode_bg && !init_phase) ? bg_next : cur;

endmodule
