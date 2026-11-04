`timescale 1ns / 1ps
// multi_bbox：基于逐行游程及标签合并的多目标包围盒提取。
// 每拍匹配一个上一行游程，忙期间输入进入 SF_DEPTH 深度的 FIFO。
// 标签容量为 MAX_LABEL，每行参与匹配的游程数量上限为 MAX_RUN。
// 标签或游程表满后不能新增对应条目；FIFO 溢出由 o_overflow 指示。
// in_y 回绕或配置的 END_X/END_Y 末样本触发帧结算。
// 面积达到 MIN_CNT 的目标逐个输出，o_done 标记整批完成（包括空批）。
// 输出为 2×2 大像素域的闭区间坐标，o_id 为该批目标序号。
module multi_bbox #(
    parameter integer MIN_CNT   = 64,   // 面积门限：与 bbox.v 同口径
    // 标签与游程容量独立配置；MAX_RUN 同时决定串行匹配的最长扫描长度。
    parameter integer MAX_LABEL = 16,   // 并查集标签容量（一帧最多 MAX_LABEL 个目标）
    parameter integer SF_DEPTH = 4096,  // bounded sample backlog, mapped to block RAM
    parameter integer MAX_RUN   = 16,   // 上一行参与匹配的最大游程数
    // Optional last accepted mask coordinate. -1 preserves wrap-only clients.
    parameter integer END_X = -1,
    parameter integer END_Y = -1
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
    output reg         o_overflow,  // FIFO 丢样的帧级锁存标志
    output reg         o_done       // Every completed batch, including zero targets
);

    // 并查集 + 包围盒表
    // 5 位标签可区分 16 个有效编号与无效标记 5'h1F。
    reg [4:0]  parent [0:MAX_LABEL-1];  // 父指针；parent[i]==i 即根
    reg        used    [0:MAX_LABEL-1];
    reg [15:0] lab_mnx [0:MAX_LABEL-1];
    reg [15:0] lab_mny [0:MAX_LABEL-1];
    reg [15:0] lab_mxx [0:MAX_LABEL-1];
    reg [15:0] lab_mxy [0:MAX_LABEL-1];
    reg [15:0] lab_cnt [0:MAX_LABEL-1];

    // 根查找最多展开 4 次父指针访问。
    function [4:0] find_root(input [4:0] l0);
        reg [4:0] l;
        begin
            l = l0;
            if (parent[l] != l) l = parent[l];
            if (parent[l] != l) l = parent[l];
            if (parent[l] != l) l = parent[l];
            if (parent[l] != l) l = parent[l];
            find_root = l;
        end
    endfunction

    function [15:0] sat_add(input [15:0] a, input [16:0] b);
        reg [17:0] sum;
        begin sum={2'b0,a}+{1'b0,b}; sat_add=(sum>65535)?16'hffff:sum[15:0]; end
    endfunction

    // 上一行 / 当前行的游程表
    reg [15:0] pr_s [0:MAX_RUN-1];      // 上一行游程起点
    reg [15:0] pr_e [0:MAX_RUN-1];      // 上一行游程终点
    reg [4:0]  pr_lab[0:MAX_RUN-1];     // 上一行游程的标签
    reg [5:0]  pr_n;                    // 上一行游程数（0..MAX_RUN）

    reg [15:0] cr_s [0:MAX_RUN-1];      // 当前行游程起点
    reg [15:0] cr_e [0:MAX_RUN-1];
    reg [4:0]  cr_lab[0:MAX_RUN-1];
    reg [5:0]  cr_n;

    // 流式状态
    reg        run_open;                // 当前行是否有未关闭的游程
    reg [15:0] rs;                      // 当前游程起点
    reg [15:0] prow;                    // 上一个有效样本的 y
    reg [15:0] px;                      // 上一个有效样本的 x
    reg        seen_any;                // 是否已见过第一个有效样本
    reg        end_pending, finishing_end;

    // Synchronous simple-dual-port sample FIFO, plus one prefetched item.
    // 4096 samples cover the 76x36 dense MIN_CNT64 test frame. Real 640-wide
    // input has >=2 clocks/sample plus blanking; arbitrary sustained input
    // beyond the serial service rate remains bounded and raises o_overflow.
    localparam integer SF_AW = $clog2(SF_DEPTH);
    (* ram_style="block" *) reg [33:0] sf [0:SF_DEPTH-1];
    reg [SF_AW-1:0] sf_wr, sf_rd;
    reg [SF_AW:0] sf_cnt;
    reg [33:0] sf_data;
    reg sf_valid;
    reg fifo_overflow;

    // 串行匹配状态机
    localparam [2:0] ST_IDLE   = 3'd0,  // 正常流式（处理 FIFO/in_valid/pending）
                     ST_MATCH  = 3'd1,  // 串行匹配上一行游程，每拍 1 个
                     ST_ALLOC  = 3'd2,  // 分配新标签 + 写 bbox + 写当前行表
                     ST_FINISH = 3'd3, ST_COLLECT=3'd4, ST_PUBLISH=3'd5, ST_CLEAR=3'd6;  // 收尾：转表/结算/开新行/开新帧
    reg [2:0]  state;

    reg [5:0]  mk;                      // 匹配游标 0..MAX_RUN
    reg [4:0]  mroot;                   // 当前匹配根
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
        if (state == ST_IDLE && !end_pending) begin
            if (pend_valid) begin
                cur_valid = 1'b1;  cur_x = pend_x;  cur_y = pend_y;  cur_mask = pend_mask;
                cur_from_fifo = 1'b0;
            end else if (sf_valid) begin
                cur_valid = sf_data[33];
                cur_x     = sf_data[32:17];
                cur_y     = sf_data[16:1];
                cur_mask  = sf_data[0];
                cur_from_fifo = 1'b1;
            end else if (sf_cnt == 0) begin
                cur_valid = in_valid; cur_x = in_x; cur_y = in_y; cur_mask = in_mask;
                cur_from_fifo = 1'b0;
            end else begin
                cur_valid=0;cur_x=0;cur_y=0;cur_mask=0;cur_from_fifo=0;
            end
        end else begin
            cur_valid = 1'b0; cur_x = 16'd0; cur_y = 16'd0; cur_mask = 1'b0;
            cur_from_fifo = 1'b0;
        end
    end

    wire new_frame = cur_valid && seen_any && (cur_y < prow);
    wire new_row   = cur_valid && seen_any && !new_frame && (cur_y != prow);

    wire fifo_consume = (state==ST_IDLE) && cur_valid && cur_from_fifo;
    wire fifo_re = (sf_cnt!=0) && (!sf_valid || fifo_consume);
    wire must_queue = (state!=ST_IDLE) || end_pending || pend_valid || sf_valid || (sf_cnt!=0);
    wire fifo_we = in_valid && must_queue && ((sf_cnt<SF_DEPTH) || fifo_re);
    // Memory has no asynchronous reset. Reset invalidates pointers and cache.
    always @(posedge clk) begin
        if(rst_n && fifo_we) sf[sf_wr] <= {1'b1,in_x,in_y,in_mask};
        if(rst_n && fifo_re) sf_data <= sf[sf_rd];
    end

    // 结算输出区
    reg [15:0] out_x1 [0:MAX_LABEL-1];
    reg [15:0] out_y1 [0:MAX_LABEL-1];
    reg [15:0] out_x2 [0:MAX_LABEL-1];
    reg [15:0] out_y2 [0:MAX_LABEL-1];
    reg [15:0] out_cnt[0:MAX_LABEL-1];
    reg [5:0] out_n;
    reg [5:0] collect_k;
    reg [5:0] out_k;

    integer i, j;
    reg [4:0] lj, lo, hi;
    reg hit;

    // 组合优先编码每拍只选择一个空闲标签。
    reg [4:0] first_free_lbl;
    reg       first_free_valid;
    integer kk;
    always @(*) begin
        first_free_valid = 1'b0; first_free_lbl = 4'd0;
        for (kk = 0; kk < MAX_LABEL; kk = kk + 1) begin
            if (!used[kk] && !first_free_valid) begin
                first_free_lbl = kk[4:0]; first_free_valid = 1'b1;
            end
        end
    end

    // ST_IDLE 按同行、换行、换帧三种关闭原因锁存游程，并进入 ST_MATCH。

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            run_open <= 1'b0; rs <= 16'd0; prow <= 16'd0; px <= 16'd0;
            seen_any <= 1'b0;
            end_pending<=0;finishing_end<=0;o_done<=0;
            o_valid <= 1'b0; o_x1 <= 0; o_y1 <= 0; o_x2 <= 0; o_y2 <= 0;
            o_cnt <= 0; o_id <= 0; o_last <= 1'b0;
            pr_n <= 0; cr_n <= 0;
            sf_wr <= 0; sf_rd <= 0; sf_cnt <= 0; sf_valid <= 0; fifo_overflow <= 1'b0; o_overflow <= 1'b0;
            mk <= 0; mroot <= 4'h0; mfound <= 1'b0;
            close_s <= 0; close_e <= 0; close_row <= 0; close_type <= CL_SAME;
            pend_valid <= 1'b0; pend_x <= 0; pend_y <= 0; pend_mask <= 1'b0;
            out_n = 0; out_k = 0; collect_k<=0;
            for (i = 0; i < MAX_LABEL; i = i + 1) begin
                parent[i] <= i[4:0]; used[i] <= 1'b0; lab_cnt[i] <= 16'd0;
                lab_mnx[i] <= 16'hFFFF; lab_mny[i] <= 16'hFFFF;
                lab_mxx[i] <= 16'd0;    lab_mxy[i] <= 16'd0;
            end
        end else begin
            // 默认：输出总线空闲
            o_valid <= 1'b0;
            o_last  <= 1'b0;
            o_done  <= 1'b0;

            // 依据 fifo_we/fifo_re 统一更新指针和占用数，同时读写时计数保持不变。
            if (fifo_we) begin
                sf_wr <= (sf_wr == SF_DEPTH-1) ? 0 : sf_wr + 1'b1;
            end
            if (fifo_re) begin
                sf_rd <= (sf_rd == SF_DEPTH-1) ? 0 : sf_rd + 1'b1;
            end
            case ({fifo_we,fifo_re})
              2'b10: sf_cnt<=sf_cnt+1'b1;
              2'b01: sf_cnt<=sf_cnt-1'b1;
              default: sf_cnt<=sf_cnt;
            endcase
            if(fifo_re) sf_valid<=1;
            else if(fifo_consume) sf_valid<=0;
            // 输入无法写入 FIFO 时锁存溢出标志。
            if (new_frame || (cur_valid && !seen_any)) fifo_overflow <= 1'b0;
            if (in_valid && must_queue && !fifo_we) fifo_overflow <= 1'b1;
            o_overflow <= fifo_overflow;

            case (state)
                // ST_IDLE: 正常流式
                ST_IDLE: begin
                    if (end_pending) begin
                        end_pending<=0;finishing_end<=1;
                        if(run_open)begin
                            close_s<=rs;close_e<=px;close_row<=prow;
                            close_type<=CL_FRAME;mk<=0;mroot<=5'h1F;mfound<=0;
                            state<=ST_MATCH;
                        end else begin collect_k<=0;out_n=0;out_k=0;state<=ST_COLLECT;end
                    end else if (cur_valid) begin
                        seen_any <= 1'b1;
                        if(END_X>=0 && END_Y>=0 && cur_x==END_X && cur_y==END_Y)
                            end_pending<=1;

                        // 帧边界
                        if (new_frame) begin
                            finishing_end<=0;
                            if (run_open) begin
                                // 末行有未闭合游程 → 触发匹配
                                close_s <= rs; close_e <= px; close_row <= prow;
                                close_type <= CL_FRAME;
                                mk <= 0; mroot <= 5'h1F; mfound <= 1'b0;
                                state <= ST_MATCH;
                                // 当前样本（新帧第一行）pending
                                pend_valid <= 1'b1;
                                pend_x <= cur_x; pend_y <= cur_y; pend_mask <= cur_mask;
                                // 出队（若来自 FIFO）
                                // 出队由 fifo_re 统一处理。
                            end else begin
                                // Retain boundary sample while serial frame finalization runs.
                                pend_valid<=1;pend_x<=cur_x;pend_y<=cur_y;pend_mask<=cur_mask;
                                collect_k<=0;out_n=0;out_k=0;state<=ST_COLLECT;
                            end
                        end
                        // 行边界
                        else if (new_row) begin
                            if (run_open) begin
                                close_s <= rs; close_e <= px; close_row <= prow;
                                close_type <= CL_ROW;
                                mk <= 0; mroot <= 5'h1F; mfound <= 1'b0;
                                state <= ST_MATCH;
                                pend_valid <= 1'b1;
                                pend_x <= cur_x; pend_y <= cur_y; pend_mask <= cur_mask;
                                // 出队由 fifo_re 统一处理。
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
                                // 出队由 fifo_re 统一处理。
                            end
                        end
                        // 同行
                        else begin
                            if (cur_mask && !run_open) begin
                                // 游程开始
                                run_open <= 1'b1;
                                rs <= cur_x;
                                px <= cur_x;
                                // 出队由 fifo_re 统一处理。
                            end else if (!cur_mask && run_open) begin
                                // 游程关闭 → 触发匹配（当前样本是 !mask，已处理 px）
                                close_s <= rs; close_e <= px; close_row <= prow;
                                close_type <= CL_SAME;
                                mk <= 0; mroot <= 5'h1F; mfound <= 1'b0;
                                state <= ST_MATCH;
                                px <= cur_x;
                                pend_valid <= 1'b0;  // CL_SAME 闭合后清除已消费的 pending 样本。
                                // 出队由 fifo_re 统一处理。
                            end else begin
                                // 正常（mask&&run_open 或 !mask&&!run_open）
                                px <= cur_x;
                                // 出队由 fifo_re 统一处理。
                            end
                            // 每个有效样本都更新行坐标，供后续边界判断使用。
                            prow <= cur_y;
                        end
                    end
                end

                // ST_MATCH: 串行匹配
                ST_MATCH: begin
                    if (mk < pr_n) begin
                        // 每拍判断一个游程的区间重叠，并排除无效标签 5'h1F。
                        hit = (pr_lab[mk] != 5'h1F) &&
                              (pr_s[mk] <= close_e) && (pr_e[mk] >= close_s);
                        if (hit) begin
                            lj = pr_lab[mk];
                            if (!mfound) begin
                                mroot <= lj; mfound <= 1'b1;
                            end else if (lj != mroot) begin
                                // 合并：小 id 吸收大 id
                                if (mroot < lj) begin lo = mroot; hi = lj; end
                                else            begin lo = lj;    hi = mroot; end
                                // Canonicalize every live alias before hi is made reusable.
                                // Run labels always name roots; no parent chain survives a merge.
                                for (j=0;j<MAX_RUN;j=j+1) begin
                                    if(pr_lab[j]==hi) pr_lab[j]<=lo;
                                    if(cr_lab[j]==hi) cr_lab[j]<=lo;
                                end
                                for (j=0;j<MAX_LABEL;j=j+1)
                                    if(parent[j]==hi) parent[j]<=lo;
                                parent[hi] <= lo;
                                if (lab_mnx[hi] < lab_mnx[lo]) lab_mnx[lo] <= lab_mnx[hi];
                                if (lab_mny[hi] < lab_mny[lo]) lab_mny[lo] <= lab_mny[hi];
                                if (lab_mxx[hi] > lab_mxx[lo]) lab_mxx[lo] <= lab_mxx[hi];
                                if (lab_mxy[hi] > lab_mxy[lo]) lab_mxy[lo] <= lab_mxy[hi];
                                lab_cnt[lo] <= sat_add(lab_cnt[lo],{1'b0,lab_cnt[hi]});
                                lab_cnt[hi] <= 16'd0; used[hi] <= 1'b0;
                                mroot <= lo;
                            end
                        end
                        mk <= mk + 6'd1;
                    end else begin
                        state <= ST_ALLOC;
                    end
                end

                // ST_ALLOC: 分配/更新标签 + 写当前行表
                ST_ALLOC: begin
                    if (!mfound) begin
                        // 使用组合优先编码结果分配一个新标签。
                        if (first_free_valid) begin
                            parent[first_free_lbl] <= first_free_lbl;
                            used[first_free_lbl] <= 1'b1;
                            lab_mnx[first_free_lbl] <= close_s;
                            lab_mny[first_free_lbl] <= close_row;
                            lab_mxx[first_free_lbl] <= close_e;
                            lab_mxy[first_free_lbl] <= close_row;
                            lab_cnt[first_free_lbl] <= sat_add(16'd0,{1'b0,close_e}-{1'b0,close_s}+17'd1);
                            mroot <= first_free_lbl; mfound <= 1'b1;
                        end
                        // else 标签表满，丢弃（见头部限制说明）
                    end else begin
                        // 更新 mroot 的 bbox + cnt
                        if (close_s   < lab_mnx[mroot]) lab_mnx[mroot] <= close_s;
                        if (close_row < lab_mny[mroot]) lab_mny[mroot] <= close_row;
                        if (close_e   > lab_mxx[mroot]) lab_mxx[mroot] <= close_e;
                        if (close_row > lab_mxy[mroot]) lab_mxy[mroot] <= close_row;
                        lab_cnt[mroot] <= sat_add(lab_cnt[mroot],{1'b0,close_e}-{1'b0,close_s}+17'd1);
                    end
                    // 写当前行表
                    if (cr_n < MAX_RUN) begin
                        cr_s[cr_n] <= close_s; cr_e[cr_n] <= close_e;
                        // 记录本拍生效的标签：已有根、新分配标签或无效标记。
                        cr_lab[cr_n] <= mfound ? mroot :
                                         (first_free_valid ? first_free_lbl : 5'h1F);
                        cr_n <= cr_n + 6'd1;
                    end
                    state <= ST_FINISH;
                end

                // ST_FINISH: 收尾（按 close_type 分发）
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
                            collect_k<=0;out_n=0;out_k=0;state<=ST_COLLECT;
                        end
                        default: state <= ST_IDLE;
                    endcase
                end

                ST_COLLECT: begin
                    if(collect_k<MAX_LABEL)begin
                        if(used[collect_k] && parent[collect_k]==collect_k &&
                           lab_cnt[collect_k]>=MIN_CNT &&
                           lab_mnx[collect_k]<=lab_mxx[collect_k] && lab_mny[collect_k]<=lab_mxy[collect_k])begin
                            out_x1[out_n]<=lab_mnx[collect_k];out_y1[out_n]<=lab_mny[collect_k];
                            out_x2[out_n]<=lab_mxx[collect_k];out_y2[out_n]<=lab_mxy[collect_k];
                            out_cnt[out_n]<=lab_cnt[collect_k];out_n=out_n+1'b1;
                        end
                        collect_k<=collect_k+1'b1;
                    end else begin out_k=0;state<=ST_PUBLISH;end
                end
                ST_PUBLISH: if(out_k==out_n)begin o_done<=1;collect_k<=0;state<=ST_CLEAR;end
                ST_CLEAR: begin
                    if(collect_k<MAX_LABEL)begin
                        parent[collect_k]<=collect_k;used[collect_k]<=0;lab_cnt[collect_k]<=0;
                        lab_mnx[collect_k]<=16'hffff;lab_mny[collect_k]<=16'hffff;
                        lab_mxx[collect_k]<=0;lab_mxy[collect_k]<=0;collect_k<=collect_k+1'b1;
                    end else begin
                        pr_n<=0;cr_n<=0;pend_valid<=0;state<=ST_IDLE;
                        if(finishing_end)begin
                            seen_any<=0;run_open<=0;finishing_end<=0;
                        end else begin
                            prow<=pend_y;px<=pend_x;run_open<=pend_mask;rs<=pend_x;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase

            // 输出：把结算列表逐拍发出去
            if (state==ST_PUBLISH && out_k < out_n) begin
                o_valid <= 1'b1;
                o_x1  <= out_x1[out_k];
                o_y1  <= out_y1[out_k];
                o_x2  <= out_x2[out_k];
                o_y2  <= out_y2[out_k];
                o_cnt <= out_cnt[out_k];
                o_id  <= {2'b00,out_k};
                o_last <= (out_k == out_n - 1);
                out_k = out_k + 1;
            end
        end
    end

endmodule
