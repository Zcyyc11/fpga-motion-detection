`timescale 1ns/1ps
module tb_uart_pixel_frame;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0, de=0;
  reg [15:0] x=0,y=0;
  wire tx;
  integer bytes=0, headers=0, errors=0, ticks=0;
  reg [7:0] data, packet[0:4];
  integer bitno, n=0, f, row, col;
  md_pipeline #(.H_ACTIVE(32),.V_ACTIVE(16),.INPUT_SEL(1),
    .UART_BAUD_DIV(4),.MIN_CNT(4)) dut(
    .clk(clk),.rst_n(rst_n),.rx_de(de),.rx_hs(1'b0),.rx_vs(1'b0),
    .rx_sof(de && x==0 && y==0),.rx_x(x),.rx_y(y),.rx_gray(8'd32),
    .uart_txd(tx),.clk_axi(clk),.rst_n_axi(rst_n),
    .ps_en(1'b0),.ps_we(1'b0),.ps_addr(6'd0),.ps_wdata(32'd0));
  always @(posedge clk) if(rst_n && dut.frame_tick) ticks=ticks+1;
  initial forever begin
    @(negedge tx); #60;
    for(bitno=0;bitno<8;bitno=bitno+1) begin
      data[bitno]=tx; #40;
    end
    if(tx!==1'b1) errors=errors+1;
    bytes=bytes+1; packet[n]=data;
    if(n==4) begin
      if(packet[0]!==8'h5a || packet[3]!==0 ||
         packet[4]!==((packet[0]+packet[1]+packet[2]+packet[3])&8'hff)) errors=errors+1;
      headers=headers+1; n=0;
    end else n=n+1;
  end
  initial begin
    repeat(8) @(negedge clk); rst_n=1;
    for(f=0;f<8;f=f+1) begin
      for(row=0;row<16;row=row+1) begin
        for(col=0;col<32;col=col+1) begin
          @(negedge clk); de=1; x=col; y=row;
        end
        @(negedge clk); de=0; x=0; y=0;
        repeat(8) @(negedge clk);
      end
      repeat(500) @(negedge clk);
    end
    repeat(1000) @(negedge clk);
    $display("UART_PIXEL_RESULT bytes=%0d headers=%0d errors=%0d ticks=%0d",bytes,headers,errors,ticks);
    if(headers<6 || errors!=0 || ticks<7 || ticks>8 || n!=0) $fatal(1,"FAIL missing/corrupt UART with valid pixels and stuck VS");
    $display("TAKEOVER_PASS pixel-frame UART with blank scene and stuck VS"); $finish;
  end
endmodule
