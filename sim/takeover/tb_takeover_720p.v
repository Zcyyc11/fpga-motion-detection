// 720p source cadence (1650x750 cycles); 100MHz simulation clock scales wall time only.
`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_md_pipeline_full —— 顶层集成仿真台：元数据链 + I4 寄存器通路 + UART 回传
//
// 覆盖（对应 docs/line2_integration_guide.md 的接线，2026-10-12 顶层接入验收）：
//   S1  regs 瘦总线写/读回环（THRESH 80 → 读回 → 恢复 70）
//   S2  STATUS（0x18）位表：bit0=b_valid、15:8=obj_count、30:16=frame_idx
//   S3  BBOX 快照（0x1C~0x34）：坐标/VALID/FRAME 与 bbox 输出一致（防撕裂组）
//   S4  UART 回传：帧头 0x5A(OBJ_CNT=1) + 目标 0xA5（坐标=bbox，id 跨帧持续）
//       三包校验和逐包验证；事件包本场景应为 0（LINE_X/DWELL 未触发）
//   S5  ★运行时改阈值不重烧板：THRESH→1023 全帧无掩码 → UART 帧头 OBJ_CNT=0
//       （★零目标帧也有 tick 的直接证据）→ 恢复 70 检测恢复
//   S6  全程 uart_drop=0、无 X 态
//
// 运行（Icarus）：
//  iverilog -g2005 -o sim_full src/rtl/{md_pipeline,video_timing,pattern_gen,
//   downsample2x2,frame_buf,diff_stage,threshold,morph3x3,morph_open,bbox,
//   overlay,multi_bbox,track,alarm,uart_tx,regs,bbox_snapshot}.v
//   sim/tb/tb_md_pipeline_full.v && vvp sim_full
// -----------------------------------------------------------------------------
module tb_takeover_720p;
    parameter integer EVENTS = 0;

    // ---------------- 配置（与 tb_md_pipeline 同口径的小尺寸场景）----------------
    parameter integer H_ACTIVE = 1280;
    parameter integer V_ACTIVE = 720;
    parameter integer OBJ_W    = 40;
    parameter integer OBJ_H    = 30;
    parameter integer X0       = 40;
    parameter integer Y0       = 80;
    parameter integer DX       = 16;
    parameter integer THRESH_P = 70;
    parameter integer SHIFT_P  = 6;
    parameter integer MIN_CNT  = 64;
    parameter integer UART_DIV = 645;      // 位周期 = UART_DIV 个 clk（10ns）= 500ns

    localparam integer BIT_NS = UART_DIV * 10;   // 一个 UART 位的时间（ns）

    // ---------------- 时钟 / 复位 ----------------
    reg clk = 0, clk_axi = 0;
    always #5    clk     = ~clk;          // 100 MHz 像素钟（仿真口径）
    always #4.7  clk_axi = ~clk_axi;      // 100 MHz AXI 钟，相位错开模拟真异步
    reg rst_n = 0, rst_n_axi = 0;

    // ---------------- DUT ----------------
    wire        vde, alarm_evt, uart_txd, uart_drop;
    wire [15:0] vx, vy;
    wire [7:0]  vr, vg, vb;
    wire [15:0] b_x1, b_y1, b_x2, b_y2, b_cnt, frame_idx;
    wire        b_valid, m_valid, m_bit;
    wire [15:0] m_x, m_y;
    wire [7:0]  obj_count;
    wire        ps_en, ps_we;
    wire [5:0]  ps_addr;
    wire [31:0] ps_wdata, ps_rdata;

    md_pipeline #(
        .H_ACTIVE(H_ACTIVE), .V_ACTIVE(V_ACTIVE),
        .H_FP(110), .H_SYNC(40), .H_BP(220),
        .V_FP(5), .V_SYNC(5), .V_BP(20), .SYNC_POS(1),
        .OBJ_W(OBJ_W), .OBJ_H(OBJ_H), .X0(X0), .Y0(Y0), .DX(DX),
        .THRESH(THRESH_P), .SHIFT(SHIFT_P), .MODE_BG(0), .MIN_CNT(MIN_CNT),
        .INCLUDE_PS(1), .UART_BAUD_DIV(UART_DIV),
        .LINE_X_DEFAULT(640), .DWELL_DEFAULT(90)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .vde(vde), .vx(vx), .vy(vy), .vr(vr), .vg(vg), .vb(vb),
        .b_x1(b_x1), .b_y1(b_y1), .b_x2(b_x2), .b_y2(b_y2),
        .b_cnt(b_cnt), .b_valid(b_valid),
        .m_valid(m_valid), .m_x(m_x), .m_y(m_y), .m_bit(m_bit),
        .frame_idx(frame_idx),
        .clk_axi(clk_axi), .rst_n_axi(rst_n_axi),
        .ps_en(ps_en), .ps_we(ps_we), .ps_addr(ps_addr),
        .ps_wdata(ps_wdata), .ps_rdata(ps_rdata),
        .uart_txd(uart_txd), .uart_drop(uart_drop),
        .b_obj_count(obj_count), .alarm_evt(alarm_evt)
    );

    initial begin
        rst_n = 0; rst_n_axi = 0;
        repeat (20) @(posedge clk);
        rst_n = 1; rst_n_axi = 1;
    end

    // ---------------- 公共事件 ----------------
    wire frame_start = vde && (vx == 16'd0) && (vy == 16'd0);
    reg [15:0] vframe = 0;
    always @(posedge clk) if (frame_start) vframe <= vframe + 16'd1;

    reg  [15:0] mpy = 16'hFFFF;
    always @(posedge clk) if (m_valid) mpy <= m_y;
    wire        mk_boundary = m_valid && (m_y < mpy);   // 掩码流帧边界

    // ---------------- S1/S2/S3：regs 瘦总线主机（AXI 钟域）----------------
    reg        tb_en = 0, tb_we = 0;
    reg [5:0]  tb_addr = 6'd0;
    reg [31:0] tb_wdata = 32'd0;
    assign ps_en = tb_en; assign ps_we = tb_we;
    assign ps_addr = tb_addr; assign ps_wdata = tb_wdata;
    // ps_rdata 由 DUT 驱动（regs 寄存输出）

    task ps_write(input [5:0] addr, input [31:0] data);
        begin
            @(negedge clk_axi);
            tb_en = 1; tb_we = 1; tb_addr = addr; tb_wdata = data;
            @(negedge clk_axi);
            tb_en = 0; tb_we = 0;
        end
    endtask

    task ps_read(input [5:0] addr, output [31:0] data);
        begin
            @(negedge clk_axi);
            tb_en = 1; tb_we = 0; tb_addr = addr;
            @(negedge clk_axi);
            tb_en = 0;
            // regs 读寄存输出在 ps_en 脉冲当拍的 posedge 更新、下一 posedge
            // 清零 —— 必须在本 negedge（两 posedge 之间）采样
            data = ps_rdata;
        end
    endtask

    // ---------------- S4：UART 解码器（后台持续收包）----------------
    integer pk_hdr = 0, pk_tgt = 0, pk_evt = 0, pk_err = 0;
    integer hdr_frame = -1, hdr_cnt = -1, hdr_zero_seen = 0, hdr_two_seen = 0;
    integer tgt_frame = -1, tgt_id = -1;
    integer tgt_x1 = -1, tgt_y1 = -1, tgt_x2 = -1, tgt_y2 = -1;
    integer id_seen [0:255];
    reg [7:0] byte_buf [0:15];

    task uart_rx_byte(output [7:0] data);
        integer b;
        begin
            @(negedge uart_txd);                 // 起始位下降沿
            #(BIT_NS * 3 / 2);                   // 第 0 数据位中心
            for (b = 0; b < 8; b = b + 1) begin
                data[b] = uart_txd;
                #(BIT_NS);
            end
            #(BIT_NS / 2);                       // 进入停止位
        end
    endtask

    // 校验和：字节 0..n-2 累加和低 8 位 == 字节 n-1
    task chk_sum(input integer n, output integer ok);
        integer k, s;
        begin
            s = 0;
            for (k = 0; k < n - 1; k = k + 1) s = s + byte_buf[k];
            ok = ((s & 8'hFF) == byte_buf[n-1]);
        end
    endtask

    reg [7:0] rb;
    integer   cks;
    integer   dbg = 0;
    initial forever begin
        uart_rx_byte(rb);
        if (dbg) $display("[RX] t=%0t magic=%02x", $time, rb);
        case (rb)
            8'h5A: begin                         // 帧头包：MAGIC,FRAME_L,FRAME_H,CNT,CHK
                byte_buf[0] = rb;
                uart_rx_byte(byte_buf[1]); uart_rx_byte(byte_buf[2]);
                uart_rx_byte(byte_buf[3]); uart_rx_byte(byte_buf[4]);
                chk_sum(5, cks);
                if (!cks) pk_err = pk_err + 1;
                else begin
                    pk_hdr = pk_hdr + 1;
                    hdr_frame = byte_buf[1] | (byte_buf[2] << 8);
                    hdr_cnt   = byte_buf[3];
                    if (hdr_cnt == 0) hdr_zero_seen = 1;
                    if (hdr_cnt == 2) hdr_two_seen = 1;
                end
            end
            8'hA5: begin                         // 目标包：14 字节
                byte_buf[0] = rb;
                for (integer j = 1; j < 14; j = j + 1) uart_rx_byte(byte_buf[j]);
                chk_sum(14, cks);
                if (!cks) pk_err = pk_err + 1;
                else begin
                    pk_tgt = pk_tgt + 1;
                    tgt_frame = byte_buf[1] | (byte_buf[2] << 8);
                    tgt_id    = byte_buf[3];
                    tgt_x1    = byte_buf[4] | (byte_buf[5] << 8);
                    tgt_y1    = byte_buf[6] | (byte_buf[7] << 8);
                    tgt_x2    = byte_buf[8] | (byte_buf[9] << 8);
                    tgt_y2    = byte_buf[10] | (byte_buf[11] << 8);
                    if (tgt_id < 256) id_seen[tgt_id] = id_seen[tgt_id] + 1;
                end
            end
            8'hC3: begin                         // 事件包：8 字节
                byte_buf[0] = rb;
                for (integer j = 1; j < 8; j = j + 1) uart_rx_byte(byte_buf[j]);
                chk_sum(8, cks);
                if (!cks) pk_err = pk_err + 1; else pk_evt = pk_evt + 1;
            end
            default: pk_err = pk_err + 1;        // 不认识的 MAGIC（字节流失步）
        endcase
    end

    // ---------------- 记分板 ----------------
    integer errs = 0;
    task check(input integer cond, input [255:0] msg);
        begin
            if (!cond) begin
                errs = errs + 1;
                $display("FAIL: %0s (t=%0t)", msg, $time);
            end else
                $display("PASS: %0s", msg);
        end
    endtask

    task wait_frames(input integer n);
        integer k;
        begin
            // 以 frame_tick（vsync 上升沿，每个视频帧 1 拍）计帧。
            // 注意：pattern 内容帧约每 2 个视频帧更新一次（30fps 内容），
            // 且 UART 有 1 帧滞后 —— 检查窗口必须留足余量。
            for (k = 0; k < n; k = k + 1) @(posedge dut.frame_tick);
        end
    endtask

    reg [31:0] rd;
    reg [31:0] rd_status;
    integer    ref_x1, ref_y1, ref_x2, ref_y2;
    reg        ref_v;

    initial begin
        wait (rst_n == 1'b1);
        for (integer z = 0; z < 256; z = z + 1) id_seen[z] = 0;
        if (EVENTS != 0) begin
            ps_write(6'h0C, 32'd55);
            ps_write(6'h10, 32'd3);
        end
        dbg = 1;                                 // 前 3 个包打印调试
        wait_frames(3);                          // 第 1 帧起有目标
        dbg = 0;

        // ---------- S1 寄存器写读回环 ----------
        ps_write(6'h00, 32'd80);
        ps_read(6'h00, rd);
        check(rd == 32'd80, "S1 THRESH 写 80 读回 80");
        ps_write(6'h00, 32'd70);                 // 恢复默认
        ps_read(6'h00, rd);
        check(rd == 32'd70, "S1 THRESH 恢复 70");

        // ---------- S2/S3 等检测稳定后读 STATUS 与 BBOX 快照 ----------
        // 场景说明：帧差模式下运动目标产生「前缘 + 后缘」两条边缘带，
        // multi_bbox 正确输出 2 个目标（bbox 是两带的全局并集框，cnt=2×120）。
        wait (b_valid === 1'b1);
        @(posedge clk);
        ref_x1 = b_x1; ref_y1 = b_y1; ref_x2 = b_x2; ref_y2 = b_y2; ref_v = b_valid;
        repeat (30) @(posedge clk_axi);          // 等快照握手 CDC 完成
        ps_read(6'h1C, rd); check(rd[15:0] === ref_x1[15:0], "S3 BBOX_X1 == bbox.x1");
        ps_read(6'h20, rd); check(rd[15:0] === ref_y1[15:0], "S3 BBOX_Y1 == bbox.y1");
        ps_read(6'h24, rd); check(rd[15:0] === ref_x2[15:0], "S3 BBOX_X2 == bbox.x2");
        ps_read(6'h28, rd); check(rd[15:0] === ref_y2[15:0], "S3 BBOX_Y2 == bbox.y2");
        ps_read(6'h30, rd); check(rd[0] === ref_v,           "S3 BBOX_VALID == bbox.valid");
        ps_read(6'h34, rd);
        check(rd[15:0] !== 16'd0, "S3 BBOX_FRAME 已随帧更新（非零）");
        ps_read(6'h18, rd_status);
        check(rd_status[0] === 1'b1,                "S2 STATUS bit0 = b_valid=1");
        check(rd_status[15:8] === 8'd2,             "S2 STATUS obj_count = 2（双边缘带）");
        check(rd_status[30:16] !== 15'd0,           "S2 STATUS frame_idx 非零");

        // ---------- S4 UART：帧头 + 目标包 ----------
        // 等足 10 个视频帧（≈5 个内容帧 + UART 1 帧滞后余量）
        wait_frames(10);
        check(pk_hdr >= 6,            "S4 收到 >=6 个帧头包（每视频帧 1 个）");
        check(pk_tgt >= 4,            "S4 收到 >=4 个目标包（每个内容帧 2 带）");
        check(pk_err == 0,            "S4 全部包校验和通过、无失步");
        check(hdr_two_seen == 1,      "S4 帧头出现过 OBJ_CNT=2（双边缘带）");
        check(id_seen[0] > 0 && id_seen[1] > 0,
                                      "S4 两条带各有跨帧持续 id（0/1），未撞号");
        check(tgt_x2 > tgt_x1 && tgt_y2 > tgt_y1, "S4 目标包坐标构成有效框");
        check(tgt_x2 < H_ACTIVE/2 && tgt_y2 < V_ACTIVE/2,
                                      "S4 目标包坐标在大像素域范围内");
        check((EVENTS != 0) || pk_evt == 0,            "S4 本场景无事件包（LINE_X/DWELL 未触发）");
        check(uart_drop === 1'b0,     "S6 全程无 FIFO 满丢包");
        check(obj_count === 8'd0 || obj_count === 8'd2,
                                      "S4 obj_count 端口 = 2（内容帧）/0（保持帧）");

        // ---------- S5 ★运行时改阈值：不重烧板，检测关断与恢复 ----------
        hdr_zero_seen = 0;                       // 清早期零目标帧记录，重证一次
        ps_write(6'h00, 32'd1023);               // 和域最大差 1020 < 1023 → 无掩码
        wait_frames(10);
        check(b_valid === 1'b0,       "S5 THRESH=1023 后 b_valid=0（检测关断）");
        check(obj_count === 8'd0,     "S5 obj_count = 0");
        check(hdr_zero_seen == 1,     "S5 ★检测关断后仍有帧头包（OBJ_CNT=0，零目标 tick 有效）");
        ps_read(6'h18, rd_status);
        check(rd_status[0] === 1'b0,  "S5 STATUS bit0 = 0");
        ps_write(6'h00, 32'd70);                 // 恢复
        wait_frames(6);
        check(b_valid === 1'b1,       "S5 THRESH=70 恢复后检测恢复");
        check(pk_err == 0,            "S5 全程 UART 无失步");

        // Test-only drain: last frame_tick has committed the final complete interval.
        // Leave new uncommitted inputs out of the compared interval, but log them.
        repeat (10) @(posedge clk);
        wait (dut.u_utx.state == 0 && dut.u_utx.ready == 0 && dut.u_utx.bits_left == 0);
        repeat (2 * UART_DIV) @(posedge clk);
        if (EVENTS != 0) check(pk_evt > 0, "LINE3 event scenario produced UART events");
        $display("LINE3_DRAIN_DONE");
        // ---------- 收尾 ----------
        if (errs == 0)
            $display("TAKEOVER_PASS strict integration probe");
        else
            $display("==== FAIL：tb_md_pipeline_full 共 %0d 项失败 ====", errs);
        $finish;
    end

    // 看门狗
    initial begin
        #600000000;   // 40ms 仿真时间兜底
        $display("==== FAIL：看门狗超时 ====");
        $finish;
    end

    line3_uart_probe #(.BIT_NS(BIT_NS)) probe (
        .clk(clk), .rst_n(rst_n), .tx(uart_txd), .tick(dut.frame_tick),
        .video_frame(frame_idx), .tv(dut.tk_valid), .tid(dut.tk_id),
        .x1(dut.tk_x1), .y1(dut.tk_y1), .x2(dut.tk_x2), .y2(dut.tk_y2),
        .ev(dut.al_valid), .eid(dut.al_id), .etype(dut.al_type), .cx(dut.al_cx),
        .drop(uart_drop));
    // Independent scene formula: source N compares object positions N-1 and N.
    // Before threshold changes, the two disjoint difference strips are exact.
    integer scene_track_checks=0, scene_snapshot_checks=0;
    integer expect_left, scene_fd;
    initial scene_fd=$fopen("scene_alignment.csv","w");
    always @(posedge clk) if(rst_n) begin
      if(dut.tk_valid && frame_idx>=3 && frame_idx<=8) begin
        expect_left=(X0+DX*(frame_idx-3))/2;
        if(dut.tk_x1!==expect_left && dut.tk_x1!==(expect_left+OBJ_W/2))
          $fatal(1,"FAIL source-frame track x1 fid=%0d x1=%0d",frame_idx,dut.tk_x1);
        if(dut.tk_x2!==dut.tk_x1+DX/2-1 || dut.tk_y1!==Y0/2 || dut.tk_y2!==(Y0+OBJ_H)/2-1)
          $fatal(1,"FAIL source-frame track bounds fid=%0d",frame_idx);
        $fwrite(scene_fd,"track,%0d,%0d,%0d,%0d\n",frame_idx,frame_idx-1,dut.tk_id,dut.tk_x1);
        scene_track_checks=scene_track_checks+1;
      end
      if(dut.snap_latch && frame_idx>=4 && frame_idx<=8) begin
        expect_left=(X0+DX*(frame_idx-4))/2;
        if(b_x1!==expect_left || obj_count!==2 || b_valid!==1)
          $fatal(1,"FAIL source-frame overlay fid=%0d x1=%0d expected=%0d",frame_idx,b_x1,expect_left);
        $fwrite(scene_fd,"snapshot,%0d,%0d,%0d,%0d\n",frame_idx,frame_idx-2,obj_count,b_x1);
        scene_snapshot_checks=scene_snapshot_checks+1;
      end
    end
    final begin
      if(scene_track_checks!=12 || scene_snapshot_checks!=5)
        $error("FAIL source-frame coverage track=%0d snapshot=%0d",scene_track_checks,scene_snapshot_checks);
      else $display("SCENE_ALIGNMENT_PASS track12 snapshot5 source-formula fixed-delay");
    end
endmodule



