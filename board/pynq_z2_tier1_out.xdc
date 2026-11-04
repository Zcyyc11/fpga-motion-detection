# Tier1: 125MHz comes from PS FCLK0; no H16 clock port.
# =============================================================================
#  PYNQ-Z2 板级约束 —— HDMI 输出（J11, source）+ 125 MHz 参考时钟 + 4 个 LED
#
#  来源与口径（每条都能指回原文，不是猜的）：
#    · 管脚号与 IOSTANDARD：官方 `pynq-z2_v1.0.xdc`（依元素课程材料里的那份，
#      原文全部是注释行，按需取消注释）。本文件把它**实际启用的那几条**抄出来并注明出处。
#    · 同目录 `pynq-z2_v1.0_official.xdc` 是那份原件的完整留存，便于逐条对照。
#
#  ★ TMDS 输出的电平是 **TMDS_33**，不是 LVCMOS33 —— 这两种不能混。
#    板载 HDMI 引脚标的是 LVCMOS33，而 TMDS 差分对必须用 TMDS_33；
#    写错不会在综合阶段报错，会在实现阶段以 DRC / 布线错误的形式炸出来。
#
#  ★ 关于模拟视频时序：本设计的像素时钟由 MMCM 从 125 MHz 生成（74.25 MHz），
#    720p60 总时序 1650×750。同步极性为**正**（SYNC_POS=1），
#    与 rgb2dvi 把 vid_pHSync/vid_pVSync 直接当 TMDS 控制位用的做法一致。
# =============================================================================

# ---- 125 MHz PL 参考时钟（H16）------------------------------------------------

# ---- 用户 LED（LED0..LED3，共 4 个，高电平点亮）--------------------------------
set_property -dict { PACKAGE_PIN R14   IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

# ---- HDMI 输出 J11（source）：4 对差分，3 数据 + 1 时钟 ------------------------
set_property -dict { PACKAGE_PIN L16   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_clk_p }];
set_property -dict { PACKAGE_PIN L17   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_clk_n }];

set_property -dict { PACKAGE_PIN K17   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_p[0] }];
set_property -dict { PACKAGE_PIN K18   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_n[0] }];

set_property -dict { PACKAGE_PIN K19   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_p[1] }];
set_property -dict { PACKAGE_PIN J19   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_n[1] }];

set_property -dict { PACKAGE_PIN J18   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_p[2] }];
set_property -dict { PACKAGE_PIN H18   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_n[2] }];

# ---- 未用到的板级引脚 ---------------------------------------------------------
# HDMI 的 HPD / CEC / DDC（B9,B13,R19,G15 等）本设计不接，因此不写约束：
# 没有对应端口就不会被实现工具拉进去。等接 HDMI 输入的版本再补。

# ---- 线二回传 UART（PL 侧，协议 v0.2 115200-8-N-1）----------------------------
# uart_txd → PMOD A 引脚 1（ja[0]，Y18）。不与 HDMI 收发同 bank 冲突（bank 34），
# GND 就近取 PMOD A 的 pin 7/8。出处：pynq-z2_v1.0_official.xdc 的 PmodA 段。
set_property -dict { PACKAGE_PIN Y18   IOSTANDARD LVCMOS33 } [get_ports { uart_txd }];
