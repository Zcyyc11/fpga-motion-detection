`timescale 1ns/1ps
// Natural 65537-frame lifetime: no force/deposit of counters or IDs.
module track_saturation_tb;
 reg clk=0,rst_n=0,v=0,tick=0;always #5 clk=~clk;
 wire ov,ol,av;wire[7:0]id,aid;wire[15:0]x1,x2,y1,y2,dw,ac;wire[1:0]at;
 track #(.MAX_TRACK(1),.MAX_TARGET(1)) dut(.clk(clk),.rst_n(rst_n),.t_valid(v),.t_id(8'd0),
 .t_x1(16'd60000),.t_x2(16'd60010),.t_y1(16'd50000),.t_y2(16'd50010),.t_last(v),.frame_tick(tick),
 .o_valid(ov),.o_last(ol),.o_id(id),.o_x1(x1),.o_x2(x2),.o_y1(y1),.o_y2(y2),.o_dwell(dw));
 alarm a(.clk(clk),.rst_n(rst_n),.LINE_X(16'd0),.DWELL(16'hffff),.t_valid(ov),.t_id(id),
 .t_x1(x1),.t_x2(x2),.t_y1(y1),.t_y2(y2),.t_dwell(dw),.a_valid(av),.a_id(aid),.a_type(at),.a_cx(ac));
 integer f,n=0,alarms=0,errors=0;
 always @(posedge clk)begin #1;
 if(ov)begin
 n=n+1;
 if(id!==0 || dw!==((f<65535)?f:65535) || !ol || x1!=60000 || x2!=60010)begin
 errors=errors+1;$display("FAIL natural dwell f=%0d id=%0d dw=%0d",f,id,dw);end
 end
 if(av)begin
 alarms=alarms+1;
 if(at!=2 || ac!=60005)begin errors=errors+1;$display("FAIL saturation alarm centre or type");end
 end
 end
 initial begin
 repeat(3)@(negedge clk);rst_n=1;
 for(f=1;f<=65537;f=f+1)begin
 n=0;@(negedge clk);v=1;@(negedge clk);v=0;tick=1;
 @(negedge clk);tick=0;repeat(20)@(negedge clk);
 if(n!=1)begin errors=errors+1;$display("FAIL saturation frame missing");end
 end
 if(alarms!=1)begin errors=errors+1;$display("FAIL saturated dwell alarms=%0d",alarms);end
 $display("TRACK_SATURATION_DONE errors=%0d natural_frames=65537 alarms=%0d",errors,alarms);
 if(errors)$fatal(1,"saturation regression");$finish;
 end
 initial begin #20000000;$fatal(1,"saturation timeout");end
endmodule
