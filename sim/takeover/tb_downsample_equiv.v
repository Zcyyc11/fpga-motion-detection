`timescale 1ns/1ps
module tb_downsample_equiv;
reg clk=0,rst_n=0,vde=0; always #5 clk=~clk;
reg [15:0] x=0,y=0; reg [7:0] pixel=0;
wire va,vb;wire [15:0] xa,ya,xb,yb;wire [9:0] pa,pb;
downsample2x2 #(.H_ACTIVE(1280)) a(clk,rst_n,vde,x,y,pixel,va,xa,ya,pa);
downsample2x2_baseline #(.H_ACTIVE(1280)) b(clk,rst_n,vde,x,y,pixel,vb,xb,yb,pb);
integer f,xx,yy,n=0,expected;
function integer value(input integer px,py,fr);value=(px*7+py*13+fr*29)%256;endfunction
always @(posedge clk) begin #1;
 if(rst_n)begin
  if({va,xa,ya,pa} !== {vb,xb,yb,pb})$fatal(1,"FAIL equivalence");
  if(va)begin
   expected=value(x-1,y-1,f)+value(x,y-1,f)+value(x-1,y,f)+value(x,y,f);
   if(pa!==expected[9:0] || xa!==(x>>1) || ya!==(y>>1))$fatal(1,"FAIL independent sum");
   n=n+1;
  end
 end
end
initial begin
 repeat(4)@(negedge clk);rst_n=1;
 for(f=0;f<3;f=f+1)begin
  for(yy=0;yy<6;yy=yy+1)begin
   for(xx=0;xx<1280;xx=xx+1)begin
    @(negedge clk);vde=1;x=xx;y=yy;pixel=value(xx,yy,f);
    if(xx%17==0)begin @(negedge clk);vde=0;end
   end
   @(negedge clk);vde=0;repeat(11)@(negedge clk);
  end
  rst_n=0;repeat(3)@(negedge clk);rst_n=1;
 end
 if(n!=5760)$fatal(1,"FAIL output count %d",n);
 $display("TAKEOVER_PASS downsample equivalence and independent sums %d",n);$finish;
end
initial begin #2000000;$fatal(1,"FAIL timeout");end
endmodule
