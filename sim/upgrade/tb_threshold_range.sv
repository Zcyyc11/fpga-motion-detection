`timescale 1ns/1ps
module tb_threshold_range;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0, in_valid=0;
 reg [15:0] thresh=0; reg [10:0] absdiff=0;
 wire valid_out,mask;
 integer t,d,cases=0;
 threshold dut(clk,rst_n,thresh,in_valid,absdiff,valid_out,mask);
 task check(input integer tv,input integer dv);
 begin
  @(negedge clk); thresh=tv; absdiff=dv; in_valid=1;
  @(posedge clk); #1;
  if(valid_out!==1 || mask!==(dv>tv))
    $fatal(1,"FAIL threshold=%0d diff=%0d mask=%b expected=%0d",tv,dv,mask,dv>tv);
  cases=cases+1;
 end endtask
 initial begin
  repeat(3) @(negedge clk); rst_n=1;
  check(2048,1); check(65535,2047);
  for(t=0;t<65536;t=t+1) begin
   check(t,0); check(t,70); check(t,1023); check(t,2047);
  end
  $display("TAKEOVER_PASS threshold full 16-bit range cases=%0d",cases); $finish;
 end
endmodule
