`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// axi_lite_slave —— 线一任务（技术方案 §5.3 最小验证工程 · 甲通路 PL 核心）
//
// 作用：把 Zynq PS 的 AXI4-Lite 从机总线，翻译成 regs.v 的"瘦总线"
//   (ps_en / ps_we / ps_addr / ps_wdata / ps_rdata)。本模块只做协议翻译，
//   寄存器语义全在 regs.v（线二），本模块改动不影响 regs 内部逻辑。
//
// ★ 时钟域：本模块在 S_AXI_ACLK（= PS FCLK）域。最小验证工程里所有逻辑同钟，
//   先证明 PS↔PL AXI 路径通（§5.3 "路线成立"）。
//   **CDC（像素钟↔AXI 钟 整帧快照一致）由线二在快照锁存处做（伟博硬要求②）**，
//   本桥不管——它只管 AXI 协议↔瘦总线翻译。
//
// ★ 地址宽度 ADDR_W=6：字节地址 0x00..0x34（含 BBOX 快照寄存器）。
//   ⚠️ 配合修复：regs.v 当前 ps_addr 是 [4:0]（只能编到 0x1C），
//    BBOX 寄存器 0x20+ 会超宽 → 线二须把 regs.ps_addr 加宽到 [5:0]。
//   本桥按 6 位字节地址输出，与加宽后的 regs 直接对接。
//
// ★ 单驱动约束：ps_en/ps_we/ps_addr 由本文件唯一一个 always 块驱动
//   （此前分读写两块双驱动，导致 ps_en 脉冲被覆盖、寄存器堆采不到写）。
//
// 写：AW/W 同时有效且未持 B → 锁存、发 1 拍 ps_en 脉冲、拉 BVALID；
//     等 BREADY 清 BVALID。读：AR 有效且未持 R → 发 1 拍读 ps_en、
//     下一拍 ps_rdata 稳定 → 锁进 rdata_r 并拉 RVALID；等 RREADY 清。
// 单拍、非突发、全 32 位对齐（PS MMIO 即此用法）。
// -----------------------------------------------------------------------------
module axi_lite_slave #(
    parameter integer ADDR_W = 6     // 字节地址位宽，覆盖 0x00..0x34
)(
    // ---------------- AXI4-Lite 从机接口 ----------------
    input  wire        S_AXI_ACLK,
    input  wire        S_AXI_ARESETN,
    input  wire [31:0] S_AXI_AWADDR,
    input  wire        S_AXI_AWVALID,
    output wire        S_AXI_AWREADY,
    input  wire [31:0] S_AXI_WDATA,
    input  wire [3:0]  S_AXI_WSTRB,
    input  wire        S_AXI_WVALID,
    output wire        S_AXI_WREADY,
    output wire [1:0]  S_AXI_BRESP,
    output reg         S_AXI_BVALID,
    input  wire        S_AXI_BREADY,
    input  wire [31:0] S_AXI_ARADDR,
    input  wire        S_AXI_ARVALID,
    output wire        S_AXI_ARREADY,
    output wire [31:0] S_AXI_RDATA,
    output wire [1:0]  S_AXI_RRESP,
    output reg         S_AXI_RVALID,
    input  wire        S_AXI_RREADY,
    // ---------------- 瘦总线（接 regs.v / 测试寄存器堆）----------------
    output reg         ps_en,
    output reg         ps_we,
    output reg  [ADDR_W-1:0] ps_addr,
    output reg  [31:0] ps_wdata,
    input  wire [31:0] ps_rdata
);

    assign S_AXI_AWREADY = ~S_AXI_BVALID;   // 持 B 期间反压，保证单笔有序
    assign S_AXI_WREADY  = ~S_AXI_BVALID;
    assign S_AXI_ARREADY = ~S_AXI_RVALID;
    assign S_AXI_BRESP   = 2'b00;          // OKAY
    assign S_AXI_RRESP   = 2'b00;

    // ---------------- 单始终块（读写合并，ps_* 唯一驱动）----------------
    reg [ADDR_W-1:0] aw_addr_r;
    reg [31:0]      wdata_r;
    reg [31:0]      rdata_r;
    reg             rd_pend;

    always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_BVALID <= 1'b0;
            S_AXI_RVALID <= 1'b0;
            ps_en  <= 1'b0;
            ps_we  <= 1'b0;
            ps_addr<= {ADDR_W{1'b0}};
            ps_wdata<= 32'd0;
            aw_addr_r <= {ADDR_W{1'b0}};
            wdata_r <= 32'd0;
            rdata_r <= 32'd0;
            rd_pend <= 1'b0;
        end else begin
            // 默认：本拍不发脉冲、不更新数据
            ps_en <= 1'b0;
            ps_we <= 1'b0;

            // ---- 写通道 ----
            if (S_AXI_AWVALID && S_AXI_AWREADY && S_AXI_WVALID && S_AXI_WREADY) begin
                // 接受本次写：锁存并产 1 拍 ps_en 脉冲，拉 BVALID
                aw_addr_r <= S_AXI_AWADDR[ADDR_W-1:0];
                wdata_r   <= S_AXI_WDATA;
                ps_en     <= 1'b1;
                ps_we     <= 1'b1;
                ps_addr   <= S_AXI_AWADDR[ADDR_W-1:0];
                ps_wdata  <= S_AXI_WDATA;
                S_AXI_BVALID <= 1'b1;
            end else if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;   // 写响应完成
            end

            // ---- 读通道 ----
            if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                // 接受读地址：发 1 拍读 ps_en，锁 rd_pend
                // ps_addr 当拍更新→寄存器堆 combo 输出 ps_rdata 下一拍稳定
                ps_en   <= 1'b1;
                ps_we   <= 1'b0;
                ps_addr <= S_AXI_ARADDR[ADDR_W-1:0];
                rd_pend <= 1'b1;
            end else if (rd_pend && !S_AXI_RVALID) begin
                // ps_rdata 已稳定（ps_addr 当拍更新后下一拍 combo 有效），送出并清 pend
                rdata_r <= ps_rdata;
                S_AXI_RVALID <= 1'b1;
                rd_pend <= 1'b0;
            end else if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end

    assign S_AXI_RDATA = rdata_r;

endmodule
