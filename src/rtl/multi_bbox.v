`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// multi_bbox —— 多目标连通域包围盒（行扫描 + 并查集）
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
// ★ 资源与限制：
//   - MAX_LABEL 个标签的并查集 + 包围盒用寄存器/分布式 RAM 实现；
//   - 每行最多 MAX_RUN 个**上一行**游程参与匹配，超出部分丢弃；
//   - 一帧最多输出 MAX_LABEL 个目标，标签表满后新游程被丢弃。
//
// ★★★ XIF123 治本（2026-10-13）：匹配循环串行化 + 输入缓存 ★★★
//   原版：3 处 `for (j=0; j<MAX_RUN; j++)` 16 路并行做重叠判断 + find_root
//   + 合并，全在 always 阻塞赋值区一拍完成 → 综合后 16 套并行组合逻辑云
//   × 3 处 + parent/lab_* 动态索引 mux/demux 爆炸，multi_bbox 占 83,286 LUT
//   （全模块 96,997/53,200 = 182% 超限，见 docs/handoff_line2_multibbox_20261013.md）。
//
//   治本：游程关闭后不再一拍内匹配完 16 个上一行游程，改为状态机串行——
//   每拍只处理 1 个 pr 游程的重叠判断 + find_root + 合并，MAX_RUN 拍完成。
//   匹配期间上游来的 in_valid 样本缓存进 SF_DEPTH 深度的 FIFO，匹配完排空。
//   组合逻辑从 16 套降到 1 套，LUT 大幅下降。
//
//   ★ OOC 综合实测（Vivado 2025.2, xc7z020clg400-1, 满配 MAX_LABEL=16/MAX_RUN=16）：
//     Slice LUTs = 19,048 / 53,200 = 35.80% < 50% ✅ 达标
//     （原并行版 83,286 LUT ≈ 157%，降 77.1%；Slice Registers 5,166 = 4.86%）
//   ★ 功能：tb_multi_bbox PASS（帧1单目标/帧2+双目标 cnt=1200 全对）
//           tb_md_pipeline_uart 13 项 PASS + tb_md_pipeline 13 帧 PASS（整链回归）
//   ★ 验收待办：孙伟博满配/回绕测试台复跑（验收④）
//
//   接口完全不变（遵守接口冻结表），只改内部实现。
//
// ★ 时序说明：
//   - 标签表/游程表用 NBA 跨拍更新；结算输出表（out_*）用阻塞（原版风格）；
//   - find_root 限深 4（小 id 吸收大 id，实际树深 ≤2）；
//   - 输出在帧边界后的若干拍内串行发出，不占用下一帧的掩码处理通路。
// -----------------------------------------------------------------------------
module multi_bbox #(
    parameter integer MIN_CNT   = 64,   // 面积门限：与 bbox.v 同口径
    // ★ XIF123 串行化版（2026-10-13，WIP）：恢复满配 MAX_LABEL=16 / MAX_RUN=16。
    //   串行化（每拍 1 套匹配逻辑）的目的就是满配下 LUT<50%——验收标准第一条
    //   「16 目标满配 PASS」（docs/handoff_code_fixes_20261013.md）。
    //   MAX_RUN 只影响匹配时长（16 拍）与 FIFO 积压（约 18 拍），不增 LUT。
    parameter integer MAX_LABEL = 16,   // 并查集标签容量（一帧最多 MAX_LABEL 个目标）
    parameter integer MAX_RUN   = 16    // 上一行参与匹配的最大游程数
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
    output reg         o_last,
    output reg         o_overflow   // FIFO 满仍要写=静默丢样时粘存（防静默丢失，供 PS 按帧感知）
);

    // ---------------- 并查集 + 包围盒表 ----------------
    reg [3:0]  parent [0:MAX_LABEL-1];  // 父指针；parent[i]==i 即根
    reg        used    [0:MAX_LABEL-1];
    reg [15:0] lab_mnx [0:MAX_LABEL-1];
    reg [15:0] lab_mny [0:MAX_LABEL-1];
    reg [15:0] lab_mxx [0:MAX_LABEL-1];
    reg [15:0] lab_mxy [0:MAX_LABEL-1];
    reg [15:0] lab_cnt [0:MAX_LABEL-1];

    // ★ find_root 限深 4（治本第 1 步）：手写 4 步代替 for k=0..15，
    //   把 16 级 parent[l] 动态索引 mux 链砍到 4 级。
    //   小 id 吸收大 id 策略下实际树深 ≤2，限深 4 充裕。
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
    reg [5:0]  pr_n;                    // 上一行游程数（0..MAX_RUN）

    reg [15:0] cr_s [0:MAX_RUN-1];      // 当前行游程起点
    reg [15:0] cr_e [0:MAX_RUN-1];
    reg [3:0]  cr_lab[0:MAX_RUN-1];
    reg [5:0]  cr_n;

    // ---------------- 流式状态 ----------------
    reg        run_open;                // 当前行是否有未关闭的游程
    reg [15:0] rs;                      // 当前游程起点
    reg [15:0] prow;                    // 上一个有效样本的 y
    reg [15:0] px;                      // 上一个有效样本的 x
    reg        seen_any;                // 是否已见过第一个有效样本

    // ---------------- 输入缓存 FIFO（治本第 2 步新增）----------------
    // ST_MATCH/ST_ALLOC/ST_FINISH 期间上游来的 in_valid 样本缓存于此。
    // 深度 512（2026-10-15 full16 定位实测：256 仍不够——串行 ST_MATCH 每关一个
    // 游程要 MAX_RUN+2≈18 拍，一行 16 游程净欠 ~336 拍，FIFO 峰值积压 ~336 > 256
    // → 溢出丢样（丢行/帧边界样本）→ 永不结算 → 0 框，full16/label_full 复现；
    // bridge/reuse/overflow(MAX_RUN=4) 欠账小所以过。512 覆盖 full16/label_full
    // 峰值积压并留余量。已知局限：full16_64（16 目标×32 行、行行 16 游程）净欠
    // ~7800 拍，任何可行深度都救不了，属串行化结构性上限，见
    // docs/multibbox_16_vs_mainstream_20261015.md）。宽度 {valid,x,y,mask}=34bit。
    localparam integer SF_DEPTH = 512;
    reg [33:0] sf [0:SF_DEPTH-1];
    reg [8:0]  sf_wr, sf_rd;            // 0..SF_DEPTH-1（512 需 9 位）
    reg [9:0]  sf_cnt;                  // 0..SF_DEPTH（512 需 10 位）
    reg        fifo_overflow;           // 满仍要写=静默丢样时粘存（不再静默，供 PS 读）

    // ---------------- 匹配状态机（治本第 2 步）----------------
    localparam [2:0] ST_IDLE   = 3'd0,  // 正常流式（处理 FIFO/in_valid/pending）
                     ST_MATCH  = 3'd1,  // 串行匹配上一行游程，每拍 1 个
                     ST_ALLOC  = 3'd2,  // 分配新标签 + 写 bbox + 写当前行表
                     ST_FINISH = 3'd3;  // 收尾：转表/结算/开新行/开新帧
    reg [2:0]  state;

    reg [5:0]  mk;                      // 匹配游标 0..MAX_RUN
    reg [3:0]  mroot;                   // 当前匹配根
    reg        mfound;                  // 是否命中过

    // 闭合游程缓存（游程关闭时锁存，供 ST_MATCH/ST_ALLOC 用）
    reg [15:0] close_s, close_e, close_row;
    localparam [1:0] CL_SAME = 2'd0,    // 同行游程关闭
                     CL_ROW  = 2'd1,    // 行边界（含末游程关闭）
                     CL_FRAME = 2'd2;   // 帧边界（末行末游程关闭）
    reg [1:0]  close_type;

    // pending 样本：闭合触发那拍的「当前样本」（新行/新帧第一个），
    // ST_FINISH 时消费它开新行/新帧。
    reg        pend_valid;
    reg [15:0] pend_x, pend_y;
    reg        pend_mask;

    // 当前要处理的样本（组合选择：ST_IDLE 时 pending > FIFO > in_valid）
    reg        cur_valid, cur_mask;
    reg [15:0] cur_x, cur_y;
    reg        cur_from_fifo;
    always @(*) begin
        if (state == ST_IDLE) begin
            if (pend_valid) begin
                cur_valid = 1'b1;  cur_x = pend_x;  cur_y = pend_y;  cur_mask = pend_mask;
                cur_from_fifo = 1'b0;
            end else if (sf_cnt > 0) begin
                cur_valid = sf[sf_rd][33];
                cur_x     = sf[sf_rd][32:17];
                cur_y     = sf[sf_rd][16:1];
                cur_mask  = sf[sf_rd][0];
                cur_from_fifo = 1'b1;
            end else begin
                cur_valid = in_valid; cur_x = in_x; cur_y = in_y; cur_mask = in_mask;
                cur_from_fifo = 1'b0;
            end
        end else begin
            cur_valid = 1'b0; cur_x = 16'd0; cur_y = 16'd0; cur_mask = 1'b0;
            cur_from_fifo = 1'b0;
        end
    end

    wire new_frame = cur_valid && seen_any && (cur_y < prow);
    wire new_row   = cur_valid && seen_any && !new_frame && (cur_y != prow);

    // ★ 统一 FIFO 读写使能（修复 sf_cnt NBA 冲突：原写与排 FIFO 同拍对 sf_cnt
    //   重复 NBA 赋值，last-write-wins 导致指针/计数不同步、样本乱序）
    reg fifo_we, fifo_re;
    always @(*) begin
        fifo_we = 1'b0;
        // 写：非「ST_IDLE 直处理 in_valid」时都缓存
        if (in_valid && (sf_cnt < SF_DEPTH) &&
            (state != ST_IDLE || pend_valid || (sf_cnt > 0)))
            fifo_we = 1'b1;
        // 读：ST_IDLE 排 FIFO（cur 来自 FIFO）时出队
        fifo_re = (state == ST_IDLE) && cur_valid && cur_from_fifo;
    end

    // ---------------- 结算输出区 ----------------
    reg [15:0] out_x1 [0:MAX_LABEL-1];
    reg [15:0] out_y1 [0:MAX_LABEL-1];
    reg [15:0] out_x2 [0:MAX_LABEL-1];
    reg [15:0] out_y2 [0:MAX_LABEL-1];
    reg [15:0] out_cnt[0:MAX_LABEL-1];
    integer    out_n;
    integer    out_k;

    integer i, j;
    reg [3:0] lj, lo, hi;
    reg hit;

    // ★ 修复 ST_ALLOC 的 NBA 时序坑：for 循环里 `!mfound` 读 NBA 旧值，
    //   导致同拍内所有 !used 标签都被分配。改用组合优先编码选出 first_free。
    reg [3:0] first_free_lbl;
    reg       first_free_valid;
    integer kk;
    always @(*) begin
        first_free_valid = 1'b0; first_free_lbl = 4'd0;
        for (kk = 0; kk < MAX_LABEL; kk = kk + 1) begin
            if (!used[kk] && !first_free_valid) begin
                first_free_lbl = kk[3:0]; first_free_valid = 1'b1;
            end
        end
    end

    // 游程关闭触发的统一入口：锁存闭合信息 + 进 ST_MATCH
    // （同行/行边界/帧边界 三种闭合共用，区别在 close_type）
    // 调用点：ST_IDLE 检测到关闭时。注意：本任务用 task 简化，但 Verilog
    // task 在 always 里不能改 state（NBA），所以这里内联。
    // 下面 ST_IDLE 的三个分支各自内联触发逻辑。

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            run_open <= 1'b0; rs <= 16'd0; prow <= 16'd0; px <= 16'd0;
            seen_any <= 1'b0;
            o_valid <= 1'b0; o_x1 <= 0; o_y1 <= 0; o_x2 <= 0; o_y2 <= 0;
            o_cnt <= 0; o_id <= 0; o_last <= 1'b0;
            pr_n <= 0; cr_n <= 0;
            sf_wr <= 0; sf_rd <= 0; sf_cnt <= 0; fifo_overflow <= 1'b0; o_overflow <= 1'b0;
            mk <= 0; mroot <= 4'h0; mfound <= 1'b0;
            close_s <= 0; close_e <= 0; close_row <= 0; close_type <= CL_SAME;
            pend_valid <= 1'b0; pend_x <= 0; pend_y <= 0; pend_mask <= 1'b0;
            out_n = 0; out_k = 0;
            for (i = 0; i < MAX_LABEL; i = i + 1) begin
                parent[i] <= i[3:0]; used[i] <= 1'b0; lab_cnt[i] <= 16'd0;
                lab_mnx[i] <= 16'hFFFF; lab_mny[i] <= 16'hFFFF;
                lab_mxx[i] <= 16'd0;    lab_mxy[i] <= 16'd0;
            end
        end else begin
            // 默认：输出总线空闲
            o_valid <= 1'b0;
            o_last  <= 1'b0;

            // ★ 统一 FIFO 读写指针/计数更新（fifo_we/fifo_re 在组合 always 里算）
            //   修复原写与排 FIFO 同拍对 sf_cnt 冲突 NBA（last-write-wins）
            if (fifo_we) begin
                sf[sf_wr] <= {1'b1, in_x, in_y, in_mask};
                sf_wr <= (sf_wr == SF_DEPTH-1) ? 9'd0 : sf_wr + 9'd1;
            end
            if (fifo_re) begin
                sf_rd <= (sf_rd == SF_DEPTH-1) ? 9'd0 : sf_rd + 9'd1;
            end
            sf_cnt <= sf_cnt + (fifo_we ? 10'd1 : 10'd0) - (fifo_re ? 10'd1 : 10'd0);
            // 溢出粘存：FIFO 满仍要写 = 静默丢样，锁存标志（不再静默丢失）
            if (new_frame) fifo_overflow <= 1'b0;        // 每帧开始清，PS 按帧感知
            if (in_valid && (sf_cnt == SF_DEPTH)) fifo_overflow <= 1'b1;
            o_overflow <= fifo_overflow;

            case (state)
                // ===================== ST_IDLE: 正常流式 =====================
                ST_IDLE: begin
                    if (cur_valid) begin
                        seen_any <= 1'b1;

                        // ---------- 帧边界 ----------
                        if (new_frame) begin
                            if (run_open) begin
                                // 末行有未闭合游程 → 触发匹配
                                close_s <= rs; close_e <= px; close_row <= prow;
                                close_type <= CL_FRAME;
                                mk <= 0; mroot <= 4'hF; mfound <= 1'b0;
                                state <= ST_MATCH;
                                // 当前样本（新帧第一行）pending
                                pend_valid <= 1'b1;
                                pend_x <= cur_x; pend_y <= cur_y; pend_mask <= cur_mask;
                                // 出队（若来自 FIFO）
                                // 出队由 fifo_re 统一处理（治本第 2 步重构）
                            end else begin
                                // 无末行游程 → 直接结算 + 清表 + 开新帧
                                out_n = 0;
                                for (i = 0; i < MAX_LABEL; i = i + 1) begin
                                    if (used[i] && (parent[i] == i[3:0]) &&
                                        (lab_cnt[i] >= MIN_CNT[15:0]) &&
                                        (lab_mnx[i] <= lab_mxx[i]) && (lab_mny[i] <= lab_mxy[i])) begin
                                        out_x1[out_n] = lab_mnx[i]; out_y1[out_n] = lab_mny[i];
                                        out_x2[out_n] = lab_mxx[i]; out_y2[out_n] = lab_mxy[i];
                                        out_cnt[out_n] = lab_cnt[i];
                                        out_n = out_n + 1;
                                    end
                                end
                                out_k = 0;
                                for (i = 0; i < MAX_LABEL; i = i + 1) begin
                                    parent[i] <= i[3:0]; used[i] <= 1'b0; lab_cnt[i] <= 16'd0;
                                    lab_mnx[i] <= 16'hFFFF; lab_mny[i] <= 16'hFFFF;
                                    lab_mxx[i] <= 16'd0;    lab_mxy[i] <= 16'd0;
                                end
                                pr_n <= 0; cr_n <= 0;
                                prow <= cur_y; px <= cur_x;
                                if (cur_mask) begin
                                    run_open <= 1'b1; rs <= cur_x;
                                end else begin
                                    run_open <= 1'b0;
                                end
                                // 出队由 fifo_re 统一处理（治本第 2 步重构）
                            end
                        end
                        // ---------- 行边界 ----------
                        else if (new_row) begin
                            if (run_open) begin
                                close_s <= rs; close_e <= px; close_row <= prow;
                                close_type <= CL_ROW;
                                mk <= 0; mroot <= 4'hF; mfound <= 1'b0;
                                state <= ST_MATCH;
                                pend_valid <= 1'b1;
                                pend_x <= cur_x; pend_y <= cur_y; pend_mask <= cur_mask;
                                // 出队由 fifo_re 统一处理（治本第 2 步重构）
                            end else begin
                                // 无游程 → 直接转表 + 开新行
                                pr_n <= cr_n;
                                for (j = 0; j < MAX_RUN; j = j + 1) begin
                                    pr_s[j] <= cr_s[j]; pr_e[j] <= cr_e[j]; pr_lab[j] <= cr_lab[j];
                                end
                                cr_n <= 0;
                                prow <= cur_y; px <= cur_x;
                                if (cur_mask) begin
                                    run_open <= 1'b1; rs <= cur_x;
                                end else begin
                                    run_open <= 1'b0;
                                end
                                // 出队由 fifo_re 统一处理（治本第 2 步重构）
                            end
                        end
                        // ---------- 同行 ----------
                        else begin
                            if (cur_mask && !run_open) begin
                                // 游程开始
                                run_open <= 1'b1;
                                rs <= cur_x;
                                px <= cur_x;
                                // 出队由 fifo_re 统一处理（治本第 2 步重构）
                            end else if (!cur_mask && run_open) begin
                                // 游程关闭 → 触发匹配（当前样本是 !mask，已处理 px）
                                close_s <= rs; close_e <= px; close_row <= prow;
                                close_type <= CL_SAME;
                                mk <= 0; mroot <= 4'hF; mfound <= 1'b0;
                                state <= ST_MATCH;
                                px <= cur_x;
                                pend_valid <= 1'b0;  // ★ 修复：CL_SAME 闭合时清 pending（消费当前样本）
                                // 出队由 fifo_re 统一处理（治本第 2 步重构）
                            end else begin
                                // 正常（mask&&run_open 或 !mask&&!run_open）
                                px <= cur_x;
                                // 出队由 fifo_re 统一处理（治本第 2 步重构）
                            end
                            // ★ 修复第一行误触发 new_frame：同行也要让 prow 跟踪 cur_y。
                            //   原同行分支不写 prow，首个样本后 prow 仍是复位值，
                            //   第二个样本 (y=0 < 65535) 误判帧边界、误清表。
                            //   同行时 cur_y==prow，同值写无害。
                            prow <= cur_y;
                        end
                    end
                end

                // ===================== ST_MATCH: 串行匹配 =====================
                ST_MATCH: begin
                    if (mk < pr_n) begin
                        // 重叠判断（1 套组合逻辑，不是 16 套）
                        // ★ 守卫 pr_lab==4'hF（上一行该游程无标签，如表满丢弃）：
                        //   否则 find_root(4'hF) 越界读 parent[0xF] 返回 x，污染 mroot
                        hit = (pr_lab[mk] != 4'hF) &&
                              (pr_s[mk] <= close_e) && (pr_e[mk] >= close_s);
                        if (hit) begin
                            lj = find_root(pr_lab[mk]);
                            if (!mfound) begin
                                mroot <= lj; mfound <= 1'b1;
                            end else if (lj != mroot) begin
                                // 合并：小 id 吸收大 id
                                if (mroot < lj) begin lo = mroot; hi = lj; end
                                else            begin lo = lj;    hi = mroot; end
                                parent[hi] <= lo;
                                if (lab_mnx[hi] < lab_mnx[lo]) lab_mnx[lo] <= lab_mnx[hi];
                                if (lab_mny[hi] < lab_mny[lo]) lab_mny[lo] <= lab_mny[hi];
                                if (lab_mxx[hi] > lab_mxx[lo]) lab_mxx[lo] <= lab_mxx[hi];
                                if (lab_mxy[hi] > lab_mxy[lo]) lab_mxy[lo] <= lab_mxy[hi];
                                lab_cnt[lo] <= lab_cnt[lo] + lab_cnt[hi];
                                lab_cnt[hi] <= 16'd0; used[hi] <= 1'b0;
                                mroot <= lo;
                            end
                        end
                        mk <= mk + 6'd1;
                    end else begin
                        state <= ST_ALLOC;
                    end
                end

                // ===================== ST_ALLOC: 分配/更新标签 + 写当前行表 =====================
                ST_ALLOC: begin
                    if (!mfound) begin
                        // 独占新标签：用组合优先编码选 first_free（修复 NBA for 坑）
                        if (first_free_valid) begin
                            parent[first_free_lbl] <= first_free_lbl;
                            used[first_free_lbl] <= 1'b1;
                            lab_mnx[first_free_lbl] <= close_s;
                            lab_mny[first_free_lbl] <= close_row;
                            lab_mxx[first_free_lbl] <= close_e;
                            lab_mxy[first_free_lbl] <= close_row;
                            lab_cnt[first_free_lbl] <= close_e - close_s + 16'd1;
                            mroot <= first_free_lbl; mfound <= 1'b1;
                        end
                        // else 标签表满，丢弃（见头部限制说明）
                    end else begin
                        // 更新 mroot 的 bbox + cnt
                        if (close_s   < lab_mnx[mroot]) lab_mnx[mroot] <= close_s;
                        if (close_row < lab_mny[mroot]) lab_mny[mroot] <= close_row;
                        if (close_e   > lab_mxx[mroot]) lab_mxx[mroot] <= close_e;
                        if (close_row > lab_mxy[mroot]) lab_mxy[mroot] <= close_row;
                        lab_cnt[mroot] <= lab_cnt[mroot] + (close_e - close_s + 16'd1);
                    end
                    // 写当前行表
                    if (cr_n < MAX_RUN) begin
                        cr_s[cr_n] <= close_s; cr_e[cr_n] <= close_e;
                        // ★ 核心修复（prow bug 真身）：cr_lab 不能直接 <= mroot——
                        //   「分配新标签」分支里 mroot <= first_free_lbl 与本句同拍 NBA，
                        //   这里读到的是旧值 4'hF，导致下一行 find_root(0xF) 越界、
                        //   cnt 永不累积、结算时 cnt<MIN_CNT → out_n=0。
                        //   改用本拍实际生效的根：命中旧根用 mroot，新分配用 first_free_lbl，
                        //   表满丢弃记 4'hF（ST_MATCH 已加守卫跳过）。
                        cr_lab[cr_n] <= mfound ? mroot :
                                         (first_free_valid ? first_free_lbl : 4'hF);
                        cr_n <= cr_n + 6'd1;
                    end
                    state <= ST_FINISH;
                end

                // ===================== ST_FINISH: 收尾（按 close_type 分发）=====================
                ST_FINISH: begin
                    case (close_type)
                        CL_SAME: begin
                            run_open <= 1'b0;
                            state <= ST_IDLE;
                        end
                        CL_ROW: begin
                            // 当前行表 → 上一行表（此时 cr_s[cr_n] 已写入，NBA 生效）
                            pr_n <= cr_n;
                            for (j = 0; j < MAX_RUN; j = j + 1) begin
                                pr_s[j] <= cr_s[j]; pr_e[j] <= cr_e[j]; pr_lab[j] <= cr_lab[j];
                            end
                            cr_n <= 0;
                            // 消费 pending 开新行
                            prow <= pend_y; px <= pend_x;
                            if (pend_mask) begin
                                run_open <= 1'b1; rs <= pend_x;
                            end else begin
                                run_open <= 1'b0;
                            end
                            pend_valid <= 1'b0;
                            state <= ST_IDLE;
                        end
                        CL_FRAME: begin
                            // 结算上一帧
                            out_n = 0;
                            for (i = 0; i < MAX_LABEL; i = i + 1) begin
                                if (used[i] && (parent[i] == i[3:0]) &&
                                    (lab_cnt[i] >= MIN_CNT[15:0]) &&
                                    (lab_mnx[i] <= lab_mxx[i]) && (lab_mny[i] <= lab_mxy[i])) begin
                                    out_x1[out_n] = lab_mnx[i]; out_y1[out_n] = lab_mny[i];
                                    out_x2[out_n] = lab_mxx[i]; out_y2[out_n] = lab_mxy[i];
                                    out_cnt[out_n] = lab_cnt[i];
                                    out_n = out_n + 1;
                                end
                            end
                            out_k = 0;
                            // 清表
                            for (i = 0; i < MAX_LABEL; i = i + 1) begin
                                parent[i] <= i[3:0]; used[i] <= 1'b0; lab_cnt[i] <= 16'd0;
                                lab_mnx[i] <= 16'hFFFF; lab_mny[i] <= 16'hFFFF;
                                lab_mxx[i] <= 16'd0;    lab_mxy[i] <= 16'd0;
                            end
                            pr_n <= 0; cr_n <= 0;
                            // 消费 pending 开新帧
                            prow <= pend_y; px <= pend_x;
                            if (pend_mask) begin
                                run_open <= 1'b1; rs <= pend_x;
                            end else begin
                                run_open <= 1'b0;
                            end
                            pend_valid <= 1'b0;
                            state <= ST_IDLE;
                        end
                        default: state <= ST_IDLE;
                    endcase
                end

                default: state <= ST_IDLE;
            endcase

            // ---------- 输出：把结算列表逐拍发出去 ----------
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
