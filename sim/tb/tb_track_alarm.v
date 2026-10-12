`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_track_alarm —— track + alarm 联合自检仿真台
//
// 场景（大像素域，LINE_X=90，DWELL=4，MISSED_MAX=2）：
//   目标 A：cx 从 45 出发，每帧右移 15 —— 第 4 帧 cx=90 跨过警戒线 → 越界告警 1 次
//   目标 B：停在 cx=150 —— 第 4 帧 dwell=4 → 停留告警 1 次；第 6 帧起消失
//   第 9 帧 B 重新出现 —— 旧轨迹已老化删除，应分配**新 id**
//   同帧多目标在同一 frame_tick 前连发（A 先 B 后，输出顺序与输入一致）
//
// 自检项：
//   1) id 跨帧持续：A/B 第 1 帧的 id 在第 2~5 帧保持不变，dwell 单调递增；
//   2) type=1 越界告警恰好 1 次且 id==A；
//   3) type=2 停留告警恰好 1 次且 id==B；
//   4) B 消失后（第 6~8 帧）每帧只剩 A；
//   5) 第 9 帧 B 重现拿到新 id（轨迹老化机制生效）。
//
// 运行（Icarus）：iverilog -g2005 -o sim_track src/rtl/track.v src/rtl/alarm.v sim/tb/tb_track_alarm.v && vvp sim_track
// 运行（Vivado）：python build/scripts/run_sim.py --top tb_track_alarm
// -----------------------------------------------------------------------------
module tb_track_alarm;

    parameter integer LINE_X     = 90;
    parameter integer DWELL      = 4;
    parameter integer MISSED_MAX = 2;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    // ---- track 输入 ----
    reg         t_valid = 0;
    reg  [7:0]  t_id = 0;
    reg  [15:0] t_x1 = 0, t_y1 = 0, t_x2 = 0, t_y2 = 0;
    reg         t_last = 0;
    reg         frame_tick = 0;

    // ---- track ↔ alarm ----
    wire        k_valid, k_last;
    wire [7:0]  k_id;
    wire [15:0] k_x1, k_y1, k_x2, k_y2, k_dwell;

    // ---- alarm 输出 ----
    wire        a_valid;
    wire [7:0]  a_id;
    wire [1:0]  a_type;
    wire [15:0] a_cx;

    track #(.MISSED_MAX(MISSED_MAX)) u_track (
        .clk(clk), .rst_n(rst_n),
        .t_valid(t_valid), .t_id(t_id),
        .t_x1(t_x1), .t_y1(t_y1), .t_x2(t_x2), .t_y2(t_y2), .t_last(t_last),
        .frame_tick(frame_tick),
        .o_valid(k_valid), .o_id(k_id),
        .o_x1(k_x1), .o_y1(k_y1), .o_x2(k_x2), .o_y2(k_y2),
        .o_dwell(k_dwell), .o_last(k_last)
    );

    alarm u_alarm (
        .clk(clk), .rst_n(rst_n),
        .LINE_X(LINE_X[15:0]), .DWELL(DWELL[15:0]),
        .t_valid(k_valid), .t_id(k_id),
        .t_x1(k_x1), .t_y1(k_y1), .t_x2(k_x2), .t_y2(k_y2), .t_dwell(k_dwell),
        .a_valid(a_valid), .a_id(a_id), .a_type(a_type), .a_cx(a_cx)
    );

    // ---------------- 激励与采集 ----------------
    integer f, errs = 0;
    integer n_out;                 // 本帧已收跟踪输出数
    integer oid [0:15];
    integer odw [0:15];
    integer n_alarm = 0;
    integer a_id_c [0:7];
    integer a_ty  [0:7];

    always @(posedge clk) begin
        if (rst_n) begin
            if (k_valid && n_out < 16) begin
                oid[n_out] = k_id;
                odw[n_out] = k_dwell;
                n_out = n_out + 1;
                $display("[f%0d] track id=%0d x=%0d..%0d dwell=%0d%s",
                         f, k_id, k_x1, k_x2, k_dwell, k_last ? " (last)" : "");
            end
            if (a_valid && n_alarm < 8) begin
                a_id_c[n_alarm] = a_id;
                a_ty[n_alarm]   = a_type;
                n_alarm = n_alarm + 1;
                $display("[f%0d] ALARM type=%0d id=%0d cx=%0d", f, a_type, a_id, a_cx);
            end
        end
    end

    task send_target(input integer x1, input integer y1,
                     input integer x2, input integer y2);
        begin
            @(posedge clk);
            t_valid <= 1'b1;
            t_x1 <= x1[15:0]; t_y1 <= y1[15:0];
            t_x2 <= x2[15:0]; t_y2 <= y2[15:0];
            t_last <= 1'b1;
        end
    endtask

    task end_frame;
        begin
            @(posedge clk);
            t_valid <= 1'b0; t_last <= 1'b0;
            @(posedge clk);
            frame_tick <= 1'b1;
            @(posedge clk);
            frame_tick <= 1'b0;
            repeat (20) @(posedge clk);   // 输出流与告警都在这段时间发出
        end
    endtask

    task check(input integer cond, input [255:0] msg);
        begin
            if (!cond) begin
                errs = errs + 1;
                $display("FAIL: %0s", msg);
            end
        end
    endtask

    integer id_a, id_b, id_b2, i, fc, fd;

    initial begin
        n_out = 0;
        #12 rst_n = 1;

        // ===== 帧 1：A(cx=45) + B(cx=150) 首次出现 =====
        f = 1;
        send_target(30, 20, 60, 49);      // A: cx=45
        send_target(135, 80, 165, 109);   // B: cx=150
        end_frame;
        check(n_out == 2, "frame1 应输出 2 个跟踪目标");
        if (n_out == 2) begin
            id_a = oid[0]; id_b = oid[1];
            check(id_a != id_b, "A/B 的 id 应不同");
            check(odw[0] == 1 && odw[1] == 1, "frame1 两目标 dwell 都应为 1");
        end

        // ===== 帧 2~5：A 右移（cx=45+15*(f-1)），B 不动 =====
        for (f = 2; f <= 5; f = f + 1) begin
            n_out = 0;
            send_target(30 + 15*(f-1), 20, 60 + 15*(f-1), 49);
            send_target(135, 80, 165, 109);
            end_frame;
            check(n_out == 2, "frame2-5 每帧应输出 2 个目标");
            if (n_out == 2) begin
                check(oid[0] == id_a, "A 的 id 应跨帧持续");
                check(oid[1] == id_b, "B 的 id 应跨帧持续");
                check(odw[0] == f, "A 的 dwell 应等于已出现帧数");
            end
        end

        // ===== 帧 6~8：B 消失（轨迹老化），每帧只剩 A =====
        for (f = 6; f <= 8; f = f + 1) begin
            n_out = 0;
            send_target(30 + 15*(f-1), 20, 60 + 15*(f-1), 49);
            end_frame;
            check(n_out == 1, "B 消失后每帧应只剩 A");
            if (n_out == 1)
                check(oid[0] == id_a, "A 的 id 仍应持续");
        end

        // ===== 帧 9：B 重新出现 → 旧轨迹已删，应拿新 id =====
        f = 9;
        n_out = 0;
        send_target(30 + 15*8, 20, 60 + 15*8, 49);
        send_target(135, 80, 165, 109);
        end_frame;
        check(n_out == 2, "frame9 应输出 2 个目标");
        if (n_out == 2) begin
            check(oid[0] == id_a, "A 的 id 仍应持续");
            id_b2 = oid[1];
            check(id_b2 != id_b, "B 重现应分配新 id（旧轨迹已老化删除）");
        end

        // ===== 告警总账 =====
        fc = 0; fd = 0;
        for (i = 0; i < n_alarm; i = i + 1) begin
            if (a_ty[i] == 1) fc = fc + 1;
            if (a_ty[i] == 2) fd = fd + 1;
        end
        check(fc == 1, "type=1 越界告警应恰好 1 次");
        check(fd == 1, "type=2 停留告警应恰好 1 次（A 的 dwell=4 恰逢穿越帧，穿越优先）");
        begin : check_dwell_id
            integer hit_b;
            hit_b = 0;
            for (i = 0; i < n_alarm; i = i + 1)
                if (a_ty[i] == 2 && a_id_c[i] == id_b) hit_b = 1;
            check(hit_b == 1, "停留告警中应有一次属于 B");
        end

        if (errs == 0) $display("=== PASS：track+alarm 联合仿真全部通过 ===");
        else           $display("=== FAIL：%0d 项自检未通过 ===", errs);
        $finish;
    end

    initial begin
        #10_000_000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule
