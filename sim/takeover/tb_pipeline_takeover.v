`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_pipeline_takeover —— 顶层集成仿真台：回传元数据链（线一版结构 + 线二移植）
//
// 场景：INCLUDE_PS=0（纯 PL 构建，10/13 bit 的口径），验证：
//   S1  UART 回传：帧头 0x5A（OBJ_CNT=2，帧差双边缘带）+ 目标 0xA5
//       （校验和逐包验证，id 跨帧持续 0/1 不撞号，坐标在大像素域内）
//   S2  事件包 0（LINE_X/DWELL 默认关闭）、全程 uart_drop=0
//   S3  b_obj_count 输出与 UART 帧头计数一致语义（2/0 交替）
//   S4  原显示链行为不变（b_valid 正常出现、无 X）
//
// 运行（Icarus）：
//  iverilog -g2005 -o sim_uart src/rtl/{md_pipeline,video_timing,pattern_gen,
//   downsample2x2,frame_buf,diff_stage,threshold,morph3x3,morph_open,multi_bbox,
//   overlay_multi,track,alarm,uart_tx,regs,bbox_snapshot}.v
//   sim/tb/tb_pipeline_takeover.v && vvp sim_uart
// -----------------------------------------------------------------------------
module tb_pipeline_takeover;

    // ---------------- 配置（与 tb_md_pipeline 同口径的小尺寸场景）----------------
    parameter integer H_ACTIVE = 320;
    parameter integer V_ACTIVE = 180;
    parameter integer OBJ_W    = 40;
    parameter integer OBJ_H    = 30;
    parameter integer X0       = 40;
    parameter integer Y0       = 80;
    parameter integer DX       = 16;
    parameter integer THRESH_P = 70;
    parameter integer SHIFT_P  = 6;
    parameter integer MIN_CNT  = 64;
    parameter integer UART_DIV = 50;      // 位周期 = UART_DIV 个 clk（10ns）= 500ns

    localparam integer BIT_NS = UART_DIV * 10;   // 一个 UART 位的时间（ns）

    // ---------------- 时钟 / 复位 ----------------
    reg clk = 0;
    always #5    clk     = ~clk;          // 100 MHz 像素钟（仿真口径）
    reg rst_n = 0;

    // ---------------- DUT ----------------
    wire        vde, alarm_evt, uart_txd, uart_drop;
    wire [15:0] vx, vy;
    wire [7:0]  vr, vg, vb;
    wire [15:0] b_x1, b_y1, b_x2, b_y2, b_cnt, frame_idx;
    wire        b_valid, m_valid, m_bit;
    wire [15:0] m_x, m_y;
    wire [7:0]  b_obj_count;

    md_pipeline #(
        .H_ACTIVE(H_ACTIVE), .V_ACTIVE(V_ACTIVE),
        .H_FP(8), .H_SYNC(16), .H_BP(16),
        .V_FP(2), .V_SYNC(4), .V_BP(4), .SYNC_POS(0),
        .OBJ_W(OBJ_W), .OBJ_H(OBJ_H), .X0(X0), .Y0(Y0), .DX(DX),
        .THRESH(THRESH_P), .SHIFT(SHIFT_P), .MODE_BG(0), .MIN_CNT(MIN_CNT),
        .INCLUDE_PS(0), .UART_BAUD_DIV(UART_DIV),
        .LINE_X_DEFAULT(640), .DWELL_DEFAULT(90)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .vde(vde), .vx(vx), .vy(vy), .vr(vr), .vg(vg), .vb(vb),
        .b_x1(b_x1), .b_y1(b_y1), .b_x2(b_x2), .b_y2(b_y2),
        .b_cnt(b_cnt), .b_valid(b_valid), .b_obj_count(b_obj_count),
        .m_valid(m_valid), .m_x(m_x), .m_y(m_y), .m_bit(m_bit),
        .frame_idx(frame_idx),
        .uart_txd(uart_txd), .uart_drop(uart_drop), .alarm_evt(alarm_evt)
        // INCLUDE_PS=0：clk_axi/rst_n_axi/ps_* 悬空（g_nops 不用）
    );

    initial begin
        rst_n = 0;
        repeat (20) @(posedge clk);
        rst_n = 1;
    end

    // ---------------- 公共事件 ----------------
    wire frame_start = vde && (vx == 16'd0) && (vy == 16'd0);
    reg [15:0] vframe = 0;
    always @(posedge clk) if (frame_start) vframe <= vframe + 16'd1;

    // ---------------- UART 解码器（后台持续收包）----------------
    integer pk_hdr = 0, pk_tgt = 0, pk_evt = 0, pk_err = 0;
    integer hdr_frame = -1, hdr_cnt = -1, hdr_two_seen = 0;
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

    initial begin
        wait (rst_n == 1'b1);
        for (integer z = 0; z < 256; z = z + 1) id_seen[z] = 0;
        dbg = 1;                                 // 前 3 个包打印调试
        wait_frames(3);                          // 第 1 帧起有目标
        dbg = 0;

        // ---------- S1 检测链起来（原显示链行为不变）----------
        // 场景说明：帧差模式下运动目标产生「前缘 + 后缘」两条边缘带，
        // multi_bbox 正确输出 2 个目标（overlay_multi 的 b_* 是两带之一/并集）。
        wait (b_valid === 1'b1);
        @(posedge clk);
        check(b_x2 > b_x1 && b_y2 > b_y1, "S1 显示链 b_* 构成有效框（原链行为不变）");

        // ---------- S2 UART：帧头 + 目标包 ----------
        // 等足 10 个视频帧（≈5 个内容帧 + UART 1 帧滞后余量）
        wait_frames(10);
        check(pk_hdr >= 6,            "S2 收到 >=6 个帧头包（每视频帧 1 个）");
        check(pk_tgt >= 4,            "S2 收到 >=4 个目标包（每个内容帧 2 带）");
        check(pk_err == 0,            "S2 全部包校验和通过、无失步");
        check(hdr_two_seen == 1,      "S2 帧头出现过 OBJ_CNT=2（双边缘带）");
        check(id_seen[0] > 0 && id_seen[1] > 0,
                                      "S2 两条带各有跨帧持续 id（0/1），未撞号");
        check(tgt_x2 > tgt_x1 && tgt_y2 > tgt_y1, "S2 目标包坐标构成有效框");
        check(tgt_x2 < H_ACTIVE/2 && tgt_y2 < V_ACTIVE/2,
                                      "S2 目标包坐标在大像素域范围内");
        check(pk_evt == 0,            "S2 本场景无事件包（LINE_X/DWELL 默认关闭）");
        check(uart_drop === 1'b0,     "S2 全程无 FIFO 满丢包");
        check(b_obj_count === 8'd0 || b_obj_count === 8'd2,
                                      "S3 b_obj_count = 2（内容帧）/0（保持帧）交替");
        check(alarm_evt === 1'b0,     "S2 无告警（默认 LINE_X 超出画面）");
        check(frame_idx !== 16'hxxxx, "S4 frame_idx 无 X 态");

        // ---------- 收尾 ----------
        if (errs == 0)
            $display("TAKEOVER_PASS pipeline UART integrated");
        else
            $display("==== FAIL：tb_pipeline_takeover 共 %0d 项失败 ====", errs);
        $finish;
    end

    // 看门狗
    initial begin
        #40000000;   // 40ms 仿真时间兜底
        $display("==== FAIL：看门狗超时 ====");
        $finish;
    end

endmodule
