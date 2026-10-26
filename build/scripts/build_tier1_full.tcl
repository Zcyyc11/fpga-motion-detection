# Run in a new MOTION_BUILD_DIR with Vivado 2025.2 and the Digilent IP repo.
set ::env(MOTION_BUILD_LIBRARY) 1
source [file join [file dirname [info script]] build_vivado.tcl]
set TOP board_top_tier1
set ::env(MOTION_BOARD_PART) tul.com.tw:pynq-z2:part0:1.0
stage_setup
open_project $XPR
set ::env(MOTION_TIER1_IN_PROJECT) 1
set ::env(MOTION_TIER1_OUT) [file join $BUILD_DIR ps]
source [file join $SCRIPT_DIR create_tier1.tcl]
remove_files [get_files [file join $BOARD_DIR pynq_z2_hdmi_out.xdc]]
add_files -fileset constrs_1 -norecurse [file join $BOARD_DIR pynq_z2_tier1_out.xdc]
set_property top $TOP [current_fileset]
update_compile_order -fileset sources_1
close_project
stage_synth
stage_impl
stage_bit
open_project $XPR
open_run impl_1
write_hw_platform -fixed -file [file join $BUILD_DIR board_top_tier1.xsa]
puts TIER1_FULL_BUILD_PASSED
exit
