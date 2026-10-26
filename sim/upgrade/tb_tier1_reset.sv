`timescale 1ns/1ps
module tb_tier1_reset;
 parameter AUX_LEVEL=1;
 reg clk=0;always #5 clk=~clk;
 reg ext_n=0,dcm=1;
 wire [0:0] peripheral_n,interconnect_n;
 ps_system_axi_reset_0 dut(.slowest_sync_clk(clk),.ext_reset_in(ext_n),
  .aux_reset_in(AUX_LEVEL!=0),.mb_debug_sys_rst(1'b0),.dcm_locked(dcm),
  .peripheral_aresetn(peripheral_n),.interconnect_aresetn(interconnect_n),
  .mb_reset(),.bus_struct_reset(),.peripheral_reset());
 task released;
 begin repeat(300)@(negedge clk);
  if(peripheral_n!==1 || interconnect_n!==1)$fatal(1,"FAIL reset did not release aux=%0d",AUX_LEVEL);
 end endtask
 initial begin
  repeat(30)@(negedge clk);ext_n=1;released;
  ext_n=0;repeat(30)@(negedge clk);
  if(peripheral_n!==0)$fatal(1,"FAIL external reset assertion");
  ext_n=1;released;
  dcm=0;repeat(30)@(negedge clk);
  if(peripheral_n!==0)$fatal(1,"FAIL lost clock lock reset");
  dcm=1;released;
  $display("TAKEOVER_PASS generated Tier1 reset IP releases/reasserts with real polarity");$finish;
 end
endmodule
