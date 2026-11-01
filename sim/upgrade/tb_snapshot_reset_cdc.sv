`timescale 1ns/1ps
module tb_snapshot_reset_cdc;
 reg cp=0,ca=0;always #6.734 cp=~cp;always #5 ca=~ca;
 reg rp=0,ra=0,latch=0,valid=0,alarm=0;
 reg [15:0] x1=0,y1=0,x2=0,y2=0,cnt=0,fid=0;
 reg [7:0] nobj=0;
 wire [15:0] ox1,oy1,ox2,oy2,ocnt,ofid;wire [7:0] onobj;
 wire ov,ob,oa;
 integer n,k,seen=0;
 bbox_snapshot dut(.clk_px(cp),.rst_n_px(rp),.i_latch(latch),
  .i_x1(x1),.i_y1(y1),.i_x2(x2),.i_y2(y2),.i_cnt(cnt),.i_valid(valid),
  .i_frame_idx(fid),.i_obj_count(nobj),.i_alarm_pulse(alarm),
  .clk_axi(ca),.rst_n_axi(ra),.o_x1(ox1),.o_y1(oy1),.o_x2(ox2),.o_y2(oy2),
  .o_cnt(ocnt),.o_valid(ov),.o_frame(ofid),.o_obj_count(onobj),.o_b_valid(ob),.o_alarm(oa));
 initial begin
  repeat(8)@(negedge cp);
  if(dut.ack_sync_ff !== 2'b00) $fatal(1,"FAIL ack synchronizer not reset");
  rp=1;ra=1;
  for(n=1;n<=100;n=n+1)begin
   repeat(8+n%7)@(negedge cp);
   x1=n;y1=n*2;x2=n*3;y2=n*4;cnt=n*5;fid=n;nobj=n%16;valid=n%2;
   @(negedge cp);latch=1;@(negedge cp);latch=0;
   // Mutate live inputs immediately: AXI must still see the held snapshot.
   x1=65535;y1=65534;x2=65533;y2=65532;cnt=65531;fid=65530;nobj=255;valid=0;
   k=0;
   while(ofid!=n && k<30)begin @(negedge ca);k=k+1;end
   if(k==30 || ox1!==n || oy1!==n*2 || ox2!==n*3 || oy2!==n*4 || ocnt!==n*5 || onobj!==(n%16) || ov!==(n%2) || ob!==(n%2))
    $fatal(1,"FAIL CDC torn/missing frame n=%0d got fid=%0d x1=%0d",n,ofid,ox1);
   seen=seen+1;
   if(n==50)begin
    @(negedge cp);rp=0;ra=0;repeat(4)@(negedge cp);
    if(dut.ack_sync_ff !== 2'b00 || ofid !== 0) $fatal(1,"FAIL mid-run reset");
    rp=1;ra=1;
   end
  end
  $display("TAKEOVER_PASS 100 atomic snapshots across independent 74.25/100 MHz clocks");$finish;
 end
endmodule
