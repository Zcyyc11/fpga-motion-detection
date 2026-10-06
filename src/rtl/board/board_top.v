`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// board_top —— 板级顶层：把 md_pipeline 接到真实的时钟、LED 和 HDMI 上
//
// 这一段做的事（整机图的最外层）：
//    125 MHz (H16) → MMCM → 74.25 MHz 像素时钟
//    md_pipeline（自测激励 → 检测 → 叠加）→ rgb2dvi → HDMI J11 输出
//    4 个 LED 当状态灯
//
// ★ 为什么默认走"内部自测激励"而不是等 HDMI 输入：
//    那样只需要**板子 + HDMI 输出线 + 一块屏**，不需要任何视频源，
//    就能看到"黑底白块被红框框住、框跟着块走"。
//    于是三类故障可以分开定位：
//      LED 全灭 / 屏黑  → 时钟或 HDMI 输出这一段（看 LED0=锁定）
//      屏有画面但没红框  → 检测这一段（看 LED1/LED3）
//      有框但框不跟     → 叠加/坐标这一段
//    否则"黑屏"可能是十几种原因，第一天就会卡死在排查上。
//
// ★ HDMI 输入通路（J10 + dvi2rgb）**本版没有接**。
//    没接就是没接 —— 这里不做"预留接口"式的假声明；
//    接输入要另外生成 dvi2rgb IP、处理 TMDS 时钟恢复与像素时钟切换，
//    是下一个动作，不是这一版的内容。
//
// ★ 复位策略：不依赖板上按键（按键的有效电平与内部上电时序都要另外验证），
//    两段计数器自己产生复位 —— 上电即用，且不引入任何板级假设。
// -----------------------------------------------------------------------------
module board_top #(
    parameter integer MODE_BG = 0          // 0 = 帧差法（v1）／1 = 背景建模（v2）
)(
    input  wire       sys_clk,             // 125 MHz，H16
    output wire [3:0] led,                 // LED0..LED3，高电平点亮
    output wire       hdmi_tx_clk_p,       // HDMI J11（source）
    output wire       hdmi_tx_clk_n,
    output wire [2:0] hdmi_tx_d_p,
    output wire [2:0] hdmi_tx_d_n
);

    // ---------------- ① 时钟：125 MHz → 74.25 MHz ----------------
    reg [3:0] rst_cnt = 4'd0;
    always @(posedge sys_clk)
        if (rst_cnt != 4'hF) rst_cnt <= rst_cnt + 1'b1;
    wire mmcm_rst = (rst_cnt != 4'hF);

    wire clk_pix;
    wire locked;

    clock_74m25 u_clk (
        .clk_125m (sys_clk),
        .mmcm_rst (mmcm_rst),
        .clk_pix  (clk_pix),
        .locked   (locked)
    );

    // ---------------- ② 像素域复位：等锁定后再数一段 ----------------
    reg [9:0] por = 10'd0;
    always @(posedge clk_pix)
        if (!locked)           por <= 10'd0;
        else if (por != 10'd1023) por <= por + 1'b1;

    wire rst_n = locked & (por == 10'd1023);

    // ---------------- ③ 检测流水线 ----------------
    wire        vde, vhs, vvs;
    wire [15:0] vx, vy;
    wire [7:0]  vr, vg, vb;
    wire [15:0] b_x1, b_y1, b_x2, b_y2, b_cnt;
    wire        b_valid;
    wire        m_valid, m_bit;
    wire [15:0] m_x, m_y;
    wire [15:0] frame_idx;

    md_pipeline #(
        .H_ACTIVE(1280), .V_ACTIVE(720),
        .H_FP(110), .H_SYNC(40), .H_BP(220),
        .V_FP(5),   .V_SYNC(5),  .V_BP(20),
        .SYNC_POS(1),
        .OBJ_W(160), .OBJ_H(120), .X0(60), .Y0(300), .DX(16),
        .THRESH(70), .SHIFT(6), .MODE_BG(MODE_BG), .MIN_CNT(64)
    ) u_pipe (
        .clk(clk_pix), .rst_n(rst_n),
        .vde(vde), .vx(vx), .vy(vy), .vhs(vhs), .vvs(vvs),
        .vr(vr), .vg(vg), .vb(vb),
        .b_x1(b_x1), .b_y1(b_y1), .b_x2(b_x2), .b_y2(b_y2),
        .b_cnt(b_cnt), .b_valid(b_valid),
        .m_valid(m_valid), .m_x(m_x), .m_y(m_y), .m_bit(m_bit),
        .frame_idx(frame_idx)
    );

    // ---------------- ④ HDMI 输出：TMDS 编码 + 串化 ----------------
    // rgb2dvi 的 kGenerateSerialClk=true：内部自己用 MMCM 造 5× 串行时钟，
    // 所以这里只喂 74.25 MHz 的 PixelClk。
    //
    // ★★ 端口表是"配置决定"的，不能照抄文档 —— 以 IP 生成的 stub 为准：
    //   build/.../ip/rgb2dvi_0/rgb2dvi_0_stub.v 里一共只有 10 个端口：
    //     TMDS_Clk_p/n, TMDS_Data_p/n, aRst, vid_pData, vid_pVDE,
    //     vid_pHSync, vid_pVSync, PixelClk
    //   两个"看起来该有"的端口按当前配置**根本不存在**：
    //     · aRst_n  —— 只有 kRstActiveHigh=false 时才有；
    //     · SerialClk —— 只有 kGenerateSerialClk=false（外部自己喂 5× 时钟）时才有。
    //   实测代价：之前照文档把这两个也连上，综合直接报
    //     ERROR [Synth 8-11365] named port connection 'aRst_n' does not exist
    //     ERROR [Synth 8-11365] named port connection 'SerialClk' does not exist
    //   → 少连两个端口，代码是对的，错的是"我以为它有"。
    //
    // kRstActiveHigh=true ⇒ aRst 高有效，接 ~rst_n。
    rgb2dvi_0 u_dvi (
        .TMDS_Clk_p  (hdmi_tx_clk_p),
        .TMDS_Clk_n  (hdmi_tx_clk_n),
        .TMDS_Data_p (hdmi_tx_d_p),
        .TMDS_Data_n (hdmi_tx_d_n),
        .aRst        (~rst_n),
        .vid_pData   ({vr, vg, vb}),
        .vid_pVDE    (vde),
        .vid_pHSync  (vhs),
        .vid_pVSync  (vvs),
        .PixelClk    (clk_pix)
    );

    // ---------------- ⑤ 状态灯 ----------------
    // LED0 = MMCM 已锁定（最根上的"活着"指示，屏黑时先看它）
    // LED1 = 本帧检测到目标（等价于画面里那个红框有没有）
    // LED2 = 心跳（约 1.4 Hz，证明像素域时钟真的在跑）
    // LED3 = 本帧出现过运动掩码（形状对上了但框没出来时，用它区分"没检出"和"框没画"）
    reg [23:0] hb = 24'd0;
    always @(posedge clk_pix) hb <= hb + 1'b1;

    reg mask_seen = 1'b0;
    always @(posedge clk_pix) begin
        if (vde && (vx == 16'd0) && (vy == 16'd0)) mask_seen <= 1'b0;
        else if (m_valid && m_bit)                 mask_seen <= 1'b1;
    end

    assign led[0] = locked;
    assign led[1] = b_valid;
    assign led[2] = hb[23];
    assign led[3] = mask_seen;

endmodule
