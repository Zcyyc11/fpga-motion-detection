# Standalone PS/AXI BD generation and validation. Does not program hardware.
set ROOT D:/fpga_upgrade_20261022/work
set OUT D:/fpga_upgrade_20261022/tier1d
file mkdir $OUT
create_project tier1 $OUT/project -part xc7z020clg400-1
set_property board_part tul.com.tw:pynq-z2:part0:1.0 [current_project]
set_property target_language Verilog [current_project]
add_files $ROOT/src/rtl/board/axi_lite_slave.v
create_bd_design ps_system
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} $ps
set_property -dict [list CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_EN_CLK0_PORT {1} CONFIG.PCW_EN_CLK1_PORT {1} CONFIG.PCW_EN_RST1_PORT {1} CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {125} CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {100}] $ps
set bridge [create_bd_cell -type module -reference axi_lite_slave bridge]
set ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_ic]
set_property CONFIG.NUM_MI 1 $ic
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_ic/M00_AXI] [get_bd_intf_pins bridge/S_AXI]
set reset [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 axi_reset]
set one [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 constant_one]
set zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 constant_zero]
set_property CONFIG.CONST_VAL 0 $zero
connect_bd_net [get_bd_pins ps7/FCLK_CLK1] [get_bd_pins ps7/M_AXI_GP0_ACLK] [get_bd_pins axi_ic/ACLK] [get_bd_pins axi_ic/S00_ACLK] [get_bd_pins axi_ic/M00_ACLK] [get_bd_pins bridge/S_AXI_ACLK] [get_bd_pins axi_reset/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET1_N] [get_bd_pins axi_reset/ext_reset_in]
connect_bd_net [get_bd_pins constant_one/dout] [get_bd_pins axi_reset/dcm_locked]
connect_bd_net [get_bd_pins constant_zero/dout] [get_bd_pins axi_reset/aux_reset_in] [get_bd_pins axi_reset/mb_debug_sys_rst]
connect_bd_net [get_bd_pins axi_reset/interconnect_aresetn] [get_bd_pins axi_ic/ARESETN]
connect_bd_net [get_bd_pins axi_reset/peripheral_aresetn] [get_bd_pins axi_ic/S00_ARESETN] [get_bd_pins axi_ic/M00_ARESETN] [get_bd_pins bridge/S_AXI_ARESETN]
foreach name {ps_en ps_we ps_addr ps_wdata ps_rdata} {
  make_bd_pins_external [get_bd_pins bridge/$name]
  set port [get_bd_ports ${name}_0]
  set_property name $name $port
}
foreach {pin name freq} {ps7/FCLK_CLK0 sys_clk 125000000 ps7/FCLK_CLK1 clk_axi 100000000} {
  set port [create_bd_port -dir O -type clk $name]
  set_property CONFIG.FREQ_HZ $freq $port
  connect_bd_net [get_bd_pins $pin] $port
}
set port [create_bd_port -dir O -type rst rst_n_axi]
set_property CONFIG.POLARITY ACTIVE_LOW $port
connect_bd_net [get_bd_pins axi_reset/peripheral_aresetn] $port
assign_bd_address -offset 0x43C00000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs bridge/S_AXI/reg0] -force
validate_bd_design
save_bd_design
generate_target all [get_files ps_system.bd]
make_wrapper -files [get_files ps_system.bd] -top
write_bd_tcl $OUT/ps_system_recreate.tcl
puts TIER1_BD_VALIDATED
exit
