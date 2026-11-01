# =============================================================================
#  PYNQ-Z2 + Attach-Z2 整机约束（HDMI 输入 + 全部外设）
#
#  主板引脚：官方 pynq-z2_v1.0.xdc（逐条对照）
#  Attach 引脚：FPGA-Attach-Z2-RevD.pdf 第 1 页 J1/J3/J4 读图所得
#               **已实物验证：9 位数码管全亮、WS2812 点亮**
# =============================================================================

# ---- 125 MHz 参考时钟 ----------------------------------------------------------
set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { sys_clk }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { sys_clk }];

# ---- 按键 / 拨码 --------------------------------------------------------------
set_property -dict { PACKAGE_PIN D19   IOSTANDARD LVCMOS33 } [get_ports { btn[0] }];
set_property -dict { PACKAGE_PIN D20   IOSTANDARD LVCMOS33 } [get_ports { btn[1] }];
set_property -dict { PACKAGE_PIN L20   IOSTANDARD LVCMOS33 } [get_ports { btn[2] }];
set_property -dict { PACKAGE_PIN L19   IOSTANDARD LVCMOS33 } [get_ports { btn[3] }];
set_property -dict { PACKAGE_PIN M20   IOSTANDARD LVCMOS33 } [get_ports { sw[0] }];
set_property -dict { PACKAGE_PIN M19   IOSTANDARD LVCMOS33 } [get_ports { sw[1] }];

# ---- 单色 LED0-3 --------------------------------------------------------------
set_property -dict { PACKAGE_PIN R14   IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

# ---- 三色 LED LD4 / LD5（三极管反相，极性已在 RTL 里取反）------------------------
set_property -dict { PACKAGE_PIN N15   IOSTANDARD LVCMOS33 } [get_ports { led4_r }];
set_property -dict { PACKAGE_PIN G17   IOSTANDARD LVCMOS33 } [get_ports { led4_g }];
set_property -dict { PACKAGE_PIN L15   IOSTANDARD LVCMOS33 } [get_ports { led4_b }];
set_property -dict { PACKAGE_PIN M15   IOSTANDARD LVCMOS33 } [get_ports { led5_r }];
set_property -dict { PACKAGE_PIN L14   IOSTANDARD LVCMOS33 } [get_ports { led5_g }];
set_property -dict { PACKAGE_PIN G14   IOSTANDARD LVCMOS33 } [get_ports { led5_b }];

# ---- HDMI 输出 J11（source）---------------------------------------------------
set_property -dict { PACKAGE_PIN L16   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_clk_p }];
set_property -dict { PACKAGE_PIN L17   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_clk_n }];
set_property -dict { PACKAGE_PIN K17   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_p[0] }];
set_property -dict { PACKAGE_PIN K18   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_n[0] }];
set_property -dict { PACKAGE_PIN K19   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_p[1] }];
set_property -dict { PACKAGE_PIN J19   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_n[1] }];
set_property -dict { PACKAGE_PIN J18   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_p[2] }];
set_property -dict { PACKAGE_PIN H18   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_n[2] }];

# ---- HDMI 输入 J10（sink）-----------------------------------------------------
set_property -dict { PACKAGE_PIN N18   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_clk_p }];
set_property -dict { PACKAGE_PIN P19   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_clk_n }];
set_property -dict { PACKAGE_PIN V20   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_d_p[0] }];
set_property -dict { PACKAGE_PIN W20   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_d_n[0] }];
set_property -dict { PACKAGE_PIN T20   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_d_p[1] }];
set_property -dict { PACKAGE_PIN U20   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_d_n[1] }];
set_property -dict { PACKAGE_PIN N20   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_d_p[2] }];
set_property -dict { PACKAGE_PIN P20   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_d_n[2] }];
set_property -dict { PACKAGE_PIN T19   IOSTANDARD LVCMOS33 } [get_ports { hdmi_rx_hpd }];
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports { hdmi_rx_scl }];
set_property -dict { PACKAGE_PIN U15   IOSTANDARD LVCMOS33 } [get_ports { hdmi_rx_sda }];
# DDC 是 I2C 开漏，需要上拉
set_property PULLUP true [get_ports { hdmi_rx_scl }];
set_property PULLUP true [get_ports { hdmi_rx_sda }];

# ---- UART 遥测 → PMOD B（JB1_P = W14）----------------------------------------
# ★ 原方案在 PMOD A / Y18，但 Y18 已被 Attach 的 LCD_SDAT 占用（Pmod A 与
#   RPi 排针共享引脚，官方手册第 24 页明文），故迁到 Pmod B。
set_property -dict { PACKAGE_PIN W14   IOSTANDARD LVCMOS33 } [get_ports { uart_txd }];

# =============================================================================
#  Attach-Z2 外设（读图 + 实物已验证）
# =============================================================================

# ---- 数码管段选 A..G（seg[0]=A ... seg[6]=G）-----------------------------------
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { attach_seg[0] }];
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { attach_seg[1] }];
set_property -dict { PACKAGE_PIN V18   IOSTANDARD LVCMOS33 } [get_ports { attach_seg[2] }];
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { attach_seg[3] }];
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 } [get_ports { attach_seg[4] }];
set_property -dict { PACKAGE_PIN P18   IOSTANDARD LVCMOS33 } [get_ports { attach_seg[5] }];
set_property -dict { PACKAGE_PIN R16   IOSTANDARD LVCMOS33 } [get_ports { attach_seg[6] }];

# ---- 数码管位选 DIG1..DIG9 ----------------------------------------------------
set_property -dict { PACKAGE_PIN P16   IOSTANDARD LVCMOS33 } [get_ports { attach_digit[0] }];
set_property -dict { PACKAGE_PIN P15   IOSTANDARD LVCMOS33 } [get_ports { attach_digit[1] }];
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { attach_digit[2] }];
set_property -dict { PACKAGE_PIN Y13   IOSTANDARD LVCMOS33 } [get_ports { attach_digit[3] }];
set_property -dict { PACKAGE_PIN V13   IOSTANDARD LVCMOS33 } [get_ports { attach_digit[4] }];
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { attach_digit[5] }];
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { attach_digit[6] }];
set_property -dict { PACKAGE_PIN U13   IOSTANDARD LVCMOS33 } [get_ports { attach_digit[7] }];
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { attach_digit[8] }];

# ---- WS2812 / 蜂鸣器 ---------------------------------------------------------
set_property -dict { PACKAGE_PIN Y9    IOSTANDARD LVCMOS33 } [get_ports { attach_ws2812_din }];
set_property -dict { PACKAGE_PIN Y8    IOSTANDARD LVCMOS33 } [get_ports { buzzer }];

# ---- LCD（ST7789 SPI）-------------------------------------------------------
set_property -dict { PACKAGE_PIN Y6    IOSTANDARD LVCMOS33 } [get_ports { attach_lcd_sck }];
set_property -dict { PACKAGE_PIN Y18   IOSTANDARD LVCMOS33 } [get_ports { attach_lcd_mosi }];
set_property -dict { PACKAGE_PIN C20   IOSTANDARD LVCMOS33 } [get_ports { attach_lcd_cs_n }];
set_property -dict { PACKAGE_PIN U7    IOSTANDARD LVCMOS33 } [get_ports { attach_lcd_dc }];
set_property -dict { PACKAGE_PIN V6    IOSTANDARD LVCMOS33 } [get_ports { attach_lcd_rst_n }];
set_property -dict { PACKAGE_PIN V7    IOSTANDARD LVCMOS33 } [get_ports { attach_lcd_bkl }];

# ---- 触摸 I2C（CST816T，0xD4）------------------------------------------------
set_property -dict { PACKAGE_PIN U19   IOSTANDARD LVCMOS33 } [get_ports { attach_touch_scl }];
set_property -dict { PACKAGE_PIN W10   IOSTANDARD LVCMOS33 } [get_ports { attach_touch_sda }];

# ---- 未使用的时钟引脚处理 ------------------------------------------------------
# PYNQ-Z2 的 B9(R19/G15 等) 是 HDMI CEC/DDC 备用，本设计不接。
