`timescale 1ns / 1ps
// Sequential greedy Manhattan tracker.
// A tick closes the old accumulation window. A simultaneous t_valid belongs
// to the NEW window (including when the old window was empty).
// Two banks allow all next-frame metadata to arrive while processing runs.
// There is no ready port: consecutive ticks must be at least FRAME_CYCLES
// clocks apart, and each window must contain at most MAX_TARGET inputs.
// FRAME_CYCLES = MAX_TARGET*(MAX_TRACK*MAX_TRACK+3*MAX_TRACK+7)
// + MAX_TRACK + 4 (default 4996 clocks).
// This conservative bound includes candidate-ID collisions, stable compaction
// and output. Actual video frame periods are far longer. Simulation fails on
// violations instead of hiding dropped metadata. t_id/t_last are informational;
// frame_tick, including zero-target windows, defines the accumulation boundary.
// A full live table may reject an unmatched target, when no track slot is available.
module track #(
    parameter integer MAX_TRACK=16,
    parameter integer MAX_TARGET=16,
    parameter integer MATCH_DIST=48,
    parameter integer MISSED_MAX=5
)(
    input wire clk, rst_n,
    input wire t_valid,
    input wire [7:0] t_id,
    input wire [15:0] t_x1,t_y1,t_x2,t_y2,
    input wire t_last, frame_tick,
    output reg o_valid,
    output reg [7:0] o_id,
    output reg [15:0] o_x1,o_y1,o_x2,o_y2,o_dwell,
    output reg o_last,
    output reg o_done // one clock after last output; also emitted for empty batches
);
    localparam TW=(MAX_TRACK<2)?1:$clog2(MAX_TRACK+1);
    localparam CW=(MAX_TARGET<2)?1:$clog2(MAX_TARGET+1);
    localparam AW=(2*MAX_TARGET<2)?1:$clog2(2*MAX_TARGET);
    localparam [3:0] IDLE=0,LOAD=1,SCAN=2,DECIDE=3,ID_SCAN=4,
                     APPEND=5,ADVANCE=6,AGE=7,EMIT=8;
    reg [3:0] state;
    reg [15:0] c_x1[0:2*MAX_TARGET-1],c_y1[0:2*MAX_TARGET-1];
    reg [15:0] c_x2[0:2*MAX_TARGET-1],c_y2[0:2*MAX_TARGET-1];
    reg capture_bank,process_bank;
    reg [CW-1:0] c_n,process_n,target_k,out_n,out_k;
    wire [AW-1:0] capture_addr=(capture_bank?MAX_TARGET:0)+c_n;
    wire [AW-1:0] target_addr=(process_bank?MAX_TARGET:0)+target_k;
    reg [CW-1:0] out_target[0:MAX_TARGET-1];
    reg [7:0] out_id[0:MAX_TARGET-1];
    reg [15:0] out_dw[0:MAX_TARGET-1];
    wire [AW-1:0] output_addr=(process_bank?MAX_TARGET:0)+out_target[out_k];

    // Only the prefix [0,tr_n) is live. Compaction is stable, preserving the
    // original first-track tie break. Coordinates need no asynchronous reset.
    reg [TW-1:0] tr_n,scan_k,best,selected,compact_n;
    reg [7:0] tr_id[0:MAX_TRACK-1];
    reg [15:0] tr_cx[0:MAX_TRACK-1],tr_cy[0:MAX_TRACK-1];
    reg [15:0] tr_seen[0:MAX_TRACK-1],tr_miss[0:MAX_TRACK-1];
    reg tr_m[0:MAX_TRACK-1];
    reg [7:0] id_next;
    reg [15:0] cur_cx,cur_cy;
    reg [16:0] best_dist;
    wire [16:0] sum_x={1'b0,c_x1[target_addr]}+{1'b0,c_x2[target_addr]};
    wire [16:0] sum_y={1'b0,c_y1[target_addr]}+{1'b0,c_y2[target_addr]};
    wire [15:0] dx=(cur_cx>=tr_cx[scan_k])?(cur_cx-tr_cx[scan_k]):(tr_cx[scan_k]-cur_cx);
    wire [15:0] dy=(cur_cy>=tr_cy[scan_k])?(cur_cy-tr_cy[scan_k]):(tr_cy[scan_k]-cur_cy);
    wire [16:0] distance={1'b0,dx}+{1'b0,dy};

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            state<=IDLE;capture_bank<=0;process_bank<=0;c_n<=0;process_n<=0;
            tr_n<=0;id_next<=0;scan_k<=0;best<=0;selected<=0;compact_n<=0;
            target_k<=0;out_n<=0;out_k<=0;cur_cx<=0;cur_cy<=0;best_dist<=0;
            o_valid<=0;o_last<=0;o_done<=0;o_id<=0;o_x1<=0;o_y1<=0;o_x2<=0;o_y2<=0;o_dwell<=0;
        end else begin
            o_valid<=0;o_last<=0;o_done<=0;
            // Independent capture: the processing FSM never blocks t_valid.
            if(frame_tick)begin
                capture_bank<=~capture_bank;
                c_n<=t_valid?1:0;
                if(t_valid)begin
                    c_x1[capture_bank?0:MAX_TARGET]<=t_x1;
                    c_y1[capture_bank?0:MAX_TARGET]<=t_y1;
                    c_x2[capture_bank?0:MAX_TARGET]<=t_x2;
                    c_y2[capture_bank?0:MAX_TARGET]<=t_y2;
                end
            end else if(t_valid && c_n<MAX_TARGET)begin
                c_x1[capture_addr]<=t_x1;c_y1[capture_addr]<=t_y1;
                c_x2[capture_addr]<=t_x2;c_y2[capture_addr]<=t_y2;c_n<=c_n+1'b1;
            end
            case(state)
            IDLE:if(frame_tick)begin
                process_bank<=capture_bank;process_n<=c_n;target_k<=0;
                out_n<=0;out_k<=0;scan_k<=0;compact_n<=0;
                state<=(c_n==0)?AGE:LOAD;
            end
            LOAD:begin
                cur_cx<=sum_x[16:1];cur_cy<=sum_y[16:1];
                best<=MAX_TRACK;best_dist<=17'h1ffff;scan_k<=0;state<=SCAN;
            end
            SCAN:begin
                if(scan_k<tr_n)begin
                    if(!tr_m[scan_k] && distance<=MATCH_DIST && distance<best_dist)begin
                        best<=scan_k;best_dist<=distance;
                    end
                    scan_k<=scan_k+1'b1;
                end else state<=DECIDE;
            end
            DECIDE:begin
                if(best!=MAX_TRACK)begin
                    selected<=best;tr_cx[best]<=cur_cx;tr_cy[best]<=cur_cy;
                    tr_m[best]<=1;tr_miss[best]<=0;
                    if(tr_seen[best]!=16'hffff)tr_seen[best]<=tr_seen[best]+1'b1;
                    state<=APPEND;
                end else if(tr_n<MAX_TRACK)begin scan_k<=0;state<=ID_SCAN;end
                else state<=ADVANCE;
            end
            // At most tr_n occupied candidates are skipped. Since tr_n<256
            // whenever a slot is free, a free 8-bit ID always exists.
            ID_SCAN:begin
                if(scan_k<tr_n)begin
                    if(tr_id[scan_k]==id_next)begin id_next<=id_next+1'b1;scan_k<=0;end
                    else scan_k<=scan_k+1'b1;
                end else begin
                    selected<=tr_n;tr_id[tr_n]<=id_next;id_next<=id_next+1'b1;
                    tr_cx[tr_n]<=cur_cx;tr_cy[tr_n]<=cur_cy;
                    tr_seen[tr_n]<=16'd1;tr_miss[tr_n]<=0;tr_m[tr_n]<=1;
                    tr_n<=tr_n+1'b1;state<=APPEND;
                end
            end
            APPEND:begin
                out_id[out_n]<=tr_id[selected];out_dw[out_n]<=tr_seen[selected];
                out_target[out_n]<=target_k;out_n<=out_n+1'b1;state<=ADVANCE;
            end
            ADVANCE:begin
                if(target_k+1<process_n)begin target_k<=target_k+1'b1;state<=LOAD;end
                else begin scan_k<=0;compact_n<=0;state<=AGE;end
            end
            AGE:begin
                if(scan_k<tr_n)begin
                    // Preserve the original tolerance: delete when the new
                    // missed count EXCEEDS MISSED_MAX, not when equal to it.
                    if(tr_m[scan_k] || tr_miss[scan_k]<MISSED_MAX)begin
                        tr_id[compact_n]<=tr_id[scan_k];tr_cx[compact_n]<=tr_cx[scan_k];
                        tr_cy[compact_n]<=tr_cy[scan_k];tr_seen[compact_n]<=tr_seen[scan_k];
                        tr_miss[compact_n]<=tr_m[scan_k]?16'd0:tr_miss[scan_k]+1'b1;
                        tr_m[compact_n]<=0;compact_n<=compact_n+1'b1;
                    end
                    scan_k<=scan_k+1'b1;
                end else begin tr_n<=compact_n;out_k<=0;state<=EMIT;end
            end
            EMIT:begin
                if(out_k<out_n)begin
                    o_valid<=1;o_id<=out_id[out_k];o_dwell<=out_dw[out_k];
                    o_x1<=c_x1[output_addr];o_y1<=c_y1[output_addr];
                    o_x2<=c_x2[output_addr];o_y2<=c_y2[output_addr];
                    o_last<=(out_k==out_n-1'b1);out_k<=out_k+1'b1;
                end else begin state<=IDLE;o_done<=1;end
            end
            default:state<=IDLE;
            endcase
        end
    end
    // synthesis translate_off
    initial begin
        if(MAX_TRACK<1 || MAX_TRACK>256 || MAX_TARGET<1 || MAX_TARGET>256)
            $fatal(1,"track counts must be within 1..256");
        if(MISSED_MAX<0 || MISSED_MAX>65535 || MATCH_DIST<0)
            $fatal(1,"invalid track thresholds");
    end
    always @(posedge clk)if(rst_n)begin
        if(frame_tick && state!=IDLE)$fatal(1,"track frame period violates processing bound");
        if(!frame_tick && t_valid && c_n>=MAX_TARGET)$fatal(1,"track input exceeds MAX_TARGET");
    end
    // synthesis translate_on
endmodule
