module board_top_legacy #(
    parameter integer MODE_BG   = 0,     // 0 = 帧差法（v1）／1 = 背景建模（v2）
    parameter integer BG_SHIFT = 6,
    parameter integer BG_FRAC_BITS = 0,
    parameter integer INPUT_SEL = 0      // 0 = 内部自测激励／1 = 真实 HDMI 输入
)(
    input  wire       sys_clk,             // 125 MHz，H16
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

board_top #(.MODE_BG(MODE_BG),.INPUT_SEL(INPUT_SEL),.BG_SHIFT(BG_SHIFT),.BG_FRAC_BITS(BG_FRAC_BITS)) core (
 .sys_clk(sys_clk),
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
 .hdmi_rx_sda(hdmi_rx_sda),
 .clk_axi(1'b0),.rst_n_axi(1'b0),.ps_en(1'b0),.ps_we(1'b0),.ps_addr(6'd0),.ps_wdata(32'd0),.ps_rdata());
endmodule
