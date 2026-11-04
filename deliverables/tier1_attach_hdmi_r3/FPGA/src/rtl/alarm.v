`timescale 1ns / 1ps
// Per-ID crossing and dwell history. A dwell of one starts a NEW lifetime,
// including reused IDs after wrap. Crossing wins when both rules trigger.
// Repeated saturated dwell values cannot repeat the dwell event.
module alarm #(parameter integer MAX_ID=256)(
    input wire clk,rst_n,
    input wire [15:0] LINE_X,DWELL,
    input wire t_valid,
    input wire [7:0] t_id,
    input wire [15:0] t_x1,t_y1,t_x2,t_y2,t_dwell,
    output reg a_valid,
    output reg [7:0] a_id,
    output reg [1:0] a_type,
    output reg [15:0] a_cx
);
    reg [MAX_ID-1:0] seen;
    reg [15:0] prev_cx[0:MAX_ID-1];
    reg [15:0] prev_dwell[0:MAX_ID-1];
    wire [16:0] sum_x={1'b0,t_x1}+{1'b0,t_x2};
    wire [15:0] cx=sum_x[16:1];
    wire new_lifetime=!seen[t_id] || t_dwell==16'd1;
    wire cross_now=!new_lifetime && LINE_X!=0 && prev_cx[t_id]<LINE_X && cx>=LINE_X;
    wire dwell_now=DWELL!=0 && t_dwell==DWELL &&
                   (new_lifetime || prev_dwell[t_id]!=t_dwell);
    // Data arrays do not require reset: seen guards all previous values.
    // This permits RAM inference instead of thousands of resettable flops.
    always @(posedge clk)begin
        if(rst_n && t_valid && t_id<MAX_ID)begin
            prev_cx[t_id]<=cx;prev_dwell[t_id]<=t_dwell;
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin seen<=0;a_valid<=0;a_id<=0;a_type<=0;a_cx<=0;end
        else begin
            a_valid<=0;
            if(t_valid && t_id<MAX_ID)begin
                seen[t_id]<=1;
                if(cross_now || dwell_now)begin
                    a_valid<=1;a_id<=t_id;a_type<=cross_now?2'd1:2'd2;a_cx<=cx;
                end
            end
        end
    end
    // synthesis translate_off
    initial if(MAX_ID<1 || MAX_ID>256)$fatal(1,"alarm MAX_ID must be within 1..256");
    always @(posedge clk)if(rst_n && t_valid && t_id>=MAX_ID)$fatal(1,"alarm ID outside MAX_ID");
    // synthesis translate_on
endmodule
