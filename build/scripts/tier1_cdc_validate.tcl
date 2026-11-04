# Run after reading tier1_cdc.xdc into an open synthesized/routed design.
if {[llength $cdc_first]<50 || [llength $cdc_chain]<100 || [llength $cdc_payload_src]<100 || [llength $cdc_payload_dst]<100} {
 error "Tier1 CDC endpoint coverage changed; inspect synthesized names"
}
puts "TIER1_CDC_BOUNDED first=[llength $cdc_first] chain=[llength $cdc_chain] payload_src=[llength $cdc_payload_src] payload_dst=[llength $cdc_payload_dst]"
