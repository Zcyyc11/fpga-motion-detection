`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_regs —— 寄存器堆自检仿真台（2026-10-12 版：6 位地址 + bbox 快照 + STATUS 位表）
//
// 自检项：
//   1) 复位值与接口冻结表 I4 一致（70/15/5/640/90/0）；
//   2) 写后读回一致（各字段位宽截断正确：LINE_X 只留 11bit 等）；
//   3) BBOX_* 快照读回（0x1C..0x34）与输入副本一致；地址 6 位：0x20/0x24 等
//      不再被 5 位截断（回归 10/12 前的静默错位雷）；
//   4) STATUS 位分配：bit0=b_valid / bit1=alarm / 15:8=obj_count /
//      30:16=frame_idx 低 15 位 / bit31=UART 丢包粘存（写 STATUS 清除）；
//   5) 写参数立即反映到 o_* 输出。
//
// 运行（Icarus）：iverilog -g2005 -o sim_regs src/rtl/regs.v sim/tb/tb_regs.v && vvp sim_regs
// 运行（Vivado）：python build/scripts/run_sim.py --top tb_regs
// -----------------------------------------------------------------------------
module tb_regs;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg         ps_en = 0, ps_we = 0;
    reg  [5:0]  ps_addr = 0;
    reg  [31:0] ps_wdata = 0;
    wire [31:0] ps_rdata;

    // bbox 快照副本输入（模拟 bbox_snapshot 的 AXI 钟域输出）
    reg  [15:0] s_x1 = 16'd100, s_y1 = 16'd80, s_x2 = 16'd139, s_y2 = 16'd109;
    reg  [15:0] s_cnt = 16'd1200, s_frame = 16'd1234;
    reg         s_valid = 1'b1, s_b_valid = 1'b1, s_alarm = 1'b0;
    reg  [7:0]  s_obj = 8'd3;
    reg         i_uart_drop = 0;

    wire [15:0] o_thresh, o_thresh_rel, o_dwell;
    wire [4:0]  o_alpha_shift;
    wire [10:0] o_line_x;
    wire        o_enable;

    regs dut (
        .clk(clk), .rst_n(rst_n),
        .ps_en(ps_en), .ps_we(ps_we), .ps_addr(ps_addr),
        .ps_wdata(ps_wdata), .ps_rdata(ps_rdata),
        .o_thresh(o_thresh), .o_thresh_rel(o_thresh_rel),
        .o_alpha_shift(o_alpha_shift), .o_line_x(o_line_x),
        .o_dwell(o_dwell), .o_enable(o_enable),
        .i_snap_x1(s_x1), .i_snap_y1(s_y1), .i_snap_x2(s_x2),
        .i_snap_y2(s_y2), .i_snap_cnt(s_cnt), .i_snap_valid(s_valid),
        .i_snap_frame(s_frame), .i_snap_obj_count(s_obj),
        .i_snap_b_valid(s_b_valid), .i_snap_alarm(s_alarm),
        .i_uart_drop(i_uart_drop)
    );

    integer errs = 0;

    task wr(input [5:0] a, input [31:0] d);
        begin
            @(posedge clk);
            ps_en <= 1; ps_we <= 1; ps_addr <= a; ps_wdata <= d;
            @(posedge clk);
            ps_en <= 0; ps_we <= 0;
        end
    endtask

    task rd_check(input [5:0] a, input [31:0] exp, input [255:0] name);
        begin
            @(posedge clk);
            ps_en <= 1; ps_we <= 0; ps_addr <= a;
            @(posedge clk);
            ps_en <= 0;
            #1;
            check(ps_rdata === exp, name);
        end
    endtask

    task check(input integer cond, input [255:0] msg);
        begin
            if (!cond) begin
                errs = errs + 1;
                $display("FAIL: %0s (rdata=%h)", msg, ps_rdata);
            end
        end
    endtask

    initial begin
        #12 rst_n = 1;
        #1;

        // 1) 复位值
        rd_check(6'h00, 32'd70,      "THRESH reset = 70");
        rd_check(6'h04, 32'd15,      "THRESH_REL reset = 15");
        rd_check(6'h08, 32'd5,       "ALPHA_SHIFT reset = 5");
        rd_check(6'h0C, 32'd640,     "LINE_X reset = 640");
        rd_check(6'h10, 32'd90,      "DWELL reset = 90");
        rd_check(6'h14, 32'd0,       "ENABLE reset = 0");

        // 2) 写后读回 + 位宽截断
        wr(6'h00, 32'd88);   rd_check(6'h00, 32'd88, "THRESH write/read 88");
        wr(6'h04, 32'd20);   rd_check(6'h04, 32'd20, "THRESH_REL write/read 20");
        wr(6'h08, 32'h1F);   rd_check(6'h08, 32'd31, "ALPHA_SHIFT write 31");
        wr(6'h0C, 32'h2000 + 32'd500); rd_check(6'h0C, 32'd500, "LINE_X 截断为 11bit=500");
        wr(6'h10, 32'd60);   rd_check(6'h10, 32'd60, "DWELL write/read 60");
        wr(6'h14, 32'd1);    rd_check(6'h14, 32'd1,  "ENABLE write/read 1");

        // 3) BBOX_* 快照读回（6 位地址，0x20 起不再截断）
        rd_check(6'h1C, 32'd100,  "BBOX_X1 = 100");
        rd_check(6'h20, 32'd80,   "BBOX_Y1 = 80");
        rd_check(6'h24, 32'd139,  "BBOX_X2 = 139");
        rd_check(6'h28, 32'd109,  "BBOX_Y2 = 109");
        rd_check(6'h2C, 32'd1200, "BBOX_CNT = 1200");
        rd_check(6'h30, 32'd1,    "BBOX_VALID = 1");
        rd_check(6'h34, 32'd1234, "BBOX_FRAME = 1234");
        // 超范围地址不挂、读 0
        rd_check(6'h38, 32'd0,    "0x38 超映射读 0");

        // 4) STATUS 位分配
        // 期望：{sticky=0, frame[14:0]=1234, obj=3, 6'b0, alarm=0, b_valid=1}
        //       = 1234<<16 | 3<<8 | 1
        rd_check(6'h18, (32'd1234 << 16) | (32'd3 << 8) | 32'd1,
                 "STATUS 初值：bit0=1 bit15:8=3 bit30:16=1234");
        s_alarm = 1'b1; #1;
        rd_check(6'h18, (32'd1234 << 16) | (32'd3 << 8) | 32'd3,
                 "STATUS bit1=alarm 置位后为 3");
        s_alarm = 1'b0; #1;
        s_b_valid = 1'b0; s_valid = 1'b0; #1;
        rd_check(6'h18, (32'd1234 << 16) | (32'd3 << 8),
                 "STATUS bit0 清零后低 8 位为 0");
        s_b_valid = 1'b1; s_valid = 1'b1; #1;

        // frame_idx 高位被截：只镜像低 15 位
        s_frame = 16'h8000 + 16'd7; #1;   // bit15=1, 低 15 位 = 7
        rd_check(6'h18, (32'd7 << 16) | (32'd3 << 8) | 32'd1,
                 "STATUS 30:16 只镜像 frame_idx 低 15 位");
        rd_check(6'h34, 32'h8007, "BBOX_FRAME 保留完整 16 位");

        // 4b) UART 丢包粘存位（bit31）
        @(posedge clk); i_uart_drop <= 1;
        @(posedge clk); i_uart_drop <= 0; #1;
        rd_check(6'h18, 32'h80000000 | (32'd7 << 16) | (32'd3 << 8) | 32'd1,
                 "i_uart_drop 脉冲后 bit31 粘存为 1");
        wr(6'h18, 32'h0);            // 写 STATUS = 清除
        rd_check(6'h18, (32'd7 << 16) | (32'd3 << 8) | 32'd1,
                 "写 STATUS 后丢包位清 0，其余位不变");

        // 5) 参数输出即时生效
        check(o_thresh === 16'd88, "o_thresh 应随写立即更新");
        check(o_line_x === 11'd500, "o_line_x 应随写立即更新");
        check(o_enable === 1'b1, "o_enable 应随写立即更新");

        if (errs == 0) $display("=== PASS：regs 仿真全部通过（6 位地址 + 快照 + STATUS 位表）===");
        else           $display("=== FAIL：%0d 项未通过 ===", errs);
        $finish;
    end

    initial begin
        #100_000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule
