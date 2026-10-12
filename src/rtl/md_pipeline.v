`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// md_pipeline —— 运动目标检测流水线（顶层，不含板级 IO）
//
// 这一份是**整机图**，把五步链按顺序串起来：
//
//   ① 时序      video_timing   → de / x / y / sof
//   ② 激励      pattern_gen    → 复刻 PC 端 make_test_clip.py 的合成片段
//      [上板可换成 HDMI 输入：dvi2rgb → gray → 同一入口]
//   ③ 压缩      downsample2x2  → 8bit 像素 2×2 求和 → 10bit 大像素（省 BRAM 的关键）
//   ④ 缓存      frame_buf      → 存 1 张「大像素图」：帧差模式存上一帧 / 背景模式存背景图
//   ⑤ 差分      diff_stage     → |I − 缓存|（**唯一与参考作品 #1 不同的一步**）
//   ⑥ 阈值      threshold      → >70（照抄 #1 的硬编码值，2×2 和域）
//   ⑦ 形态学    morph_open     → 3×3 开运算去噪
//   ⑧ 包围盒    bbox           → x1/y1/x2/y2 + 面积门限
//   ⑨ 叠加      overlay        → 把框画回画面（这是「看得见」的那一半）
//
// ★ 为什么要在 FPGA 里自己造激励（pattern_gen）而不是先接 HDMI 输入：
//   自测模式**不需要任何输入线**，只要板子 + HDMI 输出线 + 一块屏就能看到
//   「黑底白块被红框框住」。这样「上板/时序/时钟/HDMI 输出」和「算法对不对」
//   这两类问题可以分开定位 —— 出问题时先看灯再查算法，不用同时怀疑三件事。
//
// 流水线延迟（拍数，都在大像素域）：
//   downsample 1 → [延迟 1 拍给 frame_buf 读] → diff 组合 → threshold 1
//   → morph3x3 1 → morph3x3 1 → bbox
//   所以 mask 比大像素晚 3 拍、坐标一路打拍对齐（bx_d2/by_d2）。
// -----------------------------------------------------------------------------
module md_pipeline #(
    // ---- 视频时序（默认 720p60：像素时钟 74.25 MHz，H/V 同步正极性）----
    parameter integer H_ACTIVE = 1280,
    parameter integer V_ACTIVE = 720,
    parameter integer H_FP     = 110,
    parameter integer H_SYNC   = 40,
    parameter integer H_BP     = 220,
    parameter integer V_FP     = 5,
    parameter integer V_SYNC   = 5,
    parameter integer V_BP     = 20,
    parameter integer SYNC_POS = 1,
    // ---- 内部合成激励（参数与 data/golden/make_test_clip.py 对齐）----
    parameter integer OBJ_W    = 160,
    parameter integer OBJ_H    = 120,
    parameter integer X0       = 60,
    parameter integer Y0       = 300,
    parameter integer DX       = 16,
    // ---- 算法参数 ----
    parameter integer THRESH   = 70,     // 2×2 和域阈值（#1 的硬编码值）
    parameter integer SHIFT    = 6,      // 背景更新 α = 1/2^SHIFT
    parameter integer MODE_BG  = 0,      // 0 = 帧差法（v1）／1 = 背景建模（v2）
    parameter integer MIN_CNT  = 64,     // 包围盒面积门限（大像素个数）
    parameter integer INPUT_SEL = 0      // 0 = 内部自测激励／1 = 外部 HDMI 输入（构建定死）
)(
    input  wire        clk,
    input  wire        rst_n,
    // ---- HDMI 输入视频流（INPUT_SEL=1 时使用；0 时悬空，综合会优化掉）----
    input  wire        rx_de,
    input  wire        rx_hs,
    input  wire        rx_vs,
    input  wire        rx_sof,
    input  wire [15:0] rx_x,
    input  wire [15:0] rx_y,
    input  wire [7:0]  rx_gray,
    // ---- 输出视频（像素坐标，已叠加包围盒）----
    output wire        vde,
    output wire [15:0] vx,
    output wire [15:0] vy,
    output wire        vhs,          // 行同步（极性由 SYNC_POS 决定；上板送 rgb2dvi）
    output wire        vvs,          // 场同步
    output wire [7:0]  vr,
    output wire [7:0]  vg,
    output wire [7:0]  vb,
    // ---- 检测结果（大像素坐标，帧边界更新，描述上一帧）----
    output wire [15:0] b_x1,
    output wire [15:0] b_y1,
    output wire [15:0] b_x2,
    output wire [15:0] b_y2,
    output wire [15:0] b_cnt,
    output wire        b_valid,
    output wire [7:0]  b_obj_count,   // 上一帧目标数（多目标）
    // ---- 掩码流（大像素坐标，供仿真可视化/探针）----
    output wire        m_valid,
    output wire [15:0] m_x,
    output wire [15:0] m_y,
    output wire        m_bit,
    // ---- 当前帧号（自测 = pattern_gen 的；HDMI = 外部 sof 计帧）----
    output wire [15:0] frame_idx
);

    localparam integer BW = H_ACTIVE / 2;      // 大像素宽 640
    localparam integer BH = V_ACTIVE / 2;      // 大像素高 360
    localparam integer AW = $clog2(BW * BH);   // 帧缓存地址位宽 18

    // ======================= ① 时序 =======================
    // 自测模式用内部 video_timing 生成；HDMI 输入模式用外部恢复的同步信号。
    // INPUT_SEL 是构建定死的参数，综合后选择退化为直连（不是真 mux，无毛刺问题）。
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

    // ======================= ② 激励 =======================
    // 自测模式：pattern_gen 合成画面（接内部时序，行为与旧版完全一致）；
    // HDMI 输入模式：外部灰度流（board_top 里 dvi2rgb→hdmi_in_ctrl→gray_conv 整理好）。
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

    // 像素源选择（INPUT_SEL 定死 → 综合后直连）
    wire        p_vde = INPUT_SEL ? rx_de   : g_vde;
    wire [15:0] p_x   = INPUT_SEL ? rx_x    : g_x;
    wire [15:0] p_y   = INPUT_SEL ? rx_y    : g_y;
    wire [7:0]  p_pix = INPUT_SEL ? rx_gray : g_pix;

    // ======================= ③ 2×2 压缩 =======================
    wire        d_valid;
    wire [15:0] bx, by;
    wire [9:0]  bpx;

    downsample2x2 #(.H_ACTIVE(H_ACTIVE)) u_ds (
        .clk(clk), .rst_n(rst_n),
        .vde(p_vde), .x(p_x), .y(p_y), .pixel(p_pix),
        .valid(d_valid), .big_x(bx), .big_y(by), .big_pixel(bpx)
    );

    // ======================= ④ 帧缓存 =======================
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

    // ======================= ⑤ 差分 =======================
    wire [9:0]  ref_px;              // 读出的旧值（上一帧 / 背景图）
    wire [10:0] absdiff;
    wire [9:0]  wr_data;
    reg  [9:0]  wr_data_r;

    // 帧号：HDMI 输入没有 pattern_gen 的 frame_idx，统一用 sof 计帧（两种模式都准）。
    reg [15:0] frame_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)   frame_cnt <= 16'd0;
        else if (sof) frame_cnt <= frame_cnt + 16'd1;
    end
    wire [15:0] fid = INPUT_SEL ? frame_cnt : pat_frame_idx;

    // ★ 初始化/掩码门用"已进入掩码阶段"的粘性标志，不依赖 fid 绝对值：
    //   16 位帧号 @60fps ≈ 18.2 分钟会回绕，回绕后 fid 又变 0/1，
    //   若直接用 fid<=1 / fid>=2 判断，运行 18 分钟后背景会重新初始化、掩码消失一帧。
    reg mask_phase;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          mask_phase <= 1'b0;
        else if (fid == 16'd2) mask_phase <= 1'b1;
    end
    wire init_phase = (fid <= 16'd1) & ~mask_phase;   // 首帧：缓存直接写当前帧

    diff_stage #(.SHIFT(SHIFT)) u_diff (
        .mode_bg(MODE_BG[0]),
        .init_phase(init_phase),
        .cur(cur_d1),
        .ref_px(ref_px),
        .absdiff(absdiff),
        .wr_data(wr_data)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) wr_data_r <= 10'd0;
        else        wr_data_r <= wr_data;
    end

    frame_buf #(.DEPTH(BW * BH), .AW(AW)) u_fb (
        .clk(clk),
        .re(d_valid),   .raddr(addr),     .dout(ref_px),
        .we(valid_d2),  .waddr(addr_d2),  .din(wr_data_r)
    );

    // ======================= ⑥ 阈值 =======================
    // 首帧不出掩码（帧差模式下没有「上一帧」可比，背景模式还在初始化）
    wire mask_en = (fid >= 16'd2) | mask_phase;        // 回绕后仍保持掩码开启
    wire t_valid, t_mask;

    threshold #(.THRESH(THRESH)) u_th (
        .clk(clk), .rst_n(rst_n),
        .in_valid(valid_d1 && mask_en),
        .absdiff(absdiff),
        .out_valid(t_valid), .mask(t_mask)
    );

    // ======================= ⑦ 形态学开运算 =======================
    wire        o_valid;
    wire [15:0] o_x, o_y;
    wire        o_bit;

    morph_open #(.W(BW)) u_mo (
        .clk(clk), .rst_n(rst_n),
        .in_valid(t_valid), .in_x(bx_d2), .in_y(by_d2), .in_mask(t_mask),
        .o_valid(o_valid), .o_x(o_x), .o_y(o_y), .o_mask(o_bit)
    );

    // ======================= ⑧ 多目标包围盒（multi_bbox 替代 bbox）=======================
    wire        t_valid;
    wire [15:0] t_x1, t_y1, t_x2, t_y2, t_cnt;
    wire [7:0]  t_id;
    wire        t_last;

    multi_bbox #(.MIN_CNT(MIN_CNT)) u_mbb (
        .clk(clk), .rst_n(rst_n),
        .in_valid(o_valid), .in_x(o_x), .in_y(o_y), .in_mask(o_bit),
        .o_valid(t_valid), .o_x1(t_x1), .o_y1(t_y1), .o_x2(t_x2), .o_y2(t_y2),
        .o_cnt(t_cnt), .o_id(t_id), .o_last(t_last)
    );

    // 掩码流帧边界（检测域 y 回绕，与 multi_bbox 结算同拍）→ overlay_multi 发布用
    reg [15:0] m_y_prev;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)  m_y_prev <= 16'hFFFF;
        else if (o_valid) m_y_prev <= o_y;
    end
    wire f_edge = o_valid && (o_y < m_y_prev);

    // ======================= ⑨ 叠加显示（多目标）=======================
    overlay_multi #() u_ovm (
        .clk(clk), .rst_n(rst_n),
        .de(p_vde), .x(p_x), .y(p_y), .gray(p_pix),
        .f_edge(f_edge),
        .t_valid(t_valid), .t_x1(t_x1), .t_y1(t_y1), .t_x2(t_x2), .t_y2(t_y2),
        .t_cnt(t_cnt), .t_last(t_last),
        .r(vr), .g(vg), .b(vb),
        .o_x1(b_x1), .o_y1(b_y1), .o_x2(b_x2), .o_y2(b_y2), .o_cnt(b_cnt),
        .o_valid(b_valid), .o_obj_count(b_obj_count)
    );

    assign vde = p_vde;
    assign vx  = p_x;
    assign vy  = p_y;
    assign vhs = hs;
    assign vvs = vs;

    // ======================= 探针输出 =======================
    // 当前帧号（自测 = pattern_gen 的；HDMI = 外部计帧，与 sof 同步）
    assign frame_idx = INPUT_SEL ? frame_cnt : pat_frame_idx;

    assign m_valid = o_valid;
    assign m_x     = o_x;
    assign m_y     = o_y;
    assign m_bit   = o_bit;

endmodule
