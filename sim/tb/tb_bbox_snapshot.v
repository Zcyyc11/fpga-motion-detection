`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_bbox_snapshot —— 快照锁存 + 四段握手 CDC 自检（异步双钟）
//
// 场景：
//   S1 复位后副本全 0；首次 i_latch → 握手 → 副本与像素侧输入一致（含帧号同锁存）；
//   S2 连续两帧快照：第二帧锁存后副本更新为新值，BBOX_FRAME 与数据同帧；
//   S3 撕裂防护：锁存后立刻在像素侧改输入，副本读多拍保持旧帧值不变；
//   S4 alarm 帧级粘存（方案 A）：帧内脉冲 → 本帧快照 bit1=1 → 下一帧快照
//      回 0（清除窗口 128 拍，覆盖 frame_tick 后事件发出）；
//   S5 i_latch 连打（握手未完成）不丢同步性：副本仍与最后一次完成握手的
//      快照一致，无 x 态。
//
// 运行：iverilog -g2005 -o sim_snap src/rtl/bbox_snapshot.v sim/tb/tb_bbox_snapshot.v && vvp sim_snap
// -----------------------------------------------------------------------------
module tb_bbox_snapshot;

    // 像素钟 74.25MHz ≈ 13.47ns；AXI 钟 100MHz = 10ns（真异步）
    reg clk_px = 0, clk_axi = 0;
    always #6.74  clk_px  = ~clk_px;
    always #5     clk_axi = ~clk_axi;

    reg rst_px = 0, rst_axi = 0;

    reg  [15:0] in_x1 = 0, in_y1 = 0, in_x2 = 0, in_y2 = 0, in_cnt = 0;
    reg         in_valid = 0;
    reg  [15:0] in_frame = 0;
    reg  [7:0]  in_obj = 0;
    reg         in_alarm = 0;
    reg         latch = 0;

    wire [15:0] o_x1, o_y1, o_x2, o_y2, o_cnt, o_frame;
    wire        o_valid, o_b_valid, o_alarm;
    wire [7:0]  o_obj;

    bbox_snapshot #(.ALARM_CLEAR_DELAY(128)) dut (
        .clk_px(clk_px), .rst_n_px(rst_px),
        .i_x1(in_x1), .i_y1(in_y1), .i_x2(in_x2), .i_y2(in_y2), .i_cnt(in_cnt),
        .i_valid(in_valid), .i_frame_idx(in_frame), .i_obj_count(in_obj),
        .i_alarm_pulse(in_alarm), .i_latch(latch),
        .clk_axi(clk_axi), .rst_n_axi(rst_axi),
        .o_x1(o_x1), .o_y1(o_y1), .o_x2(o_x2), .o_y2(o_y2), .o_cnt(o_cnt),
        .o_valid(o_valid), .o_frame(o_frame), .o_obj_count(o_obj),
        .o_b_valid(o_b_valid), .o_alarm(o_alarm)
    );

    integer errs = 0;

    task check(input integer cond, input [255:0] msg);
        begin
            if (!cond) begin
                errs = errs + 1;
                $display("FAIL: %0s (x1=%0d y1=%0d x2=%0d y2=%0d cnt=%0d v=%b f=%0d obj=%0d bv=%b al=%b)",
                         msg, o_x1, o_y1, o_x2, o_y2, o_cnt, o_valid,
                         o_frame, o_obj, o_b_valid, o_alarm);
            end
        end
    endtask

    task do_latch;   // 1 拍 i_latch（像素钟）
        begin
            @(posedge clk_px); latch <= 1;
            @(posedge clk_px); latch <= 0;
        end
    endtask

    task wait_handshake_done;  // 等 AXI 侧副本更新完成（轮询帧号稳定 + 富余拍）
        begin
            repeat (20) @(posedge clk_axi);
        end
    endtask

    integer k;

    initial begin
        #20 rst_px = 1;  rst_axi = 1;
        repeat (10) @(posedge clk_axi);

        // ---------- S1 复位后副本全 0，首帧锁存 ----------
        check(o_x1 === 0 && o_frame === 0 && o_valid === 0,
              "S1 复位后副本应全 0");
        in_x1 = 100; in_y1 = 80; in_x2 = 139; in_y2 = 109;
        in_cnt = 1200; in_valid = 1; in_frame = 16'd1; in_obj = 8'd1;
        do_latch; wait_handshake_done;
        check(o_x1 === 100 && o_y1 === 80 && o_x2 === 139 && o_y2 === 109,
              "S1 首帧快照坐标");
        check(o_cnt === 1200 && o_valid === 1 && o_frame === 16'd1 && o_obj === 8'd1,
              "S1 首帧快照 cnt/valid/frame/obj（帧号同拍锁存）");

        // ---------- S2 第二帧 ----------
        in_x1 = 200; in_y1 = 60; in_x2 = 260; in_y2 = 150;
        in_cnt = 800; in_frame = 16'd2; in_obj = 8'd2;
        do_latch; wait_handshake_done;
        check(o_x1 === 200 && o_y2 === 150 && o_frame === 16'd2 && o_obj === 8'd2,
              "S2 第二帧快照整组更新");

        // ---------- S3 撕裂防护：锁存后立刻改输入，副本保持 ----------
        do_latch;                       // 第三帧锁存（输入仍是 S2 值+frame=2）
        @(posedge clk_px); #1;          // 避开采样拍（NBA 竞争），模拟"锁存后下一拍"
        in_x1 = 999; in_frame = 16'd999; in_cnt = 16'hFFFF;  // 锁存后立刻改
        repeat (30) @(posedge clk_axi); // AXI 侧连续多拍读
        check(o_x1 === 200 && o_frame === 16'd2 && o_cnt === 800,
              "S3 锁存后改输入，副本保持旧帧值不变（防撕裂）");
        // 再来一次正式锁存，新值才生效
        in_x1 = 300; in_frame = 16'd3;
        do_latch; wait_handshake_done;
        check(o_x1 === 300 && o_frame === 16'd3, "S3 下一帧锁存后新值生效");

        // ---------- S4 alarm 帧级粘存 ----------
        // 帧内第 5 帧无告警 → 快照 alarm=0
        in_frame = 16'd5; do_latch; wait_handshake_done;
        check(o_alarm === 0, "S4 无告警帧 bit1=0");
        // 第 6 帧中间来一拍 alarm 脉冲，随后帧边界锁存 → 本帧快照 bit1=1
        in_frame = 16'd6;
        @(posedge clk_px); in_alarm <= 1;
        @(posedge clk_px); in_alarm <= 0;
        repeat (10) @(posedge clk_px);
        do_latch; wait_handshake_done;
        check(o_alarm === 1 && o_frame === 16'd6,
              "S4 告警帧快照 bit1=1 且与帧号同锁存");
        // 第 7 帧无告警：清除窗口 128 拍已过 → 新快照 bit1=0
        repeat (150) @(posedge clk_px);   // 越过清除窗口
        in_frame = 16'd7; do_latch; wait_handshake_done;
        check(o_alarm === 0 && o_frame === 16'd7,
              "S4 下一帧快照 alarm 回 0（帧级粘存非跨帧）");

        // ---------- S5 i_latch 连打（握手未完成） ----------
        for (k = 0; k < 5; k = k + 1) begin
            latch <= 1; @(posedge clk_px); latch <= 0; @(posedge clk_px);
        end
        repeat (40) @(posedge clk_axi);
        check(o_x1 !== 16'hxxxx && o_frame !== 16'hxxxx,
              "S5 连打 latch 副本无 x 态");

        if (errs == 0)
            $display("=== PASS：bbox_snapshot 仿真全部通过（锁存+帧号同拍+握手CDC+粘存）===");
        else
            $display("=== FAIL：%0d 项未通过 ===", errs);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule
