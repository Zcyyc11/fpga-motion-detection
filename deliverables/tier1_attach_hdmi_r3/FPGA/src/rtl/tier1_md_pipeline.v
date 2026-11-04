`timescale 1ns / 1ps
// tier1_md_pipeline：视频运动目标检测、叠加显示及元数据输出流水线。
// INPUT_SEL 选择内部测试图案或外部 HDMI 灰度视频。
// 数据路径：2×2 求和、帧缓存、差分、阈值分割、两级滤波、连通域包围盒及叠加。
// 算法基线参考原项目材料中的“参考作品 #1”；阈值、背景模式和滤波方式由参数配置。
// BG_FRAC_BITS 控制定点背景的小数位数，FILTER_MODE 选择开运算或多数滤波。
// 目标流另经 track、alarm 和 uart_tx 输出跟踪及告警元数据。
// INCLUDE_PS 控制参数寄存器和跨时钟快照接口的生成。
module tier1_md_pipeline #(
    // 视频时序（默认 720p60：像素时钟 74.25 MHz，H/V 同步正极性）
    parameter integer H_ACTIVE = 1280,
    parameter integer V_ACTIVE = 720,
    parameter integer H_FP     = 110,
    parameter integer H_SYNC   = 40,
    parameter integer H_BP     = 220,
    parameter integer V_FP     = 5,
    parameter integer V_SYNC   = 5,
    parameter integer V_BP     = 20,
    parameter integer SYNC_POS = 1,
    // 内部合成激励（参数与 data/golden/make_test_clip.py 对齐）
    parameter integer OBJ_W    = 160,
    parameter integer OBJ_H    = 120,
    parameter integer X0       = 60,
    parameter integer Y0       = 300,
    parameter integer DX       = 16,
    // 算法参数
    parameter integer THRESH   = 70,     // 2×2 和域阈值，默认值源于参考作品 #1
    parameter integer SHIFT    = 6,      // 背景更新 α = 1/2^SHIFT
    parameter integer MODE_BG  = 0,      // 0 = 帧差法／1 = 背景建模
    parameter integer MIN_CNT  = 64,     // 包围盒面积门限（大像素个数）
    parameter integer INPUT_SEL = 0,     // 0 = 内部测试图案／1 = 外部 HDMI 输入
    // 跟踪、告警与回传配置
    parameter integer INCLUDE_PS   = 0,  // 1 = 例化 regs+bbox_snapshot（接 AXI）；0 = 纯 PL
    parameter integer UART_BAUD_DIV = 645, // uart_tx 分频：74.25MHz/115200 ≈ 645
    parameter integer LINE_X_DEFAULT = 640, // INCLUDE_PS=0 时的警戒线（大像素域）
    parameter integer BG_FRAC_BITS = 0,
    parameter integer BG_FG_SHIFT = 10,
    parameter integer DWELL_DEFAULT  = 90,   // INCLUDE_PS=0 时的停留告警帧数
    parameter integer FILTER_MODE = 0       // 0=开运算；1=两级多数滤波
)(
    input  wire        clk,
    input  wire        rst_n,
    // HDMI 输入视频流（INPUT_SEL=1 时使用；0 时悬空，综合会优化掉）
    input  wire        rx_de,
    input  wire        rx_hs,
    input  wire        rx_vs,
    input  wire        rx_sof,
    input  wire [15:0] rx_x,
    input  wire [15:0] rx_y,
    input  wire [7:0]  rx_gray,
    // 输出视频（像素坐标，已叠加包围盒）
    output wire        vde,
    output wire [15:0] vx,
    output wire [15:0] vy,
    output wire        vhs,          // 行同步（极性由 SYNC_POS 决定；上板送 rgb2dvi）
    output wire        vvs,          // 场同步
    output wire [7:0]  vr,
    output wire [7:0]  vg,
    output wire [7:0]  vb,
    // 检测结果（大像素坐标，帧边界更新，描述上一帧）
    output wire [15:0] b_x1,
    output wire [15:0] b_y1,
    output wire [15:0] b_x2,
    output wire [15:0] b_y2,
    output wire [15:0] b_cnt,
    output wire        b_valid,
    output wire [7:0]  b_obj_count,   // 上一帧目标数（多目标）
    // 掩码流（大像素坐标，供仿真可视化/探针）
    output wire        m_valid,
    output wire [15:0] m_x,
    output wire [15:0] m_y,
    output wire        m_bit,
    // 当前帧号（自测 = pattern_gen 的；HDMI = 外部 sof 计帧）
    output wire [15:0] frame_idx,
    // UART 元数据输出
    output wire        uart_txd,         // 板→PC 回传（115200-8-N-1）
    output wire        uart_drop,        // UART FIFO 满丢包脉冲（STATUS bit31 粘存源）
    output wire        alarm_evt,        // 自本帧 frame_tick 起发生过告警（粘存，LED/探针）
    // PS/AXI 钟域（INCLUDE_PS=1 时使用；0 时悬空，综合优化掉）
    input  wire        clk_axi,          // AXI-Lite 时钟（PS FCLK，PYNQ 上 100MHz）
    input  wire        rst_n_axi,
    // 寄存器总线的 ps_en/we/addr/wdata 由桥接模块驱动，
    // ps_rdata 是 regs 读寄存输出（输出，桥在脉冲后 1 拍采样）
    input  wire        ps_en,
    input  wire        ps_we,
    input  wire [5:0]  ps_addr,          // 6 位字节地址，范围 0x00..0x34
    input  wire [31:0] ps_wdata,
    output wire [31:0] ps_rdata
);

    localparam integer BW = H_ACTIVE / 2;      // 大像素宽 640
    localparam integer BH = V_ACTIVE / 2;      // 大像素高 360
    localparam integer AW = $clog2(BW * BH);   // 帧缓存地址位宽 18

    localparam integer FW=10+BG_FRAC_BITS;

    // 时序
    // 自测模式用内部 video_timing 生成；HDMI 输入模式用外部恢复的同步信号。
    // INPUT_SEL 为编译期参数，综合时保留选中的输入路径。
    wire        i_hs, i_vs, i_de, i_sof;
    wire [15:0] i_x, i_y;

    video_timing #(
        .H_ACTIVE(H_ACTIVE), .H_FP(H_FP), .H_SYNC(H_SYNC), .H_BP(H_BP),
        .V_ACTIVE(V_ACTIVE), .V_FP(V_FP), .V_SYNC(V_SYNC), .V_BP(V_BP),
        .SYNC_POS(SYNC_POS)
    ) u_timing (
        .clk(clk), .rst_n(rst_n),
        .hs(i_hs), .vs(i_vs), .de(i_de), .x(i_x), .y(i_y), .sof(i_sof)
    );

    wire        hs  = INPUT_SEL ? rx_hs  : i_hs;
    wire        vs  = INPUT_SEL ? rx_vs  : i_vs;
    wire        de  = INPUT_SEL ? rx_de  : i_de;
    wire        sof = INPUT_SEL ? rx_sof : i_sof;
    wire [15:0] x   = INPUT_SEL ? rx_x   : i_x;
    wire [15:0] y   = INPUT_SEL ? rx_y   : i_y;

    // 激励
    // 自测模式由 pattern_gen 与内部时序生成画面；
    // HDMI 输入模式接收板级 dvi2rgb、hdmi_in_ctrl 和 gray_conv 提供的灰度流。
    wire        g_vde;
    wire [15:0] g_x, g_y;
    wire [7:0]  g_pix;
    wire [15:0] pat_frame_idx;

    pattern_gen #(
        .H_ACTIVE(H_ACTIVE), .V_ACTIVE(V_ACTIVE),
        .OBJ_W(OBJ_W), .OBJ_H(OBJ_H), .X0(X0), .Y0(Y0), .DX(DX)
    ) u_pat (
        .clk(clk), .rst_n(rst_n),
        .sof(i_sof), .de(i_de), .x(i_x), .y(i_y),
        .vde(g_vde), .x_o(g_x), .y_o(g_y), .pixel(g_pix),
        .frame_idx(pat_frame_idx)
    );

    // 编译期选择像素源
    wire        p_vde = INPUT_SEL ? rx_de   : g_vde;
    wire [15:0] p_x   = INPUT_SEL ? rx_x    : g_x;
    wire [15:0] p_y   = INPUT_SEL ? rx_y    : g_y;
    wire [7:0]  p_pix = INPUT_SEL ? rx_gray : g_pix;
    wire frame_tick;

    // 2×2 压缩
    wire        d_valid;
    wire [15:0] bx, by;
    wire [9:0]  bpx;

    downsample2x2 #(.H_ACTIVE(H_ACTIVE)) u_ds (
        .clk(clk), .rst_n(rst_n),
        .vde(p_vde), .x(p_x), .y(p_y), .pixel(p_pix),
        .valid(d_valid), .big_x(bx), .big_y(by), .big_pixel(bpx)
    );

    // 帧缓存
    wire [AW-1:0] addr = by * BW[15:0] + bx;

    reg  [AW-1:0] addr_d1, addr_d2;
    reg           valid_d1, valid_d2;
    reg  [9:0]    cur_d1;
    reg  [15:0]   bx_d2, by_d2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_d1 <= {AW{1'b0}}; addr_d2 <= {AW{1'b0}};
            valid_d1 <= 1'b0;      valid_d2 <= 1'b0;
            cur_d1   <= 10'd0;
            bx_d2    <= 16'd0;     by_d2    <= 16'd0;
        end else begin
            addr_d1  <= addr;      addr_d2  <= addr_d1;
            valid_d1 <= d_valid;   valid_d2 <= valid_d1;
            cur_d1   <= bpx;
            bx_d2    <= bx;        by_d2    <= by;
        end
    end

    // 差分
    // I4 运行时参数（像素钟域）：INCLUDE_PS=1 来自 regs 过 2FF 同步；=0 编译期直通
    wire [15:0] cfg_thresh;
    wire [4:0]  cfg_shift;
    wire        cfg_enable;
    wire [10:0] cfg_line_x;
    wire [15:0] cfg_dwell;

    wire [FW-1:0] ref_px;              // 读出的旧值（上一帧 / 背景图）
    wire [10:0] absdiff;
    wire [FW-1:0] wr_data;
    reg [FW-1:0] wr_data_r;

    // 外部输入帧号按有效图像 frame_tick 递增，内部图案使用 pattern_gen 的帧号。
    reg [15:0] frame_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)   frame_cnt <= 16'd0;
        else if (frame_tick) frame_cnt <= frame_cnt + 16'd1;
    end
    wire [15:0] fid = INPUT_SEL ? frame_cnt : pat_frame_idx;

    // 掩码阶段使用粘存标志，避免 16 位帧号回绕时重新触发背景初始化。
    reg mask_phase;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          mask_phase <= 1'b0;
        else if (fid == 16'd2) mask_phase <= 1'b1;
    end
    wire init_phase = (fid <= 16'd1) & ~mask_phase;   // 首帧：缓存直接写当前帧

    wire fb_write_valid;
    wire [AW-1:0] fb_write_addr;
    wire [FW-1:0] fb_write_data;
    generate if(BG_FRAC_BITS==0) begin : g_legacy_background
    assign fb_write_valid=valid_d2;
    assign fb_write_addr=addr_d2;
    assign fb_write_data=wr_data_r;

    diff_stage #() u_diff (
        .mode_bg(cfg_enable),    // 算法模式：g_nops=编译期 MODE_BG[0]；g_ps=regs 0x14 ENABLE 运行时切帧差/背景建模
        .init_phase(init_phase),
        .shift_amt(cfg_shift),
        .cur(cur_d1),
        .ref_px(ref_px),
        .absdiff(absdiff),
        .wr_data(wr_data)
    );

    end else begin : g_fixed_background
        background_fixed #(.FRAC_BITS(BG_FRAC_BITS),.FG_SHIFT(BG_FG_SHIFT)) u_diff (
            .mode_bg(cfg_enable),.init_phase(init_phase),.shift_amt(cfg_shift),
            .thresh(cfg_thresh),.cur(cur_d1),.ref_px(ref_px),.absdiff(absdiff),.wr_data());
        background_fixed_pipe #(.FRAC_BITS(BG_FRAC_BITS),.FG_SHIFT(BG_FG_SHIFT),.AW(AW)) u_update (
            .clk(clk),.rst_n(rst_n),.in_valid(valid_d1),.in_addr(addr_d1),
            .mode_bg(cfg_enable),.init_phase(init_phase),.shift_amt(cfg_shift),
            .thresh(cfg_thresh),.cur(cur_d1),.ref_px(ref_px),
            .out_valid(fb_write_valid),.out_addr(fb_write_addr),.wr_data(wr_data));
        assign fb_write_data=wr_data;
    end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) wr_data_r <= 10'd0;
        else        wr_data_r <= wr_data;
    end

    frame_buf #(.DEPTH(BW * BH), .AW(AW), .DW(FW)) u_fb (
        .clk(clk),
        .re(d_valid),   .raddr(addr),     .dout(ref_px),
        .we(fb_write_valid), .waddr(fb_write_addr), .din(fb_write_data)
    );

    // 阈值
    // 首帧不出掩码（帧差模式下没有「上一帧」可比，背景模式还在初始化）
    wire mask_en = (fid >= 16'd2) | mask_phase;        // 回绕后仍保持掩码开启
    wire t_valid, t_mask;

    threshold #() u_th (
        .clk(clk), .rst_n(rst_n),
        .thresh(cfg_thresh),
        .in_valid(valid_d1 && mask_en),
        .absdiff(absdiff),
        .out_valid(t_valid), .mask(t_mask)
    );

    // 二值滤波
    wire        o_valid;
    wire [15:0] o_x, o_y;
    wire        o_bit;

    morph_open #(.W(BW),.FILTER_MODE(FILTER_MODE)) u_mo (
        .clk(clk), .rst_n(rst_n),
        .in_valid(t_valid), .in_x(bx_d2), .in_y(by_d2), .in_mask(t_mask),
        .o_valid(o_valid), .o_x(o_x), .o_y(o_y), .o_mask(o_bit)
    );

    // 多目标包围盒
    wire        mb_valid;
    wire [15:0] t_x1, t_y1, t_x2, t_y2, t_cnt;
    wire [7:0]  t_id;
    wire        t_last;
    wire        mb_done;

    multi_bbox #(.MIN_CNT(MIN_CNT),.END_X(BW-3),.END_Y(BH-3)) u_mbb (
        .clk(clk), .rst_n(rst_n),
        .in_valid(o_valid), .in_x(o_x), .in_y(o_y), .in_mask(o_bit),
        .o_valid(mb_valid), .o_x1(t_x1), .o_y1(t_y1), .o_x2(t_x2), .o_y2(t_y2),
        .o_cnt(t_cnt), .o_id(t_id), .o_last(t_last),.o_done(mb_done)
    );

    // 掩码流帧首仅用于源帧标签；显示发布使用真实图像 frame_tick。
    reg [15:0] m_y_prev;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)  m_y_prev <= 16'hFFFF;
        else if (o_valid) m_y_prev <= o_y;
    end
    wire f_edge = o_valid && (o_y < m_y_prev);
    // Tag each input mask frame with the unchanged public source counter.
    // Two slots cover current input + preceding CCL finalization at wrap fallback.
    // Assumes bounded backlog: at most two input frames await CCL completion.
    // FIFO overflow / sustained over-service-rate input is not a valid stream.
    reg [15:0] bbox_source_tags[0:1];
    reg tag_wr,tag_rd;
    reg [15:0] completed_source_frame,snapshot_source_frame;
    wire bbox_published;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            tag_wr<=0;tag_rd<=0;bbox_source_tags[0]<=0;bbox_source_tags[1]<=0;
            completed_source_frame<=0;snapshot_source_frame<=0;
        end else begin
            if(f_edge)begin bbox_source_tags[tag_wr]<=fid;tag_wr<=~tag_wr;end
            if(mb_done)begin completed_source_frame<=bbox_source_tags[tag_rd];tag_rd<=~tag_rd;end
            if(frame_tick)snapshot_source_frame<=completed_source_frame;
        end
    end

    // 叠加显示（多目标）
    overlay_multi #() u_ovm (
        .clk(clk), .rst_n(rst_n),
        .de(p_vde), .x(p_x), .y(p_y), .gray(p_pix),
        .f_edge(frame_tick),
        .t_valid(mb_valid), .t_x1(t_x1), .t_y1(t_y1), .t_x2(t_x2), .t_y2(t_y2),
        .t_cnt(t_cnt), .t_last(t_last),.t_done(mb_done),.o_published(bbox_published),
        .r(vr), .g(vg), .b(vb),
        .o_x1(b_x1), .o_y1(b_y1), .o_x2(b_x2), .o_y2(b_y2), .o_cnt(b_cnt),
        .o_valid(b_valid), .o_obj_count(b_obj_count)
    );

    // 回传元数据链
    // multi_bbox 目标流（I3）→ track（持续 id）→ alarm（越界/停留）→ uart_tx（打包回传）
    // 跟踪与回传路径和叠加显示路径并行。
    //
    // Frame boundary follows accepted active pixels, independent of VS polarity.
    // Update y history only on DE: blanking coordinates must not create ticks.
    // An initial top-left pixel opens the first frame; partial startup waits for wrap.
    reg pixel_seen;
    reg [15:0] pixel_y_prev;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_seen <= 1'b0;
            pixel_y_prev <= 16'd0;
        end else if (p_vde) begin
            pixel_seen <= 1'b1;
            pixel_y_prev <= p_y;
        end
    end
    assign frame_tick = p_vde && (pixel_seen ? (p_y < pixel_y_prev) :
                                               ((p_x == 0) && (p_y == 0)));

    wire        tk_valid, tk_last, tk_done;
    wire [7:0]  tk_id;
    wire [15:0] tk_x1, tk_y1, tk_x2, tk_y2, tk_dwell;

    track u_trk (
        .clk(clk), .rst_n(rst_n),
        .t_valid(mb_valid), .t_id(t_id),           // 输入 id 被忽略，输出持续 id
        .t_x1(t_x1), .t_y1(t_y1), .t_x2(t_x2), .t_y2(t_y2), .t_last(t_last),
        .frame_tick(frame_tick),
        .o_valid(tk_valid), .o_id(tk_id),
        .o_x1(tk_x1), .o_y1(tk_y1), .o_x2(tk_x2), .o_y2(tk_y2),
        .o_dwell(tk_dwell), .o_last(tk_last),.o_done(tk_done)
    );

    wire        al_valid;
    wire [7:0]  al_id;
    wire [1:0]  al_type;
    wire [15:0] al_cx;

    alarm u_alm (
        .clk(clk), .rst_n(rst_n),
        .LINE_X({5'd0, cfg_line_x}),               // 11 位警戒线零扩展到 16 位
        .DWELL(cfg_dwell),
        .t_valid(tk_valid), .t_id(tk_id),
        .t_x1(tk_x1), .t_y1(tk_y1), .t_x2(tk_x2), .t_y2(tk_y2), .t_dwell(tk_dwell),
        .a_valid(al_valid), .a_id(al_id), .a_type(al_type), .a_cx(al_cx)
    );

    uart_tx #(.BAUD_DIV(UART_BAUD_DIV)) u_utx (
        .clk(clk), .rst_n(rst_n),
        .s_valid(tk_valid), .s_id(tk_id),
        .s_x1(tk_x1), .s_y1(tk_y1), .s_x2(tk_x2), .s_y2(tk_y2),
        .e_valid(al_valid), .e_id(al_id), .e_type(al_type), .e_cx(al_cx),
        .frame_tick(frame_tick),
        .tx(uart_txd), .drop(uart_drop)
    );

    // 本帧告警粘存（LED/探针用；frame_tick 清零）
    reg alarm_sticky;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)            alarm_sticky <= 1'b0;
        else if (frame_tick)   alarm_sticky <= 1'b0;
        else if (al_valid)     alarm_sticky <= 1'b1;
    end
    assign alarm_evt = alarm_sticky;

    // A snapshot waits for this display batch's tracker/alarm to settle.
    // Each normal video window has one explicit CCL completion, including empty.
    // Reject ambiguous late/multiple batches instead of attributing their alarm
    // to the displayed frame. Public snapshot then retains its previous frame.
    reg [1:0] track_batch_count;
    reg track_batch_unique,snapshot_armed;
    reg track_batch_open,track_window_dirty;
    reg latch_fire;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latch_fire <= 1'b0;
            track_batch_count<=0;track_batch_unique<=0;snapshot_armed<=0;
            track_batch_open<=0;track_window_dirty<=0;
        end else begin
            latch_fire<=0;
            if(mb_valid)track_batch_open<=1;
            if(mb_done)track_batch_open<=0;
            if(frame_tick)begin
                track_batch_unique<=(track_batch_count==1)&&!mb_done&&
                    !mb_valid&&!track_batch_open&&!track_window_dirty;
                track_batch_count<=0;snapshot_armed<=0;
                // Invalidate both halves of any batch crossing the boundary.
                track_window_dirty<=track_batch_open||mb_valid||mb_done;
            end else if(mb_done && track_batch_count!=3)
                track_batch_count<=track_batch_count+1'b1;
            if(bbox_published && track_batch_unique)snapshot_armed<=1;
            if(tk_done && snapshot_armed)begin
                latch_fire<=1;snapshot_armed<=0;
            end
        end
    end
    wire snap_latch = latch_fire;

    // ⑪ I4 参数通路 + PS/AXI 域
    generate
        if (INCLUDE_PS != 0) begin : g_ps
            // regs（AXI 钟域）
            wire [15:0] r_thresh, r_thresh_rel, r_dwell;
            wire [4:0]  r_shift;
            wire [10:0] r_line_x;
            wire        r_enable;
            // bbox 快照（AXI 钟域稳定副本）
            wire [15:0] s_x1q, s_y1q, s_x2q, s_y2q, s_cntq, s_frameq;
            wire        s_validq, s_bvalidq, s_alarmq;
            wire [7:0]  s_objq;
            // uart drop：像素→AXI 2FF 同步
            reg drop_q1, drop_q2;
            always @(posedge clk_axi or negedge rst_n_axi)
                if (!rst_n_axi) {drop_q1, drop_q2} <= 2'b00;
                else            {drop_q1, drop_q2} <= {uart_drop, drop_q1};

            bbox_snapshot #(.EXPLICIT_ALARM_CLEAR(1)) u_snap (
                .clk_px(clk), .rst_n_px(rst_n),
                .i_x1(b_x1), .i_y1(b_y1), .i_x2(b_x2), .i_y2(b_y2), .i_cnt(b_cnt),
                .i_valid(b_valid),
                .i_frame_idx(snapshot_source_frame), .i_obj_count(b_obj_count), .i_alarm_pulse(al_valid),
                .i_latch(snap_latch),.i_alarm_clear(frame_tick),
                .clk_axi(clk_axi), .rst_n_axi(rst_n_axi),
                .o_x1(s_x1q), .o_y1(s_y1q), .o_x2(s_x2q), .o_y2(s_y2q), .o_cnt(s_cntq),
                .o_valid(s_validq), .o_frame(s_frameq), .o_obj_count(s_objq),
                .o_b_valid(s_bvalidq), .o_alarm(s_alarmq)
            );

            regs u_regs (
                .clk(clk_axi), .rst_n(rst_n_axi),
                .ps_en(ps_en), .ps_we(ps_we), .ps_addr(ps_addr),
                .ps_wdata(ps_wdata), .ps_rdata(ps_rdata),
                .o_thresh(r_thresh), .o_thresh_rel(r_thresh_rel),
                .o_alpha_shift(r_shift), .o_line_x(r_line_x),
                .o_dwell(r_dwell), .o_enable(r_enable),
                .i_snap_x1(s_x1q), .i_snap_y1(s_y1q),
                .i_snap_x2(s_x2q), .i_snap_y2(s_y2q), .i_snap_cnt(s_cntq),
                .i_snap_valid(s_validq), .i_snap_frame(s_frameq),
                .i_snap_obj_count(s_objq), .i_snap_b_valid(s_bvalidq),
                .i_snap_alarm(s_alarmq),
                .i_uart_drop(drop_q2)
            );

            // AXI→像素 2FF 同步
            // 复位值取编译期参数（=原行为），regs 时钟起来后被寄存器复位值
            // 覆盖（70/6/0/640/90）。多位总线在「写参数瞬间」可能一拍位间
            // 不一致——配置型信号已知取舍，下拍自愈。
            reg [15:0] thresh_q1,  thresh_q2;
            reg [4:0]  shift_q1,   shift_q2;
            reg        enable_q1,  enable_q2;
            reg [10:0] line_x_q1,  line_x_q2;
            reg [15:0] dwell_q1,   dwell_q2;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    thresh_q1 <= THRESH[15:0];  thresh_q2 <= THRESH[15:0];
                    shift_q1  <= SHIFT[4:0];    shift_q2  <= SHIFT[4:0];
                    enable_q1 <= MODE_BG[0];    enable_q2 <= MODE_BG[0];
                    line_x_q1 <= LINE_X_DEFAULT[10:0]; line_x_q2 <= LINE_X_DEFAULT[10:0];
                    dwell_q1  <= DWELL_DEFAULT[15:0];  dwell_q2  <= DWELL_DEFAULT[15:0];
                end else begin
                    thresh_q1 <= r_thresh;  thresh_q2 <= thresh_q1;
                    shift_q1  <= r_shift;   shift_q2  <= shift_q1;
                    enable_q1 <= r_enable;  enable_q2 <= enable_q1;
                    line_x_q1 <= r_line_x;  line_x_q2 <= line_x_q1;
                    dwell_q1  <= r_dwell;   dwell_q2  <= dwell_q1;
                end
            end
            assign cfg_thresh = thresh_q2;
            assign cfg_shift  = shift_q2;
            assign cfg_enable = enable_q2;
            assign cfg_line_x = line_x_q2;
            assign cfg_dwell  = dwell_q2;
        end else begin : g_nops
            // 纯 PL 构建：编译期参数直通（INCLUDE_PS=0，当前 10/13 bit 用这个）
            assign cfg_thresh = THRESH[15:0];
            assign cfg_shift  = SHIFT[4:0];
            assign cfg_enable = MODE_BG[0];
            assign cfg_line_x = LINE_X_DEFAULT[10:0];
            assign cfg_dwell  = DWELL_DEFAULT[15:0];
            assign ps_rdata   = 32'd0;       // 无 regs：桥读回 0（输入悬空不驱动）
        end
    endgenerate

    assign vde = p_vde;
    assign vx  = p_x;
    assign vy  = p_y;
    assign vhs = hs;
    assign vvs = vs;

    // 探针输出
    // 当前帧号（自测 = pattern_gen 的；HDMI = 外部计帧，与 sof 同步）
    assign frame_idx = INPUT_SEL ? frame_cnt : pat_frame_idx;

    assign m_valid = o_valid;
    assign m_x     = o_x;
    assign m_y     = o_y;
    assign m_bit   = o_bit;

endmodule

