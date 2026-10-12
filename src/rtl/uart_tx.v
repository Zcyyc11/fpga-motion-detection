`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// uart_tx —— 线二任务：板端回传发送（协议打包 + UART 串行化）
//
// 协议：docs/protocol_and_interface_requirements.md §4（v0.1 草案 + v0.2 增补），小端，字节累加和校验：
//   帧头包 0x5A（5B）：MAGIC, FRAME_L, FRAME_H, OBJ_CNT, CHK
//   目标包 0xA5（14B）：MAGIC, FRAME_L, FRAME_H, ID, X1L,X1H,Y1L,Y1H,
//                       X2L,X2H,Y2L,Y2H, FLAGS, CHK
//   事件包 0xC3（8B） ：MAGIC, FRAME_L, FRAME_H, ID, TYPE, CX_L, CX_H, CHK
//     （v0.2 增补：告警事件独立成包，type 1=越界 2=停留；接收端按 MAGIC 分流）
//
// 数据流与一帧滞后（与 bbox.v 同口径）：
//   两个 frame_tick 之间的目标/事件属于"当前帧"（帧号 = tick 后的计数值）；
//   目标/事件包随到随入 FIFO；**下一个 frame_tick** 时才知道 OBJ_CNT，
//   于是先排队一个帧头包（帧号=刚结束那帧、计数=该帧目标数），再排 FIFO 内容。
//   PC 端看到的数据滞后一帧 —— 正常，与 bbox 帧滞后同口径。
//
// UART：1 起始位 + 8 数据（LSB first）+ 1 停止位，空闲 1。
//   BAUD_DIV = clk_hz / baud（100MHz/115200 ≈ 868；仿真传小值加速）。
//
// 资源：字节 FIFO 256 深（16 目标 × 14B + 事件若干 + 头包，绰绰有余）。
//   FIFO 满 → 丢弃并置 drop 标志（已粘存进 regs STATUS bit31，PS 写 STATUS 清除）。
// 单进程设计：打包、头包排队、发送引擎共用一个时序块，共享变量全部阻塞赋值。
// -----------------------------------------------------------------------------
module uart_tx #(
    parameter integer BAUD_DIV = 868
)(
    input  wire        clk,
    input  wire        rst_n,
    // 目标流输入（track 输出）
    input  wire        s_valid,
    input  wire [7:0]  s_id,
    input  wire [15:0] s_x1, s_y1, s_x2, s_y2,
    // 告警事件流输入（alarm 输出）
    input  wire        e_valid,
    input  wire [7:0]  e_id,
    input  wire [1:0]  e_type,
    input  wire [15:0] e_cx,
    // 帧边界（vsync，每帧 1 拍）
    input  wire        frame_tick,
    // UART 输出
    output reg         tx,
    output reg         drop            // FIFO 满导致丢包（粘到 STATUS 用）
);

    // ---------------- 帧计数与排队状态 ----------------
    reg [15:0] frame_num;      // 当前帧号（tick 后递增）
    reg [7:0]  obj_cnt;        // 当前帧已入队目标数
    reg        hdr_pending;    // 有帧头包待排队
    reg [15:0] hdr_frame;
    reg [7:0]  hdr_cnt;

    // ---------------- 字节 FIFO ----------------
    reg [7:0]  fifo [0:255];
    reg [8:0]  wptr, rptr;
    reg [8:0]  commit_ptr;   // 提交水位：帧头包排队后才放行发送（保证头包先于本帧目标包）
    wire       fifo_full  = (wptr[7:0] == rptr[7:0]) && (wptr[8] != rptr[8]);
    wire       fifo_empty = (wptr == rptr);

    // 头包字节小队列（固定 5 字节，阻塞区维护）
    reg [7:0]  hq [0:4];
    integer    hq_n;

    integer    k;
    reg [7:0]  c, db;
    reg        src_hdr;
    reg [9:0]  shifter;   // {stop, data[8], start}，用 10bit 移位
    reg [3:0]  bitidx;
    integer    baud_cnt;
    reg        busy;

    task push_byte(input [7:0] b);
        begin
            if (fifo_full) drop <= 1'b1;
            else begin
                fifo[wptr[7:0]] = b;
                wptr = wptr + 9'd1;
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_num <= 0; obj_cnt <= 0; hdr_pending <= 0;
            hdr_frame <= 0; hdr_cnt <= 0;
            wptr = 0; rptr = 0; commit_ptr = 0; hq_n = 0;
            tx <= 1'b1; drop <= 1'b0;
            busy = 1'b0; shifter = 10'h3FF; bitidx = 0; baud_cnt = 0;
        end else begin
            drop <= 1'b0;

            // ================= 打包区 =================
            if (frame_tick) begin
                hdr_frame <= frame_num;             // 刚结束那帧的帧号
                hdr_cnt   <= obj_cnt;
                hdr_pending <= 1'b1;
                frame_num <= frame_num + 16'd1;
                obj_cnt   <= 8'd0;
            end else begin
                if (s_valid) begin
                    // 目标包 0xA5
                    c = 8'hA5 + s_id + frame_num[7:0] + frame_num[15:8]
                             + s_x1[7:0] + s_x1[15:8] + s_y1[7:0] + s_y1[15:8]
                             + s_x2[7:0] + s_x2[15:8] + s_y2[7:0] + s_y2[15:8];
                    push_byte(8'hA5);
                    push_byte(frame_num[7:0]); push_byte(frame_num[15:8]);
                    push_byte(s_id);
                    push_byte(s_x1[7:0]); push_byte(s_x1[15:8]);
                    push_byte(s_y1[7:0]); push_byte(s_y1[15:8]);
                    push_byte(s_x2[7:0]); push_byte(s_x2[15:8]);
                    push_byte(s_y2[7:0]); push_byte(s_y2[15:8]);
                    push_byte(8'd0);
                    push_byte(c);
                    if (obj_cnt != 8'hFF) obj_cnt <= obj_cnt + 8'd1;
                end
                if (e_valid) begin
                    // 事件包 0xC3
                    c = 8'hC3 + e_id + frame_num[7:0] + frame_num[15:8]
                             + {6'd0, e_type} + e_cx[7:0] + e_cx[15:8];
                    push_byte(8'hC3);
                    push_byte(frame_num[7:0]); push_byte(frame_num[15:8]);
                    push_byte(e_id);
                    push_byte({6'd0, e_type});
                    push_byte(e_cx[7:0]); push_byte(e_cx[15:8]);
                    push_byte(c);
                end
            end

            // 帧头包排队（frame_tick 的次拍，等头包小队列空）
            if (hdr_pending && hq_n == 0) begin
                c = 8'h5A + hdr_frame[7:0] + hdr_frame[15:8] + hdr_cnt;
                hq[0] = 8'h5A; hq[1] = hdr_frame[7:0]; hq[2] = hdr_frame[15:8];
                hq[3] = hdr_cnt; hq[4] = c;
                hq_n = 5;
                hdr_pending <= 1'b0;
                commit_ptr = wptr;   // 放行：帧头已排队，本帧已入队字节可发
            end

            // ================= 发送引擎 =================
            if (!busy) begin
                if (hq_n > 0) begin
                    db = hq[0];
                    for (k = 0; k < 4; k = k + 1) hq[k] = hq[k+1];
                    hq_n = hq_n - 1;
                    busy = 1'b1;
                    shifter = {1'b1, db, 1'b0};
                    bitidx = 4'd0;
                    baud_cnt = 0;
                    tx <= 1'b0;                   // 起始位
                end else if (rptr != commit_ptr) begin
                    db = fifo[rptr[7:0]];
                    rptr = rptr + 9'd1;
                    busy = 1'b1;
                    shifter = {1'b1, db, 1'b0};
                    bitidx = 4'd0;
                    baud_cnt = 0;
                    tx <= 1'b0;
                end
                // 都没有：保持空闲 1
            end else begin
                baud_cnt = baud_cnt + 1;
                if (baud_cnt >= BAUD_DIV) begin
                    baud_cnt = 0;
                    if (bitidx == 4'd9) begin
                        busy = 1'b0;              // 停止位周期结束
                        tx <= 1'b1;
                    end else if (bitidx == 4'd8) begin
                        bitidx = 4'd9;
                        tx <= 1'b1;               // 进入停止位周期
                    end else begin
                        bitidx = bitidx + 4'd1;
                        tx <= shifter[1];         // 先按未移位的 shifter 取当前位
                        shifter = {1'b1, shifter[9:1]};
                    end
                end
            end
        end
    end

endmodule
