# prime_ipcache.tcl - one-shot: import existing project's generated IP results
# into the shared IP cache dir, so the next fresh build hits the cache.
# Run: vivado -mode batch -nojournal -nolog -source build/scripts/prime_ipcache.tcl

set SCRIPT_DIR  [file dirname [file normalize [info script]]]
set ROOT        [file normalize [file join $SCRIPT_DIR .. ..]]
set XPR         [file join $ROOT build vivado fpga_motion_detection.xpr]
set IP_CACHE_DIR [file normalize [file join $ROOT .. fmd_ip_cache]]

if {![file exists $XPR]} {
    puts "ERROR: project not found: $XPR"
    exit 1
}

open_project $XPR
file mkdir $IP_CACHE_DIR
set_property ip_output_repo $IP_CACHE_DIR [current_project]
set_property ip_cache_permissions {read write} [current_project]

if {[catch {config_ip_cache -import} err]} {
    puts "WARN: config_ip_cache -import failed: $err"
    puts "(cache stays empty; next build just re-synthesizes IPs as before)"
} else {
    puts "IP cache primed at $IP_CACHE_DIR"
}
close_project
exit 0
