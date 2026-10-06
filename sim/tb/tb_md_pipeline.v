`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_md_pipeline —— 运动检测流水线仿真台（自带可视化导出）
//
// 它不只是"跑一跑看有没有 X"，而是把每次运行的**产物**落盘，供人眼和脚本核对：
//   wave/bbox_rtl.csv     逐帧包围盒（大像素坐标）  ← 与 PC 参考模型逐帧对比用
//   wave/frame_<k>.ppm    叠加了红框的输出画面      ← 给人眼看"显示"这一半
//   wave/mask_<k>.ppm     形态学之后的运动掩码      ← 看算法中间结果
// 同时把逐帧摘要打到日志（xsim 日志里有），便于确认它真在跑、跑到第几帧。
//
// 为什么仿真用 320×180 而不是 720p：
//   xsim 是**事件驱动**仿真器，一帧 720p 要 100 万个时钟。要跑几十帧就是上亿个事件，
//   仿真时间会从秒级涨到分钟级，卡住"当天必须看到结果"这件事。
//   所以：**小尺寸定功能，大尺寸定规模**——
//     320×180 跑全片段（几何同比例缩小，时钟数少 16 倍）→ 逐帧数值对照
//   720p 只跑少数几帧，证明全分辨率下这条链也是通的（见 sim/README.md）。
//
// ★ 两个容易搞错的时刻，先写清楚（否则 CSV 会整体错一帧）：
//   1) bbox 是在**掩码流的帧边界**结算的（掩码流 y 回绕那一拍），
//      而结算用的是**非阻塞赋值**，所以结算后的新值要到**下一拍**才读得到。
//      本台就在"下一拍"取样，编号 0 即第 0 帧。
//   2) 视频帧首（vx=0,vy=0）比掩码帧边界早几拍，所以**不能**在视频帧首取 bbox，
//      那样读到的永远是再上一帧的值。
//
// ★ 参数纪律：本台的激励参数必须与 src/ps/rtl_golden.py 的同名参数一致，
//   否则两边比的不是同一段输入，对照就没有意义。
// -----------------------------------------------------------------------------
module tb_md_pipeline;

    // ---------------- 可调配置 ----------------
    parameter integer H_ACTIVE = 320;
    parameter integer V_ACTIVE = 180;
    parameter integer OBJ_W    = 40;
    parameter integer OBJ_H    = 30;
    parameter integer X0       = 40;
    parameter integer Y0       = 80;
    parameter integer DX       = 16;
    parameter integer FRAMES   = 12;      // 有效帧数（跑完再留 1 帧收尾）
    parameter integer DUMP_N   = 12;      // 导出 PPM 的帧数上限（大尺寸时调小）
    parameter integer MODE_BG  = 0;       // 0 = 帧差法 v1 ／ 1 = 背景建模 v2
    parameter integer THRESH   = 70;
    parameter integer SHIFT    = 6;
    parameter integer MIN_CNT  = 64;

    localparam integer BW   = H_ACTIVE / 2;
    localparam integer BH   = V_ACTIVE / 2;
    localparam integer NPIX = BW * BH;

    // ---------------- 时钟 / 复位 ----------------
    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;                  // 100 MHz。仿真里像素时钟不是瓶颈

    // ---------------- DUT ----------------
    wire        vde;
    wire [15:0] vx, vy;
    wire [7:0]  vr, vg, vb;
    wire [15:0] b_x1, b_y1, b_x2, b_y2, b_cnt;
    wire        b_valid;
    wire        m_valid;
    wire [15:0] m_x, m_y;
    wire        m_bit;
    wire [15:0] frame_idx;

    md_pipeline #(
        .H_ACTIVE(H_ACTIVE), .V_ACTIVE(V_ACTIVE),
        .H_FP(8), .H_SYNC(16), .H_BP(16),
        .V_FP(2), .V_SYNC(4), .V_BP(4), .SYNC_POS(0),
        .OBJ_W(OBJ_W), .OBJ_H(OBJ_H), .X0(X0), .Y0(Y0), .DX(DX),
        .THRESH(THRESH), .SHIFT(SHIFT), .MODE_BG(MODE_BG), .MIN_CNT(MIN_CNT)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .vde(vde), .vx(vx), .vy(vy), .vr(vr), .vg(vg), .vb(vb),
        .b_x1(b_x1), .b_y1(b_y1), .b_x2(b_x2), .b_y2(b_y2),
        .b_cnt(b_cnt), .b_valid(b_valid),
        .m_valid(m_valid), .m_x(m_x), .m_y(m_y), .m_bit(m_bit),
        .frame_idx(frame_idx)
    );

    initial begin
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
    end

    // ---------------- 公共事件 ----------------
    wire        frame_start = vde && (vx == 16'd0) && (vy == 16'd0);

    reg  [15:0] mpy;
    initial mpy = 16'hFFFF;
    always @(posedge clk) if (m_valid) mpy <= m_y;

    wire mk_boundary = m_valid && (m_y < mpy);     // 掩码流：新的一帧开始
    reg  mk_poke     = 1'b0;                       // 边界后一拍：新 bbox 已稳定
    always @(posedge clk) mk_poke <= mk_boundary;

    // ---------------- 产物 1：逐帧包围盒 CSV ----------------
    integer csv_f;
    integer poke_idx;
    initial begin
        csv_f    = $fopen("wave/bbox_rtl.csv", "w");
        poke_idx = 0;
        if (csv_f == 0) $display("!! 打不开 wave/bbox_rtl.csv");
        else            $fwrite(csv_f, "frame,b_valid,b_x1,b_y1,b_x2,b_y2,b_cnt\n");
    end

    always @(posedge clk) begin
        if (mk_poke) begin
            if (csv_f != 0)
                $fwrite(csv_f, "%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                        poke_idx, b_valid, b_x1, b_y1, b_x2, b_y2, b_cnt);
            $display("t=%0t  第 %0d 帧检测: bbox=(%0d,%0d)-(%0d,%0d)  cnt=%0d  valid=%0d",
                     $time, poke_idx, b_x1, b_y1, b_x2, b_y2, b_cnt, b_valid);
            poke_idx <= poke_idx + 1;
        end
    end

    // ---------------- 产物 2：输出画面 PPM（流式，不占内存）----------------
    integer        ppm_f;
    integer        ppm_idx;
    reg [8*96-1:0] ppm_name;

    initial begin
        ppm_f   = 0;
        ppm_idx = 0;
    end

    always @(posedge clk) begin
        if (vde) begin
            if (frame_start) begin
                if (ppm_f != 0) $fclose(ppm_f);
                ppm_f = 0;
                if (ppm_idx < DUMP_N) begin
                    $sformat(ppm_name, "wave/frame_%0d.ppm", ppm_idx);
                    ppm_f = $fopen(ppm_name, "wb");
                    if (ppm_f != 0)
                        $fwrite(ppm_f, "P6\n%0d %0d\n255\n", H_ACTIVE, V_ACTIVE);
                end
                ppm_idx <= ppm_idx + 1;
            end
            if (ppm_f != 0) $fwrite(ppm_f, "%c%c%c", vr, vg, vb);
        end
    end

    // ---------------- 产物 3：运动掩码 PPM ----------------
    reg [7:0]      mimg [0:NPIX-1];
    integer        mk_f;
    integer        mk_idx;
    integer        ii, jj, k;
    reg [8*96-1:0] mk_name;

    initial begin
        for (k = 0; k < NPIX; k = k + 1) mimg[k] = 8'h00;
        mk_idx = 0;
    end

    always @(posedge clk) if (m_valid) mimg[m_y * BW + m_x] <= (m_bit === 1'b1) ? 8'hFF : 8'h00;

    // ---- X 检查：仿真里最怕"悄悄跑了 X"，看着跑完其实没算 ----
    // 掩码流上出现未知态直接计数，结束时报出来；为 0 才算干净。
    integer x_hits;
    initial x_hits = 0;
    always @(posedge clk)
        if ((m_valid === 1'bx) || (m_bit === 1'bx) || (m_x === 16'hxxxx) || (m_y === 16'hxxxx))
            x_hits = x_hits + 1;

    // 边界那一拍缓冲里还是**上一帧**的完整掩码；掩码帧 k 的边界 → 导出帧 k-1 的掩码
    always @(posedge clk) begin
        if (mk_boundary) begin
            if (mk_idx < DUMP_N) begin
                $sformat(mk_name, "wave/mask_%0d.ppm", mk_idx);
                mk_f = $fopen(mk_name, "wb");
                if (mk_f != 0) begin
                    $fwrite(mk_f, "P6\n%0d %0d\n255\n", BW, BH);
                    for (ii = 0; ii < BH; ii = ii + 1)
                        for (jj = 0; jj < BW; jj = jj + 1)
                            $fwrite(mk_f, "%c%c%c",
                                    mimg[ii * BW + jj], mimg[ii * BW + jj], mimg[ii * BW + jj]);
                    $fclose(mk_f);
                    mk_f = 0;
                end
            end
            mk_idx <= mk_idx + 1;
        end
    end

    // ---------------- 收尾 ----------------
    integer vframe;
    initial vframe = 0;
    always @(posedge clk) if (frame_start) vframe <= vframe + 1;

    initial begin
        wait (rst_n == 1'b1);
        while (vframe <= FRAMES) @(posedge clk);
        repeat (200) @(posedge clk);
        if (csv_f != 0) $fclose(csv_f);
        if (ppm_f != 0) $fclose(ppm_f);
        $display("---- 仿真结束：共跑 %0d 个视频帧，bbox 见 wave/bbox_rtl.csv ----", vframe);
        if (x_hits == 0)
            $display("---- X 检查：掩码流未出现未知态（x_hits=0）----");
        else
            $display("!! X 检查：掩码流出现 %0d 次未知态，流水线有未初始化路径，需排查", x_hits);
        $finish;
    end

    // 看门狗：卡死时明确报错，别让日志停在中间让人猜
    initial begin
        #200000000;
        $display("!! TIMEOUT：仿真未在预期时间内结束");
        $finish;
    end

endmodule
