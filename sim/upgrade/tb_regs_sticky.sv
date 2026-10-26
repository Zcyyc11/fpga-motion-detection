`timescale 1ns/1ps
module tb_regs_sticky;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,en=0,we=0,drop=0;
 reg [5:0] addr=0;reg [31:0] wdata=0;
 wire [31:0] rdata;
 regs dut(.clk(clk),.rst_n(rst_n),.ps_en(en),.ps_we(we),.ps_addr(addr),.ps_wdata(wdata),.ps_rdata(rdata),
  .i_snap_x1(16'd0),.i_snap_y1(16'd0),.i_snap_x2(16'd0),.i_snap_y2(16'd0),.i_snap_cnt(16'd0),
  .i_snap_valid(1'b0),.i_snap_frame(16'd0),.i_snap_obj_count(8'd0),.i_snap_b_valid(1'b0),.i_snap_alarm(1'b0),.i_uart_drop(drop));
 task read_sticky(input bit expected);
 begin
  @(negedge clk);en=1;we=0;addr=6'h18;
  @(posedge clk);#1;if(rdata[31]!==expected)$fatal(1,"FAIL synthesized UART drop sticky expected=%b got=%b",expected,rdata[31]);
  @(negedge clk);en=0;
 end endtask
 initial begin
  repeat(20)@(negedge clk);rst_n=1;read_sticky(0);
  @(negedge clk);drop=1;@(negedge clk);drop=0;
  repeat(4)@(negedge clk);read_sticky(1);
  @(negedge clk);en=1;we=1;addr=6'h18;wdata=32'h80000000;
  @(negedge clk);en=0;we=0;read_sticky(0);
  @(negedge clk);drop=1;@(negedge clk);drop=0;read_sticky(1);
  @(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;read_sticky(0);
  $display("TAKEOVER_PASS synthesized register sticky set/hold/clear/reset");$finish;
 end
endmodule
