`timescale 1ns/1ps
module tb_hdmi_coordinates;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,pde=0,pvs=0,plock=1;
 reg [23:0] pixel=0;
 wire de,hs,vs,sof,locked;
 wire [15:0] x,y; wire [23:0] data;
 integer mode,f,r,c,count=0,sofs=0;
 hdmi_in_ctrl dut(.clk(clk),.rst_n(rst_n),.pVDE(pde),.pHSync(1'b0),
  .pVSync(pvs),.pData(pixel),.pLocked(plock),.de(de),.hs(hs),.vs(vs),
  .x(x),.y(y),.sof(sof),.pix_data(data),.locked(locked));
 task drive(input integer xx,input integer yy);
 begin
  @(negedge clk);pde=1;pixel=yy*4+xx;
  @(posedge clk);#1;
  if(de!==1 || x!==xx || y!==yy || data!==pixel || sof!==((xx==0)&&(yy==0)))
    $fatal(1,"FAIL mode=%0d frame=%0d want=(%0d,%0d) got=(%0d,%0d) de=%b sof=%b",mode,f,xx,yy,x,y,de,sof);
  count=count+1;if(sof)sofs=sofs+1;
 end endtask
 initial begin
  for(mode=0;mode<3;mode=mode+1) begin
   @(negedge clk);rst_n=0;pde=0;pvs=0;
   repeat(4) @(negedge clk);rst_n=1;
   for(f=0;f<2;f=f+1) begin
    @(negedge clk);pvs=(mode==0 || mode==2);
    repeat(3) @(negedge clk);pvs=(mode==2);
    for(r=0;r<720;r=r+1) begin
     for(c=0;c<4;c=c+1) drive(c,r);
     @(negedge clk);pde=0;repeat(2) @(negedge clk);
    end
    repeat(5) @(negedge clk);
   end
  end
  @(negedge clk);plock=0;
  @(posedge clk);#1;if(de!==0 || locked!==0)$fatal(1,"FAIL unlock must blank");
  if(count!=17280 || sofs!=6)$fatal(1,"FAIL sample count");
  $display("TAKEOVER_PASS HDMI coordinates count=%0d sofs=%0d normal/stuck-low/stuck-high VS",count,sofs);$finish;
 end
endmodule
