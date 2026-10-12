`timescale 1ns/1ps
module tb_track_duplicate;
    reg clk=0, rst_n=0, valid=0, tick=0, last=0;
    reg [15:0] x1=0,x2=0,far_x1=0,far_x2=0;
    always #5 clk=~clk;
    wire nv,fv;
    wire [7:0] ni,fi;
    wire [15:0] nd,fd;
    track near_dut(.clk(clk),.rst_n(rst_n),.t_valid(valid),.t_id(8'd0),
      .t_x1(x1),.t_y1(16'd40),.t_x2(x2),.t_y2(16'd54),.t_last(last),.frame_tick(tick),
      .o_valid(nv),.o_id(ni),.o_dwell(nd),.o_x1(),.o_y1(),.o_x2(),.o_y2(),.o_last());
    track far_dut(.clk(clk),.rst_n(rst_n),.t_valid(valid),.t_id(8'd0),
      .t_x1(far_x1),.t_y1(16'd40),.t_x2(far_x2),.t_y2(16'd54),.t_last(last),.frame_tick(tick),
      .o_valid(fv),.o_id(fi),.o_dwell(fd),.o_x1(),.o_y1(),.o_x2(),.o_y2(),.o_last());
    integer nc=0,fc=0,n0=-1,n1=-1,f0=-1,f1=-1;
    always @(negedge clk) if(rst_n) begin
      if(nv) begin
        if(nc==0) n0=ni; else n1=ni;
        nc=nc+1;
        $display("NEAR target=%0d id=%0d dwell=%0d",nc,ni,nd);
      end
      if(fv) begin
        if(fc==0) f0=fi; else f1=fi;
        fc=fc+1;
        $display("FAR target=%0d id=%0d dwell=%0d",fc,fi,fd);
      end
    end
    initial begin
      repeat(4) @(negedge clk);
      rst_n=1;
      @(negedge clk); valid=1; x1=20; x2=27; far_x1=20; far_x2=27;
      @(negedge clk); x1=40; x2=47; far_x1=100; far_x2=107; last=1;
      @(negedge clk); valid=0; last=0;
      @(negedge clk); tick=1;
      @(negedge clk); tick=0;
      $display("MATCH_STATE near_hits=%0d,%0d near_tr_n=%0d far_hits=%0d,%0d far_tr_n=%0d",
        near_dut.c_hit[0],near_dut.c_hit[1],near_dut.tr_n,
        far_dut.c_hit[0],far_dut.c_hit[1],far_dut.tr_n);
      repeat(8) @(negedge clk);
      if(fc==2 && f0!=f1) $display("PASS: LINE3_FAR_CONTROL_UNIQUE");
      else $display("FAIL: LINE3_FAR_CONTROL");
      if(nc==2 && n0!=n1) $display("PASS: LINE3_NEAR_IDS_UNIQUE");
      else $display("FAIL: LINE3_NEAR_DUPLICATE nc=%0d ids=%0d,%0d",nc,n0,n1);
      $display("LINE3_TRACK_PROBE_DONE");
      $finish;
    end
    initial begin #10000; $fatal(1,"LINE3_TRACK_PROBE_TIMEOUT"); end
endmodule
