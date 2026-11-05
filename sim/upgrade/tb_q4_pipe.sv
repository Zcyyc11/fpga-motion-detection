`timescale 1ns/1ps
module tb_q4_pipe;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,iv=0,mode=0,init=0;
 reg [8:0] addr=0;reg [4:0] shift=0;reg [15:0] thresh=0;
 reg [9:0] cur=0;reg [13:0] refpx=0;
 wire ov;wire [8:0] oa;wire [13:0] wr;
 integer ec[0:9999],er[0:9999],es[0:9999],et[0:9999],em[0:9999],ei[0:9999],ew[0:9999];
 integer fd,n,rc,ad,seen=0;
 background_fixed_pipe #(.AW(9)) dut(clk,rst_n,iv,mode,init,addr,shift,thresh,cur,refpx,ov,oa,wr);
 initial begin
  fd=$fopen("<ABS>/fpga_upgrade_20261022/replay/arithmetic.txt","r");
  if(!fd)$fatal(1,"FAIL missing arithmetic fixture");
  for(n=0;n<10000;n=n+1)begin
   rc=$fscanf(fd,"%d %d %d %d %d %d %d %d\n",ec[n],er[n],es[n],et[n],em[n],ei[n],ad,ew[n]);
   if(rc!=8)$fatal(1,"FAIL fixture");
  end
  repeat(4)@(negedge clk);rst_n=1;
  for(n=0;n<10003;n=n+1)begin
   @(negedge clk);iv=n<10000;
   if(iv)begin addr=n%512;cur=ec[n];refpx=er[n];shift=es[n];thresh=et[n];mode=em[n];init=ei[n];end
   @(posedge clk);#1;
   if(ov)begin
    if(wr!==ew[seen] || oa!==(seen%512))$fatal(1,"FAIL pipe sample=%0d wr=%0d/%0d addr=%0d",seen,wr,ew[seen],oa);
    seen=seen+1;
   end
  end
  if(seen!=10000)$fatal(1,"FAIL lost pipeline samples");
  $display("TAKEOVER_PASS 10000 consecutive Q4 pipelined updates with exact addresses");$finish;
 end
endmodule
