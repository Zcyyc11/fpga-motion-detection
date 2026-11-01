`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// board_top —— 板级顶层：把 md_pipeline 接到真实的时钟、LED 和 HDMI 上
//
// 这一段做的事（整机图的最外层）：
//    125 MHz (H16) → MMCM → 74.25 MHz 像素时钟（自测模式）
//                   → MMCM → 200 MHz RefClk（dvi2rgb 规格要求）
//    [HDMI 输入模式] dvi2rgb(J10) → hdmi_in_ctrl → gray_conv → md_pipeline
//    [自测模式]     md_pipeline 内部合成激励
//    md_pipeline（检测 → 叠加）→ rgb2dvi → HDMI J11 输出
//    4 个 LED 当状态灯
//
// ★ 两种模式由构建参数 INPUT_SEL 定死（与 MODE_BG 同一机制，构建两版 bit）：
//   INPUT_SEL=0 自测：板子 + HDMI 输出线 + 屏，看到"黑底白块被红框框住"。
//   INPUT_SEL=1 真实输入：HDMI 线从信源进 J10，看到"真实画面里运动目标被红框框住"。
//   输入模式下整条链（流水线 + HDMI 输出）跟 dvi2rgb 恢复的 PixelClk 走，
//   避免两个 74.25 MHz 混用造成亚稳态 —— 时钟只有一套。
//
// ★ 复位策略：不依赖板上按键，两段计数器自己产生复位 —— 上电即用。
//   输入模式锁定信号换成 pLocked（dvi2rgb 时钟恢复锁定），解锁/拔线自动复位。
//
// ★ HPD（热插拔检测）拉高：告诉信源"显示设备已连接"，信源才会读 EDID
//   并按 720p 输出。不拉高 = 信源认为没接显示器 = 永远无信号。
// -----------------------------------------------------------------------------
module board_top #(
    parameter integer MODE_BG   = 0,     // 0 = 帧差法（v1）／1 = 背景建模（v2）
    parameter integer INPUT_SEL = 0      // 0 = 内部自测激励／1 = 真实 HDMI 输入
)(
    input  wire       sys_clk,             // 125 MHz，H16
    output wire [3:0] led,                 // LED0..LED3，高电平点亮
    output wire       uart_txd,            // ★线二回传：PL 侧 UART（协议 v0.2），★改到 PMOD B（原 PMOD A/Y18 已被 Attach 占用）
    // ---- 板载按键/拨码（W1/W4 场景与模式切换）----
    input  wire [3:0] btn,
    input  wire [1:0] sw,
    // ---- 板载三色灯 LD4 / LD5（经三极管，反相；本模块内部已取反）----
    output wire       led4_r, led4_g, led4_b,
    output wire       led5_r, led5_g, led5_b,
    // ---- Attach-Z2 外设（W5–W9）----
    output wire       buzzer,              // 无源蜂鸣器
    output wire [6:0] attach_seg,          // 数码管段选 A..G
    output wire [8:0] attach_digit,        // 数码管位选 DIG1..DIG9
    output wire       attach_ws2812_din,   // WS2812 单线数据
    output wire       attach_lcd_sck,
    output wire       attach_lcd_mosi,
    output wire       attach_lcd_cs_n,
    output wire       attach_lcd_dc,
    output wire       attach_lcd_rst_n,
    output wire       attach_lcd_bkl,
    output wire       attach_touch_scl,
    output wire       attach_touch_sda,
    output wire       hdmi_tx_clk_p,       // HDMI J11（source）
    output wire       hdmi_tx_clk_n,
    output wire [2:0] hdmi_tx_d_p,
    output wire [2:0] hdmi_tx_d_n,
    // ---- HDMI J10（sink，输入）----
    input  wire       hdmi_rx_clk_p,
    input  wire       hdmi_rx_clk_n,
    input  wire [2:0] hdmi_rx_d_p,
    input  wire [2:0] hdmi_rx_d_n,
    output wire       hdmi_rx_hpd,         // 热插拔检测（输出拉高）
    inout  wire       hdmi_rx_scl,         // DDC I2C 时钟（信源读 EDID 用）
    inout  wire       hdmi_rx_sda          // DDC I2C 数据
);

    // ---------------- ① 时钟：125 MHz → 74.25 MHz 像素时钟 + 200 MHz RefClk ----------------
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

    // 200 MHz：dvi2rgb 的 RefClk（IDELAYCTRL 参考时钟，规格就是 200 MHz）。
    // 独立 MMCM（参数解出来 M=64/Dv=8/D0=5，VCO=1000MHz），不蹭 74.25 那组的 VCO。
    wire clk_200m;
    wire locked_200;

    clock_200m u_clk200 (
        .clk_125m (sys_clk),
        .mmcm_rst (mmcm_rst),
        .clk_200m (clk_200m),
        .locked   (locked_200)
    );

    // ---- HDMI 输入解码信号声明（提前：② 的时钟/复位选择要用到）----
    wire        pixel_clk_rx;      // dvi2rgb 恢复的像素时钟（74.25 MHz @ 720p）
    wire        pLocked;
    wire        vid_pVDE, vid_pHSync, vid_pVSync;
    wire [23:0] vid_pData;         // RBG 打包（[23:16]=R [15:8]=B [7:0]=G）
    wire        ddc_sda_i, ddc_sda_o, ddc_sda_t;
    wire        ddc_scl_i, ddc_scl_o, ddc_scl_t;

    // ---------------- ② 像素时钟与复位（按模式选一套）----------------
    // INPUT_SEL 是构建定死参数：综合后选择退化为直连（不是真 mux，无毛刺）。
    // 输入模式整条链（流水线 + rgb2dvi 输出）跟 PixelClk 走。
    wire clk_pipe = INPUT_SEL ? pixel_clk_rx : clk_pix;

    // 锁定信号：自测看 74.25 MMCM；输入看 dvi2rgb 时钟恢复（文档：断言同步于 PixelClk）
    wire locked_sel = INPUT_SEL ? pLocked : locked;

    reg [9:0] por = 10'd0;
    always @(posedge clk_pipe)
        if (!locked_sel)           por <= 10'd0;
        else if (por != 10'd1023)  por <= por + 1'b1;

    wire rst_n = locked_sel & (por == 10'd1023);

    // ---------------- ③ HDMI 输入解码（J10 → dvi2rgb）----------------
    // dvi2rgb_0 是 Digilent 官方开源 IP（与 rgb2dvi_0 同一套 vivado-library），
    // 配置：kClkRange=3（<80MHz/720p）、EDID=dgl_720p_cea.data（720p 首选时序）、
    //       kEmulateDDC=true（电脑才读得到 EDID）、kAddBUFG=true（PixelClk 全局化）、
    //       kDebug=false（不例化调试 ILA）。参数出处见 create_dvi2rgb.tcl。
    //
    // ★ 复位：aRst 接 ~locked_200 —— 文档原话"aRst: Assert, if RefClk is not within spec"。
    //   200M 未锁 → 保持复位；锁定后自动开始恢复。不依赖 pLocked，无死锁。
    //   pRst（同步复位）不用，接 0 —— 锁定过程自行开始。
    dvi2rgb_0 u_rx (
        .TMDS_Clk_p  (hdmi_rx_clk_p),
        .TMDS_Clk_n  (hdmi_rx_clk_n),
        .TMDS_Data_p (hdmi_rx_d_p),
        .TMDS_Data_n (hdmi_rx_d_n),
        .RefClk      (clk_200m),
        .aRst        (~locked_200),
        .vid_pData   (vid_pData),
        .vid_pVDE    (vid_pVDE),
        .vid_pHSync  (vid_pHSync),
        .vid_pVSync  (vid_pVSync),
        .PixelClk    (pixel_clk_rx),
        .pLocked     (pLocked),
        .SDA_I       (ddc_sda_i),
        .SDA_O       (ddc_sda_o),
        .SDA_T       (ddc_sda_t),
        .SCL_I       (ddc_scl_i),
        .SCL_O       (ddc_scl_o),
        .SCL_T       (ddc_scl_t),
        .pRst        (1'b0)
    );

    // ---- DDC：inout 引脚用 IOBUF 三态缓冲（Digilent 参考设计标准接法）----
    IOBUF u_ddc_scl (.IO(hdmi_rx_scl), .I(ddc_scl_o), .O(ddc_scl_i), .T(ddc_scl_t));
    IOBUF u_ddc_sda (.IO(hdmi_rx_sda), .I(ddc_sda_o), .O(ddc_sda_i), .T(ddc_sda_t));

    // ---- HPD 拉高：告诉信源"显示器已连接"，信源才会读 EDID 并输出 720p ----
    assign hdmi_rx_hpd = 1'b1;

    // ---------------- ④ 输入整理 + 灰度（PixelClk 域）----------------
    // hdmi_in_ctrl：补 x/y 坐标、sof 帧首、无信号黑屏兜底（拔线不花屏）。
    // gray_conv：RBG 24bit → 8bit 灰度（BT.601，77/150/29），进流水线同一入口。
    wire        in_de, in_hs, in_vs, in_sof;
    wire [15:0] in_x, in_y;
    wire [23:0] in_pix;

    hdmi_in_ctrl u_in_ctrl (
        .clk     (pixel_clk_rx),
        .rst_n   (rst_n),              // INPUT_SEL=1 时整机复位就在 PixelClk 域
        .pVDE    (vid_pVDE),
        .pHSync  (vid_pHSync),
        .pVSync  (vid_pVSync),
        .pData   (vid_pData),
        .pLocked (pLocked),
        .de      (in_de),
        .hs      (in_hs),
        .vs      (in_vs),
        .x       (in_x),
        .y       (in_y),
        .sof     (in_sof),
        .pix_data(in_pix),
        .locked  ()
    );

    wire        g_vde;
    wire [15:0] g_x, g_y;
    wire [7:0]  g_gray;

    gray_conv u_gray (
        .clk   (pixel_clk_rx),
        .rst_n (rst_n),
        .vde   (in_de),
        .x     (in_x),
        .y     (in_y),
        .pix_in(in_pix),
        .o_vde (g_vde),
        .o_x   (g_x),
        .o_y   (g_y),
        .gray  (g_gray)
    );

    // ---------------- ⑤ 检测流水线 ----------------
    wire        vde, vhs, vvs;
    wire [15:0] vx, vy;
    wire [7:0]  vr, vg, vb;
    wire [15:0] b_x1, b_y1, b_x2, b_y2, b_cnt;
    wire        b_valid;
    wire [7:0]  b_obj_count;
    wire        alarm_evt;                 // ★从 md_pipeline 引出（原来悬空）
    wire [15:0] ext_thresh;                // ★按键设定的阈值，覆盖编译期 THRESH
    wire        ext_thresh_en;
    wire        m_valid, m_bit;
    wire [15:0] m_x, m_y;
    wire [15:0] frame_idx;

    md_pipeline #(
        .H_ACTIVE(1280), .V_ACTIVE(720),
        .H_FP(110), .H_SYNC(40), .H_BP(220),
        .V_FP(5),   .V_SYNC(5),  .V_BP(20),
        .SYNC_POS(1),
        .OBJ_W(160), .OBJ_H(120), .X0(60), .Y0(300), .DX(16),
        .THRESH(70), .SHIFT(6), .MODE_BG(MODE_BG), .MIN_CNT(64),
        .INPUT_SEL(INPUT_SEL),
        .INCLUDE_PS(0)          // 0 = 纯 PL（AXI 口悬空，UART 链无条件生效）
    ) u_pipe (
        .clk(clk_pipe), .rst_n(rst_n),
        .rx_de(g_vde), .rx_hs(in_hs), .rx_vs(in_vs), .rx_sof(in_sof),
        .rx_x(g_x), .rx_y(g_y), .rx_gray(g_gray),
        .ext_thresh(ext_thresh), .ext_thresh_en(ext_thresh_en),
        .vde(vde), .vx(vx), .vy(vy), .vhs(vhs), .vvs(vvs),
        .vr(vr), .vg(vg), .vb(vb),
        .b_x1(b_x1), .b_y1(b_y1), .b_x2(b_x2), .b_y2(b_y2),
        .b_cnt(b_cnt), .b_valid(b_valid), .b_obj_count(b_obj_count),
        .m_valid(m_valid), .m_x(m_x), .m_y(m_y), .m_bit(m_bit),
        .frame_idx(frame_idx),
        // ---- 线二回传链：INCLUDE_PS=0 ⇒ AXI 口悬空，UART 链无条件生效（参数已在 #() 覆盖，非端口）----
        .clk_axi(1'b0), .rst_n_axi(1'b0),
        .ps_en(1'b0), .ps_we(1'b0), .ps_addr(6'd0), .ps_wdata(32'd0),
        .ps_rdata(),
        .uart_txd(uart_txd), .uart_drop(), .alarm_evt(alarm_evt)
    );

    // ---------------- ⑤B 人机交互 + Attach-Z2 外设（W1–W9）----------------
    // 按键 BTN0-3 选四档场景 → 直接覆盖阈值（改了就立刻生效，不用重烧）
    // 三色灯 LD4/LD5 经三极管反相，所以输出取反；板载 LED0-3 在下面另有定义。
    reg  [1:0]  scene;
    reg  [3:0]  btn_d;
    reg  [19:0] dbnc;
    wire [15:0] thr_sel;
    always @(posedge clk_pipe or negedge rst_n) begin
        if (!rst_n) begin
            scene <= 2'd0; btn_d <= 4'd0; dbnc <= 20'd0;
        end else begin
            btn_d <= btn;
            if (dbnc != 20'd0) dbnc <= dbnc - 1'b1;
            else if (btn[0] && !btn_d[0]) begin scene <= 2'd0; dbnc <= 20'hFFFFF; end
            else if (btn[1] && !btn_d[1]) begin scene <= 2'd1; dbnc <= 20'hFFFFF; end
            else if (btn[2] && !btn_d[2]) begin scene <= 2'd2; dbnc <= 20'hFFFFF; end
            else if (btn[3] && !btn_d[3]) begin scene <= 2'd3; dbnc <= 20'hFFFFF; end
        end
    end
    // 四档：周界(70) / 室内(90) / 夜间(45) / 高灵敏(35)
    assign thr_sel = (scene == 2'd0) ? 16'd70 :
                     (scene == 2'd1) ? 16'd90 :
                     (scene == 2'd2) ? 16'd45 : 16'd35;
    assign ext_thresh    = thr_sel;
    assign ext_thresh_en = 1'b1;          // 常开：始终用按键设定的值

    // 三色灯：红=越界，绿=有目标，蓝=正常。板上三极管反相 ⇒ 输出取反。
    assign led4_r = ~alarm_evt;
    assign led4_g = ~(b_valid && !alarm_evt);
    assign led4_b = 1'b1;                 // 常灭（反相后）
    assign led5_r = ~alarm_evt;
    assign led5_g = ~(!alarm_evt && !b_valid);
    assign led5_b = ~(b_valid && !alarm_evt);

    attach_z2_interaction #(.CLK_HZ(125_000_000)) u_attach (
        .clk(clk_pipe), .rst_n(rst_n),
        .target_count(b_obj_count),       // ★真实目标数（不是 0/1）
        .threshold(thr_sel), .mode(scene),
        .fps(16'd60),
        .violation_count(alarm_evt ? 16'd1 : 16'd0),
        .target_present(b_valid), .violation_event(alarm_evt),
        .light_dark(sw[1]),
        .enc_a(1'b0), .enc_b(1'b0), .enc_push(1'b0),   // 编码器暂未接（管脚留空）
        .fiveway(5'b00001),
        .threshold_delta(), .night_mode(),
        .seg(attach_seg), .digit(attach_digit),
        .ws2812_din(attach_ws2812_din),
        .lcd_sck(attach_lcd_sck), .lcd_mosi(attach_lcd_mosi),
        .lcd_cs_n(attach_lcd_cs_n), .lcd_dc(attach_lcd_dc),
        .lcd_rst_n(attach_lcd_rst_n), .lcd_bkl(attach_lcd_bkl),
        .buzzer(buzzer),
        .touch_scl(attach_touch_scl), .touch_sda(attach_touch_sda)
    );

    // ---------------- ⑥ HDMI 输出：TMDS 编码 + 串化 ----------------
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
        .vid_pData   ({vr, vb, vg}),   // rgb2dvi 按 RBG 解包（R=[23:16] G=[7:0] B=[15:8]），不能按 RGB 喂
        .vid_pVDE    (vde),
        .vid_pHSync  (vhs),
        .vid_pVSync  (vvs),
        .PixelClk    (clk_pipe)      // 输入模式 = dvi2rgb 恢复时钟；自测 = 74.25 MMCM
    );

    // ---------------- ⑦ 状态灯 ----------------
    // LED0 = 当前模式的锁定（自测=MMCM 锁定／输入=dvi2rgb 时钟恢复锁定；屏黑先看它）
    // LED1 = 本帧检测到目标（等价于画面里那个红框有没有）
    // LED2 = 心跳（约 1.4 Hz，证明像素域时钟真的在跑）
    // LED3 = 本帧出现过运动掩码（形状对上了但框没出来时，用它区分"没检出"和"框没画"）
    reg [23:0] hb = 24'd0;
    always @(posedge clk_pipe) hb <= hb + 1'b1;

    reg mask_seen = 1'b0;
    always @(posedge clk_pipe) begin
        if (vde && (vx == 16'd0) && (vy == 16'd0)) mask_seen <= 1'b0;
        else if (m_valid && m_bit)                 mask_seen <= 1'b1;
    end

    assign led[0] = locked_sel;
    assign led[1] = b_valid;
    assign led[2] = hb[23];
    assign led[3] = mask_seen;

endmodule
