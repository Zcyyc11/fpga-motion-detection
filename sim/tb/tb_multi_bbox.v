`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_multi_bbox —— 多目标连通域模块的自检仿真台
//
// 线二第一周验收目标：**波形里出现两个框而不是一个**。
//
// 激励：直接喂掩码流（大像素域 320×180），不经过前面的流水线 ——
//   本台只验「游程 + 并查集」这一级的功能，输入即真值，排除上游干扰。
//   画面里放两个互不相连的矩形（第 2 帧起）：
//     目标 A：x 20..59,  y 20..49   （40×30 = 1200 大像素）
//     目标 B：x 100..139, y 80..109 （40×30 = 1200 大像素）
//   两框水平间隔 40 个大像素，垂直也错开，任何单游程合并都不该把它们连起来。
//
// 自检项（不通过直接 $fatal，日志里也有 PASS/FAIL 汇总）：
//   1) 第 1 帧（只有一个目标 A）输出 1 个目标，坐标 = A；
//   2) 第 2 帧起输出 2 个目标，坐标分别为 A、B（允许输出顺序互换）；
//   3) 计数 cnt = 1200；
//   4) o_last 在第 2 个目标上为 1。
//
// 运行（Icarus）  ：iverilog -g2005 -o sim_multi src/rtl/multi_bbox.v sim/tb/tb_multi_bbox.v && vvp sim_multi
// 运行（Vivado）  ：python build/scripts/run_sim.py --top tb_multi_bbox
// -----------------------------------------------------------------------------
module tb_multi_bbox;

    // ---------------- 图像与目标参数 ----------------
    parameter integer BW     = 320;     // 大像素域宽
    parameter integer BH     = 180;     // 大像素域高
    parameter integer A_X1   = 20;
    parameter integer A_X2   = 59;
    parameter integer A_Y1   = 20;
    parameter integer A_Y2   = 49;
    parameter integer B_X1   = 100;
    parameter integer B_X2   = 139;
    parameter integer B_Y1   = 80;
    parameter integer B_Y2   = 109;
    parameter integer MIN_CNT = 64;
    parameter integer FRAMES = 3;       // 跑 3 帧：第 1 帧单目标，之后双目标

    // ---------------- 时钟 / 复位 ----------------
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    // ---------------- DUT ----------------
    reg         in_valid;
    reg  [15:0] in_x, in_y;
    reg         in_mask;
    wire        o_valid, o_last;
    wire [15:0] o_x1, o_y1, o_x2, o_y2, o_cnt;
    wire [7:0]  o_id;

    multi_bbox #(.MIN_CNT(MIN_CNT)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_x(in_x), .in_y(in_y), .in_mask(in_mask),
        .o_valid(o_valid), .o_x1(o_x1), .o_y1(o_y1), .o_x2(o_x2), .o_y2(o_y2),
        .o_cnt(o_cnt), .o_id(o_id), .o_last(o_last)
    );

    // ---------------- 激励与采集 ----------------
    integer f, x, y;
    integer n_out;                       // 本帧已收目标数
    integer fx1 [0:15]; integer fy1 [0:15];
    integer fx2 [0:15]; integer fy2 [0:15];
    integer fcnt[0:15];
    integer errs;

    task collect_outputs;
        begin
            // 在激励推进的每个时钟沿后顺手采样（o_valid 每目标一拍）
            if (o_valid) begin
                if (n_out < 16) begin
                    fx1[n_out] = o_x1; fy1[n_out] = o_y1;
                    fx2[n_out] = o_x2; fy2[n_out] = o_y2;
                    fcnt[n_out] = o_cnt;
                end
                n_out = n_out + 1;
                $display("[frame %0d] target id=%0d  x1=%0d y1=%0d x2=%0d y2=%0d cnt=%0d%s",
                         f, o_id, o_x1, o_y1, o_x2, o_y2, o_cnt, o_last ? "  (last)" : "");
            end
        end
    endtask

    // 送一帧掩码流：目标A 全帧存在；目标B 仅 frame_idx >= 1 时存在
    task send_frame(input integer frame_idx);
        begin
            for (y = 0; y < BH; y = y + 1) begin
                for (x = 0; x < BW; x = x + 1) begin
                    @(posedge clk);
                    in_valid <= 1'b1;
                    in_x     <= x[15:0];
                    in_y     <= y[15:0];
                    in_mask  <= ((x >= A_X1) && (x <= A_X2) && (y >= A_Y1) && (y <= A_Y2))
                             || ((frame_idx >= 1) &&
                                 (x >= B_X1) && (x <= B_X2) && (y >= B_Y1) && (y <= B_Y2));
                    collect_outputs;
                end
            end
            @(posedge clk);
            in_valid <= 1'b0;   // 帧间空隙（模拟消隐），y 回绕判据依赖 in_y < prow，不受影响
            in_mask  <= 1'b0;
            repeat (8) begin
                @(posedge clk);
                collect_outputs;    // 结算与目标输出发生在帧边界后的几拍内
            end
        end
    endtask

    // ---------------- 自检 ----------------
    task check(input integer cond, input [127:0] msg);
        begin
            if (!cond) begin
                errs = errs + 1;
                $display("FAIL: %0s", msg);
            end
        end
    endtask

    integer j, t1x1, t1x2;
    initial begin
        in_valid = 0; in_x = 0; in_y = 0; in_mask = 0;
        n_out = 0; errs = 0;
        #12 rst_n = 1'b1;

        for (f = 0; f < FRAMES; f = f + 1) begin
            send_frame(f);
            // ---- 帧内自检 ----
            // 注意：send_frame(f) 期间收到的是第 f-1 帧的结果
            //（第 f-1 帧在第 f 帧的帧边界才结算）。所以：
            //   f==1 → 检验第 0 帧（单目标 A）
            //   f>=2 → 检验第 f-1 帧（双目标）
            if (f == 1) begin
                check(n_out == 1, "frame0 应只输出 1 个目标");
                if (n_out == 1) begin
                    check(fx1[0] == A_X1 && fy1[0] == A_Y1 && fx2[0] == A_X2 && fy2[0] == A_Y2,
                          "frame0 目标坐标应等于 A");
                    check(fcnt[0] == (A_X2-A_X1+1)*(A_Y2-A_Y1+1), "frame0 cnt 应为 1200");
                end
            end else if (f >= 2) begin
                check(n_out == 2, "frame1+ 应输出 2 个目标（波形里两个框）");
                if (n_out == 2) begin
                    // 顺序不保证：找到 A 在哪个槽位
                    if (fx1[0] == A_X1) j = 0; else j = 1;
                    t1x1 = fx1[j]; t1x2 = fx2[j];
                    check(t1x1 == A_X1 && fy1[j] == A_Y1 && t1x2 == A_X2 && fy2[j] == A_Y2,
                          "目标 A 坐标不符");
                    check(fx1[1-j] == B_X1 && fy1[1-j] == B_Y1 &&
                          fx2[1-j] == B_X2 && fy2[1-j] == B_Y2,
                          "目标 B 坐标不符");
                    check(fcnt[j] == 1200 && fcnt[1-j] == 1200, "两个目标 cnt 都应为 1200");
                end
            end
            n_out = 0;
        end

        // 冲刷帧：触发最后一帧的结算，使最后一帧结果可见
        send_frame(FRAMES);
        check(n_out == 2, "flush: last frame should output 2 targets");
        if (n_out == 2) begin
            if (fx1[0] == A_X1) j = 0; else j = 1;
            check(fx1[j] == A_X1 && fy1[j] == A_Y1 && fx2[j] == A_X2 && fy2[j] == A_Y2,
                  "flush: target A coords");
            check(fx1[1-j] == B_X1 && fy1[1-j] == B_Y1 &&
                  fx2[1-j] == B_X2 && fy2[1-j] == B_Y2,
                  "flush: target B coords");
            check(fcnt[j] == 1200 && fcnt[1-j] == 1200, "flush: cnt 1200 both");
        end

        if (errs == 0) $display("=== PASS：多目标连通域仿真全部通过（两个框）===");
        else           $display("=== FAIL：%0d 项自检未通过 ===", errs);
        $finish;
    end

    // 看门狗
    initial begin
        #50_000_000;
        $display("FAIL: 仿真超时");
        $finish;
    end

endmodule
