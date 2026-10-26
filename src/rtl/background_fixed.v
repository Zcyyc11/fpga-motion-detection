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
    // All states fit W bits. A rounded step is never larger than |delta|,
    // so moving toward cur cannot underflow or exceed max(cur, ref_px).
    // Keep arithmetic at W/W+1 bits rather than synthesizing 32/33-bit carries.
    wire [W-1:0] scaled_cur={cur,{FRAC_BITS{1'b0}}};
    wire signed [W:0] delta=$signed({1'b0,scaled_cur})-$signed({1'b0,ref_px});
    wire [W-1:0] magnitude=delta[W] ? -delta : delta;
    wire foreground=magnitude > ({16'd0,thresh} << FRAC_BITS);
    wire [4:0] rate=foreground ? FG_SHIFT : shift_amt;
    wire [W:0] rounding=(rate==0 || rate>W) ? 0 : ({{W{1'b0}},1'b1} << (rate-1));
    wire [W:0] rounded={1'b0,magnitude}+rounding;
    wire [W-1:0] step=(rate>W) ? 0 : (rounded >> rate);
    wire [W-1:0] next_value=delta[W] ? ref_px-step : ref_px+step;
    wire [W-1:0] bounded=next_value>(1023<<FRAC_BITS) ? (1023<<FRAC_BITS) : next_value;
    // Ceil converts fractional magnitude to the existing integer comparator:
    // ceil(d/16)>T iff d>16*T, so the threshold decision is bit-exact.
    assign absdiff=(magnitude+((1<<FRAC_BITS)-1)) >> FRAC_BITS;
    assign wr_data=(mode_bg&&!init_phase) ? bounded : {cur,{FRAC_BITS{1'b0}}};
endmodule
