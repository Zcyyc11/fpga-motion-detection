`timescale 1ns/1ps
// Attach-Z2 W5-W9 display/interaction layer.
// Metrics are supplied by the vehicle detector; this block owns only external peripherals.
module attach_z2_interaction #(
  parameter integer CLK_HZ=125_000_000,
  parameter integer WS_T0H=25, parameter integer WS_T1H=50,
  parameter integer WS_BIT=125
)(
  input wire clk,input wire rst_n,
  input wire [7:0] target_count,input wire [15:0] threshold,input wire [1:0] mode,
  input wire [15:0] fps,input wire [15:0] violation_count,
  input wire target_present,input wire violation_event,input wire light_dark,
  input wire enc_a,input wire enc_b,input wire enc_push,
  input wire [4:0] fiveway,
  output reg [7:0] threshold_delta,
  output reg night_mode,
  output reg [6:0] seg, output reg [8:0] digit,
  output reg ws2812_din,
  output reg lcd_sck,output reg lcd_mosi,output reg lcd_cs_n,output reg lcd_dc,output reg lcd_rst_n,
  output wire lcd_bkl,
  output reg buzzer,
  output wire touch_scl,output wire touch_sda
);
  localparam integer SCAN_DIV=CLK_HZ/9000;
  localparam integer BZ_LEN=CLK_HZ/10;
  reg [15:0] scan_cnt; reg [3:0] scan_idx;
  reg [7:0] disp_digit[0:8]; reg [7:0] enc_prev; reg enc_push_d;
  reg [15:0] bz_cnt; reg violation_d;
  reg [31:0] light_cnt;
  reg [2:0] ws_bit_idx; reg [3:0] ws_led_idx; reg [1:0] ws_phase; reg [23:0] ws_shift;
  reg [15:0] ws_cnt;
  reg ws_active;
  assign lcd_bkl=1'b1;
  assign touch_scl=1'bz; assign touch_sda=1'bz;

  function [6:0] hex7(input [3:0] x);
    case(x)
      4'h0:hex7=7'b1000000;4'h1:hex7=7'b1111001;4'h2:hex7=7'b0100100;4'h3:hex7=7'b0110000;
      4'h4:hex7=7'b0011001;4'h5:hex7=7'b0010010;4'h6:hex7=7'b0000010;4'h7:hex7=7'b1111000;
      4'h8:hex7=7'b0000000;4'h9:hex7=7'b0010000;4'hA:hex7=7'b0001000;4'hB:hex7=7'b0000011;
      4'hC:hex7=7'b1000110;4'hD:hex7=7'b0100001;4'hE:hex7=7'b0000110;default:hex7=7'b0001110;
    endcase
  endfunction

  always @* begin
    disp_digit[0]=target_count/10; disp_digit[1]=target_count%10;
    disp_digit[2]=mode; disp_digit[3]=threshold/1000; disp_digit[4]=(threshold/100)%10;
    disp_digit[5]=(threshold/10)%10; disp_digit[6]=threshold%10;
    disp_digit[7]=violation_count/10; disp_digit[8]=violation_count%10;
  end
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin scan_cnt<=0;scan_idx<=0;seg<=7'h7f;digit<=9'h1ff; end
    else if(scan_cnt==SCAN_DIV-1) begin
      scan_cnt<=0; scan_idx<=(scan_idx==8)?0:scan_idx+1'b1;
      digit<=~(9'b1<<((scan_idx==8)?0:scan_idx)); seg<=hex7(disp_digit[(scan_idx==8)?0:scan_idx][3:0]);
    end else scan_cnt<=scan_cnt+1'b1;
  end

  // Encoder: signed one-step threshold trim, latched for the detector bridge.
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin enc_prev<=0;threshold_delta<=0;enc_push_d<=0;night_mode<=0;end
    else begin
      enc_prev<={enc_prev[5:0],enc_a,enc_b}; enc_push_d<=enc_push;
      if(enc_prev[1:0]!={enc_a,enc_b}) begin
        if(({enc_prev[1:0],enc_a,enc_b}==4'b0111)||({enc_prev[1:0],enc_a,enc_b}==4'b1000)) threshold_delta<=threshold_delta+1'b1;
        else if(({enc_prev[1:0],enc_a,enc_b}==4'b0010)||({enc_prev[1:0],enc_a,enc_b}==4'b1101)) threshold_delta<=threshold_delta-1'b1;
      end
      if(enc_push && !enc_push_d) night_mode<=~night_mode;
      if(light_dark) night_mode<=1'b1; else if(!light_dark) night_mode<=1'b0;
      if(fiveway[0]) night_mode<=1'b0; else if(fiveway[1]) night_mode<=1'b1;
    end
  end

  // One short beep per new violation event.
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin violation_d<=0;buzzer<=0;bz_cnt<=0;end
    else begin
      violation_d<=violation_event;
      if(violation_event && !violation_d) begin buzzer<=1'b1;bz_cnt<=BZ_LEN-1;end
      else if(buzzer && bz_cnt!=0) bz_cnt<=bz_cnt-1'b1;
      else buzzer<=1'b0;
    end
  end

  // WS2812 serializer: GRB, 8 LEDs, 24 bits each. Idle low between frames.
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin ws_cnt<=0;ws_bit_idx<=0;ws_led_idx<=0;ws_phase<=0;ws_shift<=0;ws2812_din<=0;ws_active<=0;end
    else if(!ws_active) begin
      ws_active<=1'b1;ws_led_idx<=0;ws_bit_idx<=0;ws_shift<=
        violation_event ? 24'h400000 : (target_present ? 24'h404000 : 24'h004000); ws_cnt<=0;ws2812_din<=1'b0;
    end else if(ws_cnt==WS_BIT-1) begin
      ws_cnt<=0; ws2812_din<=0;
      if(ws_bit_idx==23) begin
        ws_bit_idx<=0;
        if(ws_led_idx==7) begin ws_active<=0; ws_led_idx<=0; end
        else begin ws_led_idx<=ws_led_idx+1'b1; ws_shift<=violation_event?24'h400000:(target_present?24'h404000:24'h004000); end
      end else begin ws_bit_idx<=ws_bit_idx+1'b1; ws_shift<={ws_shift[22:0],1'b0}; end
    end else begin
      ws_cnt<=ws_cnt+1'b1;
      ws2812_din <= ws_shift[23] ? (ws_cnt<WS_T1H) : (ws_cnt<WS_T0H);
    end
  end
  // LCD electrical pins are kept in reset/idle until a board-specific page driver is selected.
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin lcd_sck<=0;lcd_mosi<=0;lcd_cs_n<=1;lcd_dc<=0;lcd_rst_n<=0;end
    else begin lcd_sck<=0;lcd_mosi<=0;lcd_cs_n<=1;lcd_dc<=1;lcd_rst_n<=1;end
  end
endmodule
