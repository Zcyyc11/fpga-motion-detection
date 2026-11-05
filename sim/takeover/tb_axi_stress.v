`timescale 1ns/1ps
module tb_axi_stress;
reg clk=0,rst=0;always #5 clk=~clk;
reg [31:0] aw=0,wd=0,ar=0;reg [3:0]strb=15;
reg awv=0,wv=0,arv=0,br=0,rr=0;
wire awr,wr,arr,bv,rv,pe,pw;wire [1:0] bp,rp;wire [31:0]rd,pd;wire [5:0]pa;
reg [31:0] mem[0:15];reg [31:0] pr=0;integer writes=0,reads=0,i,k;
axi_lite_slave d(clk,rst,aw,awv,awr,wd,strb,wv,wr,bp,bv,br,ar,arv,arr,rd,rp,rv,rr,pe,pw,pa,pd,pr);
always @(posedge clk)begin
 if(rst)begin
  if(pe&&pw)begin mem[pa[5:2]]<=pd;writes=writes+1;end
  if(pe&&!pw)reads=reads+1;
  pr<=(pe&&!pw)?mem[pa[5:2]]:0;
 end
end
task addr(input integer a);integer n;begin
 @(negedge clk);aw=a;awv=1;n=0;
 @(posedge clk);while(!awr&&n<100)begin n=n+1;@(posedge clk);end
 if(!awr)$fatal(1,"FAIL AW timeout");@(negedge clk);awv=0;aw=32'hdeadbeef;
end endtask
task data(input integer val,input [3:0]st);integer n;begin
 @(negedge clk);wd=val;strb=st;wv=1;n=0;
 @(posedge clk);while(!wr&&n<100)begin n=n+1;@(posedge clk);end
 if(!wr)$fatal(1,"FAIL W timeout");@(negedge clk);wv=0;wd=32'hbadbad;
end endtask
task bresp(input [1:0]resp);integer n;begin
 n=0;while(!bv&&n<100)begin @(negedge clk);n=n+1;end
 if(!bv||bp!==resp)$fatal(1,"FAIL B response");
 repeat(5)begin @(negedge clk);if(!bv||bp!==resp)$fatal(1,"FAIL B stability");end
 br=1;@(negedge clk);br=0;
end endtask
task raddr(input integer a);integer n;begin
 @(negedge clk);ar=a;arv=1;n=0;
 @(posedge clk);while(!arr&&n<100)begin n=n+1;@(posedge clk);end
 if(!arr)$fatal(1,"FAIL AR timeout");@(negedge clk);arv=0;ar=32'hbadbad;
end endtask
task rresp(input [31:0]val);integer n;begin
 n=0;while(!rv&&n<100)begin @(negedge clk);n=n+1;end
 if(!rv||rd!==val||rp!==0)$fatal(1,"FAIL read got=%h expected=%h",rd,val);
 repeat(5)begin @(negedge clk);if(!rv||rd!==val)$fatal(1,"FAIL R stability");end
 rr=1;@(negedge clk);rr=0;
end endtask
initial begin
 for(i=0;i<16;i=i+1)mem[i]=32'h1000+i;
 repeat(4)@(negedge clk);rst=1;
 for(k=0;k<12;k=k+1)begin
  if(k%3==0)begin addr(k*4);repeat(3)@(negedge clk);data(32'h2000+k,15);end
  else if(k%3==1)begin data(32'h2000+k,15);repeat(3)@(negedge clk);addr(k*4);end
  else fork addr(k*4);data(32'h2000+k,15);join
  bresp(0);raddr(k*4);rresp(32'h2000+k);
 end
 // All three address/data channels accepted together; read must not disappear.
 fork addr(0);data(32'h3456,15);raddr(4);join
 fork bresp(0);rresp(32'h2001);join
 // Register bus has no byte strobes: abort zero strobe, reject partial, no side effect.
 fork addr(0);data(32'hffff,0);join bresp(0);
 fork addr(0);data(32'hffff,1);join bresp(2);
 if(writes!=13||mem[0]!==32'h3456||reads!=13)$fatal(1,"FAIL side effects writes=%d reads=%d",writes,reads);
 // Reset discards an unmatched AW and pending responses.
 addr(0);@(negedge clk);rst=0;repeat(3)@(negedge clk);rst=1;
 fork addr(8);data(32'h7788,15);join bresp(0);raddr(8);rresp(32'h7788);
 $display("TAKEOVER_PASS AXI split simultaneous backpressure strobe reset");$finish;
end
initial begin #100000;$fatal(1,"FAIL timeout");end
endmodule
