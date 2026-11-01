# PixelClk_int and PS FCLK1 are independent clocks. Only the existing CDC
# first stages and the req/ack-held snapshot payload are bounded here.
# A 10ns datapath bound is one period of the faster 100MHz clock; the payload
# remains held until request synchronization, sampling, ack, and return sync.
# UG903: set_max_delay -datapath_only / set_bus_skew for asynchronous buses.
set cdc_first [get_cells -hier -regexp {^core/u_pipe/g_ps[./](u_snap/(req_sync_ff|ack_sync_ff)_reg\[0\]|drop_q1_reg|(thresh|shift|enable|line_x|dwell)_q1_reg.*)$}]
set cdc_chain [get_cells -hier -regexp {^core/u_pipe/g_ps[./](u_snap/(req_sync_ff|ack_sync_ff)_reg.*|drop_q[12]_reg|(thresh|shift|enable|line_x|dwell)_q[12]_reg.*)$}]
set cdc_payload_src [get_cells -hier -regexp {^core/u_pipe/g_ps[./]u_snap/snap_hold_reg.*$}]
set cdc_payload_dst [get_cells -hier -regexp {^core/u_pipe/g_ps[./]u_snap/o_.*_reg.*$}]
set_property ASYNC_REG TRUE $cdc_chain
set_max_delay -datapath_only 10.000 -from [get_clocks {clk_fpga_1 PixelClk_int}] -to [get_pins -of_objects $cdc_first -filter {REF_PIN_NAME == D}]
set_max_delay -datapath_only 10.000 -from $cdc_payload_src -to $cdc_payload_dst
set_bus_skew 5.000 -from $cdc_payload_src -to $cdc_payload_dst
