`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// clock_200m —— 125 MHz PL 时钟生成 200 MHz 参考时钟（dvi2rgb 的 RefClk）
//
// 为什么需要它：dvi2rgb 官方文档端口表原文
//     "RefClk: 200 MHz reference clock."（IDELAYCTRL 的参考时钟，
//     也是 IP 内部控制/锁定监控的时钟）。不是近似、不是拍 —— 规格就是 200 MHz。
//
// ★ 参数不是拍的，是解出来的（与 clock_74m25 同一方法，同一哲学）：
//   MMCM 的 CLKFBOUT_MULT_F / DIVCLK_DIVIDE / CLKOUT0_DIVIDE_F 是 0.125 步进，
//   要「125 MHz 出精确 200 MHz」：
//       200 = 125 × M / (Dv × D0)
//       取 Dv=8 → M/D0 = 200×8/125 = 12.8 = 64/5 → M=64、D0=5
//       VCO = 125 × 64 / 8 = 1000 MHz ∈ [600, 1200]（Artix-7 -1 级）✅
//   为什么不能扩 clock_74m25 那个 MMCM：
//       它 VCO = 1160.156 MHz（74.25 组），CLKOUT 分频 0.125 步进，
//       1160.156/200 = 5.80078 不是 0.125 的整数倍 → 只能近似（5.75=201.8 / 5.875=197.5）
//       而 IDELAYCTRL 的 tap 是按 200 MHz 标定的，近似值引入 1% 级 tap 偏差。
//       既然 125→200 有精确整数解，就绝不用近似 —— 和"参数要解出来"同一标准。
// -----------------------------------------------------------------------------
module clock_200m (
    input  wire clk_125m,       // PYNQ-Z2 PL 参考时钟 125 MHz（H16）
    input  wire mmcm_rst,       // 异步复位（高有效）
    output wire clk_200m,       // 200 MHz
    output wire locked
);

    wire clk_fb;
    wire clk_200m_raw;

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (64.0),       // 64
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (8.000),      // 125 MHz
        .CLKOUT0_DIVIDE_F   (5.0),        // 5
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .DIVCLK_DIVIDE      (8),          // 8
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        .CLKOUT0  (clk_200m_raw),
        .CLKFBOUT (clk_fb),
        .LOCKED   (locked),
        .CLKIN1   (clk_125m),
        .PWRDWN   (1'b0),
        .RST      (mmcm_rst),
        .CLKFBIN  (clk_fb)
    );

    BUFG u_bufg_200 (.I(clk_200m_raw), .O(clk_200m));

endmodule
