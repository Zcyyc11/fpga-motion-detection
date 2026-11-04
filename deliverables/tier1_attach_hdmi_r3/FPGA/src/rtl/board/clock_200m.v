`timescale 1ns / 1ps
// clock_200m：将 125 MHz PL 时钟转换为 dvi2rgb 所需的 200 MHz 参考时钟。
// 参考来源：Digilent dvi2rgb 文档中的 RefClk 接口规格。
// MMCM 参数：M=64、D=8、O=5，VCO=1000 MHz，输出=200 MHz。
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
