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
    parameter integer MIN_CNT  = 64      // 包围盒面积门限（大像素个数）
)(
    input  wire        clk,
    input  wire        rst_n,
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
    // ---- 掩码流（大像素坐标，供仿真可视化/探针）----
    output wire        m_valid,
    output wire [15:0] m_x,
    output wire [15:0] m_y,
    output wire        m_bit,
    // ---- 当前激励帧号（自测模式专用）----
    output wire [15:0] frame_idx
);

    localparam integer BW = H_ACTIVE / 2;      // 大像素宽 640
    localparam integer BH = V_ACTIVE / 2;      // 大像素高 360
    localparam integer AW = $clog2(BW * BH);   // 帧缓存地址位宽 18

    // ======================= ① 时序 =======================
    wire        hs, vs, de, sof;
    wire [15:0] x, y;

    video_timing #(
        .H_ACTIVE(H_ACTIVE), .H_FP(H_FP), .H_SYNC(H_SYNC), .H_BP(H_BP),
        .V_ACTIVE(V_ACTIVE), .V_FP(V_FP), .V_SYNC(V_SYNC), .V_BP(V_BP),
        .SYNC_POS(SYNC_POS)
    ) u_timing (
        .clk(clk), .rst_n(rst_n),
        .hs(hs), .vs(vs), .de(de), .x(x), .y(y), .sof(sof)
    );

    // ======================= ② 激励 =======================
    wire        p_vde;
    wire [15:0] p_x, p_y;
    wire [7:0]  p_pix;

    pattern_gen #(
        .H_ACTIVE(H_ACTIVE), .V_ACTIVE(V_ACTIVE),
        .OBJ_W(OBJ_W), .OBJ_H(OBJ_H), .X0(X0), .Y0(Y0), .DX(DX)
    ) u_pat (
        .clk(clk), .rst_n(rst_n),
        .sof(sof), .de(de), .x(x), .y(y),
        .vde(p_vde), .x_o(p_x), .y_o(p_y), .pixel(p_pix),
        .frame_idx(frame_idx)
    );

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

    wire init_phase = (frame_idx <= 16'd1);      // 首帧：缓存直接写当前帧

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
    wire mask_en = (frame_idx >= 16'd2);
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

    // ======================= ⑧ 包围盒 =======================
    bbox #(.MIN_CNT(MIN_CNT)) u_bb (
        .clk(clk), .rst_n(rst_n),
        .in_valid(o_valid), .in_x(o_x), .in_y(o_y), .in_mask(o_bit),
        .x1(b_x1), .y1(b_y1), .x2(b_x2), .y2(b_y2),
        .cnt(b_cnt), .valid(b_valid)
    );

    // ======================= ⑨ 叠加显示 =======================
    // 大像素坐标 → 像素坐标（×2）。显示用的框来自**上一帧**的检测结果。
    wire [15:0] px1 = {b_x1[14:0], 1'b0};
    wire [15:0] py1 = {b_y1[14:0], 1'b0};
    wire [15:0] px2 = {b_x2[14:0], 1'b0};
    wire [15:0] py2 = {b_y2[14:0], 1'b0};

    overlay #() u_ov (
        .de(p_vde), .x(p_x), .y(p_y), .gray(p_pix),
        .bx1(px1), .by1(py1), .bx2(px2), .by2(py2), .bvalid(b_valid),
        .r(vr), .g(vg), .b(vb)
    );

    assign vde = p_vde;
    assign vx  = p_x;
    assign vy  = p_y;
    assign vhs = hs;
    assign vvs = vs;

    // ======================= 探针输出 =======================
    assign m_valid = o_valid;
    assign m_x     = o_x;
    assign m_y     = o_y;
    assign m_bit   = o_bit;

endmodule
