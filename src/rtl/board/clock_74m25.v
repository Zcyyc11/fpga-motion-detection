`timescale 1ns / 1ps
// clock_74m25：将 125 MHz PL 时钟转换为 74.25 MHz 像素时钟。
// MMCM 参数：M=37.125、D=4、O=15.625，VCO=1160.15625 MHz。
// 74.25 MHz 对应 1650×750 总时序下的 60 Hz；输出经 BUFG 驱动全局网络。
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
