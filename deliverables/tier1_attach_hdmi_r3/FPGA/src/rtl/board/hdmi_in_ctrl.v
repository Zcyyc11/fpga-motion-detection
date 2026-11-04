`timescale 1ns/1ps
// Pixel-domain coordinate reconstruction for the EDID-selected 720p mode.
// VS rising edge realigns the next active line; an active-line counter also
// wraps at V_ACTIVE so missing or stuck VS cannot stop metadata indefinitely.
// Other resolutions must configure V_ACTIVE to match the source.
module hdmi_in_ctrl #(
 parameter integer WDT_FRAMES=5,
 parameter integer V_ACTIVE=720
)(
 input wire clk,rst_n,pVDE,pHSync,pVSync,
 input wire [23:0] pData,
 input wire pLocked,
 output reg de,hs,vs,
 output reg [15:0] x,y,
 output reg sof,
 output reg [23:0] pix_data,
 output wire locked
);
 localparam integer WDT_MAX=74_250_000*WDT_FRAMES/60;
 reg pVDE_d,pVSync_d,pending_sof;
 reg [15:0] x_cnt,y_cnt;
 reg [31:0] wdt_cnt;
 reg wdt_alive;
 wire de_rise=pVDE && !pVDE_d;
 wire vs_rise=pVSync && !pVSync_d;
 wire sof_cnd=de_rise && (pending_sof || y_cnt==V_ACTIVE-1);
 wire [15:0] pixel_y=sof_cnd ? 16'd0 : (de_rise ? y_cnt+16'd1 : y_cnt);
 assign locked=pLocked && (wdt_alive || sof_cnd);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   pVDE_d<=0;pVSync_d<=0;pending_sof<=0;
   x_cnt<=0;y_cnt<=V_ACTIVE-1;wdt_cnt<=0;wdt_alive<=0;
  end else if(!pLocked) begin
   pVDE_d<=0;pVSync_d<=0;pending_sof<=0;
   x_cnt<=0;y_cnt<=V_ACTIVE-1;wdt_cnt<=0;wdt_alive<=0;
  end else begin
   pVDE_d<=pVDE;pVSync_d<=pVSync;
   if(vs_rise) pending_sof<=1;
   else if(de_rise) pending_sof<=0;
   // x_cnt holds the coordinate for the NEXT pixel in the active line.
   if(pVDE) begin
    x_cnt<=de_rise ? 16'd1 : x_cnt+16'd1;
    if(de_rise) y_cnt<=pixel_y;
   end
   if(sof_cnd || vs_rise) begin wdt_cnt<=0;wdt_alive<=1;end
   else if(wdt_cnt>=WDT_MAX) wdt_alive<=0;
   else wdt_cnt<=wdt_cnt+1'b1;
  end
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   de<=0;hs<=0;vs<=0;sof<=0;x<=0;y<=0;pix_data<=0;
  end else if(locked) begin
   de<=pVDE;hs<=pHSync;vs<=pVSync;sof<=sof_cnd;
   x<=de_rise ? 16'd0 : x_cnt;y<=pixel_y;pix_data<=pData;
  end else begin
   de<=0;hs<=0;vs<=0;sof<=0;x<=0;y<=0;pix_data<=0;
  end
 end
endmodule
