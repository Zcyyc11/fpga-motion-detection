`timescale 1ns/1ps
module tb_hdmi_restore;
 reg clk=0;always #6.734 clk=~clk;
 combined_top dut(.sys_clk(clk),.hdmi_rx_clk_p(clk),.hdmi_rx_clk_n(~clk),.hdmi_rx_d_p(3'd0),.hdmi_rx_d_n(3'd0),.btn(4'd0),.sw(2'd0));
 integer active=0,white=0,red=0,frames=0,boxes=0;
 always @(negedge clk) if(dut.rst_n && dut.vde) begin
   active=active+1;
   if(dut.vx==0 && dut.vy==0)frames=frames+1;
   if(dut.vx>=420 && dut.vx<540 && dut.vy>=220 && dut.vy<300 && dut.u_rx.f>=3) begin
     if({dut.vr,dut.vg,dut.vb}!==24'hffffff)$fatal(1,"HDMI_INPUT_PIXEL_LOST");white=white+1;
   end
   if(dut.vr==255 && dut.vg==0 && dut.vb==0)red=red+1;
   if(dut.vx==0 && dut.vy==100 && dut.b_valid) begin
     if(dut.b_obj_count!=1 || dut.b_x1!=200 || dut.b_y1!=100 || dut.b_x2!=279 || dut.b_y2!=159)
       $fatal(1,"HDMI_GEOMETRY got count=%d (%d,%d)-(%d,%d)",dut.b_obj_count,dut.b_x1,dut.b_y1,dut.b_x2,dut.b_y2);
     boxes=boxes+1;
   end
 end
 initial begin
   wait(dut.rst_n);repeat(4)@(negedge clk);dut.u_rx.stream_on=1;
   wait(frames>=6);@(negedge clk);
   if(active<1280*720*4 || white<1000 || red<100 || boxes<2)$fatal(1,"HDMI_INSUFFICIENT_EVIDENCE");
   dut.u_rx.link_up=0;#1;
   if(dut.rst_n!==0)$fatal(1,"HDMI_LOSS_RESET");
   repeat(8)@(negedge clk);dut.u_rx.link_up=1;
   repeat(100)@(negedge clk);if(dut.rst_n!==0)$fatal(1,"HDMI_RELEASE_TOO_EARLY");
   wait(dut.rst_n);repeat(4)@(negedge clk);
   if(dut.b_valid!==0)$fatal(1,"HDMI_STALE_BOX_AFTER_RELOCK");
   $display("HDMI_RESTORE_PASS frames=%d active=%d white=%d red=%d boxes=%d loss_relock=PASS",frames,active,white,red,boxes);$finish;
 end
 initial begin #150000000;$fatal(1,"HDMI_TIMEOUT");end
endmodule
