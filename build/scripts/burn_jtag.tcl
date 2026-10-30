# JTAG 烧写 bit（Vivado batch，不依赖板子系统）
# 用法：vivado -mode batch -source build/scripts/burn_jtag.tcl -tclargs <bit文件名>
#   例：vivado -mode batch -source build/scripts/burn_jtag.tcl -tclargs board_top_hdmiin.bit
set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT       [file normalize [file join $SCRIPT_DIR .. ..]]
set BIT        [lindex $argv 0]
if {$BIT eq ""} { set BIT "board_top_hdmiin.bit" }
set BITFILE    [file join $ROOT build bitstream $BIT]
open_hw_manager
connect_hw_server
open_hw_target
set dev [current_hw_device]
puts "== DEVICE: $dev =="
puts "== BIT: $BITFILE =="
set_property PROGRAM.FILE $BITFILE $dev
program_hw_devices $dev
puts "== PROGRAM OK =="
close_hw_target
disconnect_hw_server
close_hw_manager
