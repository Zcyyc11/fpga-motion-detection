`timescale 1ns/1ps
// Fixed-point running background. Preserve fractional state, round both signs
// symmetrically, and learn foreground slowly to retain slow/stopped objects.
// Default pipeline remains legacy unless BG_FRAC_BITS is explicitly enabled.
module background_fixed #(
    parameter integer FRAC_BITS=4,
    parameter integer FG_SHIFT=10
)(
    input wire mode_bg,
    input wire init_phase,
    input wire [4:0] shift_amt,
    input wire [15:0] thresh,
    input wire [9:0] cur,
    input wire [9+FRAC_BITS:0] ref_px,
    output wire [10:0] absdiff,
    output wire [9+FRAC_BITS:0] wr_data
);
    localparam integer W=10+FRAC_BITS;
    wire signed [W+1:0] delta=$signed({2'b00,cur,{FRAC_BITS{1'b0}}})-$signed({2'b00,ref_px});
    wire [W+1:0] magnitude=delta[W+1] ? -delta : delta;
    wire foreground=magnitude > ({16'd0,thresh} << FRAC_BITS);
    wire [4:0] rate=foreground ? FG_SHIFT : shift_amt;
    wire [31:0] rounding=(rate==0) ? 32'd0 : (32'd1 << (rate-1));
    wire [31:0] step=(magnitude+rounding) >> rate;
    wire signed [32:0] next_value=$signed({1'b0,{{(32-W){1'b0}},ref_px}})+
        (delta[W+1] ? -$signed({1'b0,step}) : $signed({1'b0,step}));
    wire [W-1:0] bounded=next_value<0 ? {W{1'b0}} :
        next_value>(1023<<FRAC_BITS) ? (1023<<FRAC_BITS) : next_value[W-1:0];
    // Ceil converts fractional magnitude to the existing integer comparator:
    // ceil(d/16)>T iff d>16*T, so the threshold decision is bit-exact.
    assign absdiff=(magnitude+((1<<FRAC_BITS)-1)) >> FRAC_BITS;
    assign wr_data=(mode_bg&&!init_phase) ? bounded : {cur,{FRAC_BITS{1'b0}}};
endmodule
