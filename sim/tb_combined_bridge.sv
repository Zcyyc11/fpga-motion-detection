`timescale 1ns/1ps
// Interface-only check. Clock and HDMI serializer are stubs; detector is real,
// with synthetic published metadata forced to exercise top-level consumers.
module tb_combined_bridge;
 reg clk=0;always #6.734 clk=~clk;
 reg [3:0] btn=0;reg [1:0] sw=0;
 wire [3:0] led;
 combined_top dut(.sys_clk(clk),.hdmi_rx_clk_p(clk),.hdmi_rx_clk_n(~clk),.hdmi_rx_d_p(3'd0),.hdmi_rx_d_n(3'd0),.btn(btn),.sw(sw),.led(led));
 task check(input bit condition,input string message);
   if(!condition)$fatal(1,"BRIDGE_FAIL %s",message);
 endtask
 task select_mode(input integer m);
   begin
     repeat(100010)@(negedge clk);
     btn=4'b1<<m;repeat(8)@(negedge clk);btn=0;
     check(dut.mode===m[1:0],"button mode selection");
   end
 endtask
 initial begin
   wait(dut.rst_n);repeat(4)@(negedge clk);
   check(dut.u_attach.CLK_HZ==74250000,"actual Attach clock parameter");
   force dut.b_obj_count=8'd3;force dut.b_valid=1'b1;
   force dut.b_x1=16'd32;force dut.b_x2=16'd608;
   repeat(4)@(negedge clk);
   check(dut.u_attach.target_count===8'd3,"real multi-target count bridge");
   check(dut.violation_event===1'b0,"inclusive boundary is legal");
   force dut.b_x1=16'd31;@(negedge clk);
   check(dut.violation_event===1'b1,"left boundary violation");
   force dut.b_x1=16'd32;force dut.b_x2=16'd609;@(negedge clk);
   check(dut.violation_event===1'b1,"right boundary violation");
   force dut.b_valid=1'b0;@(negedge clk);
   check(dut.violation_event===1'b0,"invalid metadata suppresses violation");
   sw[1]=1;repeat(8)@(negedge clk);check(dut.night_mode===1'b1,"night switch");
   sw[1]=0;repeat(8)@(negedge clk);check(dut.night_mode===1'b0,"day switch");
   select_mode(1);select_mode(2);select_mode(3);select_mode(0);
   $display("COMBINED_BRIDGE_PASS count=3 modes=4 boundaries=4 night_switch=2");$finish;
 end
 initial begin #10000000;$fatal(1,"BRIDGE_TIMEOUT");end
endmodule
