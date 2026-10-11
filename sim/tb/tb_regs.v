`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_regs —— 寄存器堆自检仿真台
//
// 自检项：
//   1) 复位值与接口冻结表 I4 一致（70/15/5/640/90/0）；
//   2) 写后读回一致（各字段位宽截断正确：LINE_X 只留 11bit 等）；
//   3) STATUS 只读：写被忽略，读回 i_status；
//   4) 写参数立即反映到 o_* 输出。
//
// 运行（Icarus）：iverilog -g2005 -o sim_regs src/rtl/regs.v sim/tb/tb_regs.v && vvp sim_regs
// 运行（Vivado）：python build/scripts/run_sim.py --top tb_regs
// -----------------------------------------------------------------------------
module tb_regs;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg         ps_en = 0, ps_we = 0;
    reg  [4:0]  ps_addr = 0;
    reg  [31:0] ps_wdata = 0;
    wire [31:0] ps_rdata;
    reg  [31:0] i_status = 32'hDEADBEEF;

    wire [15:0] o_thresh, o_thresh_rel, o_dwell;
    wire [4:0]  o_alpha_shift;
    wire [10:0] o_line_x;
    wire        o_enable;

    regs dut (
        .clk(clk), .rst_n(rst_n),
        .ps_en(ps_en), .ps_we(ps_we), .ps_addr(ps_addr),
        .ps_wdata(ps_wdata), .ps_rdata(ps_rdata), .i_status(i_status),
        .o_thresh(o_thresh), .o_thresh_rel(o_thresh_rel),
        .o_alpha_shift(o_alpha_shift), .o_line_x(o_line_x),
        .o_dwell(o_dwell), .o_enable(o_enable)
    );

    integer errs = 0;

    task wr(input [4:0] a, input [31:0] d);
        begin
            @(posedge clk);
            ps_en <= 1; ps_we <= 1; ps_addr <= a; ps_wdata <= d;
            @(posedge clk);
            ps_en <= 0; ps_we <= 0;
        end
    endtask

    task rd_check(input [4:0] a, input [31:0] exp, input [255:0] name);
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
        rd_check(5'h00, 32'd70,      "THRESH reset = 70");
        rd_check(5'h04, 32'd15,      "THRESH_REL reset = 15");
        rd_check(5'h08, 32'd5,       "ALPHA_SHIFT reset = 5");
        rd_check(5'h0C, 32'd640,     "LINE_X reset = 640");
        rd_check(5'h10, 32'd90,      "DWELL reset = 90");
        rd_check(5'h14, 32'd0,       "ENABLE reset = 0");

        // 2) 写后读回 + 位宽截断
        wr(5'h00, 32'd88);   rd_check(5'h00, 32'd88, "THRESH write/read 88");
        wr(5'h04, 32'd20);   rd_check(5'h04, 32'd20, "THRESH_REL write/read 20");
        wr(5'h08, 32'h1F);   rd_check(5'h08, 32'd31, "ALPHA_SHIFT write 31");
        wr(5'h0C, 32'h2000 + 32'd500); rd_check(5'h0C, 32'd500, "LINE_X 13bit 写入应截断为 11bit=500");
        wr(5'h10, 32'd60);   rd_check(5'h10, 32'd60, "DWELL write/read 60");
        wr(5'h14, 32'd1);    rd_check(5'h14, 32'd1,  "ENABLE write/read 1");

        // 3) STATUS 只读
        wr(5'h18, 32'h12345678);
        rd_check(5'h18, 32'hDEADBEEF, "STATUS 写应被忽略，读回 i_status");

        // 4) 参数输出即时生效
        check(o_thresh === 16'd88, "o_thresh 应随写立即更新");
        check(o_line_x === 11'd500, "o_line_x 应随写立即更新");
        check(o_enable === 1'b1, "o_enable 应随写立即更新");

        if (errs == 0) $display("=== PASS：regs 仿真全部通过 ===");
        else           $display("=== FAIL：%0d 项未通过 ===", errs);
        $finish;
    end

    initial begin
        #100_000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule
