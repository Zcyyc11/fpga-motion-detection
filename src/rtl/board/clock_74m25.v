`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// clock_74m25 —— 用 125 MHz 的 PL 时钟生成 74.25 MHz 像素时钟
//
// 为什么不用 Clocking Wizard IP：
//   参数要能写进源码、能进版本库、能被第三方一眼复核。直接实例化 MMCME2_BASE
//   就三个参数，比"谁来点一遍 IP 向导"更可复现（官方要求里"可复现构建"这一条）。
//
// ★★ 参数不是拍出来的，是解出来的（脚本 build/scripts/mmcm_search.py）：
//   MMCM 的 CLKFBOUT_MULT_F / DIVCLK_DIVIDE / CLKOUT0_DIVIDE_F 都是 **0.125 步进**，
//   所以「125 MHz 出一模一样的 74.25 MHz」是有解的，但**只在 DIVCLK_DIVIDE>1 时才有**：
//       74.25 = 125 × M / (Dv × D0)
//       取 Dv=4 → M/D0 = 2.376 = 297/125 → M = 37.125 (=297/8)、D0 = 15.625 (=125/8)
//       VCO = 125 × 37.125 / 4 = 1160.156 MHz   ∈ [600, 1200] ✅（Artix-7 -1 级）
//   只试 Dv=1 会得出"做不到、只能取近似"的错误结论 —— 这件事本身值得写在报告里：
//   参数要**解**出来，不要靠试、也不要靠感觉。
//
// 74.25 MHz 为什么必须是精确值：720p60 的总时序是 1650×750，
//   刷新率 = 74.25e6 / (1650×750) = 60.00 Hz。频率偏了刷新率就跟着偏，
//   而现在偏差是 0。
//
// 输出的 pixel clock 必须过 BUFG 再给整个视频通路用（MMCM 输出到 BUFG 到全局网络）。
// -----------------------------------------------------------------------------
module clock_74m25 (
    input  wire clk_125m,       // PYNQ-Z2 PL 独立参考时钟，125 MHz，H16
    input  wire mmcm_rst,       // 异步复位（高有效）
    output wire clk_pix,        // 74.25 MHz
    output wire locked
);

    wire clk_fb;
    wire clk_pix_raw;

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (37.125),      // 37.125
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (8.000),       // 125 MHz
        .CLKOUT0_DIVIDE_F   (15.625),      // 15.625
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .DIVCLK_DIVIDE      (4),           // 4
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        .CLKOUT0  (clk_pix_raw),
        .CLKFBOUT (clk_fb),
        .LOCKED   (locked),
        .CLKIN1   (clk_125m),
        .PWRDWN   (1'b0),
        .RST      (mmcm_rst),
        .CLKFBIN  (clk_fb)
    );

    BUFG u_bufg_pix (.I(clk_pix_raw), .O(clk_pix));

endmodule
