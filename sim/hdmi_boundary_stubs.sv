`timescale 1ns/1ps
module clock_200m(input clk_125m,input mmcm_rst,output clk_200m,output locked);
  assign clk_200m=clk_125m;assign locked=~mmcm_rst;
endmodule
module rgb2dvi_0(output TMDS_Clk_p,TMDS_Clk_n,output [2:0] TMDS_Data_p,TMDS_Data_n,
 input aRst,input [23:0] vid_pData,input vid_pVDE,vid_pHSync,vid_pVSync,PixelClk);
 assign TMDS_Clk_p=PixelClk;assign TMDS_Clk_n=~PixelClk;
 assign TMDS_Data_p=0;assign TMDS_Data_n=0;
endmodule

module IOBUF(inout IO,input I,T,output O);
 assign IO=T?1'bz:I;assign O=IO;
endmodule
// Digital boundary model only; TMDS decoding and analog lock are not simulated.
module dvi2rgb_0(input TMDS_Clk_p,TMDS_Clk_n,input [2:0] TMDS_Data_p,TMDS_Data_n,
 input RefClk,aRst,pRst,input SDA_I,SCL_I,output SDA_O,SDA_T,SCL_O,SCL_T,
 output PixelClk,pLocked,output [23:0] vid_pData,output vid_pVDE,vid_pHSync,vid_pVSync);
 reg link_up=1,stream_on=0;
 wire de,hs,vs,sof;wire [15:0] x,y;
 integer f=0;
 assign PixelClk=TMDS_Clk_p;
 assign pLocked=link_up && !aRst;
 assign SDA_O=0;assign SDA_T=1;assign SCL_O=0;assign SCL_T=1;
 video_timing #(.H_ACTIVE(1280),.V_ACTIVE(720),.H_FP(110),.H_SYNC(40),.H_BP(220),.V_FP(5),.V_SYNC(5),.V_BP(20),.SYNC_POS(1)) timing(
 .clk(PixelClk),.rst_n(stream_on && pLocked),.de(de),.hs(hs),.vs(vs),.sof(sof),.x(x),.y(y));
 always @(posedge PixelClk) if(!stream_on || !pLocked)f<=0;else if(sof)f<=f+1;
 assign vid_pVDE=de;assign vid_pHSync=hs;assign vid_pVSync=vs;
 wire obj=(f>=2)&&(x>=400)&&(x<560)&&(y>=200)&&(y<320);
 assign vid_pData=obj?24'hffffff:24'h000000;
endmodule
