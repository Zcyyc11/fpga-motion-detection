# =============================================================================
#  pynq_z2_hdmi_in.xdc —— HDMI 输入（J10）引脚与时钟约束
#
#  来源：board/pynq-z2_v1.0_official.xdc 的 HDMI Rx 段（原样去 # 注释，逐条对照）。
#  时钟：create_clock -period 13.468 是 dvi2rgb 官方文档 6.1 节对 720p 的示例约束
#        （1 / 74.25 MHz = 13.468 ns，波形 {0.000 5.000} 也来自文档原文）。
#        顶层约束会覆盖 dvi2rgb IP 内部的 165 MHz 默认约束（文档 6.1 明说）。
# =============================================================================

# ---- HDMI RX 引脚（TMDS_33 差分）----
set_property -dict { PACKAGE_PIN N18   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_clk_p }]
set_property -dict { PACKAGE_PIN P19   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_clk_n }]
set_property -dict { PACKAGE_PIN V20   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_d_p[0] }]
set_property -dict { PACKAGE_PIN W20   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_d_n[0] }]
set_property -dict { PACKAGE_PIN T20   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_d_p[1] }]
set_property -dict { PACKAGE_PIN U20   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_d_n[1] }]
set_property -dict { PACKAGE_PIN N20   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_d_p[2] }]
set_property -dict { PACKAGE_PIN P20   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_d_n[2] }]

# ---- HPD（热插拔检测，输出拉高）----
set_property -dict { PACKAGE_PIN T19   IOSTANDARD LVCMOS33  } [get_ports { hdmi_rx_hpd }]

# ---- DDC（I2C，inout 三态）----
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33  } [get_ports { hdmi_rx_scl }]
set_property -dict { PACKAGE_PIN U15   IOSTANDARD LVCMOS33  } [get_ports { hdmi_rx_sda }]

# ---- TMDS 输入时钟：720p60 = 74.25 MHz（官方文档 6.1 示例，覆盖 IP 内部 165M 约束）----
create_clock -period 13.468 -waveform {0.000 5.000} [get_ports hdmi_rx_clk_p]
