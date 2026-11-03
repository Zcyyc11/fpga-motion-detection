# Create a portable GUI project without starting synthesis or implementation.
set ROOT [file normalize [file join [file dirname [info script]] .. ..]]
set PROJ [file join $ROOT project]
if {[file exists $PROJ]} { error "Project already exists: $PROJ; open its XPR instead" }
if {[info exists ::env(MOTION_IP_REPO)]} {
  set IP_REPO $::env(MOTION_IP_REPO)
} else { set IP_REPO [file join $ROOT ip_repository] }
if {![file isdirectory $IP_REPO]} { error "Missing rgb2dvi repository: $IP_REPO" }
create_project combined_pynq_attach $PROJ -part xc7z020clg400-1
set_property target_language Verilog [current_project]
set_property ip_repo_paths [list $IP_REPO] [current_project]
update_ip_catalog -rebuild
create_ip -name rgb2dvi -vendor digilentinc.com -library ip -version 1.4 -module_name rgb2dvi_0
set_property -dict [list CONFIG.kGenerateSerialClk {true} CONFIG.kClkPrimitive {MMCM} CONFIG.kClkRange {2} CONFIG.kRstActiveHigh {true} CONFIG.TMDS_BOARD_INTERFACE {Custom}] [get_ips rgb2dvi_0]
generate_target all [get_ips rgb2dvi_0]

create_ip -name dvi2rgb -vendor digilentinc.com -library ip -version 2.0 -module_name dvi2rgb_0
set_property -dict [list CONFIG.kEmulateDDC {true} CONFIG.kRstActiveHigh {true} CONFIG.kAddBUFG {true} CONFIG.kClkRange {3} CONFIG.kEdidFileName {dgl_720p_cea.data} CONFIG.kDebug {false}] [get_ips dvi2rgb_0]
generate_target all [get_ips dvi2rgb_0]

add_files -norecurse [glob [file join $ROOT src rtl *.v]]
add_files -norecurse [glob [file join $ROOT src rtl board *.v]]
add_files -fileset constrs_1 -norecurse [file join $ROOT board pynq_z2_combined.xdc]
set_property top combined_top [current_fileset]
update_compile_order -fileset sources_1
puts "PROJECT_READY: [file join $PROJ combined_pynq_attach.xpr]"
