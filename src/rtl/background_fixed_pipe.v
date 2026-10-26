`timescale 1ns/1ps
// Three registered update stages: delta/rate -> rounded step -> new state.
// Read-side mask timing stays unchanged; write address/valid travel with data.
module background_fixed_pipe #(
 parameter integer FRAC_BITS=4, FG_SHIFT=10, AW=18
)(
 input wire clk,rst_n,in_valid,mode_bg,init_phase,
 input wire [AW-1:0] in_addr,
 input wire [4:0] shift_amt,
 input wire [15:0] thresh,
 input wire [9:0] cur,
 input wire [9+FRAC_BITS:0] ref_px,
 output reg out_valid,
 output reg [AW-1:0] out_addr,
 output reg [9+FRAC_BITS:0] wr_data
);
 localparam integer W=10+FRAC_BITS;
 wire [W-1:0] scaled_cur={cur,{FRAC_BITS{1'b0}}};
 wire signed [W:0] delta=$signed({1'b0,scaled_cur})-$signed({1'b0,ref_px});
 wire [W-1:0] magnitude=delta[W] ? -delta : delta;
 wire foreground=magnitude>({16'd0,thresh}<<FRAC_BITS);
 reg v1,v2,sign1,sign2,bypass1,bypass2;
 reg [AW-1:0] addr1,addr2;
 reg [W-1:0] mag1,ref1,ref2,cur1,cur2,step2;
 reg [4:0] rate1;
 wire [W:0] rounding=(rate1==0 || rate1>W) ? 0 : ({{W{1'b0}},1'b1} << (rate1-1));
 wire [W:0] rounded={1'b0,mag1}+rounding;
 wire [W-1:0] step=(rate1>W) ? 0 : (rounded >> rate1);
 // Rounded movement toward cur lies between ref_px and cur, without underflow.
 wire [W-1:0] next_value=sign2 ? ref2-step2 : ref2+step2;
 wire [W-1:0] bounded=next_value>(1023<<FRAC_BITS) ? (1023<<FRAC_BITS) : next_value;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   v1<=0;v2<=0;out_valid<=0;addr1<=0;addr2<=0;out_addr<=0;wr_data<=0;
   sign1<=0;sign2<=0;bypass1<=1;bypass2<=1;
   mag1<=0;ref1<=0;ref2<=0;cur1<=0;cur2<=0;step2<=0;rate1<=0;
  end else begin
   v1<=in_valid;v2<=v1;out_valid<=v2;
   addr1<=in_addr;addr2<=addr1;out_addr<=addr2;
   mag1<=magnitude;sign1<=delta[W];ref1<=ref_px;cur1<=scaled_cur;
   rate1<=foreground ? FG_SHIFT : shift_amt;bypass1<=!mode_bg || init_phase;
   step2<=step;sign2<=sign1;ref2<=ref1;cur2<=cur1;bypass2<=bypass1;
   wr_data<=bypass2 ? cur2 : bounded;
  end
 end
endmodule
