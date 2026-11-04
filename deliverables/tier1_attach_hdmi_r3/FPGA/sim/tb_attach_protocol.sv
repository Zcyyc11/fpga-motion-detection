`timescale 1ns/1ps
// Black-box electrical/protocol checks at the actual 74.25 MHz input clock.
module tb_attach_protocol;
  localparam integer CLK_HZ=74250000;
  localparam integer SCAN_DIV=8250;
  reg clk=0,rst_n=0;
  always #6.734006734 clk=~clk;
  reg [7:0] target_count=12;
  reg [15:0] threshold=3456, fps=60, violation_count=78;
  reg [1:0] mode=2;
  reg target_present=1, violation_event=0;
  wire [7:0] delta; wire night;
  wire [6:0] seg; wire [8:0] digit;
  wire ws,ls,lm,lc,ld,lr,lb,bz,tsc,tsd;
  attach_z2_interaction #(.CLK_HZ(CLK_HZ)) dut(
    .clk(clk),.rst_n(rst_n),.target_count(target_count),.threshold(threshold),.mode(mode),
    .fps(fps),.violation_count(violation_count),.target_present(target_present),.violation_event(violation_event),
    .light_dark(1'b0),.enc_a(1'b0),.enc_b(1'b0),.enc_push(1'b0),.fiveway(5'd0),
    .threshold_delta(delta),.night_mode(night),.seg(seg),.digit(digit),.ws2812_din(ws),
    .lcd_sck(ls),.lcd_mosi(lm),.lcd_cs_n(lc),.lcd_dc(ld),.lcd_rst_n(lr),.lcd_bkl(lb),
    .buzzer(bz),.touch_scl(tsc),.touch_sda(tsd));
  integer test_id, errors=0, cycles=0, i, idx, slots=0;
  integer expected[0:8]; reg [8:0] seen=0, prev_digit=0;
  reg prev_ws=0,prev_bz=0; integer high_cycles=0,low_cycles=0,last_rise=-1;
  integer bits=0,frames=0,words=0; reg [23:0] word_data=0;
  integer first_bz=-1,last_bz=-1,bz_edges=0,edge_cycle=-1;
  bit polarity_error=0,pattern_error=0,ws_timing_error=0,ws_frame_error=0;
  function [6:0] expected_seg(input integer n);
    case(n)
      1:expected_seg=7'b1111001;2:expected_seg=7'b0100100;
      3:expected_seg=7'b0110000;4:expected_seg=7'b0011001;
      5:expected_seg=7'b0010010;6:expected_seg=7'b0000010;
      7:expected_seg=7'b1111000;8:expected_seg=7'b0000000;
      default:expected_seg=7'b1000000;
    endcase
  endfunction
  task fail(input string reason);
    begin errors=errors+1; $display("CHECK_FAIL %s",reason); end
  endtask
  initial begin
    if($test$plusargs("TEST1")) test_id=1; else if($test$plusargs("TEST2")) test_id=2; else test_id=0;
    expected[0]=1;expected[1]=2;expected[2]=2;expected[3]=3;expected[4]=4;
    expected[5]=5;expected[6]=6;expected[7]=7;expected[8]=8;
    repeat(10) @(negedge clk);
    if(digit!==9'd0 && test_id==0) fail("reset must disable all active-high digit MOSFETs");
    rst_n=1;
    if(test_id==0) begin
      repeat(SCAN_DIV*20) begin
        @(negedge clk); cycles=cycles+1;
        if(digit!=0 && digit!=prev_digit) begin
          slots=slots+1;
          if($countones(digit)!=1) begin
            if(!polarity_error) fail("exactly one active-high digit required");
            polarity_error=1;
          end else begin
            for(i=0;i<9;i=i+1) if(digit[i]) begin
              seen[i]=1;
              if(seg!==expected_seg(expected[i]) && !pattern_error) begin
                fail("segment pattern does not match selected digit value");pattern_error=1;
              end
            end
          end
        end
        prev_digit=digit;
      end
      if(seen!==9'h1ff) fail("all nine digit positions must be visited");
      if(slots<18) fail("scan cadence did not cover two complete displays");
      $display("SCAN_EVIDENCE seen=%h slots=%0d",seen,slots);
    end else if(test_id==1) begin
      repeat(130000) begin
        @(negedge clk); cycles=cycles+1;
        if(ws) begin
          if(!prev_ws) begin
            if(last_rise<0 || low_cycles>=20800) begin
              if(low_cycles<22275 && !ws_frame_error) begin fail("WS reset low must be at least 300 us");ws_frame_error=1;end
              if(last_rise>=0) begin
                if(bits!=192 && !ws_frame_error) begin fail("WS frame must contain exactly 8 x 24 bits");ws_frame_error=1;end
                frames=frames+1;bits=0;words=0;
              end
            end else if(cycles-last_rise!=95 && !ws_timing_error) begin
              fail("WS bit period must be 95 cycles at 74.25 MHz");ws_timing_error=1;
            end
            last_rise=cycles;high_cycles=1;low_cycles=0;
          end else high_cycles=high_cycles+1;
        end else begin
          if(prev_ws) begin
            if(high_cycles!=22 && high_cycles!=48 && !ws_timing_error) begin
              fail("WS high duration must be 22 or 48 cycles");ws_timing_error=1;
            end
            word_data={word_data[22:0],(high_cycles>35)}; bits=bits+1;
            if(bits%24==0) begin
              if(word_data!==24'h404000 && !ws_frame_error) begin fail("WS decoded GRB payload mismatch");ws_frame_error=1;end
              words=words+1;
            end
            low_cycles=1;high_cycles=0;
          end else low_cycles=low_cycles+1;
        end
        prev_ws=ws;
      end
      if(frames<2) fail("no two complete WS frames with latch gaps");
      $display("WS_EVIDENCE complete_frames=%0d current_bits=%0d",frames,bits);
    end else begin
      @(negedge clk);violation_event=1;
      repeat(CLK_HZ/10+CLK_HZ/100) begin
        @(negedge clk);cycles=cycles+1;
        if(bz) begin if(first_bz<0)first_bz=cycles;last_bz=cycles;end
        if(bz!=prev_bz) begin
          if(edge_cycle>=0 && cycles-edge_cycle!=18562 && cycles-edge_cycle!=18563 && bz && !pattern_error) begin
            fail("passive buzzer must generate a 2 kHz square wave");pattern_error=1;
          end
          edge_cycle=cycles;bz_edges=bz_edges+1;
        end
        prev_bz=bz;
      end
      if(first_bz<0 || last_bz-first_bz < CLK_HZ/10-CLK_HZ/2000) fail("beep envelope shorter than 100 ms");
      if(last_bz>CLK_HZ/10+2) fail("held violation must not retrigger envelope");
      if(bz_edges<398 || bz_edges>402) fail("expected about 400 buzzer edges in 100 ms");
      if(bz!==0) fail("buzzer must idle low after envelope");
      $display("BUZZER_EVIDENCE first=%0d last=%0d edges=%0d",first_bz,last_bz,bz_edges);
    end
    if(errors) $fatal(1,"ATTACH_PROTOCOL_FAIL test=%0d errors=%0d",test_id,errors);
    $display("ATTACH_PROTOCOL_PASS test=%0d",test_id);$finish;
  end
endmodule
