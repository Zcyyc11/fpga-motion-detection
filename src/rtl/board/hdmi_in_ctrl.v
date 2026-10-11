`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// hdmi_in_ctrl —— 把 dvi2rgb 恢复的视频流整理成 md_pipeline 认识的入口
//
// dvi2rgb 只保证输出 RGB 数据 + 同步信号，不保证你下游方便用：
//   · 没有像素坐标 x/y（de=1 期间要自己数）
//   · 没有帧首标记 sof（下游 frame_buf 首帧逻辑要用）
//   · 没有无信号兜底（拔线时 vid_pVDE 会乱，直接送流水线会花屏）
// 本模块补这三样，全部在 PixelClk 域。
//
// ★ 坐标重建不是拍 1280/720 常数，是从同步信号本身推出来的：
//   x：de=1 期间 +1，行首（de 上升沿）清零 → 每行 0..H_ACTIVE-1
//   y：帧首行 0，之后每行（de 上升沿）行号 +1 → 0..V_ACTIVE-1
//   这样换分辨率也自适应（EDID 锁 720p 时就是 0..1279 / 0..719），
//   不依赖任何"这个分辨率是几乘几"的假设。
//
// ★ sof（帧首像素拍）：
//   vsync 高电平结束后第一个 de 上升沿 = 新帧第一行的第一个像素。
//   vsync 高持续 5 行（720p60 的 V_SYNC），期间没有 de；
//   之后还有 20 行 V_BP blanking 也没有 de，所以"vsync 后首个 de 上升沿"
//   必然落在新帧行 0 的像素 0 —— 这就是 sof，不依赖分辨率常数。
//
// ★ 无信号兜底（拔线/冻结不花屏）：
//   pLocked 是 dvi2rgb 的时钟恢复锁定（文档：解锁时 PixelClk 丢失/不在规格）。
//   再加一道帧看门狗：vsync 每帧必到（720p60 是 60 次/秒），超过 5 个帧周期
//   没见到 vsync 就判无信号 → 输出全部拉黑（de=0、数据=0），屏是黑的不是花的。
//   看门狗计时 = 5 × (1/60) s @ 74.25 MHz = 6,187,500 拍（这个数有出处：
//   720p60 帧率 60Hz 是 EDID 首选时序保证的，见 dgl_720p_cea.data）。
// -----------------------------------------------------------------------------
module hdmi_in_ctrl #(
    // 帧看门狗容错帧数（拍脑袋的默认值？不是：5 帧 ≈ 83ms，覆盖首帧锁定抖动，
    // 又比 1 秒快一个量级 —— 拔线后 0.1 秒内黑屏，肉眼无感）
    parameter integer WDT_FRAMES = 5
)(
    input  wire        clk,          // PixelClk（dvi2rgb 恢复的像素时钟）
    input  wire        rst_n,        // 全局复位（PixelClk 域）
    // ---- dvi2rgb 输出（PixelClk 域）----
    input  wire        pVDE,
    input  wire        pHSync,
    input  wire        pVSync,
    input  wire [23:0] pData,        // RBG 打包
    input  wire        pLocked,      // 时钟恢复锁定（文档：断言同步于 PixelClk）
    // ---- 整理后视频流（全部寄存器输出，与 de 同拍）----
    output reg         de,
    output reg         hs,
    output reg         vs,
    output reg  [15:0] x,            // 有效像素坐标
    output reg  [15:0] y,            // 有效行号
    output reg         sof,          // 帧首像素拍
    output reg  [23:0] pix_data,     // RBG 原样透传（对齐）
    output wire        locked        // 综合锁定：pLocked && 帧看门狗存活
);

    // 帧看门狗上限：5 帧周期 @ 74.25 MHz / 60 Hz
    localparam integer WDT_MAX = 74_250_000 * WDT_FRAMES / 60;

    // ---------------- 输入打 1 拍（供沿检测，避免组合环）----------------
    reg pVDE_d, pHSync_d, pVSync_d;
    reg [23:0] pData_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pVDE_d <= 1'b0; pHSync_d <= 1'b0; pVSync_d <= 1'b0;
            pData_d <= 24'd0;
        end else begin
            pVDE_d  <= pVDE;
            pHSync_d<= pHSync;
            pVSync_d<= pVSync;
            pData_d <= pData;
        end
    end

    // ---------------- 帧首判定：vsync 高后第一个 de 上升沿 ----------------
    wire de_rise = pVDE && !pVDE_d;

    reg  pending_sof;
    wire sof_cnd = de_rise && pending_sof;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      pending_sof <= 1'b0;
        else if (pVSync) pending_sof <= 1'b1;   // vsync 高 → 等待帧首
        else if (de_rise) pending_sof <= 1'b0;  // 首个 de 上升沿消耗
    end

    // ---------------- 坐标计数（行为层：de 驱动，不拍分辨率常数）----------------
    reg [15:0] x_cnt;
    reg [15:0] y_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)       x_cnt <= 16'd0;
        else if (sof_cnd) x_cnt <= 16'd0;   // 帧首像素 = x 0
        else if (de_rise) x_cnt <= 16'd0;   // 行首 = x 0
        else if (pVDE)    x_cnt <= x_cnt + 16'd1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)       y_cnt <= 16'd0;
        else if (sof_cnd) y_cnt <= 16'd0;           // 帧首行 = y 0
        else if (de_rise) y_cnt <= y_cnt + 16'd1;   // 非帧首的行首 = 下一行
    end

    // ---------------- 帧看门狗：vsync 超时判无信号 ----------------
    reg [31:0] wdt_cnt;
    reg        wdt_alive;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wdt_cnt  <= 32'd0;
            wdt_alive<= 1'b0;
        end else if (pVSync) begin
            wdt_cnt  <= 32'd0;
            wdt_alive<= 1'b1;
        end else if (wdt_cnt >= WDT_MAX) begin
            wdt_alive<= 1'b0;
        end else begin
            wdt_cnt  <= wdt_cnt + 32'd1;
        end
    end

    assign locked = pLocked && wdt_alive;

    // ---------------- 输出（全部打 1 拍，与 de 同拍）----------------
    // locked=0（无信号）→ 拉黑：de/hs/vs/sof 全 0、数据 0，屏黑不花。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de       <= 1'b0;
            hs       <= 1'b0;
            vs       <= 1'b0;
            sof      <= 1'b0;
            x        <= 16'd0;
            y        <= 16'd0;
            pix_data <= 24'd0;
        end else if (locked) begin
            de       <= pVDE;
            hs       <= pHSync;
            vs       <= pVSync;
            sof      <= sof_cnd;
            x        <= x_cnt;
            y        <= y_cnt;
            pix_data <= pData;
        end else begin
            de       <= 1'b0;
            hs       <= 1'b0;
            vs       <= 1'b0;
            sof      <= 1'b0;
            x        <= x_cnt;
            y        <= y_cnt;
            pix_data <= 24'd0;
        end
    end

endmodule
