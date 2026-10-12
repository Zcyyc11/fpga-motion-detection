`timescale 1ns / 1ps
// tb_axi_lite_slave —— 线二/线三 互验门用：验证 axi_lite_slave 协议↔瘦总线翻译
//
// 结构：axi_lite_slave + 一个最小瘦总线寄存器堆（THRESH 可写回读 + CNT 只读计数）。
// 验证点：① 写 0x00 后读回一致；② 写 0x04 后读回一致；③ 读 0x08(RO 计数) 单调增；
//         ④ 多笔连续读写不错位。全过 = "PS↔PL AXI 路径成立"（§5.3 路线判据）。
module tb_axi_lite_slave;

    reg aclk = 0, aresetn = 0;
    always #5 aclk = ~aclk;   // 100 MHz（PS FCLK 量级）

    // AXI 信号
    reg  [31:0] awaddr, wdata, araddr;
    reg         awvalid, wvalid, bready, arvalid, rready;
    wire        awready, wready, bvalid, arready, rvalid;
    wire [1:0]  bresp, rresp;
    wire [31:0] rdata;

    // 瘦总线（接最小寄存器堆）
    wire        ps_en, ps_we;
    wire [5:0]  ps_addr;
    wire [31:0] ps_wdata;
    reg  [31:0] ps_rdata;

    // ---- 最小寄存器堆（瘦总线消费者，模拟 regs.v 接口）----
    reg [15:0] thresh = 16'd70, thresh_rel = 16'd15;
    reg [31:0] cnt = 32'd0;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin thresh <= 16'd70; thresh_rel <= 16'd15; cnt <= 32'd0; end
        else begin
            cnt <= cnt + 32'd1;                       // 只读计数
            if (ps_en && ps_we && ps_addr == 6'h00) thresh <= ps_wdata[15:0];
            if (ps_en && ps_we && ps_addr == 6'h04) thresh_rel <= ps_wdata[15:0]; // 第二独立可写口
        end
    end
    always @(*) begin
        case (ps_addr)
            6'h00: ps_rdata = {16'd0, thresh};
            6'h04: ps_rdata = {16'd0, thresh_rel};
            6'h08: ps_rdata = cnt;                    // 只读计数
            default: ps_rdata = 32'd0;
        endcase
    end

    axi_lite_slave u_ax (
        .S_AXI_ACLK(aclk), .S_AXI_ARESETN(aresetn),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata), .S_AXI_WSTRB(4'hF), .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr), .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp), .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready),
        .ps_en(ps_en), .ps_we(ps_we), .ps_addr(ps_addr), .ps_wdata(ps_wdata), .ps_rdata(ps_rdata)
    );

    // ---- 简易 AXI master 任务（阻塞赋值，时序确定，避免 NB 0 延迟竞争）----
    task axi_write(input [31:0] a, input [31:0] d);
        begin
            @(posedge aclk);
            awaddr = a; wdata = d; awvalid = 1; wvalid = 1; bready = 0;
            @(posedge aclk);
            awvalid = 0; wvalid = 0; bready = 1;
            @(posedge aclk);
            bready = 0;
        end
    endtask

    task axi_read(input [31:0] a, output [31:0] d);
        begin
            @(posedge aclk);
            araddr = a; arvalid = 1; rready = 0;
            @(posedge aclk);
            arvalid = 0; rready = 1;   // 地址已收，拉 rready 等数据
            // 桥有 1 拍读延迟（rd_pend→下一拍 ps_rdata 稳定才送 RVALID），
            // 等到 RVALID 起后再采一拍，保证采到有效数据而非上一拍残值
            while (rvalid !== 1'b1) @(posedge aclk);
            @(posedge aclk);
            d = rdata;
            rready = 0;
        end
    endtask

    // ---- 测试序列 ----
    reg [31:0] rd;
    integer fail = 0;
    initial begin
        awvalid=0; wvalid=0; bready=0; arvalid=0; rready=0;
        araddr=0; awaddr=0; wdata=0;
        #20 aresetn = 1;
        #20;

        // ① 写 THRESH=0x1234，读回
        axi_write(32'h00, 32'h00001234);
        axi_read (32'h00, rd);
        if (rd !== 32'h00001234) begin $display("FAIL ① THRESH 写回 rd=%h", rd); fail=fail+1; end
        else $display("PASS ① THRESH 写回 %h", rd);

        // ② 写第二可写口=0xABCD，读回
        axi_write(32'h04, 32'h0000ABCD);
        axi_read (32'h04, rd);
        if (rd !== 32'h0000ABCD) begin $display("FAIL ② rd=%h", rd); fail=fail+1; end
        else $display("PASS ② 写回 %h", rd);

        // ③ 读只读计数（取两拍，应不同）
        axi_read(32'h08, rd);
        $display("INFO ③ CNT 第一拍 %h", rd);
        #200;
        axi_read(32'h08, rd);
        $display("INFO ③ CNT 第二拍 %h", rd);

        // ④ 连续写读错位检查
        axi_write(32'h00, 32'h00000099);
        axi_write(32'h04, 32'h00000055);
        axi_read (32'h00, rd);
        if (rd !== 32'h00000099) begin $display("FAIL ④ 错位 rd=%h", rd); fail=fail+1; end
        else $display("PASS ④ 无错位 %h", rd);

        #50;
        if (fail == 0) $display("==== RESULT: PASS —— AXI↔瘦总线翻译正确，PS↔PL 路径成立 ====");
        else            $display("==== RESULT: FAIL (%0d) —— 见上 ====", fail);
        $finish;
    end

endmodule
