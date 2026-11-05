`timescale 1ns/1ps
// No force/deposit into id_next: allocate and retire 256 real lifetimes.
module tb_track_id_wrap;
 reg clk=0,rst_n=0,v=0,tick=0; reg[15:0] x=40;
 always #5 clk=~clk;
 wire ov,ol,av;wire[7:0]id,aid;wire[1:0]at;
 wire[15:0]x1,y1,x2,y2,dw,ac;
 track #(.MISSED_MAX(2)) dut(.clk(clk),.rst_n(rst_n),.t_valid(v),.t_id(8'd0),
 .t_x1(x),.t_x2(x),.t_y1(16'd20),.t_y2(16'd20),.t_last(v),.frame_tick(tick),
 .o_valid(ov),.o_last(ol),.o_id(id),.o_x1(x1),.o_y1(y1),.o_x2(x2),.o_y2(y2),.o_dwell(dw));
 alarm a(.clk(clk),.rst_n(rst_n),.LINE_X(16'd50),.DWELL(16'd0),.t_valid(ov),.t_id(id),
 .t_x1(x1),.t_x2(x2),.t_y1(y1),.t_y2(y2),.t_dwell(dw),.a_valid(av),.a_id(aid),.a_type(at),.a_cx(ac));
 integer n=0,alarms=0,errors=0,i,j,got_id,got_dw;
 always @(posedge clk) begin #1;
 if(ov) begin n=n+1;got_id=id;got_dw=dw;end
 if(av) begin alarms=alarms+1;$display("EVENT %0d %0d %0d",aid,at,ac);end
 end
 task check(input bit ok,input string msg);begin
 if(!ok)begin errors=errors+1;$display("FAIL %s",msg);end
 end endtask
 task frame(input bit present,input integer pos);begin
 n=0;@(negedge clk);x=pos;v=present;
 @(negedge clk);v=0;tick=1;
 @(negedge clk);tick=0;
 repeat(6000)@(negedge clk); // sequential track bound is 4996 clocks
 end endtask
 initial begin
 repeat(4)@(negedge clk);rst_n=1;
 for(i=0;i<256;i=i+1)begin
 frame(1,40);check(n==1,"lifetime count");check(got_id==i,"natural id sequence");check(got_dw==1,"new lifetime dwell");
 for(j=0;j<3;j=j+1)frame(0,0);
 end
 check(alarms==0,"no crossings before reuse");
 frame(1,60);check(n==1 && got_id==0 && got_dw==1,"id 255 wraps to new id 0");
 check(alarms==0,"new lifetime must not inherit old left position");
 alarms=0;frame(1,40);check(n==1 && got_id==0 && got_dw==2,"reused id moves left");
 check(alarms==0,"right to left is not crossing");
 frame(1,60);check(n==1 && got_id==0 && got_dw==3,"reused id moves right");
 check(alarms==1,"reused id real crossing exactly once");
 $display("VERIFY_DONE wrap errors=%0d",errors);$finish;
 end
 initial begin #100000000;$fatal(1,"FAIL timeout wrap");end
endmodule
