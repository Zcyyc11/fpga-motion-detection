`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// track —— 线二任务：多目标跟踪（帧间匹配 + 持续 id + 停留计数）
//
// 在流水线里的位置：
//   multi_bbox（每目标一个框，I3 流）→ **track（本模块）** → alarm（越界/停留告警）
//   输入输出都是 I3 目标元数据流，接口冻结，不碰顶层。
//
// ★ 算法（PC 端 multi_track.py 的硬件等价物，够用版）：
//   - 每帧把输入目标攒成"当前帧列表"（最多 MAX_TRACK 个）；
//   - 帧边界（frame_tick，来自 vsync，**零目标帧也必须有 tick**，否则轨迹老化不了）
//     做一次贪心最近邻匹配：每个新目标找中心距离最近且 ≤ MATCH_DIST 的活轨迹，
//     一条轨迹一帧最多配一个目标；
//   - 配上的：更新包围盒，missed=0，seen_frames+1（= 停留帧数 dwell），id 不变；
//   - 没配上的目标：分配新 id（全局递增计数器，8bit 回绕）；
//   - 没配上的轨迹：missed+1，连续 MISSED_MAX 帧没出现就删除（id 不回收，
//     回绕前不会撞号 —— 8bit 回绕是已知取舍，报告里说明）。
//
// ★ 输出：本帧目标的**跟踪后**流（id 为跨帧持续 id + dwell 停留帧数），
//   在 frame_tick 后的若干拍内串行发出，与下一帧的目标输入互不占用。
//
// ★ 匹配只用加减比较（中心距），没有乘除 —— 综合友好。
//   IoU 匹配是后续升级项，接口不变，只改内部。
//
// ★ 综合修复（line1）：原 6 处循环以 integer 变量 tr_n / c_n 作循环上界
//   （Synth 8-3380 不可综合）。统一改为以常量 MAX_TRACK / MAX_TARGET 展开，
//   再用 `if (idx < tr_n/c_n)` 门控，逻辑语义与原动态上界完全一致。
// -----------------------------------------------------------------------------
module track #(
    parameter integer MAX_TRACK  = 16,   // 同时存在的轨迹数上限
    parameter integer MAX_TARGET = 16,   // 单帧输入目标数上限（与 multi_bbox 的 MAX_LABEL 对齐）
    parameter integer MATCH_DIST = 48,   // 中心距匹配门限（大像素域）
    parameter integer MISSED_MAX = 5     // 连续丢失多少帧后删轨迹
)(
    input  wire        clk,
    input  wire        rst_n,
    // I3 目标流输入（来自 multi_bbox：每目标一拍，o_last 标记本帧最后一个）
    input  wire        t_valid,
    input  wire [7:0]  t_id,          // 输入 id（检测序号），本模块忽略，输出自己的持续 id
    input  wire [15:0] t_x1, t_y1, t_x2, t_y2,
    input  wire        t_last,
    // 帧边界：每帧 1 拍（来自 vsync 上升沿）。★ 零目标帧也必须给
    input  wire        frame_tick,
    // 跟踪后的目标流输出（frame_tick 之后发出）
    output reg         o_valid,
    output reg  [7:0]  o_id,          // ★ 跨帧持续 id
    output reg [15:0] o_x1, o_y1, o_x2, o_y2,
    output reg [15:0] o_dwell,       // 连续出现帧数（停留计数的直接依据）
    output reg         o_last
);

    // ---------------- 轨迹表 ----------------
    reg        tr_act  [0:MAX_TRACK-1]; // active
    reg [7:0]  tr_id   [0:MAX_TRACK-1];
    reg [15:0] tr_x1 [0:MAX_TRACK-1], tr_y1 [0:MAX_TRACK-1];
    reg [15:0] tr_x2 [0:MAX_TRACK-1], tr_y2 [0:MAX_TRACK-1];
    reg [15:0] tr_seen[0:MAX_TRACK-1];   // 连续出现帧数（dwell）
    reg [15:0] tr_miss[0:MAX_TRACK-1];
    integer    tr_n;                     // 当前轨迹数
    reg        tr_m   [0:MAX_TRACK-1];   // 本帧已被匹配标记（帧边界结算用，blocking 区）

    reg [7:0]  id_next;                  // 新 id 分配计数器

    // ---------------- 当前帧目标积累 ----------------
    reg [15:0] c_x1 [0:MAX_TARGET-1], c_y1 [0:MAX_TARGET-1];
    reg [15:0] c_x2 [0:MAX_TARGET-1], c_y2 [0:MAX_TARGET-1];
    integer    c_n;
    // 匹配结果：目标 k → 轨迹号（0xFF = 新建）
    reg [7:0]  c_hit [0:MAX_TARGET-1];

    // ---------------- 结算输出 ----------------
    reg [7:0]  out_id  [0:MAX_TARGET-1];
    reg [15:0] out_x1 [0:MAX_TARGET-1], out_y1 [0:MAX_TARGET-1];
    reg [15:0] out_x2 [0:MAX_TARGET-1], out_y2 [0:MAX_TARGET-1];
    reg [15:0] out_dw  [0:MAX_TARGET-1];
    integer    out_n, out_k;

    integer i, k, best, bd, dx, dy, dcx, dcy, t_cx, t_cy;
    reg [15:0] cx, cy;
    reg matched;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tr_n = 0; id_next = 8'd0; c_n = 0; out_n = 0; out_k = 0;
            o_valid <= 0; o_id <= 0; o_x1 <= 0; o_y1 <= 0; o_x2 <= 0; o_y2 <= 0;
            o_dwell <= 0; o_last <= 0;
            for (i = 0; i < MAX_TRACK; i = i + 1) begin
                tr_act[i] = 1'b0; tr_id[i] = 8'd0; tr_seen[i] = 0; tr_miss[i] = 0;
                tr_x1[i]=0; tr_y1[i]=0; tr_x2[i]=0; tr_y2[i]=0;
            end
        end else begin
            o_valid <= 1'b0;
            o_last  <= 1'b0;

            // ---------- 输出：把上一帧结算结果串行发出 ----------
            if (out_k < out_n) begin
                o_valid <= 1'b1;
                o_id    <= out_id[out_k];
                o_x1    <= out_x1[out_k]; o_y1 <= out_y1[out_k];
                o_x2    <= out_x2[out_k]; o_y2 <= out_y2[out_k];
                o_dwell <= out_dw[out_k];
                o_last  <= (out_k == out_n - 1);
                out_k   = out_k + 1;
            end

            // ---------- 帧边界：匹配 + 更新轨迹表 + 生成输出列表 ----------
            if (frame_tick) begin
                // 1) 逐目标贪心最近邻匹配
                for (k = 0; k < MAX_TARGET; k = k + 1)
                    c_hit[k] = 8'hFF;
                for (i = 0; i < MAX_TRACK; i = i + 1)
                    tr_m[i] = 1'b0;

                for (k = 0; k < MAX_TARGET; k = k + 1) begin
                    if (k < c_n) begin
                    cx = (c_x1[k] + c_x2[k]) >> 1;
                    cy = (c_y1[k] + c_y2[k]) >> 1;
                    best = -1; bd = MATCH_DIST + 1;
                    for (i = 0; i < MAX_TRACK; i = i + 1) begin
                        if (i < tr_n) begin
                        if (tr_act[i] && !tr_m[i]) begin
                            dcx = cx - (( (tr_x1[i] + tr_x2[i]) >> 1 ));
                            dcy = cy - (( (tr_y1[i] + tr_y2[i]) >> 1 ));
                            if (dcx < 0) dx = -dcx; else dx = dcx;
                            if (dcy < 0) dy = -dcy; else dy = dcy;
                            if (dx <= MATCH_DIST && dy <= MATCH_DIST && (dx + dy) < bd) begin
                                bd = dx + dy; best = i;
                            end
                        end
                        end
                    end
                    if (best >= 0) begin
                        c_hit[k]     = best[7:0];
                        tr_m[best]   = 1'b1;
                        tr_x1[best]  = c_x1[k]; tr_y1[best] = c_y1[k];
                        tr_x2[best]  = c_x2[k]; tr_y2[best] = c_y2[k];
                        if (tr_seen[best] != 16'hFFFF) tr_seen[best] = tr_seen[best] + 1;
                        tr_miss[best] = 0;
                    end else begin
                        // 新轨迹
                        if (tr_n < MAX_TRACK) begin
                            tr_act[tr_n]  = 1'b1;
                            tr_id[tr_n]   = id_next;  id_next = id_next + 8'd1;
                            tr_x1[tr_n]   = c_x1[k];  tr_y1[tr_n] = c_y1[k];
                            tr_x2[tr_n]   = c_x2[k];  tr_y2[tr_n] = c_y2[k];
                            tr_seen[tr_n] = 16'd1;    tr_miss[tr_n] = 0;
                            c_hit[k]      = tr_n[7:0];
                            tr_n          = tr_n + 1;
                        end
                        // 表满：丢弃目标（见头部限制）
                    end
                    end
                end
                // 2) 未匹配轨迹老化；删除到期轨迹（压缩表）
                for (i = 0; i < MAX_TRACK; i = i + 1) begin
                    if (i < tr_n) begin
                    if (tr_act[i] && !tr_m[i]) begin
                        if (tr_miss[i] != 16'hFFFF) tr_miss[i] = tr_miss[i] + 1;
                    end
                    end
                end
                begin : compact
                    integer w, r;
                    w = 0;
                    for (r = 0; r < MAX_TRACK; r = r + 1) begin
                        if (r < tr_n) begin
                        if (tr_act[r] && (tr_miss[r] <= MISSED_MAX)) begin
                            tr_act[w]=tr_act[r]; tr_id[w]=tr_id[r];
                            tr_x1[w]=tr_x1[r]; tr_y1[w]=tr_y1[r];
                            tr_x2[w]=tr_x2[r]; tr_y2[w]=tr_y2[r];
                            tr_seen[w]=tr_seen[r]; tr_miss[w]=tr_miss[r];
                            // 更新 c_hit 里的轨迹号引用
                            for (k = 0; k < MAX_TARGET; k = k + 1) if (k < c_n) begin
                                if (c_hit[k] == r[7:0]) c_hit[k] = w[7:0];
                            end
                            w = w + 1;
                        end
                        end
                    end
                    tr_n = w;
                end
                // 3) 生成本帧输出列表（跟踪后 id + dwell）
                out_n = 0;
                for (k = 0; k < MAX_TARGET; k = k + 1) begin
                    if (k < c_n) begin
                    if (c_hit[k] != 8'hFF) begin
                        out_id[out_n]  = tr_id[c_hit[k]];
                        out_x1[out_n]  = c_x1[k]; out_y1[out_n] = c_y1[k];
                        out_x2[out_n]  = c_x2[k]; out_y2[out_n] = c_y2[k];
                        out_dw[out_n]  = tr_seen[c_hit[k]];
                        out_n          = out_n + 1;
                    end
                    end
                end
                out_k = 0;
                // 4) 清当前帧积累
                c_n = 0;
                for (i = 0; i < MAX_TRACK; i = i + 1) tr_m[i] = 1'b0;
            end
            // ---------- 积累本帧输入目标 ----------
            else if (t_valid && (c_n < MAX_TARGET)) begin
                c_x1[c_n] = t_x1; c_y1[c_n] = t_y1;
                c_x2[c_n] = t_x2; c_y2[c_n] = t_y2;
                c_n = c_n + 1;
            end
        end
    end

endmodule
