`timescale 1ns/1ps
module tb_background_fixed;
reg mode,init;
reg [4:0] shift;
reg [15:0] thresh;
reg [9:0] cur;
reg [13:0] refpx;
wire [10:0] ad;wire [13:0] wr;
background_fixed dut(.mode_bg(mode),.init_phase(init),.shift_amt(shift),.thresh(thresh),.cur(cur),.ref_px(refpx),.absdiff(ad),.wr_data(wr));
integer fd,n,rc,ec,er,es,et,em,ei,ead,ew,errors=0;
initial begin
 fd=$fopen("<ABS>/fpga_upgrade_20261022/replay/arithmetic.txt","r");
 if(!fd)$fatal(1,"FAIL missing vectors");
 for(n=0;n<10000;n=n+1)begin
  rc=$fscanf(fd,"%d %d %d %d %d %d %d %d\n",ec,er,es,et,em,ei,ead,ew);
  if(rc!=8)$fatal(1,"FAIL vector format");
  cur=ec;refpx=er;shift=es;thresh=et;mode=em;init=ei;#1;
  if(ad!==ead || wr!==ew)begin
    if(errors<10)$display("ARITH_ERROR i=%0d ad=%0d/%0d wr=%0d/%0d",n,ad,ead,wr,ew);
    errors=errors+1;
  end
 end
 if(errors)$fatal(1,"FAIL arithmetic errors=%0d",errors);
 $display("TAKEOVER_PASS 10000 fixed-point arithmetic vectors");$finish;
end
endmodule
