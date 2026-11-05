`timescale 1ns/1ps
module tb_mask_q4_stress;
parameter MODE=1;
parameter FRAC=4;
parameter SHIFT=6;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,de=0;
reg [15:0] x=0,y=0;
reg [7:0] pix=0;
reg [7:0] pixels[0:552959];
reg expected[0:138239];
wire mv,mb;
wire [15:0] mx,my;
integer f=0,row,col,errors=0,samples=0,stop_positive=0; integer last_index=-1; integer current_index;
md_pipeline #(.H_ACTIVE(64),.V_ACTIVE(48),.INPUT_SEL(1),.MODE_BG(MODE),
  .SHIFT(SHIFT),.BG_FRAC_BITS(FRAC),.THRESH(70),.MIN_CNT(4),.UART_BAUD_DIV(4)) dut(
  .clk(clk),.rst_n(rst_n),.rx_de(de),.rx_hs(1'b0),.rx_vs(1'b0),
  .rx_sof(de&&x==0&&y==0),.rx_x(x),.rx_y(y),.rx_gray(pix),
  .m_valid(mv),.m_bit(mb),.m_x(mx),.m_y(my),
  .clk_axi(clk),.rst_n_axi(rst_n),.ps_en(1'b0),.ps_we(1'b0),
  .ps_addr(6'd0),.ps_wdata(32'd0));
always @(negedge clk) if(rst_n&&mv) begin
  samples=samples+1; current_index=f*609+(my-1)*29+(mx-1); if(f<1 || mx<1 || mx>29 || my<1 || my>21 || current_index!=last_index+1 && last_index!=-1) errors=errors+1; last_index=current_index;
  if(f>=180 || mx>=32 || my>=24) begin errors=errors+1; end
  else if(mb!==expected[f*768+my*32+mx]) begin
    if(errors<8) $display("MASK_MISMATCH f=%0d x=%0d y=%0d got=%b expected=%b",f,mx,my,mb,expected[f*768+my*32+mx]);
    errors=errors+1;
  end
  if(f>=16&&mb)stop_positive=stop_positive+1;
end
initial begin
 $readmemh("<ABS>/fpga_upgrade_20261022/q4_stress_fixture/pixels.mem",pixels);
 if(FRAC) $readmemb("<ABS>/fpga_upgrade_20261022/q4_stress_fixture/expectedq4.mem",expected);
 else if(MODE) $readmemb("<ABS>/fpga_upgrade_20261022/q4_stress_fixture/expected1.mem",expected);
 else $readmemb("<ABS>/fpga_upgrade_20261022/q4_stress_fixture/expected0.mem",expected);
 repeat(8) @(negedge clk);rst_n=1;
 for(f=0;f<180;f=f+1) begin
   for(row=0;row<48;row=row+1) begin
     for(col=0;col<64;col=col+1)begin
       @(negedge clk);de=1;x=col;y=row;pix=pixels[f*3072+row*64+col];
     end
     @(negedge clk);de=0;x=0;y=0;repeat(16)@(negedge clk);
   end
   repeat(1000)@(negedge clk);
 end
 $display("MASK_REPLAY mode=%0d samples=%0d errors=%0d stationary_positive=%0d",MODE,samples,errors,stop_positive);
 if(errors || samples!=109011 || (MODE&&stop_positive==0) || (!MODE&&stop_positive!=0)) $fatal(1,"FAIL replay mismatch");
 $display("TAKEOVER_PASS RTL mask matches integer model including slow/stopped target");$finish;
end
endmodule
