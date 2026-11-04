`timescale 1ns/1ps
module tb_attach_z2_interaction;
 reg clk=0,rst_n=0;always #4 clk=~clk;
 reg [7:0] n=0;reg [15:0] th=70,fps=30,viol=0;reg [1:0] mode=0;reg tp=0,ve=0,dark=0,ea=0,eb=0,ep=0;reg [4:0] five=0;
 wire [7:0] delta;wire night;wire [6:0] seg;wire [8:0] dig;wire ws;wire ls,lm,lc,ld,lr,bz;wire tsc,tsd,lb;
 attach_z2_interaction #(.CLK_HZ(125) ) dut(clk,rst_n,n,th,mode,fps,viol,tp,ve,dark,ea,eb,ep,five,delta,night,seg,dig,ws,ls,lm,lc,ld,lr,lb,bz,tsc,tsd);
 initial begin #20 rst_n=1; #40 tp=1; #40 ve=1; #16 ve=0; #100; if(!bz) $display("beep completed"); dark=1;#20;if(!night)$fatal(1,"night mode failed"); $display("ATTACH_INTERACTION_PASS");$finish;end
endmodule

