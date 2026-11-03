# Vivado batch build for combined PYNQ-Z2 + Attach-Z2 package.
set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT [file normalize [file join $SCRIPT_DIR .. ..]]
if {$argc > 0} {
    set BUILD [file normalize [lindex $argv 0]]
} else {
    set BUILD [file join $ROOT build run_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]
}
set PROJ [file join $BUILD vivado]
set REPORT [file join $BUILD reports]
set PART xc7z020clg400-1
if {[info exists ::env(MOTION_IP_REPO)]} {
    set IP_REPO $::env(MOTION_IP_REPO)
} elseif {[file isdirectory [file join $ROOT ip_repository]]} {
    set IP_REPO [file join $ROOT ip_repository]
} else { error "Set MOTION_IP_REPO to the Digilent rgb2dvi IP repository" }
if {[file exists $PROJ]} { error "Refusing to overwrite existing Vivado run: $PROJ" }
file mkdir $BUILD
file mkdir $REPORT
create_project combined_pynq_attach $PROJ -part $PART
set_param general.maxThreads 4
set_property target_language Verilog [current_project]
if {$IP_REPO ne ""} { set_property ip_repo_paths [list $IP_REPO] [current_project]; update_ip_catalog -rebuild }
create_ip -name rgb2dvi -vendor digilentinc.com -library ip -version 1.4 -module_name rgb2dvi_0
set_property -dict [list CONFIG.kGenerateSerialClk {true} CONFIG.kClkPrimitive {MMCM} CONFIG.kClkRange {2} CONFIG.kRstActiveHigh {true} CONFIG.TMDS_BOARD_INTERFACE {Custom}] [get_ips rgb2dvi_0]
generate_target all [get_ips rgb2dvi_0]

create_ip -name dvi2rgb -vendor digilentinc.com -library ip -version 2.0 -module_name dvi2rgb_0
set_property -dict [list CONFIG.kEmulateDDC {true} CONFIG.kRstActiveHigh {true} CONFIG.kAddBUFG {true} CONFIG.kClkRange {3} CONFIG.kEdidFileName {dgl_720p_cea.data} CONFIG.kDebug {false}] [get_ips dvi2rgb_0]
generate_target all [get_ips dvi2rgb_0]

add_files -norecurse [glob -nocomplain [file join $ROOT src rtl *.v]]
add_files -norecurse [glob -nocomplain [file join $ROOT src rtl board *.v]]
add_files -fileset constrs_1 -norecurse [file join $ROOT board pynq_z2_combined.xdc]
set_property top combined_top [current_fileset]
update_compile_order -fileset sources_1
set_property strategy Performance_Explore [get_runs impl_1]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "synthesis failed" }
open_run synth_1
report_utilization -file [file join $REPORT synth_utilization.rpt]
report_timing_summary -file [file join $REPORT synth_timing_summary.rpt]
foreach port [get_ports] {
    if {[get_property PACKAGE_PIN $port] eq "" || [get_property IOSTANDARD $port] eq "DEFAULT"} {
        error "Unconstrained physical port: $port"
    }
}
report_io -file [file join $REPORT synth_io.rpt]
close_design
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
if {![string match "*route_design Complete*" [get_property STATUS [get_runs impl_1]]]} { error "route failed" }
open_run impl_1
write_checkpoint [file join $BUILD combined_top_before_postroute.dcp]
phys_opt_design -directive AggressiveExplore
report_utilization -file [file join $REPORT impl_utilization.rpt]
report_timing_summary -file [file join $REPORT impl_timing_summary.rpt]
report_drc -file [file join $REPORT impl_drc.rpt]
report_cdc -file [file join $REPORT impl_cdc.rpt]
report_io -file [file join $REPORT impl_io.rpt]
report_clock_interaction -file [file join $REPORT impl_clock_interaction.rpt]
check_timing -verbose -file [file join $REPORT check_timing.rpt]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
set blockers [get_drc_violations -quiet -filter {SEVERITY == "Error" || SEVERITY == "Critical Warning"}]
set ts [open [file join $REPORT impl_timing_summary.rpt] r]
set timing_text [read $ts]
close $ts
set pass [expr {$wns ne "" && $whs ne "" && $wns >= 0 && $whs >= 0 && [llength $blockers] == 0 && [string first "All user specified timing constraints are met." $timing_text] >= 0}]
set gate [open [file join $BUILD gate.json] w]
puts $gate [format {{"wns":%s,"whs":%s,"blocking_drc":%d,"passed":%s,"board_verified":false}} $wns $whs [llength $blockers] [expr {$pass ? "true" : "false"}]]
close $gate
write_checkpoint [file join $BUILD combined_top_routed.dcp]
if {!$pass} { error "Timing/DRC gate failed; bitstream not written" }
set OUT [file join $BUILD bitstream]
file mkdir $OUT
write_bitstream [file join $OUT combined_top.bit]
# Pure PL delivery: no PS block design, so do not request an XSA export.
puts "BUILD PASS: [file join $OUT combined_top.bit]"
