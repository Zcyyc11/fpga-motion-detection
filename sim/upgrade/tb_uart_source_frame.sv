`timescale 1ns/1ps
module tb_uart_source_frame;
 parameter VS_MODE=0; // 0=normal, 1=stuck low, 2=stuck high
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,pde=0,pvs=0;
 reg [23:0] pixel=0;
 wire de,hs,vs,sof,locked,gd,tx,drop;
 wire [15:0] x,y,gx,gy;wire [23:0] data;wire [7:0] gray;
 hdmi_in_ctrl #(.V_ACTIVE(48)) ctrl(.clk(clk),.rst_n(rst_n),.pVDE(pde),
  .pHSync(1'b0),.pVSync(pvs),.pData(pixel),.pLocked(1'b1),
  .de(de),.hs(hs),.vs(vs),.sof(sof),.x(x),.y(y),.pix_data(data),.locked(locked));
 gray_conv gc(clk,rst_n,de,x,y,data,gd,gx,gy,gray);
 md_pipeline #(.H_ACTIVE(64),.V_ACTIVE(48),.INPUT_SEL(1),.MODE_BG(1),
  .BG_FRAC_BITS(4),.SHIFT(6),.UART_BAUD_DIV(4),.MIN_CNT(4)) dut(
  .clk(clk),.rst_n(rst_n),.rx_de(gd),.rx_hs(1'b0),.rx_vs(1'b0),.rx_sof(1'b0),
  .rx_x(gx),.rx_y(gy),.rx_gray(gray),.uart_txd(tx),.uart_drop(drop),
  .clk_axi(clk),.rst_n_axi(rst_n),.ps_en(1'b0),.ps_we(1'b0),.ps_addr(6'd0),.ps_wdata(32'd0));
 integer f,row,col,k,n=0,len=0,headers=0,objects=0,expected_frame=0;
 integer frame_id,checksum;
 reg [7:0] byte_data,packet[0:13];
 always @(posedge clk)if(rst_n && drop)$fatal(1,"FAIL unexpected UART drop");
 initial forever begin
  @(negedge tx);#60;
  for(k=0;k<8;k=k+1)begin byte_data[k]=tx;#40;end
  if(tx!==1)$fatal(1,"FAIL UART stop bit");
  packet[n]=byte_data;
  if(n==0)begin
   if(byte_data==8'h5a)len=5;
   else if(byte_data==8'ha5)len=14;
   else $fatal(1,"FAIL unexpected packet marker %h",byte_data);
  end
  if(n==len-1)begin
   checksum=0;for(k=0;k<len-1;k=k+1)checksum=(checksum+packet[k])&255;
   if(packet[len-1]!==checksum)$fatal(1,"FAIL checksum");
   frame_id=packet[1]+256*packet[2];
   if(packet[0]==8'h5a)begin
    $display("SOURCE_HEADER frame=%0d objects=%0d",frame_id,packet[3]);
    if(frame_id!=expected_frame || packet[3]!==((frame_id==6)?1:0))
     $fatal(1,"FAIL source-frame header association frame=%0d objects=%0d",frame_id,packet[3]);
    expected_frame=expected_frame+1;headers=headers+1;
   end else begin
    $display("SOURCE_OBJECT packet=%0d id=%0d box=(%0d,%0d,%0d,%0d)",frame_id,packet[3],packet[4]+256*packet[5],packet[6]+256*packet[7],packet[8]+256*packet[9],packet[10]+256*packet[11]);
    if(frame_id!=6 || packet[3]!=0 || packet[4]!=8 || packet[5]!=0 || packet[6]!=8 || packet[7]!=0 || packet[8]!=15 || packet[9]!=0 || packet[10]!=15 || packet[11]!=0 || packet[12]!=0)
     $fatal(1,"FAIL source-frame object fields");
    objects=objects+1;
   end
   n=0;
  end else n=n+1;
 end
 initial begin
  repeat(8)@(negedge clk);rst_n=1;
  for(f=0;f<11;f=f+1)begin
   @(negedge clk);pvs=(VS_MODE==0 || VS_MODE==2);
   repeat(4)@(negedge clk);pvs=(VS_MODE==2);
   for(row=0;row<48;row=row+1)begin
    for(col=0;col<64;col=col+1)begin
     @(negedge clk);pde=1;
     pixel=(f==3 && col>=16 && col<32 && row>=16 && row<32)?24'he0e0e0:24'h101010;
    end
    @(negedge clk);pde=0;repeat(16)@(negedge clk);
   end
   repeat(3000)@(negedge clk);
  end
  repeat(2000)@(negedge clk);
  if(headers!=11 || objects!=1 || n!=0)$fatal(1,"FAIL missing/extra source packets headers=%0d objects=%0d",headers,objects);
  $display("TAKEOVER_PASS single source frame3 reaches exact UART frame6 id0 box(8,8,15,15) VS_MODE=%0d",VS_MODE);$finish;
 end
endmodule
