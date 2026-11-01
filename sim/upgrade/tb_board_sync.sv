`timescale 1ns/1ps
module tb_board_sync;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,hs=0,vs=0,sof=0,de=0;
 reg [15:0] x=0;
 reg phs=0,pvs=0,psof=0,pde=0;
 integer i;
 board_top #(.INPUT_SEL(1)) dut(.sys_clk(clk),.clk_axi(clk),.rst_n_axi(rst),
  .ps_en(1'b0),.ps_we(1'b0),.ps_addr(6'd0),.ps_wdata(32'd0));
 initial begin
  force dut.pixel_clk_rx=clk;force dut.rst_n=rst;
  force dut.in_hs=hs;force dut.in_vs=vs;force dut.in_sof=sof;
  force dut.in_de=de;force dut.in_x=x;force dut.in_y=16'd0;force dut.in_pix=24'h808080;
  repeat(4)@(negedge clk);rst=1;
  for(i=0;i<40;i=i+1)begin
   @(negedge clk);hs=(i%3==0);vs=(i%5==0);sof=(i%7==0);de=(i%2==0);x=i;
   @(posedge clk);
   if(dut.u_pipe.hs!==phs || dut.u_pipe.vs!==pvs || dut.u_pipe.sof!==psof || dut.u_pipe.p_vde!==pde)
    $fatal(1,"FAIL gray/sync alignment cycle=%0d hs=%b/%b vs=%b/%b",i,dut.u_pipe.hs,phs,dut.u_pipe.vs,pvs);
   #1;phs=hs;pvs=vs;psof=sof;pde=de;
  end
  $display("TAKEOVER_PASS actual board_top sync matches registered gray/video input");$finish;
 end
endmodule
module clock_74m25(input clk_125m,mmcm_rst,output clk_pix,locked);
 assign clk_pix=clk_125m;assign locked=1;
endmodule
module clock_200m(input clk_125m,mmcm_rst,output clk_200m,locked);
 assign clk_200m=clk_125m;assign locked=1;
endmodule
module IOBUF(inout IO,input I,T,output O);assign IO=T?1'bz:I;assign O=IO;endmodule
module dvi2rgb_0(input TMDS_Clk_p,TMDS_Clk_n,input [2:0] TMDS_Data_p,TMDS_Data_n,
 input RefClk,aRst,pRst,SDA_I,SCL_I,output [23:0] vid_pData,
 output vid_pVDE,vid_pHSync,vid_pVSync,PixelClk,pLocked,SDA_O,SDA_T,SCL_O,SCL_T);
endmodule
module rgb2dvi_0(input PixelClk,aRst,input [23:0] vid_pData,
 input vid_pVDE,vid_pHSync,vid_pVSync,
 output TMDS_Clk_p,TMDS_Clk_n,output [2:0] TMDS_Data_p,TMDS_Data_n);
endmodule
