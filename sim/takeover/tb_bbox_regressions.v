`timescale 1ns/1ps
module tb_bbox_regressions;
reg clk=0,rst=0,v=0,m=0; reg [15:0] x=0,y=0;
always #5 clk=~clk;
wire ov,ol,of; wire[15:0] x1,y1,x2,y2,cnt;wire[7:0] id;
multi_bbox #(.MIN_CNT(1)) dut(.clk(clk),.rst_n(rst),.in_valid(v),.in_x(x),.in_y(y),.in_mask(m),.o_valid(ov),.o_last(ol),.o_overflow(of),.o_x1(x1),.o_y1(y1),.o_x2(x2),.o_y2(y2),.o_cnt(cnt),.o_id(id));
integer good=0;
integer testcase=0,boxes=0,xx,yy,frame,overflow_seen=0;
always @(posedge clk) begin #1;if(ov)begin boxes=boxes+1;
 if(testcase==1)begin
  if((x1==2&&y1==0&&x2==11&&y2==3&&cnt==21)||(x1==14&&y1==2&&x2==15&&y2==2&&cnt==2))good=good+1;
  else $fatal(1,"FAIL alias corruption");
 end
 if(testcase==2 && !(x1==0&&y1==0&&x2==255&&y2==255&&cnt==65535))$fatal(1,"FAIL saturated large target");
 $display("CASE%0d BOX %0d %0d %0d %0d COUNT %0d",testcase,x1,y1,x2,y2,cnt);end if(of)overflow_seen=1;end
 task reset_dut;begin @(negedge clk);rst=0;v=0;repeat(5)@(negedge clk);rst=1;boxes=0;overflow_seen=0;end endtask
 task pixel(input integer a,b,c,gap); begin @(negedge clk);v=1;x=a;y=b;m=c;if(gap>1)begin @(negedge clk);v=0;repeat(gap-2)@(negedge clk);end end endtask
 task flush;begin pixel(0,0,0,32);v=0;repeat(10000)@(negedge clk);end endtask
initial begin
 testcase=1;reset_dut;
 for(yy=0;yy<5;yy=yy+1)for(xx=0;xx<18;xx=xx+1)begin
 m=0;
 pixel(xx,yy,((yy==0&&xx>=10&&xx<=11)||(yy==1&&((xx>=2&&xx<=8)||(xx>=10&&xx<=11)))||(yy==2&&((xx>=2&&xx<=3)||(xx>=6&&xx<=11)||(xx>=14&&xx<=15)))||(yy==3&&xx>=2&&xx<=3)),32);
 end
 flush;$display("CASE1 EXPECTED bbox(2,0,11,3) cnt21 AND bbox(14,2,15,2) cnt2; observed_boxes=%0d overflow=%0d",boxes,overflow_seen);
 if(boxes!=2||good!=2||overflow_seen)$fatal(1,"FAIL alias count");
 testcase=2;reset_dut;
 for(yy=0;yy<257;yy=yy+1)for(xx=0;xx<257;xx=xx+1)pixel(xx,yy,yy<256&&xx<256,2);
 flush;$display("CASE2 EXPECTED one 256x256 target; observed_boxes=%0d overflow=%0d",boxes,overflow_seen);
 if(boxes!=1||overflow_seen)$fatal(1,"FAIL large target missing");
 testcase=3;reset_dut;
 for(frame=0;frame<2;frame=frame+1)begin
 for(yy=0;yy<360;yy=yy+1)begin
 for(xx=0;xx<640;xx=xx+1)pixel(xx,yy,(xx%40)<20,2);
 v=0;repeat(2020)@(negedge clk); // two 1650-pixel source rows per big-pixel row
 end
 repeat(49500)@(negedge clk); // source vertical blanking
 end
 @(negedge clk);v=0;repeat(20000)@(negedge clk);
 $display("CASE3 continuous 640x360 16 strips frames=2 overflow_seen=%0d",overflow_seen);
 if(overflow_seen||boxes!=16)$fatal(1,"FAIL 720p cadence full16");
 $display("TAKEOVER_PASS bbox alias saturation 720p cadence full16");$finish;
end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
