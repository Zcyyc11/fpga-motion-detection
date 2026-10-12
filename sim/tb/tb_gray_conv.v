`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_gray_conv —— 灰度转换模块自检仿真台
//
// 自检项：
//   1) 三个纯色输入的灰度值与手算一致：
//      白 (255,255,255) → 255；黑 (0,0,0) → 0；
//      纯绿 (0,255,0)   → (150*255)>>8 = 149；
//      纯红 (255,0,0)   → (77*255)>>8  = 76；
//      纯蓝 (0,0,255)   → (29*255)>>8  = 28。
//   2) 流水线延迟恒为 2 拍：in_de 上升后第 2 拍 out_de 才为 1，
//      且 out_x/out_y 与 gray 严格同拍（坐标不错位）。
//   3) de=0 期间输出 de=0。
//
// 运行（Icarus）：iverilog -g2005 -o sim_gray src/rtl/gray_conv.v sim/tb/tb_gray_conv.v && vvp sim_gray
// 运行（Vivado）：python build/scripts/run_sim.py --top tb_gray_conv
// -----------------------------------------------------------------------------
module tb_gray_conv;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg         in_de = 0;
    reg         in_hsync = 0, in_vsync = 0;
    reg  [15:0] in_x = 0, in_y = 0;
    reg  [23:0] in_rgb = 0;

    wire        out_de, out_hsync, out_vsync;
    wire [15:0] out_x, out_y;
    wire [7:0]  out_gray;

    gray_conv dut (
        .clk(clk), .rst_n(rst_n),
        .in_de(in_de), .in_hsync(in_hsync), .in_vsync(in_vsync),
        .in_x(in_x), .in_y(in_y), .in_rgb(in_rgb),
        .out_de(out_de), .out_hsync(out_hsync), .out_vsync(out_vsync),
        .out_x(out_x), .out_y(out_y), .out_gray(out_gray)
    );

    integer errs = 0;
    integer i;

    task check(input integer cond, input [255:0] msg);
        begin
            if (!cond) begin
                errs = errs + 1;
                $display("FAIL: %0s", msg);
            end
        end
    endtask

    // 送一个像素并等 2 拍收输出
    task send_pixel(input [23:0] rgb, input integer exp_gray, input [255:0] name);
        begin
            @(posedge clk);
            in_de <= 1'b1; in_rgb <= rgb; in_x <= in_x + 16'd1;
            @(posedge clk);            // 第 1 拍后：乘加完成
            in_de <= 1'b0;
            @(posedge clk);            // 第 2 拍后：输出有效
            #1;                        // 等 NBA 更新完再采样（避免同沿读旧值）
            check(out_de == 1'b1, "out_de should be 1");
            check(out_gray == exp_gray[7:0], name);
            $display("rgb=%03d_%03d_%03d -> gray=%0d (expect %0d)",
                     rgb[23:16], rgb[15:8], rgb[7:0], out_gray, exp_gray);
        end
    endtask

    initial begin
        #12 rst_n = 1'b1;

        // 每个像素之间隔 2 拍（de=0），顺便验证 de=0 期间输出为 0
        send_pixel(24'hFFFFFF, 255, "white should be 255");
        repeat (2) begin
            @(posedge clk);
            #1;
            check(out_de == 1'b0, "gap: out_de should be 0");
        end
        send_pixel(24'h000000,   0, "black should be 0");
        send_pixel(24'h00FF00, 149, "pure green should be 149");
        send_pixel(24'hFF0000,  76, "pure red should be 76");
        send_pixel(24'h0000FF,  28, "pure blue should be 28");

        // 坐标同拍性：流水线延迟恒 2 拍，out_x 应落后 in_x 恰好 2
        check(out_x == in_x, "out_x should equal the x of the pixel just sent");

        if (errs == 0) $display("=== PASS：gray_conv 仿真全部通过 ===");
        else           $display("=== FAIL：%0d 项未通过 ===", errs);
        $finish;
    end

    initial begin
        #100_000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule
