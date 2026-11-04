`timescale 1ns / 1ps
// Bounded three-frame store. See docs/uart_resource_contract.md.
module uart_tx #(parameter integer BAUD_DIV = 868)(
 input wire clk, rst_n,
 input wire s_valid, input wire [7:0] s_id,
 input wire [15:0] s_x1,s_y1,s_x2,s_y2,
 input wire e_valid, input wire [7:0] e_id,
 input wire [1:0] e_type, input wire [15:0] e_cx,
 input wire frame_tick, output reg tx, output reg drop
);
 function [1:0] next_bank(input [1:0] b);
 begin next_bank=(b==2)?0:b+1'b1;end
 endfunction
 // One write port per record kind; no reset on RAM data. Synchronous reads.
 (* ram_style = "block" *) reg [71:0] objects[0:47];
 (* ram_style = "block" *) reg [25:0] events[0:47];
 reg [71:0] object_q; reg [25:0] event_q;
 reg [5:0] read_addr;
 reg read_object,read_event;
 reg [1:0] capture_bank,send_bank;
 reg capture_valid,capture_bad;
 reg [4:0] object_count,event_count;
 reg [15:0] frame_num;
 reg [2:0] occupied,ready;
 reg [15:0] bank_frame[0:2];
 reg [4:0] bank_objects[0:2],bank_events[0:2];
 wire seal = frame_tick && capture_valid && !capture_bad;
 wire [1:0] incoming_bank = seal ? next_bank(capture_bank) : capture_bank;
 wire input_accept = frame_tick ? !occupied[incoming_bank] : (capture_valid && !capture_bad);
 wire [1:0] write_bank = frame_tick ? incoming_bank : capture_bank;
 wire [4:0] object_index = frame_tick ? 5'd0 : object_count;
 wire [4:0] event_index = frame_tick ? 5'd0 : event_count;
 wire capacity_error = input_accept && ((s_valid && object_index==16) || (e_valid && event_index==16));
 // RAM writes remain single, unconditional in shape; control reset gates enable.
 always @(posedge clk) begin
  if(rst_n && input_accept && !capacity_error && s_valid)
   objects[{write_bank,object_index[3:0]}] <= {s_y2,s_x2,s_y1,s_x1,s_id};
  if(rst_n && input_accept && !capacity_error && e_valid)
   events[{write_bank,event_index[3:0]}] <= {e_cx,e_type,e_id};
  if(read_object) object_q <= objects[read_addr];
  if(read_event) event_q <= events[read_addr];
 end
 localparam IDLE=0, PACKET=1, READ_OBJ=2, LOAD_OBJ=3, READ_EVT=4, LOAD_EVT=5, ADVANCE=6;
 reg [2:0] state;
 reg [1:0] packet_kind;
 reg [4:0] object_sent,event_sent;
 reg [15:0] sending_frame;
 reg [4:0] sending_objects,sending_events;
 reg [103:0] payload;
 reg [3:0] bytes_left;
 reg [7:0] checksum;
 reg [9:0] uart_shift;
 reg [3:0] bits_left;
 localparam integer BAUD_BITS = (BAUD_DIV<2)?1:$clog2(BAUD_DIV);
 reg [BAUD_BITS-1:0] baud_count;
 wire uart_idle=(bits_left==0);
 integer b;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   capture_bank<=0;send_bank<=0;capture_valid<=1;capture_bad<=0;
   object_count<=0;event_count<=0;frame_num<=0;occupied<=0;ready<=0;
   state<=IDLE;packet_kind<=0;object_sent<=0;event_sent<=0;
   sending_frame<=0;sending_objects<=0;sending_events<=0;
   payload<=0;bytes_left<=0;checksum<=0;uart_shift<=10'h3ff;bits_left<=0;baud_count<=0;
   read_addr<=0;read_object<=0;read_event<=0;tx<=1;drop<=0;
   for(b=0;b<3;b=b+1)begin bank_frame[b]<=0;bank_objects[b]<=0;bank_events[b]<=0;end
  end else begin
   drop<=0;read_object<=0;read_event<=0;
   if(frame_tick)begin
    frame_num<=frame_num+1'b1;
    if(seal)begin
     occupied[capture_bank]<=1;ready[capture_bank]<=1;
     bank_frame[capture_bank]<=frame_num;
     bank_objects[capture_bank]<=object_count;bank_events[capture_bank]<=event_count;
    end
    capture_bank<=incoming_bank;capture_valid<=!occupied[incoming_bank];capture_bad<=0;
    object_count<=input_accept && s_valid ? 1 : 0;
    event_count<=input_accept && e_valid ? 1 : 0;
    if(!capture_valid)drop<=1;
   end else if(input_accept)begin
    if(capacity_error)begin capture_bad<=1;drop<=1;end
    else begin
     if(s_valid)object_count<=object_count+1'b1;
     if(e_valid)event_count<=event_count+1'b1;
    end
   end
   // UART timing: every start/data/stop bit lasts exactly BAUD_DIV clocks.
   if(!uart_idle)begin
    if(baud_count==BAUD_DIV-1)begin
     baud_count<=0;bits_left<=bits_left-1'b1;
     uart_shift<={1'b1,uart_shift[9:1]};tx<=uart_shift[1];
    end else baud_count<=baud_count+1'b1;
   end
   case(state)
    IDLE:if(ready[send_bank])begin
     ready[send_bank]<=0;
     sending_frame<=bank_frame[send_bank];
     sending_objects<=bank_objects[send_bank];sending_events<=bank_events[send_bank];
     object_sent<=0;event_sent<=0;
     payload<={72'd0,3'd0,bank_objects[send_bank],bank_frame[send_bank],8'h5a};
     bytes_left<=4;checksum<=0;packet_kind<=0;state<=PACKET;
    end
    PACKET:if(uart_idle)begin
     bits_left<=10;baud_count<=0;
     if(bytes_left!=0)begin
      uart_shift<={1'b1,payload[7:0],1'b0};tx<=0;
      checksum<=checksum+payload[7:0];payload<={8'd0,payload[103:8]};bytes_left<=bytes_left-1'b1;
     end else begin
      uart_shift<={1'b1,checksum,1'b0};tx<=0;state<=ADVANCE;
     end
    end
    ADVANCE:if(uart_idle)begin
     if(object_sent<sending_objects)begin
      read_addr<={send_bank,object_sent[3:0]};read_object<=1;state<=READ_OBJ;
     end else if(event_sent<sending_events)begin
      read_addr<={send_bank,event_sent[3:0]};read_event<=1;state<=READ_EVT;
     end else begin
      occupied[send_bank]<=0;send_bank<=next_bank(send_bank);state<=IDLE;
     end
    end
    READ_OBJ:state<=LOAD_OBJ;
    LOAD_OBJ:begin
     payload<={8'd0,object_q,sending_frame,8'ha5};bytes_left<=13;checksum<=0;
     object_sent<=object_sent+1'b1;packet_kind<=1;state<=PACKET;
    end
    READ_EVT:state<=LOAD_EVT;
    LOAD_EVT:begin
     payload<={48'd0,event_q[25:10],6'd0,event_q[9:8],event_q[7:0],sending_frame,8'hc3};
     bytes_left<=7;checksum<=0;event_sent<=event_sent+1'b1;packet_kind<=2;state<=PACKET;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule

