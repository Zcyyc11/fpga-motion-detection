`timescale 1ns/1ps
module tb_cfg_enable_verify;
 reg clk=0,axi=0,rst=0,ra=0,en=0,we=0;reg[5:0]addr=0;reg[31:0]data=0;
 always #5 clk=~clk;always #7 axi=~axi;
 wire[31:0]rd;integer errors=0,samples=0;reg monitor=0;
 md_pipeline #(.H_ACTIVE(32),.V_ACTIVE(24),.H_FP(2),.H_SYNC(2),.H_BP(2),
 .V_FP(1),.V_SYNC(1),.V_BP(1),.OBJ_W(8),.OBJ_H(8),.X0(4),.Y0(8),.DX(2),
 .INCLUDE_PS(1),.MODE_BG(0),.UART_BAUD_DIV(4)) dut(
 .clk(clk),.rst_n(rst),.clk_axi(axi),.rst_n_axi(ra),.ps_en(en),.ps_we(we),.ps_addr(addr),.ps_wdata(data),.ps_rdata(rd),
 .rx_de(1'b0),.rx_hs(1'b0),.rx_vs(1'b0),.rx_sof(1'b0),.rx_x(16'd0),.rx_y(16'd0),.rx_gray(8'd0));
 integer expected,delta;
 task check(input bit ok,input string msg);begin
 if(!ok)begin errors=errors+1;$display("FAIL %s",msg);end
 else $display("PASS %s",msg);
 end endtask
 task write_reg(input[5:0]a,input[31:0]d);begin
 @(negedge axi);en=1;we=1;addr=a;data=d;
 @(negedge axi);en=0;we=0;
 repeat(8)@(negedge clk);
 end endtask
 always @(posedge clk)begin #2;
 if(monitor && !dut.init_phase && !$isunknown({dut.cur_d1,dut.ref_px,dut.cfg_enable,dut.cfg_shift}))begin
 delta=integer'(dut.cur_d1)-integer'(dut.ref_px);
 expected=dut.cfg_enable ? integer'(dut.ref_px)+(delta >>> dut.cfg_shift) : integer'(dut.cur_d1);
 if(expected<0)expected=0;if(expected>1023)expected=1023;
 if(dut.wr_data !== expected[9:0])begin errors=errors+1;$display("FAIL mode arithmetic");end
 if(dut.cur_d1!=dut.ref_px)samples=samples+1;
 end
 end
 initial begin
 repeat(4)@(negedge clk);rst=1;ra=1;
 repeat(20)@(negedge clk);check(dut.cfg_enable===0,"reset mode 0");
 monitor=1;repeat(4000)@(negedge clk);
 check(samples>0,"frame difference nontrivial samples");samples=0;
 write_reg(6'h14,1);check(dut.cfg_enable===1 && dut.u_diff.mode_bg===1,"ENABLE 1 reaches diff mode");
 @(negedge axi);en=1;addr=6'h14;we=0;
 @(posedge axi);#1;check(rd===32'd1,"ENABLE register readback");
 @(negedge axi);en=0;
 repeat(4000)@(negedge clk);check(samples>0,"background mode nontrivial samples");
 write_reg(6'h14,0);check(dut.cfg_enable===0 && dut.u_diff.mode_bg===0,"ENABLE 0 restores diff mode");
 repeat(2000)@(negedge clk);
 $display("VERIFY_DONE cfg errors=%0d",errors);$finish;
 end
 initial begin #2000000;$fatal(1,"FAIL timeout cfg");end
endmodule
