`timescale 1ns/1ps
module uart_contract_tb;
parameter integer BAUD=8;
reg clk=0; always #5 clk=~clk;
reg rst_n=0, s_valid=0,e_valid=0,frame_tick=0;
reg [7:0] s_id=0,e_id=0; reg [15:0] s_x1=0,s_y1=0,s_x2=0,s_y2=0,e_cx=0; reg [1:0] e_type=0;
wire tx,drop;
uart_tx #(.BAUD_DIV(BAUD)) dut(.*);
integer received=0, drops=0, f=0,i,j,k,n,fr,cnt,idx,sum,expect_headers=0;
integer expected[0:255]; integer seen[0:255];
reg [7:0] bytes[0:20000]; reg [7:0] b;
integer reset_epoch=0, byte_epoch=0;
always @(negedge rst_n) reset_epoch=reset_epoch+1;
always @(posedge clk) if(rst_n && drop) drops=drops+1;
initial forever begin
 @(negedge tx);
 if(rst_n) begin
  byte_epoch=reset_epoch;
  repeat(BAUD+BAUD/2) @(posedge clk);
  for(integer q=0;q<8;q=q+1) begin b[q]=tx; repeat(BAUD) @(posedge clk); end
  if(byte_epoch==reset_epoch)begin
   if(tx!==1'b1) $fatal(1,"FAIL stop bit");
   bytes[received]=b; received=received+1;
  end
 end
end
task drive(input integer tick,input integer valid,input integer id);
begin
 @(negedge clk);frame_tick=tick;s_valid=valid;e_valid=valid;s_id=id;e_id=id;
 s_x1=16'h1200+id;s_y1=16'h2300+id;s_x2=16'h3400+id;s_y2=16'h4500+id;e_cx=16'h5600+id;e_type=2;
end endtask
task check_stream;
begin
 idx=0;
 while(idx<received) begin
 if(bytes[idx]!==8'h5a) $fatal(1,"FAIL expected header byte %0d got %h",idx,bytes[idx]);
 fr={bytes[idx+2],bytes[idx+1]};cnt=bytes[idx+3];
 if(fr>255 || seen[fr] || cnt!=expected[fr]) $fatal(1,"FAIL frame/count fr=%0d cnt=%0d expected=%0d",fr,cnt,expected[fr]);
 seen[fr]=1; sum=0;for(j=0;j<4;j=j+1)sum=sum+bytes[idx+j];
 if(bytes[idx+4]!== (sum & 255)) $fatal(1,"FAIL header checksum");idx=idx+5;
 for(i=0;i<cnt;i=i+1) begin
 if(bytes[idx]!==8'ha5 || {bytes[idx+2],bytes[idx+1]}!=fr || bytes[idx+3]!=i) $fatal(1,"FAIL object frame/order idx=%0d",idx);
 if({bytes[idx+5],bytes[idx+4]}!=16'h1200+i || {bytes[idx+7],bytes[idx+6]}!=16'h2300+i || {bytes[idx+9],bytes[idx+8]}!=16'h3400+i || {bytes[idx+11],bytes[idx+10]}!=16'h4500+i || bytes[idx+12]!=0) $fatal(1,"FAIL coordinates");
 sum=0;for(j=0;j<13;j=j+1)sum=sum+bytes[idx+j];if(bytes[idx+13] !== (sum &255))$fatal(1,"FAIL object checksum");idx=idx+14;
 end
 for(i=0;i<cnt;i=i+1)begin
 if(bytes[idx]!==8'hc3 || {bytes[idx+2],bytes[idx+1]}!=fr || bytes[idx+3]!=i || bytes[idx+4]!=2 || {bytes[idx+6],bytes[idx+5]}!=16'h5600+i)$fatal(1,"FAIL event frame/order idx=%0d",idx);
 sum=0;for(j=0;j<7;j=j+1)sum=sum+bytes[idx+j];if(bytes[idx+7] !== (sum &255))$fatal(1,"FAIL event checksum");idx=idx+8;
 end
 end
 if(idx!=received)$fatal(1,"FAIL truncated packet");
end endtask
initial begin
 for(k=0;k<256;k=k+1)begin expected[k]=0;seen[k]=0;end
 repeat(5)@(negedge clk);rst_n=1;
 // tick + valid belongs to frame 1; frame 0 is empty.
 drive(1,1,0);expected[1]=16;
 for(k=1;k<16;k=k+1)drive(0,1,k);
 drive(1,0,0);drive(1,0,0);drive(0,0,0);
 repeat(70000*BAUD/8)@(negedge clk);
 check_stream();if(!seen[0]||!seen[1]||!seen[2]||drops)$fatal(1,"FAIL loss without pressure");
 // Repeated full frames overrun bounded storage; completed frames must be whole.
 for(f=3;f<24;f=f+1)begin
 expected[f]=16;for(k=0;k<16;k=k+1)drive(0,1,k);
 drive(1,0,0);drive(0,0,0);
 end
 repeat(150000*BAUD/8)@(negedge clk);
 for(k=0;k<256;k=k+1)seen[k]=0;
 check_stream();if(drops==0)$fatal(1,"FAIL no observable overflow");
 // Reset then exceed one frame's record capacity: the entire frame disappears.
 @(negedge clk);rst_n=0;repeat(5)@(negedge clk);received=0;drops=0;
 for(k=0;k<256;k=k+1)begin expected[k]=0;seen[k]=0;end
 rst_n=1;
 for(k=0;k<17;k=k+1)drive(0,1,k);
 drive(1,1,0);expected[1]=1;drive(1,0,0);drive(1,0,0);drive(0,0,0);
 repeat(10000*BAUD/8)@(negedge clk);check_stream();
 if(seen[0]||!seen[1]||!seen[2]||drops==0)$fatal(1,"FAIL capacity rollback/recovery");
 // Start another complete frame and assert reset while its UART is active.
 drive(0,1,0);drive(1,0,0);drive(0,0,0);
 @(negedge tx);repeat(3)@(negedge clk);rst_n=0;
 repeat(100*BAUD/8)@(negedge clk);
 // Reset discards unsent records and restarts numbering.
 @(negedge clk);rst_n=0;repeat(5)@(negedge clk);received=0;drops=0;
 for(k=0;k<256;k=k+1)begin expected[k]=0;seen[k]=0;end
 rst_n=1;drive(1,0,0);drive(0,0,0);repeat(2000*BAUD/8)@(negedge clk);
 check_stream();if(!seen[0])$fatal(1,"FAIL reset frame");
 $display("TAKEOVER_PASS UART wire decode burst tick simultaneous overflow capacity rollback empty active-reset");$finish;
end
initial begin #(1250000.0*BAUD);$fatal(1,"FAIL timeout");end
endmodule

