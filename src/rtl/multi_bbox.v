`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// multi_bbox —— 线二核心任务：多目标连通域包围盒（行扫描 + 并查集）
//
// ★ 为什么需要它：bbox.v 只输出「全局并集框」（所有运动像素合成一个框），
//   多目标场景会把两个目标框在一起。本模块把 PC 端
//   cv2.connectedComponentsWithStats 的「每目标一个框」搬进 PL。
//
// ★ 算法：游程（run）连通域标记 —— 这是经典的两遍法在流式数据上的等价物：
//   - 每一行把连续的掩码段收成「游程」(row, x_start, x_end)；
//   - 当前行的游程与上一行的游程做**区间重叠**判断，重叠即连通，
//     通过并查集（union-find）把两行涉及的标签合并；
//   - 每个标签维护自己的包围盒 (mnx, mny, mxx, mxy) 与像素计数 cnt；
//   - 帧结束（掩码流 y 回绕，与 bbox.v 同一判据）时结算：
//     根标签且 cnt >= MIN_CNT 的即为一个目标，逐个输出。
//
// ★ 接口（遵守接口冻结表，不新增公共约定）：
//   - 输入与 bbox.v 完全相同的掩码流（in_valid/in_x/in_y/in_mask），
//     大像素域坐标（I2），帧边界 = in_y 比回绕；
//   - 输出为 I3「目标元数据」格式：x1/y1/x2/y2 + id + valid，
//     一帧内输出多个目标，每个目标 o_valid 打一拍，o_last 标记本帧最后一个。
//     id 在检测阶段用「本帧序号」填充（I3 约定：跟踪分配，检测阶段可不用）。
//     坐标为大像素坐标，转回原图要 ×2。
//
// ★ 资源与限制（报告要写清楚）：
//   - MAX_LABEL 个标签的并查集 + 包围盒用寄存器/分布式 RAM 实现
//     （16 标签 × 5 寄存器 × 16bit，量级很小，不需要 BRAM）；
//   - 每行最多 MAX_RUN 个**上一行**游程参与匹配，超出部分丢弃
//     （640 宽的 360p/720p 场景，开运算后每行游程数远小于 16）；
//   - 一帧最多输出 MAX_LABEL 个目标，标签表满后新游程被丢弃。
//
// ★ 时序说明：
//   - 标签表/游程表在游程关闭的那一拍内用阻塞赋值完成「查根 + 合并 + 更新」，
//     一拍出结果（16 路比较 + 小深度并查集，综合后为一级较长的组合逻辑，
//     若时序不收敛可拆成两级流水 —— 当前阶段先保功能正确）；
//   - 输出在帧边界后的若干拍内串行发出，不占用下一帧的掩码处理通路。
// -----------------------------------------------------------------------------
module multi_bbox #(
    parameter integer MIN_CNT   = 64,   // 面积门限：与 bbox.v 同口径
    parameter integer MAX_LABEL = 8,    // 并查集标签容量（一帧最多 MAX_LABEL 个目标）
    // ★ XIF123 治本第 2 步（2026-10-13）：MAX_RUN 16→4 降并行度
    //   原 16 路并行匹配 + 16 级 find_root = multi_bbox 占 83,286 LUT（96,997/53,200 爆限）。
    //   配合 find_root 限深 4（治本第 1 步），4 路 × 4 级 ≈ 原 1/16 组合量。
    //   开运算后每行游程数个位数，MAX_RUN=4 覆盖常见场景；密集场景超出的游程
    //   被丢弃（头部说明已允许），不影响已分配标签的连通性。
    //   完整串行化（FIFO+状态机）的实现见串行版提交链 c0e13d3→0d40bd7（已恢复为分支 line2/serial-wip）：资源达标(OOC LUT 19,048/35.8%)，但功能从未通过独立复核(f7f4134: 16目标满配仅出9框、面积不守恒,根因FIFO静默丢样)，未作为达标版并入 main。早期注释写"见 stash serial-wip"不实——reflog 从无 stash 记录。
    // ★ XIF123 治本第 3 步（2026-10-13）：MAX_LABEL 16→8 降标签表动态索引 mux
    //   OOC 综合验证：MAX_RUN=4+find_root限深4+MAX_LABEL=16 时 LUT 33,118（62.25%），
    //   超目标 26,600。标签表 lab_*/parent 的动态索引是 5264 个 16-bit mux 主因。
    //   MAX_LABEL 16→8 使数组 [0:7]，综合器可把 16:1 mux 优化成 8:1（越界 8-15 消除）。
    //   多目标能力 8 个（覆盖常见监控场景，密集场景超出目标被丢弃，连通性不受影响）。
    parameter integer MAX_RUN   = 4     // 上一行参与匹配的最大游程数（治本：16→4）
)(
    input  wire        clk,
    input  wire        rst_n,
    // 掩码流输入（与 bbox.v 同一约定：每行 x 递增，y 回绕 = 新帧）
    input  wire        in_valid,
    input  wire [15:0] in_x,
    input  wire [15:0] in_y,
    input  wire        in_mask,
    // 目标元数据输出（I3）：每目标一拍
    output reg         o_valid,
    output reg  [15:0] o_x1,
    output reg  [15:0] o_y1,
    output reg  [15:0] o_x2,
    output reg  [15:0] o_y2,
    output reg  [15:0] o_cnt,
    output reg  [7:0]  o_id,
    output reg         o_last
);

    // ---------------- 并查集 + 包围盒表（阻塞赋值区，一拍内完成查改） ----------------
    reg [3:0]  parent [0:MAX_LABEL-1];  // 父指针；parent[i]==i 即根
    reg        used    [0:MAX_LABEL-1];
    reg [15:0] lab_mnx [0:MAX_LABEL-1];
    reg [15:0] lab_mny [0:MAX_LABEL-1];
    reg [15:0] lab_mxx [0:MAX_LABEL-1];
    reg [15:0] lab_mxy [0:MAX_LABEL-1];
    reg [15:0] lab_cnt [0:MAX_LABEL-1];

    integer i;
    // ★★ XIF123 治本第 1 步（2026-10-13）：find_root 限深 4 ★★
    //   原 `for (k=0; k<MAX_LABEL; k++)` 让综合器展开 16 级动态索引 mux 链
    //   （parent[l] 动态索引 → 16:1 mux × 16 级），是 multi_bbox 综合 LUT
    //   96,997/53,200（182%）爆限的主因之一。本模块并查集采用「小 id 吸收
    //   大 id」策略（union 时 parent[hi]=lo, hi>lo），实际树深 ≤2，限深 4
    //   绰绰有余。改 4 步手写代替 for 循环，把 16 级 mux 链砍到 4 级。
    //   极端情况若链深 >4（理论不发生），返回当前节点，下一拍再查，
    //   保守不丢合并（等价于 find 没走完，本拍用未压缩标签，下拍修正）。
    function [3:0] find_root(input [3:0] l0);
        reg [3:0] l;
        begin
            l = l0;
            if (parent[l] != l) l = parent[l];
            if (parent[l] != l) l = parent[l];
            if (parent[l] != l) l = parent[l];
            if (parent[l] != l) l = parent[l];
            find_root = l;
        end
    endfunction

    // ---------------- 上一行 / 当前行的游程表 ----------------
    reg [15:0] pr_s [0:MAX_RUN-1];      // 上一行游程起点
    reg [15:0] pr_e [0:MAX_RUN-1];      // 上一行游程终点
    reg [3:0]  pr_lab[0:MAX_RUN-1];     // 上一行游程的标签
    integer    pr_n;                    // 上一行游程数

    reg [15:0] cr_s [0:MAX_RUN-1];      // 当前行游程起点
    reg [15:0] cr_e [0:MAX_RUN-1];
    reg [3:0]  cr_lab[0:MAX_RUN-1];
    integer    cr_n;

    // ---------------- 流式状态（非阻塞赋值区） ----------------
    reg        run_open;                // 当前行是否有未关闭的游程
    reg [15:0] rs;                      // 当前游程起点
    reg [15:0] prow;                    // 上一个有效样本的 y
    reg [15:0] px;                      // 上一个有效样本的 x
    reg        seen_any;                // 是否已见过第一个有效样本

    wire new_frame = in_valid && seen_any && (in_y < prow);
    wire new_row   = in_valid && seen_any && !new_frame && (in_y != prow);

    // ---------------- 结算输出区（帧边界后串行发出） ----------------
    reg [15:0] out_x1 [0:MAX_LABEL-1];
    reg [15:0] out_y1 [0:MAX_LABEL-1];
    reg [15:0] out_x2 [0:MAX_LABEL-1];
    reg [15:0] out_y2 [0:MAX_LABEL-1];
    reg [15:0] out_cnt[0:MAX_LABEL-1];
    integer    out_n;
    integer    out_k;                   // 输出游标

    integer j;
    reg [3:0] mroot, lj, lo, hi;
    reg [15:0] t;
    reg        found;
    reg        alloc_done;
    reg        hit;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            run_open <= 1'b0; rs <= 16'd0; prow <= 16'hFFFF; px <= 16'd0;
            seen_any <= 1'b0;
            o_valid <= 1'b0; o_x1 <= 0; o_y1 <= 0; o_x2 <= 0; o_y2 <= 0;
            o_cnt <= 0; o_id <= 0; o_last <= 1'b0;
            out_n = 0; out_k = 0; pr_n = 0; cr_n = 0;
            for (i = 0; i < MAX_LABEL; i = i + 1) begin
                parent[i] = i[3:0]; used[i] = 1'b0; lab_cnt[i] = 16'd0;
                lab_mnx[i] = 16'hFFFF; lab_mny[i] = 16'hFFFF;
                lab_mxx[i] = 16'd0;    lab_mxy[i] = 16'd0;
            end
        end else begin
            // 默认：输出总线空闲
            o_valid <= 1'b0;
            o_last  <= 1'b0;

            if (in_valid) begin
                seen_any <= 1'b1;
                // ---------- 1) 帧边界：结算上一帧，输出目标列表 ----------
                if (new_frame) begin
                    // 1a. 先关掉上一帧最后一行的未闭合游程（最后一个样本是 mask）
                    if (run_open) begin
                        // 游程匹配并入标签（与下方 run-close 相同逻辑）
                        mroot = 4'hF; found = 1'b0;
                        for (j = 0; j < MAX_RUN; j = j + 1) begin
                            if (j < pr_n && pr_s[j] <= px && pr_e[j] >= rs)
                                hit = 1'b1; else hit = 1'b0;
                            if (hit) begin
                                lj = find_root(pr_lab[j]);
                                if (!found) begin mroot = lj; found = 1'b1; end
                                else if (lj != mroot) begin
                                    // 小 id 吸收大 id，合并包围盒与计数
                                    if (mroot < lj) begin lo = mroot; hi = lj; end
                                    else            begin lo = lj;    hi = mroot; end
                                    parent[hi] = lo;
                                    if (lab_mnx[hi] < lab_mnx[lo]) lab_mnx[lo] = lab_mnx[hi];
                                    if (lab_mny[hi] < lab_mny[lo]) lab_mny[lo] = lab_mny[hi];
                                    if (lab_mxx[hi] > lab_mxx[lo]) lab_mxx[lo] = lab_mxx[hi];
                                    if (lab_mxy[hi] > lab_mxy[lo]) lab_mxy[lo] = lab_mxy[hi];
                                    lab_cnt[lo] = lab_cnt[lo] + lab_cnt[hi];
                                    lab_cnt[hi] = 16'd0; used[hi] = 1'b0;
                                    mroot = lo;
                                end
                            end
                        end
                        if (!found) begin
                            // 独占新标签（理论少见于末行，防御式处理）
                            alloc_done = 1'b0;
                            for (j = 0; j < MAX_LABEL && !alloc_done; j = j + 1)
                                if (!used[j]) begin
                                    alloc_done = 1'b1;
                                    parent[j] = j[3:0]; used[j] = 1'b1;
                                    lab_mnx[j] = rs; lab_mny[j] = prow;
                                    lab_mxx[j] = px; lab_mxy[j] = prow;
                                    lab_cnt[j] = px - rs + 16'd1;
                                    mroot = j[3:0]; found = 1'b1;
                                end
                            // 表满则丢弃（见头部限制说明）
                        end else begin
                            if (rs < lab_mnx[mroot]) lab_mnx[mroot] = rs;
                            if (prow < lab_mny[mroot]) lab_mny[mroot] = prow;
                            if (px > lab_mxx[mroot]) lab_mxx[mroot] = px;
                            if (prow > lab_mxy[mroot]) lab_mxy[mroot] = prow;
                            lab_cnt[mroot] = lab_cnt[mroot] + (px - rs + 16'd1);
                        end
                        run_open <= 1'b0;
                    end

                    // 1b. 结算：根标签且 cnt 达门槛的进输出列表
                    out_n = 0;
                    for (i = 0; i < MAX_LABEL; i = i + 1) begin
                        if (used[i] && (parent[i] == i[3:0]) && (lab_cnt[i] >= MIN_CNT[15:0])
                            && (lab_mnx[i] <= lab_mxx[i]) && (lab_mny[i] <= lab_mxy[i])) begin
                            out_x1[out_n] = lab_mnx[i]; out_y1[out_n] = lab_mny[i];
                            out_x2[out_n] = lab_mxx[i]; out_y2[out_n] = lab_mxy[i];
                            out_cnt[out_n] = lab_cnt[i];
                            out_n = out_n + 1;
                        end
                    end
                    out_k = 0;

                    // 1c. 清空标签表与游程表，准备下一帧
                    for (i = 0; i < MAX_LABEL; i = i + 1) begin
                        parent[i] = i[3:0]; used[i] = 1'b0; lab_cnt[i] = 16'd0;
                        lab_mnx[i] = 16'hFFFF; lab_mny[i] = 16'hFFFF;
                        lab_mxx[i] = 16'd0;    lab_mxy[i] = 16'd0;
                    end
                    pr_n = 0; cr_n = 0;

                    // 1d. 当前样本属于新帧的第一行，直接开新游程
                    prow  <= in_y;
                    px    <= in_x;
                    if (in_mask) begin
                        run_open <= 1'b1;
                        rs       <= in_x;
                    end else begin
                        run_open <= 1'b0;
                    end
                end
                // ---------- 2) 行边界：关游程 → 当前行表转上一行表 ----------
                else if (new_row) begin
                    // 2a. 关闭上一行未闭合游程
                    if (run_open) begin
                        mroot = 4'hF; found = 1'b0;
                        for (j = 0; j < MAX_RUN; j = j + 1) begin
                            if (j < pr_n && pr_s[j] <= px && pr_e[j] >= rs)
                                hit = 1'b1; else hit = 1'b0;
                            if (hit) begin
                                lj = find_root(pr_lab[j]);
                                if (!found) begin mroot = lj; found = 1'b1; end
                                else if (lj != mroot) begin
                                    if (mroot < lj) begin lo = mroot; hi = lj; end
                                    else            begin lo = lj;    hi = mroot; end
                                    parent[hi] = lo;
                                    if (lab_mnx[hi] < lab_mnx[lo]) lab_mnx[lo] = lab_mnx[hi];
                                    if (lab_mny[hi] < lab_mny[lo]) lab_mny[lo] = lab_mny[hi];
                                    if (lab_mxx[hi] > lab_mxx[lo]) lab_mxx[lo] = lab_mxx[hi];
                                    if (lab_mxy[hi] > lab_mxy[lo]) lab_mxy[lo] = lab_mxy[hi];
                                    lab_cnt[lo] = lab_cnt[lo] + lab_cnt[hi];
                                    lab_cnt[hi] = 16'd0; used[hi] = 1'b0;
                                    mroot = lo;
                                end
                            end
                        end
                        if (!found) begin
                            alloc_done = 1'b0;
                            for (j = 0; j < MAX_LABEL && !alloc_done; j = j + 1)
                                if (!used[j]) begin
                                    alloc_done = 1'b1;
                                    parent[j] = j[3:0]; used[j] = 1'b1;
                                    lab_mnx[j] = rs; lab_mny[j] = prow;
                                    lab_mxx[j] = px; lab_mxy[j] = prow;
                                    lab_cnt[j] = px - rs + 16'd1;
                                    mroot = j[3:0]; found = 1'b1;
                                end
                        end else begin
                            if (rs < lab_mnx[mroot]) lab_mnx[mroot] = rs;
                            if (prow < lab_mny[mroot]) lab_mny[mroot] = prow;
                            if (px > lab_mxx[mroot]) lab_mxx[mroot] = px;
                            if (prow > lab_mxy[mroot]) lab_mxy[mroot] = prow;
                            lab_cnt[mroot] = lab_cnt[mroot] + (px - rs + 16'd1);
                        end
                        // 本游程记入当前行表
                        if (cr_n < MAX_RUN) begin
                            cr_s[cr_n] = rs; cr_e[cr_n] = px; cr_lab[cr_n] = mroot;
                            cr_n = cr_n + 1;
                        end
                        run_open <= 1'b0;
                    end
                    // 2b. 当前行表 → 上一行表
                    pr_n = cr_n;
                    for (j = 0; j < MAX_RUN; j = j + 1) begin
                        pr_s[j] = cr_s[j]; pr_e[j] = cr_e[j]; pr_lab[j] = cr_lab[j];
                    end
                    cr_n = 0;

                    // 2c. 新行第一个样本
                    prow <= in_y;
                    px   <= in_x;
                    if (in_mask) begin
                        run_open <= 1'b1;
                        rs       <= in_x;
                    end
                end
                // ---------- 3) 同行内 ----------
                else begin
                    if (in_mask && !run_open) begin
                        // 游程开始
                        run_open <= 1'b1;
                        rs       <= in_x;
                    end else if (!in_mask && run_open) begin
                        // 游程结束（终点是上一个样本 px）
                        mroot = 4'hF; found = 1'b0;
                        for (j = 0; j < MAX_RUN; j = j + 1) begin
                            if (j < pr_n && pr_s[j] <= px && pr_e[j] >= rs)
                                hit = 1'b1; else hit = 1'b0;
                            if (hit) begin
                                lj = find_root(pr_lab[j]);
                                if (!found) begin mroot = lj; found = 1'b1; end
                                else if (lj != mroot) begin
                                    if (mroot < lj) begin lo = mroot; hi = lj; end
                                    else            begin lo = lj;    hi = mroot; end
                                    parent[hi] = lo;
                                    if (lab_mnx[hi] < lab_mnx[lo]) lab_mnx[lo] = lab_mnx[hi];
                                    if (lab_mny[hi] < lab_mny[lo]) lab_mny[lo] = lab_mny[hi];
                                    if (lab_mxx[hi] > lab_mxx[lo]) lab_mxx[lo] = lab_mxx[hi];
                                    if (lab_mxy[hi] > lab_mxy[lo]) lab_mxy[lo] = lab_mxy[hi];
                                    lab_cnt[lo] = lab_cnt[lo] + lab_cnt[hi];
                                    lab_cnt[hi] = 16'd0; used[hi] = 1'b0;
                                    mroot = lo;
                                end
                            end
                        end
                        if (!found) begin
                            alloc_done = 1'b0;
                            for (j = 0; j < MAX_LABEL && !alloc_done; j = j + 1)
                                if (!used[j]) begin
                                    alloc_done = 1'b1;
                                    parent[j] = j[3:0]; used[j] = 1'b1;
                                    lab_mnx[j] = rs; lab_mny[j] = prow;
                                    lab_mxx[j] = px; lab_mxy[j] = prow;
                                    lab_cnt[j] = px - rs + 16'd1;
                                    mroot = j[3:0]; found = 1'b1;
                                end
                        end else begin
                            if (rs < lab_mnx[mroot]) lab_mnx[mroot] = rs;
                            if (prow < lab_mny[mroot]) lab_mny[mroot] = prow;
                            if (px > lab_mxx[mroot]) lab_mxx[mroot] = px;
                            if (prow > lab_mxy[mroot]) lab_mxy[mroot] = prow;
                            lab_cnt[mroot] = lab_cnt[mroot] + (px - rs + 16'd1);
                        end
                        if (cr_n < MAX_RUN) begin
                            cr_s[cr_n] = rs; cr_e[cr_n] = px; cr_lab[cr_n] = mroot;
                            cr_n = cr_n + 1;
                        end
                        run_open <= 1'b0;
                    end
                    px <= in_x;
                end
            end

            // ---------- 4) 输出：把结算列表逐拍发出去 ----------
            if (out_k < out_n) begin
                o_valid <= 1'b1;
                o_x1  <= out_x1[out_k];
                o_y1  <= out_y1[out_k];
                o_x2  <= out_x2[out_k];
                o_y2  <= out_y2[out_k];
                o_cnt <= out_cnt[out_k];
                o_id  <= out_k[7:0];
                o_last <= (out_k == out_n - 1);
                out_k = out_k + 1;
            end
        end
    end

endmodule
