`timescale 1ns/1ps
// PS FCLK0=125MHz drives the existing board clocks; FCLK1=100MHz drives AXI.
// Requires a booted PS (PYNQ SD image) and the supplied local startup script.
module board_top_tier1 #(
 parameter integer MODE_BG=1, INPUT_SEL=1, BG_SHIFT=6, BG_FRAC_BITS=4
)(
 inout wire [14:0]DDR_addr,
 inout wire [2:0]DDR_ba,
 inout wire DDR_cas_n,
 inout wire DDR_ck_n,
 inout wire DDR_ck_p,
 inout wire DDR_cke,
 inout wire DDR_cs_n,
 inout wire [3:0]DDR_dm,
 inout wire [31:0]DDR_dq,
 inout wire [3:0]DDR_dqs_n,
 inout wire [3:0]DDR_dqs_p,
 inout wire DDR_odt,
 inout wire DDR_ras_n,
 inout wire DDR_reset_n,
 inout wire DDR_we_n,
 inout wire FIXED_IO_ddr_vrn,
 inout wire FIXED_IO_ddr_vrp,
 inout wire [53:0]FIXED_IO_mio,
 inout wire FIXED_IO_ps_clk,
 inout wire FIXED_IO_ps_porb,
 inout wire FIXED_IO_ps_srstb,
    output wire [3:0] led,                 // LED0..LED3，高电平点亮
    output wire       uart_txd,            // ★线二回传：PL 侧 UART（协议 v0.2，115200-8-N-1），PMOD A ja[0]
    output wire       hdmi_tx_clk_p,       // HDMI J11（source）
    output wire       hdmi_tx_clk_n,
    output wire [2:0] hdmi_tx_d_p,
    output wire [2:0] hdmi_tx_d_n,
    // ---- HDMI J10（sink，输入）----
    input  wire       hdmi_rx_clk_p,
    input  wire       hdmi_rx_clk_n,
    input  wire [2:0] hdmi_rx_d_p,
    input  wire [2:0] hdmi_rx_d_n,
    output wire       hdmi_rx_hpd,         // 热插拔检测（输出拉高）
    inout  wire       hdmi_rx_scl,         // DDC I2C 时钟（信源读 EDID 用）
    inout  wire       hdmi_rx_sda          // DDC I2C 数据
);
wire sys_clk,clk_axi,rst_n_axi,ps_en,ps_we;
wire [5:0] ps_addr;
wire [31:0] ps_wdata,ps_rdata;
ps_system_wrapper ps(
 .DDR_addr(DDR_addr),
 .DDR_ba(DDR_ba),
 .DDR_cas_n(DDR_cas_n),
 .DDR_ck_n(DDR_ck_n),
 .DDR_ck_p(DDR_ck_p),
 .DDR_cke(DDR_cke),
 .DDR_cs_n(DDR_cs_n),
 .DDR_dm(DDR_dm),
 .DDR_dq(DDR_dq),
 .DDR_dqs_n(DDR_dqs_n),
 .DDR_dqs_p(DDR_dqs_p),
 .DDR_odt(DDR_odt),
 .DDR_ras_n(DDR_ras_n),
 .DDR_reset_n(DDR_reset_n),
 .DDR_we_n(DDR_we_n),
 .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
 .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
 .FIXED_IO_mio(FIXED_IO_mio),
 .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
 .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
 .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
 .sys_clk(sys_clk),
 .clk_axi(clk_axi),
 .rst_n_axi(rst_n_axi),
 .ps_en(ps_en),
 .ps_we(ps_we),
 .ps_addr(ps_addr),
 .ps_wdata(ps_wdata),
 .ps_rdata(ps_rdata));
board_top #(.INCLUDE_PS(1),.MODE_BG(MODE_BG),.INPUT_SEL(INPUT_SEL),.BG_SHIFT(BG_SHIFT),.BG_FRAC_BITS(BG_FRAC_BITS)) core(
 .sys_clk(sys_clk),
 .clk_axi(clk_axi),
 .rst_n_axi(rst_n_axi),
 .ps_en(ps_en),
 .ps_we(ps_we),
 .ps_addr(ps_addr),
 .ps_wdata(ps_wdata),
 .ps_rdata(ps_rdata),
 .led(led),
 .uart_txd(uart_txd),
 .hdmi_tx_clk_p(hdmi_tx_clk_p),
 .hdmi_tx_clk_n(hdmi_tx_clk_n),
 .hdmi_tx_d_p(hdmi_tx_d_p),
 .hdmi_tx_d_n(hdmi_tx_d_n),
 .hdmi_rx_clk_p(hdmi_rx_clk_p),
 .hdmi_rx_clk_n(hdmi_rx_clk_n),
 .hdmi_rx_d_p(hdmi_rx_d_p),
 .hdmi_rx_d_n(hdmi_rx_d_n),
 .hdmi_rx_hpd(hdmi_rx_hpd),
 .hdmi_rx_scl(hdmi_rx_scl),
 .hdmi_rx_sda(hdmi_rx_sda));
endmodule
