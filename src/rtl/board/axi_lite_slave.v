`timescale 1ns/1ps
// AXI4-Lite to registered 32-bit MMIO bus; independent AW/W/AR holding slots.
// Full-word aligned writes supported. Zero WSTRB aborts; partial writes SLVERR.
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

    // One entry per independent channel. READY only acknowledges stored data.
    reg aw_full, w_full, ar_full;
    reg [ADDR_W-1:0] aw_addr_r, ar_addr_r;
    reg [31:0] wdata_r, rdata_r;
    reg [3:0] wstrb_r;
    reg [1:0] bresp_r;
    reg [1:0] rd_phase;
    reg wr_pending;
    assign S_AXI_AWREADY = S_AXI_ARESETN && !aw_full && !S_AXI_BVALID && !wr_pending;
    assign S_AXI_WREADY  = S_AXI_ARESETN && !w_full && !S_AXI_BVALID && !wr_pending;
    assign S_AXI_ARREADY = S_AXI_ARESETN && !ar_full && !S_AXI_RVALID && rd_phase==0;
    assign S_AXI_BRESP = bresp_r;
    assign S_AXI_RRESP = 2'b00;
    assign S_AXI_RDATA = rdata_r;

    always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN) begin
            aw_full<=0;w_full<=0;ar_full<=0;
            aw_addr_r<=0;ar_addr_r<=0;wdata_r<=0;wstrb_r<=0;
            rdata_r<=0;bresp_r<=0;rd_phase<=0;wr_pending<=0;
            S_AXI_BVALID<=0;S_AXI_RVALID<=0;
            ps_en<=0;ps_we<=0;ps_addr<=0;ps_wdata<=0;
        end else begin
            ps_en<=0;
            if(S_AXI_AWVALID && S_AXI_AWREADY) begin
                aw_full<=1;aw_addr_r<=S_AXI_AWADDR[ADDR_W-1:0];
            end
            if(S_AXI_WVALID && S_AXI_WREADY) begin
                w_full<=1;wdata_r<=S_AXI_WDATA;wstrb_r<=S_AXI_WSTRB;
            end
            if(S_AXI_ARVALID && S_AXI_ARREADY) begin
                ar_full<=1;ar_addr_r<=S_AXI_ARADDR[ADDR_W-1:0];
            end
            if(S_AXI_BVALID && S_AXI_BREADY) S_AXI_BVALID<=0;
            if(S_AXI_RVALID && S_AXI_RREADY) S_AXI_RVALID<=0;

            // Shared register port: never overwrite a read while it is in flight.
            // regs.v samples ps_en next edge and registers its result; capture
            // two edges after issue, before its subsequent idle zero update.
            // A response becomes visible only when regs samples the issued write.
            if(wr_pending) begin
                wr_pending<=0;S_AXI_BVALID<=1;
            end else if(rd_phase==1) rd_phase<=2;
            else if(rd_phase==2) begin
                rdata_r<=ps_rdata;S_AXI_RVALID<=1;rd_phase<=0;
            end else if(aw_full && w_full && !S_AXI_BVALID) begin
                aw_full<=0;w_full<=0;wr_pending<=1;
                bresp_r<=0;
                // No byte-enable exists on the downstream bus. Zero strobe is
                // a legal no-op. Partial/unaligned writes return SLVERR rather
                // than silently corrupting untouched bytes or side-effect regs.
                if(wstrb_r!=0 && (wstrb_r!=4'hf || aw_addr_r[1:0]!=0)) bresp_r<=2'b10;
                else if(wstrb_r==4'hf) begin
                    ps_en<=1;ps_we<=1;ps_addr<=aw_addr_r;ps_wdata<=wdata_r;
                end
            end else if(ar_full && !S_AXI_RVALID) begin
                ar_full<=0;ps_en<=1;ps_we<=0;ps_addr<=ar_addr_r;rd_phase<=1;
            end
        end
    end
endmodule
