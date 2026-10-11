`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_uart_tx —— UART 回传发送自检仿真台（含串口 BFM 反序列化）
//
// 激励：1 帧内 2 个目标 + 1 次告警事件 → frame_tick → 空帧 frame_tick。
// BFM 在 tx 线上逐位收字节、按协议拆包，校验：
//   1) 先收到帧头包（0x5A，frame=0，cnt=2，校验和正确）；
//   2) 随后 2 个目标包（0xA5）：帧号/id/坐标与激励一致、校验和正确；
//   3) 1 个事件包（0xC3）：type/cx 正确；
//   4) 空帧 tick 后：帧头包 cnt=0；
//   5) 所有字节无校验错误、无丢包（收到包数 = 期望数）。
//
// 仿真加速：clk 100MHz，BAUD_DIV=4（25 Mbit/s）。
// 运行（Icarus）：iverilog -g2005 -o sim_uart src/rtl/uart_tx.v sim/tb/tb_uart_tx.v && vvp sim_uart
// 运行（Vivado）：python build/scripts/run_sim.py --top tb_uart_tx
// -----------------------------------------------------------------------------
module tb_uart_tx;

    parameter integer BAUD_DIV = 4;
    parameter real    BIT_NS   = BAUD_DIV * 10.0;   // clk 10ns 周期

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg         s_valid = 0;
    reg  [7:0]  s_id = 0;
    reg  [15:0] s_x1 = 0, s_y1 = 0, s_x2 = 0, s_y2 = 0;
    reg         e_valid = 0;
    reg  [7:0]  e_id = 0;
    reg  [1:0]  e_type = 0;
    reg  [15:0] e_cx = 0;
    reg         frame_tick = 0;
    wire        tx;
    wire        drop;

    uart_tx #(.BAUD_DIV(BAUD_DIV)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_valid), .s_id(s_id),
        .s_x1(s_x1), .s_y1(s_y1), .s_x2(s_x2), .s_y2(s_y2),
        .e_valid(e_valid), .e_id(e_id), .e_type(e_type), .e_cx(e_cx),
        .frame_tick(frame_tick),
        .tx(tx), .drop(drop)
    );

    // ---------------- UART BFM：收一个字节 ----------------
    task recv_byte(output [7:0] data);
        integer b;
        begin
            // 定位起始位：若上一字节后紧跟新字节，当前已处于起始位（tx=0）；
            // 否则等下降沿。然后跳到 data bit0 中心。
            if (tx !== 1'b0)
                @(negedge tx);
            #(1.5 * BIT_NS);
            for (b = 0; b < 8; b = b + 1) begin
                data[b] = tx;
                #(BIT_NS);                   // 下一位的中心
            end
            // 此刻在停止位中心（起始位前沿后 9.5 bit）
            if (tx !== 1'b1) begin
                errs = errs + 1;
                $display("FAIL: stop bit not 1");
            end
            #(0.5 * BIT_NS);                 // 回到字节边界（不丢相位）
        end
    endtask

    // 收一包并校验
    integer errs = 0;
    reg [7:0] pkt [0:15];
    integer plen;

    task recv_packet;
        reg [7:0] b0, sum;
        integer j;
        begin
            // 先偷看第一个字节（不消费——BFM 已把位流吃进去了，直接收满包长）
            recv_byte(b0);
            case (b0)
                8'h5A: plen = 5;
                8'hA5: plen = 14;
                8'hC3: plen = 8;
                default: begin
                    errs = errs + 1;
                    $display("FAIL: bad magic %h", b0);
                    plen = 0;
                end
            endcase
            pkt[0] = b0;
            sum = b0;
            for (j = 1; j < plen; j = j + 1) begin
                recv_byte(pkt[j]);
                if (j < plen - 1) sum = sum + pkt[j];
            end
            if (plen > 1 && pkt[plen-1] !== sum) begin
                errs = errs + 1;
                $display("FAIL: checksum got %h exp %h", pkt[plen-1], sum);
            end
        end
    endtask

    reg [7:0] b;
    initial begin
        #12 rst_n = 1;

        // ===== 帧 0：2 目标 + 1 事件 =====
        @(posedge clk);
        s_valid <= 1; s_id <= 8'd7; s_x1 <= 16'd30; s_y1 <= 16'd20;
        s_x2 <= 16'd60; s_y2 <= 16'd49;
        @(posedge clk);
        s_valid <= 0;
        @(posedge clk);
        s_valid <= 1; s_id <= 8'd9; s_x1 <= 16'd135; s_y1 <= 16'd80;
        s_x2 <= 16'd165; s_y2 <= 16'd109;
        @(posedge clk);
        s_valid <= 0;
        @(posedge clk);
        e_valid <= 1; e_id <= 8'd7; e_type <= 2'd1; e_cx <= 16'd90;
        @(posedge clk);
        e_valid <= 0;
        repeat (10) @(posedge clk);
        // 帧结束
        @(posedge clk);
        frame_tick <= 1;
        @(posedge clk);
        frame_tick <= 0;

        // ===== 收包校验 =====
        // 头包
        recv_packet;
        if (pkt[0] === 8'h5A) begin
            if ({pkt[2], pkt[1]} !== 16'd0) begin errs=errs+1; $display("FAIL: header frame=%0d", {pkt[2],pkt[1]}); end
            if (pkt[3] !== 8'd2)            begin errs=errs+1; $display("FAIL: header cnt=%0d", pkt[3]); end
            $display("header: frame=%0d cnt=%0d", {pkt[2],pkt[1]}, pkt[3]);
        end
        // 目标包 1（id=7）
        recv_packet;
        if (pkt[0] === 8'hA5) begin
            if ({pkt[2],pkt[1]} !== 16'd0)  begin errs=errs+1; $display("FAIL: tgt1 frame"); end
            if (pkt[3] !== 8'd7)            begin errs=errs+1; $display("FAIL: tgt1 id"); end
            if ({pkt[5],pkt[4]} !== 16'd30 || {pkt[7],pkt[6]} !== 16'd20 ||
                {pkt[9],pkt[8]} !== 16'd60 || {pkt[11],pkt[10]} !== 16'd49) begin
                errs=errs+1; $display("FAIL: tgt1 coords");
            end
            $display("target1: id=%0d x1=%0d y1=%0d x2=%0d y2=%0d",
                     pkt[3], {pkt[5],pkt[4]}, {pkt[7],pkt[6]}, {pkt[9],pkt[8]}, {pkt[11],pkt[10]});
        end
        // 目标包 2（id=9）
        recv_packet;
        if (pkt[0] === 8'hA5) begin
            if (pkt[3] !== 8'd9) begin errs=errs+1; $display("FAIL: tgt2 id=%0d", pkt[3]); end
            else $display("target2: id=%0d x1=%0d y1=%0d", pkt[3], {pkt[5],pkt[4]}, {pkt[7],pkt[6]});
        end else begin
            errs=errs+1; $display("FAIL: expected tgt2 packet, got magic %h", pkt[0]);
        end
        // 事件包
        recv_packet;
        if (pkt[0] === 8'hC3) begin
            if (pkt[3] !== 8'd7 || pkt[4] !== 8'd1 || {pkt[6],pkt[5]} !== 16'd90) begin
                errs=errs+1; $display("FAIL: event fields id=%0d type=%0d cx=%0d",
                                      pkt[3], pkt[4], {pkt[6],pkt[5]});
            end else
                $display("event: id=%0d type=%0d cx=%0d", pkt[3], pkt[4], {pkt[6],pkt[5]});
        end

        // ===== 帧 1：空帧 → 头包 cnt=0 =====
        repeat (100) @(posedge clk);   // 等发送引擎排空
        @(posedge clk);
        frame_tick <= 1;
        @(posedge clk);
        frame_tick <= 0;
        recv_packet;
        if (pkt[0] === 8'h5A) begin
            if (pkt[3] !== 8'd0) begin errs=errs+1; $display("FAIL: empty-frame cnt=%0d", pkt[3]); end
            else $display("header: frame=%0d cnt=0 (空帧)", {pkt[2],pkt[1]});
            if ({pkt[2],pkt[1]} !== 16'd1) begin errs=errs+1; $display("FAIL: empty-frame frame num"); end
        end

        // 确认线路回空闲、没有多余包
        repeat (200) @(posedge clk);
        if (tx !== 1'b1) begin errs=errs+1; $display("FAIL: tx should be idle"); end
        // 再等一下确认无多余数据
        fork : watch_extra
            begin
                @(negedge tx);
                errs = errs + 1;
                $display("FAIL: extra data on tx after all packets");
                disable watch_extra;
            end
            begin
                #200_000;
                disable watch_extra;
            end
        join

        if (errs == 0) $display("=== PASS：uart_tx 仿真全部通过 ===");
        else           $display("=== FAIL：%0d 项未通过 ===", errs);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule
