# PYNQ-Z2 与 Attach-Z2 Rev.D 集成板级约束。
# 覆盖 J10 HDMI 输入、J11 HDMI 输出、125 MHz 参考时钟和板上交互接口。
# 主板引脚来源：官方 pynq-z2_v1.0.xdc；扩展板引脚来源：FPGA-Attach-Z2-RevD.pdf。
# HDMI TMDS 差分接口使用 TMDS_33，外部输入按 720p60 时序约束。

set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { sys_clk }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { sys_clk }];

# 用户 LED（LED0..LED3，共 4 个，高电平点亮）
set_property -dict { PACKAGE_PIN R14   IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

# PYNQ-Z2 按键/拨码（官方 pynq-z2_v1.0.xdc）
set_property -dict { PACKAGE_PIN D19   IOSTANDARD LVCMOS33 } [get_ports { btn[0] }];
set_property -dict { PACKAGE_PIN D20   IOSTANDARD LVCMOS33 } [get_ports { btn[1] }];
set_property -dict { PACKAGE_PIN L20   IOSTANDARD LVCMOS33 } [get_ports { btn[2] }];
set_property -dict { PACKAGE_PIN L19   IOSTANDARD LVCMOS33 } [get_ports { btn[3] }];
set_property -dict { PACKAGE_PIN M20   IOSTANDARD LVCMOS33 } [get_ports { sw[0] }];
set_property -dict { PACKAGE_PIN M19   IOSTANDARD LVCMOS33 } [get_ports { sw[1] }];

# PYNQ-Z2 RGB LED（官方 pynq-z2_v1.0.xdc）
set_property -dict { PACKAGE_PIN N15   IOSTANDARD LVCMOS33 } [get_ports { led4_r }];
set_property -dict { PACKAGE_PIN G17   IOSTANDARD LVCMOS33 } [get_ports { led4_g }];
set_property -dict { PACKAGE_PIN L15   IOSTANDARD LVCMOS33 } [get_ports { led4_b }];
set_property -dict { PACKAGE_PIN M15   IOSTANDARD LVCMOS33 } [get_ports { led5_r }];
set_property -dict { PACKAGE_PIN L14   IOSTANDARD LVCMOS33 } [get_ports { led5_g }];
set_property -dict { PACKAGE_PIN G14   IOSTANDARD LVCMOS33 } [get_ports { led5_b }];

# HDMI 输出 J11（source）：4 对差分，3 数据 + 1 时钟
set_property -dict { PACKAGE_PIN L16   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_clk_p }];
set_property -dict { PACKAGE_PIN L17   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_clk_n }];

set_property -dict { PACKAGE_PIN K17   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_p[0] }];
set_property -dict { PACKAGE_PIN K18   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_n[0] }];

set_property -dict { PACKAGE_PIN K19   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_p[1] }];
set_property -dict { PACKAGE_PIN J19   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_n[1] }];

set_property -dict { PACKAGE_PIN J18   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_p[2] }];
set_property -dict { PACKAGE_PIN H18   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_n[2] }];

# Attach-Z2 Rev.D（FPGA-Attach-Z2-RevD.pdf，Sheet 1/2）
# 数码管网络由 J3/J4 引出；索引按 combined_top 的 A..G、DIG1..DIG9 定义。
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { attach_seg[0] }]; # SEG7_A, J4-8
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { attach_seg[1] }]; # SEG7_B, J3-1
set_property -dict { PACKAGE_PIN V18   IOSTANDARD LVCMOS33 } [get_ports { attach_seg[2] }]; # SEG7_C, J3-2
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { attach_seg[3] }]; # SEG7_D, J3-3
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 } [get_ports { attach_seg[4] }]; # SEG7_E, J3-4
set_property -dict { PACKAGE_PIN P18   IOSTANDARD LVCMOS33 } [get_ports { attach_seg[5] }]; # SEG7_F, J3-5
set_property -dict { PACKAGE_PIN R16   IOSTANDARD LVCMOS33 } [get_ports { attach_seg[6] }]; # SEG7_G, J4-7

# SEG7_DIG1 位于最右侧，SEG7_DIG9 位于最左侧。
# attach_digit[i] 对应 SEG7_DIG(9-i)，使 disp_digit[0] 显示在最左侧。
# 引脚来源：Attach-Z2 Rev.D 原理图。
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { attach_digit[0] }]; # SEG7_DIG9, J4-1
set_property -dict { PACKAGE_PIN U13   IOSTANDARD LVCMOS33 } [get_ports { attach_digit[1] }]; # SEG7_DIG8, J4-3
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { attach_digit[2] }]; # SEG7_DIG7, J4-2
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { attach_digit[3] }]; # SEG7_DIG6, J4-5
set_property -dict { PACKAGE_PIN V13   IOSTANDARD LVCMOS33 } [get_ports { attach_digit[4] }]; # SEG7_DIG5, J4-4
set_property -dict { PACKAGE_PIN Y13   IOSTANDARD LVCMOS33 } [get_ports { attach_digit[5] }]; # SEG7_DIG4, J3-8
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { attach_digit[6] }]; # SEG7_DIG3, J3-6
set_property -dict { PACKAGE_PIN P15   IOSTANDARD LVCMOS33 } [get_ports { attach_digit[7] }]; # SEG7_DIG2, J3-10
set_property -dict { PACKAGE_PIN P16   IOSTANDARD LVCMOS33 } [get_ports { attach_digit[8] }]; # SEG7_DIG1, J3-9

# J1 PYNQZ2_RPI_IDE 网络：WS2812 串链、LCD SPI、触摸 I2C 与蜂鸣器。
set_property -dict { PACKAGE_PIN Y9    IOSTANDARD LVCMOS33 } [get_ports { attach_ws2812_din }]; # LED_DIN, J1-40
set_property -dict { PACKAGE_PIN Y6    IOSTANDARD LVCMOS33 } [get_ports { attach_lcd_sck }];     # LCD_SCK, J1-10
set_property -dict { PACKAGE_PIN Y18   IOSTANDARD LVCMOS33 } [get_ports { attach_lcd_mosi }];    # LCD_SDAT, J1-7
set_property -dict { PACKAGE_PIN C20   IOSTANDARD LVCMOS33 } [get_ports { attach_lcd_cs_n }];    # LCD_nCS, J1-12
set_property -dict { PACKAGE_PIN U7    IOSTANDARD LVCMOS33 } [get_ports { attach_lcd_dc }];      # LCD_DCx, J1-11
set_property -dict { PACKAGE_PIN V6    IOSTANDARD LVCMOS33 } [get_ports { attach_lcd_rst_n }];   # LCD_RSTx, J1-8
set_property -dict { PACKAGE_PIN V7    IOSTANDARD LVCMOS33 } [get_ports { attach_lcd_bkl }];     # LCD_BKLT, J1-13
set_property -dict { PACKAGE_PIN U19   IOSTANDARD LVCMOS33 } [get_ports { attach_touch_scl }];   # SCL, J1-26
set_property -dict { PACKAGE_PIN W10   IOSTANDARD LVCMOS33 } [get_ports { attach_touch_sda }];   # SDA, J1-23
set_property -dict { PACKAGE_PIN Y8    IOSTANDARD LVCMOS33 } [get_ports { buzzer }];             # BUZ, J1-35

# NSTD/UCIO 检查使用工具默认严重级别。

# Human-operated asynchronous inputs: only the pad-to-first synchronizer stage
# is asynchronous. The second stage and all downstream logic remain timed.
set_false_path -from [get_ports {btn[*]}] -to [get_cells -hier -filter {NAME =~ btn_meta_reg*}]
set_false_path -from [get_ports {sw[1]}] -to [get_cells -hier -filter {NAME =~ dark_meta_reg*}]
# These peripherals have no external capture clock. Their serial/scan/beep
# protocol periods are tested at 74.25 MHz; this excludes only pad endpoints.
# HDMI timing is handled by the rgb2dvi IP and is NOT excluded here.
set_false_path -to [get_ports {led[*] led4_* led5_* buzzer attach_*}]

# J10 HDMI 输入引脚来源：官方 pynq-z2_v1.0.xdc 的 HDMI Rx 定义。
# 接收时钟约束参考 Digilent dvi2rgb 文档的 720p 示例。

# HDMI RX 引脚（TMDS_33 差分）
set_property -dict { PACKAGE_PIN N18   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_clk_p }]
set_property -dict { PACKAGE_PIN P19   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_clk_n }]
set_property -dict { PACKAGE_PIN V20   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_d_p[0] }]
set_property -dict { PACKAGE_PIN W20   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_d_n[0] }]
set_property -dict { PACKAGE_PIN T20   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_d_p[1] }]
set_property -dict { PACKAGE_PIN U20   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_d_n[1] }]
set_property -dict { PACKAGE_PIN N20   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_d_p[2] }]
set_property -dict { PACKAGE_PIN P20   IOSTANDARD TMDS_33  } [get_ports { hdmi_rx_d_n[2] }]

# HPD（热插拔检测，输出拉高）
set_property -dict { PACKAGE_PIN T19   IOSTANDARD LVCMOS33  } [get_ports { hdmi_rx_hpd }]

# DDC（I2C，inout 三态）
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33  } [get_ports { hdmi_rx_scl }]
set_property -dict { PACKAGE_PIN U15   IOSTANDARD LVCMOS33  } [get_ports { hdmi_rx_sda }]

# TMDS 输入时钟：720p60 = 74.25 MHz（官方文档 6.1 示例，覆盖 IP 内部 165M 约束）
create_clock -period 13.468 -waveform {0.000 5.000} [get_ports hdmi_rx_clk_p]
