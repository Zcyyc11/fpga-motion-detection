# Called on the actual routed Tier1 design before any deliverable bit is written.
# Re-query coverage: XDC variables do not survive project/run process boundaries.
set cdc_first [get_cells -hier -regexp {^core/u_pipe/g_ps[./](u_snap/(req_sync_ff|ack_sync_ff)_reg\[0\]|drop_q1_reg|(thresh|shift|enable|line_x|dwell)_q1_reg.*)$}]
set cdc_chain [get_cells -hier -regexp {^core/u_pipe/g_ps[./](u_snap/(req_sync_ff|ack_sync_ff)_reg.*|drop_q[12]_reg|(thresh|shift|enable|line_x|dwell)_q[12]_reg.*)$}]
set cdc_payload_src [get_cells -hier -regexp {^core/u_pipe/g_ps[./]u_snap/snap_hold_reg.*$}]
set cdc_payload_dst [get_cells -hier -regexp {^core/u_pipe/g_ps[./]u_snap/o_.*_reg.*$}]
source [file join $SCRIPT_DIR tier1_cdc_validate.tcl]
if {[llength [get_cells -hier -regexp {^core/u_pipe/g_ps[./]drop_q[12]_reg$}]] != 2} {
    error "UART drop status synchronizer missing after synthesis"
}
foreach cell $cdc_chain {
    if {![get_property ASYNC_REG $cell]} { error "Missing ASYNC_REG: $cell" }
}
set cdc_text [report_cdc -details -return_string]
set fh [open [file join $REPORT_DIR impl_cdc.rpt] w]; puts $fh $cdc_text; close $fh
foreach line [split $cdc_text "\n"] {
    if {[string match *Critical* $line] && [string match *core/u_pipe/* $line]} {
        error "Unresolved user-RTL CDC critical: $line"
    }
}
# Legacy dvi2rgb reset/fanout findings are retained, not waived or hidden.
set skew_text [report_bus_skew -return_string]
set fh [open [file join $REPORT_DIR impl_bus_skew.rpt] w]; puts $fh $skew_text; close $fh
set skew_matches [regexp -all -inline {Slack\s+\((MET|VIOLATED)\)\s*:\s*([-0-9.]+)ns} $skew_text]
if {[llength $skew_matches] < 3} { error "Missing bus-skew path evidence" }
foreach {full state slack} $skew_matches {
    if {$state ne "MET" || ![string is double -strict $slack] || $slack < 0} {
        error "Bus skew failed: $full"
    }
}
report_exceptions -file [file join $REPORT_DIR impl_exceptions.rpt]
puts "TIER1_CDC_AND_BUS_SKEW_GATES_PASSED (legacy HDMI IP findings retained)"
