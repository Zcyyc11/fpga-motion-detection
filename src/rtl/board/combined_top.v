`timescale 1ns/1ps
module combined_top(
 input wire sys_clk,
 input wire hdmi_rx_clk_p,hdmi_rx_clk_n,
 input wire [2:0] hdmi_rx_d_p,hdmi_rx_d_n,
 output wire hdmi_rx_hpd,
 inout wire hdmi_rx_scl,hdmi_rx_sda,
 input wire [3:0] btn,
 input wire [1:0] sw,
 output wire [3:0] led,
 output wire led4_r,led4_g,led4_b,led5_r,led5_g,led5_b,
 output wire buzzer,
 output wire hdmi_tx_clk_p,hdmi_tx_clk_n,
 output wire [2:0] hdmi_tx_d_p,hdmi_tx_d_n,
 output wire [6:0] attach_seg,
 output wire [8:0] attach_digit,
 output wire attach_ws2812_din,
 output wire attach_lcd_sck,attach_lcd_mosi,attach_lcd_cs_n,attach_lcd_dc,attach_lcd_rst_n,attach_lcd_bkl,
 output wire attach_touch_scl,attach_touch_sda
);
  reg [3:0] rst_cnt=0; wire mmcm_rst=(rst_cnt!=4'hf);
  always @(posedge sys_clk) if(mmcm_rst) rst_cnt<=rst_cnt+1'b1;
  wire clk_pix,locked,clk_200m,locked_200;
  clock_200m u_clk200(.clk_125m(sys_clk),.mmcm_rst(mmcm_rst),.clk_200m(clk_200m),.locked(locked_200));
  wire pLocked;
  assign locked=pLocked;
  wire vid_pVDE,vid_pHSync,vid_pVSync;
  wire [23:0] vid_pData;
  wire ddc_sda_i,ddc_sda_o,ddc_sda_t,ddc_scl_i,ddc_scl_o,ddc_scl_t;
  // Loss of lock asserts reset even if the recovered pixel clock stops.
  // Release is delayed by 1023 recovered pixel clocks.
  reg [9:0] por=0;
  always @(posedge clk_pix or negedge pLocked)
    if(!pLocked) por<=0; else if(por!=10'h3ff) por<=por+1'b1;
  wire rst_n=pLocked && (por==10'h3ff);
    // HDMI 输入解码（J10 → dvi2rgb）
    // dvi2rgb_0 是 Digilent 官方开源 IP（与 rgb2dvi_0 同一套 vivado-library），
    // 配置：kClkRange=3（<80MHz/720p）、EDID=dgl_720p_cea.data（720p 首选时序）、
    // kEmulateDDC=true（电脑才读得到 EDID）、kAddBUFG=true（PixelClk 全局化）、
    // kDebug=false（不例化调试 ILA）。参数出处见 create_dvi2rgb.tcl。
    //
    // 按 Digilent dvi2rgb 接口要求，在 200 MHz 参考时钟未锁定时置位 aRst。
    // 200M 未锁 → 保持复位；锁定后自动开始恢复。不依赖 pLocked，无死锁。
    // pRst（同步复位）不用，接 0 —— 锁定过程自行开始。
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
        .PixelClk    (clk_pix),
        .pLocked     (pLocked),
        .SDA_I       (ddc_sda_i),
        .SDA_O       (ddc_sda_o),
        .SDA_T       (ddc_sda_t),
        .SCL_I       (ddc_scl_i),
        .SCL_O       (ddc_scl_o),
        .SCL_T       (ddc_scl_t),
        .pRst        (1'b0)
    );

    // DDC：inout 引脚用 IOBUF 三态缓冲（Digilent 参考设计标准接法）
    IOBUF u_ddc_scl (.IO(hdmi_rx_scl), .I(ddc_scl_o), .O(ddc_scl_i), .T(ddc_scl_t));
    IOBUF u_ddc_sda (.IO(hdmi_rx_sda), .I(ddc_sda_o), .O(ddc_sda_i), .T(ddc_sda_t));

    // HPD 拉高：告诉信源"显示器已连接"，信源才会读 EDID 并输出 720p
    assign hdmi_rx_hpd = 1'b1;

    // 输入整理 + 灰度（PixelClk 域）
    // hdmi_in_ctrl：补 x/y 坐标、sof 帧首、无信号黑屏兜底（拔线不花屏）。
    // gray_conv：RBG 24bit → 8bit 灰度（BT.601，77/150/29），进流水线同一入口。
    wire        in_de, in_hs, in_vs, in_sof;
    wire [15:0] in_x, in_y;
    wire [23:0] in_pix;

    hdmi_in_ctrl u_in_ctrl (
        .clk     (clk_pix),
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
        .clk   (clk_pix),
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

    // gray_conv registers pixels, DE and coordinates by one cycle.
    // Register sync markers by the same amount before entering md_pipeline.
    reg g_hs, g_vs, g_sof;
    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n) begin g_hs<=0; g_vs<=0; g_sof<=0; end
        else begin g_hs<=in_hs; g_vs<=in_vs; g_sof<=in_sof; end
    end

  wire vde,vhs,vvs,b_valid,m_valid,m_bit;
  wire [15:0] vx,vy,b_x1,b_y1,b_x2,b_y2,b_cnt,m_x,m_y,frame_idx;
  wire [7:0] vr,vg,vb;
  wire [7:0] b_obj_count;
  tier1_md_pipeline #(.INPUT_SEL(1),.INCLUDE_PS(0),.MODE_BG(1),.THRESH(100),.SHIFT(6),.BG_FRAC_BITS(4),.BG_FG_SHIFT(10),.FILTER_MODE(1)) u_pipe(.clk(clk_pix),.rst_n(rst_n),.rx_de(g_vde),.rx_hs(g_hs),.rx_vs(g_vs),.rx_sof(g_sof),.rx_x(g_x),.rx_y(g_y),.rx_gray(g_gray),.clk_axi(clk_pix),.rst_n_axi(rst_n),.ps_en(1'b0),.ps_we(1'b0),.ps_addr(6'd0),.ps_wdata(32'd0),.vde(vde),.vx(vx),.vy(vy),.vhs(vhs),.vvs(vvs),.vr(vr),.vg(vg),.vb(vb),.b_x1(b_x1),.b_y1(b_y1),.b_x2(b_x2),.b_y2(b_y2),.b_cnt(b_cnt),.b_valid(b_valid),.b_obj_count(b_obj_count),.m_valid(m_valid),.m_x(m_x),.m_y(m_y),.m_bit(m_bit),.frame_idx(frame_idx));
  rgb2dvi_0 u_dvi(.TMDS_Clk_p(hdmi_tx_clk_p),.TMDS_Clk_n(hdmi_tx_clk_n),.TMDS_Data_p(hdmi_tx_d_p),.TMDS_Data_n(hdmi_tx_d_n),.aRst(~rst_n),.vid_pData({vr,vb,vg}),.vid_pVDE(vde),.vid_pHSync(vhs),.vid_pVSync(vvs),.PixelClk(clk_pix));

  (* ASYNC_REG = "TRUE" *) reg [3:0] btn_meta=0, btn_sync=0;
  (* ASYNC_REG = "TRUE" *) reg dark_meta=0, dark_sync=0;
  always @(posedge clk_pix or negedge rst_n) begin
    if(!rst_n) begin btn_meta<=0;btn_sync<=0;dark_meta<=0;dark_sync<=0; end
    else begin btn_meta<=btn;btn_sync<=btn_meta;dark_meta<=sw[1];dark_sync<=dark_meta; end
  end
  reg [1:0] mode=0; reg [3:0] btn_d=0; reg [19:0] debounce=0;
  always @(posedge clk_pix or negedge rst_n) begin
    if(!rst_n) begin mode<=0; btn_d<=0; debounce<=0; end
    else begin
      btn_d<=btn_sync;
      if(debounce!=0) debounce<=debounce-1'b1;
      else if(btn_sync[0]&&!btn_d[0]) begin mode<=0; debounce<=20'd100000; end
      else if(btn_sync[1]&&!btn_d[1]) begin mode<=1; debounce<=20'd100000; end
      else if(btn_sync[2]&&!btn_d[2]) begin mode<=2; debounce<=20'd100000; end
      else if(btn_sync[3]&&!btn_d[3]) begin mode<=3; debounce<=20'd100000; end
    end
  end
  wire violation_event = b_valid && (b_x1 < 16'd32 || b_x2 > 16'd608);
  wire target_present=b_valid;
  wire [15:0] threshold_cfg = (mode==0)?16'd70:(mode==1)?16'd90:(mode==2)?16'd45:16'd35;
  wire [7:0] threshold_delta; wire night_mode;
  attach_z2_interaction #(.CLK_HZ(74_250_000)) u_attach(
    .clk(clk_pix),.rst_n(rst_n),.target_count(b_obj_count),.threshold(threshold_cfg),.mode(mode),.fps(16'd60),.violation_count(violation_event ? 16'd1 : 16'd0),.target_present(target_present),.violation_event(violation_event),.light_dark(dark_sync),.enc_a(1'b0),.enc_b(1'b0),.enc_push(1'b0),.fiveway(5'b00000),.threshold_delta(threshold_delta),.night_mode(night_mode),.seg(attach_seg),.digit(attach_digit),.ws2812_din(attach_ws2812_din),.lcd_sck(attach_lcd_sck),.lcd_mosi(attach_lcd_mosi),.lcd_cs_n(attach_lcd_cs_n),.lcd_dc(attach_lcd_dc),.lcd_rst_n(attach_lcd_rst_n),.lcd_bkl(attach_lcd_bkl),.buzzer(buzzer),.touch_scl(attach_touch_scl),.touch_sda(attach_touch_sda));

  assign led[0]=locked;
  assign led[1]=target_present;
  assign led[2]=violation_event;
  assign led[3]=mode[0];
  assign led4_r=violation_event; assign led4_g=target_present&&!violation_event; assign led4_b=1'b0;
  assign led5_r=violation_event; assign led5_g=!violation_event&&!target_present; assign led5_b=target_present&&!violation_event;
endmodule
