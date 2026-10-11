`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// alarm —— 线二任务：越界 / 停留告警（对跟踪后的 I3 流做规则判定）
//
// 输入：track 输出的跟踪后目标流（每目标一拍，含跨帧 id 与 dwell）。
// 输出：告警事件流（与目标流独立，各自打一拍）。
//
// 两条规则（对应寄存器表 I4 的 LINE_X / DWELL）：
//   1) 越界（type=1）：目标中心从 LINE_X 左侧跨到右侧（cx 前帧 < LINE_X ≤ 本帧 cx）。
//      每条轨迹每次穿越只报一次。LINE_X=0 时规则关闭（0 是复位值，即默认不告警）。
//   2) 停留（type=2）：轨迹连续出现帧数 dwell 恰好达到 DWELL 时报一次
//      （dwell 每帧 +1，== 只成立一次，天然不重复）。DWELL=0 关闭。
//
// 记忆按 id 索引（0..255），每个 id 存 prev_cx 与 seen 标记；
// 轨迹死亡后 id 不复用（track.v 的约定），所以不会串档。
//
// ★ 多区域/多规则细化：在此结构上加 LINE_Y/区域表即可，事件格式预留 type 字段。
// -----------------------------------------------------------------------------
module alarm #(
    parameter integer MAX_ID = 256       // id 空间（8bit）
)(
    input  wire        clk,
    input  wire        rst_n,
    // 寄存器表 I4 的两个运行时参数（将来接寄存器堆）
    input  wire [15:0] LINE_X,           // 警戒线 X（大像素域），0=关闭
    input  wire [15:0] DWELL,            // 停留告警帧数，0=关闭
    // 跟踪后目标流输入
    input  wire        t_valid,
    input  wire [7:0]  t_id,
    input  wire [15:0] t_x1, t_y1, t_x2, t_y2,
    input  wire [15:0] t_dwell,
    // 告警事件输出
    output reg         a_valid,
    output reg  [7:0]  a_id,
    output reg  [1:0]  a_type,           // 1=越界 2=停留
    output reg  [15:0] a_cx              // 事件发生时的目标中心 X
);

    // 每 id 的记忆
    reg        seen  [0:MAX_ID-1];       // 该 id 是否出现过
    reg [15:0] prev_cx[0:MAX_ID-1];

    integer i;
    reg [15:0] cx;
    reg cross_now, dwell_now;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_valid <= 1'b0; a_id <= 0; a_type <= 2'd0; a_cx <= 0;
            for (i = 0; i < MAX_ID; i = i + 1) begin
                seen[i] = 1'b0; prev_cx[i] = 16'd0;
            end
        end else begin
            a_valid <= 1'b0;
            cross_now = 1'b0;
            dwell_now = 1'b0;

            if (t_valid) begin
                cx = (t_x1 + t_x2) >> 1;

                if (!seen[t_id]) begin
                    seen[t_id]  = 1'b1;
                    prev_cx[t_id] = cx;
                    // 首现不做穿越判断（没有前帧位置）；但 dwell=1 < DWELL 也无事件
                end else begin
                    // 规则 1：越界（中心穿越，左→右）
                    if (LINE_X != 16'd0 && prev_cx[t_id] < LINE_X && cx >= LINE_X)
                        cross_now = 1'b1;
                    // 规则 2：停留（dwell 恰好达到阈值）
                    if (DWELL != 16'd0 && t_dwell == DWELL)
                        dwell_now = 1'b1;
                    prev_cx[t_id] = cx;

                    // 一次只报一件：穿越优先（越界通常比停留更紧急）
                    if (cross_now) begin
                        a_valid <= 1'b1; a_id <= t_id; a_type <= 2'd1; a_cx <= cx;
                    end else if (dwell_now) begin
                        a_valid <= 1'b1; a_id <= t_id; a_type <= 2'd2; a_cx <= cx;
                    end
                end
            end
        end
    end

endmodule
